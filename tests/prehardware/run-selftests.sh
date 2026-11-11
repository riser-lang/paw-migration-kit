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
mkdir -p /run/paw-network
for suite in virtual network; do
  case "$suite" in
    virtual) script="$root/scripts/ci/run-virtual-tests.sh" ;;
    network) script="$root/scripts/ci/run-network-virtual-tests.sh" ;;
  esac
  log="$out/$suite-suite.log"
  netdir="$(mktemp -d /run/paw-selftest-net.XXXXXX)"
  # The suites write placeholder Rescue endpoint/key files at the production
  # RAM path.  Run each in a private mount namespace with a temporary
  # /run/paw-network so cleanup can never delete the live chain's credentials.
  if unshare -m true 2>/dev/null; then
    run=(unshare -m bash -c 'mount --make-rprivate /; mount --bind "$1" /run/paw-network; shift; exec "$@"' _ "$netdir" env -u PAW_EXPECTED_SOURCE_BYTES "PAW_SELFTEST_OUT=$out" "PAW_ROOT=$root" bash "$script")
  else
    run=(env -u PAW_EXPECTED_SOURCE_BYTES "PAW_SELFTEST_OUT=$out" "PAW_ROOT=$root" bash "$script")
  fi
  if "${run[@]}" >"$log" 2>&1; then
    printf 'PAW_PREHW_SELFTEST=%s PASS %s\n' "$suite" "$(tail -n1 "$log")"
  else
    printf 'PAW_PREHW_SELFTEST=%s FAIL rc=%s %s\n' "$suite" "$?" "$(tail -n1 "$log")"
    rc=1
  fi
  rm -rf "$netdir"
done
exit "$rc"
