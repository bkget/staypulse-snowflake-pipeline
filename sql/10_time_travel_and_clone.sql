-- Drill A: Time Travel and zero-copy cloning. Run after the first full dbt build, as SP_ENGINEER.
USE ROLE SP_ENGINEER; USE WAREHOUSE TRANSFORM_WH; USE SCHEMA STAYPULSE.MARTS;

SELECT COUNT(*) FROM FCT_BOOKING;                                  -- note it
DELETE FROM FCT_BOOKING WHERE status = 'cancelled';                -- the mistake
SELECT LAST_QUERY_ID();                                            -- copy: the id of the DELETE

SELECT COUNT(*) FROM FCT_BOOKING BEFORE (STATEMENT => '<DELETE_QUERY_ID>');   -- the old count is still there
CREATE OR REPLACE TABLE FCT_BOOKING_RESTORED CLONE FCT_BOOKING BEFORE (STATEMENT => '<DELETE_QUERY_ID>');
ALTER TABLE FCT_BOOKING SWAP WITH FCT_BOOKING_RESTORED;
SELECT COUNT(*) FROM FCT_BOOKING;                                  -- back to the original
DROP TABLE FCT_BOOKING_RESTORED;

DROP TABLE FCT_DAILY_BOOKINGS;
UNDROP TABLE FCT_DAILY_BOOKINGS;                                   -- the other recovery path

-- Zero-copy clone of the whole database, the manual stand-in for the CI step that was cut
USE ROLE SYSADMIN;
CREATE OR REPLACE DATABASE STAYPULSE_DEV CLONE STAYPULSE;          -- if this errors on privileges, run it once as ACCOUNTADMIN
TRUNCATE TABLE STAYPULSE_DEV.MARTS.FCT_BOOKING;
SELECT (SELECT COUNT(*) FROM STAYPULSE_DEV.MARTS.FCT_BOOKING) AS clone_rows,
       (SELECT COUNT(*) FROM STAYPULSE.MARTS.FCT_BOOKING)     AS source_rows;
DROP DATABASE STAYPULSE_DEV;
