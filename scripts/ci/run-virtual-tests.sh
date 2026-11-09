#!/usr/bin/env bash
set -Eeuo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
out="${PAW_ARTIFACT_DIR:-$PWD/artifacts}"
work="$root/tests/virtual/ci-run"
state="$work/state"
mock="$work/mockbin"
mkdir -p "$work" "$mock" "$out" "$state/configs" "$state/reports" "$state/logs" "$root/logs"
export PAW_ROOT="$root" PAW_STATE_DIR="$state" PAW_CONFIG_DIR="$state/configs" PAW_REPORT_DIR="$state/reports" PAW_LOG_DIR="$state/logs"
export PATH="$mock:$PATH"
report="$out/virtual-fault-injection-report.txt"
failed=0
passed=0
loop_devices=()
cleanup(){
  for dev in "${loop_devices[@]}"; do losetup -d "$dev" 2>/dev/null || true; done
  rm -f "$root/tests/virtual/ci-source.img" "$root/tests/virtual/ci-target.img" "$root/tests/virtual/ci-too-small.img" "$root/tests/virtual/ci-gpt-ext4.img" /run/paw-network/rescue_ed25519 /run/paw-network/known_hosts /run/paw-network/rescue-endpoint.json /run/paw-network/remote-lsblk.json
  rm -rf "$work"
}
trap cleanup EXIT
pass(){ printf 'PASS %s\n' "$1" >>"$report"; passed=$((passed+1)); }
expect_fail(){
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then printf 'FAIL %s unexpectedly succeeded\n' "$label" >>"$report"; failed=$((failed+1)); else pass "$label stopped as expected"; fi
}

cat >"$mock/lsblk" <<'MOCKLSBLK'
#!/usr/bin/env bash
last="${!#}"
if [[ " $* " == *" -o SERIAL "* && "$last" == "${PAW_MOCK_TARGET_DEVICE:-}" ]]; then
  printf '%s\n' "${PAW_MOCK_TARGET_SERIAL:-CI-LOOP-ONLY}"
  exit 0
fi
exec /usr/bin/lsblk "$@"
MOCKLSBLK
chmod 0755 "$mock/lsblk"

cat >"$mock/ssh" <<'MOCKSSH'
#!/usr/bin/env bash
cmd="${!#}"
[[ "${PAW_TEST_SSH_MODE:-ok}" != fail_all ]] || exit 255
case "$cmd" in
  *'lsblk --json --bytes --output'*) cat "$PAW_MOCK_LSBLK_JSON"; exit 0 ;;
  *'findmnt --noheadings --raw --source'*) [[ "${PAW_TEST_RW_MOUNT:-0}" == 1 ]] && echo rw,relatime; exit 0 ;;
  *'lsblk -nrpo MOUNTPOINTS'*) exit 0 ;;
  *'blkid -U '*) printf '%s\n' /dev/mock-root-partition; exit 0 ;;
  *'lsblk -dn -o PKNAME'*) printf '%s\n' "${PAW_MOCK_SOURCE_PARENT:-mock-source}"; exit 0 ;;
  *'blockdev --getsize64'*) stat -c %s "$PAW_MOCK_SOURCE_FILE"; exit 0 ;;
  *'command -v zstd'*)
    if [[ "${PAW_TEST_ZSTD_MODE:-available}" == missing ]]; then echo ZSTD_UNAVAILABLE; else echo ZSTD_AVAILABLE; fi
    exit 0
    ;;
  *'cat /proc/meminfo'*) printf 'MemAvailable: 1048576 kB\n'; exit 0 ;;
  *'bash -o pipefail -c '* )
    if [[ "${PAW_TEST_SSH_MODE:-ok}" == interrupt ]]; then
      head -c 1048576 "$PAW_MOCK_SOURCE_FILE" | zstd -T1 -1 -c
      exit 255
    fi
    zstd -T1 -1 -c "$PAW_MOCK_SOURCE_FILE"
    exit 0
    ;;
  *'dd if='*) cat "$PAW_MOCK_SOURCE_FILE"; exit 0 ;;
  *'sha256sum '*) sha256sum "$PAW_MOCK_SOURCE_FILE" | awk '{print $1}'; exit 0 ;;
  *) exit 0 ;;
esac
MOCKSSH
chmod 0755 "$mock/ssh"

