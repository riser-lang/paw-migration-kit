#!/usr/bin/env bash
set -Eeuo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
out="${PAW_ARTIFACT_DIR:-$PWD/artifacts}"
work="$root/tests/virtual/pawdata-run"
state="$work/state"
mock="$work/mockbin"
mkdir -p "$work" "$state/configs" "$state/reports" "$state/logs" "$out" "$mock"
export PAW_ROOT="$root" PAW_STATE_DIR="$state" PAW_CONFIG_DIR="$state/configs" PAW_REPORT_DIR="$state/reports" PAW_LOG_DIR="$state/logs" PAW_SIMULATION=1
report="$out/pawdata-virtual-test-report.txt"
loops=(); mounts=()
passed=0; failed=0
cleanup(){
  for m in "${mounts[@]}"; do umount "$m" 2>/dev/null || true; done
  for l in "${loops[@]}"; do losetup -d "$l" 2>/dev/null || true; done
  rm -rf "$work"
  rm -f "$root/tests/virtual/pawdata-media.img" "$root/tests/virtual/pawdata-corrupt.img" "$root/tests/virtual/pawdata-small.img" "$root/tests/virtual/pawdata-gpt.img"
}
trap cleanup EXIT
pass(){ printf 'PASS %s\n' "$1" >>"$report"; passed=$((passed+1)); }
fail(){ printf 'FAIL %s\n' "$1" >>"$report"; failed=$((failed+1)); }
printf 'PAWDATA virtual partition tests\n' >"$report"

cat >"$mock/lsblk" <<'MOCKLSBLK'
#!/usr/bin/env bash
last="${!#}"
if [[ " $* " == *" -o SERIAL "* && "$last" == "${PAW_MOCK_MEDIA_DEVICE:-}" ]]; then
  printf '%s\n' "${PAW_MOCK_MEDIA_SERIAL:-CI-MEDIA-123456}"
  exit 0
fi
exec /usr/bin/lsblk "$@"
MOCKLSBLK
chmod 0755 "$mock/lsblk"
export PATH="$mock:$PATH" PAW_MOCK_MEDIA_SERIAL='CI-MEDIA-123456'

snapshot(){
  local disk="$1" file="$2"
  sfdisk --json "$disk" >"$file"
}
partition_one(){
  python3 - "$1" <<'PY'
import json,sys
parts=json.load(open(sys.argv[1],encoding="utf-8"))["partitiontable"].get("partitions") or []
p=next((x for x in parts if int(x.get("start",-1))>=0),None)
if not p: raise SystemExit("no partitions")
print(int(p.get("start")),int(p.get("size")),str(p.get("type","")))
PY
}
count_parts(){
  python3 - "$1" <<'PY'
import json,sys
print(len(json.load(open(sys.argv[1],encoding="utf-8"))["partitiontable"].get("partitions") or []))
PY
}
wait_part(){
  local disk="$1" n="$2" part=''
  for _ in $(seq 1 30); do
    for cand in "${disk}p${n}" "${disk}${n}"; do [[ -b "$cand" ]] && { printf '%s\n' "$cand"; return 0; }; done
    sleep 1
  done
  return 1
}
auto_prepare(){
  local disk="$1" mount="$2" suffix="$3" log="$4"
  PAW_MOUNTPOINT_OVERRIDE="$mount" PAW_LIVE_DISK_OVERRIDE="$disk" PAW_DATA_CONFIRM_SUFFIX="$suffix" \
    "$root/scripts/paw-data-prepare.sh" auto >"$log" 2>&1
}

