#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/paw-lib.sh"
src="${1:-}"; dst="${2:-}"
[[ -n "$src" && -n "$dst" ]] || die 'Usage: paw-stream-verify.sh SOURCE_DEVICE_OR_SIMULATION_FILE TARGET'
need sha256sum; need python3
[[ -s "$PAW_REPORT_DIR/stream-transfer-report.json" ]] || die 'No completed stream receipt.'
grep -q '"status"[[:space:]]*:[[:space:]]*"STREAM_COMPLETE_UNVERIFIED"' "$PAW_REPORT_DIR/stream-transfer-report.json" || die 'Stream receipt is not awaiting verification.'

if [[ ${PAW_SIMULATION:-0} == 1 ]]; then
  assert_sim_files "$src" "$dst"
  source_bytes="$(stat -c %s "$src")"
  target_bytes="$(stat -c %s "$dst")"
  a="$(sha256sum "$src" | awk '{print $1}')"
else
  [[ -b "$src" && -b "$dst" ]] || die 'Verification requires block devices.'
  require_target_enrollment; assert_registered_target_device "$dst"
  assert_authorization_for_target "$dst"
  configured_src="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("device_path", ""))' "$PAW_CONFIG_DIR/source.json")"
  [[ "$src" =~ ^/dev/[A-Za-z0-9/]+$ && "$src" == "$configured_src" ]] || die 'Source device does not match the enrolled source path.'
  source_bytes="$(rescue_ssh "blockdev --getsize64 '$src'")"
  target_bytes="$(blockdev --getsize64 "$dst")"
  a="$(rescue_ssh "sha256sum '$src' | awk '{print \$1}'")"
fi

[[ "$source_bytes" =~ ^[0-9]+$ && "$target_bytes" =~ ^[0-9]+$ ]] || die 'Could not validate source/target size for verification.'
((target_bytes >= source_bytes)) || die 'Target is smaller than the source byte range.'
python3 - "$PAW_REPORT_DIR/stream-transfer-report.json" "$source_bytes" <<'PY' || die 'Stream receipt byte counts are incomplete or inconsistent.'
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
assert d.get("status")=="STREAM_COMPLETE_UNVERIFIED"
assert d.get("byte_count_streams_complete") is True
assert d.get("source_bytes")==int(sys.argv[2])
assert d.get("restored_bytes")==int(sys.argv[2])
PY
b="$(head -c "$source_bytes" "$dst" | sha256sum | awk '{print $1}')"
[[ "$a" =~ ^[0-9a-f]{64}$ && "$a" == "$b" ]] || die 'Independent SHA256 mismatch; CLONE-INCOMPLETE remains set.'

python3 - "$PAW_REPORT_DIR/stream-verify.json" "$PAW_REPORT_DIR/stream-transfer-report.json" "$a" "$source_bytes" <<'PY'
import json,sys
verify_path,transfer_path,digest,size=sys.argv[1:]
with open(transfer_path,encoding="utf-8") as handle:
    transfer=json.load(handle)
if transfer.get("status") != "STREAM_COMPLETE_UNVERIFIED" or transfer.get("source_bytes") != int(size):
    raise SystemExit("Stream receipt does not match the verified source range.")
transfer.update({"status":"PASS","sha256":digest,"independent_sha256_verified":True})
with open(transfer_path,"w",encoding="utf-8") as handle:
    json.dump(transfer,handle,indent=2)
with open(verify_path,"w",encoding="utf-8") as handle:
    json.dump({"status":"PASS","sha256":digest,"bytes_verified":int(size),"independent_sha256_verified":True,"verified_at":__import__("datetime").datetime.now(__import__("datetime").timezone.utc).isoformat()},handle,indent=2)
PY
rm -f "$PAW_REPORT_DIR/CLONE-INCOMPLETE"
log INFO 'Independent SHA256 verification passed; incomplete marker cleared.'
