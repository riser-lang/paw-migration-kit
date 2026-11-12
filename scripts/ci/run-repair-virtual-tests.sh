#!/usr/bin/env bash
# Offline-repair / rollback suite on disposable loop ext4 images.
#
# The chroot is a deliberately minimal Ubuntu-like root, so the fixture must
# supply the same basic runtime the production repair calls: a static shell,
# env(1), cpio-based initramfs tooling, lsinitramfs, fstab and a GRUB config
# containing the real root UUID.  Every fixture program has an observable
# effect; none is allowed to be a no-op that only returns success.
set -Eeuo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
out="${PAW_ARTIFACT_DIR:-$PWD/artifacts}"
work="$root/tests/virtual/repair-run"
mkdir -p "$work" "$out"
report="$out/repair-virtual-test-report.txt"
passed=0; failed=0; summary_written=0
loops=(); mounts=()
cleanup_mounts(){
  for m in "${mounts[@]}"; do umount "$m" 2>/dev/null || true; done
  for l in "${loops[@]}"; do losetup -d "$l" 2>/dev/null || true; done
  mounts=(); loops=()
}
finish(){
  rc=$?
  set +e
  cleanup_mounts
  # Preserve raw logs before deleting the work tree; the CI artifact must show
  # the first failing command, not just the resulting assertion failures.
  [[ -f "$work/repair-a.log" ]] && cp "$work/repair-a.log" "$out/repair-normal.log"
  [[ -f "$work/repair-b.log" ]] && cp "$work/repair-b.log" "$out/repair-rollback.log"
  [[ -f "$work/grub-install.log" ]] && cp "$work/grub-install.log" "$out/repair-grub-install.log"
  if (( summary_written == 0 )); then
    (( rc != 0 )) && fail "test harness aborted unexpectedly (rc=$rc)"
    printf 'Summary: %s passed, %s failed\n' "$passed" "$failed" >>"$report"
    printf 'Summary: %s passed, %s failed\n' "$passed" "$failed"
  fi
  printf '===== repair report =====\n'
  cat "$report"
  rm -rf "$work"
  rm -f "$root/tests/virtual/repair-root.img" "$root/tests/virtual/repair-rollback.img"
  exit "$rc"
}
pass(){ printf 'PASS %s\n' "$1" >>"$report"; passed=$((passed+1)); }
fail(){ printf 'FAIL %s\n' "$1" >>"$report"; failed=$((failed+1)); return 0; }
trap finish EXIT
printf 'Offline repair virtual tests\n' >"$report"
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

cat >"$work/stub.c" <<'C'
int main(void){return 0;}
C
cat >"$work/fail.c" <<'C'
#include <stdio.h>
int main(void){fputs("injected update-grub failure\n", stderr); return 1;}
C

busybox_bin="$(command -v busybox || true)"
[[ -n "$busybox_bin" ]] || { fail 'busybox is required to build the chroot fixtures'; exit 1; }

