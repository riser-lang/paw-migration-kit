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
  grep -q '"status"[[:space:]]*:[[:space:]]*"PASS"' "$PAW_REPORT_DIR/stream-verify.json" || die 'Clone verification is not PASS.'
  [[ "$(lsblk -dn -o FSTYPE "$dev" | xargs)" == ext4 ]] || die 'Cloned root partition is not ext4.'
  assert_transaction_stage repair
  transaction_event REPAIR_STARTED
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
boot_mounted=0
modules_dir_existed=0
# Ubuntu/Debian cloud images use a separate XBOOTLDR-style ext4 partition
# (GPT type EA00) mounted at /boot.  The root partition then has an empty
# /boot, so GRUB config and kernels are on that sibling partition.  Refusing
# to repair such a target would strand a perfectly valid whole-disk clone.
if [[ ! -s "$mount_root/boot/grub/grub.cfg" ]]; then
  boot_part=''
  while read -r cand fstype; do
    [[ -n "$cand" && "$cand" != "$dev" ]] || continue
    [[ "$fstype" == ext4 ]] || continue
    mkdir -p "$mount_root/boot"
    if mount -o rw "$cand" "$mount_root/boot" 2>/dev/null; then
      if [[ -s "$mount_root/boot/grub/grub.cfg" ]]; then
        boot_part="$cand"; boot_mounted=1; break
      fi
      umount "$mount_root/boot" 2>/dev/null || true
    fi
  done < <(lsblk -nrpo NAME,FSTYPE "$disk")
  [[ -n "$boot_part" ]] || die 'Existing GRUB config was not found on the cloned root or its separate /boot partition; refusing to claim boot repair.'
  log INFO "Mounted separate boot partition $boot_part at the cloned /boot."
fi
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
    if [[ ${boot_mounted:-0} == 1 ]]; then umount "$mount_root/boot" 2>/dev/null || true; fi
    umount "$mount_root" 2>/dev/null
    e2fsck -f -p "$dev" || true
    set -e
  fi
  if [[ ${boot_mounted:-0} == 1 ]]; then umount "$mount_root/boot" 2>/dev/null || true; fi
  if [[ ${mounted:-0} == 1 ]]; then umount "$mount_root" || true; fi
  if ((rc != 0)); then
    if [[ ${PAW_SIMULATION:-0} != 1 ]]; then
      transaction_event NEEDS_MANUAL_ACTION --phase repair --reason "offline repair failed rc=$rc" || true
    fi
    log ERROR "offline adaptation failed; the backup is retained at $backup"
  fi
  exit "$rc"
}
trap rollback EXIT

[[ -x "$mount_root/usr/sbin/grub-install" && -s "$mount_root/boot/grub/grub.cfg" ]] || die 'Existing GRUB installation/config was not found; refusing to claim boot repair.'
[[ -x "$mount_root/usr/sbin/update-initramfs" && -x "$mount_root/usr/sbin/update-grub" ]] || die 'Target update-initramfs/update-grub is missing; refusing to claim boot repair.'
module_root="$mount_root/lib/modules"
ahci_available=0
r8169_available=0
if find "$module_root" -type f -name 'ahci.ko*' -print -quit | grep -q . || grep -RqsE '(^|/)ahci\.ko$' "$module_root"/*/modules.builtin; then
  ahci_available=1
else
  log WARN 'Target kernel has no AHCI module; boot media support is left to the cloned kernel.'
fi
if find "$module_root" -type f -name 'r8169.ko*' -print -quit | grep -q . || grep -RqsE '(^|/)r8169\.ko$' "$module_root"/*/modules.builtin; then
  r8169_available=1
else
  log WARN 'Target kernel has no Realtek r8169 module; it is not added to the initramfs.'
