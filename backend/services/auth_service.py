from __future__ import annotations

import hashlib
import hmac
import os
import secrets
from datetime import datetime, timedelta, timezone
from typing import Any
from uuid import uuid4

from database import get_connection
from repositories.auth_repository import AuthRepository


PBKDF2_ITERATIONS = 200_000


class AuthError(PermissionError):
    pass


class AuthService:
    def bootstrap_admin_from_env(self) -> None:
        username = os.environ.get("ADMIN_USERNAME", "").strip()
        password = os.environ.get("ADMIN_PASSWORD", "")
        if not username or not password:
            print("Admin user bootstrap skipped: set ADMIN_USERNAME and ADMIN_PASSWORD in backend/.env")
            return

        now = self._format_time(self._now())
        with get_connection() as connection:
            repository = AuthRepository(connection)
            if repository.count_users() > 0:
                return
            salt = secrets.token_hex(16)
            repository.create_user(
                user_id=f"admin_{uuid4().hex}",
                username=username,
                password_hash=self._hash_password(password, salt),
                salt=salt,
                role="admin",
                created_at=now,
            )
        print(f"Created admin user from env: {username}")

    def login(self, username: str, password: str) -> dict[str, Any]:
        if not username or not password:
            raise AuthError("username and password are required")

        now = self._now()
        now_str = self._format_time(now)
        ttl_hours = int(os.environ.get("AUTH_TOKEN_TTL_HOURS", "24"))
        expires_at = self._format_time(now + timedelta(hours=ttl_hours))
        token = secrets.token_urlsafe(32)
        token_hash = self._hash_token(token)

        with get_connection() as connection:
            repository = AuthRepository(connection)
            user = repository.get_user_by_username(username)
            if user is None:
                raise AuthError("invalid username or password")
            expected = self._hash_password(password, str(user["salt"]))
            if not hmac.compare_digest(expected, str(user["password_hash"])):
                raise AuthError("invalid username or password")
            repository.create_session(token_hash, str(user["id"]), expires_at, now_str)
            repository.update_last_login(str(user["id"]), now_str)

        return {
            "token": token,
            "expires_at": expires_at,
            "user": {
                "id": str(user["id"]),
                "username": str(user["username"]),
                "role": str(user["role"]),
            },
        }

    def require_user(self, authorization_header: str | None) -> dict[str, Any]:
        if not authorization_header:
            raise AuthError("missing Authorization header")
        prefix = "Bearer "
        if not authorization_header.startswith(prefix):
            raise AuthError("Authorization must be a Bearer token")
        token = authorization_header[len(prefix) :].strip()
        if not token:
            raise AuthError("missing token")

        with get_connection() as connection:
            repository = AuthRepository(connection)
            session = repository.get_session(self._hash_token(token), self._format_time(self._now()))
            if session is None:
                raise AuthError("invalid or expired token")

        return {
            "id": str(session["user_id"]),
            "username": str(session["username"]),
            "role": str(session["role"]),
        }

    def logout(self, authorization_header: str | None) -> bool:
        if not authorization_header or not authorization_header.startswith("Bearer "):
            return False
        token = authorization_header[len("Bearer ") :].strip()
        if not token:
            return False
        with get_connection() as connection:
            repository = AuthRepository(connection)
            return repository.revoke_session(self._hash_token(token), self._format_time(self._now()))

    def _hash_password(self, password: str, salt: str) -> str:
        digest = hashlib.pbkdf2_hmac(
            "sha256",
            password.encode("utf-8"),
            salt.encode("utf-8"),
            PBKDF2_ITERATIONS,
        )
        return digest.hex()

    def _hash_token(self, token: str) -> str:
        return hashlib.sha256(token.encode("utf-8")).hexdigest()

    def _now(self) -> datetime:
        return datetime.now(timezone.utc)

    def _format_time(self, value: datetime) -> str:
        return value.strftime("%Y-%m-%d %H:%M:%S")
