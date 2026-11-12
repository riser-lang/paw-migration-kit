#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/paw-lib.sh"
need python3; need sync

completion_data=''
authorization=''
receipt="${PAW_COMPLETION_RECEIPT:-$PAW_REPORT_DIR/migration-completion.json}"
status_file="${PAW_REBOOT_STATUS:-$PAW_REPORT_DIR/reboot-status.json}"
evidence_dir="${PAW_FINALIZE_EVIDENCE_DIR:-$PAW_REPORT_DIR}"
countdown="${PAW_REBOOT_COUNTDOWN_SECONDS:-10}"
reboot_cmd="${PAW_REBOOT_CMD:-systemctl reboot}"
dry_run="${PAW_REBOOT_DRY_RUN:-0}"
tty_dev="${PAW_INTERACTIVE_TTY:-/dev/tty1}"

usage(){
  printf '%s\n' 'Usage: paw-finalize-reboot.sh --completion-data FILE [--authorization FILE] [--receipt FILE]'
}
while (($#)); do
  case "$1" in
    --completion-data) completion_data="${2:-}"; shift 2 ;;
    --authorization) authorization="${2:-}"; shift 2 ;;
    --receipt) receipt="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done
[[ -n "$completion_data" && -r "$completion_data" ]] || { usage >&2; exit 2; }
[[ "$countdown" =~ ^[0-9]+$ ]] && ((countdown >= 1 && countdown <= 600)) || die '重启倒计时必须是 1-600 秒的整数.'
[[ -n "$reboot_cmd" ]] || die '重启命令不能为空.'
mkdir -p "$PAW_REPORT_DIR" "$(dirname "$status_file")"
if [[ ${PAW_FINALIZE_TEST_MODE:-0} != 1 ]]; then
  assert_transaction_stage finalize
fi

say(){
  if [[ -c "$tty_dev" ]]; then printf '%s\n' "$*" >"$tty_dev"; else printf '%s\n' "$*" >&2; fi
}

write_reboot_status(){
  local state="$1" reason="$2" invoked="$3" extra="${4:-}"
  [[ -n "$extra" ]] || extra='{}'
  python3 - "$status_file" "$state" "$reason" "$invoked" "$countdown" "$reboot_cmd" "$dry_run" "$extra" <<'PY' | python3 "$PAW_ROOT/scripts/paw-atomic-write.py" "$status_file"
import datetime,json,sys
path,state,reason,invoked,countdown,cmd,dry,extra=sys.argv[1:]
document={
 "schema":"paw.reboot-status.v1",
 "status":state,
 "reason":reason,
 "reboot_invoked":invoked == "true",
 "reboot_command":cmd,
 "countdown_seconds":int(countdown),
 "dry_run":dry == "1",
 "updated_at":datetime.datetime.now(datetime.timezone.utc).isoformat(),
}
document.update(json.loads(extra))
sys.stdout.write(json.dumps(document,ensure_ascii=False,indent=2)+"\n")
PY
}

fail_finalize(){
  local state="$1" gate="$2" reason="$3"
  log ERROR "最终重启门禁失败:$gate:$reason"
  write_reboot_status "$state" "$gate:$reason" false "{\"failed_gate\":$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1],ensure_ascii=False))' "$gate")}" \
    || { log ERROR '无法写入重启状态文件;仍不执行重启.'; exit 4; }
  say "迁移未完成最终门禁,不会自动重启:$gate($reason)"
  say '请人工检查报告后重试.'
  exit 2
}

# A previous successful pass must never issue a second reboot.
if python3 - "$status_file" <<'PY' 2>/dev/null
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
raise SystemExit(0 if d.get("status")=="PASS" and d.get("reboot_invoked") is True else 1)
PY
then
  log INFO '检测到已成功下发重启;本次不重复重启.'
  say '本次迁移已完成并已下发重启,不会重复重启.'
  exit 0
fi

evidence_pass(){
  local file="$1" label="$2"
  [[ -r "$file" ]] || fail_finalize BLOCKED "$label" "证据文件缺失:$file"
  python3 - "$file" <<'PY' || fail_finalize BLOCKED "$label" '证据状态不是 PASS'
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
raise SystemExit(0 if d.get("status")=="PASS" else 1)
PY
}

