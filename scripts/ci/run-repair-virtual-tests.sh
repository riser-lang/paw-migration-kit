#!/usr/bin/env bash
set -Eeuo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
out="${PAW_ARTIFACT_DIR:-$PWD/artifacts}"
work="$root/tests/virtual/repair-run"
mkdir -p "$work" "$out"
report="$out/repair-virtual-test-report.txt"
passed=0; failed=0
loops=(); mounts=()
cleanup(){
  for m in "${mounts[@]}"; do umount "$m" 2>/dev/null || true; done
  for l in "${loops[@]}"; do losetup -d "$l" 2>/dev/null || true; done
  rm -rf "$work"
  rm -f "$root/tests/virtual/repair-root.img" "$root/tests/virtual/repair-rollback.img"
}
trap cleanup EXIT
pass(){ printf 'PASS %s\n' "$1" >>"$report"; passed=$((passed+1)); }
fail(){ printf 'FAIL %s\n' "$1" >>"$report"; failed=$((failed+1)); }
printf 'Offline repair virtual tests\n' >"$report"
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

cat >"$work/stub.c" <<'C'
int main(void){return 0;}
C
cat >"$work/fail.c" <<'C'
int main(void){return 1;}
C

make_fixture(){
  local image="$1" mnt="$2" fail_grub="$3" loop part
  truncate -s 512M "$image"
  printf 'label: dos\n,,83\n' | sfdisk "$image" >/dev/null
  loop="$(losetup --find --show -P "$image")"; loops+=("$loop")
  part="${loop}p1"
  for _ in $(seq 1 30); do [[ -b "$part" ]] && break; sleep 1; done
  [[ -b "$part" ]] || { echo "partition missing" >&2; return 1; }
  mkfs.ext4 -F "$part" >/dev/null
  mount "$part" "$mnt"; mounts+=("$mnt")
  install -d "$mnt"/etc/{netplan,cloud/cloud.cfg.d,udev/rules.d,ssh,default,initramfs-tools} \
    "$mnt"/boot/grub "$mnt"/usr/sbin "$mnt"/lib/modules/6.1.0/kernel/drivers/ata \
    "$mnt"/lib/modules/6.1.0/kernel/drivers/net/ethernet/realtek \
    "$mnt"/var/lib/{dbus,tailscale,paw} "$mnt"/root/.ssh
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
  printf 'GRUB_DEFAULT=0\n' >"$mnt/etc/default/grub"
  printf 'oldmodule\n' >"$mnt/etc/initramfs-tools/modules"
  : >"$mnt/boot/grub/grub.cfg"
  : >"$mnt/lib/modules/6.1.0/kernel/drivers/ata/ahci.ko"
  : >"$mnt/lib/modules/6.1.0/kernel/drivers/net/ethernet/realtek/r8169.ko"
  ssh-keygen -q -t ed25519 -N '' -f "$work/host-before"
  install -m 0600 "$work/host-before" "$mnt/etc/ssh/ssh_host_ed25519_key"
  install -m 0644 "$work/host-before.pub" "$mnt/etc/ssh/ssh_host_ed25519_key.pub"
  gcc -static -O2 -o "$mnt/usr/sbin/update-initramfs" "$work/stub.c"
  gcc -static -O2 -o "$mnt/usr/sbin/grub-install" "$work/stub.c"
  if [[ "$fail_grub" == 1 ]]; then
    gcc -static -O2 -o "$mnt/usr/sbin/update-grub" "$work/fail.c"
  else
    gcc -static -O2 -o "$mnt/usr/sbin/update-grub" "$work/stub.c"
  fi
  chmod 0755 "$mnt/usr/sbin/update-initramfs" "$mnt/usr/sbin/grub-install" "$mnt/usr/sbin/update-grub"
  sync
  umount "$mnt"; mounts=()
  printf '%s\n' "$loop"
}

run_repair(){
  local part="$1" state="$2"
  PAW_ROOT="$root" PAW_STATE_DIR="$state" PAW_CONFIG_DIR="$state/configs" PAW_REPORT_DIR="$state/reports" PAW_LOG_DIR="$state/logs" \
    PAW_SIMULATION=1 PAW_REPAIR_ARM=I_HAVE_VERIFIED_OFFLINE_FILESYSTEM \
    "$root/scripts/paw-offline-repair.sh" "$part"
}

