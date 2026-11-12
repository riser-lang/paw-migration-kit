#!/usr/bin/env bash
# Stage 3 guest-side integration chain.
#
# This script runs as root inside the disposable QEMU "PAW Live" guest built
# from the release ISO root filesystem.  It drives the real project entry
# points against virtual block devices; it never talks to a physical disk.
#
# Required kernel command line parameters (set by the host runner):
#   paw3.src=/dev/vdb  paw3.dst=/dev/vdc  paw3.media=/dev/sda
#   paw3.media_serial=PAW-MEDIA-123456
set -uo pipefail

export PAW_ROOT=/opt/paw-migration
state=/opt/paw-migration/tests/stage3/state
export PAW_STATE_DIR="$state"
export PAW_CONFIG_DIR="$state/configs"
export PAW_REPORT_DIR="$state/reports"
export PAW_LOG_DIR="$state/logs"
export PAW_REBOOT_HANDOFF_FILE=/run/paw3-chain-pass
mkdir -p "$PAW_CONFIG_DIR" "$PAW_REPORT_DIR" "$PAW_LOG_DIR" /mnt/paw3-host
log_file="$state/chain.log"
: >"$log_file"

say(){
  printf '%s\n' "$*" | tee -a "$log_file" /dev/console >&2
}
step(){
  local name="$1" status="$2" detail="${3:-}"
  say "PAW3_STEP=${name} STATUS=${status} ${detail}"
}
prompt(){
  say "PAW3_PROMPT=$1"
}
fail(){
  step "$1" FAIL "${2:-}"
  say "PAW3_CHAIN_RESULT=FAIL STEP=$1"
  sync
  exit 1
}

# Copy all evidence to the host 9p share as soon as it exists.  The final
# automatic reboot replaces the live root with the cloned target, so evidence
# must not depend on the live tmpfs surviving.
copy_out(){
  if mountpoint -q /mnt/paw3-host; then
    install -d -m 0700 /mnt/paw3-host/state
    rsync -a --delete --exclude 'interrupt-target.img' --exclude '.interrupt-target.img.*' --exclude 'mixed/' "$state/" /mnt/paw3-host/state/ 2>/dev/null || cp -a "$state/." /mnt/paw3-host/state/
    sync
  fi
}

cmdline_value(){
  local key="$1" token
  for token in $(cat /proc/cmdline); do
    case "$token" in "$key="*) printf '%s\n' "${token#*=}"; return 0 ;; esac
  done
  return 1
}

SRC_DEV="$(cmdline_value paw3.src || true)"
DST_DEV="$(cmdline_value paw3.dst || true)"
MEDIA_DEV="$(cmdline_value paw3.media || true)"
MEDIA_SERIAL="$(cmdline_value paw3.media_serial || true)"
# Linux enumerates the virtio-scsi removable medium before the AHCI disks on
# this QEMU machine, so /dev/sda is not a stable role name.  Resolve every
# disposable lab disk by its QEMU serial; never let the test silently measure
# a different physical role.
resolve_lab_disk(){
  lsblk -nrpo NAME,SERIAL 2>/dev/null | awk -v s="$1" '$0 ~ ("[[:space:]]" s "$") {print $1; exit}'
}
SRC_DEV="$(resolve_lab_disk PAW-SRC-123456)"
DST_DEV="$(resolve_lab_disk PAW-DST-123456)"
MEDIA_DEV="$(resolve_lab_disk PAW-MEDIA-123456)"
MEDIA_SERIAL="PAW-MEDIA-123456"
[[ -n "$SRC_DEV" && -n "$DST_DEV" && -n "$MEDIA_DEV" ]] || fail device_roles "could not resolve lab disks by serial (src=${SRC_DEV:-none} dst=${DST_DEV:-none} media=${MEDIA_DEV:-none})"

# Remove stale disposable artifacts from earlier failed lab runs before the
# first evidence copy; an 8 GiB loop image must never be rsynced over 9p.
rm -rf "$state/mixed" "$state/interrupt" "$state/interrupt-target.img" "$state/evidence-clone-incomplete"
rm -f "$PAW_REPORT_DIR/operator-authorization.json" "$PAW_REPORT_DIR/CLONE-INCOMPLETE" "$PAW_REPORT_DIR/stream-transfer-report.json" "$PAW_REPORT_DIR/stream-verify.json"
rm -f "$PAW_LOG_DIR/final-wrong.log" "$PAW_LOG_DIR/final-correct.log"
systemctl stop paw-console.service 2>/dev/null || true
say "PAW3_CHAIN_BEGIN src=$SRC_DEV dst=$DST_DEV media=$MEDIA_DEV media_serial=$MEDIA_SERIAL"
say "boot_id=$(cat /proc/sys/kernel/random/boot_id) kernel=$(uname -r)"
live_root="$(findmnt -n -o SOURCE / 2>/dev/null || true)"
live_medium="$(findmnt -n -o SOURCE --target /run/live/medium 2>/dev/null || true)"
live_toram=0; grep -qw toram /proc/cmdline && live_toram=1
step live_boot PASS "kernel=$(uname -r) root_source=${live_root:-unknown} live_medium=${live_medium:-unknown} root_is_toram=$live_toram cmdline_root=$(cmdline_value root || true)"

# A separate reboot-to-USB pass can prove PAWDATA persistence without rerunning
# the destructive clone.  It is selected only by an explicit lab kernel word.
if [[ "$(cmdline_value paw3.test || true)" == usb-persistence ]]; then
  data_part="$(blkid -L PAWDATA 2>/dev/null | head -n1 || true)"
  [[ -n "$data_part" && -b "$data_part" ]] || { step usb_persistence FAIL 'PAWDATA label not found after reboot'; say 'PAW3_CHAIN_RESULT=FAIL'; poweroff -f; }
  data_parent="$(lsblk -dn -o PKNAME "$data_part" | xargs || true)"
  data_disk="/dev/${data_parent:-$(basename "$data_part")}"
  [[ "$data_disk" == "$MEDIA_DEV" ]] || { step usb_persistence FAIL "PAWDATA is on $data_disk, not boot media $MEDIA_DEV"; say 'PAW3_CHAIN_RESULT=FAIL'; poweroff -f; }
  install -d /mnt/pawdata-check
  mount -o ro "$data_part" /mnt/pawdata-check || { step usb_persistence FAIL 'PAWDATA remount after reboot failed'; say 'PAW3_CHAIN_RESULT=FAIL'; poweroff -f; }
  token=/mnt/pawdata-check/.paw-persistence-token
  if [[ -s "$token" ]] && grep -qE '^created_at=.*boot_id=.*media_serial=PAW-MEDIA-123456' "$token"; then
    step usb_persistence PASS "partition=$data_part disk=$data_disk token=$(cat "$token") token_sha256=$(sha256sum "$token" | awk '{print $1}') remount=ro reboot_observed=true"
    say 'PAW3_CHAIN_RESULT=PASS'
  else
    step usb_persistence FAIL 'persistence token missing or invalid after reboot'
    say 'PAW3_CHAIN_RESULT=FAIL'
  fi
  umount /mnt/pawdata-check || true
  copy_out
  sync
  poweroff -f || true
  exit 0
fi