# 1-5: all clone, SHA256, offline repair, expansion and first-boot gates.
evidence_pass "$evidence_dir/stream-verify.json" 'SHA256 独立校验'
python3 - "$evidence_dir/stream-verify.json" <<'PY' || fail_finalize BLOCKED 'SHA256 独立校验' '缺少独立校验标志或哈希格式无效'
import json,re,sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
ok=d.get("independent_sha256_verified") is True and re.fullmatch(r"[0-9a-f]{64}",str(d.get("sha256",""))) is not None
raise SystemExit(0 if ok else 1)
PY
evidence_pass "$evidence_dir/offline-repair.json" '离线修复'
evidence_pass "$evidence_dir/gpt-expand.json" 'GPT/ext4 扩容'
evidence_pass "$evidence_dir/preboot-handoff.json" '重启前交接检查'

python3 - "$completion_data" <<'PY' || fail_finalize BLOCKED '完成记录门禁' '完成数据不是 PASS 或步骤不完整'
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
required={"clone","sha256","offline_repair","gpt_ext4_expand","preboot_handoff"}
checks=d.get("checks") or {}
ok=d.get("status")=="PASS" and required <= set(checks) and all(checks[k]=="PASS" for k in required)
raise SystemExit(0 if ok else 1)
PY

# 6: atomic completion record, then read it back.
if ! python3 "$PAW_ROOT/scripts/paw-atomic-write.py" "$receipt" <"$completion_data"; then
  fail_finalize FAIL '完成记录写入' "无法原子写入 $receipt"
fi
python3 - "$completion_data" "$receipt" <<'PY' || fail_finalize FAIL '完成记录回读' '完成记录与写入内容不一致'
import json,sys
a=json.load(open(sys.argv[1],encoding="utf-8")); b=json.load(open(sys.argv[2],encoding="utf-8"))
raise SystemExit(0 if a==b else 1)
PY

if [[ -n "$authorization" ]]; then
  [[ -r "$authorization" ]] || fail_finalize FAIL '授权记录' "授权文件缺失:$authorization"
  auth_state="$(python3 - "$authorization" <<'PY'
import json,sys
try: print(json.load(open(sys.argv[1],encoding="utf-8")).get("status",""))
except Exception: print("")
PY
)"
  if [[ "$auth_state" == CONSUMED ]]; then
    log INFO '授权记录已是 CONSUMED;重试不会再次消费,继续执行最终门禁.'
  elif [[ "$auth_state" == AUTHORIZED ]]; then
  if ! python3 - "$authorization" <<'PY' | python3 "$PAW_ROOT/scripts/paw-atomic-write.py" "$authorization"
import datetime,json,sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
if d.get("status")!="AUTHORIZED":
    raise SystemExit(1)
d["status"]="CONSUMED"
d["completed_at"]=datetime.datetime.now(datetime.timezone.utc).isoformat()
sys.stdout.write(json.dumps(d,ensure_ascii=False,indent=2)+"\n")
PY
  then
    fail_finalize FAIL '授权记录' '无法原子消费授权记录'
  fi
  else
    fail_finalize FAIL '授权记录' "授权状态不是 AUTHORIZED/CONSUMED:$auth_state"
  fi
fi

# 7: sync all filesystems before announcing success.
sync || fail_finalize FAIL 'sync' 'sync 失败'

# 7b: legacy BIOS cannot be reprogrammed from Linux.  Refuse an automatic
# reboot that would likely re-enter the live USB; the operator must remove it
# and explicitly arm the removal.
if [[ ${PAW_FINALIZE_TEST_MODE:-0} != 1 ]]; then
  "$PAW_ROOT/scripts/paw-reboot-media-check.sh" || fail_finalize BLOCKED '启动介质顺序' 'PAW-LIVE 介质仍在;必须真正移除 USB/TF 并在块设备层观察到消失后才能自动重启'
fi

