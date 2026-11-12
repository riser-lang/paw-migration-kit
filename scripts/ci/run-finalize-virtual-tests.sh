#!/usr/bin/env bash
set -Eeuo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
out="${PAW_ARTIFACT_DIR:-$PWD/artifacts}"
work="$root/tests/virtual/finalize-run"
report="$out/finalize-virtual-test-report.txt"
rm -rf "$work"
mkdir -p "$work" "$out"
passed=0; failed=0
trap 'rm -rf "$work"' EXIT

pass(){ printf 'PASS %s\n' "$1" >>"$report"; passed=$((passed+1)); }
fail(){ printf 'FAIL %s\n' "$1" >>"$report"; failed=$((failed+1)); }
printf 'PAW finalize/reboot virtual fault-injection results\n' >"$report"
printf 'Executed: %s\n' "$(date -u +%FT%TZ)" >>"$report"

firstboot_line="$(grep -n 'paw-preboot-handoff-check\.sh' "$root/scripts/paw-final-confirm.sh" | head -n1 | cut -d: -f1)"
finalize_line="$(grep -n 'paw-finalize-reboot\.sh' "$root/scripts/paw-final-confirm.sh" | head -n1 | cut -d: -f1)"
[[ -n "$firstboot_line" && -n "$finalize_line" && "$finalize_line" -gt "$firstboot_line" ]] \
  && pass 'A0 final-confirm 在重启前交接检查之后才调用 finalizer' \
  || fail 'A0 final-confirm 调用顺序错误'
! grep -q 'with open(receipt' "$root/scripts/paw-final-confirm.sh" \
  && pass 'A0 旧的直接完成记录写入已移除（仅 finalizer 原子写）' \
  || fail 'A0 final-confirm 仍直接写完成记录'

new_case(){
  local name="$1"
  CASE="$work/$name"
  mkdir -p "$CASE/reports" "$CASE/state/configs" "$CASE/state/logs" "$CASE/bin"
  cat >"$CASE/bin/reboot" <<'MOCKREBOOT'
#!/usr/bin/env bash
printf 'reboot %s\n' "$*" >>"$PAW_TEST_REBOOT_LOG"
exit "${PAW_TEST_REBOOT_EXIT:-0}"
MOCKREBOOT
  chmod 0755 "$CASE/bin/reboot"
  : >"$CASE/reboot.log"
  cat >"$CASE/reports/stream-verify.json" <<'JSON'
{"status":"PASS","sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","bytes_verified":1024,"independent_sha256_verified":true}
JSON
  printf '{"status":"PASS","source":"clone"}\n' >"$CASE/reports/offline-repair.json"
  printf '{"status":"PASS","before_bytes":100,"after_bytes":200}\n' >"$CASE/reports/gpt-expand.json"
  printf '{"status":"PASS","clone_sha256":"%s"}\n' "$(printf 'a%.0s' {1..64})" >"$CASE/reports/preboot-handoff.json"
  cat >"$CASE/completion.json" <<'JSON'
{"schema":"paw.migration-completion.v2","status":"PASS","checks":{"clone":"PASS","sha256":"PASS","offline_repair":"PASS","gpt_ext4_expand":"PASS","preboot_handoff":"PASS"}}
JSON
  cat >"$CASE/reports/operator-authorization.json" <<'JSON'
{"status":"AUTHORIZED","target_serial":"TEST-SERIAL-123456","target_device":"/dev/virtual"}
JSON
  chmod 0600 "$CASE/reports/operator-authorization.json"
}

run_finalize(){
  local input="${1:-}" extra=()
  shift || true
  extra=("$@")
  export PAW_ROOT="$root" PAW_STATE_DIR="$CASE/state" PAW_CONFIG_DIR="$CASE/state/configs"
  export PAW_REPORT_DIR="$CASE/reports" PAW_LOG_DIR="$CASE/state/logs"
  export PAW_TEST_REBOOT_LOG="$CASE/reboot.log" PAW_REBOOT_CMD="$CASE/bin/reboot"
  export PAW_REBOOT_COUNTDOWN_SECONDS=1 PAW_INTERACTIVE_TTY="$CASE/not-a-tty"
  # This suite isolates reboot sequencing; the P0 transaction suite covers the
  # state-machine integration with the real finalizer separately.
  export PAW_FINALIZE_TEST_MODE=1
  export PAW_TEST_REBOOT_EXIT="${PAW_TEST_REBOOT_EXIT:-0}"
  set +e
  if [[ -n "$input" ]]; then
    printf '%s' "$input" | bash "$root/scripts/paw-finalize-reboot.sh" --completion-data "$CASE/completion.json" "${extra[@]}" >"$CASE/output.log" 2>&1
  else
    bash "$root/scripts/paw-finalize-reboot.sh" --completion-data "$CASE/completion.json" "${extra[@]}" </dev/null >"$CASE/output.log" 2>&1
  fi
  RC=$?
  set -e
}

