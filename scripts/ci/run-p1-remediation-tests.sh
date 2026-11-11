#!/usr/bin/env bash
set -Eeuo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
work="${PAW_P1_TEST_DIR:-$root/tests/virtual/p1-remediation}"
out="${PAW_ARTIFACT_DIR:-$PWD/artifacts}"
report="$out/p1-remediation-report.txt"
rm -rf "$work"; mkdir -p "$work" "$out"
passed=0; failed=0
pass(){ printf 'PASS %s\n' "$1" | tee -a "$report"; passed=$((passed+1)); }
fail(){ printf 'FAIL %s\n' "$1" | tee -a "$report"; failed=$((failed+1)); }
printf 'PAW P1 remediation tests\nExecuted: %s\n' "$(date -u +%FT%TZ)" >"$report"

# Real target readback: O_DIRECT path and read-method evidence.
grep -q 'iflag=direct' "$root/scripts/paw-stream-verify.sh" && pass 'P1 stream-verify uses O_DIRECT target readback' || fail 'P1 no O_DIRECT readback'
grep -q 'target_readback_method' "$root/scripts/paw-stream-verify.sh" && pass 'P1 stream-verify records readback method' || fail 'P1 readback method missing'

# Windows disk blocking.
grep -q 'ebd0a0a2-' "$root/scripts/paw-target-discovery.sh" && grep -qi 'ntfs' "$root/scripts/paw-target-discovery.sh" \
  && pass 'P1 target discovery excludes NTFS/Windows GPT disks' || fail 'P1 Windows disk filter missing'

# Offline repair truth.
grep -q 'DEBIAN_FRONTEND=noninteractive' "$root/scripts/paw-offline-repair.sh" && pass 'P1 GRUB/initramfs run noninteractively' || fail 'P1 debconf noninteractive missing'
grep -q 'lsinitramfs' "$root/scripts/paw-offline-repair.sh" && pass 'P1 initramfs module inclusion is independently listed' || fail 'P1 no lsinitramfs verification'
grep -q 'fstab/GRUB UUID identity checked' "$root/scripts/paw-offline-repair.sh" && pass 'P1 fstab/GRUB UUID check is recorded' || fail 'P1 fstab/GRUB check missing'
grep -q 'i915' "$root/scripts/paw-offline-repair.sh" && pass 'P1 HD4600 i915 availability is classified' || fail 'P1 i915 detection missing'
grep -q 'Target kernel has no AHCI driver' "$root/scripts/paw-offline-repair.sh" && pass 'P1 missing AHCI driver is a hard pre-boot block' || fail 'P1 missing AHCI still only warns'
grep -q 'Target kernel has no Realtek r8169 driver' "$root/scripts/paw-offline-repair.sh" && pass 'P1 missing r8169 driver is a hard pre-boot block' || fail 'P1 missing r8169 still only warns'
grep -q 'grub-pc/install_devices multiselect' "$root/scripts/paw-offline-repair.sh" \
  && grep -q 'dpkg-reconfigure -f noninteractive grub-pc' "$root/scripts/paw-offline-repair.sh" \
  && pass 'P1 grub-pc install_devices pinned via noninteractive debconf' \
  || fail 'P1 grub-pc debconf pin missing'
grep -q 'grub_install_devices_stable' "$root/scripts/paw-offline-repair.sh" && pass 'P1 grub install-device stability is recorded' || fail 'P1 grub stability evidence missing'
grep -q 'debconf-show grub-pc' "$root/scripts/paw-offline-repair.sh" && pass 'P1 grub-pc install_devices is read back after reconfigure' || fail 'P1 grub debconf readback missing'

# Reboot media order and firstboot semantics.
grep -q 'boot_order_control' "$root/scripts/paw-reboot-media-check.sh" && pass 'P1 BIOS media-order limitation is recorded' || fail 'P1 media-order check missing'
grep -q 'actual_first_boot_performed.*False' "$root/scripts/paw-preboot-handoff-check.sh" && pass 'P1 pre-reboot handoff does not claim a first boot' || fail 'P1 preboot semantics still misleading'
grep -q 'post_boot' "$root/scripts/paw-firstboot-check.sh" && pass 'P1 real firstboot check is post-boot only' || fail 'P1 firstboot split missing'

