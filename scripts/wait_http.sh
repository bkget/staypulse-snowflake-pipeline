#!/usr/bin/env bash
# Usage: wait_http.sh <url> <timeout_seconds>
# Polls the url. Stops early with the init logs if airflow-init has failed, and prints diagnostics on timeout.
url=$1; timeout=${2:-120}; waited=0

diagnose() {
  echo "--- container status ---"
  docker compose --profile airflow ps -a 2>&1 | tail -n 12
  echo "--- airflow-init (last 40 lines) ---"
  docker compose --profile airflow logs --no-color --tail 40 airflow-init 2>&1 | tail -n 40
  echo "--- airflow-webserver (last 20 lines) ---"
  docker compose --profile airflow logs --no-color --tail 20 airflow-webserver 2>&1 | tail -n 20
}

until curl -fsS -o /dev/null "$url" 2>/dev/null || python3 -c "import urllib.request as u; u.urlopen('$url', timeout=5)" 2>/dev/null; do
  init_state=$(docker compose --profile airflow ps -a --format '{{.State}} {{.ExitCode}}' airflow-init 2>/dev/null | head -n 1)
  if [[ "$init_state" == exited* && "$init_state" != "exited 0" ]]; then
    echo "airflow-init failed ($init_state)"; diagnose; exit 1
  fi
  if (( waited >= timeout )); then
    echo "timed out after ${timeout}s waiting for $url"; diagnose; exit 1
  fi
  echo "waiting for $url (${waited}s, airflow-init: ${init_state:-starting})"; sleep 5; waited=$(( waited + 5 ))
done
echo "$url is up"
