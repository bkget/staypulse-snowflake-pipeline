-- snowflake_smoke_test.sql  |  run after snowflake_setup.sql as a second block.
-- Every line marked EXPECT FAIL must fail. The Cortex line works only once AI is enabled on the account.
USE ROLE SP_LOADER; USE WAREHOUSE LOAD_WH;
CREATE OR REPLACE TABLE STAYPULSE.RAW.SMOKE (id INT);
INSERT INTO STAYPULSE.RAW.SMOKE VALUES (1);                                  -- OK

USE ROLE SP_TRANSFORMER; USE WAREHOUSE TRANSFORM_WH;
CREATE OR REPLACE TABLE STAYPULSE.STAGING.SMOKE AS SELECT * FROM STAYPULSE.RAW.SMOKE;   -- OK
INSERT INTO STAYPULSE.RAW.SMOKE VALUES (2);                                  -- EXPECT FAIL
SELECT AI_CLASSIFY('Nobody answered the phone at check-in', ['cleanliness', 'check_in']):labels;  -- OK once AI is on

USE ROLE SP_LOADER;
SELECT * FROM STAYPULSE.STAGING.SMOKE;                                       -- EXPECT FAIL

USE ROLE SP_ENGINEER;
DROP TABLE STAYPULSE.RAW.SMOKE;
DROP TABLE STAYPULSE.STAGING.SMOKE;
SHOW WAREHOUSES;                                                             -- both SUSPENDED within a minute or two