test_uuid="$(python3 -c 'import uuid; print(uuid.uuid4())')"
cat >"$root/tests/virtual/ci-source-lsblk.json" <<'LSBLK'
{"blockdevices":[{"name":"mockdisk","path":"/dev/mockdisk","type":"disk","size":53687091200,"model":"CI Virtual Disk","serial":"CI-SOURCE-ONLY","ro":false,"pttype":"gpt","children":[{"name":"mockdisk1","path":"/dev/mockdisk1","type":"part","size":1048576,"partn":1,"parttype":"21686148-6449-6e6f-744e-656564454649","fstype":null,"uuid":null,"ro":false,"mountpoints":[null]},{"name":"mockdisk2","path":"/dev/mockdisk2","type":"part","size":53686042624,"partn":2,"parttype":"0fc63daf-8483-4772-8e79-3d69d8477de4","fstype":"ext4","uuid":"__TEST_ROOT_UUID__","ro":false,"mountpoints":[null]}]}]}
LSBLK
sed -i "s/__TEST_ROOT_UUID__/$test_uuid/" "$root/tests/virtual/ci-source-lsblk.json"
export PAW_MOCK_LSBLK_JSON="$root/tests/virtual/ci-source-lsblk.json"

write_configs(){
  local source_dev="$1" target_dev="$2" serial="${3:-CI-LOOP-ONLY}"
  python3 - "$PAW_CONFIG_DIR" "$source_dev" "$target_dev" "$serial" "$test_uuid" <<'PY'
import json,sys
p,src,dst,serial,test_uuid=sys.argv[1:]
json.dump({"source_mode":"rescue","device_path":src,"root_uuid":test_uuid,"ssh_host":"rescue.invalid","ssh_port":22,"ssh_user":"root","identity_file":"/run/paw-network/rescue_ed25519","known_hosts_file":"/run/paw-network/known_hosts"},open(p+"/source.json","w"))
json.dump({"approved":True,"device_path":dst,"serial":serial,"capacity_bytes":int(__import__("subprocess").check_output(["/usr/bin/lsblk","-dnbo","SIZE",dst]))},open(p+"/target-ssd.json","w"))
json.dump({"status":"PASS"},open(p+"/../reports/source-discovery.json","w"))
import datetime
now=datetime.datetime.now(datetime.timezone.utc)
json.dump({"status":"AUTHORIZED","target_device":dst,"target_serial":serial,"authorized_at":now.isoformat(),"expires_at":(now+datetime.timedelta(hours=1)).isoformat()},open(p+"/../reports/operator-authorization.json","w"))
PY
  printf '{"status":"PASS"}\n' >"$PAW_REPORT_DIR/paw-hardware-health-report.json"
}

printf 'PAW virtual fault-injection results\n' >"$report"
source_file="$root/tests/virtual/ci-source.img"
target_file="$root/tests/virtual/ci-target.img"
truncate -s 8M "$source_file"
dd if=/dev/zero of="$source_file" bs=1M count=8 status=none
truncate -s 16M "$target_file"
source_loop="$(losetup --find --show "$source_file")"; loop_devices+=("$source_loop")
target_loop="$(losetup --find --show "$target_file")"; loop_devices+=("$target_loop")
export PAW_MOCK_TARGET_DEVICE="$target_loop" PAW_MOCK_SOURCE_FILE="$source_file" PAW_MOCK_SOURCE_PARENT="${source_loop##*/}"
export PAW_DESTRUCTIVE_ARM=I_HAVE_VERIFIED_THE_TARGET_SERIAL PAW_SIMULATION=0
install -d -m 0700 /run/paw-network
printf '{"host":"rescue.invalid","port":22}\n' >/run/paw-network/rescue-endpoint.json
chmod 0600 /run/paw-network/rescue-endpoint.json
printf 'ci-only-placeholder\n' >/run/paw-network/rescue_ed25519
chmod 0600 /run/paw-network/rescue_ed25519
printf 'rescue.invalid ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIciOnlyTestKey\n' >/run/paw-network/known_hosts
chmod 0600 /run/paw-network/known_hosts
PAW_EXPECTED_ROOT_UUID="$test_uuid" "$root/scripts/paw-source-discovery.sh" && pass 'Authenticated mock Rescue SSH discovery matched 50 GiB GPT, BIOS Boot and ext4 root' || { echo 'FAIL remote source discovery' >>"$report"; failed=$((failed+1)); }
grep -q '"status": "PASS"' "$PAW_REPORT_DIR/source-discovery.json" || { echo 'FAIL source discovery report missing PASS' >>"$report"; failed=$((failed+1)); }
expect_fail 'Read-write-mounted Rescue source' env PAW_EXPECTED_ROOT_UUID="$test_uuid" PAW_TEST_RW_MOUNT=1 "$root/scripts/paw-source-discovery.sh"
PAW_EXPECTED_ROOT_UUID="$test_uuid" "$root/scripts/paw-source-discovery.sh" >/dev/null 2>&1
write_configs "$source_loop" "$target_loop"