iso="$root/boot/custom/paw-live-amd64.iso"
[[ -s "$iso" ]] || { fail 'final ISO is present'; exit 1; }
media="$root/tests/virtual/pawdata-media.img"
iso_bytes="$(stat -c %s "$iso")"; media_bytes=$((iso_bytes + 268435456))
truncate -s "$media_bytes" "$media"
dd if="$iso" of="$media" bs=4M conv=notrunc,fsync status=none
media_loop="$(losetup --find --show -P "$media")"; loops+=("$media_loop")
export PAW_MOCK_MEDIA_DEVICE="$media_loop"
mount_dir="$work/data-mount"; mkdir -p "$mount_dir"
snapshot "$media_loop" "$work/iso-before.json"
before_one="$(partition_one "$work/iso-before.json")"; before_count="$(count_parts "$work/iso-before.json")"
if auto_prepare "$media_loop" "$mount_dir" '123456' "$work/auto-mbr.log"; then
  data_dev=''
  while IFS= read -r child; do [[ "$child" == "$media_loop" ]] && continue; [[ "$(blkid -s LABEL -o value "$child" 2>/dev/null || true)" == PAWDATA ]] && data_dev="$child"; done < <(lsblk -nrpo NAME "$media_loop")
  [[ -n "$data_dev" && "$(blkid -s TYPE -o value "$data_dev")" == ext4 ]] && pass 'Auto-init appended a labeled ext4 PAWDATA partition to MBR Hybrid ISO' || fail 'PAWDATA label is visible'
  snapshot "$media_loop" "$work/iso-after.json"
  after_one="$(partition_one "$work/iso-after.json")"; after_count="$(count_parts "$work/iso-after.json")"
  [[ "$before_one" == "$after_one" && "$after_count" == "$((before_count + 1))" ]] && pass 'Original ISO partition geometry was preserved; only one MBR partition was appended' || fail 'Original ISO partition geometry changed'
  [[ "$(blkid -s TYPE -o value "$media_loop")" == iso9660 ]] && pass 'ISO9660 boot filesystem still identifiable after PAWDATA append' || fail 'ISO9660 identity lost'
  mountpoint -q "$mount_dir" && mounts+=("$mount_dir")
  if mountpoint -q "$mount_dir"; then
    printf 'persisted-after-reboot-simulation\n' >"$mount_dir/reboot-marker.txt"; sync; umount "$mount_dir"; mounts=()
    mount -t ext4 -o rw "$data_dev" "$mount_dir"; mounts+=("$mount_dir")
    [[ "$(cat "$mount_dir/reboot-marker.txt")" == persisted-after-reboot-simulation ]] && pass 'Data survived an unmount/remount reboot simulation' || fail 'Data survived an unmount/remount reboot simulation'
    PAW_MOUNTPOINT_OVERRIDE="$mount_dir" "$root/scripts/paw-data-check.sh" >/dev/null 2>&1 && pass 'Mounted PAWDATA identity, write probe and free-space gate passed' || fail 'PAWDATA health check passed'
    umount "$mount_dir"; mounts=()
  else fail 'PAWDATA ext4 partition mounted'; fi
else
  cat "$work/auto-mbr.log" >>"$report"
  fail 'MBR Hybrid ISO auto-init'
fi

# GPT Hybrid media: append only, preserve the existing GPT partition geometry.
gpt="$root/tests/virtual/pawdata-gpt.img"
truncate -s 256M "$gpt"
printf 'label: gpt\nsize=1M,type=21686148-6449-6e6f-744e-656564454649,name="BIOS boot"\n' | sfdisk "$gpt" >/dev/null
gpt_loop="$(losetup --find --show -P "$gpt")"; loops+=("$gpt_loop")
[[ -b "${gpt_loop}p1" ]] || wait_part "$gpt_loop" 1 >/dev/null || true
export PAW_MOCK_MEDIA_DEVICE="$gpt_loop"
gpt_mount="$work/gpt-mount"; mkdir -p "$gpt_mount"
snapshot "$gpt_loop" "$work/gpt-before.json"
gpt_before_one="$(partition_one "$work/gpt-before.json")"; gpt_before_count="$(count_parts "$work/gpt-before.json")"
if auto_prepare "$gpt_loop" "$gpt_mount" '123456' "$work/auto-gpt.log"; then
  gpt_data=''
  while IFS= read -r child; do [[ "$child" == "$gpt_loop" ]] && continue; [[ "$(blkid -s LABEL -o value "$child" 2>/dev/null || true)" == PAWDATA ]] && gpt_data="$child"; done < <(lsblk -nrpo NAME "$gpt_loop")
  [[ -n "$gpt_data" && "$(blkid -s TYPE -o value "$gpt_data")" == ext4 ]] && pass 'Auto-init appended a labeled ext4 PAWDATA partition to GPT Hybrid media' || fail 'GPT PAWDATA label is visible'
  snapshot "$gpt_loop" "$work/gpt-after.json"
  gpt_after_one="$(partition_one "$work/gpt-after.json")"; gpt_after_count="$(count_parts "$work/gpt-after.json")"
  [[ "$gpt_before_one" == "$gpt_after_one" && "$gpt_after_count" == "$((gpt_before_count + 1))" ]] && pass 'Original GPT BIOS Boot geometry was preserved; only one GPT partition was appended' || fail 'Original GPT partition geometry changed'
  mountpoint -q "$gpt_mount" && mounts+=("$gpt_mount")
  [[ -n "$gpt_data" && "$(blkid -s LABEL -o value "${gpt_loop}p1" 2>/dev/null || true)" != PAWDATA ]] && pass 'Existing GPT BIOS Boot partition was not formatted' || fail 'Existing GPT partition was formatted'
  umount "$gpt_mount" 2>/dev/null || true; mounts=()
