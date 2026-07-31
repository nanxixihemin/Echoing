from __future__ import annotations

import sqlite3
from typing import Any


class AppAuthRepository:
    def __init__(self, connection: sqlite3.Connection) -> None:
        self.connection = connection

    def get_identity(self, provider: str, provider_user_id: str) -> dict[str, Any] | None:
        row = self.connection.execute(
            """
            SELECT i.id AS identity_id, i.provider, i.provider_user_id, i.email,
                   u.id, u.account_key, u.nickname, u.bio, u.created_at,
                   u.updated_at, u.last_seen_at
            FROM app_identities i
            JOIN app_users u ON u.id = i.app_user_id
            WHERE i.provider = ? AND i.provider_user_id = ?
            """,
            (provider, provider_user_id),
        ).fetchone()
        return dict(row) if row else None

    def get_user_by_id(self, app_user_id: str) -> dict[str, Any] | None:
        row = self.connection.execute(
            """
            SELECT id, account_key, provider, external_id, nickname, bio,
                   created_at, updated_at, last_seen_at
            FROM app_users
            WHERE id = ?
            """,
            (app_user_id,),
        ).fetchone()
        return dict(row) if row else None

    def get_user_by_account_key(self, account_key: str) -> dict[str, Any] | None:
        row = self.connection.execute(
            """
            SELECT id, account_key, provider, external_id, nickname, bio,
                   created_at, updated_at, last_seen_at
            FROM app_users
            WHERE account_key = ?
            """,
            (account_key,),
        ).fetchone()
        return dict(row) if row else None

    def user_has_identity(self, app_user_id: str) -> bool:
        row = self.connection.execute(
            "SELECT 1 FROM app_identities WHERE app_user_id = ? LIMIT 1",
            (app_user_id,),
        ).fetchone()
        return row is not None

    def create_user(
        self,
        user_id: str,
        account_key: str,
        provider: str,
        provider_user_id: str,
        now: str,
    ) -> dict[str, Any]:
        self.connection.execute(
            """
            INSERT INTO app_users(
              id, account_key, provider, external_id, nickname, bio,
              created_at, updated_at, last_seen_at
            ) VALUES (?, ?, ?, ?, '', '', ?, ?, ?)
            """,
            (user_id, account_key, provider, provider_user_id, now, now, now),
        )
        user = self.get_user_by_id(user_id)
        if user is None:
            raise RuntimeError("Created app user cannot be loaded")
        return user

    def bind_identity(
        self,
        identity_id: str,
        app_user_id: str,
        provider: str,
        provider_user_id: str,
        email: str,
        now: str,
    ) -> None:
        self.connection.execute(
            """
            INSERT INTO app_identities(
              id, app_user_id, provider, provider_user_id, email, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            (identity_id, app_user_id, provider, provider_user_id, email, now, now),
        )
        self.connection.execute(
            """
            UPDATE app_users
            SET provider = ?, external_id = ?, updated_at = ?, last_seen_at = ?
            WHERE id = ?
            """,
            (provider, provider_user_id, now, now, app_user_id),
        )

    def update_identity_email(self, identity_id: str, email: str, now: str) -> None:
        self.connection.execute(
            "UPDATE app_identities SET email = ?, updated_at = ? WHERE id = ?",
            (email, now, identity_id),
        )

    def record_legacy_migration(
        self,
        migration_id: str,
        identity_id: str,
        app_user_id: str,
        legacy_account_key_hash: str,
        now: str,
    ) -> None:
        self.connection.execute(
            """
            INSERT INTO app_identity_migrations(
              id, identity_id, app_user_id, legacy_account_key_hash,
              migration_type, created_at
            ) VALUES (?, ?, ?, ?, 'verified_email', ?)
            """,
            (migration_id, identity_id, app_user_id, legacy_account_key_hash, now),
        )

    def create_session(
        self,
        session_id: str,
        app_user_id: str,
        access_token_hash: str,
        refresh_token_hash: str,
        access_expires_at: str,
        refresh_expires_at: str,
        device_id_hash: str,
        now: str,
    ) -> None:
        self.connection.execute(
            """
            INSERT INTO app_auth_sessions(
              id, app_user_id, access_token_hash, refresh_token_hash,
              access_expires_at, refresh_expires_at, created_at, updated_at,
              device_id_hash, last_used_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                session_id,
                app_user_id,
                access_token_hash,
                refresh_token_hash,
                access_expires_at,
                refresh_expires_at,
                now,
                now,
                device_id_hash,
                now,
            ),
        )

    def get_active_session_by_access_hash(self, token_hash: str, now: str) -> dict[str, Any] | None:
        row = self.connection.execute(
            """
            SELECT s.id AS session_id, s.app_user_id, s.access_expires_at,
                   s.refresh_expires_at, s.device_id_hash, s.last_used_at,
                   u.id, u.account_key, u.nickname, u.bio,
                   i.provider, i.provider_user_id, i.email
            FROM app_auth_sessions s
            JOIN app_users u ON u.id = s.app_user_id
            JOIN app_identities i ON i.app_user_id = u.id
            WHERE s.access_token_hash = ?
              AND s.revoked_at IS NULL
              AND s.access_expires_at > ?
            ORDER BY i.created_at ASC
            LIMIT 1
            """,
            (token_hash, now),
        ).fetchone()
        return dict(row) if row else None

    def get_active_session_by_refresh_hash(self, token_hash: str, now: str) -> dict[str, Any] | None:
        row = self.connection.execute(
            """
            SELECT s.id AS session_id, s.app_user_id, s.device_id_hash,
                   u.id, u.account_key, u.nickname, u.bio,
                   i.provider, i.provider_user_id, i.email
            FROM app_auth_sessions s
            JOIN app_users u ON u.id = s.app_user_id
            JOIN app_identities i ON i.app_user_id = u.id
            WHERE s.refresh_token_hash = ?
              AND s.revoked_at IS NULL
              AND s.refresh_expires_at > ?
            ORDER BY i.created_at ASC
            LIMIT 1
            """,
            (token_hash, now),
        ).fetchone()
        return dict(row) if row else None

    def rotate_session(
        self,
        session_id: str,
        old_refresh_token_hash: str,
        access_token_hash: str,
        refresh_token_hash: str,
        access_expires_at: str,
        refresh_expires_at: str,
        now: str,
    ) -> bool:
        cursor = self.connection.execute(
            """
            UPDATE app_auth_sessions
            SET access_token_hash = ?, refresh_token_hash = ?,
                access_expires_at = ?, refresh_expires_at = ?,
                updated_at = ?, last_used_at = ?
            WHERE id = ? AND refresh_token_hash = ? AND revoked_at IS NULL
            """,
            (
                access_token_hash,
                refresh_token_hash,
                access_expires_at,
                refresh_expires_at,
                now,
                now,
                session_id,
                old_refresh_token_hash,
            ),
        )
        return cursor.rowcount == 1

    def touch_session(self, session_id: str, now: str, before: str) -> None:
        self.connection.execute(
            """
            UPDATE app_auth_sessions
            SET last_used_at = ?, updated_at = ?
            WHERE id = ? AND (last_used_at IS NULL OR last_used_at < ?)
            """,
            (now, now, session_id, before),
        )

    def revoke_session_by_access_hash(self, token_hash: str, now: str) -> bool:
        cursor = self.connection.execute(
            """
            UPDATE app_auth_sessions
            SET revoked_at = ?, updated_at = ?
            WHERE access_token_hash = ? AND revoked_at IS NULL
            """,
            (now, now, token_hash),
        )
        return cursor.rowcount == 1

    def update_profile(self, app_user_id: str, nickname: str, bio: str, now: str) -> dict[str, Any]:
        self.connection.execute(
            """
            UPDATE app_users
            SET nickname = ?, bio = ?, updated_at = ?, last_seen_at = ?
            WHERE id = ?
            """,
            (nickname, bio, now, now, app_user_id),
        )
        user = self.get_user_by_id(app_user_id)
        if user is None:
            raise RuntimeError("Updated app user cannot be loaded")
        return user
