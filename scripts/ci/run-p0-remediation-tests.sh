#!/usr/bin/env bash
set -Eeuo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
work="${PAW_P0_TEST_DIR:-$root/tests/virtual/p0-remediation}"
out="${PAW_ARTIFACT_DIR:-$PWD/artifacts}"
report="$out/p0-remediation-report.txt"
rm -rf "$work"; mkdir -p "$work" "$out"
passed=0; failed=0
pass(){ printf 'PASS %s\n' "$1" | tee -a "$report"; passed=$((passed+1)); }
fail(){ printf 'FAIL %s\n' "$1" | tee -a "$report"; failed=$((failed+1)); }
printf 'PAW P0 remediation tests\nExecuted: %s\n' "$(date -u +%FT%TZ)" >"$report"

# P0-1: ISOLINUX must use the Linux loader.  `kernel` with a bzImage binary
# was observed selecting the entry and leaving a black screen.
cfg="$root/configs/live-build/bootloaders/isolinux/memtest.cfg"
if grep -Eq '^[[:space:]]*linux[[:space:]]+/boot/memtest86\+x64\.bin' "$cfg" && ! grep -Eq '^[[:space:]]*kernel[[:space:]]' "$cfg"; then
  pass 'P0-1 memtest.cfg uses linux (not kernel) for the bzImage'
else
  fail 'P0-1 memtest.cfg still uses kernel'
fi
pinned="$root/configs/memtest86+/memtest86+x64.bin"
expected_sha='487bfe56b84f2016b12f393641f1acb765ef0b648c71ea9a2e3d42b62411f71f'
if [[ -s "$pinned" ]] && [[ "$(sha256sum "$pinned" | awk '{print $1}')" == "$expected_sha" ]]; then
  pass 'P0-1 pinned Memtest86+ binary SHA256 matches v7.20'
else
  fail 'P0-1 pinned Memtest86+ binary missing or hash mismatch'
fi
if strings "$pinned" 2>/dev/null | grep -q 'Memtest86+ v7.20'; then
  pass 'P0-1 pinned binary embeds version 7.20'
else
  fail 'P0-1 pinned binary version marker missing'
fi

# P0-2: the clone script must assert the transaction (and therefore expiry)
# before it can create the incomplete marker or open the target for writing.
clone_assert_line="$(grep -n 'assert_transaction_stage clone' "$root/scripts/paw-stream-clone.sh" | head -n1 | cut -d: -f1)"
clone_marker_line="$(grep -n 'mark_incomplete;' "$root/scripts/paw-stream-clone.sh" | head -n1 | cut -d: -f1)"
clone_dd_line="$(grep -n 'dd if=' "$root/scripts/paw-stream-clone.sh" | head -n1 | cut -d: -f1)"
if [[ -n "$clone_assert_line" && -n "$clone_marker_line" && -n "$clone_dd_line" ]] && (( clone_assert_line < clone_marker_line && clone_assert_line < clone_dd_line )); then
  pass 'P0-2 clone asserts authorization/transaction before marker or target write'
else
  fail 'P0-2 clone can write before transaction assertion'
fi

# P0-2: transaction state machine, including expiry-at-start only.
txdir="$work/transaction"; mkdir -p "$txdir/reports" "$txdir/configs"
cat >"$txdir/configs/source.json" <<'JSON'
{"source_mode":"rescue","device_path":"/dev/sda","root_uuid":"11111111-2222-3333-4444-555555555555","model":"SIM-SOURCE","serial":"SRC123","capacity_bytes":53687091200,"composite_identity_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","ssh_host_key_fingerprint":"SHA256:test"}
JSON
cat >"$txdir/configs/target-ssd.json" <<'JSON'
{"approved":true,"device_path":"/dev/sdb","model":"SIM-TARGET","serial":"TGT-SERIAL-999999","capacity_bytes":240000000000}
JSON
now='2026-11-11T00:00:00+00:00'; expires='2026-11-11T06:00:00+00:00'
cat >"$txdir/reports/operator-authorization.json" <<JSON
{"status":"AUTHORIZED","migration_id":"11111111-1111-1111-1111-111111111111","authorization_id":"22222222-2222-2222-2222-222222222222","target_device":"/dev/sdb","target_serial":"TGT-SERIAL-999999","source_composite_identity_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","authorized_at":"$now","expires_at":"$expires"}
JSON
tx="$txdir/reports/migration-transaction.json"
run_tx(){ python3 "$root/scripts/paw-transaction.py" "$@"; }
run_tx init --transaction "$tx" --authorization "$txdir/reports/operator-authorization.json" --source-config "$txdir/configs/source.json" --target-config "$txdir/configs/target-ssd.json" --now "$now" >/dev/null 2>"$txdir/init.err" \
  && pass 'P0-2 transaction initialized in AUTHORIZED' || fail "P0-2 init failed: $(cat "$txdir/init.err")"
