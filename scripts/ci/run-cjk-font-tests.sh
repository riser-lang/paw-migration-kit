#!/usr/bin/env bash
# Validate the generated CJK PSF font independently of the screen test.
set -Eeuo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
out="${PAW_ARTIFACT_DIR:-$PWD/artifacts}"
report="$out/cjk-font-test-report.txt"
work="$root/tests/virtual/cjk-font-run"
rm -rf "$work"; mkdir -p "$work" "$out"
trap 'rm -rf "$work"' EXIT
passed=0; failed=0
pass(){ printf 'PASS %s\n' "$1" >>"$report"; passed=$((passed+1)); }
fail(){ printf 'FAIL %s\n' "$1" >>"$report"; failed=$((failed+1)); }
printf 'PAW CJK console font validation\n' >"$report"
printf 'Executed: %s\n' "$(date -u +%FT%TZ)" >>"$report"

font="${PAW_CJK_FONT:-$work/paw-cjk-16x16.psf}"
fallback="${PAW_CJK_FALLBACK:-$work/paw-cjk-8x16.psf}"
unifont="${PAW_UNIFONT_HEX:-/usr/share/unifont/unifont.hex}"
version="${PAW_UNIFONT_VERSION:-unknown}"
if [[ ! -s "$font" ]]; then
  if [[ -r "$unifont" ]]; then
    python3 "$root/scripts/paw-build-cjk-font.py" \
      --unifont "$unifont" --scan "$root/scripts" --scan "$root/boot" \
      --out "$font" --fallback-out "$fallback" --manifest "$work/paw-cjk-font.json" \
      --unifont-version "$version" >>"$report" 2>&1
  else
    printf 'BLOCKED unifont.hex and prebuilt font are both unavailable\n' >>"$report"
    cat "$report"; exit 1
  fi
fi
printf 'Font: %s\nFallback: %s\nUnifont: %s (%s)\n' "$font" "$fallback" "$unifont" "$version" >>"$report"

if python3 - "$font" "$fallback" "$root" <<'PY' >>"$report" 2>&1
import struct, sys
from pathlib import Path
font_path, fallback_path, root = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
raw = font_path.read_bytes()
magic, version, headersize, flags, length, charsize, height, width = struct.unpack("<8I", raw[:32])
assert raw[:4] == b"\x72\xb5\x4a\x86", "PSF2 magic/byte order"
assert (width, height, charsize, length) == (16, 16, 32, 512), (width, height, charsize, length)
assert flags & 1, "PSF2 must carry a Unicode table"
table = raw[headersize + length * charsize:]
mapped = {}
idx = slot = 0
while slot < length and idx < len(table):
    end = table.find(b"\xff", idx)
    if end < 0:
        break
    if end > idx:
        mapped[slot] = table[idx:end].decode("utf-8")
    idx = end + 1
    slot += 1
assert len(mapped) >= 400, len(mapped)
assert mapped.get(32) == " ", "VGA space slot 32 must be blank/space"
assert "\ufffd" in mapped.values(), "missing-glyph marker U+FFFD must be mapped"
# Every non-ASCII character in runtime scripts must have a glyph.
chars = set()
for path in list((root / "scripts").glob("paw-*")) + list((root / "boot").glob("*")):
    if path.suffix not in {".sh", ".py", ".service", ".mount", ".network"}:
        continue
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        continue
    chars.update(ch for ch in text if ord(ch) >= 0x80)
missing = sorted(ch for ch in chars if ch not in mapped.values())
assert not missing, f"missing glyphs: {''.join(missing)!r}"
# The fallback must be a 512-glyph 8x16 PSF1.
fb = fallback_path.read_bytes()
assert fb[:2] == b"\x36\x04" and fb[2] & 1 and fb[3] == 16, "fallback PSF1 header"
assert len(fb) == 4 + 512 * 16, len(fb)
print(f"PASS PSF2 16x16 512 glyphs, {len(mapped)} Unicode mappings, space slot 32")
print(f"PASS every non-ASCII runtime character is covered ({len(chars)} unique)")
print(f"PASS fallback PSF1 8x16 512 glyphs, {len(fb)} bytes")
PY
then rc=0; else rc=$?; fi
if ((rc == 0)); then
  pass 'PSF2/PSF1 headers, space slot, Unicode table and full runtime coverage'
else
  fail 'PSF font validation failed'
fi
printf 'Summary: %s passed, %s failed\n' "$passed" "$failed" >>"$report"
cat "$report"
((failed == 0))
