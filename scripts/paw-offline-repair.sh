#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/paw-lib.sh"
dev="${1:-}"
[[ -n "$dev" && -b "$dev" ]] || die 'Usage: paw-offline-repair.sh ROOT_PARTITION'
require_sim_or_enrollment; assert_unmounted "$dev"; need e2fsck
[[ ${PAW_REPAIR_ARM:-} == 'I_HAVE_VERIFIED_OFFLINE_FILESYSTEM' ]] || die 'Repair requires explicit final authorization.'
if [[ ${PAW_SIMULATION:-0} == 1 ]]; then
  assert_sim_loop_device "$dev"
fi

disk="$(parent_disk "$dev")"
[[ -b "$disk" ]] || die 'Could not identify the target disk that contains the root partition.'

if [[ ${PAW_SIMULATION:-0} == 1 ]]; then
  [[ "$(lsblk -dn -o FSTYPE "$dev" | xargs)" == ext4 ]] || die 'Simulation root partition is not ext4.'
else
  assert_registered_target_device "$dev"; assert_authorization_for_target "$dev"
  [[ -r "$PAW_REPORT_DIR/stream-verify.json" ]] || die 'Independent SHA256 verification is required before repair.'
  grep -q '"status":"PASS"' "$PAW_REPORT_DIR/stream-verify.json" || die 'Clone verification is not PASS.'
  [[ "$(lsblk -dn -o FSTYPE "$dev" | xargs)" == ext4 ]] || die 'Cloned root partition is not ext4.'
fi
for c in mount umount mountpoint tar systemd-machine-id-setup ssh-keygen find; do need "$c"; done
mount_root=/mnt/paw-migration-cloned-root
[[ ! -e "$mount_root" || -d "$mount_root" ]] || die 'Repair mount path is not a directory.'
! mountpoint -q "$mount_root" || die 'Repair mount path is already in use.'
backup="$PAW_STATE_DIR/backups/offline-repair-$(date -u +%Y%m%dT%H%M%SZ)"
install -d -m 0700 "$backup" "$mount_root"

set +e
e2fsck -f -n "$dev"
fsck_rc=$?
set -e
((fsck_rc == 0)) || die 'Read-only e2fsck found inconsistencies; automatic repair is blocked to preserve reversibility.'
mount -o rw "$dev" "$mount_root"
mounted=1
modules_dir_existed=0
[[ -d "$mount_root/etc/initramfs-tools" ]] && modules_dir_existed=1
rollback(){
  rc=$?
  if ((rc != 0)) && [[ ${mounted:-0} == 1 ]]; then
    set +e
    if [[ ${binds:-0} == 1 ]]; then for item in sys proc dev; do umount -R "$mount_root/$item" 2>/dev/null; done; fi
    if [[ -s "$backup/original-paths.txt" ]]; then
      rm -f "$mount_root/etc/netplan/80-paw-migration.yaml" "$mount_root/etc/cloud/cloud.cfg.d/99-paw-disable-network-config.cfg"
      find "$mount_root/etc/ssh" -maxdepth 1 -type f -name 'ssh_host_*' -delete 2>/dev/null
      find "$mount_root/etc/udev/rules.d" -maxdepth 1 -type f -name '*.disabled-by-paw' -delete 2>/dev/null
      tar --acls --xattrs -xpf "$backup/target-configs.before.tar" -C "$mount_root" || true
      if [[ ${modules_dir_existed:-1} == 0 ]]; then rm -rf "$mount_root/etc/initramfs-tools"; fi
    fi
    umount "$mount_root" 2>/dev/null
    e2fsck -f -p "$dev" || true
    set -e
  fi
  if [[ ${mounted:-0} == 1 ]]; then umount "$mount_root" || true; fi
  if ((rc != 0)); then log ERROR "offline adaptation failed; the backup is retained at $backup"; fi
  exit "$rc"
}
trap rollback EXIT

[[ -x "$mount_root/usr/sbin/grub-install" && -s "$mount_root/boot/grub/grub.cfg" ]] || die 'Existing GRUB installation/config was not found; refusing to claim boot repair.'
[[ -x "$mount_root/usr/sbin/update-initramfs" && -x "$mount_root/usr/sbin/update-grub" ]] || die 'Target update-initramfs/update-grub is missing; refusing to claim boot repair.'
module_root="$mount_root/lib/modules"
find "$module_root" -type f -name 'ahci.ko*' -print -quit | grep -q . || grep -RqsE '(^|/)ahci\.ko$' "$module_root"/*/modules.builtin || die 'Target kernel has no AHCI module.'
find "$module_root" -type f -name 'r8169.ko*' -print -quit | grep -q . || grep -RqsE '(^|/)r8169\.ko$' "$module_root"/*/modules.builtin || die 'Target kernel has no Realtek r8169 module.'

paths="$backup/original-paths.txt"
: >"$paths"
for item in etc/netplan etc/cloud/cloud.cfg.d etc/udev/rules.d etc/machine-id var/lib/dbus/machine-id etc/ssh etc/default/grub boot/grub var/lib/tailscale etc/initramfs-tools/modules; do
  [[ -e "$mount_root/$item" ]] && printf '%s\n' "$item" >>"$paths"
