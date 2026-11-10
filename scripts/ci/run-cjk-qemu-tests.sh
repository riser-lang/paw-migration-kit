#!/usr/bin/env bash
# Build a disposable ext4 image from the real ISO squashfs, boot it with the
# ISO kernel on QEMU SeaBIOS/TCG + std VGA, and verify Chinese tty1 output by
# exact PSF glyph matching.  Runs as root in GitHub Actions for mke2fs -d.
set -Eeuo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
iso="${PAW_CJK_ISO:-$root/boot/custom/paw-live-amd64.iso}"
out="${PAW_ARTIFACT_DIR:-$PWD/artifacts}"
work="$root/tests/virtual/cjk-qemu-run"
report="$out/qemu-cjk-test-report.txt"
[[ -r "$iso" ]] || { echo "missing ISO: $iso" >&2; exit 2; }
command -v mke2fs >/dev/null && command -v debugfs >/dev/null || { echo 'e2fsprogs required' >&2; exit 2; }
command -v xorriso >/dev/null && command -v unsquashfs >/dev/null || { echo 'xorriso/squashfs-tools required' >&2; exit 2; }
rm -rf "$work"; mkdir -p "$work" "$out"
printf 'PAW framebuffer CJK tty1 QEMU results\n' >"$report"
printf 'Executed: %s\nISO: %s\n' "$(date -u +%FT%TZ)" "$iso" >>"$report"

for item in vmlinuz filesystem.squashfs; do
  xorriso -osirrox on -indev "$iso" -extract "/live/$item" "$work/$item" >>"$report" 2>&1
done
unsquashfs -q -d "$work/rootfs" "$work/filesystem.squashfs" >>"$report" 2>&1
: >"$work/rootfs/etc/fstab"
font="$work/rootfs/opt/paw-migration/fonts/paw-cjk-16x16.psf"
[[ -s "$font" ]] || { printf 'FAIL ISO does not contain %s\n' "$font" >>"$report"; cat "$report"; exit 1; }
# Build a minimal initramfs from the ISO's own modules.  The live-boot initrd
# expects boot=live and does not reliably honor root=/dev/vda for this plain
# ext4 test image; this initrd only mounts /dev/vda, loads bochs DRM and hands
# over to systemd.
kernel="$(find "$work/rootfs/boot" -maxdepth 1 -name 'vmlinuz-*' -type f | sort | head -n1)"
[[ -s "$kernel" ]] || kernel="$work/vmlinuz"
initrd="$work/initrd-cjk.img"
"$root/tests/qemu/build-fbcon-initrd.sh" "$work/rootfs" "$kernel" "$initrd" >>"$report" 2>&1
printf 'Kernel: %s\nInitrd: %s\n' "$kernel" "$initrd" >>"$report"

size_mb=$(( $(du -sm "$work/rootfs" | cut -f1) + 1024 ))
base="$work/base.img"
truncate -s "${size_mb}M" "$base"
mke2fs -q -F -t ext4 -d "$work/rootfs" "$base"

cmds="$work/debugfs.cmds"
{
  echo 'mkdir /opt/paw-migration/tests'
  echo 'mkdir /opt/paw-migration/tests/virtual'
  echo 'mkdir /etc/systemd/system/paw-data-init.service.d'
  echo 'mkdir /etc/systemd/system/multi-user.target.wants'
  echo 'rm /etc/paw-migration.env'
} >"$cmds"
add_file(){
  printf 'write %s %s\n' "$1" "$2" >>"$cmds"
  printf 'sif %s mode 0%s\n' "$2" "$3" >>"$cmds"
}
add_file "$root/tests/qemu/qemu-data-init-wrapper" /opt/paw-migration/qemu-data-init-wrapper.sh 100755
add_file "$root/tests/qemu/qemu-lsblk-shim" /usr/local/bin/lsblk 100755
add_file "$root/tests/qemu/qemu-data-init-dropin.conf" /etc/systemd/system/paw-data-init.service.d/90-qemu-test.conf 100644
add_file "$root/tests/qemu/qemu-paw-env" /etc/paw-migration.env 100644
add_file "$root/tests/qemu/paw-cjk-render-probe.sh" /opt/paw-migration/paw-cjk-render-probe.sh 100755
add_file "$root/tests/qemu/paw-cjk-render.service" /etc/systemd/system/paw-cjk-render.service 100644
for unit in paw-data-init.service paw-console.service paw-console-font.service paw-cjk-render.service; do
  echo "rm /etc/systemd/system/multi-user.target.wants/$unit" >>"$cmds"
  echo "symlink /etc/systemd/system/multi-user.target.wants/$unit ../$unit" >>"$cmds"
done
debugfs -w -f "$cmds" "$base" >/dev/null 2>&1

passed=0; failed=0; blocked=0
run_case(){
  local case="$1" timeout="$2" image="$work/case-$1.img" log="$out/qemu-cjk-$1.log"
  cp --sparse=always "$base" "$image"
  set +e
  python3 "$root/tests/qemu/qemu_cjk_screen_test.py" \
    --case "$case" --image "$image" --kernel "$kernel" --initrd "$initrd" \
    --font "$font" --out "$out/qemu-cjk" --timeout "$timeout" \
    --qemu-lib "" --qemu-modules "" --qemu-data "${PAW_QEMU_DATA:-}" >"$log" 2>&1
  local rc=$?
  set -e
  cat "$log" >>"$report"
  if ((rc == 0)); then passed=$((passed+1)); else failed=$((failed+1)); fi
  rm -f "$image"
  return 0
}
run_case ok 60
run_case bad 60
run_case timeout 5
run_case render 60

printf 'Cases: %s passed, %s failed, %s blocked\n' "$passed" "$failed" "$blocked" >>"$report"
printf 'Font: %s\nFont SHA256: %s\n' "$font" "$(sha256sum "$font" | awk '{print $1}')" >>"$report"
cat "$report"
((failed == 0))
