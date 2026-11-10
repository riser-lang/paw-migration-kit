#!/usr/bin/env bash
# Verify that the built ISO really contains the reviewed sources.
#
# The build copies a fixed set of files into the live filesystem; this script reads the
# ISO back, compares each payload file byte-for-byte against the repository, and refuses
# to pass when the ISO has extra or missing paw-* scripts.  It exists because "the ISO was
# built from this tree" was so far only implied by the build log.
#
# Runs as root in GitHub Actions (needs xorriso + unsquashfs, both already installed).
set -Eeuo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
iso="${PAW_ISO:-$root/boot/custom/paw-live-amd64.iso}"
out="${PAW_ARTIFACT_DIR:-$PWD/artifacts}"
report="$out/iso-payload-report.txt"
squashfs_dir="${PAW_PAYLOAD_WORK:-${TMPDIR:-/tmp}/paw-iso-payload}"

[[ -r "$iso" ]] || { echo "missing ISO: $iso" >&2; exit 2; }
command -v xorriso >/dev/null || { echo 'xorriso required' >&2; exit 2; }
command -v unsquashfs >/dev/null || { echo 'unsquashfs required' >&2; exit 2; }

mkdir -p "$out" "$squashfs_dir"
: >"$report"

pass=0
fail=0
log() { printf '%s\n' "$*" | tee -a "$report" >/dev/null; }
check() {
  local label="$1" expected="${2#\\}" actual="${3#\\}"
  # sha256sum prefixes a backslash when the file name contains one (the mount unit is
  # var-lib-paw\x2dmigration.mount), so strip it before comparing.
  if [[ "$expected" == "$actual" ]]; then
    pass=$((pass + 1))
    printf 'PASS %s\n' "$label" >>"$report"
  else
    fail=$((fail + 1))
    printf 'FAIL %s\n' "$label" >>"$report"
    printf '  expected %s\n  actual   %s\n' "$expected" "$actual" >>"$report"
  fi
}

printf 'PAW ISO payload verification\n' >>"$report"
printf 'Executed: %s\nISO: %s (%s bytes)\n' \
  "$(date -u +%FT%TZ)" "$iso" "$(stat -c %s "$iso")" >>"$report"

# Extract the live filesystem once; unsquashfs -cat per file would re-read the whole
# image for every comparison.
xorriso -osirrox on -indev "$iso" -extract /live/filesystem.squashfs "$squashfs_dir/filesystem.squashfs" \
  >>"$report" 2>&1
unsquashfs -q -d "$squashfs_dir/rootfs" "$squashfs_dir/filesystem.squashfs" >>"$report" 2>&1

live="$squashfs_dir/rootfs"

