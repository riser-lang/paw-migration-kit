#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/paw-lib.sh"
disk="${1:-}"; part="${2:-}"; [[ -n "$disk" && -n "$part" ]] || die 'Usage: paw-gpt-expand.sh DISK PARTITION'
require_sim_or_enrollment; [[ ${PAW_EXPAND_ARM:-} == 'I_HAVE_VERIFIED_CLONE' ]] || die 'Expansion requires explicit arm.'
if [[ ${PAW_SIMULATION:-0} == 1 ]]; then
  assert_sim_loop_device "$disk"
else
  assert_registered_target_device "$disk"; assert_authorization_for_target "$disk"
  assert_transaction_stage expand
  transaction_event EXPAND_STARTED
fi
expand_done=0
trap 'rc=$?; if ((rc != 0)) && [[ ${PAW_SIMULATION:-0} != 1 ]]; then transaction_event NEEDS_MANUAL_ACTION --phase expand --reason "gpt/ext4 expansion failed rc=$rc" || true; fi' EXIT
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
fs_before_blocks="$(dumpe2fs -h "$part" 2>/dev/null | awk '/^Block count:/{print $3; exit}')"
table="$PAW_REPORT_DIR/gpt-before-expand-$(basename "$disk").txt"
sfdisk --dump "$disk" >"$table"
chmod 0600 "$table"
sgdisk --move-second-header "$disk"
growpart_rc=0
growpart_out="$(growpart "$disk" "$n" 2>&1)" || growpart_rc=$?
printf '%s\n' "$growpart_out"
if ((growpart_rc != 0)); then
  if ((growpart_rc == 1)) && [[ "$growpart_out" == *NOCHANGE* ]]; then
    log INFO 'Partition is already at its maximum size; continuing to the filesystem check.'
  else
    die "growpart failed with rc=$growpart_rc"
  fi
fi
# udev workers and partition-table probes can briefly hold the resized node;
# e2fsck opens it O_EXCL and reports "is in use" until those probes finish.
command -v udevadm >/dev/null 2>&1 && udevadm settle --timeout=120 || true
rc=0
scan_holders(){
  local fd target found=0
  for fd in /proc/[0-9]*/fd/*; do
    target="$(readlink "$fd" 2>/dev/null)" || continue
    if [[ "$target" == "$part" ]]; then
      log WARN "Partition is still held by pid=${fd#/proc/} target=$target"
      found=1
    fi
  done
  ((found == 1)) || log INFO 'No process file descriptor points at the target partition.'
}
scan_holders
for attempt in $(seq 1 30); do
  mounted_now="$(lsblk -nrpo MOUNTPOINT "$part" 2>/dev/null | sed '/^$/d' | paste -sd, -)"
  if [[ -n "$mounted_now" ]]; then
    log WARN "Target root was mounted after partition growth at: $mounted_now; unmounting it before the mandatory filesystem check."
    while IFS= read -r mnt; do [[ -n "$mnt" ]] && umount "$mnt" || die "Could not unmount $mnt after growth."; done < <(lsblk -nrpo MOUNTPOINT "$part" 2>/dev/null | sed '/^$/d')
  fi
  if e2fsck -f -p "$part"; then rc=0; break; fi
  rc=$?
  ((rc == 1)) && break
  sleep 2
done
((rc == 0 || rc == 1)) || die 'Filesystem check after partition growth failed; no resize2fs was run.'
resize2fs "$part"
unset rc
after_bytes="$(blockdev --getsize64 "$part")"
fs_after_blocks="$(dumpe2fs -h "$part" 2>/dev/null | awk '/^Block count:/{print $3; exit}')"
if [[ ${PAW_SIMULATION:-0} != 1 ]]; then
  transaction_event READY_TO_BOOT
fi
expand_done=1
trap - EXIT
python3 - "$PAW_REPORT_DIR/gpt-expand.json" "$disk" "$part" "$n" "$before_bytes" "$after_bytes" "${fs_before_blocks:-0}" "${fs_after_blocks:-0}" <<'PY' | python3 "$PAW_ROOT/scripts/paw-atomic-write.py" "$PAW_REPORT_DIR/gpt-expand.json"
import datetime,json,sys
path,disk,part,number,before,after,fs_before,fs_after=sys.argv[1:]
document={"schema":"paw.gpt-expand.v1","status":"PASS","disk":disk,"partition":part,
 "partition_number":int(number),"before_bytes":int(before),"after_bytes":int(after),
 "grew":int(after)>int(before),"filesystem_before_blocks":int(fs_before),"filesystem_after_blocks":int(fs_after),"filesystem_grew":int(fs_after)>int(fs_before),"completed_at":datetime.datetime.now(datetime.timezone.utc).isoformat()}
sys.stdout.write(json.dumps(document,indent=2)+"\n")
PY
log INFO 'GPT backup header repaired and ext4 root partition/filesystem expanded.'
