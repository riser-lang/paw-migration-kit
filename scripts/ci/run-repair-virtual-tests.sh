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
  # Unmount in reverse registration order so nested/bind mounts are released first.
  local i
  for ((i=${#mounts[@]}-1; i>=0; i--)); do umount "${mounts[$i]}" 2>/dev/null || true; done
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
  rm -f "$work/host-before" "$work/host-before.pub"
  truncate -s 512M "$image"
  mkdir -p "$mnt"
  printf 'label: dos\n,,83\n' | sfdisk "$image" >/dev/null
  loop="$(losetup --find --show -P "$image")"; loops+=("$loop")
  part="${loop}p1"
  for _ in $(seq 1 30); do [[ -b "$part" ]] && break; sleep 1; done
  [[ -b "$part" ]] || { echo "partition missing" >&2; return 1; }
  mkfs.ext4 -F "$part" >/dev/null
  mount "$part" "$mnt"; mounts+=("$mnt")
  install -d "$mnt"/etc/{netplan,cloud/cloud.cfg.d,udev/rules.d,ssh,default,initramfs-tools} \
    "$mnt"/dev "$mnt"/proc "$mnt"/sys \
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
  printf 'set default=0\n' >"$mnt/boot/grub/grub.cfg"
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
[[ -f "$work/root-b/etc/netplan/50-cloud-init.yaml" ]] && pass 'Rollback restored original netplan file' || fail 'Rollback did not restore netplan'
[[ "$(cat "$work/root-b/etc/machine-id")" == "11111111111111111111111111111111" ]] && pass 'Rollback restored original machine-id' || fail 'Rollback did not restore machine-id'
[[ "$(sha256sum "$work/root-b/etc/ssh/ssh_host_ed25519_key" | awk '{print $1}')" == "$host_before_b" ]] && pass 'Rollback restored original SSH host key' || fail 'Rollback did not restore SSH host key'
grep -q 'oldmodule' "$work/root-b/etc/initramfs-tools/modules" && pass 'Rollback restored initramfs module list' || fail 'Rollback did not restore initramfs modules'
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
      cat "$work/grub-install.log" >>"$report"; fail 'Real grub-install succeeded on a loop GPT disk'
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

# The production path installs GRUB from inside the repaired root ("chroot
# $mount_root grub-install ..."), which the host-side case above does not exercise.
# Re-create that shape on loop: fixture root with /boot and a minimal grub.cfg, host
# binaries and GRUB modules supplied through read-only bind mounts (a CI stand-in for
# the packages a real target would already have), then run the same command form.
chroot_img="$work/grub-chroot.img"
truncate -s 160M "$chroot_img"
printf 'label: gpt\n2048,2048\n4096,260000\n' | sfdisk "$chroot_img" >/dev/null
sgdisk -t 1:ef02 -c 1:'BIOS boot' -c 2:'paw root' "$chroot_img" >/dev/null
chroot_loop="$(losetup --find --show -P "$chroot_img")"; loops+=("$chroot_loop")
chroot_part="${chroot_loop}p2"
for _ in $(seq 1 20); do [[ -b "$chroot_part" ]] && break; sleep 1; done
if [[ ! -b "$chroot_part" ]]; then
  fail 'Chroot grub-install fixture partitions absent'
else
  mkfs.ext4 -F -q "$chroot_part"
  chroot_root="$work/grub-chroot-root"; mkdir -p "$chroot_root"
  mount "$chroot_part" "$chroot_root"; mounts+=("$chroot_root")
  mkdir -p "$chroot_root"/{boot/grub,etc,tmp,dev,proc,sys,usr,sbin,bin,lib,lib64,var/lib}
  printf 'set default=0\n' >"$chroot_root/boot/grub/grub.cfg"
  binds_ok=1
  for d in dev proc sys usr sbin bin lib lib64; do
    if mount --bind -o ro "/$d" "$chroot_root/$d" 2>/dev/null || mount --bind "/$d" "$chroot_root/$d"; then
      mounts+=("$chroot_root/$d")
    else
      binds_ok=0
    fi
  done
  if ((binds_ok == 0)); then
    fail 'Chroot grub-install bind mounts available'
  else
    if chroot "$chroot_root" grub-install --target=i386-pc --recheck "$chroot_loop" >"$work/grub-chroot.log" 2>&1; then
      pass 'Chroot grub-install succeeded on a loop GPT disk'
    else
      cat "$work/grub-chroot.log" >>"$report"; fail 'Chroot grub-install succeeded on a loop GPT disk'
    fi
    [[ -s "$chroot_root/boot/grub/i386-pc/normal.mod" ]] && pass 'Chroot grub-install copied i386-pc modules into the fixture boot directory' || fail 'Chroot grub-install modules missing'
    if python3 - "$chroot_loop" <<'PY'
import sys
with open(sys.argv[1], 'rb') as handle:
    mbr = handle.read(512)
assert mbr[510:512] == b'\x55\xaa', 'MBR signature missing'
assert any(mbr[:440]), 'MBR boot code area is all zero'
PY
    then
      pass 'Chroot grub-install wrote MBR boot code with a valid 0x55AA signature'
    else
      fail 'Chroot grub-install did not write MBR boot code'
    fi
  fi
  for ((i=${#mounts[@]}-1; i>=0; i--)); do umount "${mounts[$i]}" 2>/dev/null || true; done
  mounts=()
  losetup -d "$chroot_loop" 2>/dev/null || true
fi

# Last link of the repair chain: a disk that GRUB installed into must actually boot.
# Build a GPT loop disk, put the ISO's own kernel and initrd into its /boot with a
# minimal grub.cfg, install GRUB host-side, then let QEMU SeaBIOS boot from the disk
# only (no ISO attached) and read the serial log.
boot_iso="$root/boot/custom/paw-live-amd64.iso"
if [[ ! -s "$boot_iso" ]]; then
  fail 'ISO present for the repaired-disk boot chain test'
else
  iso_mnt="$work/iso-mnt"; mkdir -p "$iso_mnt"
  if ! mount -o loop,ro "$boot_iso" "$iso_mnt" 2>/dev/null; then
    fail 'ISO mount for the boot chain test'
  else
    mounts+=("$iso_mnt")
    kernel_src="" initrd_src=""
    for cand in live/vmlinuz boot/vmlinuz vmlinuz; do
      [[ -s "$iso_mnt/$cand" ]] && { kernel_src="$iso_mnt/$cand"; break; }
    done
    for cand in live/initrd.img live/initrd.gz boot/initrd.img initrd.img; do
      [[ -s "$iso_mnt/$cand" ]] && { initrd_src="$iso_mnt/$cand"; break; }
    done
    if [[ -z "$kernel_src" || -z "$initrd_src" ]]; then
      fail 'ISO kernel and initrd located for the boot chain test'
    else
      pass 'ISO kernel and initrd located for the boot chain test'
      chain_img="$work/grub-chain.img"
      truncate -s 320M "$chain_img"
      printf 'label: gpt\n2048,2048\n4096,600000\n' | sfdisk "$chain_img" >/dev/null
      sgdisk -t 1:ef02 -c 1:'BIOS boot' -c 2:'paw root' "$chain_img" >/dev/null
      chain_loop="$(losetup --find --show -P "$chain_img")"; loops+=("$chain_loop")
      chain_part="${chain_loop}p2"
      for _ in $(seq 1 20); do [[ -b "$chain_part" ]] && break; sleep 1; done
      if [[ ! -b "$chain_part" ]]; then
        fail 'Boot chain fixture partitions absent'
      else
        mkfs.ext4 -F -q "$chain_part"
        chain_root="$work/grub-chain-root"; mkdir -p "$chain_root"
        mount "$chain_part" "$chain_root"; mounts+=("$chain_root")
        mkdir -p "$chain_root/boot/grub"
        cp "$kernel_src" "$chain_root/boot/vmlinuz"
        cp "$initrd_src" "$chain_root/boot/initrd.img"
        cat >"$chain_root/boot/grub/grub.cfg" <<'CFG'
set default=0
set timeout=1
menuentry 'paw boot chain test' {
  linux /boot/vmlinuz boot=live components console=ttyS0,115200n8
  initrd /boot/initrd.img
}
CFG
        if grub-install --target=i386-pc --boot-directory="$chain_root/boot" --recheck "$chain_loop" >"$work/grub-chain-install.log" 2>&1; then
          pass 'GRUB installed into the boot chain fixture'
        else
          cat "$work/grub-chain-install.log" >>"$report"; fail 'GRUB installed into the boot chain fixture'
        fi
        umount "$chain_root"
        mounts=("$iso_mnt")
        chain_log="$work/grub-chain-serial.log"
        if ! command -v qemu-system-x86_64 >/dev/null; then
          fail 'qemu-system-x86_64 available for the boot chain test'
        else
          set +e
          timeout 240 qemu-system-x86_64 -m 2048 -display none -serial "file:$chain_log" \
            -monitor none -no-reboot -boot order=c \
            -drive "file=$chain_img,format=raw,if=ide,index=0" >/dev/null 2>&1
          set -e
          # `quiet` was removed from the command line: run 42827723019 booted the disk
          # and reached the initramfs prompt, but quiet suppressed the two lines the
          # assertions look for, so the case reported a false negative.
          if grep -Eq 'Linux version ' "$chain_log" 2>/dev/null; then
            pass 'GRUB on the repaired disk loaded the kernel'
          else
            fail 'GRUB on the repaired disk loaded the kernel'
            { echo '--- serial log excerpt ---'; head -40 "$chain_log" 2>/dev/null || echo '(no serial log)'; } >>"$report"
            { echo '--- grub-install log ---'; head -20 "$work/grub-chain-install.log" 2>/dev/null || echo '(no install log)'; } >>"$report"
          fi
          # Kernel 6.12 does not necessarily print "Unpacking initramfs"; accept any of
          # the lines that prove the initrd was actually read and unpacked.
          if grep -Eqi 'Unpacking initramfs|Freeing initrd memory|Trying to unpack rootfs image' "$chain_log" 2>/dev/null; then
            pass 'Kernel processed the initrd from the repaired disk'
          else
            fail 'Kernel processed the initrd from the repaired disk'
            { echo '--- serial log excerpt ---'; head -40 "$chain_log" 2>/dev/null || echo '(no serial log)'; } >>"$report"
          fi
          if grep -Eqi 'Kernel panic' "$chain_log" 2>/dev/null; then
            fail 'Boot chain reached initramfs without a kernel panic'
          else
            pass 'Boot chain reached initramfs without a kernel panic'
          fi
          if grep -Eq 'Run /init as init process|\(initramfs\)' "$chain_log" 2>/dev/null; then
            pass 'Boot from the repaired disk reached the initramfs stage'
          else
            fail 'Boot from the repaired disk reached the initramfs stage'
          fi
        fi
        losetup -d "$chain_loop" 2>/dev/null || true
      fi
    fi
    umount "$iso_mnt"; mounts=()
  fi
fi
printf 'Summary: %s passed, %s failed\n' "$passed" "$failed" >>"$report"
cat "$report"
((failed == 0))