if run_tx assert --transaction "$tx" --authorization "$txdir/reports/operator-authorization.json" --source-config "$txdir/configs/source.json" --target-config "$txdir/configs/target-ssd.json" --stage clone --now '2026-11-11T06:00:01+00:00' >"$txdir/expired.out" 2>"$txdir/expired.err"; then
  fail 'P0-2 expired authorization still started a clone'
else
  grep -q 'AUTHORIZATION_EXPIRED_BEFORE_CLONE' "$txdir/expired.err" && pass 'P0-2 six-hour expiry blocks clone start' || fail 'P0-2 expiry failed with wrong reason'
fi
run_tx assert --transaction "$tx" --authorization "$txdir/reports/operator-authorization.json" --source-config "$txdir/configs/source.json" --target-config "$txdir/configs/target-ssd.json" --stage clone --now "$now" >/dev/null \
  && pass 'P0-2 unexpired clone start allowed' || fail 'P0-2 unexpired clone start rejected'
run_tx event --transaction "$tx" --event CLONE_STARTED --now "$now" >/dev/null \
  && pass 'P0-2 CLONE_STARTED recorded' || fail 'P0-2 CLONE_STARTED failed'
run_tx assert --transaction "$tx" --authorization "$txdir/reports/operator-authorization.json" --source-config "$txdir/configs/source.json" --target-config "$txdir/configs/target-ssd.json" --stage clone-verify --now '2026-11-12T12:00:00+00:00' >"$txdir/late-verify.out" 2>"$txdir/late-verify.err" \
  && pass 'P0-2 verify after 6h+ is allowed (expiry not applied post-clone)' || fail "P0-2 verify after expiry blocked: $(cat "$txdir/late-verify.err")"
grep -q '"expiry_enforced":false' "$txdir/late-verify.out" && pass 'P0-2 post-clone assert reports expiry_enforced=false' || fail 'P0-2 expiry flag wrong'
run_tx event --transaction "$tx" --event CLONE_INCOMPLETE --now '2026-11-11T00:10:00+00:00' >/dev/null \
  && pass 'P0-2 interrupted clone retained as CLONE_INCOMPLETE' || fail 'P0-2 CLONE_INCOMPLETE failed'
run_tx event --transaction "$tx" --event CLONE_VERIFIED --sha256 "$(printf 'b%.0s' {1..64})" --bytes-verified 53687091200 --now '2026-11-12T12:00:00+00:00' >/dev/null \
  && pass 'P0-2 CLONE_VERIFIED recorded after late verification' || fail 'P0-2 CLONE_VERIFIED failed'
if run_tx assert --transaction "$tx" --authorization "$txdir/reports/operator-authorization.json" --source-config "$txdir/configs/source.json" --target-config "$txdir/configs/target-ssd.json" --stage clone --now '2026-11-12T12:01:00+00:00' >/dev/null 2>"$txdir/dup.err"; then
  fail 'P0-2 duplicate clone start allowed'
else
  grep -q 'STATE_NOT_ALLOWED' "$txdir/dup.err" && pass 'P0-2 duplicate clone start rejected after verification' || fail 'P0-2 duplicate clone failed with wrong reason'
fi
cat >"$txdir/reports/stream-verify.json" <<JSON
{"status":"PASS","sha256":"$(printf 'b%.0s' {1..64})","bytes_verified":53687091200,"independent_sha256_verified":true}
JSON
run_tx assert --transaction "$tx" --authorization "$txdir/reports/operator-authorization.json" --source-config "$txdir/configs/source.json" --target-config "$txdir/configs/target-ssd.json" --stream-verify "$txdir/reports/stream-verify.json" --stage repair --now '2026-11-12T12:02:00+00:00' >/dev/null \
  && pass 'P0-2 repair allowed from CLONE_VERIFIED with matching independent hash' || fail 'P0-2 repair transition rejected'
