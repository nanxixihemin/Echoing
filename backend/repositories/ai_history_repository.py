from __future__ import annotations

import sqlite3
from typing import Any


class AIHistoryRepository:
    def __init__(self, connection: sqlite3.Connection) -> None:
        self.connection = connection

    def create(
        self,
        history_id: str,
        model: str,
        prompt_preview: str,
        response_preview: str,
        status: str,
        error_message: str,
        latency_ms: int,
        client_ip: str,
        created_at: str,
    ) -> None:
        self.connection.execute(
            """
            INSERT INTO ai_history(
              id, model, prompt_preview, response_preview, status,
              error_message, latency_ms, client_ip, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                history_id,
                model,
                prompt_preview,
                response_preview,
                status,
                error_message,
                latency_ms,
                client_ip,
                created_at,
            ),
        )

    def list_recent(self, limit: int) -> list[dict[str, Any]]:
        cursor = self.connection.execute(
            """
            SELECT id, model, prompt_preview, response_preview, status,
                   error_message, latency_ms, client_ip, created_at
            FROM ai_history
            ORDER BY created_at DESC
            LIMIT ?
            """,
            (limit,),
        )
        return [dict(row) for row in cursor.fetchall()]