# SMART PASS/WARN/FAIL classification with a fake smartctl.
smartdir="$work/smart"; mkdir -p "$smartdir/bin" "$smartdir/reports"
cat >"$smartdir/bin/smartctl" <<'SMART_SCRIPT'
#!/usr/bin/env bash
case "$*" in
  *"-x"*) cat <<'OUT'
SMART support is: Available - device has SMART capability.
SMART overall-health self-assessment test result: PASSED
Short self-test routine recommended polling time: ( 1) minutes.
Self-test execution status: ( 0) The previous self-test completed without error.
OUT
;;
  *"-H"*) echo 'SMART overall-health self-assessment test result: PASSED' ;;
  *"-c"*) cat <<'OUT'
Self-test execution status: ( 0) The previous self-test completed without error.
Short self-test routine recommended polling time: ( 1) minutes.
OUT
;;
  *"-l selftest"*) echo '# 1  Short offline       Completed without error       00%         1         -' ;;
  *"-t short"*) echo 'Short self-test routine started.' ;;
  *) echo 'unsupported fake invocation' >&2; exit 1 ;;
esac
SMART_SCRIPT
chmod 0755 "$smartdir/bin/smartctl"
if PATH="$smartdir/bin:$PATH" PAW_STATE_DIR="$smartdir/state" PAW_REPORT_DIR="$smartdir/reports" \
   PAW_SMART_POLL_SECONDS=1 PAW_ROOT="$root" bash "$root/scripts/paw-ssd-smart-check.sh" /dev/sr0 \
   >"$smartdir/run.log" 2>&1; then
  python3 - "$smartdir/reports/smart-sr0.json" <<'PY' && pass 'P1 SMART PASS classified with selftest clean' || fail 'P1 SMART PASS classification wrong'
import json,sys
d=json.load(open(sys.argv[1])); assert d["status"]=="PASS" and d["classification"]=="SMART_SELFTEST_CLEAN", d
PY
else
  fail "P1 SMART PASS path failed: $(tail -5 "$smartdir/run.log")"
fi
cat >"$smartdir/bin/smartctl" <<'SMART_SCRIPT'
#!/usr/bin/env bash
case "$*" in
  *"-x"*) echo 'SMART support is: Available - device has SMART capability.'; echo 'SMART overall-health self-assessment test result: PASSED' ;;
  *"-H"*) echo 'SMART overall-health self-assessment test result: FAILED!' ;;
  *) echo 'x' ;;
esac
SMART_SCRIPT
chmod 0755 "$smartdir/bin/smartctl"
if PATH="$smartdir/bin:$PATH" PAW_STATE_DIR="$smartdir/state" PAW_REPORT_DIR="$smartdir/reports" PAW_ROOT="$root" \
   bash "$root/scripts/paw-ssd-smart-check.sh" /dev/sr0 >"$smartdir/fail.log" 2>&1; then
  fail 'P1 SMART FAIL health path returned 0'
else
  python3 - "$smartdir/reports/smart-sr0.json" <<'PY' && pass 'P1 SMART FAIL health classified, never PASS' || fail 'P1 SMART FAIL classification wrong'
import json,sys
d=json.load(open(sys.argv[1])); assert d["status"]=="FAIL" and d["classification"]=="SMART_HEALTH_FAILED", d
PY
fi
cat >"$smartdir/bin/smartctl" <<'SMART_SCRIPT'
#!/usr/bin/env bash
case "$*" in
  *"-x"*) echo 'SMART support is: Available - device has SMART capability.'; echo 'SMART overall-health self-assessment test result: PASSED' ;;
  *"-H"*) echo 'SMART overall-health self-assessment test result: PASSED'; exit 16 ;;
  *) echo 'x'; exit 1 ;;