status_is(){
  python3 - "$CASE/reports/reboot-status.json" "$1" <<'PY'
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
raise SystemExit(0 if d.get("status")==sys.argv[2] else 1)
PY
}

reboot_count(){ local n=0; [[ -s "$CASE/reboot.log" ]] && n="$(wc -l <"$CASE/reboot.log")"; printf '%s\n' "$n"; }

assert_no_countdown(){
  if grep -q '倒计时' "$CASE/output.log"; then fail "$1: 未通过门禁却出现倒计时"; else pass "$1: 未通过门禁时不进入倒计时"; fi
}

# 1. All gates pass: countdown is allowed, reboot is issued exactly once, state PASS.
new_case all-pass
PAW_TEST_REBOOT_EXIT=0 run_finalize '' --receipt "$CASE/reports/migration-completion.json" --authorization "$CASE/reports/operator-authorization.json"
[[ $RC -eq 0 ]] && pass 'A1 所有步骤成功时 finalizer 返回 0' || fail "A1 成功路径返回 $RC"
status_is PASS && pass 'A1 状态为 PASS' || fail 'A1 状态不是 PASS'
[[ "$(reboot_count)" == 1 ]] && pass 'A1 reboot 恰好调用 1 次' || fail "A1 reboot 调用次数=$(reboot_count)"
[[ "$(stat -c %a "$CASE/reports/migration-completion.json" 2>/dev/null || echo missing)" == 600 ]] && pass 'A1 完成记录以 0600 原子写入' || fail 'A1 完成记录权限/存在性错误'
python3 - "$CASE/reports/operator-authorization.json" <<'PY' && pass 'A1 授权记录被原子标记为 CONSUMED' || fail 'A1 授权记录未消费'
import json,sys
raise SystemExit(0 if json.load(open(sys.argv[1]))["status"]=="CONSUMED" else 1)
PY
python3 - "$CASE/reports/migration-completion.json" <<'PY' && pass 'A1 完成记录可回读且 checks 全 PASS' || fail 'A1 完成记录内容错误'
import json,sys
d=json.load(open(sys.argv[1]))
assert d["status"]=="PASS" and all(v=="PASS" for v in d["checks"].values())
PY
find "$CASE/reports" -maxdepth 1 -name '.paw-atomic-*' -print -quit | grep -q . && fail 'A1 原子写遗留临时文件' || pass 'A1 原子写无临时文件残留'

# 2. Completion receipt cannot be written: no reboot, explicit non-PASS state.
new_case receipt-failure
PAW_TEST_REBOOT_EXIT=0 run_finalize '' --receipt "$CASE/missing-dir/migration-completion.json"
[[ $RC -ne 0 ]] && pass 'A2 完成记录写入失败时返回非 0' || fail 'A2 完成记录写入失败却返回 0'
status_is FAIL && pass 'A2 状态为 FAIL' || fail 'A2 状态不是 FAIL'
[[ "$(reboot_count)" == 0 ]] && pass 'A2 reboot 调用次数为 0' || fail "A2 reboot 调用次数=$(reboot_count)"
assert_no_countdown A2

# 3. SHA256 evidence fails: no reboot.
new_case sha-failure
printf '{"status":"FAIL","sha256":"%s","independent_sha256_verified":false}\n' "$(printf 'b%.0s' {1..64})" >"$CASE/reports/stream-verify.json"
PAW_TEST_REBOOT_EXIT=0 run_finalize
[[ $RC -ne 0 ]] && pass 'A3 SHA256 失败时返回非 0' || fail 'A3 SHA256 失败却返回 0'
status_is BLOCKED && pass 'A3 状态为 BLOCKED' || fail 'A3 状态不是 BLOCKED'
[[ "$(reboot_count)" == 0 ]] && pass 'A3 reboot 调用次数为 0' || fail "A3 reboot 调用次数=$(reboot_count)"
assert_no_countdown A3

# 4. Offline repair fails: no reboot.
new_case repair-failure
printf '{"status":"FAIL","reason":"injected repair failure"}\n' >"$CASE/reports/offline-repair.json"
PAW_TEST_REBOOT_EXIT=0 run_finalize
[[ $RC -ne 0 ]] && pass 'A4 离线修复失败时返回非 0' || fail 'A4 离线修复失败却返回 0'
status_is BLOCKED && pass 'A4 状态为 BLOCKED' || fail 'A4 状态不是 BLOCKED'
[[ "$(reboot_count)" == 0 ]] && pass 'A4 reboot 调用次数为 0' || fail "A4 reboot 调用次数=$(reboot_count)"
assert_no_countdown A4

