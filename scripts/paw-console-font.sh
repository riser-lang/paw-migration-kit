#!/usr/bin/env bash
# Load the PAW Chinese console font on tty1.
#
# The release image carries two PSF fonts built from GNU Unifont:
#   * paw-cjk-16x16.psf  - primary, kernel framebuffer console (fbcon)
#   * paw-cjk-8x16.psf   - emergency fallback for vgacon (squashed CJK)
# Only the 16x16 font on a bound fbcon may report PASS.  The 8x16 fallback is
# recorded as WARN and the destructive write gate refuses it.  A missing or
# corrupt font, a manifest/hash mismatch, a missing tty, or a setfont failure is
# recorded as FAIL before the script exits non-zero.
set -Eeuo pipefail
source "$(dirname "$0")/paw-lib.sh"

need python3
need sha256sum
tty="${PAW_INTERACTIVE_TTY:-/dev/tty1}"
font_dir="${PAW_FONT_DIR:-$PAW_ROOT/fonts}"
manifest="${PAW_FONT_MANIFEST:-$font_dir/paw-cjk-font.json}"
report="${PAW_CONSOLE_FONT_REPORT:-$PAW_REPORT_DIR/console-font.json}"
fb_device="${PAW_FBCON_DEVICE:-/dev/fb0}"
fb_sysfs="${PAW_FB_SYSFS_DIR:-/sys/class/graphics/fb0}"
vt_sysfs="${PAW_VTCONSOLE_DIR:-/sys/class/vtconsole}"

primary="$font_dir/paw-cjk-16x16.psf"
fallback="$font_dir/paw-cjk-8x16.psf"
fb_name=""
fb_size=""
fbcon_bound=false
mode="vgacon-fallback"
font="$fallback"
status="PASS"
reason=""
font_size=0
font_sha=""
expected_sha=""
manifest_schema=""
manifest_cell=""
font_loadable=false
setfont_rc=-1
setfont_output="not attempted"
wait_seconds="${PAW_FONT_WAIT_SECONDS:-30}"
if [[ ! "$wait_seconds" =~ ^[0-9]+$ ]]; then
  wait_seconds=30
fi
deadline=$((SECONDS + wait_seconds))

mark_fail(){
  if [[ "$status" != FAIL ]]; then
    status="FAIL"
    reason="$1"
  fi
}

# The DRM/fbcon driver can bind a little after udev-settle.  Wait briefly for
# the framebuffer and for fbcon to bind before deciding this is vgacon; a
# premature fallback would load the squashed 8x16 font and leave Chinese as
# boxes on a perfectly capable framebuffer console.
while [[ ! -e "$fb_device" && "$SECONDS" -lt "$deadline" ]]; do
  sleep 0.2
done

if [[ -e "$fb_device" ]]; then
  mode="fbcon"
  font="$primary"
  if [[ -d "$vt_sysfs" ]]; then
    while [[ "$SECONDS" -lt "$deadline" ]]; do
      fbcon_bound=false
      for vt in "$vt_sysfs"/vtcon*; do
        [[ -e "$vt/name" && -e "$vt/bind" ]] || continue
        # /sys/class/vtconsole/vtconN/name is "(M) frame buffer device" or
        # "(S) frame buffer device" on current kernels; match the suffix, not
        # the whole line, or a bound fbcon is misread as vgacon.
        if [[ "$(cat "$vt/name" 2>/dev/null || true)" == *"frame buffer device"* \
              && "$(cat "$vt/bind" 2>/dev/null || true)" == "1" ]]; then
          fbcon_bound=true
          break
        fi
      done
      [[ "$fbcon_bound" == true ]] && break
      sleep 0.2
    done
  fi
  fb_name="$(cat "$fb_sysfs/name" 2>/dev/null || true)"
  fb_size="$(cat "$fb_sysfs/virtual_size" 2>/dev/null || true)"
  [[ "$fbcon_bound" == true ]] || mark_fail "$fb_device exists but fbcon is not bound; refusing to claim the 16x16 primary path."
else
  # vgacon is an emergency diagnostic path only.  It must never produce PASS.
  status="WARN"
  reason="No /dev/fb0; using the 8x16 vgacon fallback. Chinese may be compressed and disk writes stay blocked."
fi

if [[ ! -d "$font_dir" ]]; then
  mark_fail "Console font directory is missing: $font_dir"
elif [[ ! -s "$font" ]]; then
  mark_fail "Console font file is missing or empty: $font"
elif [[ ! -r "$manifest" ]]; then
  mark_fail "Console font manifest is missing: $manifest"