fi
# Haswell HD Graphics 4600 needs i915 for the graphical console.  If the
# cloned kernel does not ship it, keep the text console usable instead of
# pretending the GPU path was repaired; the final report marks it WARN.
if find "$module_root" -type f -name 'i915.ko*' -print -quit | grep -q . || grep -RqsE '(^|/)i915\.ko$' "$module_root"/*/modules.builtin; then
  i915_available=1
else
  i915_available=0
  log WARN 'Target kernel has no i915 module (HD Graphics 4600); graphical console remains a physical-open item.'
fi

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

# Secret-free old/new service identity manifest.  The old VPS is still
# reachable read-only here, so record hashes and unit names while both sides
# are observable; never copy the old machine-id, host keys or Tailscale state.
if [[ ${PAW_SIMULATION:-0} != 1 ]]; then
  old_hostname="$(rescue_ssh 'hostname' 2>/dev/null || true)"
  old_machine_id="$(rescue_ssh 'cat /etc/machine-id' 2>/dev/null || true)"
  old_ssh_sha="$(rescue_ssh "sha256sum /etc/ssh/ssh_host_ed25519_key.pub 2>/dev/null || true" | awk 'NF{print $1; exit}')"
  old_services_json="$(rescue_ssh "systemctl list-unit-files --type=service --state=enabled --no-legend 2>/dev/null || true" | python3 -c 'import json,sys; print(json.dumps([l.split()[0] for l in sys.stdin if l.split()]))')"
  python3 "$PAW_ROOT/scripts/paw-service-cutover-manifest.py"     --source-config "$PAW_CONFIG_DIR/source.json"     --target-root "$mount_root"     --old-hostname "$old_hostname"     --old-machine-id "$old_machine_id"     --old-ssh-fingerprint "$old_ssh_sha"     --old-services-json "$old_services_json"     --output "$PAW_REPORT_DIR/service-cutover-manifest.json" || log WARN 'Service identity manifest needs review; see service-cutover-manifest.json.'
fi

mkdir -p "$mount_root/etc/initramfs-tools"
touch "$mount_root/etc/initramfs-tools/modules"
initramfs_modules=()
for module in ahci r8169 i915; do
  case "$module" in
    ahci) ((ahci_available == 1)) || continue ;;
    r8169) ((r8169_available == 1)) || continue ;;
    i915) ((i915_available == 1)) || continue ;;
  esac
  # Built-in drivers need no initramfs entry; only a real .ko can be added
  # and independently verified there.
  find "$module_root" -type f -name "$module.ko*" -print -quit | grep -q . || continue
  grep -qx "$module" "$mount_root/etc/initramfs-tools/modules" || printf '%s\n' "$module" >>"$mount_root/etc/initramfs-tools/modules"
  initramfs_modules+=("$module")
done

binds=1
for item in dev proc sys; do mount --rbind "/$item" "$mount_root/$item"; mount --make-rslave "$mount_root/$item"; done
# Rebuild libkmod indexes after adding modules; update-initramfs/dracut uses
# modules.dep.bin, not the text modules.dep, so an injected module is otherwise
# reported as missing even though the .ko file exists.  Minimal fixtures and
# unusual targets may have no depmod; that is a warning, not a boot-repair
# failure, because update-initramfs can still run from its own dependency data.
if chroot "$mount_root" sh -c 'command -v depmod >/dev/null 2>&1'; then
  chroot "$mount_root" sh -c 'for k in /lib/modules/*; do [ -d "$k" ] && depmod -a "$(basename "$k")"; done'
else
  log WARN 'Target has no depmod; module dependency indexes were not rebuilt.'
fi
chroot "$mount_root" env DEBIAN_FRONTEND=noninteractive update-initramfs -u -k all
initramfs_verified='not_checked'
initramfs_missing=''
if ((${#initramfs_modules[@]})); then
  initrd_rel="$(chroot "$mount_root" sh -c 'ls -1t /boot/initrd.img-* 2>/dev/null | head -n1' | sed 's#^/boot/##')"
  if [[ -n "$initrd_rel" ]] && chroot "$mount_root" sh -c 'command -v lsinitramfs >/dev/null 2>&1'; then
    initramfs_verified='PASS'
    for module in "${initramfs_modules[@]}"; do
      if ! chroot "$mount_root" lsinitramfs "/boot/$initrd_rel" 2>/dev/null | grep -Eq "/$module\.ko(\.(zst|xz|gz))?$"; then
        initramfs_verified='FAIL'
        initramfs_missing+="${initramfs_missing:+,}$module"
      fi
    done
    if [[ "$initramfs_verified" == FAIL ]]; then
      log ERROR "Initramfs verification missing modules: $initramfs_missing; refusing to claim a bootable repaired target."
      die 'Initramfs module verification failed.'
    fi
  else
    initramfs_verified='lsinitramfs_unavailable'
    log ERROR 'Cannot independently list the rebuilt initramfs; module inclusion is unverified and cannot be claimed.'
    die 'lsinitramfs or rebuilt initrd unavailable; refusing an unverified boot repair.'
  fi
fi
if [[ ${PAW_SIMULATION:-0} == 1 ]]; then
  grub_install_result='simulation_skipped'
else
  chroot "$mount_root" env DEBIAN_FRONTEND=noninteractive grub-install --target=i386-pc --recheck --no-floppy "$disk"
  grub_install_result='i386-pc'
fi
chroot "$mount_root" env DEBIAN_FRONTEND=noninteractive GRUB_DISABLE_OS_PROBER=true update-grub
root_uuid_value="$(blkid -s UUID -o value "$dev" 2>/dev/null || true)"
root_label_value="$(blkid -s LABEL -o value "$dev" 2>/dev/null || true)"
[[ "$root_uuid_value" =~ ^[0-9a-fA-F-]{36}$ ]] || die 'Cloned root UUID is unreadable after repair; refusing to claim GRUB/fstab correctness.'
python3 - "$mount_root/etc/fstab" "$root_uuid_value" "$mount_root/boot/grub/grub.cfg" "$root_label_value" <<'PY' || die 'GRUB/fstab identity check failed.'
import re,sys
fstab,uuid,grub,label=sys.argv[1:]
errors=[]
root_seen=False
for line in open(fstab,encoding="utf-8",errors="replace"):
    line=line.split("#",1)[0].strip()
    if not line: continue
    fields=line.split()
    if len(fields)<2: continue
    source,target=fields[0],fields[1]
    if target=="/":
        root_seen=True
        if source.upper()==f"UUID={uuid}".upper():
            pass
        elif label and source.upper()==f"LABEL={label}".upper():
            pass
        else:
            errors.append(f"root fstab entry does not use the cloned UUID/LABEL: {line}")
    elif re.match(r"/dev/[sh]d[a-z]",source):
        errors.append(f"fstab uses a mutable device name: {line}")
if not root_seen: errors.append("fstab has no root entry")
cfg=open(grub,encoding="utf-8",errors="replace").read()
if uuid.lower() not in cfg.lower(): errors.append("grub.cfg does not reference the cloned root UUID")
if errors: raise SystemExit("; ".join(errors))
PY
for item in sys proc dev; do umount -R "$mount_root/$item"; done
binds=0
sync
if [[ ${boot_mounted:-0} == 1 ]]; then umount "$mount_root/boot"; boot_mounted=0; fi
umount "$mount_root"; mounted=0
trap - EXIT
if [[ ${PAW_SIMULATION:-0} != 1 ]]; then
  transaction_event REPAIRED
fi
python3 - "$PAW_REPORT_DIR/offline-repair.json" "$backup" "$grub_install_result" "${PAW_SIMULATION:-0}" "${initramfs_modules[*]:-}" "$initramfs_verified" "$initramfs_missing" "$i915_available" <<'PY'
import json,os,sys,datetime
path,backup,grub,simulation,modules,verified,missing,i915=sys.argv[1:]
status="SIMULATION_PASS" if simulation=="1" else "PASS"
changes=["netplan DHCP matched to e* (eth0/en*/r8169) with no fixed MAC","cloud-init network disabled","old Tencent/MAC udev overrides disabled","machine-id regenerated","SSH host keys regenerated","clone-local Tailscale state cleared"]
if modules:
    if verified=="PASS": changes.append(f"initramfs module inclusion verified: {modules}")
    elif verified=="FAIL": changes.append(f"initramfs modules requested but NOT all present: {modules}; missing={missing}")
    else: changes.append(f"initramfs modules requested: {modules}; inclusion {verified}")
changes += ["initramfs regenerated","GRUB config regenerated with DEBIAN_FRONTEND=noninteractive","fstab/GRUB UUID identity checked"]
with open(path,"w",encoding="utf-8") as handle:
    json.dump({"status":status,"changes":changes,"grub_install":grub,"simulation":simulation=="1","initramfs_modules_requested":modules.split(",") if modules else [],"initramfs_modules_verified":verified,"initramfs_modules_missing":missing.split(",") if missing else [],"hd4600_i915_available":i915=="1","grub_noninteractive":True,"fstab_uuid_checked":True,"backup_path":backup,"completed_at":datetime.datetime.now(datetime.timezone.utc).isoformat(),"authorized_keys_touched":False,"PAW_application_data_touched":False},handle,indent=2)
    os.chmod(path,0o600)
PY

log INFO 'Offline clone adaptation completed with a reversible PAWDATA backup; user authorized_keys and PAW application data were not touched.'
