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

printf '\nPAW 最终迁移授权\n'
printf '硬件检查：PASS（内存：%s）\n' "$memory_state"
printf '源系统：Rescue Mode，型号=%s，容量=%s bytes，根分区=%s\n' "${source_model:-未知}" "$source_bytes" "$root_part_no"
printf '源盘序列号：%s\n' "${source_serial:-不可用（使用组合身份）}"
printf '源盘组合身份：%s\n' "$source_composite"
printf '固定 SSH 主机指纹：%s\n' "$source_host_fp"
printf '目标 SSD：设备=%s，型号=%s，容量=%s bytes\n' "$dst" "${target_model:-未知}" "$target_bytes"
printf '目标序列号：%s\n' "$target_serial"
printf '数据来源：固定 SSH 主机指纹的 Rescue Mode 整盘流（远端 zstd，SSH 加密传输，本地解压写入）\n'
printf '网络：本次启动已验证 Rescue SSH；不依赖旧 Ubuntu 内部的 VLESS/Tailscale 服务。\n'
printf '数据损失：目标 SSD 的整盘内容将被源盘覆盖，目标盘原有分区和数据会全部丢失。\n'
printf '恢复：离线修复前会在 PAWDATA 保留配置备份；但不等于可恢复目标盘原有数据。\n'
read -r -p '如确认覆盖，请输入目标 SSD 序列号最后 6 位：' suffix
[[ ${#target_serial} -ge 6 && "$suffix" == "${target_serial: -6}" ]] || die '确认值与目标 SSD 序列号不匹配。'
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
