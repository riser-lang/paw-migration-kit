#!/usr/bin/env bash
set -Eeuo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
iso="${1:?custom ISO path required}"
out="${PAW_ARTIFACT_DIR:-$PWD/artifacts}"
tmp="${RUNNER_TEMP:-/tmp}/paw-qemu-smoke"
mkdir -p "$out" "$tmp"
serial="$tmp/serial.log"
qemu="${QEMU_BIN:-qemu-system-x86_64}"

mountpoint="$tmp/iso"
mkdir -p "$mountpoint"
mount -o loop,ro "$iso" "$mountpoint"
unsquashfs -cat "$mountpoint/live/filesystem.squashfs" opt/paw-migration/scripts/paw-hardware-preflight.sh >/dev/null
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
for _ in $(seq 1 450); do
  if grep -q 'AUTOSTART_GATE=' "$serial" 2>/dev/null; then ready=1; break; fi
  kill -0 "$pid" 2>/dev/null || break
  sleep 2
done
if [[ $ready != 1 ]]; then
  {
    echo 'QEMU smoke test: FAIL'
    echo 'Live boot did not reach the migration readiness gate within 15 minutes.'
    if grep -q 'AUTOSTART_GATE=' "$serial" 2>/dev/null; then echo 'Gate marker observed: yes'; else echo 'Gate marker observed: no'; fi
    if grep -Eiq 'Reached target .*Multi-User System|Startup finished' "$serial" 2>/dev/null; then echo 'Systemd reached userspace-ready stage: yes'; else echo 'Systemd reached userspace-ready stage: no'; fi
    if grep -Eiq 'Failed to start|Dependency failed for' "$serial" 2>/dev/null; then echo 'Systemd reported a failed unit: yes'; else echo 'Systemd reported a failed unit: no'; fi
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
  echo 'Acceleration: TCG; KVM not used'
  echo 'Live ISO booted and systemd readiness gate ran.'
  echo 'Hardware-preflight entry is present in the built filesystem.'
  echo 'Missing physical target/source kept readiness BLOCKED.'
  echo 'Clone start marker: false'
  echo 'This test does not establish compatibility with the physical ASUS board or SSD.'
} >"$out/qemu-smoke-report.txt"
