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

# REMED-P0-1: target identity hashes in operator-authorization.json and transaction init checks
if grep -q 'target_hardware_identity_sha256' "$root/tests/prehardware/guest-chain.sh" \
  && grep -q 'target_composite_identity_sha256' "$root/tests/prehardware/guest-chain.sh" \
  && grep -q 'tx-init.stdout' "$root/tests/prehardware/guest-chain.sh" \
  && grep -q 'tx-init.stderr' "$root/tests/prehardware/guest-chain.sh" \
  && grep -q 'tx-init.rc' "$root/tests/prehardware/guest-chain.sh" \
  && grep -q 'CLONE-INCOMPLETE' "$root/tests/prehardware/guest-chain.sh"; then
  pass 'REMED-P0-1 guest-chain.sh reads target identity hashes, logs tx init outputs, and verifies CLONE-INCOMPLETE'
else
  fail 'REMED-P0-1 guest-chain.sh missing required identity hash or logging logic'
fi

id_txdir="$work/tx-identity"; mkdir -p "$id_txdir/reports" "$id_txdir/configs"
cp "$txdir/configs/source.json" "$id_txdir/configs/source.json"
hw_hash='1111111111111111111111111111111111111111111111111111111111111111'
comp_hash='2222222222222222222222222222222222222222222222222222222222222222'
cat >"$id_txdir/configs/target-ssd.json" <<JSON
{"approved":true,"device_path":"/dev/sdb","model":"SIM-TARGET","serial":"TGT-SERIAL-999999","capacity_bytes":240000000000,"hardware_identity_sha256":"$hw_hash","composite_identity_sha256":"$comp_hash"}
JSON
write_id_auth(){
  local out_file="$1" hw="$2" comp="$3"
  python3 - "$out_file" "$now" "$expires" "$hw" "$comp" <<'PY'
import json,sys
p,now,exp,hw,comp=sys.argv[1:]
doc={"status":"AUTHORIZED","migration_id":"11111111-1111-1111-1111-111111111111","authorization_id":"22222222-2222-2222-2222-222222222222","target_device":"/dev/sdb","target_serial":"TGT-SERIAL-999999","source_composite_identity_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","authorized_at":now,"expires_at":exp}
if hw != "OMIT": doc["target_hardware_identity_sha256"]=hw
if comp != "OMIT": doc["target_composite_identity_sha256"]=comp
with open(p,"w",encoding="utf-8") as h: json.dump(doc,h)
PY
}
write_id_auth "$id_txdir/auth-ok.json" "$hw_hash" "$comp_hash"
run_tx init --transaction "$id_txdir/tx-ok.json" --authorization "$id_txdir/auth-ok.json" --source-config "$id_txdir/configs/source.json" --target-config "$id_txdir/configs/target-ssd.json" --now "$now" >/dev/null 2>"$id_txdir/ok.err" \
  && pass 'REMED-P0-1 matching target hardware+composite identity hashes allow init' || fail "REMED-P0-1 valid hashes rejected: $(cat "$id_txdir/ok.err")"

write_id_auth "$id_txdir/auth-bad-hw.json" '9999999999999999999999999999999999999999999999999999999999999999' "$comp_hash"
if run_tx init --transaction "$id_txdir/tx-bad-hw.json" --authorization "$id_txdir/auth-bad-hw.json" --source-config "$id_txdir/configs/source.json" --target-config "$id_txdir/configs/target-ssd.json" --now "$now" >/dev/null 2>&1; then
  fail 'REMED-P0-1 wrong target hardware hash passed'
else
  pass 'REMED-P0-1 wrong target hardware hash rejected'
fi

write_id_auth "$id_txdir/auth-bad-comp.json" "$hw_hash" '9999999999999999999999999999999999999999999999999999999999999999'
if run_tx init --transaction "$id_txdir/tx-bad-comp.json" --authorization "$id_txdir/auth-bad-comp.json" --source-config "$id_txdir/configs/source.json" --target-config "$id_txdir/configs/target-ssd.json" --now "$now" >/dev/null 2>&1; then
  fail 'REMED-P0-1 wrong target composite hash passed'
else
  pass 'REMED-P0-1 wrong target composite hash rejected'
fi

write_id_auth "$id_txdir/auth-miss-hw.json" "OMIT" "$comp_hash"
if run_tx init --transaction "$id_txdir/tx-miss-hw.json" --authorization "$id_txdir/auth-miss-hw.json" --source-config "$id_txdir/configs/source.json" --target-config "$id_txdir/configs/target-ssd.json" --now "$now" >/dev/null 2>&1; then
  fail 'REMED-P0-1 missing target hardware hash passed'
else
  pass 'REMED-P0-1 missing target hardware hash rejected'
fi

