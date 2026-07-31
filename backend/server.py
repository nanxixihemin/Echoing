from __future__ import annotations

import json
import os
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, urlparse


ROOT = Path(__file__).resolve().parent


def load_dotenv() -> None:
    env_path = ROOT / ".env"
    if not env_path.exists():
        return

    for line in env_path.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or "=" not in stripped:
            continue
        key, value = stripped.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))


load_dotenv()

API_KEY = os.environ.get("MODELSCOPE_API_KEY", "")
API_BASE = os.environ.get("MODELSCOPE_API_BASE", "https://api-inference.modelscope.cn/v1").rstrip("/")
DEFAULT_MODEL = os.environ.get("MODELSCOPE_MODEL", "Qwen/Qwen2.5-72B-Instruct")
HOST = os.environ.get("HOST", "0.0.0.0")
PORT = int(os.environ.get("PORT", "8111"))

from database import DB_PATH, init_database
from services.ai_history_service import AIHistoryService
from services.app_auth_service import AppAuthError, AppAuthService, AppAuthValidationError
from services.auth_service import AuthError, AuthService
from services.chat_session_service import ChatSessionError, ChatSessionService
from services.provider_token_verifier import (
    ProviderConfigurationError,
    ProviderUnavailableError,
    ProviderVerificationError,
)
from services.rate_limit_service import RateLimitExceeded, RateLimitService
from services.shared_forest_service import NotFoundError, SharedForestService, ValidationError


shared_forest_service = SharedForestService()
auth_service = AuthService()
ai_history_service = AIHistoryService()
app_auth_service = AppAuthService()
chat_session_service = ChatSessionService()
rate_limit_service = RateLimitService()


MAX_JSON_BODY_BYTES = 1024 * 1024
MAX_AI_BODY_BYTES = 128 * 1024
MAX_AI_MESSAGES = 50
MAX_AI_MESSAGE_LENGTH = 8000
MAX_AI_TOKENS = 1200


class RequestBodyTooLarge(ValueError):
    pass