# scripts/paw-*.sh and scripts/paw-*.py -> /opt/paw-migration/scripts/
shopt -s nullglob
repo_scripts=( "$root"/scripts/paw-*.sh "$root"/scripts/paw-*.py )
((${#repo_scripts[@]} > 0)) || { echo 'no paw-* scripts in the repository' >&2; exit 2; }

printf '\n== scripts/paw-*\n' >>"$report"
declare -A repo_names=()
for file in "${repo_scripts[@]}"; do
  name="$(basename "$file")"
  repo_names["$name"]=1
  target="$live/opt/paw-migration/scripts/$name"
  if [[ ! -f "$target" ]]; then
    fail=$((fail + 1))
    printf 'FAIL %s missing from the ISO\n' "$name" >>"$report"
    continue
  fi
  check "$name matches the repository" \
    "$(sha256sum "$file" | cut -d' ' -f1)" \
    "$(sha256sum "$target" | cut -d' ' -f1)"
done

for target in "$live"/opt/paw-migration/scripts/paw-*.sh "$live"/opt/paw-migration/scripts/paw-*.py; do
  name="$(basename "$target")"
  if [[ -z "${repo_names[$name]:-}" ]]; then
    fail=$((fail + 1))
    printf 'FAIL %s exists only in the ISO\n' "$name" >>"$report"
  fi
done

# boot/bin/* -> /opt/paw-migration/bin/
printf '\n== boot binaries\n' >>"$report"
for file in "$root"/boot/bin/*; do
  [[ -f "$file" ]] || continue
  name="$(basename "$file")"
  target="$live/opt/paw-migration/bin/$name"
  if [[ ! -f "$target" ]]; then
    fail=$((fail + 1))
    printf 'FAIL bin/%s missing from the ISO\n' "$name" >>"$report"
    continue
  fi
  check "bin/$name matches the repository" \
    "$(sha256sum "$file" | cut -d' ' -f1)" \
    "$(sha256sum "$target" | cut -d' ' -f1)"
done

# configs/*.template -> /opt/paw-migration/configs/ and /etc/paw-migration.env
printf '\n== configs\n' >>"$report"
for name in source.template.json target-ssd.template.json xray-client.template.json; do
  check "configs/$name matches the repository" \
    "$(sha256sum "$root/configs/$name" | cut -d' ' -f1)" \
    "$(sha256sum "$live/opt/paw-migration/configs/$name" | cut -d' ' -f1)"
done
check 'paw-migration.env is the reviewed template' \
  "$(sha256sum "$root/configs/paw-migration.env.template" | cut -d' ' -f1)" \
  "$(sha256sum "$live/etc/paw-migration.env" | cut -d' ' -f1)"

# systemd units and network config
printf '\n== units and network\n' >>"$report"
for unit in paw-preflight.service paw-data-init.service paw-console.service \
            paw-console-font.service paw-network-bootstrap.service \
            paw-xray-client.service paw-tailscale-join.service tailscaled.service; do
  check "$unit matches the repository" \
    "$(sha256sum "$root/boot/$unit" | cut -d' ' -f1)" \
    "$(sha256sum "$live/etc/systemd/system/$unit" | cut -d' ' -f1)"
done
check 'paw-data.mount matches the repository' \
  "$(sha256sum "$root/boot/paw-data.mount" | cut -d' ' -f1)" \
  "$(sha256sum "$live/etc/systemd/system/var-lib-paw\\x2dmigration.mount" | cut -d' ' -f1)"
check '20-wired.network matches the repository' \
  "$(sha256sum "$root/boot/20-wired.network" | cut -d' ' -f1)" \
  "$(sha256sum "$live/etc/systemd/network/20-wired.network" | cut -d' ' -f1)"

# The ISO-level memtest menu entry must be the reviewed one, not a live-build default.
printf '\n== boot menu\n' >>"$report"
xorriso -osirrox on -indev "$iso" -extract /isolinux/memtest.cfg "$squashfs_dir/memtest.cfg" \
  >>"$report" 2>&1 || true
if [[ -s "$squashfs_dir/memtest.cfg" ]]; then
  check 'isolinux/memtest.cfg matches the repository' \
    "$(sha256sum "$root/configs/live-build/bootloaders/isolinux/memtest.cfg" | cut -d' ' -f1)" \
    "$(sha256sum "$squashfs_dir/memtest.cfg" | cut -d' ' -f1)"
else
  fail=$((fail + 1))
  printf 'FAIL isolinux/memtest.cfg missing from the ISO\n' >>"$report"
fi

# The generated CJK font is built inside the ISO by a hook, so compare its shape instead
# of its bytes: it must exist and carry the expected 16x16 header magic.
font="$live/opt/paw-migration/fonts/paw-cjk-16x16.psf"
if [[ -s "$font" ]]; then
  magic="$(head -c 2 "$font" | od -An -tx1 | tr -d ' \n')"
  check 'paw-cjk-16x16.psf carries the PSF2 magic 72b5' '72b5' "$magic"
else
  fail=$((fail + 1))
  printf 'FAIL paw-cjk-16x16.psf missing from the ISO\n' >>"$report"
fi

printf '\nSummary: %d passed, %d failed\n' "$pass" "$fail" >>"$report"
cat "$report"
((fail == 0))
