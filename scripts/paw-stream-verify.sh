#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/paw-lib.sh"
src="${1:-}"; dst="${2:-}"; [[ -n "$src" && -n "$dst" ]] || die 'Usage: paw-stream-verify.sh SOURCE_DEVICE_OR_SIMULATION_FILE TARGET'
[[ ! -e "$PAW_REPORT_DIR/CLONE-INCOMPLETE" ]] || die 'Clone marked incomplete.'; need sha256sum
if [[ ${PAW_SIMULATION:-0} == 1 ]]; then
  assert_sim_files "$src" "$dst"
  source_bytes="$(stat -c %s "$src")"
  a="$(sha256sum "$src" | awk '{print $1}')"
else
  require_target_enrollment; assert_registered_target_device "$dst"
  configured_src="$(sed -n 's/.*"device_path"[[:space:]]*:[[:space:]]*"\([A-Za-z0-9/]*\)".*/\1/p' "$PAW_CONFIG_DIR/source.json")"
  [[ "$src" =~ ^/dev/[A-Za-z0-9/]+$ && "$src" == "$configured_src" ]] || die 'Source device does not match the enrolled source path.'
  source_bytes="$(rescue_ssh "blockdev --getsize64 '$src'")"
  [[ "$source_bytes" =~ ^[0-9]+$ ]] || die 'Could not validate source size for verification.'
  a="$(rescue_ssh "dd if='$src' bs=4M iflag=fullblock status=progress" 2>"$PAW_LOG_DIR/ssh-verify.log" | head -c "$source_bytes" | sha256sum | awk '{print $1}')"
fi
b="$(head -c "$source_bytes" "$dst" | sha256sum | awk '{print $1}')"; [[ "$a" == "$b" ]] || die 'SHA256 mismatch over source-sized byte range.'
printf '{"status":"PASS","sha256":"%s","verified_at":"%s"}\n' "$a" "$(date -u +%FT%TZ)" >"$PAW_REPORT_DIR/stream-verify.json"; log INFO 'SHA256 verification passed.'
