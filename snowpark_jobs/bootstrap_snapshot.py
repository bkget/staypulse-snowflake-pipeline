"""Replay the OLDER listings snapshot into SNAP_LISTING, but only when the snapshot table is empty or missing.

Why the guard: with hard_deletes: invalidate, running the older snapshot after the newer one would close every
listing that exists only in the newer file and corrupt the SCD2 history. So this step is safe to call on every run.
"""
import os
import subprocess
import sys
from pathlib import Path

from snowflake.snowpark.exceptions import SnowparkSQLException

from ingest import SNAPSHOTS
from session import make_session

REPO = Path(__file__).resolve().parent.parent


def snapshot_has_rows(session) -> bool:
    try:
        return session.sql("SELECT COUNT(*) FROM STAYPULSE.SNAPSHOTS.SNAP_LISTING").collect()[0][0] > 0
    except SnowparkSQLException:  # table does not exist yet
        return False


def main() -> int:
    older = SNAPSHOTS[0]
    session = make_session("SP_TRANSFORMER", "TRANSFORM_WH", "script:bootstrap_snapshot", schema="SNAPSHOTS")
    try:
        if snapshot_has_rows(session):
            print(f"SKIP snapshot bootstrap: SNAP_LISTING already has history (older snapshot {older} was replayed before)")
            return 0
    finally:
        session.close()
    print(f"Bootstrapping SCD2 history from the older snapshot {older}")
    cmd = [
        os.environ.get("DBT_BIN", "dbt"), "snapshot",
        "--project-dir", str(REPO / "dbt_project"), "--profiles-dir", str(REPO / "dbt_project"),
        "--vars", f"{{snapshot_date: {older}}}",
    ]
    return subprocess.call(cmd, cwd=REPO)


if __name__ == "__main__":
    sys.exit(main())