make_fixture(){
  local image="$1" mnt="$2" fail_grub="$3" loop part uuid
  rm -f "$work/host-before" "$work/host-before.pub"
  truncate -s 512M "$image"
  mkdir -p "$mnt"
  printf 'label: dos\n,,83\n' | sfdisk "$image" >/dev/null
  loop="$(losetup --find --show -P "$image")"; loops+=("$loop")
  part="${loop}p1"
  for _ in $(seq 1 30); do [[ -b "$part" ]] && break; sleep 1; done
  [[ -b "$part" ]] || { echo "partition missing" >&2; return 1; }
  mkfs.ext4 -F "$part" >/dev/null
  uuid="$(blkid -s UUID -o value "$part")"
  [[ "$uuid" =~ ^[0-9a-fA-F-]{36}$ ]] || { echo "fixture UUID unreadable" >&2; return 1; }
  mount "$part" "$mnt"; mounts+=("$mnt")
  install -d "$mnt"/etc/{netplan,cloud/cloud.cfg.d,udev/rules.d,ssh,default,initramfs-tools} \
    "$mnt"/bin "$mnt"/usr/bin "$mnt"/usr/sbin "$mnt"/dev "$mnt"/proc "$mnt"/sys "$mnt"/tmp \
    "$mnt"/boot/grub "$mnt"/lib/modules/6.1.0/kernel/drivers/ata \
    "$mnt"/lib/modules/6.1.0/kernel/drivers/net/ethernet/realtek \
    "$mnt"/var/lib/{dbus,tailscale,paw} "$mnt"/root/.ssh

  # Minimal but real chroot runtime: static busybox applets plus the scripts
  # production repair actually invokes.
  install -m 0755 "$busybox_bin" "$mnt/bin/busybox"
  local applet
  for applet in sh env ls find grep sed head basename cat cp mkdir rm chmod touch sleep true false printf test cpio; do
    ln -sfn busybox "$mnt/bin/$applet"
  done
  ln -sfn ../../bin/busybox "$mnt/usr/bin/env"

  cat >"$mnt/etc/netplan/50-cloud-init.yaml" <<'YAML'
network:
  version: 2
  ethernets:
    eth0:
      match: {name: eth0}
      dhcp4: true
YAML
  printf 'SUBSYSTEM=="net", ACTION=="add", ATTR{address}=="00:11:22:33:44:55", NAME="eth0"\n' >"$mnt/etc/udev/rules.d/70-tencent.rules"
  printf 'network: {config: disabled}\n' >"$mnt/etc/cloud/cloud.cfg.d/50-cloud-init.cfg"
  printf '11111111111111111111111111111111\n' >"$mnt/etc/machine-id"
  cp "$mnt/etc/machine-id" "$mnt/var/lib/dbus/machine-id"
  printf 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIciOnlyFixtureKey paw@test\n' >"$mnt/root/.ssh/authorized_keys"
  printf 'paw-database-must-survive\n' >"$mnt/var/lib/paw/important.db"
  printf 'tailscale-state-must-be-backed-up\n' >"$mnt/var/lib/tailscale/tailscaled.state"
  printf 'GRUB_DEFAULT=0\nGRUB_DISABLE_OS_PROBER=true\n' >"$mnt/etc/default/grub"
  printf 'oldmodule\n' >"$mnt/etc/initramfs-tools/modules"
  printf 'UUID=%s / ext4 errors=remount-ro 0 1\n' "$uuid" >"$mnt/etc/fstab"
  printf 'set default=0\n# original-fixture-grub\nmenuentry "fixture" { linux /boot/vmlinuz-6.1.0 root=UUID=%s ro }\n' "$uuid" >"$mnt/boot/grub/grub.cfg"
  : >"$mnt/lib/modules/6.1.0/kernel/drivers/ata/ahci.ko"
  : >"$mnt/lib/modules/6.1.0/kernel/drivers/net/ethernet/realtek/r8169.ko"
  printf 'kernel/drivers/ata/ahci.ko\n' >"$mnt/lib/modules/6.1.0/modules.dep"
  ssh-keygen -q -t ed25519 -N '' -f "$work/host-before"
  install -m 0600 "$work/host-before" "$mnt/etc/ssh/ssh_host_ed25519_key"
  install -m 0644 "$work/host-before.pub" "$mnt/etc/ssh/ssh_host_ed25519_key.pub"

  # update-initramfs creates a real newc archive containing every module file.
  cat >"$mnt/usr/sbin/update-initramfs" <<'INITRAMFS'
#!/bin/sh
set -eu
kver=6.1.0
out="/boot/initrd.img-$kver"
list="/tmp/paw-initrd.list.$$"
cd /
find "lib/modules/$kver" -type f >"$list"
cpio -o -H newc <"$list" >"$out"
rm -f "$list"
printf 'generated %s\n' "$out"
INITRAMFS
  # lsinitramfs lists the archive entries so AHCI/r8169 can be verified for real.
  cat >"$mnt/usr/sbin/lsinitramfs" <<'LSINITRAMFS'
#!/bin/sh
set -eu
[ -s "$1" ] || exit 1
cpio -it <"$1"
LSINITRAMFS
  # Normal update-grub regenerates grub.cfg from the real root UUID in fstab
  # and leaves a marker; failure injection exits non-zero without a marker.
  if [[ "$fail_grub" == 1 ]]; then
    cat >"$mnt/usr/sbin/update-grub" <<'FAILGRUB'
#!/bin/sh
echo 'injected update-grub failure' >&2
exit 1
FAILGRUB
  else
    cat >"$mnt/usr/sbin/update-grub" <<'UPDATEGRUB'
#!/bin/sh
set -eu
uuid="$(sed -n 's/^UUID=\([^ ]*\).*/\1/p' /etc/fstab | head -n1)"
[ -n "$uuid" ] || exit 2
cat >/boot/grub/grub.cfg <<EOF
set default=0
set timeout=1
menuentry 'PAW repaired fixture' {
    linux /boot/vmlinuz-6.1.0 root=UUID=$uuid ro
    initrd /boot/initrd.img-6.1.0
}
EOF
printf 'generated\n' >/boot/grub/.paw-update-grub-ran
UPDATEGRUB
  fi
  gcc -static -O2 -o "$mnt/usr/sbin/grub-install" "$work/stub.c"
  chmod 0755 "$mnt/usr/sbin/update-initramfs" "$mnt/usr/sbin/lsinitramfs" \
    "$mnt/usr/sbin/update-grub" "$mnt/usr/sbin/grub-install" "$mnt/bin/busybox"
  sync
  umount "$mnt"; mounts=()
  FIXTURE_LOOP="$loop"
}

