#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/paw-lib.sh"
need python3

# This is deliberately an operator attestation, not a machine-verified result.
# The operator must have actually booted the independent Memtest86+ menu entry,
# observed completion, and then returned to this PAW Live session.
target_cfg="$PAW_CONFIG_DIR/target-ssd.json"
[[ -r "$target_cfg" ]] || die '请先登记目标 SSD,再登记内存检测结果.'
read_fields=()
mapfile -d '' -t read_fields < <(python3 - "$target_cfg" <<'PY'
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
sys.stdout.write("".join(str(d.get(k) or "")+"\0" for k in ("device_path","model","serial","capacity_bytes","approved","hardware_identity_sha256","identity_basis")))
PY
)
target_dev="${read_fields[0]:-}"; target_model="${read_fields[1]:-}"; target_serial="${read_fields[2]:-}"; target_capacity="${read_fields[3]:-}"; target_approved="${read_fields[4]:-}"
target_hw="${read_fields[5]:-}"; target_basis="${read_fields[6]:-}"
unset read_fields
[[ "$target_approved" == True ]] || die '目标 SSD 尚未批准登记,不能登记内存检测结果.'
[[ "$target_capacity" =~ ^[0-9]+$ ]] || die '目标 SSD 容量登记无效.'
[[ -n "$target_hw" || -n "$target_serial" ]] || die '目标 SSD 登记缺少稳定身份,无法绑定内存检测结果.'
if resolved="$(python3 "$PAW_ROOT/scripts/paw-identity.py" resolve --config "$target_cfg" 2>/dev/null)"; then
  target_dev="$(python3 -c 'import json,sys;print(json.load(sys.stdin).get("device_path",""))' <<<"$resolved")"
elif ! [[ "$target_dev" =~ ^/dev/[A-Za-z0-9/]+$ && -b "$target_dev" && "$(lsblk -dn -o TYPE "$target_dev" 2>/dev/null | xargs || true)" == loop ]]; then
  die '目标 SSD 身份已变化或存在身份歧义;请重新登记目标盘.'
fi
[[ "$target_dev" =~ ^/dev/[A-Za-z0-9/]+$ && -b "$target_dev" ]] || die '目标 SSD 设备路径不存在.'
python3 "$PAW_ROOT/scripts/paw-identity.py" verify --config "$target_cfg" --device "$target_dev" --phase prewrite --check-unique >/dev/null 2>&1 \
  || die '目标 SSD 身份已变化;请重新登记目标盘.'
actual_capacity="$(blockdev --getsize64 "$target_dev")"
[[ "$actual_capacity" == "$target_capacity" ]] || die '目标 SSD 容量已变化;请重新登记目标盘.'
boot_id="$(cat /proc/sys/kernel/random/boot_id)"

# The panel must reach the physical console: paw-console.service sends stdout
# to the journal only, so every operator line goes through the tty1 fd (or the
# inherited stdio when input is piped by CI).
# shellcheck source=scripts/paw-tty-lib.sh
source "$PAW_ROOT/scripts/paw-tty-lib.sh"
export PAW_TTY_SESSION_NAME=memtest-confirm
paw_tty_open_optional || die '无法打开交互终端;未写入任何结果.'
paw_tty_clear
paw_tty_marker PAW-TTY1-MEMTEST-PANEL
paw_tty_say 'PAW 内存检测人工确认'
paw_tty_say '本界面只登记操作员在 Memtest86+ 独立启动项中直接看到的结果.'
paw_tty_say '它不是机器自动验证,也不是密码学证明;请不要凭猜测填写.'
paw_tty_say "目标 SSD:$target_dev 型号=${target_model:-未知} 容量=$target_capacity bytes"
paw_tty_say "目标序列号:${target_serial:-不可用(使用稳定硬件指纹)}"
paw_tty_say "身份依据:${target_basis:-未知}"
paw_tty_say "硬件指纹:${target_hw:-旧版仅序列号登记}"
paw_tty_say "本次 PAW Live 启动 ID:$boot_id"
paw_tty_say '请选择:'
paw_tty_say '  1) Memtest86+ 已完成最少 1 轮,错误数为 0'
paw_tty_say '  2) Memtest86+ 已完成,但出现错误'
paw_tty_say '  3) 尚未完成,无法确认或不确定'
paw_tty_marker PAW-TTY1-MEMTEST-PROMPT
paw_tty_prompt '输入 1,2 或 3:'
choice=''
if ! paw_tty_read choice; then
  paw_tty_marker PAW-TTY1-MEMTEST-TIMEOUT
  paw_tty_say ''
  paw_tty_say '错误:等待输入超时或输入中断,已安全停止,未写入任何结果.'
  paw_tty_close
  exit 2
