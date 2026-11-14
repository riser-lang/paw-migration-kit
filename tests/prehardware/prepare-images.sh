#!/usr/bin/env bash
# Reproducible 50 GiB source + 240 GB target preparation for the QEMU lab.
#
#   source: 53,687,091,200 bytes (exactly 50 GiB)
#   target: 240,000,000,000 bytes (the SSD under test)
#
# Two source paths are supported:
#
#   --source-50g RAW     an already prepared, bootable 50 GiB Ubuntu disk.
#   --cloud-image IMG    a Ubuntu 24.04 cloud image (qcow2 or raw) that is
#                        expanded to exactly 50 GiB: the image is enlarged,
#                        the GPT backup header is moved to the new end, the
#                        root partition is grown in place (partition GUID and
#                        name preserved) and ext4 is resized.  The filesystem
#                        UUID and the boot partition are verified afterwards.
#
# No real /dev/sdX, SSD or TF card is touched: every output is a regular file
# under WORKDIR/boot.  The USB media (32,000,000,000 bytes) is built by
# build-lab.sh from the lab ISO so there is exactly one media producer.
#
# Sparse files are reported with both logical_bytes and allocated_bytes.  The
# clone still writes all 50 GiB, so target allocation is budgeted at 50 GiB;
# the 32 GB media only allocates the ISO payload because it is sparse.
set -Eeuo pipefail
usage(){ echo "usage: $0 WORKDIR [--iso ISO] (--source-50g RAW50G | --cloud-image IMG) [--target-bytes BYTES] [--plan-only] [--force]" >&2; }
work="${1:-}"; shift || true
iso=''; seed=''; cloud=''; plan_only=0; force=0
source_bytes=53687091200
target_bytes="${PAW_EXPECTED_TARGET_BYTES:-240000000000}"
media_bytes=32000000000
while (($#)); do
  case "$1" in
    --iso) iso="${2:-}"; shift 2 ;;
    --source-50g) seed="${2:-}"; shift 2 ;;
    --cloud-image) cloud="${2:-}"; shift 2 ;;
    --target-bytes) target_bytes="${2:-}"; shift 2 ;;
    --plan-only) plan_only=1; shift ;;
    --force) force=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done
[[ -n "$work" && ( -n "$seed" || -n "$cloud" ) ]] || { usage; exit 2; }
[[ -z "$seed" || -z "$cloud" ]] || { echo 'choose one source: --source-50g or --cloud-image' >&2; exit 2; }
[[ "$target_bytes" =~ ^[1-9][0-9]*$ ]] || { echo "invalid target_bytes '$target_bytes': must be a positive integer" >&2; exit 2; }
(( target_bytes >= source_bytes )) || { echo "invalid target_bytes $target_bytes: must be >= source_bytes $source_bytes" >&2; exit 2; }
(( target_bytes % 512 == 0 )) || { echo "invalid target_bytes $target_bytes: must be a multiple of 512 bytes" >&2; exit 2; }
boot="$work/boot"
need(){ command -v "$1" >/dev/null 2>&1 || { echo "required tool missing: $1" >&2; exit 2; }; }
file_size(){ stat -c %s "$1"; }
file_alloc(){ echo "$(($(stat -c %b "$1") * 512))"; }

[[ -n "$iso" ]] && { [[ -f "$iso" ]] || { echo "ISO not found: $iso" >&2; exit 2; }; }
if [[ -n "$seed" ]]; then
  [[ -f "$seed" ]] || { echo "50 GiB source seed not found: $seed" >&2; exit 2; }
  seed_alloc="$(file_alloc "$seed")"
  seed_bytes="$(file_size "$seed")"
  [[ "$seed_bytes" == "$source_bytes" ]] || {
    echo "source seed must be exactly $source_bytes bytes (50 GiB); got $seed_bytes; refusing to shrink or relabel" >&2
    exit 2
  }
  iso_bytes=0; [[ -n "$iso" ]] && iso_bytes="$(file_size "$iso")"
else
  [[ -f "$cloud" ]] || { echo "cloud image not found: $cloud" >&2; exit 2; }
  need qemu-img
  seed_bytes="$(python3 - "$cloud" <<'PY'
import json,subprocess,sys
info=json.loads(subprocess.run(["qemu-img","info","--output=json",sys.argv[1]],capture_output=True,text=True,check=True).stdout)
print(info["virtual-size"])
PY
)"
  (( seed_bytes <= source_bytes )) || { echo "cloud image virtual size $seed_bytes exceeds 50 GiB; refusing to shrink" >&2; exit 2; }
  # Conversion allocates roughly the source payload, not the final 50 GiB.
  seed_alloc="$(file_alloc "$cloud")"
  iso_bytes=0; [[ -n "$iso" ]] && iso_bytes="$(file_size "$iso")"
