#!/usr/bin/env bash
# Run the tty1 QEMU display/keyboard cases against a disposable Debian image.
# Requires qemu-system-x86_64 (or PAW_QEMU_BIN), a base ext4 Debian 13 image
# with a kernel/initrd, and about 7 GiB of free temporary storage.
set -Eeuo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
base_image="${PAW_QEMU_BASE_IMAGE:-$HOME/paw-qemu/rootpart.img}"
kernel="${PAW_QEMU_KERNEL:-$HOME/paw-qemu/boot/vmlinuz}"
initrd="${PAW_QEMU_INITRD:-$HOME/paw-qemu/boot/initrd.img}"
out="${PAW_ARTIFACT_DIR:-$PWD/artifacts}/qemu-tty"
work="${PAW_QEMU_WORK:-$root/tests/virtual/qemu-tty-run}"
report="$out/qemu-tty-test-report.txt"
mkdir -p "$out" "$work"
passed=0; failed=0; blocked=0
printf 'PAW tty1 QEMU display/keyboard results\n' >"$report"
printf 'Executed: %s\n' "$(date -u +%FT%TZ)" >>"$report"
printf 'Base image: %s\nKernel: %s\nInitrd: %s\n' "$base_image" "$kernel" "$initrd" >>"$report"

if [[ ! -r "$base_image" || ! -r "$kernel" || ! -r "$initrd" ]]; then
  printf 'BLOCKED base image, kernel or initrd missing\n' >>"$report"
  cat "$report"; exit 0
fi
if ! command -v "${PAW_QEMU_BIN:-$HOME/paw-qemu/sysroot/usr/bin/qemu-system-x86_64}" >/dev/null 2>&1; then
  printf 'BLOCKED qemu-system-x86_64 not found\n' >>"$report"
  cat "$report"; exit 0
fi

base="$work/qemu-tty-base.img"
if [[ ! -s "$base" ]]; then
  bash "$root/tests/qemu/build-tty-test-image.sh" "$base_image" "$base" >>"$report" 2>&1 || {
    printf 'FAIL could not build QEMU test image\n' >>"$report"; cat "$report"; exit 1;
  }
fi

run_case(){
  local case="$1" send="$2" timeout="$3"
  local image="$work/qemu-tty-$case.img" log="$out/$case.log"
  cp --sparse=always "$base" "$image"
  set +e
  PAW_QEMU_BIN="${PAW_QEMU_BIN:-$HOME/paw-qemu/sysroot/usr/bin/qemu-system-x86_64}" \
    python3 "$root/tests/qemu/qemu_tty_screen_test.py" \
      --case "$case" --image "$image" --kernel "$kernel" --initrd "$initrd" \
      --out "$out/$case" --send "$send" --timeout "$timeout" >"$log" 2>&1
  rc=$?
  set -e
  cat "$log" >>"$report"
  if ((rc == 0)); then passed=$((passed+1));
  elif ((rc == 77)); then blocked=$((blocked+1));
  else failed=$((failed+1)); fi
  rm -f "$image"
  return 0
}

run_case ok '123456' 60
run_case bad '000000' 60
run_case timeout '' 5

printf 'Summary: %s cases passed, %s failed, %s blocked\n' "$passed" "$failed" "$blocked" >>"$report"
cat "$report"
((failed == 0))
