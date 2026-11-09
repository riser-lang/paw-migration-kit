#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/paw-lib.sh"
src="${1:-}"; dst="${2:-}"; [[ -n "$src" && -n "$dst" ]] || die 'Usage: paw-stream-clone.sh SOURCE_DEVICE_OR_SIMULATION_FILE TARGET_DEVICE_OR_SIMULATION_FILE'
require_sim_or_enrollment; for c in zstd pv dd; do need "$c"; done
if [[ ${PAW_SIMULATION:-0} == 1 ]]; then [[ -f "$src" && -f "$dst" ]] || die 'Simulation requires regular image files.'; assert_sim_files "$src" "$dst"; else [[ -b "$src" && -b "$dst" ]] || die 'Real clone requires block devices.'; fi
[[ "$src" != "$dst" ]] || die 'Source and target are identical.'
[[ ${PAW_SIMULATION:-0} == 1 ]] || assert_unmounted "$dst"
if [[ ${PAW_SIMULATION:-0} != 1 ]]; then
  expected="$(sed -n 's/.*"serial"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$PAW_CONFIG_DIR/target-ssd.json")"
  expected_bytes="$(sed -n 's/.*"capacity_bytes"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$PAW_CONFIG_DIR/target-ssd.json")"
  actual="$(lsblk -dn -o SERIAL "$dst" | xargs)"; actual_bytes="$(lsblk -dnbo SIZE "$dst" | xargs)"
  [[ -n "$expected" && "$actual" == "$expected" ]] || die 'Target serial mismatch.'
  [[ -n "$expected_bytes" && "$actual_bytes" == "$expected_bytes" ]] || die 'Target capacity mismatch.'
fi
threads="${PAW_ZSTD_THREADS:-1}"; level="${PAW_ZSTD_LEVEL:-3}"; [[ "$threads" =~ ^[1-2]$ && "$level" =~ ^[1-5]$ ]] || die 'Unsafe zstd resource settings.'
mark_incomplete; trap 'rc=$?; if ((rc != 0)); then mark_incomplete; fi' EXIT
log INFO 'Clone starts; failures keep CLONE-INCOMPLETE.'; set -o pipefail
if [[ ${PAW_SIMULATION:-0} == 1 ]]; then
  dd if="$src" bs=4M iflag=fullblock status=progress 2>"$PAW_LOG_DIR/dd-read.log" | pv -ptebar | zstd -T"$threads" -"$level" | zstd -d -c | dd of="$dst" bs=4M conv=fsync status=progress 2>"$PAW_LOG_DIR/dd-write.log"
else
  configured_src="$(sed -n 's/.*"device_path"[[:space:]]*:[[:space:]]*"\([A-Za-z0-9/]*\)".*/\1/p' "$PAW_CONFIG_DIR/source.json")"
  [[ "$src" =~ ^/dev/[A-Za-z0-9/]+$ && "$src" == "$configured_src" ]] || die 'Source device does not match the enrolled source path.'
  source_mounts="$(rescue_ssh "lsblk -nrpo MOUNTPOINTS '$src'" | sed '/^$/d')"
  [[ -z "$source_mounts" ]] || die 'Source disk or partition is mounted in Rescue Mode.'
  source_uuid="$(sed -n 's/.*"root_uuid"[[:space:]]*:[[:space:]]*"\([0-9a-fA-F-]*\)".*/\1/p' "$PAW_CONFIG_DIR/source.json")"
  [[ "$source_uuid" =~ ^[0-9a-fA-F-]{36}$ ]] || die 'Expected source root UUID missing or malformed.'
  uuid_dev="$(rescue_ssh "blkid -t UUID='$source_uuid' -o device")"
  uuid_parent="$(rescue_ssh "lsblk -dn -o PKNAME '$uuid_dev'" | xargs)"
  [[ "$uuid_parent" == "${src##*/}" ]] || die 'Source root UUID is not on the enrolled source disk.'
  source_bytes="$(rescue_ssh "blockdev --getsize64 '$src'")"
  target_bytes="$(lsblk -dnbo SIZE "$dst" | xargs)"
  [[ "$source_bytes" =~ ^[0-9]+$ && "$target_bytes" =~ ^[0-9]+$ ]] || die 'Could not validate source/target sizes.'
  ((target_bytes >= source_bytes)) || die 'Target disk is smaller than source disk.'
  rescue_ssh "dd if='$src' bs=4M iflag=fullblock status=progress" 2>"$PAW_LOG_DIR/ssh-read.log" | pv -ptebar | zstd -T"$threads" -"$level" | zstd -d -c | dd of="$dst" bs=4M conv=fsync status=progress 2>"$PAW_LOG_DIR/dd-write.log"
fi
sync; rm -f "$PAW_REPORT_DIR/CLONE-INCOMPLETE"; log INFO 'Pipe completed; independent verify is mandatory.'