else
  cat "$work/auto-gpt.log" >>"$report"
  fail 'GPT Hybrid media auto-init'
fi

# Wrong suffix must not create a partition.
wrong="$root/tests/virtual/pawdata-wrong.img"
truncate -s 256M "$wrong"
printf 'label: gpt\nsize=1M,type=21686148-6449-6e6f-744e-656564454649,name="BIOS boot"\n' | sfdisk "$wrong" >/dev/null
wrong_loop="$(losetup --find --show -P "$wrong")"; loops+=("$wrong_loop")
export PAW_MOCK_MEDIA_DEVICE="$wrong_loop"
snapshot "$wrong_loop" "$work/wrong-before.json"
if auto_prepare "$wrong_loop" "$work/wrong-mount" '000000' "$work/wrong.log"; then
  fail 'Wrong serial suffix was rejected'
else
  snapshot "$wrong_loop" "$work/wrong-after.json"
  [[ "$(count_parts "$work/wrong-before.json")" == "$(count_parts "$work/wrong-after.json")" ]] && pass 'Wrong serial suffix left the partition table unchanged' || fail 'Wrong suffix changed the partition table'
fi

missing_dir="$work/missing-mount"; mkdir -p "$missing_dir"; PAW_MOUNTPOINT_OVERRIDE="$missing_dir" "$root/scripts/paw-data-check.sh" >/dev/null 2>&1 && fail 'Missing PAWDATA must block' || pass 'Missing PAWDATA is reported as WARN/BLOCKED'

corrupt_file="$root/tests/virtual/pawdata-corrupt.img"; truncate -s 48M "$corrupt_file"
corrupt_loop="$(losetup --find --show "$corrupt_file")"; loops+=("$corrupt_loop")
mkfs.ext4 -F -L PAWDATA "$corrupt_loop" >/dev/null
# Write through the loop device and flush its buffer cache; writing directly to
# the backing file can leave e2fsck reading a stale, valid superblock.
dd if=/dev/zero of="$corrupt_loop" bs=4096 count=1 conv=notrunc status=none
blockdev --flushbufs "$corrupt_loop" || true
sync
set +e; e2fsck -fn "$corrupt_loop" >/dev/null 2>&1; corrupt_rc=$?; set -e
((corrupt_rc != 0)) && pass 'Corrupted ext4 superblock fails closed' || fail 'Corrupted ext4 superblock fails closed'

small_file="$root/tests/virtual/pawdata-small.img"; truncate -s 32M "$small_file"
small_loop="$(losetup --find --show "$small_file")"; loops+=("$small_loop")
mkfs.ext4 -F -L PAWDATA "$small_loop" >/dev/null
small_dir="$work/small-mount"; mkdir -p "$small_dir"; mount -t ext4 -o rw "$small_loop" "$small_dir"; mounts+=("$small_dir")
set +e; dd if=/dev/zero of="$small_dir/fill.bin" bs=1M conv=fsync status=none 2>"$work/dd-exhaustion.err"; fill_rc=$?; set -e
if ((fill_rc != 0)) && ! PAW_MOUNTPOINT_OVERRIDE="$small_dir" PAW_STATE_MIN_FREE_BYTES=67108864 "$root/scripts/paw-data-check.sh" >/dev/null 2>&1; then
  pass 'Space exhaustion is detected and remains non-PASS'
else
  fail 'Space exhaustion must be detected and blocked'
fi

printf 'Summary: %s passed, %s failed\n' "$passed" "$failed" >>"$report"
cat "$report"
((failed == 0))
