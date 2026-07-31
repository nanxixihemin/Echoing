from __future__ import annotations

import sqlite3
from typing import Any


class ChatSessionRepository:
    def __init__(self, connection: sqlite3.Connection) -> None:
        self.connection = connection

    def upsert(
        self,
        session_id: str,
        app_user_id: str,
        account_key: str,
        theme: str,
        summary: str,
        system_prompt: str,
        messages_json: str,
        created_at: int,
        updated_at: int,
        synced_at: str,
    ) -> dict[str, Any]:
        self.connection.execute(
            """
            INSERT INTO chat_sessions(
              id, app_user_id, account_key, theme, summary, system_prompt,
              messages_json, created_at, updated_at, synced_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
              account_key = excluded.account_key,
              theme = excluded.theme,
              summary = excluded.summary,
              system_prompt = excluded.system_prompt,
              messages_json = excluded.messages_json,
              created_at = excluded.created_at,
              updated_at = excluded.updated_at,
              synced_at = excluded.synced_at
            WHERE chat_sessions.app_user_id = excluded.app_user_id
            """,
            (
                session_id,
                app_user_id,
                account_key,
                theme,
                summary,
                system_prompt,
                messages_json,
                created_at,
                updated_at,
                synced_at,
            ),
        )
        row = self.get_for_user(session_id, app_user_id)
        if row is None:
            raise PermissionError("chat session belongs to another user")
        return row

    def get_for_user(self, session_id: str, app_user_id: str) -> dict[str, Any] | None:
        row = self.connection.execute(
            """
            SELECT id, app_user_id, account_key, theme, summary, system_prompt,
                   messages_json, created_at, updated_at, synced_at
            FROM chat_sessions
            WHERE id = ? AND app_user_id = ?
            """,
            (session_id, app_user_id),
        ).fetchone()
        return dict(row) if row else None

    def list_for_user(self, app_user_id: str, limit: int) -> list[dict[str, Any]]:
        cursor = self.connection.execute(
            """
            SELECT id, app_user_id, account_key, theme, summary, system_prompt,
                   messages_json, created_at, updated_at, synced_at
            FROM chat_sessions
            WHERE app_user_id = ?
            ORDER BY updated_at DESC
            LIMIT ?
            """,
            (app_user_id, limit),
        )
        return [dict(row) for row in cursor.fetchall()]

    def delete_for_user(self, session_id: str, app_user_id: str) -> bool:
        cursor = self.connection.execute(
            "DELETE FROM chat_sessions WHERE id = ? AND app_user_id = ?",
            (session_id, app_user_id),
        )
        return cursor.rowcount > 0
