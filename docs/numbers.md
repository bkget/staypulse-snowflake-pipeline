# Key figures

Figures to quote when presenting the project. Filled rows come from the verified run on 2026-11-24 (see the logs
under `logs/`). Empty rows need a drill or a query that has not been run yet. Quote only measured values, never
estimates.

| Figure | Where it comes from | Value | What it shows |
| --- | --- | --- | --- |
| Rows per RAW table, ingest seconds, second-run rows (zero) | `ingest.py` output | listings 22,406, reviews 653,461, bookings 5,008, payments 5,000, weather 1. Second run: 0 in every table. First-load seconds not recorded | Loading, and why reruns are safe |
| Credits by warehouse, share of trial used | WAREHOUSE_METERING_HISTORY | | Cost control |
| AI-services credits, credits per review | METERING_DAILY_HISTORY / 300 | | What Cortex costs and how it is capped |
| SCD2 versions, changed listings, closed listings | proof queries over `SNAP_LISTING` | 21,621 versions in `SNAP_LISTING` | History modelling |
| MERGE seconds and bytes vs delete+insert | Query History | | Choosing an incremental strategy |
| Partitions scanned / total, unsorted vs sorted, seconds | Drill B1 | | Diagnosing a slow scan |
| Join rows out, bad vs good, seconds | Drill B2 | | Reading a Query Profile |
| Cold, warm, result-cache seconds | Drill B3 | | Snowflake's caching layers |
| Rows before, after delete, after restore; clone seconds | Drill A | | Time Travel vs zero-copy cloning |
| Backtest MAPE and the method used | `sql/30_forecast.sql` | 19.3 %, `cortex_forecast`, 14-day horizon | Forecast quality, and the fallback |
| dbt tests passed / failed, build seconds | `dbt build` log | 19 of 19 nodes passed (models, snapshot, tests), 0 failed, 14.4 s | Data quality guarantees |
| End-to-end pipeline seconds | `logs/<run-id>/summary.txt` | 442 s including a 184 s image build, 258 s without it | Duration of a full run |
