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
for c in growpart resize2fs lsblk sgdisk sfdisk e2fsck mount umount; do need "$c"; done
[[ "$(lsblk -dn -o PTTYPE "$disk" | xargs)" == gpt ]] || die 'Target is not GPT.'
part_parent="$(parent_disk "$part")"; [[ "$part_parent" == "$disk" ]] || die 'Root partition is not on the registered target disk.'
[[ "$(lsblk -dn -o FSTYPE "$part" | xargs)" == ext4 ]] || die 'Root partition is not ext4.'
n="$(lsblk -dn -o PARTN "$part" | xargs)"; [[ "$n" =~ ^[0-9]+$ ]] || die 'Cannot determine partition number.'; assert_unmounted "$part"
# growpart can only take free space that follows the partition. If another partition
# starts later on the disk, the extension is impossible and the only symptom would be
# a cryptic growpart error after the GPT backup header was already moved. Refuse up
# front, before anything on the disk is touched.
command -v udevadm >/dev/null 2>&1 && udevadm settle --timeout=30 || true
part_start="$(lsblk -bnr -o START "$part" 2>/dev/null | xargs || true)"
last_start="$(lsblk -bnr -o START "$disk" 2>/dev/null | awk 'NF{print $1}' | sort -n | tail -n1 || true)"
if [[ -z "$part_start" || -z "$last_start" ]]; then
  # Loop/partition nodes can appear a moment before lsblk reports START.
  # Give udev/partprobe a second chance, then fall back to the on-disk table
  # rather than silently skipping the collision guard.
  sleep 1
  udevadm settle --timeout=30 2>/dev/null || true
  part_start="$(lsblk -bnr -o START "$part" 2>/dev/null | xargs || true)"
  last_start="$(lsblk -bnr -o START "$disk" 2>/dev/null | awk 'NF{print $1}' | sort -n | tail -n1 || true)"
fi
if [[ -z "$part_start" ]]; then
  part_start="$(sfdisk -d "$disk" 2>/dev/null | awk -v n="$n" '{path=$1; sub(/:$/,"",path); if (path ~ ("[^0-9]" n "$")) { if (match($0,/start= *[0-9]+/)) { v=substr($0,RSTART+6,RLENGTH-6); gsub(/ /,"",v); print v; exit } }}')"
fi
if [[ -z "$last_start" ]]; then
  last_start="$(sfdisk -d "$disk" 2>/dev/null | sed -n 's/.*start= *\([0-9][0-9]*\).*/\1/p' | sort -n | tail -n1)"
fi
[[ -n "$part_start" && -n "$last_start" ]] || die 'Cannot determine partition start offsets; refusing to expand because the later-partition collision guard cannot be proven.'
((part_start == last_start)) || die 'Root partition is not the last partition on the target disk; a later partition would collide, so nothing was changed. Remove or shrink the later partition, then rerun.'
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
  lsblk -nrpo NAME,MAJ:MIN,MOUNTPOINT "$disk" "$part" 2>/dev/null | sed '/^$/d' | while IFS= read -r line; do log INFO "lsblk: $line"; done
}
scan_holders
for attempt in $(seq 1 30); do
  mounted_now="$(lsblk -nrpo MOUNTPOINT "$part" 2>/dev/null | sed '/^$/d' | paste -sd, -)"
  if [[ -n "$mounted_now" ]]; then
    log WARN "Target root was mounted after partition growth at: $mounted_now; unmounting it before the mandatory filesystem check."
    while IFS= read -r mnt; do [[ -n "$mnt" ]] && umount "$mnt" || die "Could not unmount $mnt after growth."; done < <(lsblk -nrpo MOUNTPOINT "$part" 2>/dev/null | sed '/^$/d')
  fi
  command -v udevadm >/dev/null 2>&1 && udevadm settle --timeout=30 || true
  set +e
  fsck_out="$(e2fsck -f -p "$part" 2>&1)"
  rc=$?
  set -e
  printf '%s\n' "$fsck_out" | sed '/^$/d' | tail -n 20
  if ((rc == 0)); then
    break
  fi
  # A transient udev/partition-probe holder makes e2fsck abort with
  # "is in use" or "Device or resource busy".  Retry explicitly instead of
  # treating that as a corrected-filesystem success (which would let
  # resize2fs run against a busy node and fail).
  if [[ "$fsck_out" == *'is in use'* || "$fsck_out" == *'Device or resource busy'* || "$fsck_out" == *'resource busy'* ]]; then
    log WARN "Target partition is transiently busy (e2fsck rc=$rc, attempt=$attempt/30); waiting before retry."
    sleep 3 || true
    continue
  fi
  if ((rc == 1)); then
    break
  fi
  die "Filesystem check after partition growth failed with rc=$rc; no resize2fs was run."