run_tx event --transaction "$tx" --event REPAIR_STARTED --now '2026-11-12T12:02:00+00:00' >/dev/null
run_tx event --transaction "$tx" --event REPAIRED --now '2026-11-12T12:03:00+00:00' >/dev/null
run_tx assert --transaction "$tx" --authorization "$txdir/reports/operator-authorization.json" --source-config "$txdir/configs/source.json" --target-config "$txdir/configs/target-ssd.json" --stream-verify "$txdir/reports/stream-verify.json" --stage expand --now '2026-11-12T12:04:00+00:00' >/dev/null \
  && pass 'P0-2 expansion allowed from REPAIRED' || fail 'P0-2 expansion transition rejected'
run_tx event --transaction "$tx" --event EXPAND_STARTED --now '2026-11-12T12:04:00+00:00' >/dev/null
run_tx event --transaction "$tx" --event READY_TO_BOOT --now '2026-11-12T12:05:00+00:00' >/dev/null
run_tx assert --transaction "$tx" --authorization "$txdir/reports/operator-authorization.json" --source-config "$txdir/configs/source.json" --target-config "$txdir/configs/target-ssd.json" --stream-verify "$txdir/reports/stream-verify.json" --stage finalize --now '2026-11-12T12:06:00+00:00' >/dev/null \
  && pass 'P0-2 finalizer gate allowed from READY_TO_BOOT' || fail 'P0-2 finalizer gate rejected'
run_tx event --transaction "$tx" --event COMPLETE --now '2026-11-12T12:07:00+00:00' >/dev/null \
  && pass 'P0-2 COMPLETE only after READY_TO_BOOT' || fail 'P0-2 COMPLETE transition failed'
# Target mutation after authorization must fail closed.
python3 - "$txdir/configs/target-ssd.json" <<'PY'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); d["serial"]="OTHER-SERIAL"; json.dump(d,open(p,"w"))
PY
if run_tx assert --transaction "$tx" --authorization "$txdir/reports/operator-authorization.json" --source-config "$txdir/configs/source.json" --target-config "$txdir/configs/target-ssd.json" --stage finalize --now '2026-11-12T12:07:00+00:00' >/dev/null 2>"$txdir/changed.err"; then
  fail 'P0-2 changed target accepted'
else
  grep -q 'TARGET_CHANGED' "$txdir/changed.err" && pass 'P0-2 target identity change blocks finalizer' || fail 'P0-2 target change wrong reason'
fi
# Old authorization reuse cannot reset a terminal/active transaction.
python3 - "$txdir/configs/target-ssd.json" <<'PY'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); d["serial"]="TGT-SERIAL-999999"; json.dump(d,open(p,"w"))
PY
python3 - "$txdir/reports/operator-authorization.json" <<'PY'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); d["authorization_id"]="33333333-3333-3333-3333-333333333333"; d["migration_id"]="44444444-4444-4444-4444-444444444444"; json.dump(d,open(p,"w"))
PY
if run_tx init --transaction "$tx" --authorization "$txdir/reports/operator-authorization.json" --source-config "$txdir/configs/source.json" --target-config "$txdir/configs/target-ssd.json" --now "$now" >/dev/null 2>"$txdir/reuse.err"; then
  fail 'P0-2 old authorization reuse accepted'
else
  grep -q 'TRANSACTION_EXISTS' "$txdir/reuse.err" && pass 'P0-2 old authorization cannot restart a transaction' || fail 'P0-2 authorization reuse wrong reason'
fi

# P0-3: fail-closed source mount checker.
checker="$root/scripts/paw-source-mount-check.py"
rootdev="$(findmnt -n -o SOURCE / | head -n1)"
if [[ -b "$rootdev" ]] && python3 "$checker" "$rootdev" >"$txdir/mount-rw.json" 2>"$txdir/mount-rw.err"; then
  fail 'P0-3 read-write root mount passed'
else
  grep -q 'READ_WRITE_MOUNT' "$txdir/mount-rw.json" && pass 'P0-3 read-write source mount blocked' || fail 'P0-3 read-write mount wrong reason'
