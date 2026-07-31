from __future__ import annotations

import contextlib
import hashlib
import io
import json
import os
import sqlite3
import sys
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone
from http.server import ThreadingHTTPServer
from pathlib import Path
from typing import Any


BACKEND_ROOT = Path(__file__).resolve().parents[1]
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

import database
import server
from services.app_auth_service import AppAuthService
from services.auth_service import AuthService
from services.provider_token_verifier import VerifiedIdentity
from services.rate_limit_service import RateLimitService


DEVICE_ID = "test-device-id-0000000000000001"


class FakeProviderVerifier:
    def verify(self, provider: str, credential: str, nonce: str = "") -> VerifiedIdentity:
        if credential not in {"user-a", "user-b", "legacy-user"}:
            raise server.ProviderVerificationError("credential verification failed")
        email = "legacy@example.com" if credential == "legacy-user" else ""
        return VerifiedIdentity(
            provider=provider,
            provider_user_id=credential,
            email=email,
            email_verified=bool(email),
        )


class EchoingHttpTestCase(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        database.DB_PATH = Path(self.temp_dir.name) / "echoing-test.db"
        os.environ["ADMIN_USERNAME"] = "test-admin"
        os.environ["ADMIN_PASSWORD"] = "test-admin-password"
        database.init_database()
        server.auth_service = AuthService()
        server.auth_service.bootstrap_admin_from_env()
        server.app_auth_service = AppAuthService(FakeProviderVerifier())
        server.rate_limit_service = RateLimitService()
        self.httpd = ThreadingHTTPServer(("127.0.0.1", 0), server.ProxyHandler)
        self.thread = threading.Thread(target=self.httpd.serve_forever, daemon=True)
        self.thread.start()
        self.base_url = f"http://127.0.0.1:{self.httpd.server_address[1]}"

    def tearDown(self) -> None:
        self.httpd.shutdown()
        self.httpd.server_close()
        self.thread.join(timeout=5)
        self.temp_dir.cleanup()

    def request(
        self,
        method: str,
        path: str,
        body: dict[str, Any] | None = None,
        token: str = "",
        headers: dict[str, str] | None = None,
    ) -> tuple[int, dict[str, Any]]:
        request_headers = {"Content-Type": "application/json"}
        if token:
            request_headers["Authorization"] = f"Bearer {token}"
        if headers:
            request_headers.update(headers)
        data = json.dumps(body).encode("utf-8") if body is not None else None
        request = urllib.request.Request(
            f"{self.base_url}{path}", data=data, method=method, headers=request_headers
        )
        try:
            with urllib.request.urlopen(request, timeout=5) as response:
                raw = response.read().decode("utf-8")
                return response.status, json.loads(raw) if raw else {}
        except urllib.error.HTTPError as exc:
            raw = exc.read().decode("utf-8")
            return exc.code, json.loads(raw) if raw else {}

    def exchange(self, credential: str = "user-a") -> dict[str, Any]:
        status, payload = self.request(
            "POST",
            "/api/app-auth/exchange",
            {"provider": "agc", "credential": credential, "deviceId": DEVICE_ID},
        )
        self.assertEqual(200, status)
        return payload

    def test_private_endpoints_reject_missing_and_random_tokens(self) -> None:
        for token in ("", "random-forged-token"):
            status, payload = self.request("GET", "/api/sessions", token=token)
            self.assertEqual(401, status)
            self.assertEqual("unauthorized", payload["error"])

    def test_expired_and_revoked_access_tokens_are_rejected(self) -> None:
        session = self.exchange()
        access_token = str(session["accessToken"])
        token_hash = hashlib.sha256(access_token.encode("utf-8")).hexdigest()
        with database.get_connection() as connection:
            connection.execute(
                "UPDATE app_auth_sessions SET access_expires_at = ? WHERE access_token_hash = ?",
                ("2000-01-01 00:00:00", token_hash),
            )
        self.assertEqual(401, self.request("GET", "/api/app-auth/me", token=access_token)[0])

        second_session = self.exchange()
        second_token = str(second_session["accessToken"])
        self.assertEqual(200, self.request("POST", "/api/app-auth/logout", {}, second_token)[0])
        self.assertEqual(401, self.request("GET", "/api/app-auth/me", token=second_token)[0])

    def test_refresh_rotates_tokens_and_rejects_reuse(self) -> None:
        session = self.exchange()
        old_refresh = str(session["refreshToken"])
        status, refreshed = self.request(
            "POST",
            "/api/app-auth/refresh",
            {"refreshToken": old_refresh, "deviceId": DEVICE_ID},
        )
        self.assertEqual(200, status)
        self.assertNotEqual(session["accessToken"], refreshed["accessToken"])
        self.assertNotEqual(old_refresh, refreshed["refreshToken"])
        self.assertEqual(
            401,
            self.request(
                "POST",
                "/api/app-auth/refresh",
                {"refreshToken": old_refresh, "deviceId": DEVICE_ID},
            )[0],
        )
        self.assertEqual(401, self.request("GET", "/api/app-auth/me", token=session["accessToken"])[0])
        self.assertEqual(200, self.request("GET", "/api/app-auth/me", token=refreshed["accessToken"])[0])

    def test_user_cannot_read_or_overwrite_another_users_session(self) -> None:
        user_a = self.exchange("user-a")
        user_b = self.exchange("user-b")
        session_body = {
            "id": "shared-session-id",
            "theme": "private-b",
            "summary": "secret-b",
            "messages": [{"role": "user", "content": "private"}],
            "createdAt": 1,
            "updatedAt": 1,
        }
        self.assertEqual(
            200,
            self.request("POST", "/api/sessions", session_body, user_b["accessToken"])[0],
        )
        status, listing = self.request(
            "GET",
            "/api/sessions?accountKey=user-b&userId=user-b",
            token=user_a["accessToken"],
            headers={"X-Account-Key": "user-b", "X-User-Id": "user-b"},
        )
        self.assertEqual(200, status)
        self.assertEqual([], listing["items"])
        self.assertEqual(
            404,
            self.request("GET", "/api/sessions/shared-session-id", token=user_a["accessToken"])[0],
        )
        forged_body = dict(session_body)
        forged_body["userId"] = user_b["user"]["id"]
        forged_body["accountKey"] = "user-b"
        self.assertEqual(
            404,
            self.request("POST", "/api/sessions", forged_body, user_a["accessToken"])[0],
        )

    def test_public_and_protected_endpoint_compatibility(self) -> None:
        status, health = self.request("GET", "/health")
        self.assertEqual(200, status)
        self.assertEqual({"ok": True}, health)
        self.assertEqual(200, self.request("GET", "/api/leaves")[0])
        self.assertEqual(401, self.request("POST", "/api/leaves", {"content": "hello"})[0])
        self.assertEqual(
            401,
            self.request(
                "POST", "/v1/chat/completions", {"messages": [{"role": "user", "content": "hello"}]}
            )[0],
        )

    def test_admin_and_app_tokens_cannot_cross_roles(self) -> None:
        app_session = self.exchange()
        status, admin_session = self.request(
            "POST",
            "/api/auth/login",
            {"username": "test-admin", "password": "test-admin-password"},
        )
        self.assertEqual(200, status)
        self.assertEqual(200, self.request("GET", "/api/admin/leaves", token=admin_session["token"])[0])
        self.assertEqual(401, self.request("GET", "/api/admin/leaves", token=app_session["accessToken"])[0])
        self.assertEqual(401, self.request("GET", "/api/sessions", token=admin_session["token"])[0])

    def test_tokens_are_hashed_and_not_logged(self) -> None:
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            session = self.exchange()
            self.request("GET", "/api/app-auth/me", token=session["accessToken"])
        logs = output.getvalue()
        self.assertNotIn(session["accessToken"], logs)
        self.assertNotIn(session["refreshToken"], logs)
        with contextlib.closing(sqlite3.connect(database.DB_PATH)) as connection:
            row = connection.execute(
                "SELECT access_token_hash, refresh_token_hash FROM app_auth_sessions LIMIT 1"
            ).fetchone()
        self.assertIsNotNone(row)
        self.assertNotEqual(session["accessToken"], row[0])
        self.assertNotEqual(session["refreshToken"], row[1])

    def test_verified_email_migrates_legacy_user_once(self) -> None:
        now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
        with database.get_connection() as connection:
            connection.execute(
                """
                INSERT INTO app_users(
                  id, account_key, provider, external_id, nickname, bio,
                  created_at, updated_at, last_seen_at
                ) VALUES ('legacy-id', 'email_legacy@example.com', '', '', 'Legacy', '', ?, ?, ?)
                """,
                (now, now, now),
            )
        first = self.exchange("legacy-user")
        second = self.exchange("legacy-user")
        self.assertEqual("legacy-id", first["user"]["id"])
        self.assertEqual(first["user"]["id"], second["user"]["id"])
        with database.get_connection() as connection:
            migration_count = connection.execute(
                "SELECT COUNT(*) FROM app_identity_migrations"
            ).fetchone()[0]
        self.assertEqual(1, migration_count)

    def test_migration_is_idempotent(self) -> None:
        database.init_database()
        database.init_database()
        with database.get_connection() as connection:
            versions = connection.execute(
                "SELECT version, COUNT(*) FROM schema_migrations GROUP BY version"
            ).fetchall()
            tables = {
                row[0]
                for row in connection.execute(
                    "SELECT name FROM sqlite_master WHERE type = 'table'"
                ).fetchall()
            }
        self.assertTrue(all(count == 1 for _, count in versions))
        self.assertIn("app_identities", tables)
        self.assertIn("app_auth_sessions", tables)


if __name__ == "__main__":
    unittest.main()