# ---------------------------------------------------------------------------
# v2.8 hardware-basis checks: Haswell CPU model, declared source capacity, exact
# 240 GB target, SATA/AHCI transport, source OS identity and target module
# availability.  These are QEMU/virtual observations, never physical proof.
# ---------------------------------------------------------------------------
cpu_model="$(awk -F: '/model name/{gsub(/^ +| +$/,"",$2); print $2; exit}' /proc/cpuinfo)"
cpu_vendor="$(awk -F: '/vendor_id/{gsub(/^ +| +$/,"",$2); print $2; exit}' /proc/cpuinfo)"
cpu_cores="$(nproc)"
mem_kb="$(awk '/MemTotal/{print $2}' /proc/meminfo)"
flags="$(awk -F: '/^flags/{print $2; exit}' /proc/cpuinfo)"
for f in sse4_2 avx avx2; do grep -qw "$f" <<<"$flags" || fail cpu "required Haswell flag $f is missing"; done
step cpu PASS "model=$cpu_model vendor=$cpu_vendor cores=$cpu_cores mem_kb=$mem_kb flags=sse4_2+avx+avx2; qemu_cpu_model_not_physical_cpu=true"
copy_out

for dev in "$SRC_DEV" "$DST_DEV" "$MEDIA_DEV"; do
  [[ -b "$dev" ]] || fail sata_presence "$dev is not a block device"
done
src_bytes="$(blockdev --getsize64 "$SRC_DEV")"
dst_bytes="$(blockdev --getsize64 "$DST_DEV")"
media_bytes="$(blockdev --getsize64 "$MEDIA_DEV")"
expected_src_bytes="${PAW_EXPECTED_SOURCE_BYTES:-53687091200}"
[[ "$src_bytes" == "$expected_src_bytes" ]] || fail sata_capacity "source capacity $src_bytes != $expected_src_bytes"
[[ "$dst_bytes" == 240000000000 ]] || fail sata_capacity "target capacity $dst_bytes != 240000000000"
src_tran="$(lsblk -dn -o TRAN "$SRC_DEV" | xargs)"
dst_tran="$(lsblk -dn -o TRAN "$DST_DEV" | xargs)"
# QEMU's ich9-ahci with ide-hd is a libata/AHCI substitute and reports "ata",
# not a physical SATA link.  Accept ata for the disposable lab, but label it as
# virtual and keep the ASUS B85M-G Plus SATA path PHYSICAL_OPEN.
case "$src_tran/$dst_tran" in
  sata/sata|ata/ata) ;;
  *) fail sata_transport "expected sata/sata or ata/ata, got $src_tran/$dst_tran" ;;
esac
transport_class='virtual_ata_ahci_not_physical_sata'
grep -qi 'ahci' /proc/modules || fail sata_ahci 'ahci module is not loaded'
grep -qiE 'ahci|AHCI' <(dmesg) || fail sata_ahci 'dmesg has no AHCI controller line'
# Controller-level evidence, not just a disk-name guess: lspci must name an
# AHCI SATA controller and the kernel must bind the ahci driver.  TRAN=ata is
# the libata label QEMU exposes; it is never promoted to physical SATA proof.
lspci_sata="$(lspci -nn 2>/dev/null | grep -i 'SATA controller' | head -n1 || true)"
lspci_ahci_driver="$(lspci -nnk 2>/dev/null | awk '/SATA controller/{seen=1} seen && /Kernel driver in use/{print $NF; exit}' || true)"
src_sys="/sys/block/$(basename "$SRC_DEV")"
src_driver="$(basename "$(readlink -f "$src_sys/device/driver" 2>/dev/null)" || true)"
media_tran="$(lsblk -dn -o TRAN "$MEDIA_DEV" | xargs)"
media_rm="$(lsblk -dn -o RM "$MEDIA_DEV" | xargs)"
[[ -n "$lspci_sata" ]] || fail sata_ahci 'lspci has no SATA controller entry'
[[ "$lspci_ahci_driver" == ahci ]] || fail sata_ahci "SATA controller driver is '${lspci_ahci_driver:-none}', not ahci"
step sata PASS "source=$SRC_DEV bytes=$src_bytes tran=$src_tran target=$DST_DEV bytes=$dst_bytes tran=$dst_tran media_bytes=$media_bytes controller=ich9-ahci lspci='$lspci_sata' kernel_driver=$lspci_ahci_driver src_sys=$src_sys src_scsi_driver=$src_driver transport_class=$transport_class"
step usb_media PASS "device=$MEDIA_DEV serial=$MEDIA_SERIAL tran=$media_tran rm=$media_rm bytes=$media_bytes booted_from_usb_mass_storage=true controller=qemu-xhci"
copy_out

# The disposable lab target must start blank.  A previous run can leave a clone
# with the source UUID on it; source discovery correctly refuses an ambiguous
# UUID, so reset only the serial-verified 240 GB test disk here.  Production
# entry points never wipe a target implicitly; this is a chain precondition.
dst_serial="$(lsblk -dn -o SERIAL "$DST_DEV" | xargs)"
[[ "$dst_serial" == PAW-DST-123456 ]] || fail lab_target_blank "refusing to wipe unexpected target serial '${dst_serial:-none}'"
wipefs -a "$DST_DEV" >"$PAW_LOG_DIR/target-blank.log" 2>&1 || fail lab_target_blank 'wipefs could not clear the disposable target'
step lab_target_blank PASS "device=$DST_DEV serial=$dst_serial wipefs=all signatures removed; virtual lab precondition only"
copy_out

# Pick the largest ext4 partition (the Ubuntu root), not the last ext4
# partition: cloud images also carry a small XBOOTLDR/ESP.  Prefer the
# cloudimg-rootfs label when present so a reordered disk cannot mislead us.
src_root="$(lsblk -b -nrpo NAME,FSTYPE,SIZE,LABEL "$SRC_DEV" | awk '$2=="ext4" && $4=="cloudimg-rootfs"{print $1; exit}')"
if [[ -z "$src_root" ]]; then
  src_root="$(lsblk -b -nrpo NAME,FSTYPE,SIZE "$SRC_DEV" | awk '$2=="ext4"{if($3>max){max=$3; dev=$1}} END{print dev}')"
fi
[[ -n "$src_root" ]] || fail source_os 'no ext4 root partition on source disk'
mkdir -p /mnt/paw-source
mount -o ro "$src_root" /mnt/paw-source || fail source_os "cannot mount $src_root read-only"
# The release name lives in /etc/os-release, which cloud images commonly make a
# symlink to /usr/lib/os-release.  Read both paths and record which one was
# used; a broken symlink must not silently become an empty "VERSION_ID=".
source_os_file=''
source_pretty=''
source_version=''
for candidate in /mnt/paw-source/etc/os-release /mnt/paw-source/usr/lib/os-release; do
  # shellcheck disable=SC1090 # path is one of the two fixed os-release locations
  if [[ -r "$candidate" ]]; then
    source_os_file="$candidate"
    source_pretty="$(. "$candidate" 2>/dev/null; printf '%s' "${PRETTY_NAME:-}")"
    source_version="$(. "$candidate" 2>/dev/null; printf '%s' "${VERSION_ID:-}")"
    [[ -n "$source_version" ]] && break
  fi
done
# Ubuntu cloud images keep /boot on a separate ext4 partition.  Mount it when
# present; looking only inside the root partition would falsely report a
# missing kernel even though the source system is complete.
src_boot="$(lsblk -b -nrpo NAME,FSTYPE,SIZE,LABEL "$SRC_DEV" | awk '$2=="ext4" && $4=="BOOT"{print $1; exit}')"
[[ -n "$src_boot" ]] || src_boot="$(lsblk -b -nrpo NAME,FSTYPE,SIZE "$SRC_DEV" | awk '$2=="ext4" && $3<2000000000 && $3>200000000{if($3>max){max=$3; dev=$1}} END{print dev}')"
boot_prefix=/mnt/paw-source
if [[ -n "$src_boot" ]]; then
  mkdir -p /mnt/paw-source-boot
  mount -o ro "$src_boot" /mnt/paw-source-boot || fail source_os "cannot mount source boot partition $src_boot read-only"
  boot_prefix=/mnt/paw-source-boot
