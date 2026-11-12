#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/paw-lib.sh"

src="${1:-}"; dst="${2:-}"
[[ -n "$src" && -n "$dst" ]] || die 'Usage: paw-stream-clone.sh SOURCE_DEVICE_OR_SIMULATION_FILE TARGET_DEVICE_OR_SIMULATION_FILE'
require_sim_or_enrollment
for c in zstd pv dd python3 sha256sum; do need "$c"; done

simulation="${PAW_SIMULATION:-0}"
network_simulation="${PAW_NETWORK_SIMULATION:-0}"
if [[ "$simulation" == 1 ]]; then
  [[ -f "$src" && -f "$dst" ]] || die 'Simulation requires regular image files.'
  assert_sim_files "$src" "$dst"
  source_bytes="$(stat -c %s "$src")"; target_bytes="$(stat -c %s "$dst")"
  if [[ "$network_simulation" == 1 ]]; then
    transport_kind='mock SSH byte stream; not a live network connection'
  else
    transport_kind='local pipe simulation; not SSH'
  fi
else
  [[ -b "$src" && -b "$dst" ]] || die 'Real clone requires block devices.'
  assert_unmounted "$dst"
  source_mode="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("source_mode", ""))' "$PAW_CONFIG_DIR/source.json")"
  [[ "$source_mode" == rescue ]] || die 'Source is not registered from Rescue Mode.'
  [[ -s "$PAW_REPORT_DIR/source-discovery.json" ]] || die 'Fresh Rescue Mode source discovery is required.'
  grep -q '"status"[[:space:]]*:[[:space:]]*"PASS"' "$PAW_REPORT_DIR/source-discovery.json" || die 'Rescue Mode source discovery is not PASS.'
  configured_src="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("device_path", ""))' "$PAW_CONFIG_DIR/source.json")"
  [[ "$src" =~ ^/dev/[A-Za-z0-9/]+$ && "$src" == "$configured_src" ]] || die 'Source device does not match the enrolled source path.'
  expected_bytes="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("capacity_bytes", ""))' "$PAW_CONFIG_DIR/target-ssd.json")"
  # Pre-write check includes the blank disk's partition fingerprint; after this
  # point the table is intentionally replaced and later gates use the hardware
  # hash only.
  python3 "$PAW_ROOT/scripts/paw-identity.py" verify --config "$PAW_CONFIG_DIR/target-ssd.json" \
    --device "$dst" --phase prewrite --check-unique >/dev/null 2>&1 \
    || die 'Target stable identity or pre-write partition fingerprint mismatch.'
  assert_authorization_for_target "$dst"
  target_bytes="$(blockdev --getsize64 "$dst")"
  assert_transaction_stage clone
  [[ "$expected_bytes" =~ ^[0-9]+$ && "$target_bytes" == "$expected_bytes" ]] || die 'Target capacity mismatch.'
  root_uuid="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("root_uuid", ""))' "$PAW_CONFIG_DIR/source.json")"
  [[ "$root_uuid" =~ ^[0-9a-fA-F-]{36}$ ]] || die 'Expected Rescue Mode root UUID missing or malformed.'
  uuid_dev="$(rescue_ssh "blkid -U '$root_uuid'")"
  uuid_parent="$(rescue_ssh "lsblk -dn -o PKNAME '$uuid_dev'" | xargs)"
  [[ "$uuid_parent" == "${src##*/}" ]] || die 'Source root UUID is not on the enrolled source disk.'
  source_bytes="$(rescue_ssh "blockdev --getsize64 '$src'")"
  [[ "$source_bytes" =~ ^[0-9]+$ ]] || die 'Could not validate Rescue Mode source capacity.'
  ((target_bytes >= source_bytes)) || die 'Target disk is smaller than source disk.'
  transport_kind='SSH stdout payload; excludes SSH/TCP framing overhead'
  transaction_event CLONE_STARTED
fi

[[ "$source_bytes" =~ ^[0-9]+$ && "$target_bytes" =~ ^[0-9]+$ ]] || die 'Could not validate source/target sizes.'
((target_bytes >= source_bytes)) || die 'Target is smaller than source.'

stream_mode='local-simulation-zstd'
compression_reason='local simulation only; does not measure SSH traffic'
if [[ "$network_simulation" == 1 || "$simulation" != 1 ]]; then
  remote_tools="$(rescue_ssh 'if command -v zstd >/dev/null 2>&1 && command -v bash >/dev/null 2>&1; then echo ZSTD_AVAILABLE; else echo ZSTD_UNAVAILABLE; fi')"
  remote_mem_kb="$(rescue_ssh 'cat /proc/meminfo' | awk '/^MemAvailable:/ {print $2; exit}')"
  if [[ "$remote_tools" == *ZSTD_AVAILABLE* && "$remote_mem_kb" =~ ^[0-9]+$ ]] && ((remote_mem_kb >= 262144)); then
    stream_mode='remote-zstd-level1-thread1'
    compression_reason='remote zstd and bash available; at least 256 MiB reported available'
  elif [[ "$remote_tools" == *ZSTD_AVAILABLE* ]]; then
    stream_mode='raw-fallback'
    compression_reason='remote available memory is below 256 MiB or could not be verified; compression not used'
  else
    stream_mode='raw-fallback'
    compression_reason='remote zstd or bash missing; compression not used'
  fi
  if [[ "$network_simulation" == 1 ]]; then transport_kind='mock SSH byte stream; not a live network connection'; fi
