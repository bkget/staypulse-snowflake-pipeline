-- Run as SP_TRANSFORMER after fct_daily_bookings is built (Airflow runs this file, split on semicolons,
-- so keep semicolons out of comments). Everything below the FALLBACK marker runs only if the part above fails.
USE ROLE SP_TRANSFORMER;
USE WAREHOUSE TRANSFORM_WH;
USE SCHEMA STAYPULSE.MARTS;

CREATE OR REPLACE VIEW V_BOOKINGS_TRAIN AS
SELECT booking_date::TIMESTAMP_NTZ AS ds, bookings_created::FLOAT AS y FROM FCT_DAILY_BOOKINGS;

CREATE OR REPLACE VIEW V_BOOKINGS_TRAIN_BT AS
SELECT ds, y FROM V_BOOKINGS_TRAIN WHERE ds <= (SELECT MAX(ds) - INTERVAL '14 days' FROM V_BOOKINGS_TRAIN);

-- Backtest first: train without the last 14 days, forecast them, compare with what happened
CREATE OR REPLACE SNOWFLAKE.ML.FORECAST DEMAND_FORECAST_BT(
  INPUT_DATA => SYSTEM$REFERENCE('VIEW', 'STAYPULSE.MARTS.V_BOOKINGS_TRAIN_BT'),
  TIMESTAMP_COLNAME => 'DS', TARGET_COLNAME => 'Y');
CALL DEMAND_FORECAST_BT!FORECAST(FORECASTING_PERIODS => 14);
CREATE OR REPLACE TABLE FORECAST_BACKTEST AS
SELECT ts::DATE AS d, forecast AS yhat, lower_bound, upper_bound FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

-- Production model on all days, 14 days ahead
CREATE OR REPLACE SNOWFLAKE.ML.FORECAST DEMAND_FORECAST(
  INPUT_DATA => SYSTEM$REFERENCE('VIEW', 'STAYPULSE.MARTS.V_BOOKINGS_TRAIN'),
  TIMESTAMP_COLNAME => 'DS', TARGET_COLNAME => 'Y');
CALL DEMAND_FORECAST!FORECAST(FORECASTING_PERIODS => 14);
CREATE OR REPLACE TABLE FCT_DEMAND_FORECAST AS
SELECT ts::DATE AS forecast_date, forecast AS yhat, lower_bound, upper_bound,
       'cortex_forecast' AS method, CURRENT_TIMESTAMP() AS created_at
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

-- The headline number: mean absolute percentage error over the held-out 14 days
SELECT ROUND(AVG(ABS(a.bookings_created - f.yhat) / NULLIF(a.bookings_created, 0)) * 100, 1) AS mape_pct
FROM FORECAST_BACKTEST f JOIN FCT_DAILY_BOOKINGS a ON a.booking_date = f.d;

-- ===== FALLBACK =====
CREATE OR REPLACE TABLE STAYPULSE.MARTS.FCT_DEMAND_FORECAST AS
WITH last_day AS (SELECT MAX(booking_date) AS d FROM STAYPULSE.MARTS.FCT_DAILY_BOOKINGS),
horizon AS (
  SELECT DATEADD(day, ROW_NUMBER() OVER (ORDER BY SEQ4()), (SELECT d FROM last_day)) AS forecast_date
  FROM TABLE(GENERATOR(ROWCOUNT => 14))),
hist AS (
  SELECT booking_date, bookings_created FROM STAYPULSE.MARTS.FCT_DAILY_BOOKINGS
  WHERE booking_date > DATEADD(day, -28, (SELECT d FROM last_day)))
SELECT h.forecast_date, AVG(x.bookings_created) AS yhat, MIN(x.bookings_created) AS lower_bound,
       MAX(x.bookings_created) AS upper_bound, 'seasonal_naive_4w' AS method, CURRENT_TIMESTAMP() AS created_at
FROM horizon h JOIN hist x ON DAYOFWEEK(x.booking_date) = DAYOFWEEK(h.forecast_date)
GROUP BY h.forecast_date;

CREATE OR REPLACE VIEW STAYPULSE.MARTS.V_DEMAND_ACTUAL_VS_FORECAST AS
SELECT booking_date AS d, bookings_created AS actual, NULL::FLOAT AS yhat, NULL::FLOAT AS lower_bound, NULL::FLOAT AS upper_bound, 'actual' AS method
FROM STAYPULSE.MARTS.FCT_DAILY_BOOKINGS
UNION ALL
SELECT forecast_date, NULL, yhat, lower_bound, upper_bound, method FROM STAYPULSE.MARTS.FCT_DEMAND_FORECAST;
