from __future__ import annotations

import os
import sqlite3
from pathlib import Path
from typing import Callable


ROOT = Path(__file__).resolve().parent
DEFAULT_DB_PATH = ROOT / "data" / "echoing.db"
CONFIGURED_DB_PATH = Path(os.environ.get("ECHOING_DB_PATH", str(DEFAULT_DB_PATH))).expanduser()
DB_PATH = CONFIGURED_DB_PATH if CONFIGURED_DB_PATH.is_absolute() else ROOT / CONFIGURED_DB_PATH


class ManagedConnection(sqlite3.Connection):
    def __exit__(self, exc_type: object, exc_value: object, traceback: object) -> bool:
        try:
            return super().__exit__(exc_type, exc_value, traceback)
        finally:
            self.close()


def get_connection() -> sqlite3.Connection:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    connection = sqlite3.connect(DB_PATH, factory=ManagedConnection)
    connection.row_factory = sqlite3.Row
    connection.execute("PRAGMA foreign_keys = ON")
    return connection


def init_database() -> None:
    with get_connection() as connection:
        connection.execute(
            """
            CREATE TABLE IF NOT EXISTS schema_migrations (
              version INTEGER PRIMARY KEY,
              name TEXT NOT NULL,
              applied_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
            )
            """
        )
        for version, name, migration in MIGRATIONS:
            if _is_applied(connection, version):
                continue
            migration(connection)
            connection.execute(
                "INSERT INTO schema_migrations(version, name) VALUES (?, ?)",
                (version, name),
            )


Migration = Callable[[sqlite3.Connection], None]


def _is_applied(connection: sqlite3.Connection, version: int) -> bool:
    row = connection.execute(
        "SELECT 1 FROM schema_migrations WHERE version = ?",
        (version,),
    ).fetchone()
    return row is not None


def _column_exists(connection: sqlite3.Connection, table: str, column: str) -> bool:
    rows = connection.execute(f"PRAGMA table_info({table})").fetchall()
    return any(row["name"] == column for row in rows)


def _add_column_if_missing(
    connection: sqlite3.Connection,
    table: str,
    column: str,
    definition: str,
) -> None:
    if not _column_exists(connection, table, column):
        connection.execute(f"ALTER TABLE {table} ADD COLUMN {column} {definition}")


def _migration_001_shared_forest(connection: sqlite3.Connection) -> None:
    connection.execute(
        """
        CREATE TABLE IF NOT EXISTS shared_leaves (
          id TEXT PRIMARY KEY,
          content TEXT NOT NULL,
          nickname TEXT NOT NULL,
          ai_response TEXT NOT NULL DEFAULT '',
          like_count INTEGER NOT NULL DEFAULT 0,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
        """
    )
    connection.execute(
        """
        CREATE INDEX IF NOT EXISTS idx_shared_leaves_created_at
        ON shared_leaves(created_at DESC)
        """
    )


def _migration_002_auth_admin_ai_history(connection: sqlite3.Connection) -> None:
    _add_column_if_missing(connection, "shared_leaves", "status", "TEXT NOT NULL DEFAULT 'visible'")
    _add_column_if_missing(connection, "shared_leaves", "moderation_flag", "TEXT NOT NULL DEFAULT 'clean'")
    _add_column_if_missing(connection, "shared_leaves", "moderation_reason", "TEXT NOT NULL DEFAULT ''")
    _add_column_if_missing(connection, "shared_leaves", "deleted_at", "TEXT")
    _add_column_if_missing(connection, "shared_leaves", "deleted_by", "TEXT")
    connection.execute(
        """
        CREATE INDEX IF NOT EXISTS idx_shared_leaves_status_created_at
        ON shared_leaves(status, created_at DESC)
        """
    )
    connection.execute(
        """
        CREATE TABLE IF NOT EXISTS admin_users (
          id TEXT PRIMARY KEY,
          username TEXT NOT NULL UNIQUE,
          password_hash TEXT NOT NULL,
          salt TEXT NOT NULL,
          role TEXT NOT NULL DEFAULT 'admin',
          created_at TEXT NOT NULL,
          last_login_at TEXT
        )
        """
    )
    connection.execute(
        """
        CREATE TABLE IF NOT EXISTS auth_sessions (
          token_hash TEXT PRIMARY KEY,
          user_id TEXT NOT NULL,
          expires_at TEXT NOT NULL,
          created_at TEXT NOT NULL,
          revoked_at TEXT,
          FOREIGN KEY(user_id) REFERENCES admin_users(id)
        )
        """
    )
    connection.execute(
        """
        CREATE INDEX IF NOT EXISTS idx_auth_sessions_user_id
        ON auth_sessions(user_id)
        """
    )
    connection.execute(
        """
        CREATE TABLE IF NOT EXISTS ai_history (
          id TEXT PRIMARY KEY,
          model TEXT NOT NULL,
          prompt_preview TEXT NOT NULL,
          response_preview TEXT NOT NULL DEFAULT '',
          status TEXT NOT NULL,
          error_message TEXT NOT NULL DEFAULT '',
          latency_ms INTEGER NOT NULL DEFAULT 0,
          client_ip TEXT NOT NULL DEFAULT '',
          created_at TEXT NOT NULL
        )
        """
    )
    connection.execute(
        """
        CREATE INDEX IF NOT EXISTS idx_ai_history_created_at
        ON ai_history(created_at DESC)
        """
    )


