#!/usr/bin/env bash
# Unit/integration tests for the SSD identity and read-only health gates.
# They run against /dev/loop0 with mocked lsblk/blockdev/smartctl/badblocks so
# every negative case is deterministic and never touches real hardware.
set -Eeuo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
out="${PAW_ARTIFACT_DIR:-$PWD/artifacts}"
work="$root/tests/virtual/ssd-health-run"
mock="$work/mockbin"; state="$work/state"
rm -rf "$work"; mkdir -p "$mock" "$state/configs" "$state/reports" "$state/logs" "$out"
export PAW_ROOT="$root" PAW_STATE_DIR="$state" PAW_CONFIG_DIR="$state/configs" PAW_REPORT_DIR="$state/reports" PAW_LOG_DIR="$state/logs"
export PATH="$mock:$PATH" PAW_SIMULATION=0
report="$out/ssd-health-test-report.txt"; passed=0; failed=0
pass(){ printf 'PASS %s\n' "$1" >>"$report"; passed=$((passed+1)); }
fail(){ printf 'FAIL %s\n' "$1" >>"$report"; failed=$((failed+1)); }
printf 'SSD identity and read-only health gate tests\n' >"$report"

cat >"$mock/lsblk" <<'MOCK'
#!/usr/bin/env bash
args=" $* "
case "$args" in
  *" -dn -o SERIAL "*) printf '%s\n' "${PAW_MOCK_SERIAL:-PAW-SSD-TEST}" ;;
  *" -dn -o MODEL "*) printf '%s\n' "${PAW_MOCK_MODEL:-Samsung SSD 860}" ;;
  *" -dn -o TYPE "*) printf 'disk\n' ;;
  *" -dn -o PKNAME "*) printf '\n' ;;
  *" MOUNTPOINT "*|*" MOUNTPOINTS "*|*" -o MOUNTPOINT "*|*" -o MOUNTPOINTS "*)
    [[ ${PAW_MOCK_MOUNTED:-0} == 1 ]] && printf '/mnt/target\n' || printf '\n' ;;
  *" -nrpo NAME,LABEL "*) printf '\n' ;;
  *) printf '\n' ;;
esac
MOCK
cat >"$mock/blockdev" <<'MOCK'
#!/usr/bin/env bash
printf '%s\n' "${PAW_MOCK_CAPACITY:-240000000000}"
MOCK
cat >"$mock/findmnt" <<'MOCK'
#!/usr/bin/env bash
if [[ ${PAW_MOCK_LIVE_MEDIUM:-0} == 1 ]]; then printf '/dev/loop0[/live]\n'; exit 0; fi
exit 1
MOCK
cat >"$mock/dmesg" <<'MOCK'
#!/usr/bin/env bash
[[ ${PAW_MOCK_DMESG_ERROR:-0} == 1 ]] && echo 'ata1.00: failed command: READ FPDMA QUEUED' || true
MOCK
cat >"$mock/sensors" <<'MOCK'
#!/usr/bin/env bash
printf 'Package id 0:  +45.0°C  (high = +80.0°C)\n'
MOCK
cat >"$mock/badblocks" <<'MOCK'
#!/usr/bin/env bash
[[ ${PAW_MOCK_SCAN_FAIL:-0} == 1 ]] && exit 1
echo 'Pass completed, 0 bad blocks found.'
MOCK
cat >"$mock/smartctl" <<'MOCK'
#!/usr/bin/env bash
mode="${PAW_MOCK_SMART_MODE:-pass}"
case "$1" in
  -x) echo 'SMART support is: Available - device has SMART capability.'
      echo 'ID# ATTRIBUTE_NAME FLAG VALUE WORST THRESH TYPE UPDATED WHEN_FAILED RAW_VALUE'
      echo '  5 Reallocated_Sector_Ct 0x0033 100 100 010 Pre-fail Always - 0'
      echo '194 Temperature_Celsius 0x0022 035 040 000 Old_age Always - '"${PAW_MOCK_TEMP:-35}"' (Min/Max 20/45)'
      echo '199 UDMA_CRC_Error_Count 0x0032 200 200 000 Old_age Always - '"${PAW_MOCK_CRC:-0}" ;;
  -H) if [[ "$mode" == healthfail ]]; then echo 'SMART overall-health self-assessment test result: FAILED!'; exit 1; fi
      echo 'SMART overall-health self-assessment test result: PASSED' ;;
  -c) echo 'Self-test execution status: 0'
      echo 'Short self-test routine recommended polling time: 1 minutes'
      echo 'Extended self-test routine recommended polling time: 10 minutes' ;;
  -t) echo 'Please wait 1 minutes for test to complete.' ;;
  -l) if [[ "$mode" == selffail ]]; then echo '# 1  Short offline  Completed: read failure  90%  1234 -'; else echo '# 1  Short offline  Completed without error  00%  1234 -'; fi ;;
  *) exit 0 ;;
