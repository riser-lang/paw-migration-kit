#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/paw-lib.sh"
# Refuse to show the one-time destructive authorization panel unless the
# same-boot console-font report proves fbcon 16x16 PASS.  Read-only reports stay
# available through the menu and journal.
require_console_font_pass
readiness="$PAW_REPORT_DIR/live-readiness.json"
[[ -r "$readiness" ]] || die '请先运行准备检查.'
python3 - "$readiness" <<'PY' || { printf '%s\n' '阻断:硬件,源盘,目标盘,网络和 PAWDATA 必须全部 PASS;当前不会出现确认输入.'; exit 2; }
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
assert d.get("status")=="READY_FOR_OPERATOR"
assert d.get("clone_started") is False
assert d.get("checks") and all(v=="PASS" for v in d["checks"].values())
PY

"$PAW_ROOT/scripts/paw-data-check.sh" >/dev/null
source_cfg="$PAW_CONFIG_DIR/source.json"; target_cfg="$PAW_CONFIG_DIR/target-ssd.json"
[[ -r "$source_cfg" && -r "$target_cfg" ]] || die '源盘或目标盘登记不存在.'
source_fields=()
mapfile -d '' -t source_fields < <(python3 - "$source_cfg" <<'PY'
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
sys.stdout.write("".join(str(d.get(k) or "")+"\0" for k in ("device_path","root_uuid","model","serial","capacity_bytes","partition_number","composite_identity_sha256","ssh_host_key_fingerprint")))
PY
)
src="${source_fields[0]:-}"; root_uuid="${source_fields[1]:-}"; source_model="${source_fields[2]:-}"; source_serial="${source_fields[3]:-}"; source_bytes="${source_fields[4]:-}"; root_part_no="${source_fields[5]:-}"; source_composite="${source_fields[6]:-}"; source_host_fp="${source_fields[7]:-}"
unset source_fields
# The enrolled path is a locator.  Re-scan and resolve the same physical disk
# after any hot-plug, reboot or /dev/sdX renumbering.  An ambiguous or missing
# identity stops here instead of selecting the first same-capacity disk.
resolved="$(python3 "$PAW_ROOT/scripts/paw-identity.py" resolve --config "$target_cfg" 2>/dev/null)" \
  || die '目标 SSD 的稳定身份无法单独定位;拒绝继续.'
dst="$(python3 -c 'import json,sys;print(json.load(sys.stdin).get("device_path",""))' <<<"$resolved")"
configured_dst="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("device_path",""))' "$target_cfg")"
if [[ -n "$dst" && "$dst" != "$configured_dst" ]]; then
  python3 - "$target_cfg" "$dst" <<'PY'
import json,os,sys
path,new=sys.argv[1:]
d=json.load(open(path,encoding="utf-8"))
d["previous_device_path"]=d.get("device_path","")
d["device_path"]=new
tmp=path+".tmp"
with open(tmp,"w",encoding="utf-8") as h: json.dump(d,h,indent=2,ensure_ascii=False)
os.chmod(tmp,0o600); os.replace(tmp,path)
PY
  log WARN "Target device path moved ${configured_dst:-unknown} -> $dst; stable identity re-resolved."
fi
target_fields=()
mapfile -d '' -t target_fields < <(python3 - "$target_cfg" <<'PY'
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
keys=("device_path","model","serial","capacity_bytes","wwn","by_id","identity_basis",
      "hardware_identity_sha256","composite_identity_sha256")
sys.stdout.write("".join(
    (",".join(d.get(k) or []) if k == "by_id" else str(d.get(k) or ""))+"\0" for k in keys))
PY
)
dst="${target_fields[0]:-}"; target_model="${target_fields[1]:-}"; target_serial="${target_fields[2]:-}"; target_bytes="${target_fields[3]:-}"
target_wwn="${target_fields[4]:-}"; target_by_id="${target_fields[5]:-}"; target_basis="${target_fields[6]:-}"
target_hw="${target_fields[7]:-}"; target_comp="${target_fields[8]:-}"
unset target_fields
[[ "$dst" =~ ^/dev/[A-Za-z0-9/]+$ && -b "$dst" && "$src" =~ ^/dev/[A-Za-z0-9/]+$ && "$root_part_no" =~ ^[1-9][0-9]*$ ]] || die '源盘或目标盘身份配置不完整.'
[[ "$source_bytes" =~ ^[0-9]+$ && "$target_bytes" =~ ^[0-9]+$ ]] || die '源盘或目标盘容量登记无效.'
[[ "$source_composite" =~ ^[0-9a-f]{64}$ ]] || die '源盘组合身份哈希缺失;请重新执行 Rescue 源盘识别.'
[[ "$source_host_fp" == SHA256:* ]] || die '源盘固定 SSH 主机指纹缺失;请重新执行 Rescue 源盘识别.'
[[ -n "$target_hw" || ( -n "$target_serial" && "$target_serial" != "-" ) ]] || die '目标 SSD 缺少稳定身份;不能仅凭设备名或容量授权.'
# Pre-write verification includes the partition fingerprint.  If the disk was
# replaced or re-partitioned after enrolment, this fails closed.
python3 "$PAW_ROOT/scripts/paw-identity.py" verify --config "$target_cfg" --device "$dst" \
  --phase prewrite --check-unique >"$PAW_REPORT_DIR/paw-target-final-identity.json" 2>/dev/null \
  || die '最终确认前目标 SSD 身份发生变化或存在同身份歧义.'
