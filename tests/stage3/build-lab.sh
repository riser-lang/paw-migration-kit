#!/usr/bin/env bash
# Build the disposable Stage 3 QEMU lab from the real release ISO and a real
# Ubuntu cloud image.  Everything here is unprivileged: root filesystems are
# populated with mke2fs -d and written into GPT images with dd, no loop mount
# and no host root are required.
set -Eeuo pipefail
iso="${1:?usage: build-lab.sh ISO WORKDIR SOURCE_QCOW2}"
work="${2:?usage: build-lab.sh ISO WORKDIR SOURCE_QCOW2}"
source_qcow2="${3:?usage: build-lab.sh ISO WORKDIR SOURCE_QCOW2}"
repo="$(cd "$(dirname "$0")/../.." && pwd)"
xorriso="${XORRISO:-xorriso}"

mkdir -p "$work"/{iso,rootfs,boot}
# xorriso restores ISO directory permissions (0555 for /live).  Create the
# destination directory writable first so the three extracted files can land.
install -d -m 0755 "$work/iso/live"
if [[ ! -s "$work/iso/live/filesystem.squashfs" ]]; then
  echo "[stage3] extracting ISO live files"
  "$xorriso" -osirrox on -indev "$iso" \
    -extract /live/filesystem.squashfs "$work/iso/live/filesystem.squashfs" \
    -extract /live/vmlinuz "$work/iso/live/vmlinuz" \
    -extract /live/initrd.img "$work/iso/live/initrd.img" 2>"$work/xorriso.log"
fi
[[ -s "$work/iso/live/filesystem.squashfs" ]] || { echo 'missing squashfs' >&2; exit 2; }

if [[ ! -x "$work/rootfs/sbin/init" ]]; then
  echo "[stage3] unsquashing release root filesystem"
  rm -rf "$work/rootfs"
  rc=0
  unsquashfs -d "$work/rootfs" "$work/iso/live/filesystem.squashfs" >"$work/unsquashfs.log" || rc=$?
  # rc=2 is expected for unprivileged extraction: device nodes cannot be created.
  if [[ "$rc" -ne 0 && "$rc" -ne 2 ]]; then
    echo "unsquashfs failed rc=$rc" >&2
    exit "$rc"
  fi
fi
rootfs="$work/rootfs"
[[ -x "$rootfs/sbin/init" ]] || { echo 'release rootfs has no init' >&2; exit 2; }

echo "[stage3] injecting Stage 3 harness and real project entry points"
install -d "$rootfs/opt/paw-migration/tests/stage3"
cp -a "$repo/scripts/." "$rootfs/opt/paw-migration/scripts/"
cp -a "$repo/configs/." "$rootfs/opt/paw-migration/configs/"
cp -a "$repo/tests/stage3/guest-chain.sh" "$rootfs/opt/paw-migration/tests/stage3/guest-chain.sh"
chmod 0755 "$rootfs/opt/paw-migration/tests/stage3/guest-chain.sh"
install -m 0644 "$repo/tests/stage3/paw-stage3-chain.service" "$rootfs/etc/systemd/system/paw-stage3-chain.service"
ln -sfn /etc/systemd/system/paw-stage3-chain.service "$rootfs/etc/systemd/system/multi-user.target.wants/paw-stage3-chain.service"
install -m 0644 "$work/iso/live/vmlinuz" "$rootfs/boot/vmlinuz"

# Automatic serial root shell for the disposable lab only.  The production ISO
# still has no serial autologin.
install -d "$rootfs/etc/systemd/system/serial-getty@ttyS0.service.d"
cat >"$rootfs/etc/systemd/system/serial-getty@ttyS0.service.d/autologin.conf" <<'UNIT'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear --keep-baud 115200,38400,9600 %I $TERM
UNIT
install -d "$rootfs/etc/systemd/system/getty.target.wants"
ln -sfn /lib/systemd/system/serial-getty@ttyS0.service \
  "$rootfs/etc/systemd/system/getty.target.wants/serial-getty@ttyS0.service"

# One-shot GRUB BIOS install into the lab disk.  On later boots the marker is
# present, so this service is a no-op and never touches the target disk.
install -d "$rootfs/opt/paw-migration/tests/stage3"
cp -a "$repo/tests/stage3/install-guest-grub.sh" "$rootfs/opt/paw-migration/tests/stage3/install-guest-grub.sh"
chmod 0755 "$rootfs/opt/paw-migration/tests/stage3/install-guest-grub.sh"
cat >"$rootfs/etc/systemd/system/paw-stage3-grub-install.service" <<'UNIT'
[Unit]
Description=PAW Stage 3 lab GRUB install (disposable QEMU guest disk only)
After=local-fs.target
ConditionPathExists=!/boot/grub/grub.cfg

[Service]
Type=oneshot
ExecStart=/opt/paw-migration/tests/stage3/install-guest-grub.sh
StandardOutput=journal+console
StandardError=journal+console

[Install]
WantedBy=multi-user.target
UNIT
ln -sfn /etc/systemd/system/paw-stage3-grub-install.service \
  "$rootfs/etc/systemd/system/multi-user.target.wants/paw-stage3-grub-install.service"

