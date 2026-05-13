from __future__ import annotations

import os
import sqlite3
from pathlib import Path
from typing import Callable


ROOT = Path(__file__).resolve().parent
DEFAULT_DB_PATH = ROOT / "data" / "echoing.db"
CONFIGURED_DB_PATH = Path(os.environ.get("ECHOING_DB_PATH", str(DEFAULT_DB_PATH))).expanduser()
DB_PATH = CONFIGURED_DB_PATH if CONFIGURED_DB_PATH.is_absolute() else ROOT / CONFIGURED_DB_PATH


def get_connection() -> sqlite3.Connection:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    connection = sqlite3.connect(DB_PATH)
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


MIGRATIONS: list[tuple[int, str, Migration]] = [
    (1, "shared_forest_base", _migration_001_shared_forest),
    (2, "auth_admin_ai_history", _migration_002_auth_admin_ai_history),
]
