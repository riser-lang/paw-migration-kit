#!/usr/bin/env bash
set -Eeuo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
iso="${1:?custom ISO path required}"
out="${PAW_ARTIFACT_DIR:-$PWD/artifacts}"
tmp="${RUNNER_TEMP:-/tmp}/paw-qemu-smoke"
mkdir -p "$out" "$tmp"
serial="$tmp/serial.log"
qemu="${QEMU_BIN:-qemu-system-x86_64}"
xorriso -indev "$iso" -report_system_area plain >"$out/iso-system-area.txt" 2>&1
cat "$out/iso-system-area.txt"
grep -Eiq 'isohybrid|isohdpfx|isohybrid.*MBR|MBR.*isohybrid' "$out/iso-system-area.txt" || {
  echo 'ISO system-area report does not identify an isohybrid MBR.' >"$out/qemu-smoke-report.txt"
  exit 1
}

mountpoint="$tmp/iso"
mkdir -p "$mountpoint"
mount -o loop,ro "$iso" "$mountpoint"
test -s "$mountpoint/live/vmlinuz"
test -s "$mountpoint/live/initrd.img"
grep -Eiq '^timeout[[:space:]]+[1-9][0-9]*$' "$mountpoint/isolinux/isolinux.cfg"
grep -Eiq '^include[[:space:]]+memtest\.cfg$' "$mountpoint/isolinux/isolinux.cfg"
grep -Eiq '^label[[:space:]]+memtest86$' "$mountpoint/isolinux/memtest.cfg"
test -s "$mountpoint/boot/memtest86+x64.bin"
unsquashfs -cat "$mountpoint/live/filesystem.squashfs" opt/paw-migration/scripts/paw-hardware-preflight.sh >/dev/null
unsquashfs -ll "$mountpoint/live/filesystem.squashfs" | grep -Eiq '(^|/)(usr/)?lib/firmware/rtl_nic/.*\.fw' || {
  echo 'Built ISO squashfs does not contain Realtek firmware (rtl_nic/*.fw).' >&2
  exit 1
}
grep -q 'AUTOSTART_GATE=' "$root/scripts/paw-live-controller.sh"
umount "$mountpoint"

"$qemu" \
  -machine pc,accel=tcg -cpu qemu64 -smp 2 -m 4096 \
  -cdrom "$iso" -boot order=d -display none \
  -serial "file:$serial" -monitor none -no-reboot \
  -netdev user,id=net0 -device e1000,netdev=net0 \
  >"$tmp/qemu.stdout" 2>"$tmp/qemu.stderr" &
pid=$!
cleanup(){
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  umount "$mountpoint" 2>/dev/null || true
  rm -rf "$tmp"
}
trap cleanup EXIT

ready=0
kernel_seen=0
for attempt in $(seq 1 450); do
  if grep -q 'AUTOSTART_GATE=' "$serial" 2>/dev/null; then ready=1; break; fi
  if grep -Eiq 'Linux version |Kernel command line:' "$serial" 2>/dev/null; then kernel_seen=1; fi
  if (( attempt == 90 && kernel_seen == 0 )); then break; fi
  kill -0 "$pid" 2>/dev/null || break
  sleep 2
done
if [[ $ready != 1 ]]; then
  {
    echo 'QEMU smoke test: FAIL'
    if (( kernel_seen == 0 )); then echo 'Linux kernel serial output observed: no'; else echo 'Linux kernel serial output observed: yes'; fi
    if grep -Eiq 'ISOLINUX|SYSLINUX|GNU GRUB' "$serial" 2>/dev/null; then echo 'Bootloader serial output observed: yes'; else echo 'Bootloader serial output observed: no'; fi
    if grep -Eiq 'systemd\[1\]|systemd .*running in system mode' "$serial" 2>/dev/null; then echo 'Systemd started: yes'; else echo 'Systemd started: no'; fi
    if grep -Eiq 'Kernel panic|VFS: Unable to mount root|No working init found' "$serial" 2>/dev/null; then echo 'Kernel or root filesystem fatal marker observed: yes'; else echo 'Kernel or root filesystem fatal marker observed: no'; fi
    echo 'Live boot did not reach the migration readiness gate.'
    if grep -q 'AUTOSTART_GATE=' "$serial" 2>/dev/null; then echo 'Gate marker observed: yes'; else echo 'Gate marker observed: no'; fi
    echo 'Raw serial output is discarded and is not uploaded.'
  } >"$out/qemu-smoke-report.txt"
  exit 1
fi
gate="$(grep -Eo 'AUTOSTART_GATE=(READY_FOR_OPERATOR|BLOCKED) clone_started=false' "$serial" | tail -n1)"
[[ "$gate" == 'AUTOSTART_GATE=BLOCKED clone_started=false' ]] || {
  echo 'QEMU did not fail closed with missing target/source prerequisites.' >"$out/qemu-smoke-report.txt"
  exit 1
}
{
  echo 'QEMU smoke test: PASS'
  echo 'Firmware: SeaBIOS (x86_64 PC machine)'
  echo 'ISO layout: xorriso reported an isohybrid MBR; suitable for whole-device imaging.'
  echo 'Memtest86+: independent ISOLINUX entry and BIOS binary are present.'
  echo 'Acceleration: TCG; KVM not used'
  echo 'Live ISO booted and systemd readiness gate ran.'
  echo 'Hardware-preflight entry is present in the built filesystem.'
  echo 'Missing physical target/source kept readiness BLOCKED.'
  echo 'Clone start marker: false'
  echo 'This test does not establish compatibility with the physical ASUS board or SSD.'
} >"$out/qemu-smoke-report.txt"