fi

# Target is cloned in full.  Media is sparse: only the ISO payload is allocated.
lab_overhead=$((4 * 1024 * 1024 * 1024))
peak=$((seed_alloc + source_bytes + iso_bytes + iso_bytes + lab_overhead))
reserve=$((peak * 15 / 100))
required=$((peak + reserve))
avail="$(($(df -B1 --output=avail "$(dirname "$work")" | tail -n1 | tr -d ' ')))"
cat <<EOF
source_logical_bytes=$source_bytes
source_seed_logical_bytes=$seed_bytes
source_seed_allocated_bytes=$seed_alloc
target_logical_bytes=$target_bytes
target_expected_allocated_bytes=$source_bytes
media_logical_bytes=$media_bytes
media_expected_allocated_bytes=$iso_bytes
iso_bytes=$iso_bytes
lab_work_overhead_bytes=$lab_overhead
peak_required_bytes=$peak
fifteen_percent_reserve_bytes=$reserve
required_with_reserve_bytes=$required
available_bytes=$avail
EOF
((avail >= required)) || {
  shortfall=$((required - avail))
  echo "shortfall_bytes=$shortfall"
  echo "BLOCKED: available $avail < required $required; shortfall $shortfall bytes; no image was created." >&2
  exit 2
}
((plan_only == 0)) || exit 0

if [[ -e "$boot/source50.raw" && $force -ne 1 ]]; then
  echo "refusing to overwrite $boot/source50.raw without --force" >&2; exit 2
fi
mkdir -p "$boot"
df -B1 "$boot" >"$boot/df-before.txt" 2>&1 || df -h "$boot" >"$boot/df-before.txt"
need sgdisk; need sfdisk; need losetup; need blkid; need e2fsck; need resize2fs; need dumpe2fs; need mountpoint
if [[ "$(id -u)" != 0 ]]; then
  echo 'image expansion requires root (losetup/mount); re-run with sudo' >&2; exit 2
fi

cleanup_loop(){ [[ -n ${loop:-} ]] && losetup -d "$loop" 2>/dev/null || true; loop=''; }
cleanup_mount(){
  local m
  [[ -n ${mnt:-} ]] && mountpoint -q "$mnt/dev/pts" && umount "$mnt/dev/pts" 2>/dev/null || true
  for m in ${bind_mounts:-}; do mountpoint -q "$m" && umount "$m" 2>/dev/null || true; done
  bind_mounts=''
  [[ -n ${mnt:-} ]] && mountpoint -q "$mnt" && umount "$mnt" 2>/dev/null || true
}
trap 'cleanup_mount; cleanup_loop' EXIT

# The highest partition number is not necessarily the root filesystem.
# Ubuntu 24.04 cloud images put root on partition 1 and small EFI/BIOS/boot
# partitions on 14-16, so choose the partition that extends farthest.
last_part(){ sgdisk -p "$1" | awk '$1 ~ /^[0-9]+$/ { if ($3+0 > max) { max=$3+0; part=$1 } } END { print part }'; }
part_start(){ sgdisk -i "$2" "$1" | sed -n 's/^First sector: \([0-9]*\).*/\1/p'; }
part_guid(){ sgdisk -i "$2" "$1" | sed -n 's/^Partition unique GUID: //p'; }
part_name(){ sgdisk -i "$2" "$1" | sed -n "s/^Partition name: '\(.*\)'/\1/p"; }

verify_gpt(){ sgdisk -v "$1" 2>&1 | grep -q 'No problems found.'; }
gpt_problems(){ sgdisk -v "$1" 2>&1 | grep -E 'Problem|Caution' | head -n 10 || true; }

attach_loop(){
  loop="$(losetup --find --show -P "$1")"
  udevadm settle --timeout=30 2>/dev/null || true
  local i
  for i in $(seq 1 30); do
    [[ -b "${loop}p${root_part}" ]] && return 0
    sleep 1
  done
  echo "partition ${loop}p${root_part} did not appear" >&2; return 1
}

