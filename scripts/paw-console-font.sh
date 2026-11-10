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
setfont_rc=-1
setfont_output="not attempted"

mark_fail(){
  if [[ "$status" != FAIL ]]; then
    status="FAIL"
    reason="$1"
  fi
}

if [[ -e "$fb_device" ]]; then
  mode="fbcon"
  font="$primary"
  fb_name="$(cat "$fb_sysfs/name" 2>/dev/null || true)"
  fb_size="$(cat "$fb_sysfs/virtual_size" 2>/dev/null || true)"
  if [[ -d "$vt_sysfs" ]]; then
    for vt in "$vt_sysfs"/vtcon*; do
      [[ -e "$vt/name" && -e "$vt/bind" ]] || continue
      if [[ "$(cat "$vt/name" 2>/dev/null || true)" == "frame buffer device" \
            && "$(cat "$vt/bind" 2>/dev/null || true)" == "1" ]]; then
        fbcon_bound=true
        break
      fi
    done
  fi
  [[ "$fbcon_bound" == true ]] || mark_fail "存在 $fb_device，但没有已绑定的 fbcon；拒绝冒充 16x16 主路径。"
else
  # vgacon is an emergency diagnostic path only.  It must never produce PASS.
  status="WARN"
  reason="没有 /dev/fb0；使用 8x16 vgacon 回退，中文可能压缩，禁止磁盘写入。"
fi

if [[ ! -d "$font_dir" ]]; then
  mark_fail "控制台字体目录不存在：$font_dir"
elif [[ ! -s "$font" ]]; then
  mark_fail "控制台字体文件缺失或为空：$font"
elif [[ ! -r "$manifest" ]]; then
  mark_fail "控制台字体 manifest 缺失：$manifest"
else
  font_size="$(stat -c %s "$font" 2>/dev/null || printf '0')"
  font_sha="$(sha256sum "$font" 2>/dev/null | awk '{print $1}' || true)"
  if [[ ! "$font_size" =~ ^[0-9]+$ ]] || ((font_size <= 0)); then
    mark_fail "无法读取控制台字体大小：$font"
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
    mark_fail "控制台字体 manifest 无效或缺少对应 SHA256：$manifest"
  else
    IFS=$'\t' read -r manifest_schema manifest_cell expected_sha <<<"$manifest_values"
    if [[ ! "$font_sha" =~ ^[0-9a-f]{64}$ ]]; then
      mark_fail "无法计算控制台字体 SHA256：$font"
    elif [[ "$font_sha" != "$expected_sha" ]]; then
      mark_fail "控制台字体 SHA256 与构建 manifest 不一致：$font"
    fi
  fi
fi

if [[ ! -c "$tty" ]]; then
  mark_fail "控制台字体：$tty 不是字符设备。"
fi

if [[ "$status" != FAIL && -c "$tty" ]]; then
  if command -v kbd_mode >/dev/null 2>&1; then
    kbd_mode -u -C "$tty" 2>/dev/null || log WARN "无法把 $tty 切到 UTF-8 键盘模式；仍尝试加载字体。"
  fi
  setfont_rc=0
  # setfont writes its diagnostics to stderr.  Capture them so a rejected font
  # is recorded in the report instead of only flashing on the console.
  setfont_output="$(setfont -C "$tty" "$font" 2>&1)" || setfont_rc=$?
  if ((setfont_rc != 0)); then
    mark_fail "setfont 加载失败（rc=$setfont_rc）：$font"
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
  log ERROR "中文控制台字体未通过：$reason"
  printf '%s\n' "$setfont_output" >&2 || true
  exit 1
fi
if [[ "$status" == WARN ]]; then
  log WARN "中文控制台字体回退：$reason"
  exit 0
fi
log INFO "控制台字体已加载：$mode $(basename "$font")（${fb_name:-vgacon} ${fb_size:-}），sha256=$font_sha。"
