#!/usr/bin/env bash
# Build a minimal initramfs that mounts a plain ext4 root=/dev/vda and loads
# bochs DRM + fbcon.  Used by the CJK QEMU test so it does not depend on the
# live-boot initrd's boot=live assumptions.
set -Eeuo pipefail
rootfs="${1:?usage: build-fbcon-initrd.sh ROOTFS KERNEL OUTPUT}"
kernel="${2:?usage: build-fbcon-initrd.sh ROOTFS KERNEL OUTPUT}"
out="${3:?usage: build-fbcon-initrd.sh ROOTFS KERNEL OUTPUT}"
[[ -d "$rootfs" && -r "$kernel" ]] || { echo 'rootfs/kernel missing' >&2; exit 2; }
command -v busybox >/dev/null || { echo 'busybox-static required' >&2; exit 2; }
command -v cpio >/dev/null && command -v gzip >/dev/null || { echo 'cpio/gzip required' >&2; exit 2; }

kernel_name="$(basename "$kernel")"
version="${kernel_name#vmlinuz-}"
moddir=""
for candidate in "$rootfs/lib/modules/$version" "$rootfs/usr/lib/modules/$version"; do
  [[ -d "$candidate" ]] && { moddir="$candidate"; break; }
done
if [[ -z "$moddir" ]]; then
  moddir="$(find "$rootfs/lib/modules" "$rootfs/usr/lib/modules" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort | head -n1)"
fi
[[ -n "$moddir" && -d "$moddir" ]] || { echo 'kernel modules not found in rootfs' >&2; exit 2; }
version="$(basename "$moddir")"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/initramfs"/{bin,dev,proc,sys,mnt,lib/modules}
cp "$(command -v busybox)" "$work/initramfs/bin/busybox"
for applet in sh mount umount switch_root sleep insmod ls echo; do
  ln -s busybox "$work/initramfs/bin/$applet"
done
cp -a "$moddir" "$work/initramfs/lib/modules/$version"
find "$work/initramfs/lib/modules" -name '*.ko.xz' -print0 | xargs -0 -r -P4 -n8 unxz
cat >"$work/initramfs/init" <<INIT
#!/bin/busybox sh
export PATH=/bin
mount -t devtmpfs devtmpfs /dev
mount -t proc proc /proc
mount -t sysfs sysfs /sys
M=/lib/modules/$version
insmod "\$M/kernel/drivers/block/virtio_blk.ko" 2>/dev/null || true
insmod "\$M/kernel/drivers/block/loop.ko" 2>/dev/null || true
insmod "\$M/kernel/lib/crc16.ko" 2>/dev/null || true
insmod "\$M/kernel/crypto/crc32c_generic.ko" 2>/dev/null || true
insmod "\$M/kernel/lib/libcrc32c.ko" 2>/dev/null || true
insmod "\$M/kernel/arch/x86/crypto/crc32c-intel.ko" 2>/dev/null || true
insmod "\$M/kernel/fs/mbcache.ko" 2>/dev/null || true
insmod "\$M/kernel/fs/jbd2/jbd2.ko" 2>/dev/null || true
insmod "\$M/kernel/fs/ext4/ext4.ko" 2>/dev/null || true
for m in drm drm_kms_helper ttm drm_ttm_helper drm_vram_helper bochs; do
  insmod "\$M/kernel/drivers/gpu/drm/\$m.ko" 2>/dev/null || true
  insmod "\$M/kernel/drivers/gpu/drm/ttm/\$m.ko" 2>/dev/null || true
  insmod "\$M/kernel/drivers/gpu/drm/tiny/\$m.ko" 2>/dev/null || true
done
echo "PAW-TEST: initramfs modules loaded" > /dev/console
ls /dev/vd* /dev/fb* > /dev/console 2>&1
i=0
while [ ! -b /dev/vda ] && [ \$i -lt 100 ]; do sleep 0.1; i=\$((i+1)); done
mount -t ext4 -o rw /dev/vda /mnt || { echo "PAW-TEST: mount failed" > /dev/console; exec sh; }
exec switch_root /mnt /sbin/init
INIT
chmod 0755 "$work/initramfs/init"
(cd "$work/initramfs" && find . -print0 | cpio --null -o -H newc 2>/dev/null | gzip -1) >"$out"
echo "built initramfs $out for $version ($(du -h "$out" | cut -f1))"
