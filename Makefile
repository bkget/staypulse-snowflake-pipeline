# StayPulse Lite: run the whole pipeline in Docker, with a timestamped log per step.
#   make help        list targets
#   make pipeline    doctor -> build -> login check -> ingest -> dbt -> Snowpark -> dbt -> forecast
# Every step writes logs/<run-id>/<step>.log (latest run: logs/latest) and a summary table at the end.

SHELL := /bin/bash
.DEFAULT_GOAL := help
.NOTPARALLEL:

export HOST_UID := $(shell id -u)
export HOST_GID := $(shell id -g)

RUN_ID    ?= $(shell date +%Y%m%d-%H%M%S)
LOG_DIR   := logs/$(RUN_ID)
STEP      := bash scripts/step.sh $(LOG_DIR)

# AI_CLASSIFY is blocked on Snowflake trial accounts. Use keyword_stub until a payment method is added,
# then run: make pipeline CORTEX_FN=ai_classify
CORTEX_FN ?= keyword_stub
export CORTEX_FN

DC        := docker compose
RUNNER    := $(DC) --profile pipeline run --rm -T runner
DBT       := $(RUNNER) dbt
DBT_DIR   := --project-dir dbt_project
AF        := $(DC) --profile airflow

PIPELINE_STEPS := doctor build check ingest dbt-deps dbt-staging snapshot-bootstrap prepare-reviews dbt-core forecast

.PHONY: help pipeline $(PIPELINE_STEPS) reload-raw dbt-test shell summary logs clean clean-logs \
        demo airflow-up airflow-down airflow-run airflow-trigger airflow-logs airflow-errors airflow-reset

help: ## Show this help
	@awk 'BEGIN{FS=":.*## "} /^[a-zA-Z0-9_-]+:.*## /{printf "  \033[1m%-20s\033[0m %s\n",$$1,$$2}' $(MAKEFILE_LIST)

# ---------------------------------------------------------------- pipeline (one-shot runner container)
pipeline: ## Run everything end to end in Docker (add CORTEX_FN=ai_classify once AI is enabled)
	@mkdir -p $(LOG_DIR)
	@echo "run id: $(RUN_ID)   logs: $(LOG_DIR)/   cortex_fn: $(CORTEX_FN)"
	@$(MAKE) --no-print-directory RUN_ID=$(RUN_ID) $(PIPELINE_STEPS); rc=$$?; bash scripts/summary.sh $(LOG_DIR); exit $$rc

doctor: ## Preflight: docker, .env, key, config consistency
	@$(STEP) doctor -- bash scripts/doctor.sh

build: ## Build the runner image
	@$(STEP) build -- $(DC) --profile pipeline build --progress=plain runner

check: ## Log in to Snowflake as both pipeline roles
	@$(STEP) check-connection -- $(RUNNER) python snowpark_jobs/check_connection.py

ingest: ## Download Inside Airbnb + Open-Meteo, generate bookings, PUT and COPY INTO RAW (idempotent)
	@$(STEP) ingest -- $(RUNNER) python snowpark_jobs/ingest.py

reload-raw: ## Empty the RAW tables and reload them from the stage (asks first; CONFIRM=yes skips the prompt)
	@if [ "$(CONFIRM)" != "yes" ]; then \
	  echo "This TRUNCATES the 5 RAW tables in STAYPULSE (staged files and marts are kept), then reloads them."; \
	  read -r -p "Type 'yes' to continue: " ans; \
	  [ "$$ans" = "yes" ] || { echo "aborted, nothing changed"; exit 1; }; \
	fi
	@mkdir -p $(LOG_DIR)
	@$(STEP) reload-truncate -- $(RUNNER) python snowpark_jobs/reload_raw.py
	@$(STEP) reload-ingest -- $(RUNNER) python snowpark_jobs/ingest.py
	@bash scripts/summary.sh $(LOG_DIR)