fi
case "$choice" in
  1) attestation_status=OPERATOR_CONFIRMED ;;
  2) attestation_status=FAIL ;;
  3) attestation_status=WARN ;;
  *)
    paw_tty_marker PAW-TTY1-MEMTEST-BAD
    paw_tty_say '错误:选择无效;未写入任何结果.'
    paw_tty_close
    die '选择无效;未写入任何结果.' ;;
esac

if [[ "$attestation_status" != WARN ]]; then
  paw_tty_prompt '完成的测试轮次(正整数):'
  passes=''
  if ! paw_tty_read passes; then
    paw_tty_marker PAW-TTY1-MEMTEST-TIMEOUT
    paw_tty_close
    die '轮次输入中断;未写入任何结果.'
  fi
  [[ "$passes" =~ ^[1-9][0-9]*$ ]] || { paw_tty_close; die '轮次必须是正整数;未写入任何结果.'; }
  paw_tty_prompt 'Memtest86+ 显示的错误数量(非负整数):'
  errors=''
  if ! paw_tty_read errors; then
    paw_tty_marker PAW-TTY1-MEMTEST-TIMEOUT
    paw_tty_close
    die '错误数量输入中断;未写入任何结果.'
  fi
  [[ "$errors" =~ ^[0-9]+$ ]] || { paw_tty_close; die '错误数量必须是非负整数;未写入任何结果.'; }
  if ((errors > 0)); then
    attestation_status=FAIL
    paw_tty_say '检测到错误数量大于 0,结果按 FAIL 记录;克隆将被阻断.'
  fi
  if ((passes < 1)); then
    attestation_status=WARN
    paw_tty_say '完成轮次小于 1,结果按 WARN 记录;克隆将被阻断.'
  fi
else
  passes=0
  errors=0
fi

paw_tty_say ''
paw_tty_say '登记摘要:'
paw_tty_say "  状态:$attestation_status"
paw_tty_say "  完成轮次:$passes"
paw_tty_say "  错误数量:$errors"
paw_tty_say "  目标序列号:${target_serial:-不可用(使用稳定硬件指纹)}"
paw_tty_say "  硬件指纹:${target_hw:-旧版仅序列号登记}"
paw_tty_say "  启动 ID:$boot_id"
[[ "$attestation_status" == OPERATOR_CONFIRMED ]] || paw_tty_say '注意:此状态不会允许进入克隆.'
paw_tty_prompt '确认写入本次人工登记?输入"确认":'
confirmed=''
if ! paw_tty_read confirmed; then
  paw_tty_marker PAW-TTY1-MEMTEST-TIMEOUT
  paw_tty_close
  die '确认输入中断;没有写入结果.'
fi
if [[ "$confirmed" != '确认' ]]; then
  paw_tty_marker PAW-TTY1-MEMTEST-BAD
  paw_tty_say '未确认;没有写入结果.'
  paw_tty_close
  die '未确认;没有写入结果.'
fi
paw_tty_marker PAW-TTY1-MEMTEST-OK
unset confirmed
paw_tty_close

install -d -m 0700 "$PAW_STATE_DIR"
python3 - "$PAW_STATE_DIR/memtest-attestation.json" "$attestation_status" "$passes" "$errors" "$target_dev" "$target_serial" "$target_hw" "$boot_id" <<'PY'
import datetime,json,os,sys,tempfile
path,status,passes,errors,target,serial,hw_hash,boot_id=sys.argv[1:]
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
    "target_hardware_identity_sha256":hw_hash,
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
