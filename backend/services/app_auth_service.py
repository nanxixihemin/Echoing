from __future__ import annotations

import hashlib
import hmac
import secrets
from datetime import datetime, timedelta, timezone
from typing import Any, Mapping
from uuid import uuid4

from database import get_connection
from repositories.app_auth_repository import AppAuthRepository
from services.provider_token_verifier import ProviderTokenVerifier, VerifiedIdentity


ACCESS_TOKEN_SECONDS = 30 * 60
REFRESH_TOKEN_SECONDS = 30 * 24 * 60 * 60
SESSION_TOUCH_SECONDS = 5 * 60


class AppAuthError(PermissionError):
    pass


class AppAuthValidationError(ValueError):
    pass


class AppAuthService:
    def __init__(self, verifier: ProviderTokenVerifier | None = None) -> None:
        self.verifier = verifier or ProviderTokenVerifier()

    def exchange(self, payload: Mapping[str, Any]) -> dict[str, Any]:
        provider = self._text(payload.get("provider")).lower()
        credential = self._text(payload.get("credential"))
        device_id = self._validate_device_id(payload.get("deviceId"))
        nonce = self._text(payload.get("nonce"))
        if provider not in {"agc", "huawei"}:
            raise AppAuthValidationError("provider must be agc or huawei")
        if not credential:
            raise AppAuthValidationError("credential is required")
        if provider == "huawei" and not nonce:
            raise AppAuthValidationError("nonce is required for Huawei login")

        identity = self.verifier.verify(provider, credential, nonce)
        user = self._resolve_user(identity)
        return self._create_session_response(user, identity.provider, device_id)

    def refresh(self, payload: Mapping[str, Any]) -> dict[str, Any]:
        refresh_token = self._text(payload.get("refreshToken"))
        device_id = self._validate_device_id(payload.get("deviceId"))
        if not refresh_token:
            raise AppAuthValidationError("refreshToken is required")

        now = self._now()
        now_str = self._format_time(now)
        old_refresh_hash = self._hash_token(refresh_token)
        expected_device_hash = self._hash_token(device_id)
        access_token, new_refresh_token = self._new_token_pair()
        with get_connection() as connection:
            repository = AppAuthRepository(connection)
            session = repository.get_active_session_by_refresh_hash(old_refresh_hash, now_str)
            if session is None or not hmac.compare_digest(
                str(session["device_id_hash"]), expected_device_hash
            ):
                raise AppAuthError("invalid or expired refresh token")
            rotated = repository.rotate_session(
                session_id=str(session["session_id"]),
                old_refresh_token_hash=old_refresh_hash,
                access_token_hash=self._hash_token(access_token),
                refresh_token_hash=self._hash_token(new_refresh_token),
                access_expires_at=self._format_time(now + timedelta(seconds=ACCESS_TOKEN_SECONDS)),
                refresh_expires_at=self._format_time(now + timedelta(seconds=REFRESH_TOKEN_SECONDS)),
                now=now_str,
            )
            if not rotated:
                raise AppAuthError("invalid or expired refresh token")
        return self._session_payload(access_token, new_refresh_token, session)

    def require_user(self, authorization_header: str | None) -> dict[str, Any]:
        token = self._bearer_token(authorization_header)
        now = self._now()
        now_str = self._format_time(now)
        with get_connection() as connection:
            repository = AppAuthRepository(connection)
            session = repository.get_active_session_by_access_hash(self._hash_token(token), now_str)
            if session is None:
                raise AppAuthError("invalid or expired access token")
            repository.touch_session(
                str(session["session_id"]),
                now_str,
                self._format_time(now - timedelta(seconds=SESSION_TOUCH_SECONDS)),
            )
        return {
            "id": str(session["id"]),
            "account_key": str(session["account_key"]),
            "provider": self._text(session.get("provider")),
            "nickname": self._text(session.get("nickname")),
            "bio": self._text(session.get("bio")),
        }

    def logout(self, authorization_header: str | None) -> bool:
        token = self._bearer_token(authorization_header)
        now = self._format_time(self._now())
        with get_connection() as connection:
            return AppAuthRepository(connection).revoke_session_by_access_hash(
                self._hash_token(token), now
            )

    def update_profile(self, app_user: Mapping[str, Any], payload: Mapping[str, Any]) -> dict[str, Any]:
        nickname = self._text(payload.get("nickname"))[:64]
        bio = self._text(payload.get("bio"))[:500]
        now = self._format_time(self._now())
        with get_connection() as connection:
            user = AppAuthRepository(connection).update_profile(str(app_user["id"]), nickname, bio, now)
        return {
            "id": str(user["id"]),
            "provider": self._text(app_user.get("provider")),
            "nickname": str(user["nickname"]),
            "bio": str(user["bio"]),
        }

    def _resolve_user(self, identity: VerifiedIdentity) -> dict[str, Any]:
        now = self._format_time(self._now())
        with get_connection() as connection:
            repository = AppAuthRepository(connection)
            existing = repository.get_identity(identity.provider, identity.provider_user_id)
            if existing is not None:
                if identity.email and identity.email != str(existing.get("email") or ""):
                    repository.update_identity_email(str(existing["identity_id"]), identity.email, now)
                    existing["email"] = identity.email
                return existing

            identity_id = f"identity_{uuid4().hex}"
            user = self._find_verified_legacy_user(repository, identity)
            if user is None:
                user = repository.create_user(
                    user_id=f"app_{uuid4().hex}",
                    account_key=f"trusted_{uuid4().hex}",
                    provider=identity.provider,
                    provider_user_id=identity.provider_user_id,
                    now=now,
                )
            repository.bind_identity(
                identity_id=identity_id,
                app_user_id=str(user["id"]),
                provider=identity.provider,
                provider_user_id=identity.provider_user_id,
                email=identity.email,
                now=now,
            )
            if user.get("legacy_account_key"):
                repository.record_legacy_migration(
                    migration_id=f"migration_{uuid4().hex}",
                    identity_id=identity_id,
                    app_user_id=str(user["id"]),
                    legacy_account_key_hash=self._hash_token(str(user["legacy_account_key"])),
                    now=now,
                )
            resolved = repository.get_identity(identity.provider, identity.provider_user_id)
            if resolved is None:
                raise RuntimeError("Bound app identity cannot be loaded")
            return resolved

    def _find_verified_legacy_user(
        self, repository: AppAuthRepository, identity: VerifiedIdentity
    ) -> dict[str, Any] | None:
        if identity.provider != "agc" or not identity.email_verified or not identity.email:
            return None
        legacy_account_key = f"email_{identity.email.strip().lower()}"
        user = repository.get_user_by_account_key(legacy_account_key)
        if user is None or repository.user_has_identity(str(user["id"])):
            return None
        user["legacy_account_key"] = legacy_account_key
        return user

    def _create_session_response(
        self, user: Mapping[str, Any], provider: str, device_id: str
    ) -> dict[str, Any]:
        now = self._now()
        access_token, refresh_token = self._new_token_pair()
        with get_connection() as connection:
            AppAuthRepository(connection).create_session(
                session_id=f"app_session_{uuid4().hex}",
                app_user_id=str(user["id"]),
                access_token_hash=self._hash_token(access_token),
                refresh_token_hash=self._hash_token(refresh_token),
                access_expires_at=self._format_time(now + timedelta(seconds=ACCESS_TOKEN_SECONDS)),
                refresh_expires_at=self._format_time(now + timedelta(seconds=REFRESH_TOKEN_SECONDS)),
                device_id_hash=self._hash_token(device_id),
                now=self._format_time(now),
            )
        response_user = dict(user)
        response_user["provider"] = provider
        return self._session_payload(access_token, refresh_token, response_user)

    def _session_payload(
        self, access_token: str, refresh_token: str, user: Mapping[str, Any]
    ) -> dict[str, Any]:
        return {
            "accessToken": access_token,
            "accessExpiresIn": ACCESS_TOKEN_SECONDS,
            "refreshToken": refresh_token,
            "refreshExpiresIn": REFRESH_TOKEN_SECONDS,
            "user": self._public_user(user),
        }

    def _public_user(self, user: Mapping[str, Any]) -> dict[str, Any]:
        return {
            "id": str(user["id"]),
            "provider": self._text(user.get("provider")),
            "nickname": self._text(user.get("nickname")),
            "bio": self._text(user.get("bio")),
        }

    def _bearer_token(self, authorization_header: str | None) -> str:
        if not authorization_header or not authorization_header.startswith("Bearer "):
            raise AppAuthError("missing or invalid Authorization header")
        token = authorization_header[len("Bearer ") :].strip()
        if not token:
            raise AppAuthError("missing access token")
        return token

    def _validate_device_id(self, value: Any) -> str:
        device_id = self._text(value)
        if len(device_id) < 16 or len(device_id) > 512:
            raise AppAuthValidationError("deviceId must be between 16 and 512 characters")
        return device_id

    def _new_token_pair(self) -> tuple[str, str]:
        return secrets.token_urlsafe(48), secrets.token_urlsafe(48)

    def _hash_token(self, value: str) -> str:
        return hashlib.sha256(value.encode("utf-8")).hexdigest()

    def _text(self, value: Any) -> str:
        return str(value).strip() if value is not None else ""

    def _now(self) -> datetime:
        return datetime.now(timezone.utc)

    def _format_time(self, value: datetime) -> str:
        return value.strftime("%Y-%m-%d %H:%M:%S")
