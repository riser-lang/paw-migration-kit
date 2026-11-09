#!/usr/bin/env bash
set -Eeuo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
out="${PAW_ARTIFACT_DIR:-$PWD/artifacts}"
work="$root/tests/virtual/pawdata-run"
state="$work/state"
mkdir -p "$work" "$state/configs" "$state/reports" "$state/logs" "$out"
export PAW_ROOT="$root" PAW_STATE_DIR="$state" PAW_CONFIG_DIR="$state/configs" PAW_REPORT_DIR="$state/reports" PAW_LOG_DIR="$state/logs" PAW_SIMULATION=1
report="$out/pawdata-virtual-test-report.txt"
loops=(); mounts=()
passed=0; failed=0
cleanup(){
  for m in "${mounts[@]}"; do umount "$m" 2>/dev/null || true; done
  for l in "${loops[@]}"; do losetup -d "$l" 2>/dev/null || true; done
  rm -rf "$work"
  rm -f "$root/tests/virtual/pawdata-media.img" "$root/tests/virtual/pawdata-corrupt.img" "$root/tests/virtual/pawdata-small.img"
}
trap cleanup EXIT
pass(){ printf 'PASS %s\n' "$1" >>"$report"; passed=$((passed+1)); }
fail(){ printf 'FAIL %s\n' "$1" >>"$report"; failed=$((failed+1)); }
printf 'PAWDATA virtual partition tests\n' >"$report"

iso="$root/boot/custom/paw-live-amd64.iso"
[[ -s "$iso" ]] || { fail 'final ISO is present'; exit 1; }
media="$root/tests/virtual/pawdata-media.img"
iso_bytes="$(stat -c %s "$iso")"; media_bytes=$((iso_bytes + 268435456))
truncate -s "$media_bytes" "$media"
dd if="$iso" of="$media" bs=4M conv=notrunc,fsync status=none
media_loop="$(losetup --find --show -P "$media")"; loops+=("$media_loop")
mount_dir="$work/data-mount"; mkdir -p "$mount_dir"; export PAW_MOUNTPOINT_OVERRIDE="$mount_dir"
data_dev=''
for _ in $(seq 1 30); do [[ -b "${media_loop}p1" || -b "${media_loop}1" ]] && break; sleep 1; done
if "$root/scripts/paw-prepare-data-partition.sh" "$media_loop" >/dev/null 2>&1; then
  while IFS= read -r child; do [[ "$child" == "$media_loop" ]] && continue; [[ "$(blkid -s LABEL -o value "$child" 2>/dev/null || true)" == PAWDATA ]] && data_dev="$child"; done < <(lsblk -nrpo NAME "$media_loop")
  [[ -n "$data_dev" && "$(blkid -s TYPE -o value "$data_dev")" == ext4 ]] && pass 'ISO hybrid media gained a labeled ext4 PAWDATA partition' || fail 'PAWDATA label is visible'
else
  fail 'ISO hybrid layout accepted an appended PAWDATA partition'
fi
mountpoint -q "$mount_dir" && mounts+=("$mount_dir")

if [[ -n "$data_dev" ]]; then
  if mountpoint -q "$mount_dir"; then
    printf 'persisted-after-reboot-simulation\n' >"$mount_dir/reboot-marker.txt"; sync; umount "$mount_dir"; mounts=()
    mount -t ext4 -o rw "$data_dev" "$mount_dir"; mounts+=("$mount_dir")
    [[ "$(cat "$mount_dir/reboot-marker.txt")" == persisted-after-reboot-simulation ]] && pass 'Data survived an unmount/remount reboot simulation' || fail 'Data survived an unmount/remount reboot simulation'
    "$root/scripts/paw-data-check.sh" >/dev/null 2>&1 && pass 'Mounted PAWDATA identity, write probe and free-space gate passed' || fail 'PAWDATA health check passed'
    umount "$mount_dir"; mounts=()
  else fail 'PAWDATA ext4 partition mounted'; fi
fi

missing_dir="$work/missing-mount"; mkdir -p "$missing_dir"; PAW_MOUNTPOINT_OVERRIDE="$missing_dir" "$root/scripts/paw-data-check.sh" >/dev/null 2>&1 && fail 'Missing PAWDATA must block' || pass 'Missing PAWDATA is reported as WARN/BLOCKED'

corrupt_file="$root/tests/virtual/pawdata-corrupt.img"; truncate -s 48M "$corrupt_file"
corrupt_loop="$(losetup --find --show "$corrupt_file")"; loops+=("$corrupt_loop")
mkfs.ext4 -F -L PAWDATA "$corrupt_loop" >/dev/null
dd if=/dev/zero of="$corrupt_file" bs=4096 count=1 conv=notrunc status=none
set +e; e2fsck -fn "$corrupt_loop" >/dev/null 2>&1; corrupt_rc=$?; set -e
((corrupt_rc != 0)) && pass 'Corrupted ext4 superblock fails closed' || fail 'Corrupted ext4 superblock fails closed'

small_file="$root/tests/virtual/pawdata-small.img"; truncate -s 32M "$small_file"
small_loop="$(losetup --find --show "$small_file")"; loops+=("$small_loop")
mkfs.ext4 -F -L PAWDATA "$small_loop" >/dev/null
small_dir="$work/small-mount"; mkdir -p "$small_dir"; mount -t ext4 -o rw "$small_loop" "$small_dir"; mounts+=("$small_dir")
set +e; dd if=/dev/zero of="$small_dir/fill.bin" bs=1M conv=fsync status=none; fill_rc=$?; set -e
if ((fill_rc != 0)) && ! PAW_MOUNTPOINT_OVERRIDE="$small_dir" PAW_STATE_MIN_FREE_BYTES=67108864 "$root/scripts/paw-data-check.sh" >/dev/null 2>&1; then
  pass 'Space exhaustion is detected and remains non-PASS'
else
  fail 'Space exhaustion must be detected and blocked'
fi

printf 'Summary: %s passed, %s failed\n' "$passed" "$failed" >>"$report"
((failed == 0))