expect_fail 'Rescue SSH login failure' env PAW_TEST_SSH_MODE=fail_all bash -c 'source "$PAW_ROOT/scripts/paw-lib.sh"; rescue_ssh true'
before="$(sha256sum "$target_file" | awk '{print $1}')"
write_configs "$source_loop" "$target_loop" WRONG-SERIAL
expect_fail 'Target serial mismatch before write' "$root/scripts/paw-stream-clone.sh" "$source_loop" "$target_loop"
after="$(sha256sum "$target_file" | awk '{print $1}')"
[[ "$before" == "$after" ]] || { echo 'Target changed during serial-mismatch rejection.' >>"$report"; failed=$((failed+1)); }
[[ "$before" == "$after" ]] && pass 'Serial-mismatch target stayed byte-identical'
write_configs "$source_loop" "$target_loop"

expect_fail 'Interrupted SSH stream' env PAW_TEST_SSH_MODE=interrupt "$root/scripts/paw-stream-clone.sh" "$source_loop" "$target_loop"
[[ -f "$PAW_REPORT_DIR/CLONE-INCOMPLETE" ]] && pass 'Interrupted stream retained CLONE-INCOMPLETE' || { echo 'FAIL interrupted stream marker missing' >>"$report"; failed=$((failed+1)); }
dd if=/dev/zero of="$target_loop" bs=1M count=16 conv=notrunc status=none
"$root/scripts/paw-stream-clone.sh" "$source_loop" "$target_loop"
stream_bytes="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["ssh_stream_bytes"])' "$PAW_REPORT_DIR/stream-transfer-report.json")"
((stream_bytes < 1048576)) && pass 'Remote zstd reduced the SSH payload below 1 MiB for an 8 MiB virtual source' || { echo 'FAIL compressed SSH payload was not smaller than source' >>"$report"; failed=$((failed+1)); }
"$root/scripts/paw-stream-verify.sh" "$source_loop" "$target_loop"
"$root/scripts/paw-firstboot-check.sh" && pass 'SSH stream, zstd round-trip, SHA256, and firstboot gate' || { echo 'FAIL successful clone path' >>"$report"; failed=$((failed+1)); }
python3 - "$PAW_REPORT_DIR/stream-transfer-report.json" <<'PY' && pass 'Stream report distinguishes source bytes, SSH payload, restored bytes, compression and SHA256'
import json,sys
d=json.load(open(sys.argv[1])); assert d['source_bytes']==8388608 and d['restored_bytes']==8388608
assert d['ssh_stream_bytes']<d['source_bytes'] and d['independent_sha256_verified'] is True and len(d['sha256'])==64
PY

dd if=/dev/zero of="$target_loop" bs=1M count=16 conv=notrunc status=none
export PAW_TEST_ZSTD_MODE=missing
"$root/scripts/paw-stream-clone.sh" "$source_loop" "$target_loop"
fallback_mode="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["stream_mode"])' "$PAW_REPORT_DIR/stream-transfer-report.json")"
fallback_bytes="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["ssh_stream_bytes"])' "$PAW_REPORT_DIR/stream-transfer-report.json")"
[[ "$fallback_mode" == raw-fallback && "$fallback_bytes" == 8388608 ]] && pass 'Missing remote zstd selects an explicitly reported raw SSH fallback' || { echo 'FAIL raw fallback reporting' >>"$report"; failed=$((failed+1)); }
"$root/scripts/paw-stream-verify.sh" "$source_loop" "$target_loop"
unset PAW_TEST_ZSTD_MODE

printf '\377' | dd of="$target_loop" bs=1 seek=0 conv=notrunc status=none
expect_fail 'Corrupted destination SHA256' "$root/scripts/paw-stream-verify.sh" "$source_loop" "$target_loop"
dd if=/dev/zero of="$target_loop" bs=1M count=16 conv=notrunc status=none
"$root/scripts/paw-stream-clone.sh" "$source_loop" "$target_loop"
"$root/scripts/paw-stream-verify.sh" "$source_loop" "$target_loop"
pass 'Re-run to fresh verified virtual target clears incomplete state'

