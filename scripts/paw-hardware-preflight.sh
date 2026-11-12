#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/paw-lib.sh"
dev="${1:-}"; status=PASS; reasons=()
if [[ -z "$dev" || ! -b "$dev" ]]; then
  write_status BLOCKED 'Target SSD is absent; hardware checks not run.' "$PAW_REPORT_DIR/paw-hardware-health-report.json"
  log WARN 'Target SSD absent; no hardware checks were run.'; exit 3
fi

identity_blocked(){
  local reason="$1"
  python3 - "$PAW_REPORT_DIR/paw-ssd-identity.json" "$dev" "$reason" <<'PY' || true
import datetime,json,os,sys
path,dev,reason=sys.argv[1:]
doc={"schema":"paw.ssd-identity.v1","status":"BLOCKED","device":dev,"reason":reason,
 "updated_at":datetime.datetime.now(datetime.timezone.utc).isoformat()}
tmp=path+".tmp"
with open(tmp,"w",encoding="utf-8") as h: json.dump(doc,h,indent=2,ensure_ascii=False)
os.chmod(tmp,0o600); os.replace(tmp,path)
PY
  write_status BLOCKED "$reason" "$PAW_REPORT_DIR/paw-hardware-health-report.json"
  log WARN "SSD identity/safety gate blocked hardware checks: $reason"
  exit 3
}

# Identity gate: a block device name alone is never sufficient.  The unified
# helper compares the enrolled composite identity, including WWN/by-id/sysfs
# and (before the first write) the partition fingerprint.  A disk without a
# serial is accepted when it has another stable anchor; a disk with no stable
# anchor, or two indistinguishable disks, is refused.
enroll="$PAW_CONFIG_DIR/target-ssd.json"
[[ -r "$enroll" ]] || identity_blocked 'target SSD is not enrolled'
python3 - "$enroll" <<'PY' || identity_blocked 'target SSD enrollment is not approved or has no stable identity'
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
assert d.get("approved") is True
assert d.get("hardware_identity_sha256") or d.get("composite_identity_sha256") or d.get("serial")
if d.get("capacity_bytes") is not None:
    assert isinstance(d.get("capacity_bytes"),int) and d["capacity_bytes"]>0
PY
set +e
python3 "$PAW_ROOT/scripts/paw-identity.py" verify --config "$enroll" --device "$dev" --phase prewrite --check-unique \
  >"$PAW_REPORT_DIR/paw-ssd-identity.json" 2>"$PAW_REPORT_DIR/paw-ssd-identity.err"
identity_rc=$?
set -e
if (( identity_rc != 0 )); then
  reason="$(python3 - "$PAW_REPORT_DIR/paw-ssd-identity.json" <<'PY' 2>/dev/null || true
import json,sys
try:
    d=json.load(open(sys.argv[1],encoding="utf-8")); print(d.get("reason") or d.get("status") or "identity verification failed")
except Exception:
    print("identity verification failed")
PY
)"
  [[ -n "$reason" ]] || reason="identity verification failed (rc=$identity_rc)"
  identity_blocked "$reason"
fi
read -r actual_serial actual_model actual_bytes expected_serial expected_model expected_bytes < <(python3 - "$PAW_REPORT_DIR/paw-ssd-identity.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
vals=[d.get("serial") or "-", d.get("model") or "-", str(d.get("capacity_bytes") or 0),
      str(d.get("enrolled_serial") or "-"), str(d.get("enrolled_model") or "-"),
      str(d.get("enrolled_capacity_bytes") or 0)]
print(" ".join(v.replace(" ","_") for v in vals))
PY
)
mounted_on="$(lsblk -nrpo MOUNTPOINTS "$dev" | sed '/^$/d' | tr '\n' ' ' | xargs)"
[[ -z "$mounted_on" ]] || identity_blocked "target has mounted filesystem(s): $mounted_on"
live_source="$(findmnt -n -o SOURCE --target /run/live/medium 2>/dev/null || true)"
live_source="${live_source%%\[*}"
if [[ -n "$live_source" ]]; then
  live_disk="$live_source"
  if [[ "$(lsblk -dn -o TYPE "$live_source" 2>/dev/null | xargs)" != disk ]]; then
    live_parent="$(lsblk -dn -o PKNAME "$live_source" 2>/dev/null | xargs || true)"
    [[ -z "$live_parent" ]] || live_disk="/dev/$live_parent"
  fi
  [[ "$live_disk" != "$dev" ]] || identity_blocked 'device is the current PAW boot medium'
fi
source_dev=""
if [[ -r "$PAW_CONFIG_DIR/source.json" ]]; then
  source_dev="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("device_path") or "")' "$PAW_CONFIG_DIR/source.json")"
