#!/usr/bin/env bash
# Build a disposable Debian test image for the Paw tty1 QEMU test.
#
# The base image is an ext4 Debian 13 root filesystem that already contains a
# kernel and initrd.  This harness never touches a host block device: it copies
# the base file, injects the PAW scripts/units with debugfs, and boots it as a
# QEMU virtio disk.  It is test tooling only and is not part of the ISO.
set -Eeuo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
base="${1:?usage: build-tty-test-image.sh BASE_EXT4_IMAGE OUTPUT_IMAGE}"
out="${2:?usage: build-tty-test-image.sh BASE_EXT4_IMAGE OUTPUT_IMAGE}"
[[ -f "$base" ]] || { echo "base image not found: $base" >&2; exit 2; }
[[ "$base" != "$out" ]] || { echo 'refusing to overwrite the base image' >&2; exit 2; }
command -v debugfs >/dev/null || { echo 'debugfs is required' >&2; exit 2; }
rm -f "$out"
cp --sparse=always "$base" "$out"

cmds="$(mktemp)"
trap 'rm -f "$cmds"' EXIT
{
  echo 'mkdir /opt/paw-migration'
  echo 'mkdir /opt/paw-migration/scripts'
  echo 'mkdir /opt/paw-migration/tests'
  echo 'mkdir /opt/paw-migration/tests/virtual'
  echo 'mkdir /etc/systemd/system/paw-data-init.service.d'
} >"$cmds"
debugfs -w -f "$cmds" "$out" >/dev/null 2>&1 || true

add_file(){
  local src="$1" dest="$2" mode="${3:-0644}"
  printf 'write %s %s\n' "$src" "$dest" >>"$cmds"
  printf 'sif %s mode 0%s\n' "$dest" "$mode" >>"$cmds"
}

: >"$cmds"
for src in "$root"/scripts/paw-*.sh; do
  add_file "$src" "/opt/paw-migration/scripts/$(basename "$src")" 100755
done
for src in "$root"/scripts/paw-*.py; do
  add_file "$src" "/opt/paw-migration/scripts/$(basename "$src")" 100755
done
for unit in "$root"/boot/*.service "$root"/boot/*.mount; do
  add_file "$unit" "/etc/systemd/system/$(basename "$unit")" 100644
done
add_file "$root/tests/qemu/qemu-lsblk-shim" /usr/local/bin/lsblk 100755
add_file "$root/tests/qemu/qemu-data-init-wrapper" /opt/paw-migration/qemu-data-init-wrapper.sh 100755
add_file "$root/tests/qemu/qemu-data-init-dropin.conf" /etc/systemd/system/paw-data-init.service.d/90-qemu-test.conf 100644
add_file "$root/tests/qemu/qemu-paw-env" /etc/paw-migration.env 100644

cat >>"$cmds" <<EOF
symlink /etc/systemd/system/multi-user.target.wants/paw-data-init.service ../paw-data-init.service
symlink /etc/systemd/system/multi-user.target.wants/paw-console.service ../paw-console.service
symlink /etc/systemd/system/getty.target.wants/getty@tty1.service /lib/systemd/system/getty@tty1.service
EOF
debugfs -w -f "$cmds" "$out" >/dev/null

for required in /opt/paw-migration/scripts/paw-data-prepare.sh \
  /opt/paw-migration/scripts/paw-tty-lib.sh \
  /etc/systemd/system/paw-data-init.service \
  /etc/systemd/system/paw-console.service \
  /etc/systemd/system/multi-user.target.wants/paw-data-init.service; do
  debugfs -R "stat $required" "$out" 2>/dev/null | grep -q 'Inode:' || {
    echo "injection failed: $required" >&2; exit 1;
  }
done
echo "built QEMU tty test image: $out"