fi
source_kernel="$(find "$boot_prefix" -maxdepth 2 -type f -name 'vmlinuz-*' 2>/dev/null | sort | head -n1)"
source_kernel="${source_kernel##*/vmlinuz-}"
i915_src="$(find /mnt/paw-source/usr/lib/modules -name 'i915.ko*' 2>/dev/null | head -n1)"
r8169_src="$(find /mnt/paw-source/usr/lib/modules -name 'r8169.ko*' 2>/dev/null | head -n1)"
[[ -z "$src_boot" ]] || umount /mnt/paw-source-boot
umount /mnt/paw-source
[[ -n "$source_kernel" ]] || fail source_os 'source root/boot partition has no vmlinuz-* kernel'
[[ -n "$i915_src" && -n "$r8169_src" ]] || fail source_os 'source Ubuntu lacks i915/r8169 modules'
# A source whose os-release is missing or incomplete is not silently promoted to
# PASS.  The composite identity (root UUID, capacity, GPT layout, BIOS Boot and
# pinned SSH host key) is verified later by source_identity; until that check
# passes the chain continues with an explicit WARN and no version claim.
if [[ "$source_version" == 24.04 ]]; then
  step source_os PASS "pretty=$source_pretty version=$source_version os_release=$source_os_file kernel=$source_kernel boot_partition=${src_boot:-in_root} i915_module=yes r8169_module=yes read_only_mount=true"
else
  step source_os WARN "source os-release VERSION_ID='${source_version}' file='${source_os_file:-missing}'; version not claimed, deferring to composite source identity (root UUID/capacity/GPT/BIOS Boot/pinned host key) checked later; kernel=$source_kernel boot_partition=${src_boot:-in_root} i915_module=yes r8169_module=yes read_only_mount=true"
fi
copy_out


# 9p host share is optional evidence transport; the chain does not depend on it.
modprobe 9pnet_virtio 2>/dev/null || true
modprobe 9p 2>/dev/null || true
mount -t 9p -o trans=virtio,version=9p2000.L hostshare /mnt/paw3-host 2>/dev/null \
  && step evidence_transport PASS '9p hostshare mounted' \
  || step evidence_transport WARN '9p unavailable; evidence will be extracted from the guest image after poweroff'
copy_out

# ---------------------------------------------------------------------------
# Chinese console font gate: run the real production script in this boot and
# require a same-boot fbcon 16x16 PASS before any destructive path can open.
# ---------------------------------------------------------------------------
chvt 1 2>/dev/null || true
if ! PAW_CONSOLE_FONT_REPORT="$PAW_REPORT_DIR/console-font.json" \
     "$PAW_ROOT/scripts/paw-console-font.sh" >"$PAW_LOG_DIR/console-font.log" 2>&1; then
  tail -n 60 "$PAW_LOG_DIR/console-font.log" >&2 || true
  fail console_font 'paw-console-font.sh did not produce a PASS report'
fi
python3 - "$PAW_REPORT_DIR/console-font.json" <<'PY2' || fail console_font 'font report is not same-boot 16x16 fbcon PASS'
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
assert d.get("status")=="PASS", d.get("status")
assert d.get("mode")=="fbcon", d.get("mode")
assert d.get("boot_id")==open("/proc/sys/kernel/random/boot_id").read().strip()
PY2
step console_font PASS "mode=fbcon schema=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["schema"])' "$PAW_REPORT_DIR/console-font.json") tty=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["tty"])' "$PAW_REPORT_DIR/console-font.json")"
copy_out

# Loop-backed fault-injection suites run inside the guest before Rescue
# credentials are created.  They write placeholder /run/paw-network files, so
# they must never run after the real RAM-only endpoint/key exist.
selftest_out=/mnt/paw3-host/prehw-selftests
if ! mountpoint -q /mnt/paw3-host; then
  step fault_injection WARN "9p hostshare is unavailable; in-guest fault suites not run"
elif PAW_SELFTEST_OUT="$selftest_out" bash "$PAW_ROOT/tests/prehardware/run-selftests.sh" 2>&1 | tee "$PAW_LOG_DIR/prehw-selftests.log"; then
  step fault_injection PASS "run-virtual-tests.sh and run-network-virtual-tests.sh completed inside guest; reports in $selftest_out"
else
  step fault_injection FAIL "one or more in-guest fault-injection suites failed; see $selftest_out"
fi
copy_out

# ---------------------------------------------------------------------------
# Rescue SSH: real sshd on loopback, source disk attached to this guest.
# ---------------------------------------------------------------------------
mkdir -p /run/sshd /run/paw-network
chmod 0700 /run/paw-network
if [[ ! -s /run/paw-network/ssh_host_ed25519_key ]]; then
  ssh-keygen -q -t ed25519 -N '' -C paw-stage3-loopback -f /run/paw-network/ssh_host_ed25519_key
fi
chmod 0600 /run/paw-network/ssh_host_ed25519_key
: >/run/paw-network/authorized_keys
chmod 0600 /run/paw-network/authorized_keys
mkdir -p /run/sshd
/usr/sbin/sshd -p 2222 \
  -h /run/paw-network/ssh_host_ed25519_key \
  -o PidFile=/run/paw-network/sshd.pid \
  -o AuthorizedKeysFile=/run/paw-network/authorized_keys \
  -o PermitRootLogin=yes \
  -o PasswordAuthentication=no \
  -o KbdInteractiveAuthentication=no \
  -o UsePAM=no \
  -o StrictModes=no \
  -o AllowTcpForwarding=no \
  -o X11Forwarding=no
for _ in $(seq 1 30); do
  [[ -s /run/paw-network/sshd.pid ]] && ss -ltn 2>/dev/null | grep -q ':2222 ' && break
  sleep 0.2
done
step rescue_sshd PASS 'real OpenSSH server on 127.0.0.1:2222; source disk is local loopback, not a public network path'

host_fp="$(ssh-keyscan -T 8 -p 2222 -t ed25519 127.0.0.1 2>/dev/null \
  | ssh-keygen -lf - -E sha256 2>/dev/null | awk 'NR==1{print $2}')"
[[ "$host_fp" == SHA256:* ]] || fail rescue_key 'could not derive loopback SSH host fingerprint'
printf '127.0.0.1\n2222\n%s\n' "$host_fp" \
  | "$PAW_ROOT/scripts/paw-rescue-key-prepare.sh" >"$PAW_LOG_DIR/rescue-key.log" 2>&1
rc=$?
if ((rc != 0)); then
  tail -n 40 "$PAW_LOG_DIR/rescue-key.log" >&2 || true
  fail rescue_key "paw-rescue-key-prepare.sh exit=$rc"
fi
install -m 0600 /run/paw-network/rescue_ed25519.pub /run/paw-network/authorized_keys
step rescue_key PASS "pinned_host_fingerprint=$host_fp key_is_ram_only=true"
copy_out

# Verify the real SSH transport before any identity query.
if ! bash -c 'source "$PAW_ROOT/scripts/paw-lib.sh"; rescue_ssh "id -u; hostname"' >"$PAW_LOG_DIR/rescue-ssh-probe.log" 2>&1; then
  cat "$PAW_LOG_DIR/rescue-ssh-probe.log" >&2 || true
  fail rescue_ssh 'authenticated loopback SSH probe failed'
fi
grep -qx '0' "$PAW_LOG_DIR/rescue-ssh-probe.log" || fail rescue_ssh 'remote uid is not 0'
step rescue_ssh PASS 'authenticated root SSH over 127.0.0.1:2222; transport_class=loopback_not_public'
copy_out