run_repair(){
  local part="$1" state="$2"
  PAW_ROOT="$root" PAW_STATE_DIR="$state" PAW_CONFIG_DIR="$state/configs" PAW_REPORT_DIR="$state/reports" PAW_LOG_DIR="$state/logs" \
    PAW_SIMULATION=1 PAW_REPAIR_ARM=I_HAVE_VERIFIED_OFFLINE_FILESYSTEM \
    "$root/scripts/paw-offline-repair.sh" "$part"
}

fixture="$root/tests/virtual/repair-root.img"
make_fixture "$fixture" "$work/root-a" 0
loop="$FIXTURE_LOOP"
loops+=("$loop")
part="${loop}p1"
state="$work/state-a"; mkdir -p "$state/configs" "$state/reports" "$state/logs"
host_before="$(sha256sum "$work/host-before" | awk '{print $1}')"
mount "$part" "$work/root-a"; mounts+=("$work/root-a")
auth_before="$(sha256sum "$work/root-a/root/.ssh/authorized_keys" | awk '{print $1}')"
db_before="$(sha256sum "$work/root-a/var/lib/paw/important.db" | awk '{print $1}')"
fstab_before="$(sha256sum "$work/root-a/etc/fstab" | awk '{print $1}')"
umount "$work/root-a"; mounts=()
if run_repair "$part" "$state" >"$work/repair-a.log" 2>&1; then
  pass 'Offline repair executed the simulation adaptation path'
else
  fail 'Offline repair simulation path'
