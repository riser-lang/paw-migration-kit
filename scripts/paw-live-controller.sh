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
[[ "$data_status" == PASS ]] || { status=BLOCKED; details+=('PAWDATA 自动初始化未完成,不可写或剩余空间不足;请按控制台中文提示核对启动卡序列号末六位'); }

"$PAW_ROOT/scripts/paw-live-preflight.sh" >/dev/null 2>&1 || { status=BLOCKED; details+=('Live 环境预检失败'); }

network_dir="${PAW_NETWORK_DIR:-/run/paw-network}"
source_status=BLOCKED
if [[ -r "$PAW_CONFIG_DIR/source.json" && -r "$network_dir/source-discovery-session.json" ]]; then
  if python3 - "$PAW_CONFIG_DIR/source.json" "$network_dir/source-discovery-session.json" <<'PY'
import json,sys
s=json.load(open(sys.argv[1],encoding="utf-8")); d=json.load(open(sys.argv[2],encoding="utf-8"))
boot=open("/proc/sys/kernel/random/boot_id").read().strip()
assert s.get("source_mode")=="rescue" and s.get("device_path") and d.get("status")=="PASS" and d.get("boot_id")==boot
assert len(str(s.get("composite_identity_sha256") or ""))==64
assert str(s.get("ssh_host_key_fingerprint") or "").startswith("SHA256:")
PY
  then source_status=PASS; fi
fi
checks+=("source=$source_status")
[[ "$source_status" == PASS ]] || { status=BLOCKED; details+=('本次启动尚未通过固定主机指纹的 Rescue SSH 源盘复核'); }

target_cfg="$PAW_CONFIG_DIR/target-ssd.json"
target_identity_status=BLOCKED; hardware_status=BLOCKED; target_dev=''; target_model=''; target_serial=''; target_capacity=''; target_hw=''; target_comp=''; target_basis=''
if [[ -r "$target_cfg" ]]; then
  target_fields=()
  mapfile -d '' -t target_fields < <(python3 - "$target_cfg" <<'PY'
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
keys=("device_path","model","serial","capacity_bytes","approved","hardware_identity_sha256","composite_identity_sha256","identity_basis")
sys.stdout.write("".join(str(d.get(k) or "")+"\0" for k in keys))
PY
  )
  target_dev="${target_fields[0]:-}"; target_model="${target_fields[1]:-}"; target_serial="${target_fields[2]:-}"; target_capacity="${target_fields[3]:-}"; target_approved="${target_fields[4]:-}"
  target_hw="${target_fields[5]:-}"; target_comp="${target_fields[6]:-}"; target_basis="${target_fields[7]:-}"
  unset target_fields
  if [[ "$target_approved" == True && "$target_capacity" =~ ^[1-9][0-9]*$ ]] && [[ -n "$target_hw" || -n "$target_comp" || -n "$target_serial" ]]; then
    resolved_dev=""
    if resolved_json="$(python3 "$PAW_ROOT/scripts/paw-identity.py" resolve --config "$target_cfg" 2>/dev/null)"; then
      resolved_dev="$(python3 -c 'import json,sys;print(json.load(sys.stdin).get("device_path",""))' <<<"$resolved_json")"
    elif [[ "$target_dev" =~ ^/dev/[A-Za-z0-9/]+$ && -b "$target_dev" && "$(lsblk -dn -o TYPE "$target_dev" 2>/dev/null | xargs || true)" == loop ]]; then
      resolved_dev="$target_dev"
    fi
    if [[ "$resolved_dev" =~ ^/dev/[A-Za-z0-9/]+$ && -b "$resolved_dev" ]]; then
      target_dev="$resolved_dev"
      set +e
      python3 "$PAW_ROOT/scripts/paw-identity.py" verify --config "$target_cfg" --device "$target_dev" --phase prewrite --check-unique \
        >"$PAW_REPORT_DIR/paw-controller-target-identity.json" 2>"$PAW_REPORT_DIR/paw-controller-target-identity.err"
      verify_rc=$?
      set -e
      actual_capacity="$(blockdev --getsize64 "$target_dev" 2>/dev/null || echo 0)"
      mounted_on="$(lsblk -nrpo MOUNTPOINTS "$target_dev" 2>/dev/null | sed '/^$/d' | tr '\n' ' ' | xargs || true)"
      src_dev_cfg=""
      [[ -r "$PAW_CONFIG_DIR/source.json" ]] && src_dev_cfg="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1],encoding="utf-8")).get("device_path") or "")' "$PAW_CONFIG_DIR/source.json" 2>/dev/null || true)"
      if (( verify_rc == 0 )) && [[ "$actual_capacity" == "$target_capacity" && -z "$mounted_on" ]] && [[ -z "$src_dev_cfg" || "$src_dev_cfg" != "$target_dev" ]]; then
        target_identity_status=PASS
        if [[ "$source_status" == PASS && -r "$PAW_REPORT_DIR/paw-hardware-health-report.json" ]] && python3 - "$PAW_REPORT_DIR/paw-hardware-health-report.json" "$target_serial" "$target_hw" "$target_capacity" <<'PY'
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8")); boot=open("/proc/sys/kernel/random/boot_id").read().strip()
expected_serial,expected_hw,expected_bytes=sys.argv[2:]
assert d.get("status")=="PASS" and d.get("boot_id")==boot
if d.get("target_capacity_bytes") is not None:
    assert int(d["target_capacity_bytes"])==int(expected_bytes)