fi
[[ -z "$source_dev" || "$source_dev" != "$dev" ]] || identity_blocked 'device is the registered source disk'
python3 - "$PAW_REPORT_DIR/paw-ssd-identity.json" "$dev" <<'PY'
import datetime,json,os,sys
path,dev=sys.argv[1:]
with open(path,encoding="utf-8") as handle: doc=json.load(handle)
doc.update({"status":"PASS","device":dev,"boot_medium_excluded":True,
 "source_disk_excluded":True,"mounted":False,
 "updated_at":datetime.datetime.now(datetime.timezone.utc).isoformat()})
tmp=path+".tmp"
with open(tmp,"w",encoding="utf-8") as h: json.dump(doc,h,indent=2,ensure_ascii=False)
os.chmod(tmp,0o600); os.replace(tmp,path)
PY
identity_basis="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("identity_basis",""))' "$PAW_REPORT_DIR/paw-ssd-identity.json")"
log INFO "SSD identity verified by composite fingerprint: basis=$identity_basis serial=${actual_serial:--} bytes=$actual_bytes"
if "$PAW_ROOT/scripts/paw-ssd-smart-check.sh" "$dev"; then :; else
  rc=$?; reasons+=('SMART check failed or unsupported; inspect raw report')
  if ((rc == 2)); then status=WARN; else status=FAIL; fi
fi
if [[ $status == PASS ]]; then
  "$PAW_ROOT/scripts/paw-ssd-read-scan.sh" "$dev" || { status=FAIL; reasons+=('read-only surface scan failed'); }
fi
if command -v dmesg >/dev/null 2>&1; then
  # "Power-on or device reset occurred" is the normal sd(4) spin-up notice for
  # a disk that was just attached; it is not an I/O failure.  Keep every other
  # reset/timeout/error pattern fail-closed.
  dmesg | grep -Eai 'ata[0-9].*(reset|I/O error|timeout|link is slow|failed command)|nvme.*(reset|I/O|timeout)|I/O error|blk_update_request.*timeout|device reset' \
    | grep -Ev 'Power-on or device reset occurred' >"$PAW_REPORT_DIR/storage-kernel-errors.txt" || true
  [[ ! -s "$PAW_REPORT_DIR/storage-kernel-errors.txt" ]] || { [[ $status == FAIL ]] || status=WARN; reasons+=('Storage reset/I/O timeout/error found; inspect hardware'); }
else status=WARN; reasons+=('dmesg unavailable for SATA review'); fi

sensor_report="$PAW_REPORT_DIR/hardware-sensors.txt"
: >"$sensor_report"
if command -v sensors >/dev/null 2>&1 && sensors -A >"$sensor_report" 2>&1 && grep -Eq '[+-]?[0-9]+([.][0-9]+)?([^[:alnum:]]*C|degC)' "$sensor_report"; then
  log INFO 'CPU/mainboard sensor readings recorded; thresholds are not inferred.'
else
  [[ $status == FAIL ]] || status=WARN
  reasons+=('CPU/mainboard temperature sensors unavailable or returned no readings')
fi
if [[ "$dev" == /dev/nvme* ]] && command -v nvme >/dev/null 2>&1; then
  nvme smart-log "$dev" >"$PAW_REPORT_DIR/nvme-smart-log.txt" 2>&1 || { [[ $status == FAIL ]] || status=WARN; reasons+=('NVMe temperature/health log unavailable'); }
fi
smart_json="$PAW_REPORT_DIR/smart-$(basename "$dev").json"
if [[ -r "$smart_json" ]]; then
  smart_class="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("classification","UNKNOWN"))' "$smart_json" 2>/dev/null || echo UNKNOWN)"
  smart_state="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("status","UNKNOWN"))' "$smart_json" 2>/dev/null || echo UNKNOWN)"
  if [[ "$smart_state" != PASS ]]; then
    [[ $status == FAIL ]] || status=WARN
    reasons+=("SMART $smart_state ($smart_class)")
  fi
fi
smart_report="$PAW_REPORT_DIR/smart-$(basename "$dev").txt"
if [[ -r "$smart_report" ]] && grep -Eai 'UDMA_CRC_Error_Count|CRC_Error_Count' "$smart_report" | awk '($NF+0)>0 {found=1} END {exit !found}'; then
  [[ $status == FAIL ]] || status=WARN
  reasons+=('Nonzero SATA CRC error counter detected')
fi
# Temperature is a warning/failure signal, not a substitute for SMART overall
# health.  Values are only used when the drive actually reports a plausible
# Celsius reading; QEMU virtual disks have no sensor and remain unclassified.
temp_warn="${PAW_SSD_TEMP_WARN_C:-70}"
temp_fail="${PAW_SSD_TEMP_FAIL_C:-80}"
[[ "$temp_warn" =~ ^[0-9]{1,3}$ && "$temp_fail" =~ ^[0-9]{1,3}$ ]] || { temp_warn=70; temp_fail=80; }
if [[ -r "$smart_report" ]]; then
  temp_c="$(python3 - "$smart_report" <<'PY'