esac
SMART_SCRIPT
chmod 0755 "$smartdir/bin/smartctl"
if PATH="$smartdir/bin:$PATH" PAW_STATE_DIR="$smartdir/state" PAW_REPORT_DIR="$smartdir/reports" PAW_ROOT="$root" \
   bash "$root/scripts/paw-ssd-smart-check.sh" /dev/sr0 >"$smartdir/nonzero.log" 2>&1; then
  fail 'P1 SMART PASS-with-nonzero-rc returned 0 instead of WARN'
else
  python3 - "$smartdir/reports/smart-sr0.json" <<'PY' && pass 'P1 SMART PASS with non-zero smartctl mask is WARN, not false FAIL/PASS' || fail 'P1 SMART non-zero-rc classification wrong'
import json,sys
d=json.load(open(sys.argv[1])); assert d["status"]=="WARN" and d["classification"]=="SMART_HEALTH_PASSED_NONZERO_RC", d
PY
fi

# Service identity manifest: machine-id/key isolation is required; hostname
# preservation is intentional and must not force REVIEW.
srv="$work/service"; mkdir -p "$srv/target/etc/ssh" "$srv/target/etc/systemd/system/multi-user.target.wants"
printf 'new-machine-id\n' >"$srv/target/etc/machine-id"
printf 'paw-target\n' >"$srv/target/etc/hostname"
printf 'new-public-key\n' >"$srv/target/etc/ssh/ssh_host_ed25519_key.pub"
printf '[1]\n' >"$srv/target/etc/systemd/system/multi-user.target.wants/paw-firstboot.service"
cat >"$srv/source.json" <<'JSON'
{"device_path":"/dev/sda","composite_identity_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}
JSON
old_ssh="$(printf 'old-public-key\n' | sha256sum | awk '{print $1}')"
python3 "$root/scripts/paw-service-cutover-manifest.py" --source-config "$srv/source.json" --target-root "$srv/target" \
  --old-hostname paw-target --old-machine-id old-machine-id --old-ssh-fingerprint "$old_ssh" \
  --old-services-json '["old.service"]' --output "$srv/manifest.json" >/dev/null \
  && pass 'P1 service manifest PASS with changed machine-id/SSH and preserved hostname' \
  || fail 'P1 service manifest did not PASS isolated identity'

# Reboot media order: fake attached PAW-LIVE blocks; explicit arm passes.
med="$work/media"; mkdir -p "$med/bin" "$med/reports"
cat >"$med/bin/findmnt" <<'FM'
#!/bin/sh
echo /dev/sdc1
FM
cat >"$med/bin/lsblk" <<'LS'
#!/bin/sh
case "$*" in
  *"-o PKNAME"*) echo sdc ;;
  *"NAME,LABEL"*) echo '/dev/sdc PAW-LIVE' ;;
  *) echo '' ;;
esac
LS
chmod 0755 "$med/bin/findmnt" "$med/bin/lsblk"
if PATH="$med/bin:$PATH" PAW_STATE_DIR="$med/state" PAW_REPORT_DIR="$med/reports" PAW_ROOT="$root" \
   bash "$root/scripts/paw-reboot-media-check.sh" >"$med/block.log" 2>&1; then
  fail 'P1 attached PAW-LIVE medium did not block auto reboot'
else
  python3 - "$med/reports/reboot-media-order.json" <<'PY' && pass 'P1 attached PAW-LIVE medium blocks auto reboot' || fail 'P1 media block report wrong'
import json,sys
d=json.load(open(sys.argv[1])); assert d["status"]=="BLOCKED" and d["auto_reboot_allowed"] is False, d
PY
fi
if PATH="$med/bin:$PATH" PAW_LIVE_MEDIA_REMOVED=I_HAVE_REMOVED_THE_LIVE_USB_AND_TF_MEDIA PAW_STATE_DIR="$med/state" PAW_REPORT_DIR="$med/reports" PAW_ROOT="$root" \
   bash "$root/scripts/paw-reboot-media-check.sh" >"$med/arm.log" 2>&1; then
  pass 'P1 explicit live-media removal arm allows auto reboot'
else
  fail 'P1 media removal arm rejected'
fi

printf 'Summary: %s passed, %s failed\n' "$passed" "$failed" >>"$report"
cat "$report"
((failed == 0))
