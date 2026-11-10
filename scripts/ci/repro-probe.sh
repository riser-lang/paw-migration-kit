#!/usr/bin/env bash
# Characterise why two builds of the same tree differ.
#
# The REPRO blocker says "same size, different SHA256". This probe builds a second ISO in
# a fresh work directory, then compares the two images layer by layer so the report can say
# *what* differs instead of only *that* it differs:
#
#   1. size and SHA256 of the two ISOs
#   2. first differing byte offset
#   3. ISO volume metadata (creation/modification dates from xorriso -toc)
#   4. /live/vmlinuz, /live/initrd.img and /live/filesystem.squashfs hashes
#   5. squashfs metadata (unsquashfs -s) and full file listing (unsquashfs -ll)
#   6. content hashes of a sample of files read straight out of both squashfs images
#
# Runs as root in GitHub Actions; needs xorriso, unsquashfs and live-build.
set -Eeuo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
out="${PAW_ARTIFACT_DIR:-$PWD/artifacts}"
work="${PAW_PROBE_WORK:-${RUNNER_TEMP:-/tmp}/paw-repro-probe}"
report="$out/iso-repro-report.txt"
iso="$root/boot/custom/paw-live-amd64.iso"

mkdir -p "$out" "$work"
: >"$report"
say() { printf '%s\n' "$*" >>"$report"; }

say "PAW ISO reproducibility probe"
say "Executed: $(date -u +%FT%TZ)"
say "Build work for the second build: $work/build-b"

[[ -s "$iso" ]] || { echo "missing ISO: $iso" >&2; exit 2; }

# --- build A: keep the ISO that the normal job already produced -------------------------
cp "$iso" "$work/iso-a.iso"
sha_a="$(sha256sum "$work/iso-a.iso" | cut -d' ' -f1)"
size_a="$(stat -c %s "$work/iso-a.iso")"
say ""
say "== build A"
say "bytes=$size_a"
say "sha256=$sha_a"

# --- build B: fresh work directory, same command, same SOURCE_DATE_EPOCH ----------------
rm -rf "$work/build-b"
PAW_BUILD_WORK="$work/build-b" "$root/scripts/build-debian-live.sh" >"$work/build-b.log" 2>&1 || {
  say ""
  say "FAIL second build did not complete; see the job log"
  tail -n 20 "$work/build-b.log" >>"$report"
  exit 1
}
cp "$iso" "$work/iso-b.iso"
sha_b="$(sha256sum "$work/iso-b.iso" | cut -d' ' -f1)"
size_b="$(stat -c %s "$work/iso-b.iso")"
say ""
say "== build B"
say "bytes=$size_b"
say "sha256=$sha_b"
say ""
if [[ "$sha_a" == "$sha_b" ]]; then
  say "VERDICT: REPRO=IDENTICAL"
else
  say "VERDICT: REPRO=DIFFERS"
fi

# --- 2. first differing byte ------------------------------------------------------------
say ""
say "== first differing byte"
if cmp -s "$work/iso-a.iso" "$work/iso-b.iso"; then
  say "identical"
else
  # cmp exits 1 when the files differ, so every pipeline below needs its own `|| true`;
  # with pipefail+errexit the bare form aborted the probe right here.
  offset="$( { cmp -l "$work/iso-a.iso" "$work/iso-b.iso" 2>/dev/null || true; } | head -n1 | awk '{print $1}')"
  say "first_offset=${offset:-unknown}"
  differing="$( { cmp -l "$work/iso-a.iso" "$work/iso-b.iso" 2>/dev/null || true; } | wc -l)"
  say "differing_bytes_total=${differing:-unknown}"
fi

# --- 3. ISO volume metadata ------------------------------------------------------------
say ""
say "== ISO volume metadata (xorriso -toc)"
for side in a b; do
  xorriso -indev "$work/iso-$side.iso" -toc 2>&1 |
    grep -E 'Volume id|Volume set id|Creation|Modification|Expiration|Effective' |
    sed "s/^/[$side] /" >>"$report" || true
done