# 8-10: Chinese success notice, cancellable countdown, reboot.
say '[PAW-REBOOT] all gates PASS; completion record is atomic and synced.'
say 'PAW 迁移成功:克隆,独立 SHA256 校验,离线修复,GPT/ext4 扩容和重启前交接检查全部通过.'
say '完成记录已原子写入并同步到磁盘.'
say "系统将在 ${countdown} 秒后自动重启进入正式 Ubuntu;按 C 取消自动重启."
say "Auto reboot in ${countdown}s; press C to cancel."
if [[ -c "$tty_dev" ]]; then exec 3<"$tty_dev"; fi
cancelled=0
for ((i=countdown; i>=1; i--)); do
  say "倒计时 ${i} 秒(按 C 取消)..."
  key=''
  if [[ -c "$tty_dev" ]]; then
    if IFS= read -r -t 1 -n 1 -u 3 key; then :; fi
  else
    if IFS= read -r -t 1 -n 1 key; then :; fi
  fi
  if [[ -n "$key" ]]; then cancelled=1; break; fi
done
[[ -c "$tty_dev" ]] && exec 3<&-
if ((cancelled == 1)); then
  write_reboot_status CANCELLED '用户取消自动重启' false '{"cancelled_by_user":true}'
  log WARN '用户取消自动重启;未执行 reboot.'
  say '已取消自动重启,请手动重启:sudo systemctl reboot'
  say '[PAW-REBOOT] CANCELLED; run: sudo systemctl reboot'
  exit 0
fi

if [[ "$dry_run" == 1 ]]; then
  write_reboot_status PASS 'dry-run:未执行真实重启' false '{"dry_run":true}'
  log INFO 'Dry-run:门禁全部通过,未执行真实 reboot.'
  say '自动重启为 dry-run,未执行真实重启.'
  exit 0
fi

read -r -a reboot_argv <<<"$reboot_cmd"
say "正在执行自动重启:${reboot_cmd}"
# Persist the successful reboot decision before issuing it.  systemctl reboot
# can terminate this process as soon as shutdown starts, so writing the status
# afterwards leaves no durable evidence and a later boot could reboot again.
write_reboot_status PASS '自动重启命令即将下发;状态已先行持久化' true '{"status_persisted_before_reboot":true}'
sync || true
# The chain consumes this status as its final PASS gate.  It must copy the
# report set to durable media and emit PAW3_CHAIN_RESULT=PASS *before* the
# reset; otherwise QEMU can kill the chain between this status write and the
# final marker.  The chain touches the handoff file only after that copy.
if [[ -n ${PAW_REBOOT_HANDOFF_FILE:-} ]]; then
  log INFO "Waiting for chain PASS handoff ${PAW_REBOOT_HANDOFF_FILE} before reboot."
  handoff_ok=0
  for _ in $(seq 1 60); do
    if [[ -e $PAW_REBOOT_HANDOFF_FILE ]]; then handoff_ok=1; break; fi
    sleep 1
  done
  ((handoff_ok == 1)) || fail_finalize BLOCKED '链 PASS 交接' "60 秒内未收到 ${PAW_REBOOT_HANDOFF_FILE};拒绝在证据未落盘时自动重启"
  log INFO 'Chain PASS handoff observed; issuing reboot.'
fi
sleep 2
set +e
"${reboot_argv[@]}"
rc=$?
set -e
if ((rc != 0)); then
  write_reboot_status NEEDS_MANUAL_ACTION "reboot 命令失败,退出码 ${rc}" false "{\"reboot_exit_code\":${rc}}"
  if [[ ${PAW_FINALIZE_TEST_MODE:-0} != 1 ]]; then
    transaction_event NEEDS_MANUAL_ACTION --phase finalize --reason "reboot command failed rc=$rc" || true
  fi
  log ERROR "reboot 命令失败,退出码 ${rc};需要人工重启."
  say '自动重启命令执行失败!迁移数据已完成,请立即手动重启:sudo systemctl reboot'
  say '[PAW-REBOOT] FAILED; migration data is complete, run: sudo systemctl reboot'
  exit 3
fi
write_reboot_status PASS '自动重启命令已成功下发' true "{\"reboot_exit_code\":0}"
log INFO '最终门禁全部通过,已完成 sync 并成功下发 systemctl reboot.'
say '自动重启命令已下发.'
say '[PAW-REBOOT] PASS; reboot command issued.'