# Host GRUB BIOS modules/tools are copied into the disposable guest because the
# Debian live rootfs does not ship grub-pc-bin.  Dependency libraries are copied
# only when absent from the guest.
copy_with_libs(){
  local bin="$1" dest="$2" lib
  install -d "$(dirname "$rootfs$dest")"
  cp -aL "$bin" "$rootfs$dest"
  while read -r lib; do
    [[ -n "$lib" && -e "$lib" ]] || continue
    if [[ ! -e "$rootfs$lib" ]]; then
      install -d "$rootfs$(dirname "$lib")"
      cp -aL "$lib" "$rootfs$lib"
    fi
  done < <(ldd "$bin" 2>/dev/null | awk '/=> \//{print $3} /^\//{print $1}' | sort -u)
}
install -d "$rootfs/usr/lib/grub"
rm -rf "$rootfs/usr/lib/grub/i386-pc"
cp -a /usr/lib/grub/i386-pc "$rootfs/usr/lib/grub/i386-pc"
for tool in /usr/sbin/grub-install /usr/sbin/grub-bios-setup /usr/sbin/grub-probe \
            /usr/sbin/grub-mkdevicemap /usr/sbin/grub-mkconfig /usr/bin/grub-mkimage \
            /usr/bin/grub-editenv /usr/bin/grub-script-check; do
  [[ -e "$tool" ]] || continue
  copy_with_libs "$tool" "/usr${tool#/usr}"
done
# grub-bios-setup is normally a symlink into /usr/lib/grub/i386-pc.
[[ -e "$rootfs/usr/sbin/grub-bios-setup" ]] || \
  ln -sfn ../lib/grub/i386-pc/grub-bios-setup "$rootfs/usr/sbin/grub-bios-setup"
chmod 0755 "$rootfs/usr/sbin/grub-install" "$rootfs/usr/sbin/grub-probe" 2>/dev/null || true

echo "[stage3] building Stage 3 initramfs (root=/dev/vda2)"
"$repo/tests/stage3/build-stage3-initrd.sh" "$rootfs" "$work/iso/live/vmlinuz" "$work/boot/initrd.img" \
  >"$work/initrd.log"
cp -a "$work/boot/initrd.img" "$rootfs/boot/initrd.img"

echo "[stage3] sizing guest root filesystem"
root_kb="$(du -sk "$rootfs" | awk '{print $1}')"
root_bytes=$(( (root_kb + 1048576) * 1024 ))
root_bytes=$(( ((root_bytes + 1048575) / 1048576) * 1048576 ))
rootpart="$work/boot/rootpart.img"
rm -f "$rootpart"
truncate -s "$root_bytes" "$rootpart"
fakeroot mke2fs -q -F -t ext4 -L PAW-LAB-ROOT -d "$rootfs" "$rootpart" >"$work/mke2fs.log" 2>&1

echo "[stage3] creating guest GPT disk (BIOS Boot + root)"
guest="$work/boot/guest.img"
guest_bytes=$(( root_bytes + 4 * 1024 * 1024 + 64 * 1024 * 1024 ))
guest_sectors=$(( guest_bytes / 512 ))
rm -f "$guest"
truncate -s "$guest_bytes" "$guest"
sgdisk --clear \
  --new=1:2048:+1024 --typecode=1:21686148-6449-6e6f-744e-656564454649 --change-name=1:'BIOS boot' \
  --new=2:4096:"$(( guest_sectors - 34 ))" --typecode=2:8300 --change-name=2:'PAW lab root' \
  "$guest" >"$work/sgdisk-guest.log"
dd if="$rootpart" of="$guest" bs=1M seek=2 conv=notrunc status=none
rm -f "$rootpart"

echo "[stage3] creating writable virtual live medium (ISO + free space)"
media="$work/boot/media.img"
iso_bytes="$(stat -c %s "$iso")"
media_bytes=$(( iso_bytes + 768 * 1024 * 1024 ))
media_bytes=$(( ((media_bytes + 1048575) / 1048576) * 1048576 ))
if [[ ! -s "$media" ]]; then
  rm -f "$media"
  truncate -s "$media_bytes" "$media"
  dd if="$iso" of="$media" bs=16M conv=notrunc status=none
fi
# The ISO is hybrid (MBR or GPT).  The free tail is intentionally left
# unpartitioned so the real paw-prepare-data-partition.sh appends PAWDATA just
# as it would on a physical USB stick.

echo "[stage3] converting Ubuntu source image to raw"
source_raw="$work/boot/source.raw"
if [[ ! -s "$source_raw" ]]; then
  qemu-img convert -p -O raw "$source_qcow2" "$source_raw" 2>"$work/qemu-img.log"
fi

echo "[stage3] creating sparse 240 GiB virtual target"
target="$work/boot/target.img"
if [[ ! -e "$target" ]]; then
  truncate -s 257698037760 "$target"
fi

cat >"$work/boot/manifest.txt" <<EOF
iso=$iso
iso_bytes=$iso_bytes
media_bytes=$media_bytes
guest_bytes=$guest_bytes
root_bytes=$root_bytes
source_raw=$source_raw
source_bytes=$(stat -c %s "$source_raw")
target_bytes=$(stat -c %s "$target")
kernel=$work/iso/live/vmlinuz
initrd=$work/boot/initrd.img
EOF
cat "$work/boot/manifest.txt"
echo "[stage3] lab build complete: $work/boot"
