from __future__ import annotations

import hmac
import json
import os
import threading
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from typing import Any
from urllib.parse import urlparse

import jwt
from cryptography.hazmat.primitives import serialization


AGC_DEFAULT_PUBLIC_KEYS_URL = "https://developer.huawei.com/consumer/cn/service/josp/agc/auth/keys"
HUAWEI_DEFAULT_DISCOVERY_URL = "https://oauth-login.cloud.huawei.com/.well-known/openid-configuration"
ALLOWED_SIGNING_ALGORITHMS = {"RS256", "PS256"}


class ProviderVerificationError(PermissionError):
    pass


class ProviderConfigurationError(RuntimeError):
    pass


class ProviderUnavailableError(RuntimeError):
    pass


@dataclass(frozen=True)
class VerifiedIdentity:
    provider: str
    provider_user_id: str
    email: str = ""
    email_verified: bool = False
    display_name: str = ""


class ProviderTokenVerifier:
    def __init__(self) -> None:
        self._agc_keys: dict[str, str] = {}
        self._agc_keys_loaded_at = 0.0
        self._agc_lock = threading.Lock()
        self._huawei_jwks_client: jwt.PyJWKClient | None = None
        self._huawei_discovery: dict[str, Any] | None = None
        self._huawei_lock = threading.Lock()

    def verify(self, provider: str, credential: str, nonce: str = "") -> VerifiedIdentity:
        normalized_provider = provider.strip().lower()
        if normalized_provider == "agc":
            return self.verify_agc(credential)
        if normalized_provider == "huawei":
            return self.verify_huawei(credential, nonce)
        raise ProviderVerificationError("unsupported identity provider")

    def verify_agc(self, access_token: str) -> VerifiedIdentity:
        project_id = os.environ.get("AGC_PROJECT_ID", "").strip()
        if not project_id:
            raise ProviderConfigurationError("AGC server verification is not configured")
        if not access_token or len(access_token) > 16384:
            raise ProviderVerificationError("invalid AGC credential")

        try:
            header = jwt.get_unverified_header(access_token)
        except jwt.PyJWTError as exc:
            raise ProviderVerificationError("invalid AGC credential") from exc
        algorithm = str(header.get("alg") or "")
        key_id = str(header.get("kid") or "")
        if algorithm not in ALLOWED_SIGNING_ALGORITHMS or not key_id:
            raise ProviderVerificationError("unsupported AGC token signature")

        key = self._get_agc_public_key(key_id)
        issuer = os.environ.get(
            "AGC_TOKEN_ISSUER",
            f"https://agc.developer.huawei.com/{project_id}",
        ).strip()
        try:
            claims = jwt.decode(
                access_token,
                key=key,
                algorithms=[algorithm],
                audience=project_id,
                issuer=issuer,
                options={"require": ["sub", "aud", "iss", "exp", "iat"]},
                leeway=self._clock_skew_seconds(),
            )
        except jwt.InvalidSignatureError as exc:
            self._refresh_agc_keys()
            try:
                claims = jwt.decode(
                    access_token,
                    key=self._get_agc_public_key(key_id),
                    algorithms=[algorithm],
                    audience=project_id,
                    issuer=issuer,
                    options={"require": ["sub", "aud", "iss", "exp", "iat"]},
                    leeway=self._clock_skew_seconds(),
                )
            except jwt.PyJWTError as retry_exc:
                raise ProviderVerificationError("AGC credential verification failed") from retry_exc
        except jwt.PyJWTError as exc:
            raise ProviderVerificationError("AGC credential verification failed") from exc

        subject = str(claims.get("sub") or "").strip().strip('"')
        if not subject:
            raise ProviderVerificationError("AGC credential is missing a subject")
        return VerifiedIdentity(
            provider="agc",
            provider_user_id=subject,
            email=str(claims.get("email") or "").strip().lower(),
            email_verified=claims.get("email_verified") is True,
            display_name=str(claims.get("name") or "").strip(),
        )

    def verify_huawei(self, id_token: str, nonce: str) -> VerifiedIdentity:
        client_id = os.environ.get("HUAWEI_ACCOUNT_CLIENT_ID", "").strip()
        if not client_id:
            raise ProviderConfigurationError("Huawei Account server verification is not configured")
        if not id_token or len(id_token) > 16384 or not nonce:
            raise ProviderVerificationError("invalid Huawei credential")

        discovery, jwks_client = self._get_huawei_configuration()
        try:
            header = jwt.get_unverified_header(id_token)
        except jwt.PyJWTError as exc:
            raise ProviderVerificationError("invalid Huawei credential") from exc
        algorithm = str(header.get("alg") or "")
        supported = set(discovery.get("id_token_signing_alg_values_supported") or [])
        if algorithm not in ALLOWED_SIGNING_ALGORITHMS or algorithm not in supported:
            raise ProviderVerificationError("unsupported Huawei token signature")

        try:
            signing_key = jwks_client.get_signing_key_from_jwt(id_token)
            claims = jwt.decode(
                id_token,
                key=signing_key.key,
                algorithms=[algorithm],
                audience=client_id,
                issuer=str(discovery["issuer"]),
                options={"require": ["sub", "aud", "iss", "exp", "iat", "nonce"]},
                leeway=self._clock_skew_seconds(),
            )
        except jwt.PyJWKClientConnectionError as exc:
            raise ProviderUnavailableError("Huawei verification service is unavailable") from exc
        except (jwt.PyJWTError, KeyError) as exc:
            raise ProviderVerificationError("Huawei credential verification failed") from exc

        token_nonce = str(claims.get("nonce") or "")
        if not hmac.compare_digest(token_nonce, nonce):
            raise ProviderVerificationError("Huawei credential nonce mismatch")
        authorized_party = str(claims.get("azp") or "")
        if authorized_party and not hmac.compare_digest(authorized_party, client_id):
            raise ProviderVerificationError("Huawei credential authorized party mismatch")
        subject = str(claims.get("sub") or "").strip()
        if not subject:
            raise ProviderVerificationError("Huawei credential is missing a subject")
        return VerifiedIdentity(
            provider="huawei",
            provider_user_id=subject,
            email=str(claims.get("email") or "").strip().lower(),
            email_verified=claims.get("email_verified") is True,
            display_name=str(claims.get("name") or claims.get("display_name") or "").strip(),
        )

    def _get_agc_public_key(self, key_id: str) -> Any:
        if time.monotonic() - self._agc_keys_loaded_at > 3600 or key_id not in self._agc_keys:
            self._refresh_agc_keys()
        encoded = self._agc_keys.get(key_id)
        if not encoded:
            raise ProviderVerificationError("AGC signing key is unavailable")
        public_key_pem = encoded.replace("BEGIN CERTIFICATE", "BEGIN PUBLIC KEY").replace(
            "END CERTIFICATE", "END PUBLIC KEY"
        )
        try:
            return serialization.load_pem_public_key(public_key_pem.encode("ascii"))
        except (ValueError, TypeError) as exc:
            raise ProviderVerificationError("AGC signing key is invalid") from exc

    def _refresh_agc_keys(self) -> None:
        with self._agc_lock:
            url = os.environ.get("AGC_PUBLIC_KEYS_URL", AGC_DEFAULT_PUBLIC_KEYS_URL).strip()
            payload = self._fetch_json(url)
            if not payload or not all(isinstance(key, str) and isinstance(value, str) for key, value in payload.items()):
                raise ProviderVerificationError("AGC signing keys response is invalid")
            self._agc_keys = {str(key): str(value) for key, value in payload.items()}
            self._agc_keys_loaded_at = time.monotonic()

    def _get_huawei_configuration(self) -> tuple[dict[str, Any], jwt.PyJWKClient]:
        with self._huawei_lock:
            if self._huawei_discovery is not None and self._huawei_jwks_client is not None:
                return self._huawei_discovery, self._huawei_jwks_client
            discovery_url = os.environ.get(
                "HUAWEI_OIDC_DISCOVERY_URL", HUAWEI_DEFAULT_DISCOVERY_URL
            ).strip()
            discovery = self._fetch_json(discovery_url)
            issuer = str(discovery.get("issuer") or "")
            jwks_uri = str(discovery.get("jwks_uri") or "")
            expected_issuer = os.environ.get("HUAWEI_OIDC_ISSUER", issuer).strip()
            if issuer != expected_issuer or not self._is_https_url(jwks_uri):
                raise ProviderConfigurationError("Huawei OIDC discovery response is invalid")
            self._huawei_discovery = discovery
            self._huawei_jwks_client = jwt.PyJWKClient(
                jwks_uri,
                cache_jwk_set=True,
                lifespan=3600,
                timeout=self._http_timeout_seconds(),
            )
            return discovery, self._huawei_jwks_client

    def _fetch_json(self, url: str) -> dict[str, Any]:
        if not self._is_https_url(url):
            raise ProviderConfigurationError("provider verification URLs must use HTTPS")
        request = urllib.request.Request(url, headers={"Accept": "application/json"})
        try:
            with urllib.request.urlopen(request, timeout=self._http_timeout_seconds()) as response:
                raw = response.read(1024 * 1024)
            parsed = json.loads(raw.decode("utf-8"))
        except (OSError, urllib.error.URLError) as exc:
            raise ProviderUnavailableError("provider verification service is unavailable") from exc
        except json.JSONDecodeError as exc:
            raise ProviderUnavailableError("provider verification response is invalid") from exc
        if not isinstance(parsed, dict):
            raise ProviderUnavailableError("provider verification response is invalid")
        return parsed

    def _clock_skew_seconds(self) -> int:
        return max(0, min(int(os.environ.get("PROVIDER_TOKEN_CLOCK_SKEW_SECONDS", "60")), 300))

    def _http_timeout_seconds(self) -> float:
        return max(1.0, min(float(os.environ.get("PROVIDER_VERIFY_TIMEOUT_SECONDS", "5")), 15.0))

    def _is_https_url(self, url: str) -> bool:
        parsed = urlparse(url)
        return parsed.scheme == "https" and bool(parsed.netloc)
