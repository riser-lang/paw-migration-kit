#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/paw-lib.sh"
readiness="$PAW_REPORT_DIR/live-readiness.json"
[[ -r "$readiness" ]] || die '请先运行准备检查。'
python3 - "$readiness" <<'PY' || { printf '%s\n' '阻断：硬件、源盘、目标盘、网络和 PAWDATA 必须全部 PASS；当前不会出现确认输入。'; exit 2; }
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
assert d.get("status")=="READY_FOR_OPERATOR"
assert d.get("clone_started") is False
assert d.get("checks") and all(v=="PASS" for v in d["checks"].values())
PY

"$PAW_ROOT/scripts/paw-data-check.sh" >/dev/null
source_cfg="$PAW_CONFIG_DIR/source.json"; target_cfg="$PAW_CONFIG_DIR/target-ssd.json"
[[ -r "$source_cfg" && -r "$target_cfg" ]] || die '源盘或目标盘登记不存在。'
source_fields=()
mapfile -d '' -t source_fields < <(python3 - "$source_cfg" <<'PY'
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
sys.stdout.write("".join(str(d.get(k) or "")+"\0" for k in ("device_path","root_uuid","model","serial","capacity_bytes","partition_number","composite_identity_sha256","ssh_host_key_fingerprint")))
PY
)
src="${source_fields[0]:-}"; root_uuid="${source_fields[1]:-}"; source_model="${source_fields[2]:-}"; source_serial="${source_fields[3]:-}"; source_bytes="${source_fields[4]:-}"; root_part_no="${source_fields[5]:-}"; source_composite="${source_fields[6]:-}"; source_host_fp="${source_fields[7]:-}"
unset source_fields
target_fields=()
mapfile -d '' -t target_fields < <(python3 - "$target_cfg" <<'PY'
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
sys.stdout.write("".join(str(d.get(k) or "")+"\0" for k in ("device_path","model","serial","capacity_bytes")))
PY
)
dst="${target_fields[0]:-}"; target_model="${target_fields[1]:-}"; target_serial="${target_fields[2]:-}"; target_bytes="${target_fields[3]:-}"
unset target_fields
[[ "$dst" =~ ^/dev/[A-Za-z0-9/]+$ && -b "$dst" && "$src" =~ ^/dev/[A-Za-z0-9/]+$ && "$root_part_no" =~ ^[1-9][0-9]*$ ]] || die '源盘或目标盘身份配置不完整。'
[[ "$source_bytes" =~ ^[0-9]+$ && "$target_bytes" =~ ^[0-9]+$ ]] || die '源盘或目标盘容量登记无效。'
[[ "$source_composite" =~ ^[0-9a-f]{64}$ ]] || die '源盘组合身份哈希缺失；请重新执行 Rescue 源盘识别。'
[[ "$source_host_fp" == SHA256:* ]] || die '源盘固定 SSH 主机指纹缺失；请重新执行 Rescue 源盘识别。'
actual_serial="$(lsblk -dn -o SERIAL "$dst" | xargs)"; actual_bytes="$(blockdev --getsize64 "$dst")"
[[ "$actual_serial" == "$target_serial" && "$actual_bytes" == "$target_bytes" ]] || die '最终确认前目标 SSD 身份发生变化。'
[[ "$actual_bytes" -ge "$source_bytes" ]] || die '目标盘小于源盘容量。'
health="$PAW_REPORT_DIR/paw-hardware-health-report.json"
memory_state="$(python3 - "$health" "$target_serial" /proc/sys/kernel/random/boot_id <<'PY' || echo INVALID
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8")); boot=open(sys.argv[3]).read().strip()
assert d.get("status")=="PASS" and d.get("target_serial")==sys.argv[2] and d.get("boot_id")==boot
print(d.get("memory_status","UNKNOWN"))
PY
)"
[[ "$memory_state" == OPERATOR_CONFIRMED || "$memory_state" == PASS ]] || die '最终确认前硬件报告已过期、身份不匹配或内存检测未完成。'

