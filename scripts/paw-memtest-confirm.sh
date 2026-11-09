#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/paw-lib.sh"
need python3

# This is deliberately an operator attestation, not a machine-verified result.
# The operator must have actually booted the independent Memtest86+ menu entry,
# observed completion, and then returned to this PAW Live session.
target_cfg="$PAW_CONFIG_DIR/target-ssd.json"
[[ -r "$target_cfg" ]] || die '请先登记目标 SSD，再登记内存检测结果。'
read_fields=()
mapfile -d '' -t read_fields < <(python3 - "$target_cfg" <<'PY'
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
sys.stdout.write("".join(str(d.get(k) or "")+"\0" for k in ("device_path","model","serial","capacity_bytes")))
PY
)
target_dev="${read_fields[0]:-}"; target_model="${read_fields[1]:-}"; target_serial="${read_fields[2]:-}"; target_capacity="${read_fields[3]:-}"
unset read_fields
[[ "$target_dev" =~ ^/dev/[A-Za-z0-9/]+$ && -b "$target_dev" && -n "$target_serial" ]] || die '目标 SSD 登记不完整，无法绑定内存检测结果。'
[[ "$target_capacity" =~ ^[0-9]+$ ]] || die '目标 SSD 容量登记无效。'
actual_serial="$(lsblk -dn -o SERIAL "$target_dev" | xargs)"
actual_capacity="$(blockdev --getsize64 "$target_dev")"
[[ "$actual_serial" == "$target_serial" && "$actual_capacity" == "$target_capacity" ]] || die '目标 SSD 身份已变化；请重新登记目标盘。'
boot_id="$(cat /proc/sys/kernel/random/boot_id)"

printf '\nPAW 内存检测人工确认\n'
printf '%s\n' '本界面只登记操作员在 Memtest86+ 独立启动项中亲眼看到的结果。'
printf '%s\n' '它不是机器自动验证，也不是密码学证明；请不要凭猜测填写。'
printf '目标 SSD：%s 型号=%s 容量=%s bytes\n' "$target_dev" "${target_model:-未知}" "$target_capacity"
printf '目标序列号：%s\n' "$target_serial"
printf '本次 PAW Live 启动 ID：%s\n' "$boot_id"
printf '%s\n' '请选择：'
printf '%s\n' '  1) Memtest86+ 已完成至少 1 轮，错误数为 0'
printf '%s\n' '  2) Memtest86+ 已完成，但出现错误'
printf '%s\n' '  3) 尚未完成、无法确认或不确定'
read -r -p '输入 1、2 或 3：' choice
case "$choice" in
  1) attestation_status=OPERATOR_CONFIRMED ;;
  2) attestation_status=FAIL ;;
  3) attestation_status=WARN ;;
  *) die '选择无效；未写入任何结果。' ;;
esac

if [[ "$attestation_status" != WARN ]]; then
  read -r -p '完成的测试轮次（正整数）：' passes
  [[ "$passes" =~ ^[1-9][0-9]*$ ]] || die '轮次必须是正整数；未写入任何结果。'
  read -r -p 'Memtest86+ 显示的错误数量（非负整数）：' errors
  [[ "$errors" =~ ^[0-9]+$ ]] || die '错误数量必须是非负整数；未写入任何结果。'
  if ((errors > 0)); then
    attestation_status=FAIL
    printf '%s\n' '检测到错误数量大于 0，结果按 FAIL 记录；克隆将被阻断。'
  fi
  if ((passes < 1)); then
    attestation_status=WARN
    printf '%s\n' '完成轮次小于 1，结果按 WARN 记录；克隆将被阻断。'
  fi
else
  passes=0
  errors=0
fi

printf '\n登记摘要：\n'
printf '  状态：%s\n' "$attestation_status"
printf '  完成轮次：%s\n' "$passes"
printf '  错误数量：%s\n' "$errors"
printf '  目标序列号：%s\n' "$target_serial"
printf '  启动 ID：%s\n' "$boot_id"
[[ "$attestation_status" == OPERATOR_CONFIRMED ]] || printf '%s\n' '注意：此状态不会允许进入克隆。'
read -r -p '确认写入本次人工登记？输入“确认”：' confirmed
[[ "$confirmed" == '确认' ]] || die '未确认；没有写入结果。'
unset confirmed

install -d -m 0700 "$PAW_STATE_DIR"
python3 - "$PAW_STATE_DIR/memtest-attestation.json" "$attestation_status" "$passes" "$errors" "$target_dev" "$target_serial" "$boot_id" <<'PY'
import datetime,json,os,sys,tempfile
path,status,passes,errors,target,serial,boot_id=sys.argv[1:]
record={
    "schema":"paw.memtest-attestation.v1",
    "status":status,
    "method":"manual_operator_observation",
    "trust_level":"operator_attestation_not_cryptographic",
    "program":"Memtest86+ x64, independent ISOLINUX menu entry",
    "completed_passes":int(passes),
    "error_count":int(errors),
    "target_device":target,
    "target_serial":serial,
    "boot_id":boot_id,
    "recorded_at":datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "operator_statement":"operator visually observed the Memtest86+ result and typed this record in PAW Live",
    "limits":"does not prove RAM health cryptographically; no trusted hardware signature is available",
}
fd,tmp=tempfile.mkstemp(dir=os.path.dirname(path),prefix=".memtest-")
with os.fdopen(fd,"w",encoding="utf-8") as handle:
    json.dump(record,handle,indent=2,ensure_ascii=False)
    handle.write("\n")
os.chmod(tmp,0o600); os.replace(tmp,path)
PY
unset passes errors

set +e
"$PAW_ROOT/scripts/paw-memory-test-report.sh"
rc=$?
set -e
log INFO "Memtest operator attestation recorded; status=${attestation_status}; machine_proof=false."
exit "$rc"
