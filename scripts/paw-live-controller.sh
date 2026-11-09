#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/paw-lib.sh"
status=READY_FOR_OPERATOR; details=(); checks=()
mkdir -p "$PAW_CONFIG_DIR" "$PAW_REPORT_DIR" "$PAW_LOG_DIR"
for name in source target-ssd; do
  template="$PAW_ROOT/configs/$name.template.json"
  [[ -r "$template" ]] && [[ -e "$PAW_CONFIG_DIR/$name.json" ]] || { [[ -r "$template" ]] && cp "$template" "$PAW_CONFIG_DIR/$name.json"; }
done

data_status=BLOCKED
if "$PAW_ROOT/scripts/paw-data-check.sh" >/dev/null 2>&1; then data_status=PASS; else data_status="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("status","BLOCKED"))' "$PAW_REPORT_DIR/paw-data-health.json" 2>/dev/null || echo BLOCKED)"; fi
checks+=("data=$data_status")
[[ "$data_status" == PASS ]] || { status=BLOCKED; details+=('PAWDATA 缺失、不可写或剩余空间不足；进度和报告不能保证持久化'); }

"$PAW_ROOT/scripts/paw-live-preflight.sh" >/dev/null 2>&1 || { status=BLOCKED; details+=('Live 环境预检失败'); }

source_status=BLOCKED
if [[ -r "$PAW_CONFIG_DIR/source.json" && -r /run/paw-network/source-discovery-session.json ]]; then
  if python3 - "$PAW_CONFIG_DIR/source.json" /run/paw-network/source-discovery-session.json <<'PY'
import json,sys
s=json.load(open(sys.argv[1],encoding="utf-8")); d=json.load(open(sys.argv[2],encoding="utf-8"))
boot=open("/proc/sys/kernel/random/boot_id").read().strip()
assert s.get("source_mode")=="rescue" and s.get("device_path") and d.get("status")=="PASS" and d.get("boot_id")==boot
PY
  then source_status=PASS; fi
fi
checks+=("source=$source_status")
[[ "$source_status" == PASS ]] || { status=BLOCKED; details+=('本次启动尚未通过固定主机指纹的 Rescue SSH 源盘复核'); }

target_identity_status=BLOCKED; hardware_status=BLOCKED; target_dev=''; target_model=''; target_serial=''; target_capacity=''
if [[ -r "$PAW_CONFIG_DIR/target-ssd.json" ]]; then
  read -r target_dev target_model target_serial target_capacity target_approved < <(python3 - "$PAW_CONFIG_DIR/target-ssd.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8")); print(*(str(d.get(k) or "") for k in ("device_path","model","serial","capacity_bytes","approved")))
PY
  )
  if [[ "$target_approved" == True && -b "$target_dev" && -n "$target_serial" && "$target_capacity" =~ ^[0-9]+$ ]]; then
    actual_serial="$(lsblk -dn -o SERIAL "$target_dev" | xargs)"; actual_capacity="$(blockdev --getsize64 "$target_dev")"
    if [[ "$actual_serial" == "$target_serial" && "$actual_capacity" == "$target_capacity" ]]; then
      target_identity_status=PASS
      if [[ "$source_status" == PASS && -r "$PAW_REPORT_DIR/paw-hardware-health-report.json" ]] && python3 - "$PAW_REPORT_DIR/paw-hardware-health-report.json" "$target_serial" <<'PY'
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8")); boot=open("/proc/sys/kernel/random/boot_id").read().strip()
assert d.get("status")=="PASS" and d.get("target_serial")==sys.argv[2] and d.get("boot_id")==boot
PY
      then hardware_status=PASS
      else hardware_status="$(python3 - "$PAW_REPORT_DIR/paw-hardware-health-report.json" "$target_serial" <<'PY'
import json,sys
try:
 d=json.load(open(sys.argv[1],encoding="utf-8")); boot=open("/proc/sys/kernel/random/boot_id").read().strip()
 s=d.get("status","BLOCKED")
 print(s if s in ("WARN","FAIL") else "BLOCKED" if s!="PASS" else "STALE_OR_TARGET_MISMATCH")
except Exception: print("BLOCKED")
PY
      )"; fi
    else details+=('目标 SSD 型号/容量/序列号与登记不一致，或源盘尚未确认'); fi
  else details+=('目标 SSD 尚未通过只读盘点和登记'); fi
else details+=('目标 SSD 尚未登记'); fi
checks+=("target_identity=$target_identity_status")
checks+=("hardware=$hardware_status")
[[ "$target_identity_status" == PASS && "$hardware_status" == PASS ]] || { status=BLOCKED; details+=('SMART、只读扫描、温度或内存检查未全部 PASS，或尚未完成本次启动的硬件检查'); }

network_status="$source_status"
checks+=("network=$network_status")
[[ "$network_status" == PASS ]] || status=BLOCKED

python3 - "$PAW_REPORT_DIR/live-readiness.json" "$status" "${checks[*]}" "${details[*]:-需要最终人工复核}" <<'PY'
import json,os,sys,datetime
path,status,check_text,detail_text=sys.argv[1:]
checks={k:v for item in check_text.split() for k,v in [item.split("=",1)]}
tmp=path+".tmp"
with open(tmp,"w",encoding="utf-8") as handle:
    json.dump({"status":status,"checks":checks,"details":detail_text,"updated_at":datetime.datetime.now(datetime.timezone.utc).isoformat(),"clone_started":False},handle,indent=2)
os.chmod(tmp,0o600); os.replace(tmp,path)
PY

printf '\nPAW 迁移准备状态\n'
printf '持久化分区：%s\n源系统识别：%s\n目标 SSD 身份：%s\n硬件检查：%s\nRescue SSH 网络：%s\n' "$data_status" "$source_status" "$target_identity_status" "$hardware_status" "$network_status"
printf '自动克隆：未启动\n'
if [[ "$status" != READY_FOR_OPERATOR ]]; then printf '状态：阻断\n原因：%s\n' "${details[*]}"; else printf '%s\n' '状态：全部检查通过；等待 paw-final-confirm 中文界面的一次性授权。'; fi
log INFO "AUTOSTART_GATE=$status clone_started=false ${details[*]:-}"
exit 0
