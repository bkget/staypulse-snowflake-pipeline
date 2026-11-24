-- Drill B: Query Profile lab. Run after the first full dbt build, as SP_ENGINEER.
-- The real data is too small to prune, so build a big table inside Snowflake (no download).
USE ROLE SP_ENGINEER; USE WAREHOUSE TRANSFORM_WH; USE SCHEMA STAYPULSE.MARTS;

CREATE OR REPLACE TABLE LAB_EVENTS AS
WITH ids AS (SELECT ARRAY_AGG(DISTINCT listing_id) AS a FROM FCT_BOOKING)
SELECT SEQ4() AS event_id,
       GET(ids.a, MOD(UNIFORM(0, 1000000, RANDOM(1)), ARRAY_SIZE(ids.a)))::NUMBER AS listing_id,
       DATEADD(second, UNIFORM(0, 150 * 86400, RANDOM(2)), '2026-01-01'::TIMESTAMP_NTZ) AS event_ts,
       RANDSTR(8, RANDOM(3)) AS session_key,
       UNIFORM(1, 500, RANDOM(4))::NUMBER(10, 2) AS amount
FROM ids, TABLE(GENERATOR(ROWCOUNT => 10000000));

CREATE OR REPLACE TABLE LAB_EVENTS_SORTED AS SELECT * FROM LAB_EVENTS ORDER BY event_ts;   -- manual stand-in for clustering
ALTER SESSION SET USE_CACHED_RESULT = FALSE;

-- Drill 1: pruning. Compare partitions scanned vs total in Query Profile.
SELECT COUNT(*), SUM(amount) FROM LAB_EVENTS        WHERE event_ts >= '2026-03-01' AND event_ts < '2026-03-04';
SELECT COUNT(*), SUM(amount) FROM LAB_EVENTS_SORTED WHERE event_ts >= '2026-03-01' AND event_ts < '2026-03-04';
SELECT SYSTEM$CLUSTERING_INFORMATION('STAYPULSE.MARTS.LAB_EVENTS', '(event_ts)');
SELECT SYSTEM$CLUSTERING_INFORMATION('STAYPULSE.MARTS.LAB_EVENTS_SORTED', '(event_ts)');

-- Drill 2, bad: fan-out then DISTINCT
SELECT b.listing_id, COUNT(DISTINCT e.event_id) AS events, COUNT(DISTINCT b.booking_id) AS bookings
FROM FCT_BOOKING b JOIN LAB_EVENTS e ON e.listing_id = b.listing_id AND e.event_ts < '2026-02-01'
GROUP BY 1;

-- Drill 2, good: aggregate each side, then join one row to one row
WITH ev AS (SELECT listing_id, COUNT(*) AS events FROM LAB_EVENTS WHERE event_ts < '2026-02-01' GROUP BY 1),
     bk AS (SELECT listing_id, COUNT(*) AS bookings FROM FCT_BOOKING GROUP BY 1)
SELECT bk.listing_id, ev.events, bk.bookings FROM bk JOIN ev ON ev.listing_id = bk.listing_id;

-- Drill 3: caching. Suspend, run the pruning query cold, run it warm, then allow the result cache and run it again.
ALTER WAREHOUSE TRANSFORM_WH SUSPEND;
SELECT COUNT(*), SUM(amount) FROM LAB_EVENTS_SORTED WHERE event_ts >= '2026-03-01' AND event_ts < '2026-03-04';   -- cold
SELECT COUNT(*), SUM(amount) FROM LAB_EVENTS_SORTED WHERE event_ts >= '2026-03-01' AND event_ts < '2026-03-04';   -- warm
ALTER SESSION SET USE_CACHED_RESULT = TRUE;
SELECT COUNT(*), SUM(amount) FROM LAB_EVENTS_SORTED WHERE event_ts >= '2026-03-01' AND event_ts < '2026-03-04';   -- result cache

-- Cleanup
DROP TABLE LAB_EVENTS;
DROP TABLE LAB_EVENTS_SORTED;
