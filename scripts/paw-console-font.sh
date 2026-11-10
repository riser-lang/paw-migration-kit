#!/usr/bin/env bash
# Load the PAW Chinese console font on tty1.
#
# The release image carries two PSF fonts built from GNU Unifont:
#   * paw-cjk-16x16.psf  - primary, kernel framebuffer console (fbcon)
#   * paw-cjk-8x16.psf   - emergency fallback for vgacon (squashed CJK)
# The 16x16 font is the supported path; it keeps the existing tty1 fd and
# keyboard path untouched.  This unit runs before the PAWDATA panel/menu.
set -Eeuo pipefail
source "$(dirname "$0")/paw-lib.sh"

need setfont
need sha256sum
tty="${PAW_INTERACTIVE_TTY:-/dev/tty1}"
font_dir="${PAW_FONT_DIR:-$PAW_ROOT/fonts}"
report="$PAW_REPORT_DIR/console-font.json"
[[ -c "$tty" ]] || die "控制台字体：$tty 不是字符设备。"
[[ -d "$font_dir" ]] || die "控制台字体目录不存在：$font_dir"

primary="$font_dir/paw-cjk-16x16.psf"
fallback="$font_dir/paw-cjk-8x16.psf"
fb_name=""
fb_size=""
mode="vgacon-fallback"
font="$fallback"
if [[ -e /dev/fb0 ]]; then
  mode="fbcon"
  font="$primary"
  fb_name="$(cat /sys/class/graphics/fb0/name 2>/dev/null || true)"
  fb_size="$(cat /sys/class/graphics/fb0/virtual_size 2>/dev/null || true)"
fi
[[ -s "$font" ]] || die "控制台字体文件缺失：$font"

if command -v kbd_mode >/dev/null 2>&1; then
  kbd_mode -u -C "$tty" 2>/dev/null || log WARN "无法把 $tty 切到 UTF-8 键盘模式；仍尝试加载字体。"
fi

font_sha="$(sha256sum "$font" | awk '{print $1}')"
setfont_rc=0
# setfont writes its diagnostics to stderr.  Capture them so a rejected font
# is recorded in the report instead of only flashing on the console.
setfont_output="$(setfont -C "$tty" "$font" 2>&1)" || setfont_rc=$?
if ((setfont_rc != 0)); then
  log ERROR "setfont 加载失败（rc=$setfont_rc）：$font"
  printf '%s\n' "$setfont_output" >&2
  die "中文控制台字体未加载；拒绝在无字形的情况下继续菜单。"
fi

python3 - "$report" "$tty" "$mode" "$font" "$font_sha" "$fb_name" "$fb_size" "$setfont_rc" "$setfont_output" <<'PY' | python3 "$PAW_ROOT/scripts/paw-atomic-write.py" "$report"
import datetime, json, os, sys
path, tty, mode, font, font_sha, fb_name, fb_size, rc, output = sys.argv[1:]
doc = {
    "schema": "paw.console-font.v1",
    "generated_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "tty": tty,
    "mode": mode,
    "framebuffer": fb_name,
    "framebuffer_size": fb_size,
    "font": font,
    "font_size": os.path.getsize(font),
    "font_sha256": font_sha,
    "setfont_exit_code": int(rc),
    "setfont_output": output.strip(),
    "status": "PASS",
}
sys.stdout.write(json.dumps(doc, ensure_ascii=False, indent=2) + "\n")
PY

log INFO "控制台字体已加载：$mode $(basename "$font")（${fb_name:-vgacon} ${fb_size:-}），sha256=$font_sha。"
