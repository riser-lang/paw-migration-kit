#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/paw-lib.sh"
dev="${1:-}"
[[ -b "$dev" ]] || die 'Device must be a block device.'
need smartctl; assert_unmounted "$dev"
[[ ${PAW_SIMULATION:-0} != 1 ]] || assert_sim_loop_device "$dev"
report="$PAW_REPORT_DIR/smart-$(basename "$dev").txt"
poll_seconds="${PAW_SMART_POLL_SECONDS:-15}"
max_seconds="${PAW_SMART_MAX_WAIT_SECONDS:-10800}"
[[ "$poll_seconds" =~ ^[1-9][0-9]{0,2}$ && "$max_seconds" =~ ^[1-9][0-9]{0,5}$ ]] || die 'Invalid SMART polling limits.'
mkdir -p "$(dirname "$report")"
: >"$report"

set +e
smartctl -x "$dev" >>"$report" 2>&1
query_rc=$?
set -e
if ((query_rc != 0)) && ! grep -Eiq 'SMART support is: Available|SMART overall-health' "$report"; then
  log WARN 'SMART is unsupported or unreadable; hardware result is WARN, never PASS.'
  exit 2
fi

set +e
health="$(smartctl -H "$dev" 2>&1)"
health_rc=$?
set -e
printf '%s\n' "$health" >>"$report"
if ((health_rc != 0)) || ! grep -Eiq 'SMART overall-health.*(PASSED|OK)|SMART Health Status:[[:space:]]*OK' <<<"$health"; then
  log ERROR 'SMART overall health did not report PASS.'
  exit 1
fi

capabilities="$(smartctl -c "$dev" 2>&1 || true)"
printf '%s\n' "$capabilities" >>"$report"
grep -Eiq 'Self-test execution status' <<<"$capabilities" || { log WARN 'SMART self-test capability is unavailable.'; exit 2; }

run_self_test(){
  local kind="$1" start_output begin status_output selftest_output latest
  if ! start_output="$(smartctl -t "$kind" "$dev" 2>&1)"; then
    printf '%s\n' "$start_output" >>"$report"
    log WARN "SMART $kind self-test could not be started; not PASS."
    return 2
  fi
  printf '%s\n' "$start_output" >>"$report"
  begin=$SECONDS
  while :; do
    status_output="$(smartctl -c "$dev" 2>&1 || true)"
    printf '%s\n' "$status_output" >>"$report"
    if grep -Eiq 'Self-test routine in progress|Self-test.*in progress|Self-test.*% remaining' <<<"$status_output"; then
      ((SECONDS - begin < max_seconds)) || { log WARN "SMART $kind self-test timed out before completion."; return 2; }
      sleep "$poll_seconds"
      continue
    fi
    break
  done
  selftest_output="$(smartctl -l selftest "$dev" 2>&1 || true)"
  printf '%s\n' "$selftest_output" >>"$report"
  latest="$(grep -E '^[[:space:]]*#[[:space:]]*1[[:space:]]' <<<"$selftest_output" | head -n1 || true)"
  if [[ -z "$latest" ]] || ! grep -Eiq 'Completed without error' <<<"$latest"; then
    log ERROR "SMART $kind self-test did not report a completed clean result."
    return 1
  fi
  if [[ "$kind" == short ]] && ! grep -Eiq 'Short offline|Short self-test|Short test' <<<"$latest"; then
    log ERROR 'Latest SMART result is not the requested short test.'
    return 1
  fi
  if [[ "$kind" == long ]] && ! grep -Eiq 'Extended offline|Long offline|Extended self-test' <<<"$latest"; then
    log ERROR 'Latest SMART result is not the requested long test.'
    return 1
  fi
  printf 'PAW_RESULT_%s=PASS\n' "${kind^^}" >>"$report"
}

if grep -Eiq 'No self-test support' <<<"$capabilities" || ! grep -Eiq 'Short self-test routine' <<<"$capabilities"; then
  log WARN 'SMART short self-test unsupported; result is WARN.'
  exit 2
fi
run_self_test short || exit $?

if [[ ${PAW_RUN_LONG_SMART:-0} == 1 ]]; then
  if grep -Eiq 'Extended self-test routine' <<<"$capabilities"; then
    run_self_test long || exit $?
  else
    log WARN 'SMART long self-test unsupported; result is WARN.'
    exit 2
  fi
else
  printf 'PAW_RESULT_LONG=NOT_REQUESTED\n' >>"$report"
fi
log INFO "SMART short test completed and final self-test log was checked; report=$report"