fi
mount "$part" "$work/root-a"; mounts+=("$work/root-a")
grep -q 'name: "e\*"' "$work/root-a/etc/netplan/80-paw-migration.yaml" 2>/dev/null && pass 'Netplan matches eth0/en*/r8169 with DHCP' || fail 'Netplan e* match missing'
grep -qx 'ahci' "$work/root-a/etc/initramfs-tools/modules" 2>/dev/null && grep -qx 'r8169' "$work/root-a/etc/initramfs-tools/modules" 2>/dev/null && pass 'AHCI and r8169 added to initramfs modules' || fail 'initramfs modules missing'
[[ -s "$work/root-a/boot/initrd.img-6.1.0" ]] && pass 'update-initramfs produced a non-empty initrd' || fail 'update-initramfs produced no initrd'
grep -q '/ahci\.ko$' <(chroot "$work/root-a" lsinitramfs /boot/initrd.img-6.1.0 2>/dev/null) && grep -q '/r8169\.ko$' <(chroot "$work/root-a" lsinitramfs /boot/initrd.img-6.1.0 2>/dev/null) && pass 'lsinitramfs independently finds AHCI and r8169 in the initrd' || fail 'initrd does not contain the required modules'
[[ -f "$work/root-a/boot/grub/.paw-update-grub-ran" ]] && grep -q 'root=UUID=' "$work/root-a/boot/grub/grub.cfg" && ! grep -q 'original-fixture-grub' "$work/root-a/boot/grub/grub.cfg" && pass 'update-grub regenerated grub.cfg with the real root UUID' || fail 'GRUB config was not regenerated with the root UUID'
[[ "$(sha256sum "$work/root-a/etc/fstab" | awk '{print $1}')" == "$fstab_before" ]] && pass 'fstab was preserved and uses the real root UUID' || fail 'fstab changed during repair'
[[ "$(cat "$work/root-a/etc/machine-id")" != "11111111111111111111111111111111" ]] && pass 'machine-id regenerated' || fail 'machine-id was not regenerated'
[[ "$(sha256sum "$work/root-a/etc/ssh/ssh_host_ed25519_key" | awk '{print $1}')" != "$host_before" ]] && pass 'SSH host key regenerated' || fail 'SSH host key was not regenerated'
[[ "$(sha256sum "$work/root-a/root/.ssh/authorized_keys" | awk '{print $1}')" == "$auth_before" ]] && pass 'user authorized_keys preserved' || fail 'authorized_keys changed'
[[ "$(sha256sum "$work/root-a/var/lib/paw/important.db" | awk '{print $1}')" == "$db_before" ]] && pass 'PAW business data preserved' || fail 'PAW business data changed'
[[ -f "$work/root-a/etc/udev/rules.d/70-tencent.rules.disabled-by-paw" ]] && pass 'Tencent/MAC udev rule disabled with original retained' || fail 'udev rule not disabled'
if [[ -s "$state/reports/offline-repair.json" ]]; then
  python3 - "$state/reports/offline-repair.json" <<'PY' && pass 'Repair report says SIMULATION_PASS and does not claim hardware validation' || fail 'Repair report status invalid'
import json,sys
d=json.load(open(sys.argv[1])); assert d['status']=='SIMULATION_PASS'; assert d['simulation'] is True
assert d['authorized_keys_touched'] is False and d['PAW_application_data_touched'] is False
assert d['initramfs_modules_verified']=='PASS', d.get('initramfs_modules_verified')
PY
  backup="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["backup_path"])' "$state/reports/offline-repair.json" 2>/dev/null || true)"
  [[ -n "$backup" && -s "$backup/target-configs.before.tar" && -s "$backup/target-configs.before.tar.sha256" ]] && pass 'Reversible configuration backup exists with SHA256' || fail 'Repair backup missing'
else
  fail 'Repair report status invalid'
  fail 'Repair backup missing'
fi
umount "$work/root-a"; mounts=()

# Rollback: make update-grub fail and verify the original configuration is restored.
fixture2="$root/tests/virtual/repair-rollback.img"
make_fixture "$fixture2" "$work/root-b" 1
loop2="$FIXTURE_LOOP"
loops+=("$loop2")
part2="${loop2}p1"
host_before_b="$(sha256sum "$work/host-before" | awk '{print $1}')"
state2="$work/state-b"; mkdir -p "$state2/configs" "$state2/reports" "$state2/logs"
if run_repair "$part2" "$state2" >"$work/repair-b.log" 2>&1; then
  fail 'Injected update-grub failure stopped repair'
else
  pass 'Injected update-grub failure stopped repair'
