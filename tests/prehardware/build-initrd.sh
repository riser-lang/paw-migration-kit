#!/usr/bin/env bash
# Build a minimal initramfs for the Stage 3 lab guest (root=/dev/vda2).
# Loads virtio-blk/scsi, ext4, 9p and bochs DRM + fbcon, then switch_root.
set -Eeuo pipefail
rootfs="${1:?usage: build-stage3-initrd.sh ROOTFS KERNEL OUTPUT}"
kernel="${2:?usage: build-stage3-initrd.sh ROOTFS KERNEL OUTPUT}"
out="${3:?usage: build-stage3-initrd.sh ROOTFS KERNEL OUTPUT}"
[[ -d "$rootfs" && -r "$kernel" ]] || { echo 'rootfs/kernel missing' >&2; exit 2; }
for c in busybox cpio gzip; do command -v "$c" >/dev/null || { echo "$c required" >&2; exit 2; }; done

moddir=""
for candidate in "$rootfs"/lib/modules/* "$rootfs"/usr/lib/modules/*; do
  [[ -d "$candidate" ]] && { moddir="$candidate"; break; }
done
[[ -n "$moddir" ]] || { echo 'kernel modules not found in rootfs' >&2; exit 2; }
version="$(basename "$moddir")"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/initramfs"/{bin,dev,proc,sys,mnt,lib/modules}
cp "$(command -v busybox)" "$work/initramfs/bin/busybox"
for applet in sh mount umount switch_root sleep insmod ls echo cat; do
  ln -s busybox "$work/initramfs/bin/$applet"
done
cp -a "$moddir" "$work/initramfs/lib/modules/$version"
find "$work/initramfs/lib/modules" -name '*.ko.xz' -print0 | xargs -0 -r -P4 -n8 unxz

# Load modules by path with a tolerant helper: dependency order is explicit and
# a missing optional module must not abort the boot.
cat >"$work/initramfs/init" <<INIT
#!/bin/busybox sh
export PATH=/bin
mount -t devtmpfs devtmpfs /dev
mount -t proc proc /proc
mount -t sysfs sysfs /sys
M=/lib/modules/$version
load(){ insmod "\$M/\$1" 2>/dev/null || true; }
load kernel/drivers/virtio/virtio.ko
load kernel/drivers/virtio/virtio_ring.ko
load kernel/drivers/virtio/virtio_pci_legacy_dev.ko
load kernel/drivers/virtio/virtio_pci_modern_dev.ko
load kernel/drivers/virtio/virtio_pci.ko
load kernel/drivers/block/virtio_blk.ko
load kernel/drivers/scsi/scsi_mod.ko
load kernel/drivers/scsi/sd_mod.ko
load kernel/drivers/scsi/virtio_scsi.ko
load kernel/drivers/block/loop.ko
load kernel/lib/crc16.ko
load kernel/crypto/crc32c_generic.ko
load kernel/lib/libcrc32c.ko
load kernel/arch/x86/crypto/crc32c-intel.ko
load kernel/fs/mbcache.ko
load kernel/fs/jbd2/jbd2.ko
load kernel/fs/ext4/ext4.ko
load kernel/net/9p/9pnet.ko
load kernel/net/9p/9pnet_virtio.ko
load kernel/fs/9p/9p.ko
for m in drm drm_kms_helper ttm drm_ttm_helper drm_vram_helper bochs; do
  load kernel/drivers/gpu/drm/\$m.ko
  load kernel/drivers/gpu/drm/ttm/\$m.ko
  load kernel/drivers/gpu/drm/tiny/\$m.ko
done
echo "PAW3-INITRD: modules loaded" > /dev/console
i=0
while [ ! -b /dev/vda2 ] && [ \$i -lt 150 ]; do sleep 0.1; i=\$((i+1)); done
[ -b /dev/vda2 ] || { echo "PAW3-INITRD: /dev/vda2 did not appear" > /dev/console; exec sh; }
mount -t ext4 -o rw /dev/vda2 /mnt || { echo "PAW3-INITRD: root mount failed" > /dev/console; exec sh; }
exec switch_root /mnt /sbin/init
INIT
chmod 0755 "$work/initramfs/init"
(cd "$work/initramfs" && find . -print0 | cpio --null -o -H newc 2>/dev/null | gzip -1) >"$out"
echo "built Stage 3 initramfs $out for $version ($(du -h "$out" | cut -f1))"