esac
MOCK
chmod 0755 "$mock/"*
cat >"$state/configs/target-ssd.json" <<'JSON'
{"approved": true, "device_path": "/dev/loop0", "model": "Samsung SSD 860", "capacity_bytes": 240000000000, "serial": "PAW-SSD-TEST"}
JSON
cat >"$state/memtest-attestation.json" <<JSON
{"schema":"paw.memtest-attestation.v1","method":"manual_operator_observation",
 "trust_level":"operator_attestation_not_cryptographic","status":"OPERATOR_CONFIRMED",
 "boot_id":"$(cat /proc/sys/kernel/random/boot_id)","target_serial":"PAW-SSD-TEST",
 "target_device":"/dev/loop0","completed_passes":1,"error_count":0}
JSON
export PAW_MEMTEST_ATTESTATION="$state/memtest-attestation.json"

run_case(){
  local name="$1" expected="$2" rc
  shift 2
  rm -f "$state/reports/"*.json "$state/reports/"*.txt
  set +e
  env "$@" "$root/scripts/paw-hardware-preflight.sh" /dev/loop0 >"$state/logs/$name.log" 2>&1
  rc=$?
  set -e
  local status
  status="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("status",""))' "$state/reports/paw-hardware-health-report.json" 2>/dev/null || true)"
  if [[ "$status" == "$expected" ]]; then pass "$name => $expected (rc=$rc)"; else fail "$name expected $expected got '${status:-missing}' rc=$rc"; fi
}
run_case healthy PASS
run_case serial_mismatch BLOCKED PAW_MOCK_SERIAL=OTHER-SSD
run_case capacity_mismatch BLOCKED PAW_MOCK_CAPACITY=256060514304
run_case live_medium_excluded BLOCKED PAW_MOCK_LIVE_MEDIUM=1
run_case mounted_target BLOCKED PAW_MOCK_MOUNTED=1
run_case smart_health_failed FAIL PAW_MOCK_SMART_MODE=healthfail
run_case temperature_85c FAIL PAW_MOCK_TEMP=85
run_case crc_errors WARN PAW_MOCK_CRC=12
run_case selftest_failed FAIL PAW_MOCK_SMART_MODE=selffail
run_case scan_failure FAIL PAW_MOCK_SCAN_FAIL=1
python3 - "$state/reports/paw-ssd-identity.json" <<'PY' && pass 'Identity report records serial/capacity basis, not device name' || fail 'Identity basis report'
import json,sys,os
if not os.path.exists(sys.argv[1]): raise SystemExit(1)
d=json.load(open(sys.argv[1],encoding="utf-8"))
assert d["identity_basis"]=="serial+real_capacity+model"
assert d["device_name_used_as_identity"] is False
PY
printf 'Summary: %s passed, %s failed\n' "$passed" "$failed" >>"$report"
cat "$report"
((failed == 0))
