#!/usr/bin/env bash
# Print the per-step table for a run and the overall result.
f="$1/summary.tsv"
[[ -f "$f" ]] || { echo "no steps recorded in $1"; exit 0; }
{
  echo "=== run summary: $1 ==="
  printf '%-22s %-6s %8s\n' STEP STATUS SECONDS
  total=0; failed=0
  while IFS=$'\t' read -r step status secs rc; do
    printf '%-22s %-6s %8s\n' "$step" "$status" "$secs"
    total=$(( total + secs ))
    [[ "$status" == FAIL ]] && failed=1
  done < "$f"
  printf '%-22s %-6s %8s\n' TOTAL "" "$total"
  if (( failed )); then echo "RESULT: FAILED  (see the failing step's log in $1/)"; else echo "RESULT: SUCCESS"; fi
} | tee "$1/summary.txt"
