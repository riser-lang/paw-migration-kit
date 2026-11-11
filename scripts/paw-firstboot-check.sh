#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/paw-lib.sh"
[[ -f "$PAW_REPORT_DIR/stream-verify.json" ]] || die 'No clone verification receipt.'
grep -Eq '"status"[[:space:]]*:[[:space:]]*"PASS"' "$PAW_REPORT_DIR/stream-verify.json" || die 'Clone verification not PASS.'
[[ ! -e "$PAW_REPORT_DIR/CLONE-INCOMPLETE" ]] || die 'Clone incomplete marker exists.'
[[ -r "$PAW_CONFIG_DIR/target-ssd.json" ]] || die 'Target enrollment absent.'
[[ -r "$PAW_REPORT_DIR/paw-hardware-health-report.json" ]] && grep -q '"status"[[:space:]]*:[[:space:]]*"PASS"' "$PAW_REPORT_DIR/paw-hardware-health-report.json" || die 'Hardware health report is not PASS.'
python3 - "$PAW_REPORT_DIR/firstboot-check.json" <<'PY' | python3 "$PAW_ROOT/scripts/paw-atomic-write.py" "$PAW_REPORT_DIR/firstboot-check.json"
import datetime,json,os,sys
report=sys.argv[1]
with open(os.path.join(os.path.dirname(report),"stream-verify.json"),encoding="utf-8") as handle:
    verify=json.load(handle)
document={"schema":"paw.firstboot-check.v1","status":"PASS",
 "checks":{"clone_verify_pass":True,"clone_incomplete_marker_absent":True,
           "target_enrollment_present":True,"hardware_health_pass":True},
 "clone_sha256":verify.get("sha256"),
 "completed_at":datetime.datetime.now(datetime.timezone.utc).isoformat()}
sys.stdout.write(json.dumps(document,indent=2)+"\n")
PY
log INFO 'First boot check passed; production networking is untouched.'
