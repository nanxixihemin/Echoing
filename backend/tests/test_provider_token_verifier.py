from __future__ import annotations

import os
import sys
import time
import unittest
from pathlib import Path
from types import SimpleNamespace
from typing import Any

import jwt
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa


BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

from services.provider_token_verifier import (
    ProviderConfigurationError,
    ProviderTokenVerifier,
    ProviderUnavailableError,
    ProviderVerificationError,
)


class StaticJwksClient:
    def __init__(self, key: rsa.RSAPublicKey) -> None:
        self.key = key

    def get_signing_key_from_jwt(self, token: str) -> SimpleNamespace:
        return SimpleNamespace(key=self.key)


class RecordingTokenEndpoint:
    """Stands in for Huawei's token endpoint so no network call is made."""

    def __init__(self, payload: dict[str, Any] | None = None, error: Exception | None = None) -> None:
        self.payload = payload if payload is not None else {}
        self.error = error
        self.calls: list[tuple[str, dict[str, str]]] = []

    def __call__(self, url: str, form: dict[str, str]) -> dict[str, Any]:
        self.calls.append((url, dict(form)))
        if self.error is not None:
            raise self.error
        return self.payload


class ProviderTokenVerifierTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.private_key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        cls.public_key = cls.private_key.public_key()

    def test_agc_verifies_signature_issuer_audience_and_expiry(self) -> None:
        os.environ["AGC_PROJECT_ID"] = "project-123"
        verifier = ProviderTokenVerifier()
        verifier._agc_keys = {
            "kid-1": self.public_key.public_bytes(
                serialization.Encoding.PEM,
                serialization.PublicFormat.SubjectPublicKeyInfo,
            ).decode("ascii")
        }
        verifier._agc_keys_loaded_at = time.monotonic()
        now = int(time.time())
        token = jwt.encode(
            {
                "sub": "agc-user",
                "aud": "project-123",
                "iss": "https://agc.developer.huawei.com/project-123",
                "iat": now,
                "exp": now + 300,
                "email": "USER@example.com",
                "email_verified": True,
            },
            self.private_key,
            algorithm="PS256",
            headers={"kid": "kid-1", "typ": "JWT"},
        )
        identity = verifier.verify_agc(token)
        self.assertEqual("agc-user", identity.provider_user_id)
        self.assertEqual("user@example.com", identity.email)
        self.assertTrue(identity.email_verified)

        forged = jwt.encode(
            {
                "sub": "agc-user",
                "aud": "wrong-project",
                "iss": "https://agc.developer.huawei.com/project-123",
                "iat": now,
                "exp": now + 300,
            },
            self.private_key,
            algorithm="PS256",
            headers={"kid": "kid-1"},
        )
        with self.assertRaises(ProviderVerificationError):
            verifier.verify_agc(forged)

    def _huawei_verifier(self, token_endpoint: RecordingTokenEndpoint) -> ProviderTokenVerifier:
        os.environ["HUAWEI_ACCOUNT_CLIENT_ID"] = "client-123"
        os.environ["HUAWEI_ACCOUNT_CLIENT_SECRET"] = "secret-456"
        os.environ.pop("HUAWEI_ACCOUNT_REDIRECT_URI", None)
        verifier = ProviderTokenVerifier()
        verifier._huawei_discovery = {
            "issuer": "https://accounts.huawei.com",
            "jwks_uri": "https://oauth-login.cloud.huawei.com/oauth2/v3/certs",
            "token_endpoint": "https://oauth-login.cloud.huawei.com/oauth2/v3/token",
            "id_token_signing_alg_values_supported": ["RS256", "PS256"],
        }
        verifier._huawei_jwks_client = StaticJwksClient(self.public_key)
        verifier._post_form = token_endpoint  # type: ignore[method-assign]
        return verifier

    def _huawei_id_token(self, **overrides: Any) -> str:
        now = int(time.time())
        claims: dict[str, Any] = {
            "sub": "huawei-user",
            "aud": "client-123",
            "azp": "client-123",
            "iss": "https://accounts.huawei.com",
            "iat": now,
            "exp": now + 300,
            "nonce": "nonce-123",
        }
        claims.update(overrides)
        return jwt.encode(
            claims, self.private_key, algorithm="PS256", headers={"kid": "kid-1"}
        )

    def test_huawei_redeems_authorization_code_then_verifies_claims(self) -> None:
        endpoint = RecordingTokenEndpoint({"id_token": self._huawei_id_token()})
        verifier = self._huawei_verifier(endpoint)

        identity = verifier.verify_huawei("auth-code-abc", "nonce-123")

        self.assertEqual("huawei-user", identity.provider_user_id)
        self.assertEqual("huawei", identity.provider)
        self.assertEqual(1, len(endpoint.calls))
        url, form = endpoint.calls[0]
        self.assertEqual("https://oauth-login.cloud.huawei.com/oauth2/v3/token", url)
        self.assertEqual("authorization_code", form["grant_type"])
        self.assertEqual("auth-code-abc", form["code"])
        self.assertEqual("client-123", form["client_id"])
        self.assertEqual("secret-456", form["client_secret"])
        self.assertNotIn("redirect_uri", form)

    def test_huawei_rejects_nonce_mismatch_from_redeemed_token(self) -> None:
        endpoint = RecordingTokenEndpoint({"id_token": self._huawei_id_token()})
        verifier = self._huawei_verifier(endpoint)
        with self.assertRaises(ProviderVerificationError):
            verifier.verify_huawei("auth-code-abc", "forged-nonce")

    def test_huawei_rejects_wrong_audience_from_redeemed_token(self) -> None:
        endpoint = RecordingTokenEndpoint(
            {"id_token": self._huawei_id_token(aud="other-client", azp="other-client")}
        )
        verifier = self._huawei_verifier(endpoint)
        with self.assertRaises(ProviderVerificationError):
            verifier.verify_huawei("auth-code-abc", "nonce-123")

    def test_huawei_rejects_token_endpoint_without_id_token(self) -> None:
        endpoint = RecordingTokenEndpoint({"access_token": "opaque-only"})
        verifier = self._huawei_verifier(endpoint)
        with self.assertRaises(ProviderVerificationError):
            verifier.verify_huawei("auth-code-abc", "nonce-123")

    def test_huawei_rejects_empty_code_without_contacting_provider(self) -> None:
        endpoint = RecordingTokenEndpoint({"id_token": self._huawei_id_token()})
        verifier = self._huawei_verifier(endpoint)
        with self.assertRaises(ProviderVerificationError):
            verifier.verify_huawei("", "nonce-123")
        with self.assertRaises(ProviderVerificationError):
            verifier.verify_huawei("auth-code-abc", "")
        self.assertEqual([], endpoint.calls)

    def test_huawei_propagates_provider_outage(self) -> None:
        endpoint = RecordingTokenEndpoint(
            error=ProviderUnavailableError("provider verification service is unavailable")
        )
        verifier = self._huawei_verifier(endpoint)
        with self.assertRaises(ProviderUnavailableError):
            verifier.verify_huawei("auth-code-abc", "nonce-123")

    def test_huawei_requires_client_secret(self) -> None:
        endpoint = RecordingTokenEndpoint({"id_token": self._huawei_id_token()})
        verifier = self._huawei_verifier(endpoint)
        os.environ["HUAWEI_ACCOUNT_CLIENT_SECRET"] = ""
        try:
            with self.assertRaises(ProviderConfigurationError):
                verifier.verify_huawei("auth-code-abc", "nonce-123")
        finally:
            os.environ["HUAWEI_ACCOUNT_CLIENT_SECRET"] = "secret-456"
        self.assertEqual([], endpoint.calls)

    def test_huawei_sends_redirect_uri_when_configured(self) -> None:
        endpoint = RecordingTokenEndpoint({"id_token": self._huawei_id_token()})
        verifier = self._huawei_verifier(endpoint)
        os.environ["HUAWEI_ACCOUNT_REDIRECT_URI"] = "https://echoing.example/callback"
        try:
            verifier.verify_huawei("auth-code-abc", "nonce-123")
        finally:
            os.environ.pop("HUAWEI_ACCOUNT_REDIRECT_URI", None)
        self.assertEqual("https://echoing.example/callback", endpoint.calls[0][1]["redirect_uri"])


if __name__ == "__main__":
    unittest.main()