class ProxyHandler(BaseHTTPRequestHandler):
    server_version = "EchoingAIProxy/0.1"

    def do_OPTIONS(self) -> None:
        self.send_json(204, None)

    def do_GET(self) -> None:
        route = urlparse(self.path)
        if route.path == "/health":
            self.send_json(200, {"ok": True})
            return
        if route.path == "/admin":
            self.send_admin_page()
            return
        if route.path == "/api/leaves":
            query = parse_qs(route.query)
            limit = self.parse_int(query.get("limit", ["100"])[0], 100)
            self.send_json(200, shared_forest_service.list_leaves(limit))
            return
        if route.path == "/api/sessions":
            try:
                app_user = self.require_app_user()
                query = parse_qs(route.query)
                limit = self.parse_int(query.get("limit", ["100"])[0], 100)
                self.send_json(200, chat_session_service.list_sessions(app_user, limit))
            except AppAuthError as exc:
                self.send_app_unauthorized(exc)
            return
        if route.path.startswith("/api/sessions/"):
            try:
                app_user = self.require_app_user()
                session_id = route.path.removeprefix("/api/sessions/").strip("/")
                session = chat_session_service.get_session(session_id, app_user)
                if session is None:
                    self.send_json(404, {"error": "not_found", "message": "session not found"})
                else:
                    self.send_json(200, session)
            except AppAuthError as exc:
                self.send_app_unauthorized(exc)
            return
        if route.path == "/api/memory-context":
            try:
                app_user = self.require_app_user()
                query = parse_qs(route.query)
                limit = self.parse_int(query.get("limit", ["5"])[0], 5)
                self.send_json(200, chat_session_service.memory_context(app_user, limit))
            except AppAuthError as exc:
                self.send_app_unauthorized(exc)
            return
        if route.path == "/api/app-auth/me":
            try:
                self.send_json(200, {"user": self.public_app_user(self.require_app_user())})
            except AppAuthError as exc:
                self.send_app_unauthorized(exc)
            return
        if route.path == "/api/auth/me":
            try:
                user = self.require_admin()
                self.send_json(200, {"user": user})
            except AuthError as exc:
                self.send_json(401, {"error": str(exc)})
            return
        if route.path == "/api/admin/leaves":
            try:
                self.require_admin()
                query = parse_qs(route.query)
                limit = self.parse_int(query.get("limit", ["100"])[0], 100)
                status = query.get("status", [None])[0]
                self.send_json(200, shared_forest_service.list_admin_leaves(limit, status))
            except AuthError as exc:
                self.send_json(401, {"error": str(exc)})
            return
        if route.path == "/api/admin/ai-history":
            try:
                self.require_admin()
                query = parse_qs(route.query)
                limit = self.parse_int(query.get("limit", ["100"])[0], 100)
                self.send_json(200, ai_history_service.list_recent(limit))
            except AuthError as exc:
                self.send_json(401, {"error": str(exc)})
            return
        self.send_json(404, {"error": "not_found"})

    def do_POST(self) -> None:
        route = urlparse(self.path)
        if route.path == "/api/auth/login":
            try:
                payload = self.read_json_body()
                username = str(payload.get("username", ""))
                password = str(payload.get("password", ""))
                self.send_json(200, auth_service.login(username, password))
            except AuthError as exc:
                self.send_json(401, {"error": str(exc)})
            except json.JSONDecodeError:
                self.send_json(400, {"error": "Request body must be valid JSON"})
            return

        if route.path == "/api/auth/logout":
            auth_service.logout(self.headers.get("Authorization"))
            self.send_json(200, {"ok": True})
            return

        if route.path == "/api/app-auth/exchange":
            try:
                self.send_json(200, app_auth_service.exchange(self.read_json_body()))
            except AppAuthValidationError as exc:
                self.send_json(400, {"error": "invalid_request", "message": str(exc)})
            except (ProviderConfigurationError, ProviderUnavailableError) as exc:
                self.send_json(503, {"error": "provider_unavailable", "message": str(exc)})
            except ProviderVerificationError as exc:
                self.send_app_unauthorized(exc)
            except (json.JSONDecodeError, ValueError):
                self.send_json(400, {"error": "invalid_request", "message": "Request body must be valid JSON"})
            return

        if route.path == "/api/app-auth/refresh":
            try:
                self.send_json(200, app_auth_service.refresh(self.read_json_body()))
            except AppAuthValidationError as exc:
                self.send_json(400, {"error": "invalid_request", "message": str(exc)})
            except AppAuthError as exc:
                self.send_app_unauthorized(exc)
            except (json.JSONDecodeError, ValueError):
                self.send_json(400, {"error": "invalid_request", "message": "Request body must be valid JSON"})
            return

        if route.path == "/api/app-auth/logout":
            try:
                app_auth_service.logout(self.headers.get("Authorization"))
                self.send_json(200, {"ok": True})
            except AppAuthError as exc:
                self.send_app_unauthorized(exc)
            return

        if route.path == "/api/leaves":
            try:
                app_user = self.require_app_user()
                payload = self.read_json_body()
                self.send_json(200, shared_forest_service.create_leaf(payload, app_user))
            except AppAuthError as exc:
                self.send_app_unauthorized(exc)
            except ValidationError as exc:
                self.send_json(400, {"error": str(exc)})
            except json.JSONDecodeError:
                self.send_json(400, {"error": "Request body must be valid JSON"})
            except Exception as exc:
                self.send_json(500, {"error": str(exc)})
            return

        if route.path == "/api/app-users/upsert":
            try:
                app_user = self.require_app_user()
                payload = self.read_json_body()
                self.send_json(200, {"user": app_auth_service.update_profile(app_user, payload)})
            except AppAuthError as exc:
                self.send_app_unauthorized(exc)
            except json.JSONDecodeError:
                self.send_json(400, {"error": "Request body must be valid JSON"})
            return

        if route.path == "/api/sessions":
            try:
                app_user = self.require_app_user()
                payload = self.read_json_body()
                self.send_json(200, chat_session_service.save_session(payload, app_user))
            except AppAuthError as exc:
                self.send_app_unauthorized(exc)
            except ChatSessionError as exc:
                self.send_json(400, {"error": str(exc)})
            except PermissionError:
                self.send_json(404, {"error": "not_found", "message": "session not found"})
            except json.JSONDecodeError:
                self.send_json(400, {"error": "Request body must be valid JSON"})
            return

        if route.path.startswith("/api/leaves/") and route.path.endswith("/like"):
            leaf_id = route.path.removeprefix("/api/leaves/").removesuffix("/like").strip("/")
            try:
                self.send_json(200, shared_forest_service.like_leaf(leaf_id))
            except ValidationError as exc:
                self.send_json(400, {"error": str(exc)})
            except NotFoundError as exc:
                self.send_json(404, {"error": str(exc)})
            except Exception as exc:
                self.send_json(500, {"error": str(exc)})
            return

        if route.path.startswith("/api/admin/leaves/") and route.path.endswith("/restore"):
            leaf_id = route.path.removeprefix("/api/admin/leaves/").removesuffix("/restore").strip("/")
            try:
                self.require_admin()
                self.send_json(200, shared_forest_service.restore_leaf(leaf_id))
            except AuthError as exc:
                self.send_json(401, {"error": str(exc)})
            except ValidationError as exc:
                self.send_json(400, {"error": str(exc)})
            except NotFoundError as exc:
                self.send_json(404, {"error": str(exc)})
            return

        if route.path.startswith("/api/admin/leaves/") and route.path.endswith("/hide"):
            leaf_id = route.path.removeprefix("/api/admin/leaves/").removesuffix("/hide").strip("/")
            try:
                self.require_admin()
                payload = self.read_json_body()
                reason = str(payload.get("reason", "manual moderation"))
                self.send_json(200, shared_forest_service.hide_leaf(leaf_id, reason))
            except AuthError as exc:
                self.send_json(401, {"error": str(exc)})
            except ValidationError as exc:
                self.send_json(400, {"error": str(exc)})
            except NotFoundError as exc:
                self.send_json(404, {"error": str(exc)})
            except json.JSONDecodeError:
                self.send_json(400, {"error": "Request body must be valid JSON"})
            return

        if route.path != "/v1/chat/completions":
            self.send_json(404, {"error": "not_found"})
            return

        try:
            app_user = self.require_app_user()
            if not API_KEY:
                self.send_json(503, {"error": "service_unavailable", "message": "AI service is not configured"})
                return
            rate_limit_service.check_ai_request(str(app_user["id"]), self.client_address[0])
            start = time.monotonic()
            body = self.read_json_body(MAX_AI_BODY_BYTES)
            forward_body = self.sanitize_chat_completion_body(body)
            self.validate_chat_completion_body(forward_body)
            forward_body["model"] = DEFAULT_MODEL
            upstream = self.forward_chat_completions(forward_body)
            ai_history_service.record(
                model=DEFAULT_MODEL,
                request_body=forward_body,
                response_body=upstream,
                status="success",
                error_message="",
                latency_ms=int((time.monotonic() - start) * 1000),
                client_ip=self.client_address[0],
                app_user_id=str(app_user["id"]),
                account_key=str(app_user["account_key"]),
            )
            self.send_json(200, upstream)
        except urllib.error.HTTPError as exc:
            exc.read()
            ai_history_service.record(
                model=DEFAULT_MODEL,
                request_body=locals().get("forward_body", locals().get("body", {})),
                response_body=None,
                status="upstream_error",
                error_message=f"upstream HTTP {exc.code}",
                latency_ms=int((time.monotonic() - locals().get("start", time.monotonic())) * 1000),
                client_ip=self.client_address[0],
                app_user_id=str(locals().get("app_user", {}).get("id")) if locals().get("app_user") else None,
                account_key=str(locals().get("app_user", {}).get("account_key", "")),
            )
            self.send_json(
                exc.code,
                {
                    "error": "upstream_error",
                    "status": exc.code,
                    "message": "AI provider request failed",
                },
            )
            print(f"ModelScope upstream error: status={exc.code}")
        except AppAuthError as exc:
            self.send_app_unauthorized(exc)
        except RateLimitExceeded as exc:
            self.send_json(429, {"error": "rate_limited", "message": str(exc)})
        except RequestBodyTooLarge as exc:
            self.send_json(413, {"error": "request_too_large", "message": str(exc)})
        except (AppAuthValidationError, ChatSessionError, ValueError) as exc:
            self.send_json(400, {"error": "invalid_request", "message": str(exc)})
        except json.JSONDecodeError:
            self.send_json(400, {"error": "Request body must be valid JSON"})
        except Exception as exc:
            ai_history_service.record(
                model=DEFAULT_MODEL,
                request_body=locals().get("forward_body", locals().get("body", {})),
                response_body=None,
                status="failed",
                error_message=type(exc).__name__,
                latency_ms=int((time.monotonic() - locals().get("start", time.monotonic())) * 1000),
                client_ip=self.client_address[0],
                app_user_id=str(locals().get("app_user", {}).get("id")) if locals().get("app_user") else None,
                account_key=str(locals().get("app_user", {}).get("account_key", "")),
            )
            self.send_json(500, {"error": "internal_error", "message": "AI request failed"})

    def do_DELETE(self) -> None:
        route = urlparse(self.path)
        if route.path.startswith("/api/sessions/"):
            session_id = route.path.removeprefix("/api/sessions/").strip("/")
            try:
                app_user = self.require_app_user()
                result = chat_session_service.delete_session(session_id, app_user)
                if result["ok"]:
                    self.send_json(200, result)
                else:
                    self.send_json(404, {"error": "not_found", "message": "session not found"})
            except AppAuthError as exc:
                self.send_app_unauthorized(exc)
            return
        if route.path.startswith("/api/admin/leaves/"):
            leaf_id = route.path.removeprefix("/api/admin/leaves/").strip("/")
            self.delete_leaf_as_admin(leaf_id)
            return
        self.send_json(404, {"error": "not_found"})

    def delete_leaf_as_admin(self, leaf_id: str) -> None:
        try:
            user = self.require_admin()
            self.send_json(200, shared_forest_service.delete_leaf(leaf_id, user))
        except AuthError as exc:
            self.send_json(401, {"error": str(exc)})
        except ValidationError as exc:
            self.send_json(400, {"error": str(exc)})
        except NotFoundError as exc:
            self.send_json(404, {"error": str(exc)})

    def parse_int(self, value: str, fallback: int) -> int:
        try:
            return int(value)
        except ValueError:
            return fallback

    def read_json_body(self, max_bytes: int = MAX_JSON_BODY_BYTES) -> dict[str, Any]:
        length = int(self.headers.get("Content-Length", "0"))
        if length < 0 or length > max_bytes:
            raise RequestBodyTooLarge(f"request body must be at most {max_bytes} bytes")
        raw = self.rfile.read(length)
        if not raw:
            return {}
        parsed = json.loads(raw.decode("utf-8"))
        if not isinstance(parsed, dict):
            raise ValueError("Request body must be a JSON object")
        return parsed

    def sanitize_chat_completion_body(self, body: dict[str, Any]) -> dict[str, Any]:
        blocked_keys = {
            "accountKey",
            "account_key",
            "userId",
            "user_id",
            "nickname",
            "bio",
            "provider",
            "externalId",
            "external_id",
        }
        return {key: value for key, value in body.items() if key not in blocked_keys}

    def validate_chat_completion_body(self, body: dict[str, Any]) -> None:
        messages = body.get("messages")
        if not isinstance(messages, list) or not messages or len(messages) > MAX_AI_MESSAGES:
            raise ValueError(f"messages must contain between 1 and {MAX_AI_MESSAGES} items")
        for message in messages:
            if not isinstance(message, dict):
                raise ValueError("each message must be an object")
            content = message.get("content")
            if not isinstance(content, str) or len(content) > MAX_AI_MESSAGE_LENGTH:
                raise ValueError(f"each message content must be at most {MAX_AI_MESSAGE_LENGTH} characters")
        max_tokens = body.get("max_tokens", MAX_AI_TOKENS)
        if not isinstance(max_tokens, int) or isinstance(max_tokens, bool) or not 1 <= max_tokens <= MAX_AI_TOKENS:
            raise ValueError(f"max_tokens must be between 1 and {MAX_AI_TOKENS}")

    def require_app_user(self) -> dict[str, Any]:
        return app_auth_service.require_user(self.headers.get("Authorization"))

    def public_app_user(self, user: dict[str, Any]) -> dict[str, Any]:
        return {
            "id": str(user["id"]),
            "provider": str(user.get("provider") or ""),
            "nickname": str(user.get("nickname") or ""),
            "bio": str(user.get("bio") or ""),
        }

    def send_app_unauthorized(self, exc: BaseException) -> None:
        self.send_json(401, {"error": "unauthorized", "message": str(exc)})

    def require_admin(self) -> dict[str, Any]:
        user = auth_service.require_user(self.headers.get("Authorization"))
        if user.get("role") != "admin":
            raise AuthError("admin role is required")
        return user

    def forward_chat_completions(self, body: dict[str, Any]) -> dict[str, Any]:
        data = json.dumps(body, ensure_ascii=False).encode("utf-8")
        request = urllib.request.Request(
            f"{API_BASE}/chat/completions",
            data=data,
            method="POST",
            headers={
                "Content-Type": "application/json",
                "Authorization": f"Bearer {API_KEY}",
            },
        )
        with urllib.request.urlopen(request, timeout=60) as response:
            response_body = response.read().decode("utf-8")
        parsed = json.loads(response_body)
        if not isinstance(parsed, dict):
            raise ValueError("Upstream response must be a JSON object")
        return parsed

    def send_json(self, status: int, payload: dict[str, Any] | None) -> None:
        self.send_response(status)
        self.send_cors_headers()
        if payload is None:
            self.end_headers()
            return
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def send_raw(self, status: int, payload: str) -> None:
        data = payload.encode("utf-8")
        self.send_response(status)
        self.send_cors_headers()
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def send_html(self, status: int, payload: str) -> None:
        data = payload.encode("utf-8")
        self.send_response(status)
        self.send_cors_headers()
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def send_admin_page(self) -> None:
        admin_path = ROOT / "admin.html"
        if not admin_path.exists():
            self.send_json(404, {"error": "admin page not found"})
            return
        self.send_html(200, admin_path.read_text(encoding="utf-8"))

    def send_cors_headers(self) -> None:
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization")

    def log_message(self, format: str, *args: Any) -> None:
        print("%s - %s" % (self.address_string(), format % args))


def main() -> None:
    init_database()
    auth_service.bootstrap_admin_from_env()
    httpd = ThreadingHTTPServer((HOST, PORT), ProxyHandler)
    print(f"Echoing backend listening on http://{HOST}:{PORT}")
    print(f"Forwarding chat completions to {API_BASE}/chat/completions")
    print(f"Shared forest SQLite database: {DB_PATH}")
    httpd.serve_forever()


if __name__ == "__main__":
    main()