write_id_auth "$id_txdir/auth-miss-comp.json" "$hw_hash" "OMIT"
if run_tx init --transaction "$id_txdir/tx-miss-comp.json" --authorization "$id_txdir/auth-miss-comp.json" --source-config "$id_txdir/configs/source.json" --target-config "$id_txdir/configs/target-ssd.json" --now "$now" >/dev/null 2>&1; then
  fail 'REMED-P0-1 missing target composite hash passed'
else
  pass 'REMED-P0-1 missing target composite hash rejected'
fi

run_tx event --transaction "$id_txdir/tx-ok.json" --event CLONE_STARTED --now "$now" >/dev/null
printf 'INCOMPLETE\n' >"$id_txdir/reports/CLONE-INCOMPLETE"
run_tx event --transaction "$id_txdir/tx-ok.json" --event CLONE_INCOMPLETE --now "$now" >/dev/null
if grep -q '"state": "CLONE_INCOMPLETE"' "$id_txdir/tx-ok.json" && [[ -f "$id_txdir/reports/CLONE-INCOMPLETE" ]]; then
  pass 'REMED-P0-1 SSH interrupt retains CLONE_INCOMPLETE transaction state and marker'
else
  fail 'REMED-P0-1 SSH interrupt did not retain CLONE_INCOMPLETE'
fi

# REMED-P0-2: target boot evidence verification (both verify-chain-evidence.py and run-prehardware-lab.py)
evdir="$work/evidence"; mkdir -p "$evdir"
cat >"$evdir/runner-ok.log" <<'EOF'
[prehardware] main result=TARGET_BOOT_SEEN serial_log=/tmp/console.log chain_pass=True target_boot=True
EOF
cat >"$evdir/runner-bad.log" <<'EOF'
[prehardware] main result=CHAIN_PASS_NO_TARGET_BOOT serial_log=/tmp/console.log chain_pass=True target_boot=False
EOF
python3 - "$root/tests/prehardware/verify-chain-evidence.py" "$evdir" <<'PY'
import importlib.util,sys
from pathlib import Path
spec=importlib.util.spec_from_file_location("vce",sys.argv[1])
mod=importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
d=Path(sys.argv[2])
base_steps=[]
for step in mod.REQUIRED:
    if step=="auto_reboot":
        continue
    if step=="sata":
        base_steps.append(f"PAW3_STEP=sata STATUS=PASS bytes={mod.SOURCE_BYTES} tran=ata model=ich9-ahci media_bytes={mod.MEDIA_BYTES}")
    elif step=="target_enrollment":
        base_steps.append(f"PAW3_STEP=target_enrollment STATUS=PASS capacity={mod.TARGET_BYTES}")
    else:
        base_steps.append(f"PAW3_STEP={step} STATUS=PASS")
base="\n".join(["Ubuntu 24.04.5 LTS live login:"] + base_steps + ["PAW3_CHAIN_RESULT=PASS"]) + "\n"
(d/"console-ok.log").write_text(base + "PAW3_STEP=auto_reboot STATUS=PASS target=/dev/vdb\n[ 12.345] reboot: Restarting system\nUbuntu 24.04.5 LTS ubuntu ttyS0\n\nubuntu login:\n")
(d/"console-preonly.log").write_text(base)
(d/"console-no-reboot.log").write_text(base + "Ubuntu 24.04.5 LTS ubuntu ttyS0\n\nubuntu login:\n")
(d/"console-reboot-no-login.log").write_text(base + "PAW3_STEP=auto_reboot STATUS=PASS target=/dev/vdb\n[ 12.345] reboot: Restarting system\n[ 15.000] systemd[1]: Reached target Multi-User System.\n")
(d/"console-generic-login.log").write_text(base + "PAW3_STEP=auto_reboot STATUS=PASS target=/dev/vdb\nsome-other-system ttyS0\nlogin:\n")
PY

if python3 "$root/tests/prehardware/verify-chain-evidence.py" --log "$evdir/console-ok.log" --output "$evdir/ok.json" --summary "$evdir/ok.txt" --runner-log "$evdir/runner-ok.log" >/dev/null 2>&1 \
  && python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["status"]=="PASS" and d["checks"]["target_boot_login"] and d["checks"]["auto_reboot_before_target_login"] and d["checks"]["host_runner_corroborated"]' "$evdir/ok.json"; then
  pass 'REMED-P0-2 valid post-reboot Ubuntu target login + host corroboration PASS'
else
  fail 'REMED-P0-2 valid target boot evidence failed'
fi
for neg in console-preonly console-no-reboot console-reboot-no-login console-generic-login; do
  if python3 "$root/tests/prehardware/verify-chain-evidence.py" --log "$evdir/$neg.log" --output "$evdir/$neg.json" --summary "$evdir/$neg.txt" --runner-log "$evdir/runner-ok.log" >/dev/null 2>&1; then
    fail "REMED-P0-2 negative case $neg unexpectedly passed"
  else
    pass "REMED-P0-2 negative case $neg rejected"
  fi