dbt-deps: ## Install dbt packages
	@$(STEP) dbt-deps -- $(DBT) deps $(DBT_DIR)

dbt-staging: ## Build and test the staging views
	@$(STEP) dbt-staging -- $(DBT) build $(DBT_DIR) --select tag:staging

snapshot-bootstrap: ## Replay the older listings snapshot once (skipped when history already exists)
	@$(STEP) snapshot-bootstrap -- $(RUNNER) python snowpark_jobs/bootstrap_snapshot.py

prepare-reviews: ## Snowpark pushdown: clean, dedupe and sample 300 reviews
	@$(STEP) prepare-reviews -- $(RUNNER) python snowpark_jobs/prepare_reviews.py

dbt-core: ## Snapshot (newer), intermediate and marts models, with tests
	@$(STEP) dbt-core -- $(DBT) build $(DBT_DIR) --exclude tag:staging --vars "{cortex_fn: $(CORTEX_FN)}"

forecast: ## Cortex FORECAST on daily bookings (seasonal baseline if Cortex ML is unavailable)
	@$(STEP) forecast -- $(RUNNER) python snowpark_jobs/run_forecast.py

dbt-test: ## Run all dbt tests only
	@$(STEP) dbt-test -- $(DBT) test $(DBT_DIR)

shell: ## Interactive shell in the runner container
	@$(DC) --profile pipeline run --rm runner bash

summary: ## Show the summary of the latest run
	@bash scripts/summary.sh logs/latest

logs: ## Tail every step log of the latest run
	@tail -n +1 logs/latest/*.log | less -R

# ---------------------------------------------------------------- Airflow + Cosmos (long-running stack)
demo: ## One command: start postgres, airflow-init, webserver, scheduler; wait until healthy; print URL and login
	@mkdir -p logs/airflow data
	@$(STEP) demo-doctor -- bash scripts/doctor.sh
	@$(STEP) demo-up -- $(AF) up -d --build
	@$(STEP) demo-wait -- bash scripts/wait_http.sh http://localhost:8080/health 420
	@$(STEP) demo-status -- $(AF) ps
	@pw=$$(grep -E '^AIRFLOW_ADMIN_PASSWORD=.' .env 2>/dev/null | cut -d= -f2-); \
	 echo ""; echo "Airflow is up:"; \
	 echo "  UI        http://localhost:8080"; \
	 echo "  login     admin / $${pw:-admin}"; \
	 echo "  next      make airflow-errors   (DAG import check)"; \
	 echo "            make airflow-run      (run the whole DAG once)"; \
	 echo "            make airflow-down     (stop, keeps the metadata)"; echo ""

airflow-up: demo ## Alias of demo

airflow-errors: ## Show DAG import errors (should print nothing)
	@$(STEP) airflow-errors -- $(AF) exec -T airflow-scheduler airflow dags list-import-errors

airflow-run: ## Run the whole DAG once, in the foreground, through Airflow + Cosmos
	@$(STEP) airflow-dag-test -- $(AF) exec -T airflow-scheduler airflow dags test staypulse_daily

airflow-trigger: ## Unpause and trigger the DAG through the scheduler
	@$(STEP) airflow-trigger -- bash -c '$(AF) exec -T airflow-scheduler airflow dags unpause staypulse_daily && $(AF) exec -T airflow-scheduler airflow dags trigger staypulse_daily'

airflow-logs: ## Follow scheduler logs
	@$(AF) logs -f --tail 100 airflow-scheduler

airflow-down: ## Stop Airflow (keeps the metadata database)
	@$(STEP) airflow-down -- $(AF) down

airflow-reset: ## Stop Airflow and delete its metadata database
	@$(STEP) airflow-reset -- $(AF) down -v

# ---------------------------------------------------------------- housekeeping
clean: ## Remove dbt build output and packages
	rm -rf dbt_project/target dbt_project/dbt_packages dbt_project/logs

clean-logs: ## Delete all run logs
	rm -rf logs