# The stock cloud image is intentionally minimal and lacks linux-modules-extra,
# which carries the r8169 and i915 drivers a real Ubuntu server install has.
# Install the matching extra-module package inside the image so the virtual
# source is representative of a real installed system; never pretend the
# driver check passed.  This needs network access and runs only on the
# disposable image copy, never on a host disk.
install_extra_modules(){
  local rootdev="$1" kver
  mnt="$(mktemp -d)"
  mount "$rootdev" "$mnt"
  kver="$(find "$mnt/usr/lib/modules" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort -V | tail -n1)"
  [[ -n "$kver" ]] || { echo 'cloud image has no kernel module directory' >&2; return 1; }
  if compgen -G "$mnt/usr/lib/modules/$kver/kernel/drivers/net/ethernet/realtek/r8169.ko*" >/dev/null &&      compgen -G "$mnt/usr/lib/modules/$kver/kernel/drivers/gpu/drm/i915/i915.ko*" >/dev/null; then
    echo "cloud_modules=present kernel=$kver"
    cleanup_mount
    return 0
  fi
  echo "cloud_modules=installing kernel=$kver"
  mkdir -p "$mnt/dev" "$mnt/proc" "$mnt/sys" "$mnt/run"
  mount --bind /dev "$mnt/dev"; bind_mounts="$mnt/dev"
  mount -t devpts devpts "$mnt/dev/pts" 2>/dev/null || true
  mount -t proc proc "$mnt/proc"; bind_mounts="$bind_mounts $mnt/proc"
  mount -t sysfs sysfs "$mnt/sys"; bind_mounts="$bind_mounts $mnt/sys"
  rm -f "$mnt/etc/resolv.conf"
  cp /etc/resolv.conf "$mnt/etc/resolv.conf"
  chroot "$mnt" env DEBIAN_FRONTEND=noninteractive apt-get -o Acquire::ForceIPv4=true update -qq
  chroot "$mnt" env DEBIAN_FRONTEND=noninteractive apt-get -o Acquire::ForceIPv4=true install -y --no-install-recommends "linux-modules-extra-$kver"
  chroot "$mnt" /usr/sbin/depmod -a "$kver"
  compgen -G "$mnt/usr/lib/modules/$kver/kernel/drivers/net/ethernet/realtek/r8169.ko*" >/dev/null || { echo "r8169 still missing for $kver" >&2; return 1; }
  compgen -G "$mnt/usr/lib/modules/$kver/kernel/drivers/gpu/drm/i915/i915.ko*" >/dev/null || { echo "i915 still missing for $kver" >&2; return 1; }
  echo "cloud_modules=installed kernel=$kver"
  cleanup_mount
}

verify_source(){
  local image="$1" label="$2" uuid fs_blocks bs kernel_found=0
  [[ "$(file_size "$image")" == "$source_bytes" ]] || { echo "$label: size is not $source_bytes" >&2; return 1; }
  verify_gpt "$image" || { echo "$label: GPT is not clean:" >&2; gpt_problems "$image" >&2; return 1; }
  root_part="$(last_part "$image")"
  attach_loop "$image"
  local rootdev="${loop}p${root_part}"
  [[ "$(blkid -o value -s TYPE "$rootdev")" == ext4 ]] || { echo "$label: last partition is not ext4" >&2; return 1; }
  uuid="$(blkid -o value -s UUID "$rootdev")"
  [[ "$uuid" =~ ^[0-9a-fA-F-]{36}$ ]] || { echo "$label: root UUID unreadable" >&2; return 1; }
  e2fsck -f -n "$rootdev" >/dev/null
  read -r fs_blocks bs <<<"$(dumpe2fs -h "$rootdev" 2>/dev/null | awk -F: '/Block count/{gsub(/ /,"",$2);c=$2} /Block size/{gsub(/ /,"",$2);s=$2} END{print c, s}')"
  (( fs_blocks * bs > 40 * 1024 * 1024 * 1024 )) || { echo "$label: ext4 did not grow past 40 GiB ($fs_blocks x $bs)" >&2; return 1; }
  mnt="$(mktemp -d)"
  mount -o ro "$rootdev" "$mnt"
  grep -q '^VERSION_ID="\?24\.04"\?$' "$mnt/etc/os-release" 2>/dev/null || { echo "$label: root is not Ubuntu 24.04" >&2; return 1; }
  find "$mnt/usr/lib/modules" -name 'r8169.ko*' -print -quit 2>/dev/null | grep -q . || { echo "$label: r8169 module missing" >&2; return 1; }
  find "$mnt/usr/lib/modules" -name 'i915.ko*' -print -quit 2>/dev/null | grep -q . || { echo "$label: i915 module missing" >&2; return 1; }
  umount "$mnt"; rmdir "$mnt"; mnt=''
  # The kernel normally lives on the XBOOTLDR/boot partition, not in root/boot.
  local part fstype
  while read -r part fstype; do
    [[ "$fstype" == ext4 ]] || continue
    mnt="$(mktemp -d)"
    mount -o ro "$part" "$mnt" || { rmdir "$mnt"; mnt=''; continue; }
    if find "$mnt" -maxdepth 2 -name 'vmlinuz-*' -print -quit | grep -q .; then kernel_found=1; fi
    umount "$mnt"; rmdir "$mnt"; mnt=''
    ((kernel_found == 1)) && break
  done < <(lsblk -nrpo NAME,FSTYPE "$loop")
  [[ "$kernel_found" == 1 ]] || { echo "$label: no vmlinuz on any ext4 partition" >&2; return 1; }
  echo "$label: source_root_partition=$root_part source_root_uuid=$uuid fs_blocks=$fs_blocks block_size=$bs kernel_found=yes"
  cleanup_loop
}