# paw-console.service runs with StandardOutput=journal, so bare printf would
# only reach the journal and the data-loss panel would never appear on the
# physical console.  The whole authorization screen therefore goes through the
# verified tty1 fd; without a character device it falls back to inherited
# stdio so CI can still drive the same code path.
# shellcheck source=scripts/paw-tty-lib.sh
source "$PAW_ROOT/scripts/paw-tty-lib.sh"
export PAW_TTY_SESSION_NAME=final-confirm
paw_tty_open_optional || die '无法打开交互终端；未写入任何授权。'
paw_tty_clear
paw_tty_marker PAW-TTY1-FINAL-PANEL
paw_tty_say 'PAW 最终迁移授权（请完整阅读后再确认）'
paw_tty_say "硬件检查：PASS（内存验证方式：$memory_state）"
paw_tty_say "源系统：Rescue Mode，型号=${source_model:-未知}，容量=$source_bytes bytes，根分区=$root_part_no"
paw_tty_say "源盘序列号：${source_serial:-不可用（使用组合身份）}"
paw_tty_say "源盘组合身份：$source_composite"
paw_tty_say "固定 SSH 主机指纹：$source_host_fp"
paw_tty_say "目标 SSD：设备=$dst，型号=${target_model:-未知}，容量=$target_bytes bytes"
paw_tty_say "目标序列号：$target_serial"
paw_tty_say '数据来源：固定 SSH 主机指纹的 Rescue Mode 整盘流（远端 zstd，SSH 加密传输，本地解压写入）'
paw_tty_say '网络：本次启动已验证 Rescue SSH；不依赖旧 Ubuntu 内部的 VLESS/Tailscale 服务。'
paw_tty_say '数据损失：目标 SSD 的整盘内容将被源盘覆盖，目标盘原有分区和数据会全部丢失。'
paw_tty_say '恢复：离线修复前会在 PAWDATA 保留配置备份；但不等于可恢复目标盘原有数据。'
paw_tty_marker PAW-TTY1-FINAL-PROMPT
paw_tty_say '如确认覆盖，请输入目标 SSD 序列号最后 6 位：'
paw_tty_prompt '输入：'
suffix=''
if ! paw_tty_read suffix; then
  if ((PAW_TTY_READ_RC > 128)); then
    paw_tty_marker PAW-TTY1-FINAL-TIMEOUT
    paw_tty_say ''
    paw_tty_say "错误：等待授权输入超过 ${PAW_TTY_TIMEOUT} 秒，已安全停止，没有写入任何数据。"
    log WARN 'Final authorization input timed out; nothing was written.'
    paw_tty_close
    exit 2
  fi
  paw_tty_marker PAW-TTY1-FINAL-ABORTED
  paw_tty_say ''
  paw_tty_say '错误：未收到完整授权输入，已安全停止，没有写入任何数据。'
  log WARN 'Final authorization input was aborted; nothing was written.'
  paw_tty_close
  exit 2
