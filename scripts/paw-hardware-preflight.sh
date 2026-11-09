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
  dmesg | grep -Eai 'ata[0-9].*(reset|I/O error|timeout|link is slow|failed command)' >"$PAW_REPORT_DIR/sata-kernel-errors.txt" || true
  [[ ! -s "$PAW_REPORT_DIR/sata-kernel-errors.txt" ]] || { [[ $status == FAIL ]] || status=WARN; reasons+=('SATA errors/resets found; inspect cable, power and port'); }
else status=WARN; reasons+=('dmesg unavailable for SATA review'); fi
mem_report="$PAW_REPORT_DIR/memory-test.json"
if [[ ! -r "$mem_report" ]]; then [[ $status == FAIL ]] || status=WARN; reasons+=('Memtest86+ result absent')
elif grep -q '"status"[[:space:]]*:[[:space:]]*"FAIL"' "$mem_report"; then status=FAIL; reasons+=('Memtest86+ reports FAIL')
elif ! grep -q '"status"[[:space:]]*:[[:space:]]*"PASS"' "$mem_report"; then [[ $status == FAIL ]] || status=WARN; reasons+=('Memtest86+ result is not PASS'); fi
write_status "$status" "${reasons[*]:-All currently supported checks passed}" "$PAW_REPORT_DIR/paw-hardware-health-report.json"
log INFO "health_status=$status"; [[ $status == PASS ]]
