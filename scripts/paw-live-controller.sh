#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/paw-lib.sh"
status=READY_FOR_OPERATOR; details=()
mkdir -p "$PAW_CONFIG_DIR" "$PAW_REPORT_DIR" "$PAW_LOG_DIR"
for name in source target-ssd; do
  template="$PAW_ROOT/configs/$name.template.json"
  [[ -r "$template" ]] || continue
  [[ -e "$PAW_CONFIG_DIR/$name.json" ]] || cp "$template" "$PAW_CONFIG_DIR/$name.json"
done
if [[ "$PAW_STATE_DIR" != /var/lib/paw-migration ]]; then status=BLOCKED; details+=('persistent PAWDATA partition not mounted; reports would be volatile'); fi
"$PAW_ROOT/scripts/paw-live-preflight.sh" || { status=BLOCKED; details+=('live preflight failed'); }
"$PAW_ROOT/scripts/paw-source-discovery.sh" || { status=BLOCKED; details+=('source not enrolled or discovery failed'); }
target_dev=''
if [[ -r "$PAW_CONFIG_DIR/target-ssd.json" ]]; then
  target_dev="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("device_path") or "")' "$PAW_CONFIG_DIR/target-ssd.json")"
  target_approved="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(str(d.get("approved",False)).lower())' "$PAW_CONFIG_DIR/target-ssd.json")"
  expected_serial="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("serial") or "")' "$PAW_CONFIG_DIR/target-ssd.json")"
  expected_bytes="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("capacity_bytes") or "")' "$PAW_CONFIG_DIR/target-ssd.json")"
  if [[ "$target_approved" == true && -b "$target_dev" && -n "$expected_serial" && "$expected_bytes" =~ ^[0-9]+$ ]]; then
    actual_serial="$(lsblk -dn -o SERIAL "$target_dev" | xargs)"
    actual_bytes="$(lsblk -dnbo SIZE "$target_dev" | xargs)"
    if [[ "$actual_serial" == "$expected_serial" && "$actual_bytes" == "$expected_bytes" ]]; then
      "$PAW_ROOT/scripts/paw-hardware-preflight.sh" "$target_dev" || { status=BLOCKED; details+=('target hardware health is not PASS'); }
    else
      status=BLOCKED; details+=('target SSD serial or capacity does not match enrollment')
    fi
  else
    status=BLOCKED; details+=('target SSD identity is not approved and enrolled')
    "$PAW_ROOT/scripts/paw-hardware-preflight.sh" || true
  fi
else
  status=BLOCKED; details+=('target SSD not enrolled')
  "$PAW_ROOT/scripts/paw-hardware-preflight.sh" || true
fi
if [[ ! -r "$PAW_REPORT_DIR/paw-hardware-health-report.json" ]] || ! grep -q '"status"[[:space:]]*:[[:space:]]*"PASS"' "$PAW_REPORT_DIR/paw-hardware-health-report.json"; then status=BLOCKED; details+=('hardware health report missing or not PASS'); fi
[[ -r "$PAW_CONFIG_DIR/source.json" ]] || { status=BLOCKED; details+=('source not enrolled'); }
printf '{"status":"%s","details":"%s","updated_at":"%s"}\n' "$status" "$(json_escape "${details[*]:-All readiness inputs present; human review still required}")" "$(date -u +%FT%TZ)" >"$PAW_REPORT_DIR/live-readiness.json"
log INFO "AUTOSTART_GATE=$status clone_started=false ${details[*]:-}"
# Deliberately never starts paw-stream-clone.sh. A human must review and arm it.
exit 0