actual_bytes="$(blockdev --getsize64 "$dst")"
[[ "$actual_bytes" == "$target_bytes" ]] || die '最终确认前目标 SSD 容量发生变化.'
[[ "$actual_bytes" -ge "$source_bytes" ]] || die '目标盘小于源盘容量.'
health="$PAW_REPORT_DIR/paw-hardware-health-report.json"
memory_state="$(python3 - "$health" "$target_serial" /proc/sys/kernel/random/boot_id <<'PY' || echo INVALID
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8")); boot=open(sys.argv[3]).read().strip()
assert d.get("status")=="PASS" and d.get("target_serial")==sys.argv[2] and d.get("boot_id")==boot
print(d.get("memory_status","UNKNOWN"))
PY
)"
[[ "$memory_state" == OPERATOR_CONFIRMED || "$memory_state" == PASS ]] || die '最终确认前硬件报告已过期,身份不匹配或内存检测未完成.'

# paw-console.service runs with StandardOutput=journal, so bare printf would
# only reach the journal and the data-loss panel would never appear on the
# physical console.  The whole authorization screen therefore goes through the
# verified tty1 fd; without a character device it falls back to inherited
# stdio so CI can still drive the same code path.
# shellcheck source=scripts/paw-tty-lib.sh
source "$PAW_ROOT/scripts/paw-tty-lib.sh"
export PAW_TTY_SESSION_NAME=final-confirm
paw_tty_open_optional || die '无法打开交互终端;未写入任何授权.'
paw_tty_clear
paw_tty_marker PAW-TTY1-FINAL-PANEL
paw_tty_say 'PAW 最终迁移授权(请完整阅读后再确认)'
paw_tty_say "硬件检查:PASS(内存验证方式:$memory_state)"
paw_tty_say "源系统:Rescue Mode,型号=${source_model:-未知},容量=$source_bytes bytes,根分区=$root_part_no"
paw_tty_say "源盘序列号:${source_serial:-不可用(使用组合身份)}"
paw_tty_say "源盘组合身份:$source_composite"
paw_tty_say "固定 SSH 主机指纹:$source_host_fp"
paw_tty_say "目标 SSD:设备=$dst,型号=${target_model:-未知},容量=$target_bytes bytes"
paw_tty_say "目标序列号:${target_serial:-不可用(使用稳定硬件指纹)}"
paw_tty_say "目标身份依据:${target_basis:-未知}"
paw_tty_say "目标硬件指纹:${target_hw:-旧版仅序列号登记}"
paw_tty_say '数据来源:固定 SSH 主机指纹的 Rescue Mode 整盘流(远端 zstd,SSH 加密传输,本地解压写入)'
paw_tty_say '网络:本次启动已验证 Rescue SSH;不依赖旧 Ubuntu 内部的 VLESS/Tailscale 服务.'
paw_tty_say '数据损失:目标 SSD 的整盘内容将被源盘覆盖,目标盘原有分区和数据会全部丢失.'
paw_tty_say '恢复:离线修复前会在 PAWDATA 保留配置备份;但不等于可恢复目标盘原有数据.'
paw_tty_marker PAW-TTY1-FINAL-PROMPT
if [[ ${#target_serial} -ge 6 && "$target_serial" != "-" ]]; then
  confirm_value="${target_serial: -6}"; confirm_label='目标 SSD 序列号最后 6 位'
else
  confirm_value="${target_hw: -8}"; confirm_label='目标稳定硬件指纹最后 8 位'
fi
[[ ${#confirm_value} -ge 6 ]] || die '目标稳定身份过短;拒绝生成无法复核的授权提示.'
paw_tty_say "如确认覆盖,请输入${confirm_label}:"
paw_tty_prompt '输入:'
suffix=''
if ! paw_tty_read suffix; then
  if ((PAW_TTY_READ_RC > 128)); then
    paw_tty_marker PAW-TTY1-FINAL-TIMEOUT
    paw_tty_say ''
    paw_tty_say "错误:等待授权输入超过 ${PAW_TTY_TIMEOUT} 秒,已安全停止,没有写入任何数据."
    log WARN 'Final authorization input timed out; nothing was written.'
    paw_tty_close
    exit 2
  fi
  paw_tty_marker PAW-TTY1-FINAL-ABORTED
  paw_tty_say ''
  paw_tty_say '错误:未收到完整授权输入,已安全停止,没有写入任何数据.'
  log WARN 'Final authorization input was aborted; nothing was written.'
  paw_tty_close
  exit 2
fi
if [[ "$suffix" != "$confirm_value" ]]; then
  paw_tty_marker PAW-TTY1-FINAL-BAD
  paw_tty_say ''
  paw_tty_say '错误:确认值与目标 SSD 稳定身份不匹配,已安全停止,没有写入任何数据.'
  log WARN 'Final authorization confirmation mismatched; nothing was written.'
  paw_tty_close
  exit 1
fi
paw_tty_marker PAW-TTY1-FINAL-OK
paw_tty_say ''
paw_tty_say '输入已确认;开始整盘覆盖迁移,请不要断电.'
paw_tty_close
unset suffix

# Last checkpoint before any destructive write.  Re-resolve and re-hash the
# physical disk; a swap after the operator typed the confirmation must abort.
resolved2="$(python3 "$PAW_ROOT/scripts/paw-identity.py" resolve --config "$target_cfg" 2>/dev/null)" \
  || die '最终写入前目标盘稳定身份复核失败.'
dst2="$(python3 -c 'import json,sys;print(json.load(sys.stdin).get("device_path",""))' <<<"$resolved2")"
[[ -n "$dst2" && -b "$dst2" ]] || die '最终写入前目标盘不存在.'
python3 "$PAW_ROOT/scripts/paw-identity.py" verify --config "$target_cfg" --device "$dst2" \
  --phase prewrite --check-unique >"$PAW_REPORT_DIR/paw-target-final-identity.json" 2>/dev/null \
  || die '最终写入前目标盘稳定身份复核失败.'
dst="$dst2"
before_bytes="$(blockdev --getsize64 "$dst")"
[[ "$before_bytes" == "$target_bytes" ]] || die '最终写入前目标盘容量复核失败.'
PAW_EXPECTED_ROOT_UUID="$root_uuid" "$PAW_ROOT/scripts/paw-source-discovery.sh" >/dev/null
python3 - "$source_cfg" "$root_uuid" "$src" "$source_bytes" "$source_composite" "$source_host_fp" "$source_serial" <<'PY' || die '授权前源盘重新识别结果与登记不一致;已停止.'
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
python3 - "$PAW_REPORT_DIR/operator-authorization.json" "$dst" "$target_serial" "$target_model" "$target_bytes" \
  "$target_hw" "$target_comp" "$target_wwn" "$target_by_id" "$target_basis" \
  "$src" "$root_uuid" "$source_composite" "$source_host_fp" "$source_model" "$source_serial" "$source_bytes" "$memory_state" <<'PY'
import datetime,json,os,sys,uuid
(path,dst,serial,tmodel,tbytes,thw,tcomp,twwn,tbyid,tbasis,
 src,uuid_value,composite,host_fp,smodel,sserial,sbytes,memory)=sys.argv[1:]
now=datetime.datetime.now(datetime.timezone.utc)
data={"status":"AUTHORIZED",
 "migration_id":str(uuid.uuid4()),"authorization_id":str(uuid.uuid4()),
 "target_device":dst,"target_serial":serial,"target_model":tmodel,"target_capacity_bytes":int(tbytes),
 "target_hardware_identity_sha256":thw,"target_composite_identity_sha256":tcomp,
 "target_wwn":twwn,"target_by_id":[x for x in tbyid.split(",") if x],"target_identity_basis":tbasis,
 "target_confirmation_method":("serial_suffix" if len(serial) >= 6 and serial != "-" else "hardware_fingerprint_suffix"),
 "source_device":src,"source_root_uuid":uuid_value,"source_model":smodel,"source_serial":sserial,
 "source_capacity_bytes":int(sbytes),
 "source_composite_identity_sha256":composite,
 "source_ssh_host_key_fingerprint":host_fp,"memory_verification":memory,
 "authorized_at":now.isoformat(),"expires_at":(now+datetime.timedelta(hours=6)).isoformat(),
 "confirmation":"target stable identity typed interactively after full source and target re-identification"}
tmp=path+".tmp"
with open(tmp,"w",encoding="utf-8") as handle: json.dump(data,handle,indent=2)
os.chmod(tmp,0o600); os.replace(tmp,path)
PY
transaction_init
assert_authorization_for_target "$dst"
assert_transaction_stage authorization
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
"$PAW_ROOT/scripts/paw-preboot-handoff-check.sh"
completion_data="$(mktemp "$PAW_REPORT_DIR/.migration-completion.XXXXXX")"
python3 - "$PAW_REPORT_DIR/operator-authorization.json" "$completion_data" <<'PY'
import datetime,hashlib,json,os,sys
auth,out=sys.argv[1:]
with open(auth,encoding="utf-8") as handle: authorization=json.load(handle)
report_dir=os.path.dirname(auth)
evidence={}
for name in ("stream-verify","offline-repair","gpt-expand","preboot-handoff"):
    path=os.path.join(report_dir,name+".json")
    with open(path,"rb") as handle: evidence[name]=hashlib.sha256(handle.read()).hexdigest()
document={"schema":"paw.migration-completion.v2","status":"PASS",
 "target_serial_suffix":(authorization["target_serial"][-6:] if authorization.get("target_serial") else authorization["target_hardware_identity_sha256"][-8:]),
 "completed_at":datetime.datetime.now(datetime.timezone.utc).isoformat(),
 "checks":{"clone":"PASS","sha256":"PASS","offline_repair":"PASS",
           "gpt_ext4_expand":"PASS","preboot_handoff":"PASS"},
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