fi

payload_count="$PAW_LOG_DIR/ssh-payload-bytes.pending"
restored_count="$PAW_LOG_DIR/restored-bytes.pending"
progress_log="$PAW_LOG_DIR/ssh-transfer-progress.log"
rm -f "$payload_count" "$restored_count" "$progress_log" "$PAW_REPORT_DIR/stream-transfer-report.json" "$PAW_REPORT_DIR/stream-verify.json"
mark_incomplete
trap 'rc=$?; if ((rc != 0)); then mark_incomplete; if [[ "$simulation" != 1 ]]; then transaction_event CLONE_INCOMPLETE || true; fi; log ERROR "clone stream exit=$rc; incomplete marker retained"; fi' EXIT
log INFO "Clone stream starts; mode=$stream_mode. Failed writes keep CLONE-INCOMPLETE."
set -o pipefail

if [[ "$stream_mode" == local-simulation-zstd ]]; then
  dd if="$src" bs=4M iflag=fullblock status=none \
    | zstd -T1 -1 -c \
    | pv -ptebar 2>>"$progress_log" \
    | python3 "$PAW_ROOT/scripts/paw-count-bytes.py" --count-file "$payload_count" \
    | zstd -d -c \
    | python3 "$PAW_ROOT/scripts/paw-count-bytes.py" --count-file "$restored_count" \
    | dd of="$dst" bs=4M conv=notrunc,fsync status=none
elif [[ "$stream_mode" == remote-zstd-level1-thread1 ]]; then
  rescue_ssh "bash -o pipefail -c 'dd if='$src' bs=4M iflag=fullblock status=none | zstd -T1 -1 -c'" \
    | pv -ptebar 2>>"$progress_log" \
    | python3 "$PAW_ROOT/scripts/paw-count-bytes.py" --count-file "$payload_count" \
    | zstd -d -c \
    | python3 "$PAW_ROOT/scripts/paw-count-bytes.py" --count-file "$restored_count" \
    | dd of="$dst" bs=4M conv=fsync status=none
elif [[ "$stream_mode" == raw-fallback ]]; then
  rescue_ssh "dd if='$src' bs=4M iflag=fullblock status=none" \
    | pv -s "$source_bytes" -ptebar 2>>"$progress_log" \
    | python3 "$PAW_ROOT/scripts/paw-count-bytes.py" --count-file "$payload_count" \
    | python3 "$PAW_ROOT/scripts/paw-count-bytes.py" --count-file "$restored_count" \
    | dd of="$dst" bs=4M conv=fsync status=none
else
  die 'Unsupported transfer mode.'
fi

[[ -s "$payload_count" ]] || die 'SSH stream byte counter did not produce a complete count.'
[[ -s "$restored_count" ]] || die 'Restored byte counter did not produce a complete count.'
ssh_stream_bytes="$(cat "$payload_count")"; restored_bytes="$(cat "$restored_count")"
rm -f "$payload_count" "$restored_count"
[[ "$ssh_stream_bytes" =~ ^[0-9]+$ ]] || die 'SSH stream byte count is malformed.'
[[ "$restored_bytes" =~ ^[0-9]+$ ]] || die 'Restored byte count is malformed.'
((restored_bytes == source_bytes)) || die "Restored byte count ${restored_bytes} does not match source ${source_bytes}; CLONE-INCOMPLETE remains."
python3 - "$PAW_REPORT_DIR/stream-transfer-report.json" "$source_bytes" "$ssh_stream_bytes" "$restored_bytes" "$stream_mode" "$transport_kind" "$compression_reason" <<'PY'
import json,sys
out,src,wire,restored,mode,transport,reason=sys.argv[1:]
s=int(src); w=int(wire); r=int(restored)
json.dump({"status":"STREAM_COMPLETE_UNVERIFIED","source_bytes":s,"ssh_stream_bytes":w,
 "restored_bytes":r,"stream_mode":mode,"transport":transport,"compression_reason":reason,
 "byte_count_streams_complete":True,
 "transfer_to_source_ratio":(w/s if s else None),
 "compression_reduction_percent":(100*(s-w)/s if s else None),
 "sha256":None,"independent_sha256_verified":False},open(out,"w"),indent=2)
PY
if [[ "$simulation" != 1 ]]; then
  transaction_event CLONE_INCOMPLETE
fi
log INFO "Stream complete; source_bytes=$source_bytes ssh_stream_bytes=$ssh_stream_bytes restored_bytes=$restored_bytes mode=$stream_mode. Independent SHA256 verification is still required."