if "memory_status" in d:
    assert d["memory_status"] in ("PASS","OPERATOR_CONFIRMED")
health_hw=str(d.get("target_hardware_identity_sha256") or "")
health_serial=str(d.get("target_serial") or "")
if expected_hw and health_hw:
    assert health_hw==expected_hw
    if expected_serial:
        assert health_serial==expected_serial
else:
    assert expected_serial and health_serial==expected_serial
PY
        then hardware_status=PASS
        else hardware_status="$(python3 - "$PAW_REPORT_DIR/paw-hardware-health-report.json" <<'PY'
import json,sys
try:
 d=json.load(open(sys.argv[1],encoding="utf-8"))
 s=d.get("status","BLOCKED")
 print(s if s in ("WARN","FAIL") else "BLOCKED" if s!="PASS" else "STALE_OR_TARGET_MISMATCH")
except Exception: print("BLOCKED")
PY
        )"; fi
      else
        ident_reason="$(python3 - "$PAW_REPORT_DIR/paw-controller-target-identity.json" <<'PY' 2>/dev/null || true
import json,sys
try: print(json.load(open(sys.argv[1],encoding="utf-8")).get("reason") or "")
except Exception: pass
PY
)"
        details+=("目标 SSD 稳定身份/容量/安全状态复核未通过${ident_reason:+: $ident_reason}")
      fi
    else
      details+=('目标 SSD 稳定身份无法单独定位(设备缺失或存在同身份歧义)')
    fi
  else details+=('目标 SSD 尚未通过只读盘点和稳定身份登记'); fi
else details+=('目标 SSD 尚未登记'); fi
checks+=("target_identity=$target_identity_status")
checks+=("hardware=$hardware_status")
[[ "$target_identity_status" == PASS && "$hardware_status" == PASS ]] || { status=BLOCKED; details+=('SMART,只读扫描,温度或内存检查未全部 PASS,或尚未完成本次启动的硬件检查'); }
if [[ "$hardware_status" != PASS && -r "$PAW_REPORT_DIR/memory-test.json" ]]; then
  mem_state="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("status","UNKNOWN"))' "$PAW_REPORT_DIR/memory-test.json" 2>/dev/null || echo UNKNOWN)"
  [[ "$mem_state" == OPERATOR_CONFIRMED || "$mem_state" == PASS ]] || details+=("内存检测状态=$mem_state;请从 Memtest86+ 菜单完成检测后回到 PAW Live,运行 /opt/paw-migration/scripts/paw-memtest-confirm.sh 登记")
fi

network_status="$source_status"
checks+=("network=$network_status")
[[ "$network_status" == PASS ]] || status=BLOCKED

python3 - "$PAW_REPORT_DIR/live-readiness.json" "$status" "${checks[*]}" "${details[*]:-需要最终人工复核}" "$target_dev" "$target_model" "$target_capacity" "$target_serial" "$target_hw" "$target_basis" <<'PY'
import json,os,sys,datetime
path,status,check_text,detail_text,tdev,tmodel,tcap,tser,thw,tbasis=sys.argv[1:]
checks={k:v for item in check_text.split() for k,v in [item.split("=",1)]}
doc={"status":status,"checks":checks,"details":detail_text,"updated_at":datetime.datetime.now(datetime.timezone.utc).isoformat(),"clone_started":False}
if tdev: doc["target_device"]=tdev
if tmodel: doc["target_model"]=tmodel
if tcap.isdecimal(): doc["target_capacity_bytes"]=int(tcap)
if tser: doc["target_serial"]=tser
if thw: doc["target_hardware_identity_sha256"]=thw
if tbasis: doc["target_identity_basis"]=tbasis
tmp=path+".tmp"
with open(tmp,"w",encoding="utf-8") as handle:
    json.dump(doc,handle,indent=2,ensure_ascii=False)
os.chmod(tmp,0o600); os.replace(tmp,path)
PY

printf '\nPAW 迁移准备状态\n'
printf '持久化分区:%s\n源系统识别:%s\n目标 SSD 身份:%s\n硬件检查:%s\nRescue SSH 网络:%s\n' "$data_status" "$source_status" "$target_identity_status" "$hardware_status" "$network_status"
if [[ "$data_status" != PASS ]]; then
  printf 'PAWDATA 首次准备:启动服务已自动尝试;如未完成,请按上方中文提示核对序列号末六位,或运行 /opt/paw-migration/scripts/paw-data-prepare.sh.\n'
fi
printf '自动克隆:未启动\n'
if [[ "$status" != READY_FOR_OPERATOR ]]; then printf '状态:阻断\n原因:%s\n' "${details[*]}"; else printf '%s\n' '状态:全部检查通过;等待 paw-final-confirm 中文界面的一次性授权.'; fi
log INFO "AUTOSTART_GATE=$status clone_started=false ${details[*]:-}"
exit 0
