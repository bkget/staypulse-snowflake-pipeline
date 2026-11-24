"""Empty the five RAW tables so the next ingest run reloads everything from the stage.

TRUNCATE also clears Snowflake's load history for the table, which is what makes COPY INTO load the already
staged files again. Staged files, the SCD2 snapshot history and the downstream marts are not touched.
"""
import sys

from session import make_session

TABLES = ["LISTINGS", "REVIEWS", "BOOKINGS", "PAYMENTS", "WEATHER_JSON"]


def count(session, table: str) -> int:
    return session.sql(f"SELECT COUNT(*) FROM STAYPULSE.RAW.{table}").collect()[0][0]


def main() -> int:
    session = make_session("SP_LOADER", "LOAD_WH", "script:reload_raw")
    try:
        for table in TABLES:
            before = count(session, table)
            session.sql(f"TRUNCATE TABLE STAYPULSE.RAW.{table}").collect()
            print(f"{table:<13} {before:>9} rows -> {count(session, table)}", flush=True)
    finally:
        session.close()
    print("RAW is empty. The next ingest will reload from the stage and print real counts.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