# ---------------------------------------------------------------------------
# Source identity: P0-3 composite check and fail-closed negative case.
# ---------------------------------------------------------------------------
[[ -b "$SRC_DEV" ]] || fail source_presence "$SRC_DEV is not a block device"
root_uuid="$(lsblk -b -nrpo NAME,FSTYPE,SIZE,PARTN "$SRC_DEV" \
  | awk '$2=="ext4"{print $4" "$1" "$3}' | sort -k3 -n | tail -n1 | awk '{print $2}')"
[[ -n "$root_uuid" ]] || fail source_presence 'no ext4 root partition on source disk'
root_uuid="$(blkid -s UUID -o value "$root_uuid")"
[[ "$root_uuid" =~ ^[0-9a-fA-F-]{36}$ ]] || fail source_presence 'source root UUID unreadable'
PAW_EXPECTED_SOURCE_BYTES="$(blockdev --getsize64 "$SRC_DEV")"
export PAW_EXPECTED_SOURCE_BYTES

# Negative: a UUID that does not exist must stop with no source registration.
rm -f "$PAW_CONFIG_DIR/source.json" /run/paw-network/source-discovery-session.json
if PAW_EXPECTED_ROOT_UUID=00000000-0000-0000-0000-000000000000 \
  "$PAW_ROOT/scripts/paw-source-discovery.sh" >"$PAW_LOG_DIR/source-negative.log" 2>&1; then
  fail source_identity_negative 'bogus UUID was accepted'
fi
[[ ! -e "$PAW_CONFIG_DIR/source.json" ]] || fail source_identity_negative 'negative case wrote source.json'
grep -Eqi 'UUID|match|identity|BLOCKED|ERROR' "$PAW_LOG_DIR/source-negative.log" \
  || fail source_identity_negative 'negative case produced no diagnostic'
step source_identity_negative PASS 'bogus UUID stopped with no source registration; fail-closed'
copy_out

# Positive: the enrolled UUID plus capacity/GPT/BIOS-Boot/host-key composite.
PAW_EXPECTED_ROOT_UUID="$root_uuid" "$PAW_ROOT/scripts/paw-source-discovery.sh" \
  >"$PAW_LOG_DIR/source-positive.log" 2>&1
rc=$?
if ((rc != 0)); then
  tail -n 80 "$PAW_LOG_DIR/source-positive.log" >&2 || true
  fail source_identity "paw-source-discovery.sh exit=$rc uuid=$root_uuid"
fi
python3 - "$PAW_CONFIG_DIR/source.json" "$PAW_REPORT_DIR/source-discovery.json" <<'PY' || fail source_identity 'composite identity evidence invalid'
import json,sys,re
cfg=json.load(open(sys.argv[1],encoding="utf-8")); rep=json.load(open(sys.argv[2],encoding="utf-8"))
assert cfg.get("source_mode")=="rescue"
assert re.fullmatch(r"[0-9a-f]{64}",str(cfg.get("composite_identity_sha256") or ""))
assert str(cfg.get("ssh_host_key_fingerprint") or "").startswith("SHA256:")
assert rep.get("status")=="PASS"
assert rep.get("machine_verified_layout") is True
PY
step source_identity PASS "root_uuid=$(cat "$PAW_CONFIG_DIR/source.json" | python3 -c 'import json,sys;print(json.load(sys.stdin)["root_uuid"])') composite=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["composite_identity_sha256"])' "$PAW_CONFIG_DIR/source.json")"
copy_out

# ---------------------------------------------------------------------------
# PAWDATA: real append/format/mount on the virtual writable live medium.
# The medium is attached as a removable SCSI disk carrying the release ISO
# plus free space; /run/live/medium is mounted exactly as live-boot does.
# ---------------------------------------------------------------------------
[[ -b "$MEDIA_DEV" ]] || fail pawdata "$MEDIA_DEV is not a block device"
media_ro="$(blockdev --getro "$MEDIA_DEV" 2>/dev/null || echo unknown)"
media_state="$(lsblk -dn -o NAME,RM,RO,TRAN,SERIAL,SIZE "$MEDIA_DEV" 2>&1 | tr '\n' ';')"
media_mount_source="$(findmnt -n -o SOURCE --target /run/live/medium 2>/dev/null || true)"
printf '%s\n' "PAW_MEDIA_PRECHECK device=$MEDIA_DEV ro=$media_ro state=$media_state live_medium_source=$media_mount_source" >>"$PAW_LOG_DIR/pawdata-media-precheck.log"
[[ "$media_ro" == 0 ]] || fail pawdata "USB live media is read-only (blockdev --getro=$media_ro); refusing PAWDATA before any write"
install -d /run/live/medium
if ! mountpoint -q /run/live/medium; then
  mount -o ro "${MEDIA_DEV}1" /run/live/medium 2>"$PAW_LOG_DIR/media-mount.log" \
    || mount -o ro "$MEDIA_DEV" /run/live/medium 2>>"$PAW_LOG_DIR/media-mount.log" \
    || { cat "$PAW_LOG_DIR/media-mount.log" >&2; fail pawdata 'could not mount virtual live medium'; }
fi
chvt 1 2>/dev/null || true
# Start the UI first and announce the prompt only after paw_tty_open and the
# serial-suffix read loop are ready.  Keys injected at process start were
# otherwise cleared by terminal setup (same race as the final confirmation UI).
rm -f "$PAW_REPORT_DIR/data-init.json"
PAW_INTERACTIVE_TTY=/dev/tty1 PAW_INPUT_TIMEOUT=180 \
  PAW_TEST_MODE=1 PAW_LIVE_DISK_OVERRIDE="$MEDIA_DEV" \
  PAW_DATA_MEDIA_OVERRIDE=I_HAVE_VERIFIED_LIVE_MEDIA \
  "$PAW_ROOT/scripts/paw-data-prepare.sh" auto >"$PAW_LOG_DIR/pawdata.log" 2>&1 &
pawdata_pid=$!
pawdata_prompted=0
for _ in $(seq 1 300); do
  if grep -q '"PAW-TTY1-PROMPT"' "$PAW_REPORT_DIR/data-init.json" 2>/dev/null; then
    pawdata_prompted=1
    break
  fi
  # A healthy pre-existing PAWDATA deliberately skips the suffix prompt.  Stop
  # waiting as soon as the UI exits instead of typing into a dead prompt.
  kill -0 "$pawdata_pid" 2>/dev/null || break
  sleep 0.2
done
if ((pawdata_prompted)); then
  prompt pawdata_serial_suffix
else
  say 'PAWDATA already initialized; no serial-suffix prompt was needed'
fi
wait "$pawdata_pid"; rc=$?
if ((rc != 0)); then
  tail -n 80 "$PAW_LOG_DIR/pawdata.log" >&2 || true
  fail pawdata "paw-data-prepare.sh exit=$rc"
fi
grep -q '"status": "PASS"' "$PAW_REPORT_DIR/paw-data-health.json" || fail pawdata 'PAWDATA health report is not PASS'
# Persistence token: written only on the first boot, read back by a separate
# reboot-to-USB acceptance pass.  It lives on the PAWDATA ext4 partition, not
# in the volatile live tmpfs.
token=/var/lib/paw-migration/.paw-persistence-token
if [[ ! -s "$token" ]]; then
  printf 'created_at=%s boot_id=%s media_serial=%s\n' "$(date -u +%FT%TZ)" "$(cat /proc/sys/kernel/random/boot_id)" "$MEDIA_SERIAL" >"$token"
  sync
