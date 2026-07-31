"""Smoke check for the 2026-07-30 logic fixes (not a pytest module).

Verifies against a temp SQLite database:
1. Liking a hidden leaf is rejected (status-aware increment_like).
2. Liking a deleted leaf is rejected.
3. restore() clears moderation flag/reason.
4. Liking a visible leaf still works.
"""
from __future__ import annotations

import os
import sys
import tempfile
from pathlib import Path

BACKEND = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BACKEND))

TMP = Path(tempfile.mkdtemp(prefix="echoing_smoke_"))
os.environ["ECHOING_DB_PATH"] = str(TMP / "smoke.db")

import database  # noqa: E402

database.init_database()

from repositories.shared_forest_repository import SharedForestRepository  # noqa: E402
from database import get_connection  # noqa: E402

failures: list[str] = []

with get_connection() as conn:
    repo = SharedForestRepository(conn)
    leaf = repo.create_leaf(
        leaf_id="leaf_test1",
        content="hello",
        nickname="tester",
        ai_response="",
        moderation_flag="clean",
        moderation_reason="",
        created_at="2026-07-30 10:00:00",
        app_user_id="app_u1",
        account_key="k1",
        owner_nickname="tester",
    )
    assert leaf["id"] == "leaf_test1"

    # 1. visible leaf can be liked
    liked = repo.increment_like("leaf_test1", "2026-07-30 10:01:00")
    if liked is None or int(liked["like_count"]) != 1:
        failures.append(f"visible like failed: {liked}")

    # 2. hidden leaf cannot be liked
    repo.hide_for_moderation("leaf_test1", "manual review", "2026-07-30 10:02:00")
    liked_hidden = repo.increment_like("leaf_test1", "2026-07-30 10:03:00")
    if liked_hidden is not None:
        failures.append(f"hidden leaf was likable: {liked_hidden}")

    # 3. restore clears moderation fields, leaf likable again
    restored = repo.restore("leaf_test1", "2026-07-30 10:04:00")
    if not restored:
        failures.append("restore returned False")
    row = conn.execute(
        "SELECT status, moderation_flag, moderation_reason FROM shared_leaves WHERE id = 'leaf_test1'"
    ).fetchone()
    if row["status"] != "visible" or row["moderation_flag"] != "clean" or row["moderation_reason"] != "":
        failures.append(f"restore did not clear moderation fields: {dict(row)}")
    liked_restored = repo.increment_like("leaf_test1", "2026-07-30 10:05:00")
    if liked_restored is None or int(liked_restored["like_count"]) != 2:
        failures.append(f"restored leaf not likable or count wrong: {liked_restored}")

    # 4. deleted leaf cannot be liked
    repo.soft_delete("leaf_test1", "2026-07-30 10:06:00", "admin")
    liked_deleted = repo.increment_like("leaf_test1", "2026-07-30 10:07:00")
    if liked_deleted is not None:
        failures.append(f"deleted leaf was likable: {liked_deleted}")

    # 5. liking a non-existent leaf returns None
    if repo.increment_like("leaf_nope", "2026-07-30 10:08:00") is not None:
        failures.append("non-existent leaf likable")

if failures:
    print("SMOKE FAILURES:")
    for failure in failures:
        print(" -", failure)
    sys.exit(1)
print("SMOKE OK: all 5 checks passed")
