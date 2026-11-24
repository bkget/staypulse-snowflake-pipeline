"""Run sql/30_forecast.sql (Cortex FORECAST, backtest) and fall back to a seasonal baseline if Cortex ML fails."""
import sys
import time
from pathlib import Path

from snowflake.snowpark.exceptions import SnowparkSQLException

from session import make_session

REPO = Path(__file__).resolve().parent.parent
FORECAST_SQL = REPO / "sql" / "30_forecast.sql"
FALLBACK_MARKER = "-- ===== FALLBACK ====="
VIEW_SQL = """CREATE OR REPLACE VIEW STAYPULSE.MARTS.V_DEMAND_ACTUAL_VS_FORECAST AS
SELECT booking_date AS d, bookings_created AS actual, NULL::FLOAT AS yhat, NULL::FLOAT AS lower_bound, NULL::FLOAT AS upper_bound, 'actual' AS method
FROM STAYPULSE.MARTS.FCT_DAILY_BOOKINGS
UNION ALL
SELECT forecast_date, NULL, yhat, lower_bound, upper_bound, method FROM STAYPULSE.MARTS.FCT_DEMAND_FORECAST"""


def statements(sql_text: str):
    for chunk in sql_text.split(";"):
        body = "\n".join(line for line in chunk.splitlines() if not line.strip().startswith("--")).strip()
        if body:
            yield body


def run_block(session, sql_text: str) -> None:
    for stmt in statements(sql_text):  # RESULT_SCAN needs the CALL and the CTAS back to back
        started = time.time()
        rows = session.sql(stmt).collect()
        print(f"{time.time() - started:6.1f}s  {stmt.splitlines()[0][:70]}", flush=True)
        if stmt.lstrip().upper().startswith("SELECT ROUND"):
            print(f"BACKTEST MAPE %: {rows[0][0]}", flush=True)


def main() -> int:
    primary, _, fallback = FORECAST_SQL.read_text(encoding="utf-8").partition(FALLBACK_MARKER)
    session = make_session("SP_TRANSFORMER", "TRANSFORM_WH", "script:run_forecast", schema="MARTS")
    try:
        try:
            run_block(session, primary)
        except SnowparkSQLException as exc:
            if not fallback.strip():
                raise
            print(f"WARNING Cortex FORECAST unavailable, writing the seasonal baseline instead: {exc}", flush=True)
            run_block(session, fallback)
        session.sql(VIEW_SQL).collect()
        summary = session.sql(
            "SELECT method, COUNT(*), MIN(forecast_date), MAX(forecast_date), ROUND(AVG(yhat), 1) "
            "FROM STAYPULSE.MARTS.FCT_DEMAND_FORECAST GROUP BY 1").collect()
        print(f"forecast table: {[tuple(r) for r in summary]}", flush=True)
    finally:
        session.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
