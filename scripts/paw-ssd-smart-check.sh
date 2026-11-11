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
smart_status='WARN'; smart_class='SMART_NOT_CLASSIFIED'; smart_reason='SMART check did not reach a classified result.'
write_smart_report(){
  python3 - "$PAW_REPORT_DIR/smart-$(basename "$dev").json" "$smart_status" "$smart_class" "$smart_reason" "$report" <<'PY' || true
import datetime,json,os,sys
path,status,classification,reason,raw=sys.argv[1:]
doc={"schema":"paw.smart-result.v1","status":status,"classification":classification,
 "reason":reason,"device":os.path.basename(raw).replace("smart-","").replace(".txt",""),
 "raw_report_sha256":__import__("hashlib").sha256(open(raw,"rb").read()).hexdigest() if os.path.exists(raw) else None,
 "updated_at":datetime.datetime.now(datetime.timezone.utc).isoformat()}
tmp=path+".tmp"
with open(tmp,"w",encoding="utf-8") as h: json.dump(doc,h,indent=2)
os.chmod(tmp,0o600); os.replace(tmp,path)
PY
}
trap 'write_smart_report' EXIT

set +e
smartctl -x "$dev" >>"$report" 2>&1
query_rc=$?
set -e
if ((query_rc != 0)) && ! grep -Eiq 'SMART support is: Available|SMART overall-health' "$report"; then
  smart_status='WARN'; smart_class='SMART_UNSUPPORTED_OR_UNREADABLE'; smart_reason='SMART query failed and no health line was present.'
  log WARN 'SMART is unsupported or unreadable; hardware result is WARN, never PASS.'
  exit 2
fi

set +e
health="$(smartctl -H "$dev" 2>&1)"
health_rc=$?
set -e
printf '%s\n' "$health" >>"$report"
if ((health_rc != 0)) || ! grep -Eiq 'SMART overall-health.*(PASSED|OK)|SMART Health Status:[[:space:]]*OK' <<<"$health"; then
  smart_status='FAIL'; smart_class='SMART_HEALTH_FAILED'; smart_reason='SMART overall-health did not report PASS.'
  log ERROR 'SMART overall health did not report PASS.'
  exit 1
fi

capabilities="$(smartctl -c "$dev" 2>&1 || true)"
printf '%s\n' "$capabilities" >>"$report"
grep -Eiq 'Self-test execution status' <<<"$capabilities" || { smart_status='WARN'; smart_class='SMART_SELFTEST_CAPABILITY_UNAVAILABLE'; smart_reason='No self-test execution status in SMART capabilities.'; log WARN 'SMART self-test capability is unavailable.'; exit 2; }

run_self_test(){
  local kind="$1" start_output begin status_output selftest_output latest
  if ! start_output="$(smartctl -t "$kind" "$dev" 2>&1)"; then
    printf '%s\n' "$start_output" >>"$report"
    smart_status='WARN'; smart_class='SMART_SELFTEST_NOT_STARTED'; smart_reason="SMART $kind self-test could not be started."
    log WARN "SMART $kind self-test could not be started; not PASS."
    return 2
  fi
  printf '%s\n' "$start_output" >>"$report"
  begin=$SECONDS
  while :; do
    status_output="$(smartctl -c "$dev" 2>&1 || true)"
    printf '%s\n' "$status_output" >>"$report"
    if grep -Eiq 'Self-test routine in progress|Self-test.*in progress|Self-test.*% remaining' <<<"$status_output"; then
      ((SECONDS - begin < max_seconds)) || { smart_status='WARN'; smart_class='SMART_SELFTEST_TIMEOUT'; smart_reason="SMART $kind self-test timed out."; log WARN "SMART $kind self-test timed out before completion."; return 2; }
      sleep "$poll_seconds"
      continue
    fi
    break
  done
  selftest_output="$(smartctl -l selftest "$dev" 2>&1 || true)"
  printf '%s\n' "$selftest_output" >>"$report"
  latest="$(grep -E '^[[:space:]]*#[[:space:]]*1[[:space:]]' <<<"$selftest_output" | head -n1 || true)"
  if [[ -z "$latest" ]] || ! grep -Eiq 'Completed without error' <<<"$latest"; then
    smart_status='FAIL'; smart_class='SMART_SELFTEST_NOT_CLEAN'; smart_reason="SMART $kind self-test did not report a completed clean result."
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
  smart_status='WARN'; smart_class='SMART_SHORT_SELFTEST_UNSUPPORTED'; smart_reason='SMART short self-test is unsupported.'
  log WARN 'SMART short self-test unsupported; result is WARN.'
  exit 2
fi
run_self_test short || exit $?

if [[ ${PAW_RUN_LONG_SMART:-0} == 1 ]]; then
  if grep -Eiq 'Extended self-test routine' <<<"$capabilities"; then
    run_self_test long || exit $?
  else
    smart_status='WARN'; smart_class='SMART_LONG_SELFTEST_UNSUPPORTED'; smart_reason='SMART long self-test is unsupported.'
    log WARN 'SMART long self-test unsupported; result is WARN.'
    exit 2
  fi
else
  printf 'PAW_RESULT_LONG=NOT_REQUESTED\n' >>"$report"
fi
smart_status='PASS'; smart_class='SMART_SELFTEST_CLEAN'; smart_reason='Requested SMART self-test completed without error.'
log INFO "SMART short test completed and final self-test log was checked; report=$report"
