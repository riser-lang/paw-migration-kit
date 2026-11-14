#!/usr/bin/env bash
# Build the disposable v2.8 pre-hardware QEMU lab:
#   * release ISO root filesystem (injected with this branch's scripts)
#   * a bootable lab guest disk (BIOS Boot + ext4 root, /dev/vda2)
#   * a 32 GB PF/USB media image carrying the release ISO
# The source image (source50.raw, exactly 50 GiB) and the parameterized target
# (target.img) are created by prepare-images.sh.  This builder never substitutes a 12 GiB image.
# Unprivileged: mke2fs -d + fakeroot, no host loop or mount.
set -Eeuo pipefail
iso="${1:?usage: build-lab.sh ISO WORKDIR}"
work="${2:?usage: build-lab.sh ISO WORKDIR}"
repo="$(cd "$(dirname "$0")/../.." && pwd)"
xorriso="${XORRISO:-xorriso}"

mkdir -p "$work"/{iso,rootfs,boot}

build_media(){
  echo "[prehw] creating 32 GB USB media image carrying the supplied ISO"
  local media="$work/boot/media32.img" base="$work/boot/media32-base.img"
  if [[ ! -s "$base" ]]; then
    truncate -s 32000000000 "$base"
    dd if="$iso" of="$base" bs=16M conv=notrunc conv=sparse status=none
    sync
  fi
  # Default: every independent first-boot acceptance gets a fresh sparse copy
  # of the immutable base.  A two-boot persistence test explicitly arms reuse
  # with PAW_REUSE_MEDIA=1 so the second boot sees the PAWDATA created first.
  if [[ ${PAW_REUSE_MEDIA:-0} != 1 || ! -s "$media" ]]; then
    rm -f "$media"
    cp --sparse=always "$base" "$media"
    sync
  fi
  {
    echo "iso=$iso"
    echo "iso_bytes=$(stat -c %s "$iso")"
    echo "media=$media"
    echo "media_bytes=$(stat -c %s "$media")"
    echo "media_allocated_bytes=$(( $(stat -c %b "$media") * 512 ))"
  } >"$work/boot/manifest-media.txt"
  cat "$work/boot/manifest-media.txt"
}

# The 50 GiB main chain already has a release ISO with the branch scripts
# injected by build-live-lab-iso.sh; only the USB media is needed here.  This
# avoids unsquashing and re-injecting the release rootfs a second time.
if [[ ${PAW_MEDIA_ONLY:-0} == 1 ]]; then
  build_media
  echo "[prehw] media build complete: $work/boot"
  exit 0
fi

install -d -m 0755 "$work/iso/live"
if [[ ! -s "$work/iso/live/filesystem.squashfs" ]]; then
  echo "[prehw] extracting ISO live files"
  "$xorriso" -osirrox on -indev "$iso" \
    -extract /live/filesystem.squashfs "$work/iso/live/filesystem.squashfs" \
    -extract /live/vmlinuz "$work/iso/live/vmlinuz" \
    -extract /live/initrd.img "$work/iso/live/initrd.img" 2>"$work/xorriso.log"
fi
[[ -s "$work/iso/live/filesystem.squashfs" ]] || { echo 'missing squashfs' >&2; exit 2; }

if [[ ! -x "$work/rootfs/sbin/init" ]]; then
  echo "[prehw] unsquashing release root filesystem"
  rm -rf "$work/rootfs"
  rc=0
  unsquashfs -d "$work/rootfs" "$work/iso/live/filesystem.squashfs" >"$work/unsquashfs.log" || rc=$?
  if [[ "$rc" -ne 0 && "$rc" -ne 2 ]]; then echo "unsquashfs failed rc=$rc" >&2; exit "$rc"; fi
fi
rootfs="$work/rootfs"
[[ -x "$rootfs/sbin/init" ]] || { echo 'release rootfs has no init' >&2; exit 2; }

