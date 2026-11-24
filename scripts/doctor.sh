#!/usr/bin/env bash
# Preflight checks. Never prints secret values.
cd "$(dirname "$0")/.."
fail=0
ok()  { printf '  ok    %s\n' "$1"; }
bad() { printf '  FAIL  %s\n' "$1"; fail=1; }
have() { command -v "$1" >/dev/null 2>&1; }

echo "tools"
have docker && ok "docker $(docker --version | awk '{print $3}' | tr -d ,)" || bad "docker not found"
docker compose version >/dev/null 2>&1 && ok "docker compose $(docker compose version --short)" || bad "docker compose plugin not found"
docker info >/dev/null 2>&1 && ok "docker daemon reachable" || bad "cannot talk to the docker daemon (is it running, are you in the docker group?)"

echo ".env"
if [[ -f .env ]]; then
  ok ".env exists"
  for v in SNOWFLAKE_ACCOUNT SNOWFLAKE_USER SNOWFLAKE_KEY_PASSPHRASE; do
    grep -qE "^${v}=.+" .env && ok "$v is set" || bad "$v is empty in .env"
  done
else
  bad ".env missing (cp .env.example .env and fill it in)"
fi

echo "key"
if [[ -f secrets/pipeline_rsa_key.p8 ]]; then
  ok "secrets/pipeline_rsa_key.p8 exists"
  perm=$(stat -c '%a' secrets/pipeline_rsa_key.p8)
  [[ "$perm" == "600" || "$perm" == "400" ]] && ok "key permissions $perm" || bad "key permissions $perm (run: chmod 600 secrets/pipeline_rsa_key.p8)"
else
  bad "secrets/pipeline_rsa_key.p8 missing"
fi

echo "config consistency"
newer=$(grep -E '^SNAPSHOTS' snowpark_jobs/ingest.py | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | tail -1)
dbtvar=$(grep -E "^ +snapshot_date:" dbt_project/dbt_project.yml | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}')
[[ -n "$newer" && "$newer" == "$dbtvar" ]] && ok "newer snapshot $newer matches in ingest.py and dbt_project.yml" \
  || bad "snapshot dates differ: ingest.py=$newer dbt_project.yml=$dbtvar"
git check-ignore -q .env && git check-ignore -q secrets/pipeline_rsa_key.p8 && ok ".env and the key are gitignored" || bad ".env or the key is NOT gitignored"

(( fail )) && { echo "doctor: problems found"; exit 1; } || echo "doctor: all good"
