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
read -r src root_uuid source_model source_serial source_bytes root_part_no < <(python3 - "$source_cfg" <<'PY'
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8")); print(*(str(d.get(k) or "") for k in ("device_path","root_uuid","model","serial","capacity_bytes","partition_number")))
PY
)
read -r dst target_model target_serial target_bytes < <(python3 - "$target_cfg" <<'PY'
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8")); print(*(str(d.get(k) or "") for k in ("device_path","model","serial","capacity_bytes")))
PY
)
[[ "$dst" =~ ^/dev/[A-Za-z0-9/]+$ && -b "$dst" && "$src" =~ ^/dev/[A-Za-z0-9/]+$ && "$root_part_no" =~ ^[1-9][0-9]*$ ]] || die '源盘或目标盘身份配置不完整。'
actual_serial="$(lsblk -dn -o SERIAL "$dst" | xargs)"; actual_bytes="$(blockdev --getsize64 "$dst")"
[[ "$actual_serial" == "$target_serial" && "$actual_bytes" == "$target_bytes" ]] || die '最终确认前目标 SSD 身份发生变化。'
[[ "$actual_bytes" -ge "$source_bytes" ]] || die '目标盘小于源盘容量。'
health="$PAW_REPORT_DIR/paw-hardware-health-report.json"
python3 - "$health" "$target_serial" <<'PY' || die '最终确认前硬件报告已过期或身份不匹配。'
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8")); boot=open("/proc/sys/kernel/random/boot_id").read().strip()
assert d.get("status")=="PASS" and d.get("target_serial")==sys.argv[2] and d.get("boot_id")==boot
PY

printf '\nPAW 最终迁移授权\n'
printf '硬件检查：PASS\n源系统：Rescue Mode，型号=%s，容量=%s bytes，序列号=%s\n' "$source_model" "$source_bytes" "$source_serial"
printf '目标 SSD：设备=%s，型号=%s，容量=%s bytes，序列号=%s\n' "$dst" "$target_model" "$target_bytes" "$target_serial"
printf '数据来源：固定 SSH 主机指纹的 Rescue Mode 整盘流\n网络：本次启动已验证 Rescue SSH；不依赖旧 Ubuntu 的 VLESS\n'
printf '影响：目标 SSD 整盘将被源盘覆盖；目标盘原有数据会丢失。\n'
read -r -p '如确认覆盖，请输入目标 SSD 序列号最后 6 位：' suffix
[[ ${#target_serial} -ge 6 && "$suffix" == "${target_serial: -6}" ]] || die '确认值与目标 SSD 序列号不匹配。'
unset suffix

before_serial="$(lsblk -dn -o SERIAL "$dst" | xargs)"; before_bytes="$(blockdev --getsize64 "$dst")"
[[ "$before_serial" == "$target_serial" && "$before_bytes" == "$target_bytes" ]] || die '最终写入前目标盘复核失败。'
PAW_EXPECTED_ROOT_UUID="$root_uuid" "$PAW_ROOT/scripts/paw-source-discovery.sh" >/dev/null
python3 - "$PAW_REPORT_DIR/operator-authorization.json" "$dst" "$target_serial" "$src" "$root_uuid" <<'PY'
import json,os,sys,datetime
path,dst,serial,src,uuid=sys.argv[1:]
now=datetime.datetime.now(datetime.timezone.utc)
data={"status":"AUTHORIZED","target_device":dst,"target_serial":serial,"source_device":src,"source_root_uuid":uuid,"authorized_at":now.isoformat(),"expires_at":(now+datetime.timedelta(hours=6)).isoformat(),"confirmation":"target serial suffix typed interactively"}
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
python3 - "$PAW_REPORT_DIR/operator-authorization.json" "$PAW_REPORT_DIR/migration-completion.json" <<'PY'
import json,os,sys,datetime
auth,receipt=sys.argv[1:]
with open(auth,encoding="utf-8") as handle: data=json.load(handle)
data["status"]="CONSUMED"; data["completed_at"]=datetime.datetime.now(datetime.timezone.utc).isoformat()
tmp=auth+".tmp"
with open(tmp,"w",encoding="utf-8") as handle: json.dump(data,handle,indent=2)
os.chmod(tmp,0o600); os.replace(tmp,auth)
with open(receipt,"w",encoding="utf-8") as handle: json.dump({"status":"PASS","target_serial_suffix":data["target_serial"][-6:],"completed_at":data["completed_at"]},handle,indent=2)
os.chmod(receipt,0o600)
PY
log INFO 'Clone, independent verification, offline adaptation, GPT/ext4 expansion and completion receipt succeeded.'
