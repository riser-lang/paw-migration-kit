#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/paw-lib.sh"
[[ -f "$PAW_REPORT_DIR/stream-verify.json" ]] || die 'No clone verification receipt.'
grep -Eq '"status"[[:space:]]*:[[:space:]]*"PASS"' "$PAW_REPORT_DIR/stream-verify.json" || die 'Clone verification not PASS.'
[[ ! -e "$PAW_REPORT_DIR/CLONE-INCOMPLETE" ]] || die 'Clone incomplete marker exists.'
[[ -r "$PAW_CONFIG_DIR/target-ssd.json" ]] || die 'Target enrollment absent.'
[[ -r "$PAW_REPORT_DIR/paw-hardware-health-report.json" ]] && grep -q '"status"[[:space:]]*:[[:space:]]*"PASS"' "$PAW_REPORT_DIR/paw-hardware-health-report.json" || die 'Hardware health report is not PASS.'
log INFO 'First boot check passed; production networking is untouched.'