fi
token_sha="$(sha256sum "$token" | awk '{print $1}')"
step pawdata PASS "disk=$MEDIA_DEV serial=$MEDIA_SERIAL token=$token token_sha256=$token_sha persistence_token_created_or_reused=true"
copy_out

# ---------------------------------------------------------------------------
# Target enrollment, operator memory attestation, hardware preflight.
# ---------------------------------------------------------------------------
[[ -b "$DST_DEV" ]] || fail target_enrollment "$DST_DEV is not a block device"
target_index="$(python3 - "$DST_DEV" <<'PY'
import json,subprocess,sys
want=sys.argv[1]
d=json.loads(subprocess.check_output(["lsblk","--json","--bytes","--output","NAME,PATH,TYPE,SIZE,MODEL,SERIAL,RM,MOUNTPOINTS"],text=True))
items=[]
for x in d.get("blockdevices",[]):
    p=x.get("path") or "/dev/"+str(x.get("name",""))
    if x.get("type")!="disk": continue
    if str(x.get("rm","0"))=="1" or not x.get("serial") or int(x.get("size") or 0)<=0: continue
    if any(m for c in x.get("children") or [] for m in c.get("mountpoints") or [] if m): continue
    items.append(p)
print(items.index(want)+1)
PY
)" || fail target_enrollment 'target is not in the eligible non-removable disk list'
target_serial="$(lsblk -dn -o SERIAL "$DST_DEV" | xargs)"
[[ -n "$target_serial" ]] || fail target_enrollment 'target serial is empty'
printf '%s\n%s\n' "$target_index" "${target_serial: -6}" \
  | "$PAW_ROOT/scripts/paw-target-discovery.sh" >"$PAW_LOG_DIR/target-discovery.log" 2>&1
rc=$?
if ((rc != 0)); then
  tail -n 60 "$PAW_LOG_DIR/target-discovery.log" >&2 || true
  fail target_enrollment "paw-target-discovery.sh exit=$rc"
fi
grep -q '"approved":True' "$PAW_CONFIG_DIR/target-ssd.json" || grep -q '"approved": true' "$PAW_CONFIG_DIR/target-ssd.json" \
  || fail target_enrollment 'target not approved'
step target_enrollment PASS "device=$DST_DEV serial=$target_serial capacity=$(blockdev --getsize64 "$DST_DEV")"
copy_out

printf '1\n1\n0\n确认\n' | "$PAW_ROOT/scripts/paw-memtest-confirm.sh" >"$PAW_LOG_DIR/memtest.log" 2>&1
rc=$?
if ((rc != 0)); then
  tail -n 50 "$PAW_LOG_DIR/memtest.log" >&2 || true
  fail memtest "paw-memtest-confirm.sh exit=$rc"
fi
grep -q '"status": "OPERATOR_CONFIRMED"' "$PAW_REPORT_DIR/memory-test.json" || fail memtest 'memory test status is not OPERATOR_CONFIRMED'
step memtest PASS 'operator attestation recorded; trust=operator_attestation_not_cryptographic'
copy_out

# Virtual hardware probe adapters.  QEMU virtio/SCSI disks do not expose
# physical SMART or thermal sensors.  These adapters are test-only, bounded,
# and every invocation is logged; the report is explicitly classified as
# virtual evidence and must never be used as a physical ASUS/SSD PASS.
hwbin=/run/paw3-hwbin
mkdir -p "$hwbin"
cat >"$hwbin/smartctl" <<'HW'
#!/usr/bin/env bash
echo "smartctl $*" >>/run/paw3-hw-adapter.log
args=" $* "
if [[ "$args" == *" -x "* ]]; then
  cat <<'TXT'
=== START OF INFORMATION SECTION ===
Device Model:     QEMU HARDDISK (PAW Stage 3 virtual probe adapter)
SMART support is: Available - device has SMART capability.
SMART support is: Enabled
=== START OF READ SMART DATA SECTION ===
SMART overall-health self-assessment test result: PASSED
Self-test execution status:      (   0) The previous self-test routine completed
TXT
elif [[ "$args" == *" -H "* ]]; then
  echo 'SMART overall-health self-assessment test result: PASSED'
elif [[ "$args" == *" -c "* ]]; then
  echo 'Self-test execution status:      (   0) The previous self-test routine completed'
  echo 'Short self-test routine recommended polling time: (   2) minutes.'
  echo 'Extended self-test routine recommended polling time: (  20) minutes.'
elif [[ "$args" == *" -t short "* ]]; then
  echo 'Testing has begun.'
elif [[ "$args" == *" -t long "* ]]; then
  echo 'Testing has begun.'
elif [[ "$args" == *" -l selftest "* ]]; then
  echo '# 1  Short offline       Completed without error       00%      1234         -'
else
  echo 'SMART support is: Available'