done
if python3 "$root/tests/prehardware/verify-chain-evidence.py" --log "$evdir/console-ok.log" --output "$evdir/badrun.json" --summary "$evdir/badrun.txt" --runner-log "$evdir/runner-bad.log" >/dev/null 2>&1; then
  fail 'REMED-P0-2 mismatched host runner log unexpectedly passed'
else
  pass 'REMED-P0-2 mismatched host runner log rejected'
fi
if python3 - "$root/tests/prehardware/run-prehardware-lab.py" "$evdir" <<'PY'
import importlib.util,sys
from pathlib import Path
spec=importlib.util.spec_from_file_location("lab",sys.argv[1])
mod=importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
d=Path(sys.argv[2])
assert mod.post_reboot_target_login_seen((d/"console-ok.log").read_text())
assert not mod.post_reboot_target_login_seen((d/"console-preonly.log").read_text())
assert not mod.post_reboot_target_login_seen((d/"console-no-reboot.log").read_text())
assert not mod.post_reboot_target_login_seen((d/"console-reboot-no-login.log").read_text())
assert not mod.post_reboot_target_login_seen((d/"console-generic-login.log").read_text())
PY
then
  pass 'REMED-P0-2 run-prehardware-lab.py post_reboot_target_login_seen matches verifier rules'
else
  fail 'REMED-P0-2 run-prehardware-lab.py post_reboot_target_login_seen mismatch'
fi

# REMED-P0-3: source root last-partition pre-check in paw-source-discovery.sh (while keeping paw-gpt-expand.sh gate)
if grep -q 'part_start == last_start' "$root/scripts/paw-gpt-expand.sh"; then
  pass 'REMED-P0-3 paw-gpt-expand.sh second gate retained'
else
  fail 'REMED-P0-3 paw-gpt-expand.sh second gate missing'
fi

sdir="$work/source-discovery"; mkdir -p "$sdir"
python3 - "$root/scripts/paw-source-discovery.sh" "$sdir" <<'PY'
import re,sys
src=open(sys.argv[1],encoding="utf-8").read()
m=re.search(r"candidate=\"\$\(python3 - .*?<<'PY'\n(.*?)\nPY\n\)\"",src,re.S)
assert m, "could not extract validation python block from paw-source-discovery.sh"
open(sys.argv[2]+"/validate_source.py","w",encoding="utf-8").write(m.group(1)+"\n")
PY
run_src_disc(){
  local case_dir="$1" json_payload="$2"
  rm -rf "$case_dir"; mkdir -p "$case_dir"
  printf '%s\n' "$json_payload" >"$case_dir/lsblk.json"
  python3 "$sdir/validate_source.py" \
    '11111111-2222-3333-4444-555555555555' \
    '53687091200' \
    "$case_dir/lsblk.json" \
    'SHA256:testpinnedhostkeyfingerprint' \
    '0000000000000000000000000000000000000000000000000000000000000000' \
    "$case_dir/source-discovery.json" \
    >"$case_dir/candidate.json" 2>"$case_dir/stderr.log"
}

