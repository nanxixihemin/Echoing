from __future__ import annotations

import sqlite3
from typing import Any


class AuthRepository:
    def __init__(self, connection: sqlite3.Connection) -> None:
        self.connection = connection

    def get_user_by_username(self, username: str) -> dict[str, Any] | None:
        row = self.connection.execute(
            """
            SELECT id, username, password_hash, salt, role, created_at, last_login_at
            FROM admin_users
            WHERE username = ?
            """,
            (username,),
        ).fetchone()
        return dict(row) if row else None

    def get_user_by_id(self, user_id: str) -> dict[str, Any] | None:
        row = self.connection.execute(
            """
            SELECT id, username, role, created_at, last_login_at
            FROM admin_users
            WHERE id = ?
            """,
            (user_id,),
        ).fetchone()
        return dict(row) if row else None

    def count_users(self) -> int:
        row = self.connection.execute("SELECT COUNT(*) AS count FROM admin_users").fetchone()
        return int(row["count"])

    def create_user(
        self,
        user_id: str,
        username: str,
        password_hash: str,
        salt: str,
        role: str,
        created_at: str,
    ) -> None:
        self.connection.execute(
            """
            INSERT INTO admin_users(id, username, password_hash, salt, role, created_at)
            VALUES (?, ?, ?, ?, ?, ?)
            """,
            (user_id, username, password_hash, salt, role, created_at),
        )

    def update_last_login(self, user_id: str, last_login_at: str) -> None:
        self.connection.execute(
            "UPDATE admin_users SET last_login_at = ? WHERE id = ?",
            (last_login_at, user_id),
        )

    def create_session(
        self,
        token_hash: str,
        user_id: str,
        expires_at: str,
        created_at: str,
    ) -> None:
        self.connection.execute(
            """
            INSERT INTO auth_sessions(token_hash, user_id, expires_at, created_at)
            VALUES (?, ?, ?, ?)
            """,
            (token_hash, user_id, expires_at, created_at),
        )

    def get_session(self, token_hash: str, now: str) -> dict[str, Any] | None:
        row = self.connection.execute(
            """
            SELECT s.token_hash, s.user_id, s.expires_at, s.created_at,
                   u.username, u.role
            FROM auth_sessions s
            JOIN admin_users u ON u.id = s.user_id
            WHERE s.token_hash = ?
              AND s.revoked_at IS NULL
              AND s.expires_at > ?
            """,
            (token_hash, now),
        ).fetchone()
        return dict(row) if row else None

    def revoke_session(self, token_hash: str, revoked_at: str) -> bool:
        cursor = self.connection.execute(
            """
            UPDATE auth_sessions
            SET revoked_at = ?
            WHERE token_hash = ? AND revoked_at IS NULL
            """,
            (revoked_at, token_hash),
        )
        return cursor.rowcount > 0