done
fsck_method='offline'
if [[ "$fsck_out" == *'is in use'* || "$fsck_out" == *'Device or resource busy'* || "$fsck_out" == *'resource busy'* ]]; then
  # Offline e2fsck takes O_EXCL.  A mount left in another mount namespace by
  # the just-finished offline repair makes O_EXCL fail even though the device
  # node looks unmounted in this namespace.  ext4 supports an online grow, so
  # mount the already-checked filesystem here (the repair ran e2fsck -f -n and
  # mounted it read-write) and let resize2fs grow the mounted superblock.  The
  # report records this path explicitly; it is not claimed as an offline fsck.
  log WARN 'Partition remains busy across mount namespaces after 30 offline checks; using mounted ext4 online resize instead of unsafe/unavailable O_EXCL fsck.'
  online_mount="${TMPDIR:-/tmp}/paw-online-resize-$$"
  install -d -m 0700 "$online_mount"
  mount -o rw "$part" "$online_mount" || die 'Target is busy and could not be mounted for an online ext4 resize; expansion stopped.'
  if ! resize2fs "$part" >&2; then
    umount "$online_mount" 2>/dev/null || true
    rmdir "$online_mount" 2>/dev/null || true
    die 'Online ext4 resize failed; expansion stopped.'
  fi
  sync
  umount "$online_mount" || die 'Online resize succeeded but the temporary mount could not be unmounted; refusing to claim READY_TO_BOOT.'
  rmdir "$online_mount" 2>/dev/null || true
  fsck_method='online_mounted_resize_after_namespace_holder'
  rc=0
else
  if ((rc != 0 && rc != 1)); then die 'Filesystem check after partition growth did not complete; no resize2fs was run.'; fi
  resize2fs "$part"
fi
unset rc
after_bytes="$(blockdev --getsize64 "$part")"
fs_after_blocks="$(dumpe2fs -h "$part" 2>/dev/null | awk '/^Block count:/{print $3; exit}')"
if [[ ${PAW_SIMULATION:-0} != 1 ]]; then
  transaction_event READY_TO_BOOT
fi
expand_done=1
trap - EXIT
python3 - "$PAW_REPORT_DIR/gpt-expand.json" "$disk" "$part" "$n" "$before_bytes" "$after_bytes" "${fs_before_blocks:-0}" "${fs_after_blocks:-0}" "$fsck_method" <<'PY' | python3 "$PAW_ROOT/scripts/paw-atomic-write.py" "$PAW_REPORT_DIR/gpt-expand.json"
import datetime,json,sys
path,disk,part,number,before,after,fs_before,fs_after,fsck_method=sys.argv[1:]
document={"schema":"paw.gpt-expand.v1","status":"PASS","disk":disk,"partition":part,
 "partition_number":int(number),"before_bytes":int(before),"after_bytes":int(after),
 "grew":int(after)>int(before),"filesystem_before_blocks":int(fs_before),"filesystem_after_blocks":int(fs_after),"filesystem_grew":int(fs_after)>int(fs_before),"filesystem_check_method":fsck_method,"completed_at":datetime.datetime.now(datetime.timezone.utc).isoformat()}
sys.stdout.write(json.dumps(document,indent=2)+"\n")
PY
log INFO 'GPT backup header repaired and ext4 root partition/filesystem expanded.'