import re,sys
value=None
for line in open(sys.argv[1],encoding="utf-8",errors="replace"):
    if "Temperature_Celsius" in line:
        # smartctl attribute row: "... Always - 35 (Min/Max 20/45)"
        m=re.search(r"-\s+(\d{1,3})(?:\s|$)", line)
        if m and 0 < int(m.group(1)) <= 100:
            value=int(m.group(1)); break
    if re.search(r"Current Drive Temperature|^Temperature:", line):
        m=re.search(r"[:=]\s*(\d{1,3})(?:\s|$)", line)
        if m and 0 < int(m.group(1)) <= 100:
            value=int(m.group(1)); break
print(value if value is not None else "")
PY
)"
  if [[ "$temp_c" =~ ^[0-9]{1,3}$ ]]; then
    python3 - "$PAW_REPORT_DIR/paw-ssd-thermal.json" "$dev" "$temp_c" "$temp_warn" "$temp_fail" "$status" <<'PY'
import datetime,json,os,sys
path,dev,temp,warn,fail,state=sys.argv[1:]
doc={"schema":"paw.ssd-thermal.v1","device":dev,"temperature_celsius":int(temp),
 "warn_threshold_c":int(warn),"fail_threshold_c":int(fail),
 "classification":"PASS" if int(temp)<int(warn) else ("WARN" if int(temp)<int(fail) else "FAIL"),
 "updated_at":datetime.datetime.now(datetime.timezone.utc).isoformat()}
tmp=path+".tmp"
with open(tmp,"w",encoding="utf-8") as h: json.dump(doc,h,indent=2)
os.chmod(tmp,0o600); os.replace(tmp,path)
PY
    if (( temp_c >= temp_fail )); then
      status=FAIL; reasons+=("SSD temperature ${temp_c}C is at/above the fail threshold ${temp_fail}C")
    elif (( temp_c >= temp_warn )); then
      [[ $status == FAIL ]] || status=WARN
      reasons+=("SSD temperature ${temp_c}C is at/above the warning threshold ${temp_warn}C")
    fi
  else
    [[ $status == FAIL ]] || status=WARN
    reasons+=('SMART temperature could not be read; thermal state remains unclassified')
  fi
fi
"$PAW_ROOT/scripts/paw-memory-test-report.sh" >/dev/null 2>&1 || true
mem_report="$PAW_REPORT_DIR/memory-test.json"
mem_status="$(python3 - "$mem_report" <<'PY' 2>/dev/null || echo BLOCKED
import json,sys
try: print(json.load(open(sys.argv[1],encoding="utf-8")).get("status","BLOCKED"))
except Exception: print("BLOCKED")
PY
)"
case "$mem_status" in
  PASS|OPERATOR_CONFIRMED) ;;
  FAIL) status=FAIL; reasons+=("Memtest86+ result is ${mem_status}") ;;
  *) [[ $status == FAIL ]] || status=WARN; reasons+=("Memtest86+ result is ${mem_status}; manual confirmation is required") ;;
esac
write_status "$status" "${reasons[*]:-All currently supported checks passed}" "$PAW_REPORT_DIR/paw-hardware-health-report.json"
python3 - "$PAW_REPORT_DIR/paw-hardware-health-report.json" "$dev" "$mem_status" <<'PY'
import json,os,subprocess,sys,tempfile
path,dev,mem_status=sys.argv[1:]
def query(args):
    return subprocess.check_output(args,text=True,stderr=subprocess.DEVNULL).strip()
parent=query(["lsblk","-dn","-o","PKNAME",dev])
parent="/dev/"+parent if parent else dev
serial=query(["lsblk","-dn","-o","SERIAL",parent])
capacity=int(query(["blockdev","--getsize64",parent]))
with open(path,encoding="utf-8") as handle: data=json.load(handle)
data.update({"target_device":parent,"target_serial":serial,"target_capacity_bytes":capacity,
 "memory_status":mem_status,"memory_trust":"operator_attestation_not_cryptographic" if mem_status=="OPERATOR_CONFIRMED" else "unverified",
 "boot_id":open("/proc/sys/kernel/random/boot_id").read().strip()})
fd,tmp=tempfile.mkstemp(dir=os.path.dirname(path),prefix=".health-")
with os.fdopen(fd,"w",encoding="utf-8") as handle: json.dump(data,handle,indent=2)
os.chmod(tmp,0o600); os.replace(tmp,path)
PY
log INFO "health_status=$status"; [[ $status == PASS ]]