fixture="$root/tests/virtual/repair-root.img"
loop="$(make_fixture "$fixture" "$work/root-a" 0)"
loops+=("$loop")
part="${loop}p1"
state="$work/state-a"; mkdir -p "$state/configs" "$state/reports" "$state/logs"
host_before="$(sha256sum "$work/host-before" | awk '{print $1}')"
mount "$part" "$work/root-a"; mounts+=("$work/root-a")
auth_before="$(sha256sum "$work/root-a/root/.ssh/authorized_keys" | awk '{print $1}')"
db_before="$(sha256sum "$work/root-a/var/lib/paw/important.db" | awk '{print $1}')"
umount "$work/root-a"; mounts=()
if run_repair "$part" "$state" >"$work/repair-a.log" 2>&1; then
  pass 'Offline repair executed the simulation adaptation path'
else
  cat "$work/repair-a.log" >>"$report"; fail 'Offline repair simulation path'
fi
mount "$part" "$work/root-a"; mounts+=("$work/root-a")
grep -q 'name: "e\*"' "$work/root-a/etc/netplan/80-paw-migration.yaml" && pass 'Netplan matches eth0/en*/r8169 with DHCP' || fail 'Netplan e* match missing'
grep -qx 'ahci' "$work/root-a/etc/initramfs-tools/modules" && grep -qx 'r8169' "$work/root-a/etc/initramfs-tools/modules" && pass 'AHCI and r8169 added to initramfs modules' || fail 'initramfs modules missing'
[[ "$(cat "$work/root-a/etc/machine-id")" != "11111111111111111111111111111111" ]] && pass 'machine-id regenerated' || fail 'machine-id was not regenerated'
[[ "$(sha256sum "$work/root-a/etc/ssh/ssh_host_ed25519_key" | awk '{print $1}')" != "$host_before" ]] && pass 'SSH host key regenerated' || fail 'SSH host key was not regenerated'
[[ "$(sha256sum "$work/root-a/root/.ssh/authorized_keys" | awk '{print $1}')" == "$auth_before" ]] && pass 'user authorized_keys preserved' || fail 'authorized_keys changed'
[[ "$(sha256sum "$work/root-a/var/lib/paw/important.db" | awk '{print $1}')" == "$db_before" ]] && pass 'PAW business data preserved' || fail 'PAW business data changed'
[[ -f "$work/root-a/etc/udev/rules.d/70-tencent.rules.disabled-by-paw" ]] && pass 'Tencent/MAC udev rule disabled with original retained' || fail 'udev rule not disabled'
python3 - "$state/reports/offline-repair.json" <<'PY' && pass 'Repair report says SIMULATION_PASS and does not claim hardware validation' || fail 'Repair report status invalid'
import json,sys
d=json.load(open(sys.argv[1])); assert d['status']=='SIMULATION_PASS'; assert d['simulation'] is True
assert d['authorized_keys_touched'] is False and d['PAW_application_data_touched'] is False
PY
backup="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["backup_path"])' "$state/reports/offline-repair.json")"
[[ -s "$backup/target-configs.before.tar" && -s "$backup/target-configs.before.tar.sha256" ]] && pass 'Reversible configuration backup exists with SHA256' || fail 'Repair backup missing'
umount "$work/root-a"; mounts=()

# Rollback: make update-grub fail and verify the original configuration is restored.
fixture2="$root/tests/virtual/repair-rollback.img"
loop2="$(make_fixture "$fixture2" "$work/root-b" 1)"
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
grep -q '50-cloud-init.yaml' "$(ls "$work/root-b/etc/netplan")" && pass 'Rollback restored original netplan file' || fail 'Rollback did not restore netplan'
[[ "$(cat "$work/root-b/etc/machine-id")" == "11111111111111111111111111111111" ]] && pass 'Rollback restored original machine-id' || fail 'Rollback did not restore machine-id'
[[ "$(sha256sum "$work/root-b/etc/ssh/ssh_host_ed25519_key" | awk '{print $1}')" == "$host_before_b" ]] && pass 'Rollback restored original SSH host key' || fail 'Rollback did not restore SSH host key'
grep -q 'oldmodule' "$work/root-b/etc/initramfs-tools/modules" && pass 'Rollback restored initramfs module list' || fail 'Rollback did not restore initramfs modules'
umount "$work/root-b"; mounts=()

printf 'Summary: %s passed, %s failed\n' "$passed" "$failed" >>"$report"
cat "$report"
((failed == 0))
