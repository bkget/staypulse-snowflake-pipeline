#!/usr/bin/env bash
# Run one named step: timestamp every line, tee to <log_dir>/<step>.log, record status and duration.
# Usage: step.sh <log_dir> <step_name> -- <command...>
set -uo pipefail
log_dir=$1; step=$2; shift 2
[[ "${1:-}" == "--" ]] && shift
mkdir -p "$log_dir"
ln -sfn "$(basename "$log_dir")" "$(dirname "$log_dir")/latest"
log="$log_dir/$step.log"
if [[ -t 1 ]]; then B=$'\033[1m'; G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'; N=$'\033[0m'; else B=; G=; R=; Y=; N=; fi
now() { date '+%Y-%m-%d %H:%M:%S'; }
start=$(date +%s)
printf '%s==> [%s] %s%s\n' "$B" "$(now)" "$step" "$N"
printf '# step: %s\n# started: %s\n# command: %s\n\n' "$step" "$(now)" "$*" > "$log"
"$@" 2>&1 | while IFS= read -r line; do printf '%(%H:%M:%S)T  %s\n' -1 "$line"; done | tee -a "$log"
rc=${PIPESTATUS[0]}
secs=$(( $(date +%s) - start ))
if (( rc == 0 )); then status=OK; else status=FAIL; fi
printf '%s\t%s\t%s\t%s\n' "$step" "$status" "$secs" "$rc" >> "$log_dir/summary.tsv"
printf '\n# finished: %s  status=%s  exit=%s  duration=%ss\n' "$(now)" "$status" "$rc" "$secs" >> "$log"
if (( rc == 0 )); then
  printf '%s<== %s OK in %ss%s  (log: %s)\n\n' "$G" "$step" "$secs" "$N" "$log"
else
  printf '%s<== %s FAILED (exit %s) after %ss%s\n' "$R" "$step" "$rc" "$secs" "$N"
  printf '%s--- last 25 lines of %s ---%s\n' "$Y" "$log" "$N"
  tail -n 25 "$log"
  exit "$rc"
fi
