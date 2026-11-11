#!/usr/bin/env bash
# Run the branch's loop-backed fault-injection suites inside the disposable
# QEMU guest, where /dev/loop* and root are available.  Reports are written to
# the 9p host share so they survive even if the final reboot cuts the console.
set -Eeuo pipefail
root="${PAW_ROOT:-/opt/paw-migration}"
out="${PAW_SELFTEST_OUT:?PAW_SELFTEST_OUT required}"
mkdir -p "$out"
export PAW_ARTIFACT_DIR="$out"
export PAW_ROOT="$root"
rc=0
for suite in virtual network; do
  case "$suite" in
    virtual) script="$root/scripts/ci/run-virtual-tests.sh" ;;
    network) script="$root/scripts/ci/run-network-virtual-tests.sh" ;;
  esac
  log="$out/$suite-suite.log"
  if bash "$script" >"$log" 2>&1; then
    printf 'PAW_PREHW_SELFTEST=%s PASS %s\n' "$suite" "$(tail -n1 "$log")"
  else
    printf 'PAW_PREHW_SELFTEST=%s FAIL rc=%s %s\n' "$suite" "$?" "$(tail -n1 "$log")"
    rc=1
  fi
done
exit "$rc"