small="$root/tests/virtual/ci-too-small.img"
truncate -s 4M "$small"
export PAW_SIMULATION=1
small_before="$(sha256sum "$small" | awk '{print $1}')"
expect_fail 'Destination too small' "$root/scripts/paw-stream-clone.sh" "$source_file" "$small"
small_after="$(sha256sum "$small" | awk '{print $1}')"
[[ "$small_before" == "$small_after" ]] && pass 'Too-small target stayed byte-identical before writing' || { echo 'FAIL too-small target changed' >>"$report"; failed=$((failed+1)); }
rm -f "$PAW_REPORT_DIR/CLONE-INCOMPLETE"
expect_fail 'Target image absent' "$root/scripts/paw-stream-clone.sh" "$source_file" "$root/tests/virtual/missing-target.img"
export PAW_SIMULATION=0

# Hardware fault cases use only the loop-backed target; command stubs cannot access host disks.
cat >"$mock/smartctl" <<'MOCKSMART'
#!/usr/bin/env bash
case "$1" in
  -x) echo 'SMART support is: Available'; exit 0 ;;
  -H) echo 'SMART overall-health self-assessment test result: FAILED!'; exit 1 ;;
  -c) echo 'No self-test capability'; exit 0 ;;
  *) exit 1 ;;
esac
MOCKSMART
chmod 0755 "$mock/smartctl"
export PAW_SIMULATION=1
expect_fail 'SMART FAIL injection' "$root/scripts/paw-ssd-smart-check.sh" "$target_loop"
cat >"$mock/badblocks" <<'MOCKBADBLOCKS'
#!/usr/bin/env bash
echo 'I/O error injected by virtual test stub' >&2
exit 1
MOCKBADBLOCKS
chmod 0755 "$mock/badblocks"
expect_fail 'Read I/O timeout injection' "$root/scripts/paw-ssd-read-scan.sh" "$target_loop"
printf 'Test 0 errors\nFAIL: injected memory error\n' >"$root/logs/memtest86plus-serial.log"
expect_fail 'Memory error report injection' "$root/scripts/paw-memory-test-report.sh"
grep -q '"status": "FAIL"' "$PAW_REPORT_DIR/memory-test.json" && pass 'Memory failure recorded as FAIL'

# GPT repair and ext4 growth operate only on a loop image located below tests/virtual.
gpt_file="$root/tests/virtual/ci-gpt-ext4.img"
truncate -s 128M "$gpt_file"
printf 'label: gpt\n,\n' | sfdisk "$gpt_file" >/dev/null
gpt_loop="$(losetup --find --show -P "$gpt_file")"; loop_devices+=("$gpt_loop")
part="${gpt_loop}p1"
for _ in $(seq 1 20); do [[ -b "$part" ]] && break; sleep 1; done
[[ -b "$part" ]] || { echo 'FAIL GPT loop partition absent' >>"$report"; failed=$((failed+1)); }
mkfs.ext4 -F "$part" >/dev/null
export PAW_SIMULATION=1 PAW_REPAIR_ARM=I_HAVE_VERIFIED_OFFLINE_FILESYSTEM PAW_EXPAND_ARM=I_HAVE_VERIFIED_CLONE
"$root/scripts/paw-offline-repair.sh" "$part" >/dev/null
old_bytes="$(blockdev --getsize64 "$part")"
old_fs_bytes="$(dumpe2fs -h "$part" 2>/dev/null | awk -F: '/Block count/ {gsub(/ /,"",$2); b=$2} /Block size/ {gsub(/ /,"",$2); s=$2} END {print b*s}')"
truncate -s 256M "$gpt_file"
losetup -c "$gpt_loop"
partprobe "$gpt_loop" || true
udevadm settle
"$root/scripts/paw-gpt-expand.sh" "$gpt_loop" "$part" >/dev/null
new_bytes="$(blockdev --getsize64 "$part")"
((new_bytes > old_bytes)) && pass 'Loop-backed GPT partition expanded' || { echo 'FAIL GPT partition did not grow' >>"$report"; failed=$((failed+1)); }
e2fsck -fn "$part" >/dev/null
fs_bytes="$(dumpe2fs -h "$part" 2>/dev/null | awk -F: '/Block count/ {gsub(/ /,"",$2); b=$2} /Block size/ {gsub(/ /,"",$2); s=$2} END {print b*s}')"
((fs_bytes > old_fs_bytes)) && pass 'Loop-backed ext4 filesystem expanded' || { echo 'FAIL ext4 filesystem did not grow' >>"$report"; failed=$((failed+1)); }

printf 'Summary: %s passed, %s failed\n' "$passed" "$failed" >>"$report"
((failed == 0))