echo "[prehw] injecting branch scripts and v2.8 harness"
install -d "$rootfs/opt/paw-migration/tests/prehardware"
rm -rf "$rootfs/opt/paw-migration/scripts"
cp -a "$repo/scripts/." "$rootfs/opt/paw-migration/scripts/"
cp -a "$repo/configs/." "$rootfs/opt/paw-migration/configs/"
cp -a "$repo/tests/prehardware/." "$rootfs/opt/paw-migration/tests/prehardware/"
chmod 0755 "$rootfs/opt/paw-migration/tests/prehardware/"*.sh
install -d "$rootfs/opt/paw-migration/boot"
install -m 0644 "$repo/boot/20-wired.network" "$rootfs/opt/paw-migration/boot/20-wired.network"
source_bytes="$(stat -c %s "$work/boot/source50.raw" 2>/dev/null || echo 53687091200)"
target_bytes="$(stat -c %s "$work/boot/target.img" 2>/dev/null || echo "${PAW_EXPECTED_TARGET_BYTES:-240000000000}")"
sed -e "s/%SOURCE_BYTES%/$source_bytes/" -e "s/%TARGET_BYTES%/$target_bytes/" \
  "$repo/tests/prehardware/paw-prehardware-chain.service" \
  >"$rootfs/etc/systemd/system/paw-prehardware-chain.service"
chmod 0644 "$rootfs/etc/systemd/system/paw-prehardware-chain.service"
ln -sfn /etc/systemd/system/paw-prehardware-chain.service "$rootfs/etc/systemd/system/multi-user.target.wants/paw-prehardware-chain.service"
install -m 0644 "$work/iso/live/vmlinuz" "$rootfs/boot/vmlinuz"

# Disposable serial autologin only for the QEMU lab; the production ISO keeps
# its normal getty behaviour.
install -d "$rootfs/etc/systemd/system/serial-getty@ttyS0.service.d"
cat >"$rootfs/etc/systemd/system/serial-getty@ttyS0.service.d/autologin.conf" <<'UNIT'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear --keep-baud 115200,38400,9600 %I $TERM
UNIT
install -d "$rootfs/etc/systemd/system/getty.target.wants"
ln -sfn /lib/systemd/system/serial-getty@ttyS0.service "$rootfs/etc/systemd/system/getty.target.wants/serial-getty@ttyS0.service"

# One-shot GRUB BIOS install for the disposable lab guest disk only.
cat >"$rootfs/etc/systemd/system/paw-prehardware-grub-install.service" <<'UNIT'
[Unit]
Description=PAW v2.8 lab GRUB install (disposable QEMU /dev/vda only)
After=local-fs.target
ConditionPathExists=!/boot/grub/grub.cfg

[Service]
Type=oneshot
ExecStart=/opt/paw-migration/tests/prehardware/install-guest-grub.sh
StandardOutput=journal+console
StandardError=journal+console

[Install]
WantedBy=multi-user.target
UNIT
ln -sfn /etc/systemd/system/paw-prehardware-grub-install.service "$rootfs/etc/systemd/system/multi-user.target.wants/paw-prehardware-grub-install.service"

copy_with_libs(){
  local bin="$1" dest="$2" lib
  install -d "$(dirname "$rootfs$dest")"
  cp -aL "$bin" "$rootfs$dest"
  while read -r lib; do
    [[ -n "$lib" && -e "$lib" ]] || continue
    if [[ ! -e "$rootfs$lib" ]]; then install -d "$rootfs$(dirname "$lib")"; cp -aL "$lib" "$rootfs$lib"; fi
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
[[ -e "$rootfs/usr/sbin/grub-bios-setup" ]] || ln -sfn ../lib/grub/i386-pc/grub-bios-setup "$rootfs/usr/sbin/grub-bios-setup"

echo "[prehw] building lab initramfs (root=/dev/vda2, AHCI/virtio available)"
"$repo/tests/prehardware/build-initrd.sh" "$rootfs" "$work/iso/live/vmlinuz" "$work/boot/initrd.img" >"$work/initrd.log"
cp -a "$work/boot/initrd.img" "$rootfs/boot/initrd.img"

echo "[prehw] sizing guest root filesystem"
root_kb="$(du -sk "$rootfs" | awk '{print $1}')"
root_bytes=$(( (root_kb + 1048576) * 1024 ))
root_bytes=$(( ((root_bytes + 1048575) / 1048576) * 1048576 ))
rootpart="$work/boot/rootpart.img"
rm -f "$rootpart"
truncate -s "$root_bytes" "$rootpart"
fakeroot mke2fs -q -F -t ext4 -L PAW-LAB-ROOT -d "$rootfs" "$rootpart" >"$work/mke2fs.log" 2>&1

echo "[prehw] creating guest GPT disk (BIOS Boot + root)"
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

build_media

cat >>"$work/boot/manifest-media.txt" <<MANIFEST
guest_bytes=$(stat -c %s "$guest")
kernel=$work/iso/live/vmlinuz
initrd=$work/boot/initrd.img
MANIFEST
cat "$work/boot/manifest-media.txt"
echo "[prehw] lab build complete: $work/boot"
