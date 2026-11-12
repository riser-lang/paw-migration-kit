#!/usr/bin/env bash
# Build a test-only Live ISO from the release ISO.  The release payload is
# preserved byte-for-byte except for an injected Stage-3 harness and a `toram`
# boot word, so the USB stick can be genuinely unplugged before target reboot.
set -Eeuo pipefail
source "$(dirname "$0")/../../scripts/paw-lib.sh"
input_iso="${1:-}"; output_iso="${2:-}"; work="${3:-}"
[[ -r "$input_iso" && -n "$output_iso" && -n "$work" ]] || die 'Usage: build-live-lab-iso.sh RELEASE.iso OUT.iso WORKDIR'
for c in unsquashfs mksquashfs xorriso; do need "$c"; done
source_bytes="${PAW_EXPECTED_SOURCE_BYTES:-53687091200}"
[[ "$source_bytes" =~ ^[0-9]+$ ]] || die 'Invalid expected source bytes.'
root="$PAW_ROOT"
rm -rf "$work/rootfs" "$work/iso-boot"
mkdir -p "$work/iso-boot"
xorriso -osirrox on -indev "$input_iso" -extract /live/filesystem.squashfs "$work/filesystem.squashfs" >/dev/null 2>&1
unsquashfs -d "$work/rootfs" "$work/filesystem.squashfs" >/dev/null
install -d "$work/rootfs/opt/paw-migration/tests/prehardware" "$work/rootfs/opt/paw-migration/tests/stage3/state"
rm -rf "$work/rootfs/opt/paw-migration/scripts" "$work/rootfs/opt/paw-migration/configs"
cp -a "$root/scripts" "$work/rootfs/opt/paw-migration/scripts"
cp -a "$root/configs" "$work/rootfs/opt/paw-migration/configs"
cp -a "$root/tests/prehardware/." "$work/rootfs/opt/paw-migration/tests/prehardware/"
chmod 0755 "$work/rootfs/opt/paw-migration/tests/prehardware/"*.sh
install -m 0644 "$root/boot/20-wired.network" "$work/rootfs/opt/paw-migration/boot/20-wired.network"
sed "s/%SOURCE_BYTES%/$source_bytes/" "$root/tests/prehardware/paw-prehardware-chain.service" \
  >"$work/rootfs/etc/systemd/system/paw-prehardware-chain.service"
ln -sfn /etc/systemd/system/paw-prehardware-chain.service \
  "$work/rootfs/etc/systemd/system/multi-user.target.wants/paw-prehardware-chain.service"
# Lab diagnostics only: serial root shell.  This unit is not part of the release ISO.
install -d "$work/rootfs/etc/systemd/system/serial-getty@ttyS0.service.d"
cat >"$work/rootfs/etc/systemd/system/serial-getty@ttyS0.service.d/autologin.conf" <<'UNIT'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear --keep-baud 115200,38400,9600 %I $TERM
UNIT
ln -sfn /lib/systemd/system/serial-getty@ttyS0.service \
  "$work/rootfs/etc/systemd/system/getty.target.wants/serial-getty@ttyS0.service"
mksquashfs "$work/rootfs" "$work/filesystem-lab.squashfs" -comp xz -b 1M -noappend -processors 2 >/dev/null
xorriso -osirrox on -indev "$input_iso" -extract /isolinux "$work/iso-boot/isolinux" >/dev/null 2>&1
python3 - "$work/iso-boot/isolinux/live.cfg" <<'PY'
import re,sys
p=sys.argv[1]
s=open(p,encoding="utf-8").read()
s=re.sub(r'(?m)^(\s*append\s+.*)$', lambda m: m.group(1) if re.search(r'(^|\s)toram(\s|$)',m.group(1)) else m.group(1)+' toram', s)
open(p,"w",encoding="utf-8").write(s)
PY
xorriso -indev "$input_iso" -outdev "$output_iso" -overwrite on \
  -map "$work/filesystem-lab.squashfs" /live/filesystem.squashfs \
  -map "$work/iso-boot/isolinux/live.cfg" /isolinux/live.cfg \
  -boot_image any replay >/dev/null
log INFO "test Live ISO built: $output_iso"