expand_cloud(){
  local image="$boot/source50.raw" fmt old_guid new_guid guid name start old_uuid new_uuid
  qemu-img convert -p -O raw "$cloud" "$image" >/dev/null 2>"$boot/qemu-convert.log" || {
    echo 'qemu-img convert failed; see qemu-convert.log' >&2; return 1; }
  qemu-img resize -f raw "$image" "$source_bytes" >/dev/null
  [[ "$(file_size "$image")" == "$source_bytes" ]] || { echo 'expanded file size mismatch' >&2; return 1; }
  # The old GPT backup header is still at the old end of the image.  Move it to
  # the new last sector before touching any partition entry.
  sgdisk -e "$image" >/dev/null
  verify_gpt "$image" || { echo 'GPT backup header relocation failed' >&2; gpt_problems "$image" >&2; return 1; }
  root_part="$(last_part "$image")"
  old_guid="$(part_guid "$image" "$root_part")"
  guid="$old_guid"; name="$(part_name "$image" "$root_part")"; start="$(part_start "$image" "$root_part")"
  [[ -n "$guid" && -n "$start" ]] || { echo 'cannot read root partition geometry' >&2; return 1; }
  [[ -n "$name" ]] || name='cloudimg-rootfs'
  # Grow the last partition to the end of the enlarged disk, preserving its
  # unique GUID and name; 8300 is the Linux filesystem type code.
  sgdisk -d "$root_part" -n "${root_part}:${start}:0" -t "${root_part}:8300" \
    -u "${root_part}:${guid}" -c "${root_part}:${name}" "$image" >/dev/null
  new_guid="$(part_guid "$image" "$root_part")"
  [[ "$new_guid" == "$old_guid" ]] || { echo 'partition GUID changed during growth' >&2; return 1; }
  verify_gpt "$image" || { echo 'GPT invalid after partition growth' >&2; gpt_problems "$image" >&2; return 1; }
  attach_loop "$image"
  old_uuid="$(blkid -o value -s UUID "${loop}p${root_part}")"
  e2fsck -f -p "${loop}p${root_part}" >/dev/null
  resize2fs "${loop}p${root_part}" >/dev/null
  new_uuid="$(blkid -o value -s UUID "${loop}p${root_part}")"
  [[ "$new_uuid" == "$old_uuid" ]] || { echo 'filesystem UUID changed during resize' >&2; return 1; }
  install_extra_modules "${loop}p${root_part}"
  cleanup_loop
  verify_source "$image" expanded-source
  echo "$image"
}

if [[ -n "$seed" ]]; then
  cp --sparse=always --reflink=auto "$seed" "$boot/source50.raw"
  [[ "$(file_size "$boot/source50.raw")" == "$source_bytes" ]] || { echo 'source copy size changed' >&2; exit 2; }
  root_part="$(last_part "$boot/source50.raw")"
  verify_source "$boot/source50.raw" seed-source
else
  expand_cloud
fi

rm -f "$boot/target240.img" "$boot/target.img"
qemu-img create -f raw "$boot/target.img" "$target_bytes" >/dev/null
[[ "$(file_size "$boot/target.img")" == "$target_bytes" ]] || { echo 'target size mismatch' >&2; exit 2; }

# Record identity/provenance of the images, never the guest filesystem UUID in
# the committed tree (this file lives in the disposable work directory only).
{
  echo "created_at=$(date -u +%FT%TZ)"
  echo "source_logical_bytes=$(file_size "$boot/source50.raw")"
  echo "source_allocated_bytes=$(file_alloc "$boot/source50.raw")"
  echo "target_logical_bytes=$(file_size "$boot/target.img")"
  echo "target_allocated_bytes=$(file_alloc "$boot/target.img")"
  echo "media_logical_bytes=$media_bytes"
  echo "incoming_iso_bytes=$iso_bytes"
  echo "gpt_check=$(verify_gpt "$boot/source50.raw" && echo PASS || echo FAIL)"
  sgdisk -p "$boot/source50.raw" | sed 's/^/gpt: /'
} >"$boot/image-preparation.txt"
cat "$boot/image-preparation.txt"
(
  cd "$boot"
  sha256sum source50.raw target.img > image-manifest.sha256
  stat -c '%n %s' source50.raw target.img > image-sizes.txt
)
df -B1 "$boot" >"$boot/df-after.txt" 2>&1 || df -h "$boot" >"$boot/df-after.txt"
cat "$boot/image-sizes.txt"
echo 'image preparation PASS'