fi
if python3 "$checker" --findmnt /nonexistent "$rootdev" >"$txdir/mount-nofm.json" 2>/dev/null; then
  fail 'P0-3 missing findmnt passed'
else
  grep -q 'FINDMNT_MISSING' "$txdir/mount-nofm.json" && pass 'P0-3 missing findmnt blocked' || fail 'P0-3 missing findmnt wrong reason'
fi
printf 'not a mountinfo line\n' >"$txdir/bad.mountinfo"
if python3 "$checker" --mountinfo "$txdir/bad.mountinfo" "$rootdev" >"$txdir/mount-bad.json" 2>/dev/null; then
  fail 'P0-3 malformed mountinfo passed'
else
  grep -Eq 'MOUNTINFO_MALFORMED|MOUNTINFO_UNREADABLE' "$txdir/mount-bad.json" && pass 'P0-3 malformed mountinfo blocked' || fail 'P0-3 malformed mountinfo wrong reason'
fi
if grep -Eq 'rescue_ssh.*findmnt.*\|\| true' "$root/scripts/paw-source-discovery.sh"; then
  fail 'P0-3 source discovery still swallows findmnt errors'
else
  pass 'P0-3 source discovery no longer swallows findmnt errors'
fi

# A read-only mount is safe; the checker must still prove findmnt ran.
cat >"$txdir/fake-findmnt" <<'FM'
#!/bin/sh
if [ "$1" = "--version" ]; then echo "findmnt fake 1"; exit 0; fi
exit 1
FM
chmod 0755 "$txdir/fake-findmnt"
# Match the checker exactly: st_rdev is the authoritative number, while the
# textual %t/%T form is hexadecimal and has bitten this fixture before.
rootmaj="$(python3 -c 'import os,sys;print(os.major(os.stat(sys.argv[1]).st_rdev))' "$rootdev")"
rootmin="$(python3 -c 'import os,sys;print(os.minor(os.stat(sys.argv[1]).st_rdev))' "$rootdev")"
printf '1 0 %s:%s / /mnt/fake ro,relatime - ext4 /dev/fake ro\n' "$rootmaj" "$rootmin" >"$txdir/ro.mountinfo"
if python3 "$checker" --mountinfo "$txdir/ro.mountinfo" --findmnt "$txdir/fake-findmnt" "$rootdev" >"$txdir/mount-ro.json" 2>/dev/null; then
  pass 'P0-3 read-only mount at an alternate mountpoint passes'
else
  fail "P0-3 read-only mount rejected: $(cat "$txdir/mount-ro.json")"
fi
printf '1 0 %s:%s / /mnt/fake rw,relatime - ext4 /dev/fake rw\n' "$rootmaj" "$rootmin" >"$txdir/rw-alt.mountinfo"
if python3 "$checker" --mountinfo "$txdir/rw-alt.mountinfo" --findmnt "$txdir/fake-findmnt" "$rootdev" >"$txdir/mount-rw-alt.json" 2>/dev/null; then
  fail 'P0-3 read-write mount at alternate mountpoint passed'
else
  grep -q 'READ_WRITE_MOUNT' "$txdir/mount-rw-alt.json" && pass 'P0-3 wrong/alternate mountpoint read-write mount blocked' || fail 'P0-3 alternate mountpoint wrong reason'
fi
# Whole-disk /dev/vda is normally unmounted; prove the unmounted path passes.
if [[ -b /dev/vda ]] && [[ -z "$(lsblk -dn -o MOUNTPOINTS /dev/vda 2>/dev/null | sed '/^$/d')" ]]; then
  : >"$txdir/empty.mountinfo"
  if python3 "$checker" --mountinfo "$txdir/empty.mountinfo" /dev/vda >"$txdir/mount-unmounted.json" 2>/dev/null; then
    pass 'P0-3 unmounted block device passes'
  else
    fail "P0-3 unmounted block device rejected: $(cat "$txdir/mount-unmounted.json")"
  fi
else
  pass 'P0-3 unmounted case skipped: no reliably unmounted whole disk in host fixture'
fi

printf 'Summary: %s passed, %s failed\n' "$passed" "$failed" >>"$report"
cat "$report"
((failed == 0))