fi
if [[ ${#target_serial} -lt 6 || "$suffix" != "${target_serial: -6}" ]]; then
  paw_tty_marker PAW-TTY1-FINAL-BAD
  paw_tty_say ''
  paw_tty_say '错误：确认值与目标 SSD 序列号不匹配，已安全停止，没有写入任何数据。'
  log WARN 'Final authorization suffix mismatched; nothing was written.'
  paw_tty_close
  exit 1
fi
paw_tty_marker PAW-TTY1-FINAL-OK
paw_tty_say ''
paw_tty_say '输入已确认；开始整盘覆盖迁移，请不要断电。'
paw_tty_close
unset suffix

before_serial="$(lsblk -dn -o SERIAL "$dst" | xargs)"; before_bytes="$(blockdev --getsize64 "$dst")"
[[ "$before_serial" == "$target_serial" && "$before_bytes" == "$target_bytes" ]] || die '最终写入前目标盘复核失败。'
PAW_EXPECTED_ROOT_UUID="$root_uuid" "$PAW_ROOT/scripts/paw-source-discovery.sh" >/dev/null
python3 - "$source_cfg" "$root_uuid" "$src" "$source_bytes" "$source_composite" "$source_host_fp" "$source_serial" <<'PY' || die '授权前源盘重新识别结果与登记不一致；已停止。'
import json,sys
cfg,uuid,dev,capacity,composite,host_fp,serial=sys.argv[1:]
d=json.load(open(cfg,encoding="utf-8"))
checks={
 "source_mode":d.get("source_mode")=="rescue",
 "device_path":d.get("device_path")==dev,
 "root_uuid":str(d.get("root_uuid","")).lower()==uuid.lower(),
 "capacity_bytes":int(d.get("capacity_bytes") or 0)==int(capacity),
 "composite_identity_sha256":d.get("composite_identity_sha256")==composite,
 "ssh_host_key_fingerprint":d.get("ssh_host_key_fingerprint")==host_fp,
 "serial_unchanged":str(d.get("serial") or "")==serial,
}
bad=[k for k,v in checks.items() if not v]
if bad: raise SystemExit("source identity changed: "+",".join(bad))
PY
python3 - "$PAW_REPORT_DIR/operator-authorization.json" "$dst" "$target_serial" "$src" "$root_uuid" "$source_composite" "$source_host_fp" "$memory_state" <<'PY'
import json,os,sys,datetime
path,dst,serial,src,uuid,composite,host_fp,memory=sys.argv[1:]
now=datetime.datetime.now(datetime.timezone.utc)
data={"status":"AUTHORIZED","target_device":dst,"target_serial":serial,"source_device":src,
 "source_root_uuid":uuid,"source_composite_identity_sha256":composite,
 "source_ssh_host_key_fingerprint":host_fp,"memory_verification":memory,
 "authorized_at":now.isoformat(),"expires_at":(now+datetime.timedelta(hours=6)).isoformat(),
 "confirmation":"target serial suffix typed interactively after full source and target re-identification"}
tmp=path+".tmp"
with open(tmp,"w",encoding="utf-8") as handle: json.dump(data,handle,indent=2)
os.chmod(tmp,0o600); os.replace(tmp,path)
PY
assert_authorization_for_target "$dst"
export PAW_DESTRUCTIVE_ARM=I_HAVE_VERIFIED_THE_TARGET_SERIAL
log INFO 'One-time operator authorization was recorded; the registered target workflow is starting.'

"$PAW_ROOT/scripts/paw-stream-clone.sh" "$src" "$dst"
"$PAW_ROOT/scripts/paw-stream-verify.sh" "$src" "$dst"
target_root="$(lsblk -nrpo NAME,PARTN "$dst" | awk -v n="$root_part_no" '$2==n {print $1; exit}')"
[[ -n "$target_root" && -b "$target_root" ]] || die 'Could not identify the cloned root partition by the confirmed source partition number.'
export PAW_REPAIR_ARM=I_HAVE_VERIFIED_OFFLINE_FILESYSTEM
"$PAW_ROOT/scripts/paw-offline-repair.sh" "$target_root"
export PAW_EXPAND_ARM=I_HAVE_VERIFIED_CLONE
"$PAW_ROOT/scripts/paw-gpt-expand.sh" "$dst" "$target_root"
"$PAW_ROOT/scripts/paw-firstboot-check.sh"
completion_data="$(mktemp "$PAW_REPORT_DIR/.migration-completion.XXXXXX")"
python3 - "$PAW_REPORT_DIR/operator-authorization.json" "$completion_data" <<'PY'
import datetime,hashlib,json,os,sys
auth,out=sys.argv[1:]
with open(auth,encoding="utf-8") as handle: authorization=json.load(handle)
report_dir=os.path.dirname(auth)
evidence={}
for name in ("stream-verify","offline-repair","gpt-expand","firstboot-check"):
    path=os.path.join(report_dir,name+".json")
    with open(path,"rb") as handle: evidence[name]=hashlib.sha256(handle.read()).hexdigest()
document={"schema":"paw.migration-completion.v2","status":"PASS",
 "target_serial_suffix":authorization["target_serial"][-6:],
 "completed_at":datetime.datetime.now(datetime.timezone.utc).isoformat(),
 "checks":{"clone":"PASS","sha256":"PASS","offline_repair":"PASS",
           "gpt_ext4_expand":"PASS","firstboot":"PASS"},
 "evidence_sha256":evidence}
with open(out,"w",encoding="utf-8") as handle:
    json.dump(document,handle,indent=2)
os.chmod(out,0o600)
PY
if ! "$PAW_ROOT/scripts/paw-finalize-reboot.sh" --completion-data "$completion_data" --authorization "$PAW_REPORT_DIR/operator-authorization.json" --receipt "$PAW_REPORT_DIR/migration-completion.json"; then
  rm -f "$completion_data"
  exit 1
fi
rm -f "$completion_data"
