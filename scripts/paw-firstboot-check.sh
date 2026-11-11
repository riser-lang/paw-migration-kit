#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/paw-lib.sh"
# This script is intentionally post-boot only.  The pre-reboot gate lives in
# paw-preboot-handoff-check.sh; running this on the live ISO must fail rather
# than mislabel a pre-reboot check as a real first boot.
[[ ! -d /run/live ]] || die 'Refusing: /run/live exists, so this is the live system, not the cloned target first boot.'
[[ -r "$PAW_REPORT_DIR/preboot-handoff.json" ]] || die 'Pre-reboot handoff receipt is missing; cannot verify post-boot identity.'
python3 - "$PAW_REPORT_DIR/preboot-handoff.json" <<'PY' || die 'Pre-reboot handoff receipt is not PASS.'
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
assert d.get("schema")=="paw.preboot-handoff.v1" and d.get("status")=="PASS"
assert d.get("actual_first_boot_performed") is False
PY
root_source="$(findmnt -n -o SOURCE / | head -n1)"
root_uuid="$(blkid -s UUID -o value "$root_source" 2>/dev/null || true)"
expected_uuid="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("root_uuid",""))' "$PAW_CONFIG_DIR/source.json" 2>/dev/null || true)"
[[ "$root_uuid" =~ ^[0-9a-fA-F-]{36}$ ]] || die 'Post-boot root filesystem UUID is unreadable.'
[[ "$root_uuid" == "$expected_uuid" ]] || die 'Post-boot root UUID is not the cloned source UUID.'
live_boot_id="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("source_boot_id",""))' "$PAW_REPORT_DIR/preboot-handoff.json" 2>/dev/null || true)"
current_boot_id="$(cat /proc/sys/kernel/random/boot_id)"
[[ -n "$live_boot_id" && "$current_boot_id" != "$live_boot_id" ]] || die 'Boot ID did not change; this is not a new target boot.'
python3 - "$PAW_REPORT_DIR/firstboot-check.json" "$root_uuid" "$current_boot_id" "$live_boot_id" <<'PY' | python3 "$PAW_ROOT/scripts/paw-atomic-write.py" "$PAW_REPORT_DIR/firstboot-check.json"
import datetime,json,sys
path,uuid,boot_id,prev=sys.argv[1:]
doc={"schema":"paw.firstboot-check.v2","status":"PASS","phase":"post_boot",
 "checks":{"not_live_system":True,"root_uuid_matches_clone":True,
           "preboot_handoff_pass":True,"new_boot_id":True},
 "root_uuid":uuid,"boot_id":boot_id,"preboot_boot_id":prev,
 "actual_first_boot_performed":True,
 "completed_at":datetime.datetime.now(datetime.timezone.utc).isoformat()}
json.dump(doc,sys.stdout,indent=2); sys.stdout.write("\n")
PY
if [[ -r "$PAW_REPORT_DIR/migration-transaction.json" && -r "$PAW_CONFIG_DIR/source.json" && -r "$PAW_CONFIG_DIR/target-ssd.json" ]]; then
  assert_transaction_stage complete
  transaction_event COMPLETE
fi
log INFO 'Post-boot target identity verified; firstboot-check.json records a real first boot.'