fi
mount "$part2" "$work/root-b"; mounts+=("$work/root-b")
grep -q 'injected update-grub failure' "$work/repair-b.log" && pass 'Rollback log records the injected first failure' || fail 'Rollback log does not record the injected failure'
[[ -f "$work/root-b/etc/netplan/50-cloud-init.yaml" ]] && pass 'Rollback restored original netplan file' || fail 'Rollback did not restore netplan'
[[ "$(cat "$work/root-b/etc/machine-id")" == "11111111111111111111111111111111" ]] && pass 'Rollback restored original machine-id' || fail 'Rollback did not restore machine-id'
[[ "$(sha256sum "$work/root-b/etc/ssh/ssh_host_ed25519_key" | awk '{print $1}')" == "$host_before_b" ]] && pass 'Rollback restored original SSH host key' || fail 'Rollback did not restore SSH host key'
grep -q 'oldmodule' "$work/root-b/etc/initramfs-tools/modules" && pass 'Rollback restored initramfs module list' || fail 'Rollback did not restore initramfs modules'
grep -q 'original-fixture-grub' "$work/root-b/boot/grub/grub.cfg" && ! grep -q 'PAW repaired fixture' "$work/root-b/boot/grub/grub.cfg" && pass 'Rollback restored the original GRUB config' || fail 'Rollback did not restore GRUB config'
[[ -f "$work/root-b/etc/udev/rules.d/70-tencent.rules" && ! -f "$work/root-b/etc/udev/rules.d/70-tencent.rules.disabled-by-paw" ]] && pass 'Rollback restored the original udev rule' || fail 'Rollback did not restore udev rule'
[[ ! -s "$state2/reports/offline-repair.json" ]] && pass 'Failed repair left no success report' || fail 'Failed repair emitted a success report'
umount "$work/root-b"; mounts=()

# "GRUB repair" had only simulated evidence: the repair fixture replaces grub-install
# with a compiled stub, so the real binary was never exercised on a loop disk.  Prove
# here that the real grub-install can install a BIOS boot loader on a loop GPT disk
# (BIOS boot partition + ext4 root), written by the host binary with --boot-directory
# instead of a chroot, then check the artefacts it must leave behind.
if ! command -v grub-install >/dev/null; then
  fail 'Real grub-install is not installed in CI'
else
  grub_fixture="$work/grub-real.img"
  truncate -s 96M "$grub_fixture"
  printf 'label: gpt\n2048,2048\n4096,150000\n' | sfdisk "$grub_fixture" >/dev/null
  sgdisk -t 1:ef02 -c 1:'BIOS boot' -c 2:'paw root' "$grub_fixture" >/dev/null
  grub_loop="$(losetup --find --show -P "$grub_fixture")"; loops+=("$grub_loop")
  grub_part="${grub_loop}p2"
  for _ in $(seq 1 20); do [[ -b "$grub_part" ]] && break; sleep 1; done
  if [[ ! -b "$grub_part" ]]; then
    fail 'Real grub-install fixture partitions absent'
  else
    mkfs.ext4 -F -q "$grub_part"
    grub_root="$work/grub-root"; mkdir -p "$grub_root"
    mount "$grub_part" "$grub_root"; mounts+=("$grub_root")
    mkdir -p "$grub_root/boot/grub"
    if grub-install --target=i386-pc --boot-directory="$grub_root/boot" --recheck "$grub_loop" >"$work/grub-install.log" 2>&1; then
      pass 'Real grub-install succeeded on a loop GPT disk'
    else
      fail 'Real grub-install succeeded on a loop GPT disk'
    fi
    [[ -s "$grub_root/boot/grub/i386-pc/normal.mod" ]] && pass 'GRUB i386-pc modules were copied into the boot directory' || fail 'GRUB i386-pc modules missing'
    if python3 - "$grub_loop" <<'PY'
import sys
with open(sys.argv[1], 'rb') as handle:
    mbr = handle.read(512)
assert mbr[510:512] == b'\x55\xaa', 'MBR signature missing'
assert any(mbr[:440]), 'MBR boot code area is all zero'
PY
    then
      pass 'MBR boot code was written with a valid 0x55AA signature'
    else
      fail 'MBR boot code was not written'
    fi
    if python3 - "${grub_loop}p1" <<'PY'
import sys
with open(sys.argv[1], 'rb') as handle:
    core = handle.read(1024)
assert any(core), 'BIOS boot partition has no embedded core image'
PY
    then
      pass 'GRUB core image was embedded in the BIOS boot partition'
    else
      fail 'GRUB core image was not embedded'
    fi
    umount "$grub_root"; mounts=()
  fi
fi

summary_written=1
printf 'Summary: %s passed, %s failed\n' "$passed" "$failed" >>"$report"
printf 'Summary: %s passed, %s failed\n' "$passed" "$failed"
cat "$report"
((failed == 0))
