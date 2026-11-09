#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/paw-lib.sh"
dev="${1:-}"; status=PASS; reasons=()
if [[ -z "$dev" || ! -b "$dev" ]]; then
  write_status WARN 'Target SSD is absent; hardware checks not run.' "$PAW_REPORT_DIR/paw-hardware-health-report.json"
  log WARN 'Target SSD absent; no hardware checks were run.'; exit 2
fi
if "$PAW_ROOT/scripts/paw-ssd-smart-check.sh" "$dev"; then :; else
  rc=$?; reasons+=('SMART check failed or unsupported; inspect raw report')
  if ((rc == 2)); then status=WARN; else status=FAIL; fi
fi
if [[ $status == PASS ]]; then
  "$PAW_ROOT/scripts/paw-ssd-read-scan.sh" "$dev" || { status=FAIL; reasons+=('read-only surface scan failed'); }
fi
if command -v dmesg >/dev/null 2>&1; then
  dmesg | grep -Eai 'ata[0-9].*(reset|I/O error|timeout|link is slow|failed command)|nvme.*(reset|I/O|timeout)|I/O error|blk_update_request.*timeout|device reset' >"$PAW_REPORT_DIR/storage-kernel-errors.txt" || true
  [[ ! -s "$PAW_REPORT_DIR/storage-kernel-errors.txt" ]] || { [[ $status == FAIL ]] || status=WARN; reasons+=('Storage reset/I/O timeout/error found; inspect hardware'); }
else status=WARN; reasons+=('dmesg unavailable for SATA review'); fi

sensor_report="$PAW_REPORT_DIR/hardware-sensors.txt"
: >"$sensor_report"
if command -v sensors >/dev/null 2>&1 && sensors -A >"$sensor_report" 2>&1 && grep -Eq '[+-]?[0-9]+([.][0-9]+)?°C' "$sensor_report"; then
  log INFO 'CPU/mainboard sensor readings recorded; thresholds are not inferred.'
else
  [[ $status == FAIL ]] || status=WARN
  reasons+=('CPU/mainboard temperature sensors unavailable or returned no readings')
fi
if [[ "$dev" == /dev/nvme* ]] && command -v nvme >/dev/null 2>&1; then
  nvme smart-log "$dev" >"$PAW_REPORT_DIR/nvme-smart-log.txt" 2>&1 || { [[ $status == FAIL ]] || status=WARN; reasons+=('NVMe temperature/health log unavailable'); }
fi
smart_report="$PAW_REPORT_DIR/smart-$(basename "$dev").txt"
if [[ -r "$smart_report" ]] && grep -Eai 'UDMA_CRC_Error_Count|CRC_Error_Count' "$smart_report" | awk '($NF+0)>0 {found=1} END {exit !found}'; then
  [[ $status == FAIL ]] || status=WARN
  reasons+=('Nonzero SATA CRC error counter detected')
fi
mem_report="$PAW_REPORT_DIR/memory-test.json"
if [[ ! -r "$mem_report" ]]; then [[ $status == FAIL ]] || status=WARN; reasons+=('Memtest86+ result absent')
elif grep -q '"status"[[:space:]]*:[[:space:]]*"FAIL"' "$mem_report"; then status=FAIL; reasons+=('Memtest86+ reports FAIL')
elif ! grep -q '"status"[[:space:]]*:[[:space:]]*"PASS"' "$mem_report"; then [[ $status == FAIL ]] || status=WARN; reasons+=('Memtest86+ result is not PASS'); fi
write_status "$status" "${reasons[*]:-All currently supported checks passed}" "$PAW_REPORT_DIR/paw-hardware-health-report.json"
python3 - "$PAW_REPORT_DIR/paw-hardware-health-report.json" "$dev" <<'PY'
import json,os,subprocess,sys,tempfile
path,dev=sys.argv[1:]
def query(args):
    return subprocess.check_output(args,text=True,stderr=subprocess.DEVNULL).strip()
parent=query(["lsblk","-dn","-o","PKNAME",dev])
parent="/dev/"+parent if parent else dev
serial=query(["lsblk","-dn","-o","SERIAL",parent])
capacity=int(query(["blockdev","--getsize64",parent]))
with open(path,encoding="utf-8") as handle: data=json.load(handle)
data.update({"target_device":parent,"target_serial":serial,"target_capacity_bytes":capacity,"boot_id":open("/proc/sys/kernel/random/boot_id").read().strip()})
fd,tmp=tempfile.mkstemp(dir=os.path.dirname(path),prefix=".health-")
with os.fdopen(fd,"w",encoding="utf-8") as handle: json.dump(data,handle,indent=2)
os.chmod(tmp,0o600); os.replace(tmp,path)
PY
log INFO "health_status=$status"; [[ $status == PASS ]]
