#!/usr/bin/env bash
# One-shot GRUB BIOS install for the disposable v2.8 guest disk.
# This only runs in the QEMU lab root filesystem on /dev/vda, never on a
# physical disk and never on the migration target /dev/sdb.
set -Eeuo pipefail
[[ -b /dev/vda && -b /dev/vda2 ]] || { echo 'lab guest disks are missing' >&2; exit 2; }
[[ "$(findmnt -n -o SOURCE /)" == /dev/vda2 ]] || { echo 'lab guest root is not /dev/vda2' >&2; exit 2; }

install -d /boot/grub
grub-install --target=i386-pc --recheck --no-floppy /dev/vda
cat >/boot/grub/grub.cfg <<'CFG'
set default=0
set timeout=1
insmod part_gpt
insmod ext2
menuentry 'PAW v2.8 lab root' {
  linux /boot/vmlinuz root=/dev/vda2 rw console=tty1 console=ttyS0,115200n8
  initrd /boot/initrd.img
}
CFG
sync
echo 'PAW_PREHW_GRUB_INSTALL=PASS'
systemctl poweroff
