#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/paw-lib.sh"
disk="${1:-}"; part="${2:-}"; [[ -n "$disk" && -n "$part" ]] || die 'Usage: paw-gpt-expand.sh DISK PARTITION'
require_sim_or_enrollment; [[ ${PAW_EXPAND_ARM:-} == 'I_HAVE_VERIFIED_CLONE' ]] || die 'Expansion requires explicit arm.'
if [[ ${PAW_SIMULATION:-0} == 1 ]]; then assert_sim_loop_device "$disk"; else assert_registered_target_device "$disk"; assert_authorization_for_target "$disk"; fi
for c in growpart resize2fs lsblk sgdisk sfdisk e2fsck; do need "$c"; done
[[ "$(lsblk -dn -o PTTYPE "$disk" | xargs)" == gpt ]] || die 'Target is not GPT.'
part_parent="$(parent_disk "$part")"; [[ "$part_parent" == "$disk" ]] || die 'Root partition is not on the registered target disk.'
[[ "$(lsblk -dn -o FSTYPE "$part" | xargs)" == ext4 ]] || die 'Root partition is not ext4.'
n="$(lsblk -dn -o PARTN "$part" | xargs)"; [[ "$n" =~ ^[0-9]+$ ]] || die 'Cannot determine partition number.'; assert_unmounted "$part"
# growpart can only take free space that follows the partition. If another partition
# starts later on the disk, the extension is impossible and the only symptom would be
# a cryptic growpart error after the GPT backup header was already moved. Refuse up
# front, before anything on the disk is touched.
part_start="$(lsblk -bnr -o START "$part" 2>/dev/null | xargs || true)"
last_start="$(lsblk -bnr -o START "$disk" 2>/dev/null | awk 'NF{print $1}' | sort -n | tail -n1 || true)"
if [[ -n "$part_start" && -n "$last_start" ]]; then
  ((part_start == last_start)) || die 'Root partition is not the last partition on the target disk; a later partition would collide, so nothing was changed. Remove or shrink the later partition, then rerun.'
else
  log WARN 'lsblk did not report partition start offsets; the last-partition guard was skipped.'
fi
before_bytes="$(blockdev --getsize64 "$part")"
table="$PAW_REPORT_DIR/gpt-before-expand-$(basename "$disk").txt"
sfdisk --dump "$disk" >"$table"
chmod 0600 "$table"
sgdisk --move-second-header "$disk"
growpart "$disk" "$n"
e2fsck -f -p "$part" || rc=$?
rc="${rc:-0}"
((rc == 0 || rc == 1)) || die 'Filesystem check after partition growth failed; no resize2fs was run.'
resize2fs "$part"
unset rc
after_bytes="$(blockdev --getsize64 "$part")"
python3 - "$PAW_REPORT_DIR/gpt-expand.json" "$disk" "$part" "$n" "$before_bytes" "$after_bytes" <<'PY' | python3 "$PAW_ROOT/scripts/paw-atomic-write.py" "$PAW_REPORT_DIR/gpt-expand.json"
import datetime,json,sys
path,disk,part,number,before,after=sys.argv[1:]
document={"schema":"paw.gpt-expand.v1","status":"PASS","disk":disk,"partition":part,
 "partition_number":int(number),"before_bytes":int(before),"after_bytes":int(after),
 "grew":int(after)>int(before),"completed_at":datetime.datetime.now(datetime.timezone.utc).isoformat()}
sys.stdout.write(json.dumps(document,indent=2)+"\n")
PY
log INFO 'GPT backup header repaired and ext4 root partition/filesystem expanded.'