good_last='{"blockdevices":[{"name":"vda","path":"/dev/vda","type":"disk","size":53687091200,"model":"SRC","serial":"S1","ro":false,"pttype":"gpt","children":[{"name":"vda1","path":"/dev/vda1","type":"part","size":1048576,"partn":1,"parttype":"21686148-6449-6e6f-744e-656564454649","start":2048},{"name":"vda2","path":"/dev/vda2","type":"part","size":104857600,"partn":2,"parttype":"c12a7328-f81f-11d2-ba4b-00a0c93ec93b","fstype":"vfat","start":6144},{"name":"vda3","path":"/dev/vda3","type":"part","size":53580000000,"partn":3,"parttype":"0fc63daf-8483-4772-8e79-3d69d8477de4","fstype":"ext4","uuid":"11111111-2222-3333-4444-555555555555","start":220000}]}]}'
cloud_last='{"blockdevices":[{"name":"vda","path":"/dev/vda","type":"disk","size":53687091200,"model":"SRC","serial":"S1","ro":false,"pttype":"gpt","children":[{"name":"vda1","path":"/dev/vda1","type":"part","size":53500000000,"partn":1,"parttype":"0fc63daf-8483-4772-8e79-3d69d8477de4","fstype":"ext4","uuid":"11111111-2222-3333-4444-555555555555","start":220000},{"name":"vda14","path":"/dev/vda14","type":"part","size":4194304,"partn":14,"parttype":"21686148-6449-6e6f-744e-656564454649","start":2048},{"name":"vda15","path":"/dev/vda15","type":"part","size":104857600,"partn":15,"parttype":"c12a7328-f81f-11d2-ba4b-00a0c93ec93b","fstype":"vfat","start":10240}]}]}'
non_last='{"blockdevices":[{"name":"vda","path":"/dev/vda","type":"disk","size":53687091200,"model":"SRC","serial":"S1","ro":false,"pttype":"gpt","children":[{"name":"vda14","path":"/dev/vda14","type":"part","size":4194304,"partn":14,"parttype":"21686148-6449-6e6f-744e-656564454649","start":2048},{"name":"vda1","path":"/dev/vda1","type":"part","size":40000000000,"partn":1,"parttype":"0fc63daf-8483-4772-8e79-3d69d8477de4","fstype":"ext4","uuid":"11111111-2222-3333-4444-555555555555","start":220000},{"name":"vda2","path":"/dev/vda2","type":"part","size":10000000000,"partn":2,"parttype":"0fc63daf-8483-4772-8e79-3d69d8477de4","fstype":"ext4","start":90000000}]}]}'
missing_start='{"blockdevices":[{"name":"vda","path":"/dev/vda","type":"disk","size":53687091200,"model":"SRC","serial":"S1","ro":false,"pttype":"gpt","children":[{"name":"vda14","path":"/dev/vda14","type":"part","size":4194304,"partn":14,"parttype":"21686148-6449-6e6f-744e-656564454649","start":null},{"name":"vda1","path":"/dev/vda1","type":"part","size":53500000000,"partn":1,"parttype":"0fc63daf-8483-4772-8e79-3d69d8477de4","fstype":"ext4","uuid":"11111111-2222-3333-4444-555555555555","start":220000}]}]}'
dup_partn='{"blockdevices":[{"name":"vda","path":"/dev/vda","type":"disk","size":53687091200,"model":"SRC","serial":"S1","ro":false,"pttype":"gpt","children":[{"name":"vda1","path":"/dev/vda1","type":"part","size":4194304,"partn":1,"parttype":"21686148-6449-6e6f-744e-656564454649","start":2048},{"name":"vda1b","path":"/dev/vda1b","type":"part","size":53500000000,"partn":1,"parttype":"0fc63daf-8483-4772-8e79-3d69d8477de4","fstype":"ext4","uuid":"11111111-2222-3333-4444-555555555555","start":220000}]}]}'

if run_src_disc "$sdir/good" "$good_last" && python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["root_is_last_partition"] is True and d["partition_layout_check"]["status"]=="PASS" and d["root_partition_start"]==220000 and d["max_partition_start"]==220000' "$sdir/good/candidate.json"; then
  pass 'REMED-P0-3 root-is-last-partition PASS and recorded in source candidate'
else
  fail "REMED-P0-3 good last-partition case failed: $(cat "$sdir/good/stderr.log" 2>/dev/null || true)"
fi
if run_src_disc "$sdir/cloud" "$cloud_last" && python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["root_is_last_partition"] is True' "$sdir/cloud/candidate.json"; then
  pass 'REMED-P0-3 cloud part1-is-last-by-START PASS'
else
  fail "REMED-P0-3 cloud layout failed: $(cat "$sdir/cloud/stderr.log" 2>/dev/null || true)"
fi
if run_src_disc "$sdir/nonlast" "$non_last"; then
  fail 'REMED-P0-3 partition after root unexpectedly passed'
elif python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["status"]=="BLOCKED" and d["root_is_last_partition"] is False' "$sdir/nonlast/source-discovery.json"; then
  pass 'REMED-P0-3 partition after root BLOCKED and recorded in diagnostic report'
else
  fail 'REMED-P0-3 partition after root failed without expected BLOCKED report'
fi
if run_src_disc "$sdir/missstart" "$missing_start"; then
  fail 'REMED-P0-3 missing START unexpectedly passed'
elif grep -q '"BLOCKED"' "$sdir/missstart/source-discovery.json"; then
  pass 'REMED-P0-3 missing START fail-closed BLOCKED'
else
  fail 'REMED-P0-3 missing START did not fail closed with BLOCKED report'
fi
if run_src_disc "$sdir/duppartn" "$dup_partn"; then
  fail 'REMED-P0-3 duplicate partn unexpectedly passed'
elif grep -q '"BLOCKED"' "$sdir/duppartn/source-discovery.json"; then
  pass 'REMED-P0-3 duplicate partn fail-closed BLOCKED'
else
  fail 'REMED-P0-3 duplicate partn did not fail closed with BLOCKED report'
fi

printf 'Summary: %s passed, %s failed\n' "$passed" "$failed" >>"$report"
cat "$report"
((failed == 0))
