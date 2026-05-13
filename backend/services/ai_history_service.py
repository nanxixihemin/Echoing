from __future__ import annotations

from datetime import datetime, timezone
from typing import Any
from uuid import uuid4

from database import get_connection
from repositories.ai_history_repository import AIHistoryRepository


class AIHistoryService:
    def record(
        self,
        model: str,
        request_body: dict[str, Any],
        response_body: dict[str, Any] | None,
        status: str,
        error_message: str,
        latency_ms: int,
        client_ip: str,
    ) -> None:
        prompt_preview = self._extract_prompt_preview(request_body)
        response_preview = self._extract_response_preview(response_body)
        with get_connection() as connection:
            AIHistoryRepository(connection).create(
                history_id=f"ai_{uuid4().hex}",
                model=model,
                prompt_preview=prompt_preview,
                response_preview=response_preview,
                status=status,
                error_message=error_message[:1000],
                latency_ms=latency_ms,
                client_ip=client_ip,
                created_at=self._format_time(self._now()),
            )

    def list_recent(self, limit: int) -> dict[str, Any]:
        normalized_limit = max(1, min(limit, 200))
        with get_connection() as connection:
            rows = AIHistoryRepository(connection).list_recent(normalized_limit)
        return {"items": rows}

    def _extract_prompt_preview(self, request_body: dict[str, Any]) -> str:
        messages = request_body.get("messages")
        if isinstance(messages, list):
            parts: list[str] = []
            for item in messages:
                if isinstance(item, dict):
                    role = item.get("role", "unknown")
                    content = item.get("content", "")
                    if isinstance(content, str):
                        parts.append(f"{role}: {content}")
            return "\n".join(parts)[:2000]
        return str(request_body)[:2000]

    def _extract_response_preview(self, response_body: dict[str, Any] | None) -> str:
        if not response_body:
            return ""
        choices = response_body.get("choices")
        if isinstance(choices, list) and choices:
            first = choices[0]
            if isinstance(first, dict):
                message = first.get("message")
                if isinstance(message, dict) and isinstance(message.get("content"), str):
                    return str(message["content"])[:2000]
        return str(response_body)[:2000]

    def _now(self) -> datetime:
        return datetime.now(timezone.utc)

    def _format_time(self, value: datetime) -> str:
        return value.strftime("%Y-%m-%d %H:%M:%S")