# --- 4. big live/ components -----------------------------------------------------------
mix="$work/mix"
rm -rf "$mix"; mkdir -p "$mix/a" "$mix/b"
say ""
say "== /live components"
for side in a b; do
  xorriso -osirrox on -indev "$work/iso-$side.iso" \
    -extract /live/vmlinuz "$mix/$side/vmlinuz" \
    -extract /live/initrd.img "$mix/$side/initrd.img" \
    -extract /live/filesystem.squashfs "$mix/$side/filesystem.squashfs" \
    >/dev/null 2>&1
done
for item in vmlinuz initrd.img filesystem.squashfs; do
  hash_a="$(sha256sum "$mix/a/$item" | cut -d' ' -f1)"
  hash_b="$(sha256sum "$mix/b/$item" | cut -d' ' -f1)"
  same=nope
  [[ "$hash_a" == "$hash_b" ]] && same=yes
  say "$item same=$same a=${hash_a:0:16} b=${hash_b:0:16} bytes_a=$(stat -c %s "$mix/a/$item") bytes_b=$(stat -c %s "$mix/b/$item")"
done

# --- 5. squashfs metadata and listing --------------------------------------------------
say ""
say "== squashfs metadata (unsquashfs -s)"
for side in a b; do
  unsquashfs -s "$mix/$side/filesystem.squashfs" 2>/dev/null |
    grep -Ev '^(Parallel|Number of|Filesystem size|Compression|Block size|Bytes used|Inodes|Fragments|Exportable|Xattrs|Compressor|Duplicates)' |
    sed "s/^/[$side] /" >>"$report" || true
done

say ""
say "== squashfs file listing"
unsquashfs -ll "$mix/a/filesystem.squashfs" 2>/dev/null | awk '{$1="";$2="";$3="";$4=""; print}' >"$work/listing-a.txt"
unsquashfs -ll "$mix/b/filesystem.squashfs" 2>/dev/null | awk '{$1="";$2="";$3="";$4=""; print}' >"$work/listing-b.txt"
say "listing_lines_a=$(wc -l <"$work/listing-a.txt")"
say "listing_lines_b=$(wc -l <"$work/listing-b.txt")"
listing_diff="$(diff "$work/listing-a.txt" "$work/listing-b.txt" | grep -c '^[<>]' || true)"
say "listing_differing_lines=${listing_diff:-0}"
if [[ "${listing_diff:-0}" != "0" ]]; then
  say "first 15 listing differences:"
  diff "$work/listing-a.txt" "$work/listing-b.txt" | head -n 15 >>"$report" || true
fi

# --- 6. content sample straight out of both images --------------------------------------
say ""
say "== content sample"
sample_paths=(
  opt/paw-migration/scripts/paw-final-confirm.sh
  opt/paw-migration/scripts/paw-stream-clone.sh
  opt/paw-migration/fonts/paw-cjk-16x16.psf
  etc/paw-migration.env
  etc/systemd/system/paw-console.service
  usr/bin/dash
  boot/grub/grub.cfg
)
same_count=0
diff_count=0
skip_count=0
empty_hash="$(printf '' | sha256sum | cut -d' ' -f1)"
for path in "${sample_paths[@]}"; do
  hash_a="$(unsquashfs -cat "$mix/a/filesystem.squashfs" "$path" 2>/dev/null | sha256sum | cut -d' ' -f1)"
  hash_b="$(unsquashfs -cat "$mix/b/filesystem.squashfs" "$path" 2>/dev/null | sha256sum | cut -d' ' -f1)"
  if [[ "$hash_a" == "$hash_b" ]]; then
    same_count=$((same_count + 1))
    say "same $path"
  elif [[ "$hash_a" == "$empty_hash" && "$hash_b" == "$empty_hash" ]]; then
    # unsquashfs -cat on a missing path prints nothing; do not count that as a match
    skip_count=$((skip_count + 1))
    say "skip $path (absent from both images)"
  else
    diff_count=$((diff_count + 1))
    say "DIFF $path a=${hash_a:0:16} b=${hash_b:0:16}"
  fi
done
say "content_sample_same=$same_count content_sample_diff=$diff_count skipped=$skip_count"

say ""
say "Summary: ${same_count} sampled paths identical, ${diff_count} differ, ${skip_count} skipped, listing differences ${listing_diff:-0}"
printf 'report: %s\n' "$report"