# 4b/4c. Expansion and pre-reboot handoff gates also block before countdown.
new_case expand-failure
printf '{"status":"FAIL"}\n' >"$CASE/reports/gpt-expand.json"
PAW_TEST_REBOOT_EXIT=0 run_finalize
status_is BLOCKED && [[ "$(reboot_count)" == 0 ]] && pass 'A4b GPT/ext4 扩容失败时不重启' || fail 'A4b 扩容失败仍重启/状态错误'
new_case preboot-failure
printf '{"status":"FAIL"}\n' >"$CASE/reports/preboot-handoff.json"
PAW_TEST_REBOOT_EXIT=0 run_finalize
status_is BLOCKED && [[ "$(reboot_count)" == 0 ]] && pass 'A4c 重启前交接检查失败时不重启' || fail 'A4c 交接检查失败仍重启/状态错误'

# 5. Reboot command fails: manual-restart notice and NEEDS_MANUAL_ACTION.
new_case reboot-failure
PAW_TEST_REBOOT_EXIT=9 run_finalize '' --receipt "$CASE/reports/migration-completion.json"
[[ $RC -ne 0 ]] && pass 'A5 reboot 失败时返回非 0' || fail 'A5 reboot 失败却返回 0'
status_is NEEDS_MANUAL_ACTION && pass 'A5 状态为 NEEDS_MANUAL_ACTION' || fail 'A5 状态不是 NEEDS_MANUAL_ACTION'
grep -q '手动重启' "$CASE/output.log" && pass 'A5 输出明确的手动重启提示' || fail 'A5 缺少手动重启提示'
grep -q 'systemctl reboot' "$CASE/output.log" && pass 'A5 手动提示包含可执行命令' || fail 'A5 手动提示缺少命令'
[[ "$(reboot_count)" == 1 ]] && pass 'A5 reboot 被调用且失败被捕获' || fail "A5 reboot 调用次数=$(reboot_count)"

# 6. User cancels during countdown: no reboot, CANCELLED state.
new_case cancelled
PAW_TEST_REBOOT_EXIT=0 run_finalize 'c' --receipt "$CASE/reports/migration-completion.json"
[[ $RC -eq 0 ]] && pass 'A6 用户取消时正常退出' || fail "A6 取消返回 $RC"
status_is CANCELLED && pass 'A6 状态为 CANCELLED' || fail 'A6 状态不是 CANCELLED'
[[ "$(reboot_count)" == 0 ]] && pass 'A6 取消后 reboot 调用次数为 0' || fail "A6 取消后 reboot 调用次数=$(reboot_count)"
grep -q '已取消自动重启,请手动重启' "$CASE/output.log" && pass 'A6 明确显示已取消自动重启' || fail 'A6 取消提示缺失'
python3 - "$CASE/reports/reboot-status.json" <<'PY' && pass 'A6 取消状态未伪写为已重启' || fail 'A6 取消状态包含 reboot_invoked=true'
import json,sys
d=json.load(open(sys.argv[1])); assert d["reboot_invoked"] is False and d.get("cancelled_by_user") is True
PY

# 7. Reverse assertion across every blocked case.
total=0
for case in receipt-failure sha-failure repair-failure expand-failure preboot-failure cancelled; do
  n=0; [[ -s "$work/$case/reboot.log" ]] && n="$(wc -l <"$work/$case/reboot.log")"
  total=$((total+n))
done
[[ "$total" == 0 ]] && pass 'A7 反向断言：所有前置/取消路径 reboot 总调用次数为 0' || fail "A7 反向断言失败，总调用=$total"

# 8. Completion data that claims incomplete checks must also block.
new_case incomplete-data
printf '{"status":"PASS","checks":{"clone":"PASS","sha256":"FAIL"}}\n' >"$CASE/completion.json"
PAW_TEST_REBOOT_EXIT=0 run_finalize
status_is BLOCKED && [[ "$(reboot_count)" == 0 ]] && pass 'A8 完成数据 checks 不完整时阻断重启' || fail 'A8 不完整完成数据未被阻断'

# 9. A second run after a successful pass must not issue a second reboot.
new_case idempotent
PAW_TEST_REBOOT_EXIT=0 run_finalize '' --receipt "$CASE/reports/migration-completion.json"
first_count="$(reboot_count)"
PAW_TEST_REBOOT_EXIT=0 run_finalize '' --receipt "$CASE/reports/migration-completion.json"
[[ "$first_count" == 1 && "$(reboot_count)" == 1 ]] && pass 'A9 已成功下发重启后重跑不会重复 reboot' || fail "A9 重复 reboot：first=$first_count now=$(reboot_count)"

printf 'Summary: %s passed, %s failed\n' "$passed" "$failed" >>"$report"
cat "$report"
((failed == 0))