fi
exit 0
HW
cat >"$hwbin/badblocks" <<'HW'
#!/usr/bin/env bash
echo "badblocks $*" >>/run/paw3-hw-adapter.log
dev="${!#}"
exec 9<"$dev" || exit 1
bytes=$((64*1024*1024))
if ! dd if="$dev" of=/dev/null bs=1M count=64 status=none; then exit 1; fi
echo "PAW3_VIRTUAL_BOUNDED_READ bytes=$bytes device=$dev"
echo 'Pass completed, 0 bad blocks found. (0/0/0 errors)'
exit 0
HW
cat >"$hwbin/sensors" <<'HW'
#!/usr/bin/env bash
echo "sensors $*" >>/run/paw3-hw-adapter.log
cat <<'TXT'
qemu-virtual-isa-0000
Adapter: ISA adapter
CPU Temp:     +41.0°C  (high = +85.0°C, crit = +95.0°C)
TXT
HW
chmod 0755 "$hwbin"/*
: >/run/paw3-hw-adapter.log
command -v badblocks >/run/paw3-hw-badblocks-path.txt || true
if ! PATH="$hwbin:$PATH" PAW_SMART_POLL_SECONDS=1 PAW_READ_SCAN_LAST_BLOCK=65536 \
  "$PAW_ROOT/scripts/paw-hardware-preflight.sh" "$DST_DEV" >"$PAW_LOG_DIR/hardware.log" 2>&1; then
  tail -n 80 "$PAW_LOG_DIR/hardware.log" >&2 || true
  fail hardware "paw-hardware-preflight.sh exit=$?"
fi
python3 - "$PAW_REPORT_DIR/paw-hardware-health-report.json" <<'PY' || fail hardware 'could not classify hardware report'
import json,sys
p=sys.argv[1]; d=json.load(open(p,encoding="utf-8"))
d["evidence_class"]="qemu_virtual_probe_adapter"
d["physical_smart_verified"]=False
d["physical_thermal_sensors_verified"]=False
d["virtual_probe_notes"]="QEMU virtual disks expose no physical SMART/thermal sensors; SMART and sensors adapters are test-only and logged. badblocks performed a bounded 64 MiB real read."
json.dump(d,open(p,"w",encoding="utf-8"),indent=2)
PY
step hardware PASS 'virtual probe adapter PASS; physical SMART/thermal remain OPEN'
copy_out

# ---------------------------------------------------------------------------
# Network initialization in the QEMU user network.
# ---------------------------------------------------------------------------
if PAW_NETWORK_PHASE=RESCUE "$PAW_ROOT/scripts/paw-network-bootstrap.sh" >"$PAW_LOG_DIR/network.log" 2>&1; then
  step network PASS 'RESCUE phase direct network reachable from QEMU user networking'
else
  rc=$?
  tail -n 40 "$PAW_LOG_DIR/network.log" >&2 || true
  step network WARN "network bootstrap exit=$rc (local-link only; chain gates use source status)"
fi
copy_out

# ---------------------------------------------------------------------------
# Live controller readiness.  All destructive entry points consume this.
# ---------------------------------------------------------------------------
if ! "$PAW_ROOT/scripts/paw-live-controller.sh" >"$PAW_LOG_DIR/controller.log" 2>&1; then
  cat "$PAW_LOG_DIR/controller.log" >&2 || true
  fail readiness "paw-live-controller.sh exit=$?"
fi
python3 - "$PAW_REPORT_DIR/live-readiness.json" <<'PY' || fail readiness 'readiness is not READY_FOR_OPERATOR'
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
assert d.get("status")=="READY_FOR_OPERATOR", d
assert d.get("clone_started") is False
assert all(v=="PASS" for v in d["checks"].values()), d["checks"]
PY
step readiness PASS 'paw-live-controller.sh READY_FOR_OPERATOR'
copy_out

# ---------------------------------------------------------------------------
# Mixed-data zstd byte-count test (explicit random + zero + text payload).
# Separate state so it cannot contaminate the real migration receipts.
# ---------------------------------------------------------------------------
mixed="$state/mixed"; mkdir -p "$mixed"/{configs,reports,logs}
mkdir -p /opt/paw-migration/tests/virtual
if ! mountpoint -q /opt/paw-migration/tests/virtual; then
  mount -t tmpfs -o size=768m tmpfs /opt/paw-migration/tests/virtual 2>/dev/null || true
fi
python3 - /opt/paw-migration/tests/virtual/mixed-source.img <<'PY'
import os,sys
p=sys.argv[1]
if os.path.exists(p): raise SystemExit(0)
with open(p,"wb") as f:
    f.write(os.urandom(64*1024*1024))
    f.write(b"\0"*(128*1024*1024))
    block=(b"PAW Stage 3 mixed payload text line; UUID-free; checksum target.\n"*16384)[:1024*1024]
    for _ in range(64): f.write(block)
PY
truncate -s 268435456 /opt/paw-migration/tests/virtual/mixed-target.img
if ! PAW_SIMULATION=1 PAW_STATE_DIR="$mixed" PAW_CONFIG_DIR="$mixed/configs" \
  PAW_REPORT_DIR="$mixed/reports" PAW_LOG_DIR="$mixed/logs" \
  "$PAW_ROOT/scripts/paw-stream-clone.sh" \
  /opt/paw-migration/tests/virtual/mixed-source.img \
  /opt/paw-migration/tests/virtual/mixed-target.img >"$mixed/clone.log" 2>&1; then
  tail -n 50 "$mixed/clone.log" >&2 || true
  fail mixed_stream 'mixed-data simulation clone failed'
fi
if ! PAW_SIMULATION=1 PAW_STATE_DIR="$mixed" PAW_CONFIG_DIR="$mixed/configs" \
  PAW_REPORT_DIR="$mixed/reports" PAW_LOG_DIR="$mixed/logs" \
  "$PAW_ROOT/scripts/paw-stream-verify.sh" \
  /opt/paw-migration/tests/virtual/mixed-source.img \
  /opt/paw-migration/tests/virtual/mixed-target.img >"$mixed/verify.log" 2>&1; then
  tail -n 50 "$mixed/verify.log" >&2 || true
  fail mixed_stream 'mixed-data independent verify failed'
fi
python3 - "$mixed/reports/stream-transfer-report.json" "$mixed/reports/stream-verify.json" <<'PY' || fail mixed_stream 'mixed stream counts/hash invalid'
import json,sys
t=json.load(open(sys.argv[1],encoding="utf-8")); v=json.load(open(sys.argv[2],encoding="utf-8"))
assert t["source_bytes"]==268435456
assert t["restored_bytes"]==268435456
assert t["ssh_stream_bytes"]>0
assert t["status"]=="PASS" and t["independent_sha256_verified"] is True
assert v["status"]=="PASS" and v["bytes_verified"]==268435456
assert len(v["sha256"])==64
PY
cp -a "$mixed/reports" "$state/evidence-mixed"
step mixed_stream PASS 'source=restored=268435456 bytes; independent SHA256 PASS; payload=random+zeros+text'
copy_out

# ---------------------------------------------------------------------------
# Real SSH interruption negative case on a disposable loop target.
# ---------------------------------------------------------------------------
interrupt="$state/interrupt"; mkdir -p "$interrupt"/{configs,reports,logs}
cp "$PAW_CONFIG_DIR/source.json" "$interrupt/configs/source.json"
cp "$PAW_REPORT_DIR/source-discovery.json" "$interrupt/reports/source-discovery.json"
cp "$PAW_REPORT_DIR/console-font.json" "$interrupt/reports/console-font.json"
cp "$PAW_REPORT_DIR/paw-hardware-health-report.json" "$interrupt/reports/paw-hardware-health-report.json"
truncate -s "$src_bytes" "$state/interrupt-target.img"  # sparse; must be >= the source capacity
loop="$(losetup -f --show "$state/interrupt-target.img")"
cleanup_interrupt(){
  losetup -d "$loop" 2>/dev/null || true
  rm -f "$state/interrupt-target.img"
}
trap cleanup_interrupt EXIT
loop_serial="LOOP-INT-$(printf '%s' "$loop" | sha256sum | cut -c1-6)"
mkdir -p /run/paw3-intbin
cat >/run/paw3-intbin/lsblk <<'SH'
#!/usr/bin/env bash
last="${!#}"
if [[ " $* " == *" -o SERIAL "* && "$last" == "${PAW3_LOOP_DEV:-}" ]]; then printf '%s\n' "${PAW3_LOOP_SERIAL:-LOOP-INT}"; exit 0; fi
exec /usr/bin/lsblk "$@"
SH
chmod 0755 /run/paw3-intbin/lsblk
# Controlled transport interruption: the streaming ssh (the call that carries
# dd) is closed after three seconds.  Probe ssh calls are untouched.  This is
# a real local-loopback OpenSSH stream, not a mock pipe.
cat >/run/paw3-intbin/ssh <<'SH'
#!/usr/bin/env bash
case "$*" in
  *"dd if="*)
    echo "INT_SSH_STREAM_TIMEOUT $(date -u +%FT%TZ)" >>/run/paw3-intbin/ssh.log
    exec timeout --signal=TERM 3 /usr/bin/ssh "$@"
    ;;
  *) exec /usr/bin/ssh "$@" ;;
esac
SH
chmod 0755 /run/paw3-intbin/ssh
python3 - "$interrupt/configs/target-ssd.json" "$loop" "$loop_serial" <<'PY'
import json,subprocess,sys,datetime
p,dev,serial=sys.argv[1:]
cap=int(subprocess.check_output(["blockdev","--getsize64",dev],text=True).strip())
d={"approved":True,"device_path":dev,"model":"QEMU loop interrupt target","capacity_bytes":cap,"serial":serial,"registered_at":datetime.datetime.now(datetime.timezone.utc).isoformat()}
json.dump(d,open(p,"w",encoding="utf-8"),indent=2)
PY
python3 - "$interrupt/reports/operator-authorization.json" "$loop" "$loop_serial" "$interrupt/configs/source.json" <<'PY'
import json,sys,datetime,uuid
p,dev,serial,source_path=sys.argv[1:]
source=json.load(open(source_path,encoding="utf-8"))
now=datetime.datetime.now(datetime.timezone.utc)
json.dump({"status":"AUTHORIZED","migration_id":str(uuid.uuid4()),"authorization_id":str(uuid.uuid4()),
 "target_device":dev,"target_serial":serial,"target_serial_suffix":serial[-6:],
 "source_device":source.get("device_path"),"source_root_uuid":source.get("root_uuid"),
 "source_composite_identity_sha256":source.get("composite_identity_sha256"),
 "source_capacity_bytes":source.get("capacity_bytes"),
 "authorized_at":now.isoformat(),
 "expires_at":(now+datetime.timedelta(minutes=30)).isoformat()},open(p,"w",encoding="utf-8"),indent=2)
PY
PAW_STATE_DIR="$interrupt" PAW_CONFIG_DIR="$interrupt/configs" PAW_REPORT_DIR="$interrupt/reports"   python3 "$PAW_ROOT/scripts/paw-transaction.py" init   --transaction "$interrupt/reports/migration-transaction.json"   --authorization "$interrupt/reports/operator-authorization.json"   --source-config "$interrupt/configs/source.json"   --target-config "$interrupt/configs/target-ssd.json" >/dev/null   || fail ssh_interrupt 'could not initialize the interruption transaction'
(
  PATH="/run/paw3-intbin:$PATH" PAW3_LOOP_DEV="$loop" PAW3_LOOP_SERIAL="$loop_serial" \
  PAW_STATE_DIR="$interrupt" PAW_CONFIG_DIR="$interrupt/configs" \
  PAW_REPORT_DIR="$interrupt/reports" PAW_LOG_DIR="$interrupt/logs" \
  PAW_DESTRUCTIVE_ARM=I_HAVE_VERIFIED_THE_TARGET_SERIAL \
  "$PAW_ROOT/scripts/paw-stream-clone.sh" "$SRC_DEV" "$loop" \
  >"$interrupt/clone.log" 2>&1
) &
clone_pid=$!
# The injected ssh wrapper closes the streaming connection after three
# seconds.  Wait for the clone process to observe EOF and retain its marker.
sleep 5
wait "$clone_pid"; clone_rc=$?
if ((clone_rc == 0)); then
  fail ssh_interrupt 'interrupted SSH stream unexpectedly succeeded'
fi
if [[ ! -e "$interrupt/reports/CLONE-INCOMPLETE" ]]; then
  echo '--- interrupt clone log ---' >&2
  tail -n 120 "$interrupt/clone.log" >&2 || true
  echo '--- interrupt configs ---' >&2
  ls -l "$interrupt/configs" >&2 || true
  echo '--- interrupt reports ---' >&2
  ls -l "$interrupt/reports" >&2 || true
fi
[[ -e "$interrupt/reports/CLONE-INCOMPLETE" ]] || fail ssh_interrupt 'CLONE-INCOMPLETE marker missing'
step ssh_interrupt PASS "real SSH stream killed mid-flight; exit=$clone_rc; CLONE-INCOMPLETE retained"
cp -a "$interrupt/reports/CLONE-INCOMPLETE" "$state/evidence-clone-incomplete"
cleanup_interrupt
trap - EXIT
copy_out

# Discard any unread keyboard bytes left by a prompt that an earlier step
# skipped (for example PAWDATA already initialized).  Stale input must never
# be able to satisfy a later destructive authorization prompt.
flush_tty_input(){
  python3 - <<'PY'
import os,termios
fd=os.open('/dev/tty1', os.O_RDWR | os.O_NONBLOCK)
try:
    termios.tcflush(fd, termios.TCIFLUSH)
finally:
    os.close(fd)
PY
}

# ---------------------------------------------------------------------------
# Final authorization UI: wrong serial must stop, correct serial must proceed.
# ---------------------------------------------------------------------------
target_before="$(head -c 1048576 "$DST_DEV" | sha256sum | awk '{print $1}')"
chvt 1 2>/dev/null || true
flush_tty_input
# Start the UI first and announce the prompt only when the read loop has had
# time to open tty1; keys injected at the same instant as process start were
# otherwise cleared by terminal setup.
rm -f "$PAW_REPORT_DIR/final-confirm.json"
PAW_INTERACTIVE_TTY=/dev/tty1 PAW_INPUT_TIMEOUT=180 \
  "$PAW_ROOT/scripts/paw-final-confirm.sh" >"$PAW_LOG_DIR/final-wrong.log" 2>&1 &
wrong_pid=$!
for _ in $(seq 1 300); do
  grep -q '"PAW-TTY1-FINAL-PROMPT"' "$PAW_REPORT_DIR/final-confirm.json" 2>/dev/null && break
  sleep 0.2
done
prompt final_wrong_serial
wait "$wrong_pid"; rc=$?
if ((rc == 0)); then
  fail final_authorization_wrong 'wrong serial was accepted'
fi
[[ ! -e "$PAW_REPORT_DIR/operator-authorization.json" ]] || fail final_authorization_wrong 'wrong serial wrote an authorization receipt'
target_after="$(head -c 1048576 "$DST_DEV" | sha256sum | awk '{print $1}')"
[[ "$target_before" == "$target_after" ]] || fail final_authorization_wrong 'target changed during wrong-serial rejection'
step final_authorization_wrong PASS "exit=$rc no authorization; target first 1 MiB unchanged"
copy_out

# ---------------------------------------------------------------------------
# Pipeline evidence watcher.  paw-final-confirm.sh owns the destructive
# orchestration and calls the real project entry points in order.  The watcher
# only observes the atomic reports those entry points write and mirrors each
# completed step onto the serial console; it never invokes or replaces a gate.
# ---------------------------------------------------------------------------
step_once(){
  local name="$1" status="$2" detail="${3:-}"
  [[ -e "/run/paw3-step-$name" ]] && return 0
  : >"/run/paw3-step-$name"
  step "$name" "$status" "$detail"
}

scan_pipeline(){
  if [[ -s "$PAW_REPORT_DIR/operator-authorization.json" ]]; then
    local auth_fields
    auth_fields="$(python3 - "$PAW_REPORT_DIR/operator-authorization.json" <<'PY' 2>/dev/null || true
import json,sys
try: d=json.load(open(sys.argv[1],encoding="utf-8"))
except Exception: raise SystemExit(0)
if d.get("status")=="AUTHORIZED":
    print("\t".join(str(d.get(k,"")) for k in ("target_device","target_serial","expires_at")))
PY
)"
    if [[ -n "$auth_fields" ]]; then
      IFS=$'\t' read -r auth_dev auth_serial auth_expires <<<"$auth_fields"
      step_once final_authorization_correct PASS "exit=0 authorization=AUTHORIZED target=$auth_dev serial=$auth_serial expires=$auth_expires; source and target re-identified before the write"
    fi
  fi
  if [[ -s "$PAW_REPORT_DIR/stream-transfer-report.json" ]]; then
    local t_fields
    t_fields="$(python3 - "$PAW_REPORT_DIR/stream-transfer-report.json" <<'PY' 2>/dev/null || true
import json,sys
try: d=json.load(open(sys.argv[1],encoding="utf-8"))
except Exception: raise SystemExit(0)
if d.get("status") in ("STREAM_COMPLETE_UNVERIFIED","PASS"):
    ratio=d.get("compression_reduction_percent")
    print("\t".join([d.get("status",""),str(d.get("source_bytes","")),str(d.get("ssh_stream_bytes","")),str(d.get("restored_bytes","")),str(d.get("stream_mode","")),("%.1f"%ratio if isinstance(ratio,(int,float)) else "n/a")]))
PY
)"
    if [[ -n "$t_fields" ]]; then
      IFS=$'\t' read -r t_status t_src t_wire t_restored t_mode t_ratio <<<"$t_fields"
      step_once compressed_transfer PASS "status=$t_status mode=$t_mode source_bytes=$t_src payload_bytes=$t_wire restored_bytes=$t_restored compression_reduction=${t_ratio}%"
      step_once clone_complete PASS "restored_bytes=$t_restored; target byte range written; independent SHA256 still pending"
    fi
  fi
  if [[ -s "$PAW_REPORT_DIR/stream-verify.json" ]]; then
    local v_fields
    v_fields="$(python3 - "$PAW_REPORT_DIR/stream-verify.json" <<'PY' 2>/dev/null || true
import json,sys
try: d=json.load(open(sys.argv[1],encoding="utf-8"))
except Exception: raise SystemExit(0)
if d.get("status")=="PASS" and d.get("independent_sha256_verified") is True:
    print("\t".join([str(d.get("sha256","")),str(d.get("bytes_verified",""))]))
PY
)"
    if [[ -n "$v_fields" ]]; then
      IFS=$'\t' read -r v_sha v_bytes <<<"$v_fields"
      step_once sha256_verify PASS "sha256=$v_sha bytes_verified=$v_bytes independent_sha256_verified=true; CLONE-INCOMPLETE cleared"
    fi
  fi
  if [[ -s "$PAW_REPORT_DIR/offline-repair.json" ]]; then
    local r_status r_grub r_pin
    r_status="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1],encoding="utf-8")).get("status",""))' "$PAW_REPORT_DIR/offline-repair.json" 2>/dev/null || true)"
    r_grub="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1],encoding="utf-8")).get("grub_install_device",""))' "$PAW_REPORT_DIR/offline-repair.json" 2>/dev/null || true)"
    r_pin="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1],encoding="utf-8")).get("grub_debconf_pinned",""))' "$PAW_REPORT_DIR/offline-repair.json" 2>/dev/null || true)"
    if [[ "$r_status" == PASS && "$r_grub" == /dev/disk/by-id/* ]]; then
      step_once offline_repair PASS "offline-repair.json status=PASS; grub_install_device=$r_grub grub_debconf_pinned=$r_pin; configs backed up before adaptation"
    elif [[ "$r_status" == PASS ]]; then
      fail offline_repair "status=PASS but GRUB was installed to non-stable device '$r_grub'"
    fi
  fi
  if [[ -s "$PAW_REPORT_DIR/gpt-expand.json" ]]; then
    local g_fields
    g_fields="$(python3 - "$PAW_REPORT_DIR/gpt-expand.json" <<'PY' 2>/dev/null || true
import json,sys
try: d=json.load(open(sys.argv[1],encoding="utf-8"))
except Exception: raise SystemExit(0)
if d.get("status")=="PASS":
    print("\t".join([str(d.get("partition","")),str(d.get("before_bytes","")),str(d.get("after_bytes","")),str(d.get("grew",""))]))
PY
)"
    if [[ -n "$g_fields" ]]; then
      IFS=$'\t' read -r g_part g_before g_after g_grew <<<"$g_fields"
      step_once gpt_expand PASS "partition=$g_part before_bytes=$g_before after_bytes=$g_after grew=$g_grew; GPT backup header moved"
    fi
  fi
  if [[ -s "$PAW_REPORT_DIR/preboot-handoff.json" ]]; then
    local f_status f_phase
    f_status="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1],encoding="utf-8")).get("status",""))' "$PAW_REPORT_DIR/preboot-handoff.json" 2>/dev/null || true)"
    f_phase="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1],encoding="utf-8")).get("phase",""))' "$PAW_REPORT_DIR/preboot-handoff.json" 2>/dev/null || true)"
    [[ "$f_status" == PASS && "$f_phase" == pre_reboot ]] && step_once preboot_handoff PASS "preboot-handoff.json status=PASS phase=pre_reboot; no first-boot claim"
  fi
  if [[ -s "$PAW_REPORT_DIR/reboot-status.json" ]]; then
    local b_fields
    b_fields="$(python3 - "$PAW_REPORT_DIR/reboot-status.json" <<'PY' 2>/dev/null || true
import json,sys
try: d=json.load(open(sys.argv[1],encoding="utf-8"))
except Exception: raise SystemExit(0)
if d.get("status")=="PASS" and d.get("reboot_invoked") is True:
    print("\t".join([str(d.get("status","")),str(d.get("reboot_command","")),str(d.get("dry_run",""))]))
PY
)"
    if [[ -n "$b_fields" ]]; then
      IFS=$'\t' read -r b_status b_cmd b_dry <<<"$b_fields"
      step_once auto_reboot PASS "reboot status=$b_status invoked=true command=$b_cmd dry_run=$b_dry"
      # Finalizer persists PASS before issuing reboot and then waits for this
      # handoff.  Emit the chain PASS and copy reports first, so a real QEMU
      # reset cannot cut the result marker off the serial log.
      if [[ -n ${PAW_REBOOT_HANDOFF_FILE:-} && ! -e $PAW_REBOOT_HANDOFF_FILE ]]; then
        say 'PAW3_CHAIN_RESULT=PASS'
        copy_out
        sync || true
        : >"$PAW_REBOOT_HANDOFF_FILE"
      fi
    fi
  fi
}

pipeline_watch(){
  while :; do
    scan_pipeline
    sleep 3
  done
}


chvt 1 2>/dev/null || true
flush_tty_input
# No bootindex rewriting: the USB medium is physically removed at the end and
# the target is the next bootable AHCI disk.
rm -f "$PAW_REPORT_DIR/final-confirm.json" /run/paw3-step-* "${PAW_REBOOT_HANDOFF_FILE:-/run/paw3-chain-pass}"
pipeline_watch &
watch_pid=$!
PAW_INTERACTIVE_TTY=/dev/tty1 PAW_INPUT_TIMEOUT=240 \
  PAW_DESTRUCTIVE_ARM=I_HAVE_VERIFIED_THE_TARGET_SERIAL \
  PAW_REPAIR_ARM=I_HAVE_VERIFIED_OFFLINE_FILESYSTEM \
  PAW_EXPAND_ARM=I_HAVE_VERIFIED_CLONE \
  PAW_REBOOT_HANDOFF_FILE=/run/paw3-chain-pass \
  "$PAW_ROOT/scripts/paw-final-confirm.sh" >"$PAW_LOG_DIR/final-correct.log" 2>&1 &
correct_pid=$!
for _ in $(seq 1 300); do
  grep -q '"PAW-TTY1-FINAL-PROMPT"' "$PAW_REPORT_DIR/final-confirm.json" 2>/dev/null && break
  sleep 0.2
done
prompt final_correct_serial
wait "$correct_pid"; rc=$?
kill "$watch_pid" 2>/dev/null || true
wait "$watch_pid" 2>/dev/null || true
if ((rc != 0)); then
  tail -n 120 "$PAW_LOG_DIR/final-correct.log" >&2 || true
  fail final_authorization_correct "paw-final-confirm.sh exit=$rc"
fi
# One final observation pass closes the small window between the last report
# write and the watcher being stopped.
scan_pipeline
for required in final_authorization_correct compressed_transfer clone_complete \
                sha256_verify offline_repair gpt_expand preboot_handoff; do
  [[ -e "/run/paw3-step-$required" ]] || {
    tail -n 160 "$PAW_LOG_DIR/final-correct.log" >&2 || true
    fail final_authorization_correct "pipeline returned success but $required has no PASS evidence"
  }
done
copy_out

# The finalizer issues a real systemctl reboot inside the QEMU guest.  QEMU
# resets and SeaBIOS boots the cloned target (bootindex 0).  The auto_reboot
# line is already emitted by the watcher when reboot-status.json says PASS and
# reboot_invoked=true; the host independently confirms the reset by observing
# the cloned Ubuntu login prompt on the serial console.
say 'PAW3_CHAIN_RESULT=PASS'
copy_out
sleep 2
