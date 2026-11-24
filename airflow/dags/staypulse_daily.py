"""StayPulse daily DAG: load -> dbt staging -> snapshot bootstrap -> Snowpark -> dbt core -> forecast.

Snowpark jobs run as subprocesses from their own venv and dbt runs through Astronomer Cosmos from another, so
neither can break Airflow's dependencies. Paths come from environment variables set in docker-compose.yml.
"""
import os
from datetime import datetime, timedelta

from airflow import DAG
from airflow.operators.bash import BashOperator
from cosmos import DbtTaskGroup, ExecutionConfig, ProfileConfig, ProjectConfig, RenderConfig
from cosmos.constants import TestBehavior

HOME = os.environ.get("STAYPULSE_HOME", "/opt/airflow")
DBT_ROOT = f"{HOME}/dbt_project"
JOBS_PYTHON = os.environ.get("JOBS_PYTHON", f"{HOME}/jobs_venv/bin/python")
DBT_BIN = os.environ.get("DBT_BIN", f"{HOME}/dbt_venv/bin/dbt")
CORTEX_FN = os.environ.get("CORTEX_FN", "keyword_stub")  # ai_classify once AI is enabled on the account

project = ProjectConfig(DBT_ROOT, dbt_vars={"cortex_fn": CORTEX_FN})
profile = ProfileConfig(
    profile_name="staypulse",
    target_name="dev",
    profiles_yml_filepath=f"{DBT_ROOT}/profiles.yml",
)
execution = ExecutionConfig(dbt_executable_path=DBT_BIN)


def job(task_id: str, script: str) -> BashOperator:
    return BashOperator(task_id=task_id, bash_command=f"cd {HOME} && {JOBS_PYTHON} snowpark_jobs/{script}")


def dbt_group(group_id: str, select: list[str]) -> DbtTaskGroup:
    return DbtTaskGroup(
        group_id=group_id,
        project_config=project,
        profile_config=profile,
        execution_config=execution,
        render_config=RenderConfig(select=select, test_behavior=TestBehavior.AFTER_EACH),  # each model, then its tests
        operator_args={"install_deps": True, "append_env": True},
    )


with DAG(
    dag_id="staypulse_daily",
    schedule="@daily",
    start_date=datetime(2026, 1, 1),
    catchup=False,
    max_active_runs=1,
    default_args={"retries": 1, "retry_delay": timedelta(minutes=2)},
    tags=["staypulse"],
):
    load_raw = job("load_raw", "ingest.py")  # PUT once, COPY INTO, second run loads zero rows
    dbt_stage = dbt_group("dbt_stage", ["tag:staging"])
    snapshot_bootstrap = job("snapshot_bootstrap", "bootstrap_snapshot.py")  # older snapshot, only when history is empty
    prepare_reviews = job("prepare_reviews", "prepare_reviews.py")  # Snowpark pushdown, only a row count returns
    dbt_core = dbt_group("dbt_core", ["tag:snapshot", "tag:intermediate", "tag:marts"])
    forecast = job("forecast", "run_forecast.py")  # Cortex FORECAST, seasonal baseline if unavailable

    load_raw >> dbt_stage >> snapshot_bootstrap >> prepare_reviews >> dbt_core >> forecast
