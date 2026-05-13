from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any
from uuid import uuid4

from database import get_connection
from repositories.shared_forest_repository import SharedForestRepository
from services.moderation_service import ModerationService


MAX_CONTENT_LENGTH = 500
MAX_NICKNAME_LENGTH = 12
DEFAULT_NICKNAME = "anonymous leaf"
LEAF_RETENTION_DAYS = 7
DEFAULT_LIST_LIMIT = 100
MAX_LIST_LIMIT = 200


class ValidationError(ValueError):
    pass


class NotFoundError(LookupError):
    pass


class SharedForestService:
    def __init__(self) -> None:
        self.moderation_service = ModerationService()

    def list_leaves(self, limit: int = DEFAULT_LIST_LIMIT) -> dict[str, Any]:
        normalized_limit = max(1, min(limit, MAX_LIST_LIMIT))
        cutoff = self._format_time(self._now() - timedelta(days=LEAF_RETENTION_DAYS))

        with get_connection() as connection:
            repository = SharedForestRepository(connection)
            repository.delete_expired(cutoff)
            leaves = [self._serialize_leaf(row) for row in repository.list_leaves(normalized_limit)]

        return {"leaves": leaves}

    def create_leaf(self, payload: dict[str, Any]) -> dict[str, Any]:
        content = self._normalize_content(payload.get("content"))
        nickname = self._normalize_nickname(payload.get("nickname"))
        ai_response = self._normalize_optional_text(payload.get("ai_response") or payload.get("aiResponse"), 1000)
        moderation = self.moderation_service.review_text(content)
        if moderation.flag == "blocked":
            raise ValidationError("content did not pass moderation")
        created_at = self._format_time(self._now())

        with get_connection() as connection:
            repository = SharedForestRepository(connection)
            leaf = repository.create_leaf(
                leaf_id=f"leaf_{uuid4().hex}",
                content=content,
                nickname=nickname,
                ai_response=ai_response,
                moderation_flag=moderation.flag,
                moderation_reason=moderation.reason,
                created_at=created_at,
            )

        return {"leaf": self._serialize_leaf(leaf)}

    def like_leaf(self, leaf_id: str) -> dict[str, Any]:
        normalized_id = leaf_id.strip()
        if not normalized_id:
            raise ValidationError("leaf_id is required")

        with get_connection() as connection:
            repository = SharedForestRepository(connection)
            updated = repository.increment_like(normalized_id, self._format_time(self._now()))

        if updated is None:
            raise NotFoundError("leaf not found")

        like_count = int(updated["like_count"])
        return {
            "ok": True,
            "id": normalized_id,
            "like_count": like_count,
            "green_level": self._green_level(like_count),
        }

    def list_admin_leaves(self, limit: int = DEFAULT_LIST_LIMIT, status: str | None = None) -> dict[str, Any]:
        normalized_limit = max(1, min(limit, MAX_LIST_LIMIT))
        normalized_status = status if status in {"visible", "hidden", "deleted"} else None
        with get_connection() as connection:
            repository = SharedForestRepository(connection)
            leaves = [
                self._serialize_leaf(row, include_admin_fields=True)
                for row in repository.list_admin_leaves(normalized_limit, normalized_status)
            ]
        return {"leaves": leaves}

    def delete_leaf(self, leaf_id: str, admin_user: dict[str, Any]) -> dict[str, Any]:
        normalized_id = leaf_id.strip()
        if not normalized_id:
            raise ValidationError("leaf_id is required")
        now = self._format_time(self._now())
        with get_connection() as connection:
            repository = SharedForestRepository(connection)
            deleted = repository.soft_delete(normalized_id, now, str(admin_user["username"]))
        if not deleted:
            raise NotFoundError("leaf not found")
        return {"ok": True, "id": normalized_id}

    def restore_leaf(self, leaf_id: str) -> dict[str, Any]:
        normalized_id = leaf_id.strip()
        if not normalized_id:
            raise ValidationError("leaf_id is required")
        now = self._format_time(self._now())
        with get_connection() as connection:
            repository = SharedForestRepository(connection)
            restored = repository.restore(normalized_id, now)
        if not restored:
            raise NotFoundError("leaf not found")
        return {"ok": True, "id": normalized_id}

    def hide_leaf(self, leaf_id: str, reason: str) -> dict[str, Any]:
        normalized_id = leaf_id.strip()
        if not normalized_id:
            raise ValidationError("leaf_id is required")
        now = self._format_time(self._now())
        with get_connection() as connection:
            repository = SharedForestRepository(connection)
            hidden = repository.hide_for_moderation(normalized_id, reason.strip()[:500], now)
        if not hidden:
            raise NotFoundError("leaf not found")
        return {"ok": True, "id": normalized_id}

    def _serialize_leaf(self, row: dict[str, Any], include_admin_fields: bool = False) -> dict[str, Any]:
        like_count = int(row.get("like_count") or 0)
        payload = {
            "id": str(row["id"]),
            "content": str(row["content"]),
            "nickname": str(row["nickname"]),
            "ai_response": str(row.get("ai_response") or ""),
            "like_count": like_count,
            "green_level": self._green_level(like_count),
            "created_at": str(row["created_at"]),
            "updated_at": str(row["updated_at"]),
        }
        if include_admin_fields:
            payload.update(
                {
                    "status": str(row.get("status") or "visible"),
                    "moderation_flag": str(row.get("moderation_flag") or "clean"),
                    "moderation_reason": str(row.get("moderation_reason") or ""),
                    "deleted_at": row.get("deleted_at"),
                    "deleted_by": row.get("deleted_by"),
                }
            )
        return payload

    def _normalize_content(self, value: Any) -> str:
        if not isinstance(value, str):
            raise ValidationError("content must be a string")
        content = value.strip()
        if not content:
            raise ValidationError("content is required")
        if len(content) > MAX_CONTENT_LENGTH:
            raise ValidationError(f"content must be at most {MAX_CONTENT_LENGTH} characters")
        return content

    def _normalize_nickname(self, value: Any) -> str:
        if not isinstance(value, str):
            return DEFAULT_NICKNAME
        nickname = value.strip() or DEFAULT_NICKNAME
        return nickname[:MAX_NICKNAME_LENGTH]

    def _normalize_optional_text(self, value: Any, max_length: int) -> str:
        if not isinstance(value, str):
            return ""
        return value.strip()[:max_length]

    def _green_level(self, like_count: int) -> int:
        return min(100, 30 + max(0, like_count) * 5)

    def _now(self) -> datetime:
        return datetime.now(timezone.utc)

    def _format_time(self, value: datetime) -> str:
        return value.strftime("%Y-%m-%d %H:%M:%S")
