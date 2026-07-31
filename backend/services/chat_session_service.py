from __future__ import annotations

import json
from datetime import datetime, timezone
from typing import Any, Mapping

from database import get_connection
from repositories.chat_session_repository import ChatSessionRepository
class ChatSessionError(ValueError):
    pass


class ChatSessionService:
    def save_session(self, payload: Mapping[str, Any], app_user: Mapping[str, Any]) -> dict[str, Any]:
        session_id = self._text(payload.get("id"))
        if not session_id:
            raise ChatSessionError("session id is required")
        messages = payload.get("messages")
        if not isinstance(messages, list):
            messages = []

        created_at = self._int(payload.get("createdAt"), self._now_ms())
        updated_at = self._int(payload.get("updatedAt"), created_at)
        synced_at = self._format_time(self._now())
        messages_json = json.dumps(messages, ensure_ascii=False)

        with get_connection() as connection:
            row = ChatSessionRepository(connection).upsert(
                session_id=session_id,
                app_user_id=str(app_user["id"]),
                account_key=str(app_user["account_key"]),
                theme=self._text(payload.get("theme")),
                summary=self._text(payload.get("summary")),
                system_prompt=self._text(payload.get("systemPrompt")),
                messages_json=messages_json,
                created_at=created_at,
                updated_at=updated_at,
                synced_at=synced_at,
            )
        return self._to_client_session(row)

    def list_sessions(self, app_user: Mapping[str, Any], limit: int) -> dict[str, Any]:
        normalized_limit = max(1, min(limit, 200))
        with get_connection() as connection:
            rows = ChatSessionRepository(connection).list_for_user(str(app_user["id"]), normalized_limit)
        return {"items": [self._to_client_session(row, include_messages=False) for row in rows]}

    def get_session(self, session_id: str, app_user: Mapping[str, Any]) -> dict[str, Any] | None:
        with get_connection() as connection:
            row = ChatSessionRepository(connection).get_for_user(session_id, str(app_user["id"]))
        return self._to_client_session(row) if row is not None else None

    def delete_session(self, session_id: str, app_user: Mapping[str, Any]) -> dict[str, Any]:
        with get_connection() as connection:
            deleted = ChatSessionRepository(connection).delete_for_user(session_id, str(app_user["id"]))
        return {"ok": deleted}

    def memory_context(self, app_user: Mapping[str, Any], limit: int = 5) -> dict[str, Any]:
        with get_connection() as connection:
            rows = ChatSessionRepository(connection).list_for_user(
                str(app_user["id"]), max(1, min(limit, 20))
            )
        lines: list[str] = []
        for row in rows[:limit]:
            theme = self._text(row.get("theme")) or "未设主题"
            summary = self._text(row.get("summary")) or "无摘要"
            lines.append(f"- 「{theme}」: {summary}")
        context = "用户的历史占卜记录：\n" + "\n".join(lines) if lines else ""
        return {"context": context, "count": len(lines)}

    def _to_client_session(self, row: Mapping[str, Any], include_messages: bool = True) -> dict[str, Any]:
        messages = []
        if include_messages:
            try:
                parsed = json.loads(str(row.get("messages_json") or "[]"))
                if isinstance(parsed, list):
                    messages = parsed
            except json.JSONDecodeError:
                messages = []
        return {
            "id": str(row["id"]),
            "userId": str(row["app_user_id"]),
            "theme": self._text(row.get("theme")),
            "summary": self._text(row.get("summary")),
            "systemPrompt": self._text(row.get("system_prompt")),
            "createdAt": self._int(row.get("created_at"), 0),
            "updatedAt": self._int(row.get("updated_at"), 0),
            "messageCount": len(messages) if include_messages else self._message_count(row),
            "messages": messages,
        }

    def _message_count(self, row: Mapping[str, Any]) -> int:
        try:
            parsed = json.loads(str(row.get("messages_json") or "[]"))
            return len(parsed) if isinstance(parsed, list) else 0
        except json.JSONDecodeError:
            return 0

    def _text(self, value: Any) -> str:
        if value is None:
            return ""
        return str(value).strip()

    def _int(self, value: Any, fallback: int) -> int:
        try:
            return int(value)
        except (TypeError, ValueError):
            return fallback

    def _now(self) -> datetime:
        return datetime.now(timezone.utc)

    def _now_ms(self) -> int:
        return int(self._now().timestamp() * 1000)

    def _format_time(self, value: datetime) -> str:
        return value.strftime("%Y-%m-%d %H:%M:%S")