done
find "$mount_root/boot" -maxdepth 1 -type f -name 'initrd.img-*' -printf '%P\n' 2>/dev/null | sed 's#^#boot/#' >>"$paths"
free_bytes="$(df -B1 --output=avail "$PAW_STATE_DIR" | tail -n1 | tr -d ' ')"
((free_bytes >= 536870912)) || die 'PAWDATA lacks the 512 MiB free-space reserve for reversible backups.'
tar --acls --xattrs -cpf "$backup/target-configs.before.tar" -C "$mount_root" -T "$paths"
sha256sum "$backup/target-configs.before.tar" >"$backup/target-configs.before.tar.sha256"
chmod 0600 "$backup/target-configs.before.tar" "$backup/target-configs.before.tar.sha256" "$paths"

mkdir -p "$backup/netplan-original" "$backup/tailscale-original"
shopt -s nullglob
for f in "$mount_root"/etc/netplan/*.yaml "$mount_root"/etc/netplan/*.yml; do mv -- "$f" "$backup/netplan-original/"; done
for f in "$mount_root"/etc/udev/rules.d/*.rules; do
  if grep -Eiq 'tencent|ATTR\{address\}|MACAddress|NAME="eth0"' "$f"; then mv -- "$f" "$f.disabled-by-paw"; fi
done
mkdir -p "$mount_root/etc/netplan" "$mount_root/etc/cloud/cloud.cfg.d"
cat >"$mount_root/etc/netplan/80-paw-migration.yaml" <<'NETPLAN'
network:
  version: 2
  renderer: networkd
  ethernets:
    paw-wired:
      # Covers eth0 (net.ifnames=0), enp3s0/en* and Realtek r8169 NICs.
      match:
        name: "e*"
      dhcp4: true
      dhcp4-overrides:
        use-domains: true
      dhcp6: false
      optional: true
NETPLAN
chmod 0600 "$mount_root/etc/netplan/80-paw-migration.yaml"
cat >"$mount_root/etc/cloud/cloud.cfg.d/99-paw-disable-network-config.cfg" <<'CLOUDINIT'
network: {config: disabled}
CLOUDINIT
chmod 0644 "$mount_root/etc/cloud/cloud.cfg.d/99-paw-disable-network-config.cfg"

rm -f "$mount_root/etc/machine-id" "$mount_root/var/lib/dbus/machine-id"
systemd-machine-id-setup --root="$mount_root" >/dev/null
install -d -m 0755 "$mount_root/var/lib/dbus"
cp "$mount_root/etc/machine-id" "$mount_root/var/lib/dbus/machine-id"
chmod 0444 "$mount_root/var/lib/dbus/machine-id"
find "$mount_root/etc/ssh" -maxdepth 1 -type f -name 'ssh_host_*' -delete
ssh-keygen -A -f "$mount_root"
if [[ -d "$mount_root/var/lib/tailscale" ]]; then mv "$mount_root/var/lib/tailscale" "$backup/tailscale-original/state"; fi
install -d -m 0700 "$mount_root/var/lib/tailscale"

mkdir -p "$mount_root/etc/initramfs-tools"
touch "$mount_root/etc/initramfs-tools/modules"
for module in ahci r8169; do
  grep -qx "$module" "$mount_root/etc/initramfs-tools/modules" || printf '%s\n' "$module" >>"$mount_root/etc/initramfs-tools/modules"
done

binds=1
for item in dev proc sys; do mount --rbind "/$item" "$mount_root/$item"; mount --make-rslave "$mount_root/$item"; done
chroot "$mount_root" update-initramfs -u -k all
if [[ ${PAW_SIMULATION:-0} == 1 ]]; then
  grub_install_result='simulation_skipped'
else
  chroot "$mount_root" grub-install --target=i386-pc --recheck "$disk"
  grub_install_result='i386-pc'
fi
chroot "$mount_root" update-grub
for item in sys proc dev; do umount -R "$mount_root/$item"; done
binds=0
sync
umount "$mount_root"; mounted=0
trap - EXIT
python3 - "$PAW_REPORT_DIR/offline-repair.json" "$backup" "$grub_install_result" "${PAW_SIMULATION:-0}" <<'PY'
import json,os,sys,datetime
path,backup,grub,simulation=sys.argv[1:]
status="SIMULATION_PASS" if simulation=="1" else "PASS"
with open(path,"w",encoding="utf-8") as handle:
    json.dump({"status":status,"changes":["netplan DHCP matched to e* (eth0/en*/r8169) with no fixed MAC","cloud-init network disabled","old Tencent/MAC udev overrides disabled","machine-id regenerated","SSH host keys regenerated","clone-local Tailscale state cleared","ahci/r8169 added to initramfs modules","initramfs regenerated","GRUB config regenerated"],"grub_install":grub,"simulation":simulation=="1","backup_path":backup,"completed_at":datetime.datetime.now(datetime.timezone.utc).isoformat(),"authorized_keys_touched":False,"PAW_application_data_touched":False},handle,indent=2)
os.chmod(path,0o600)
PY
log INFO 'Offline clone adaptation completed with a reversible PAWDATA backup; user authorized_keys and PAW application data were not touched.'