else
  font_size="$(stat -c %s "$font" 2>/dev/null || printf '0')"
  font_sha="$(sha256sum "$font" 2>/dev/null | awk '{print $1}' || true)"
  if [[ ! "$font_size" =~ ^[0-9]+$ ]] || ((font_size <= 0)); then
    mark_fail "Cannot read console font size: $font"
  elif ! manifest_values="$(python3 - "$manifest" "$mode" <<'PY'
import json, re, sys
path, mode = sys.argv[1:]
with open(path, encoding="utf-8") as handle:
    data = json.load(handle)
if data.get("schema") != "paw.cjk-console-font.v1":
    raise SystemExit("manifest schema")
if data.get("cell") != "16x16":
    raise SystemExit("manifest cell")
key = "primary_font_sha256" if mode == "fbcon" else "fallback_font_sha256"
value = str(data.get(key) or "")
if not re.fullmatch(r"[0-9a-f]{64}", value):
    raise SystemExit("manifest hash")
print(data["schema"], data["cell"], value, sep="\t")
PY
  )"; then
    mark_fail "Console font manifest is invalid or lacks the matching SHA256: $manifest"
  else
    IFS=$'\t' read -r manifest_schema manifest_cell expected_sha <<<"$manifest_values"
    if [[ ! "$font_sha" =~ ^[0-9a-f]{64}$ ]]; then
      mark_fail "Cannot compute console font SHA256: $font"
    elif [[ "$font_sha" != "$expected_sha" ]]; then
      mark_fail "Console font SHA256 does not match the build manifest: $font"
    else
      font_loadable=true
    fi
  fi
fi

while [[ ! -c "$tty" && "$SECONDS" -lt "$deadline" ]]; do
  sleep 0.2
done
if [[ ! -c "$tty" ]]; then
  mark_fail "Console font target $tty is not a character device."
fi

# Load the font even when fbcon is not bound yet (or the fallback is selected):
# the screen must not stay on the VGA font.  The report status remains WARN or
# FAIL, so this cannot open the destructive write gate.
if [[ "$font_loadable" == true && -c "$tty" ]]; then
  if command -v kbd_mode >/dev/null 2>&1; then
    kbd_mode -u -C "$tty" 2>/dev/null || log WARN "Cannot switch $tty to UTF-8 keyboard mode; still trying to load the font."
  fi
  setfont_rc=0
  # setfont writes its diagnostics to stderr.  Capture them so a rejected font
  # is recorded in the report instead of only flashing on the console.
  setfont_output="$(setfont -C "$tty" "$font" 2>&1)" || setfont_rc=$?
  if ((setfont_rc != 0)); then
    mark_fail "setfont failed (rc=$setfont_rc): $font"
  fi
fi

boot_id="$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || true)"
python3 - "$report" "$tty" "$mode" "$font" "$font_size" "$font_sha" \
  "$manifest" "$expected_sha" "$manifest_schema" "$setfont_rc" "$setfont_output" \
  "$status" "$reason" "$boot_id" "$fb_name" "$fb_size" "$fbcon_bound" <<'PY' \
  | python3 "$PAW_ROOT/scripts/paw-atomic-write.py" "$report"
import datetime, json, os, sys
(path, tty, mode, font, font_size, font_sha, manifest, expected_sha,
 manifest_schema, setfont_rc, setfont_output, status, reason, boot_id,
 fb_name, fb_size, fbcon_bound) = sys.argv[1:]
document = {
    "schema": "paw.console-font.v2",
    "generated_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "boot_id": boot_id,
    "tty": tty,
    "mode": mode,
    "fbcon_bound": fbcon_bound == "true",
    "framebuffer": fb_name,
    "framebuffer_size": fb_size,
    "font": font,
    "font_size": int(font_size or 0),
    "font_sha256": font_sha,
    "font_manifest": manifest,
    "manifest_schema": manifest_schema,
    "expected_font_sha256": expected_sha,
    "setfont_exit_code": int(setfont_rc),
    "setfont_output": setfont_output.strip(),
    "status": status,
    "reason": reason,
}
sys.stdout.write(json.dumps(document, ensure_ascii=False, indent=2) + "\n")
PY

if [[ "$status" == FAIL ]]; then
  log ERROR "Chinese console font did not pass: $reason"
  printf '%s\n' "$setfont_output" >&2 || true
  exit 1
fi
if [[ "$status" == WARN ]]; then
  log WARN "Chinese console font fallback: $reason"
  exit 0
fi
log INFO "Console font loaded: $mode $(basename "$font") (${fb_name:-vgacon} ${fb_size:-}), sha256=$font_sha."