def _migration_003_app_users_chat_sessions(connection: sqlite3.Connection) -> None:
    connection.execute(
        """
        CREATE TABLE IF NOT EXISTS app_users (
          id TEXT PRIMARY KEY,
          account_key TEXT NOT NULL UNIQUE,
          provider TEXT NOT NULL DEFAULT '',
          external_id TEXT NOT NULL DEFAULT '',
          nickname TEXT NOT NULL DEFAULT '',
          bio TEXT NOT NULL DEFAULT '',
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          last_seen_at TEXT
        )
        """
    )
    connection.execute(
        """
        CREATE INDEX IF NOT EXISTS idx_app_users_account_key
        ON app_users(account_key)
        """
    )
    connection.execute(
        """
        CREATE TABLE IF NOT EXISTS chat_sessions (
          id TEXT PRIMARY KEY,
          app_user_id TEXT NOT NULL,
          account_key TEXT NOT NULL,
          theme TEXT NOT NULL DEFAULT '',
          summary TEXT NOT NULL DEFAULT '',
          system_prompt TEXT NOT NULL DEFAULT '',
          messages_json TEXT NOT NULL DEFAULT '[]',
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          synced_at TEXT NOT NULL,
          FOREIGN KEY(app_user_id) REFERENCES app_users(id)
        )
        """
    )
    connection.execute(
        """
        CREATE INDEX IF NOT EXISTS idx_chat_sessions_user_updated_at
        ON chat_sessions(app_user_id, updated_at DESC)
        """
    )
    _add_column_if_missing(connection, "ai_history", "app_user_id", "TEXT")
    _add_column_if_missing(connection, "ai_history", "account_key", "TEXT NOT NULL DEFAULT ''")
    connection.execute(
        """
        CREATE INDEX IF NOT EXISTS idx_ai_history_app_user_created_at
        ON ai_history(app_user_id, created_at DESC)
        """
    )


def _migration_004_shared_forest_app_owner(connection: sqlite3.Connection) -> None:
    _add_column_if_missing(connection, "shared_leaves", "app_user_id", "TEXT")
    _add_column_if_missing(connection, "shared_leaves", "account_key", "TEXT NOT NULL DEFAULT ''")
    _add_column_if_missing(connection, "shared_leaves", "owner_nickname", "TEXT NOT NULL DEFAULT ''")
    connection.execute(
        """
        CREATE INDEX IF NOT EXISTS idx_shared_leaves_account_created_at
        ON shared_leaves(account_key, created_at DESC)
        """
    )


def _migration_005_trusted_app_auth(connection: sqlite3.Connection) -> None:
    connection.execute(
        """
        CREATE TABLE IF NOT EXISTS app_identities (
          id TEXT PRIMARY KEY,
          app_user_id TEXT NOT NULL,
          provider TEXT NOT NULL,
          provider_user_id TEXT NOT NULL,
          email TEXT NOT NULL DEFAULT '',
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          FOREIGN KEY(app_user_id) REFERENCES app_users(id),
          UNIQUE(provider, provider_user_id)
        )
        """
    )
    connection.execute(
        """
        CREATE INDEX IF NOT EXISTS idx_app_identities_user_id
        ON app_identities(app_user_id)
        """
    )
    connection.execute(
        """
        CREATE TABLE IF NOT EXISTS app_auth_sessions (
          id TEXT PRIMARY KEY,
          app_user_id TEXT NOT NULL,
          access_token_hash TEXT NOT NULL UNIQUE,
          refresh_token_hash TEXT NOT NULL UNIQUE,
          access_expires_at TEXT NOT NULL,
          refresh_expires_at TEXT NOT NULL,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          revoked_at TEXT,
          device_id_hash TEXT NOT NULL,
          last_used_at TEXT,
          FOREIGN KEY(app_user_id) REFERENCES app_users(id)
        )
        """
    )
    connection.execute(
        """
        CREATE INDEX IF NOT EXISTS idx_app_auth_sessions_user_id
        ON app_auth_sessions(app_user_id)
        """
    )
    connection.execute(
        """
        CREATE INDEX IF NOT EXISTS idx_app_auth_sessions_refresh_hash
        ON app_auth_sessions(refresh_token_hash)
        """
    )
    connection.execute(
        """
        CREATE TABLE IF NOT EXISTS app_identity_migrations (
          id TEXT PRIMARY KEY,
          identity_id TEXT NOT NULL UNIQUE,
          app_user_id TEXT NOT NULL,
          legacy_account_key_hash TEXT NOT NULL,
          migration_type TEXT NOT NULL,
          created_at TEXT NOT NULL,
          FOREIGN KEY(identity_id) REFERENCES app_identities(id),
          FOREIGN KEY(app_user_id) REFERENCES app_users(id)
        )
        """
    )


MIGRATIONS: list[tuple[int, str, Migration]] = [
    (1, "shared_forest_base", _migration_001_shared_forest),
    (2, "auth_admin_ai_history", _migration_002_auth_admin_ai_history),
    (3, "app_users_chat_sessions", _migration_003_app_users_chat_sessions),
    (4, "shared_forest_app_owner", _migration_004_shared_forest_app_owner),
    (5, "trusted_app_auth", _migration_005_trusted_app_auth),
]
