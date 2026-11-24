import os
import time
from datetime import date, timedelta
from pathlib import Path

import requests

from generate_bookings import generate
from session import make_session

CITY = "austin"
BASE = "https://data.insideairbnb.com/united-states/tx/austin"
# Older snapshot first. Both dates verified reachable on 2026-11-24. The older one is not listed on the
# public page (it sits in the archive) but the download URL works.
SNAPSHOTS = ["2026-06-22", "2026-09-17"]
STAGE = "@STAYPULSE.RAW.STG_LANDING"
DATA = Path(os.environ.get("DATA_DIR", "data"))


def download(url: str, dest: Path) -> Path:
    if not dest.exists():
        DATA.mkdir(parents=True, exist_ok=True)
        with requests.get(url, stream=True, timeout=120) as r:
            r.raise_for_status()
            with open(dest, "wb") as f:
                for chunk in r.iter_content(1 << 20):
                    f.write(chunk)
    return dest


def staged(session, stage_dir: str) -> bool:
    return len(session.sql(f"LIST {stage_dir}").collect()) > 0


def put_once(session, local: Path, stage_dir: str, compress: bool = False) -> None:
    if not staged(session, stage_dir):
        session.file.put(str(local.resolve()), stage_dir, auto_compress=compress, overwrite=True)


def ensure_table(session, table: str, stage_dir: str) -> None:
    # Header comes from the staged file, every column forced to VARCHAR so schema drift cannot break the load
    session.sql(f"""
        CREATE TABLE IF NOT EXISTS {table} USING TEMPLATE (
          SELECT ARRAY_AGG(OBJECT_CONSTRUCT('COLUMN_NAME', UPPER(COLUMN_NAME), 'TYPE', 'VARCHAR', 'NULLABLE', TRUE))
                 WITHIN GROUP (ORDER BY ORDER_ID)
          FROM TABLE(INFER_SCHEMA(LOCATION => '{stage_dir}', FILE_FORMAT => 'STAYPULSE.RAW.FF_CSV_GZ')))
    """).collect()
    for col, typ in [("_SOURCE_FILE", "VARCHAR"), ("_SOURCE_ROW", "NUMBER"), ("_LOADED_AT", "TIMESTAMP_NTZ")]:
        session.sql(f"ALTER TABLE {table} ADD COLUMN IF NOT EXISTS {col} {typ}").collect()


def copy_csv(session, table: str, stage_dir: str) -> int:
    rows = session.sql(f"""
        COPY INTO {table} FROM {stage_dir}
        FILE_FORMAT = (FORMAT_NAME = 'STAYPULSE.RAW.FF_CSV_GZ') MATCH_BY_COLUMN_NAME = CASE_INSENSITIVE
        INCLUDE_METADATA = (_SOURCE_FILE = METADATA$FILENAME, _SOURCE_ROW = METADATA$FILE_ROW_NUMBER,
                            _LOADED_AT = METADATA$START_SCAN_TIME)
        ON_ERROR = ABORT_STATEMENT
    """).collect()
    return sum(int(r.as_dict().get("rows_loaded", 0)) for r in rows)  # a no-op COPY has no rows_loaded column


def load_entity(session, table: str, stage_root: str, first_dir: str) -> int:
    ensure_table(session, table, first_dir)
    return copy_csv(session, table, stage_root)


def fetch_weather(dest: Path, start: date, end: date) -> Path:
    if not dest.exists():
        DATA.mkdir(parents=True, exist_ok=True)
        params = {
            "latitude": 30.2672, "longitude": -97.7431,
            "start_date": start.isoformat(), "end_date": end.isoformat(),
            "daily": "temperature_2m_max,temperature_2m_min,precipitation_sum", "timezone": "America/Chicago",
        }
        for attempt in range(1, 5):  # a transient network blip should not fail the whole load
            try:
                r = requests.get("https://archive-api.open-meteo.com/v1/archive", timeout=(15, 60), params=params)
                r.raise_for_status()
                break
            except requests.RequestException as exc:
                if attempt == 4:
                    raise
                print(f"Open-Meteo attempt {attempt} failed ({type(exc).__name__}), retrying")
                time.sleep(3 * attempt)
        dest.write_text(r.text, encoding="utf-8")
    return dest


def main() -> None:
    session = make_session("SP_LOADER", "LOAD_WH", "script:ingest")
    newer = date.fromisoformat(SNAPSHOTS[-1])
    local = {}
    for snap in SNAPSHOTS:  # listings: both snapshots feed SCD2
        local[snap] = download(f"{BASE}/{snap}/data/listings.csv.gz", DATA / f"listings_{snap}.csv.gz")
        put_once(session, local[snap], f"{STAGE}/airbnb/listings/snapshot={snap}/")
    reviews = download(f"{BASE}/{newer}/data/reviews.csv.gz", DATA / f"reviews_{newer}.csv.gz")
    put_once(session, reviews, f"{STAGE}/airbnb/reviews/snapshot={newer}/")

    weather = fetch_weather(DATA / f"weather_{CITY}.json", newer - timedelta(days=400), newer)
    put_once(session, weather, f"{STAGE}/weather/", compress=True)

    bookings, payments = generate(local[SNAPSHOTS[-1]], DATA / "sim", end=newer)
    put_once(session, bookings, f"{STAGE}/bookings/", compress=True)
    put_once(session, payments, f"{STAGE}/payments/", compress=True)

    loaded = {
        "listings": load_entity(session, "STAYPULSE.RAW.LISTINGS", f"{STAGE}/airbnb/listings/",
                                f"{STAGE}/airbnb/listings/snapshot={SNAPSHOTS[0]}/"),
        "reviews": load_entity(session, "STAYPULSE.RAW.REVIEWS", f"{STAGE}/airbnb/reviews/",
                               f"{STAGE}/airbnb/reviews/snapshot={newer}/"),
        "bookings": load_entity(session, "STAYPULSE.RAW.BOOKINGS", f"{STAGE}/bookings/", f"{STAGE}/bookings/"),
        "payments": load_entity(session, "STAYPULSE.RAW.PAYMENTS", f"{STAGE}/payments/", f"{STAGE}/payments/"),
    }
    session.sql("CREATE TABLE IF NOT EXISTS STAYPULSE.RAW.WEATHER_JSON "
                "(PAYLOAD VARIANT, _SOURCE_FILE VARCHAR, _LOADED_AT TIMESTAMP_NTZ)").collect()
    w = session.sql(f"""
        COPY INTO STAYPULSE.RAW.WEATHER_JSON (PAYLOAD, _SOURCE_FILE, _LOADED_AT)
        FROM (SELECT $1, METADATA$FILENAME, METADATA$START_SCAN_TIME FROM {STAGE}/weather/)
        FILE_FORMAT = (FORMAT_NAME = 'STAYPULSE.RAW.FF_JSON')
    """).collect()
    loaded["weather"] = sum(int(r.as_dict().get("rows_loaded", 0)) for r in w)
    print(loaded)  # second run: all zeros
    session.close()


if __name__ == "__main__":
    main()
