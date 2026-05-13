from __future__ import annotations

import sqlite3
from typing import Any


class SharedForestRepository:
    def __init__(self, connection: sqlite3.Connection) -> None:
        self.connection = connection

    def delete_expired(self, cutoff: str) -> int:
        cursor = self.connection.execute(
            """
            UPDATE shared_leaves
            SET status = 'deleted', deleted_at = ?, updated_at = ?
            WHERE created_at < ? AND status != 'deleted'
            """,
            (cutoff, cutoff, cutoff),
        )
        return cursor.rowcount

    def list_leaves(self, limit: int, include_hidden: bool = False) -> list[dict[str, Any]]:
        status_filter = "" if include_hidden else "WHERE status = 'visible'"
        cursor = self.connection.execute(
            f"""
            SELECT id, content, nickname, ai_response, like_count, created_at, updated_at,
                   status, moderation_flag, moderation_reason, deleted_at, deleted_by
            FROM shared_leaves
            {status_filter}
            ORDER BY created_at DESC
            LIMIT ?
            """,
            (limit,),
        )
        return [dict(row) for row in cursor.fetchall()]

    def list_admin_leaves(self, limit: int, status: str | None) -> list[dict[str, Any]]:
        if status:
            cursor = self.connection.execute(
                """
                SELECT id, content, nickname, ai_response, like_count, created_at, updated_at,
                       status, moderation_flag, moderation_reason, deleted_at, deleted_by
                FROM shared_leaves
                WHERE status = ?
                ORDER BY created_at DESC
                LIMIT ?
                """,
                (status, limit),
            )
        else:
            cursor = self.connection.execute(
                """
                SELECT id, content, nickname, ai_response, like_count, created_at, updated_at,
                       status, moderation_flag, moderation_reason, deleted_at, deleted_by
                FROM shared_leaves
                ORDER BY created_at DESC
                LIMIT ?
                """,
                (limit,),
            )
        return [dict(row) for row in cursor.fetchall()]

    def soft_delete(self, leaf_id: str, deleted_at: str, deleted_by: str) -> bool:
        cursor = self.connection.execute(
            """
            UPDATE shared_leaves
            SET status = 'deleted', deleted_at = ?, deleted_by = ?, updated_at = ?
            WHERE id = ? AND status != 'deleted'
            """,
            (deleted_at, deleted_by, deleted_at, leaf_id),
        )
        return cursor.rowcount > 0

    def restore(self, leaf_id: str, updated_at: str) -> bool:
        cursor = self.connection.execute(
            """
            UPDATE shared_leaves
            SET status = 'visible', deleted_at = NULL, deleted_by = NULL, updated_at = ?
            WHERE id = ?
            """,
            (updated_at, leaf_id),
        )
        return cursor.rowcount > 0

    def hide_for_moderation(self, leaf_id: str, reason: str, updated_at: str) -> bool:
        cursor = self.connection.execute(
            """
            UPDATE shared_leaves
            SET status = 'hidden', moderation_flag = 'review', moderation_reason = ?, updated_at = ?
            WHERE id = ?
            """,
            (reason, updated_at, leaf_id),
        )
        return cursor.rowcount > 0

    def hard_delete_expired_deleted(self, cutoff: str) -> int:
        cursor = self.connection.execute(
            "DELETE FROM shared_leaves WHERE status = 'deleted' AND deleted_at < ?",
            (cutoff,),
        )
        return cursor.rowcount

    def create_leaf(
        self,
        leaf_id: str,
        content: str,
        nickname: str,
        ai_response: str,
        moderation_flag: str,
        moderation_reason: str,
        created_at: str,
    ) -> dict[str, Any]:
        self.connection.execute(
            """
            INSERT INTO shared_leaves (
              id, content, nickname, ai_response, like_count, created_at, updated_at,
              status, moderation_flag, moderation_reason
            ) VALUES (?, ?, ?, ?, 0, ?, ?, 'visible', ?, ?)
            """,
            (
                leaf_id,
                content,
                nickname,
                ai_response,
                created_at,
                created_at,
                moderation_flag,
                moderation_reason,
            ),
        )
        row = self.connection.execute(
            """
            SELECT id, content, nickname, ai_response, like_count, created_at, updated_at,
                   status, moderation_flag, moderation_reason, deleted_at, deleted_by
            FROM shared_leaves
            WHERE id = ?
            """,
            (leaf_id,),
        ).fetchone()
        if row is None:
            raise RuntimeError("Created leaf cannot be loaded")
        return dict(row)

    def increment_like(self, leaf_id: str, updated_at: str) -> dict[str, Any] | None:
        self.connection.execute(
            """
            UPDATE shared_leaves
            SET like_count = like_count + 1, updated_at = ?
            WHERE id = ?
            """,
            (updated_at, leaf_id),
        )
        row = self.connection.execute(
            """
            SELECT id, like_count
            FROM shared_leaves
            WHERE id = ?
            """,
            (leaf_id,),
        ).fetchone()
        if row is None:
            return None
        return dict(row)
