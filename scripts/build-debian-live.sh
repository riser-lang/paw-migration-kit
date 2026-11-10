#!/usr/bin/env bash
set -Eeuo pipefail
src="$(cd "$(dirname "$0")/.." && pwd)"
work="${PAW_BUILD_WORK:-$HOME/paw-live-build}"
export SOURCE_DATE_EPOCH=1793491200
[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo 'live-build requires root in the Linux build environment; this script will not sudo or elevate.' >&2; exit 2; }
command -v lb >/dev/null 2>&1 || { echo 'Install Debian live-build in the approved Linux build environment first.' >&2; exit 2; }
mkdir -p "$work/auto" "$work/config/package-lists" "$work/config/archives" "$work/config/bootloaders/isolinux" "$work/config/includes.chroot/opt/paw-migration" "$work/config/includes.chroot/opt/paw-migration/configs" "$work/config/includes.chroot/etc/systemd/system" "$work/config/hooks/live" "$work/config/includes.chroot/etc/systemd/network" "$work/config/includes.chroot/etc/default" "$work/config/includes.chroot/etc"
cp "$src/configs/live-build/auto/config" "$work/auto/config"
cp "$src/configs/live-build/archives/debian-security.list.chroot" "$src/configs/live-build/archives/debian-security.list.binary" "$work/config/archives/"
cp -a /usr/share/live/build/bootloaders/isolinux/. "$work/config/bootloaders/isolinux/"
cp "$src/configs/live-build/bootloaders/isolinux/isolinux.cfg" "$work/config/bootloaders/isolinux/isolinux.cfg"
cp "$src/configs/live-build/bootloaders/isolinux/memtest.cfg" "$work/config/bootloaders/isolinux/memtest.cfg"
install -D -m 0644 "$src/configs/live-build/bootloaders/isolinux/memtest.cfg" "$work/config/includes.binary/isolinux/memtest.cfg"
[[ -s /boot/memtest86+x64.bin ]] || { echo 'Memtest86+ BIOS binary is required for the independent ISOLINUX boot entry.' >&2; exit 2; }
install -D -m 0644 /boot/memtest86+x64.bin "$work/config/includes.binary/boot/memtest86+x64.bin"
if [[ -s /boot/memtest86+x64.efi ]]; then install -D -m 0644 /boot/memtest86+x64.efi "$work/config/includes.binary/EFI/BOOT/memtest86+x64.efi"; fi
cp "$src/configs/live-build/package-lists/paw.list.chroot" "$work/config/package-lists/"
mkdir -p "$work/config/includes.chroot/opt/paw-migration/scripts"
cp "$src"/scripts/paw-*.sh "$work/config/includes.chroot/opt/paw-migration/scripts/"
# Copy every runtime helper, not a hand-maintained subset: the 2.7 atomic
# writer is required by tty/PAWDATA/finalizer and was missed by an explicit
# list in an earlier build.
cp "$src"/scripts/paw-*.py "$work/config/includes.chroot/opt/paw-migration/scripts/"
chmod 0755 "$work/config/includes.chroot/opt/paw-migration/scripts/"*.sh \
  "$work/config/includes.chroot/opt/paw-migration/scripts/"*.py
cp -a "$src/boot/bin" "$work/config/includes.chroot/opt/paw-migration/"
cp "$src/configs/source.template.json" "$src/configs/target-ssd.template.json" "$src/configs/xray-client.template.json" "$work/config/includes.chroot/opt/paw-migration/configs/"
cp "$src/boot/paw-preflight.service" "$src/boot/paw-data-init.service" "$src/boot/paw-console.service" "$src/boot/paw-console-font.service" "$src/boot/paw-network-bootstrap.service" "$src/boot/paw-xray-client.service" "$src/boot/paw-tailscale-join.service" "$work/config/includes.chroot/etc/systemd/system/"
cp "$src/boot/20-wired.network" "$work/config/includes.chroot/etc/systemd/network/20-wired.network"
cp "$src/configs/paw-migration.env.template" "$work/config/includes.chroot/etc/paw-migration.env"
cp "$src/boot/paw-data.mount" "$work/config/includes.chroot/etc/systemd/system/var-lib-paw\\x2dmigration.mount"
cp "$src/boot/tailscaled.service" "$work/config/includes.chroot/etc/systemd/system/tailscaled.service"
cat >"$work/config/includes.chroot/etc/default/tailscaled" <<'TSDEFAULTS'
PORT="41641"
FLAGS=""
TSDEFAULTS
cat >"$work/config/hooks/live/0500-paw-services.hook.chroot" <<'HOOK'
#!/bin/sh
set -eu
install -d /usr/sbin /var/lib/tailscale /var/lib/paw-migration /run/paw-network
install -m 0755 /opt/paw-migration/bin/tailscaled /usr/sbin/tailscaled
install -m 0755 /opt/paw-migration/bin/tailscale /usr/sbin/tailscale
install -d /etc/systemd/system/multi-user.target.wants /etc/systemd/system/local-fs.target.wants /etc/systemd/system/network-online.target.wants /etc/systemd/system/sockets.target.wants
ln -sf ../tailscaled.service /etc/systemd/system/multi-user.target.wants/tailscaled.service
ln -sf ../paw-data-init.service /etc/systemd/system/multi-user.target.wants/paw-data-init.service
ln -sf ../paw-preflight.service /etc/systemd/system/multi-user.target.wants/paw-preflight.service
ln -sf ../paw-console.service /etc/systemd/system/multi-user.target.wants/paw-console.service
ln -sf ../paw-console-font.service /etc/systemd/system/multi-user.target.wants/paw-console-font.service
ln -sf ../paw-network-bootstrap.service /etc/systemd/system/multi-user.target.wants/paw-network-bootstrap.service
ln -sf ../var-lib-paw\\x2dmigration.mount /etc/systemd/system/local-fs.target.wants/var-lib-paw\\x2dmigration.mount
ln -sf /lib/systemd/system/systemd-networkd.service /etc/systemd/system/multi-user.target.wants/systemd-networkd.service
ln -sf /lib/systemd/system/systemd-resolved.service /etc/systemd/system/multi-user.target.wants/systemd-resolved.service
ln -sf /lib/systemd/system/systemd-networkd-wait-online.service /etc/systemd/system/network-online.target.wants/systemd-networkd-wait-online.service
rm -f /etc/systemd/system/multi-user.target.wants/ssh.service /etc/systemd/system/sockets.target.wants/ssh.socket
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
HOOK
chmod 0755 "$work/config/hooks/live/0500-paw-services.hook.chroot"
cat >"$work/config/hooks/live/0550-paw-console-font.hook.chroot" <<'HOOK'
#!/bin/sh
set -eu
install -d -m 0755 /opt/paw-migration/fonts
/usr/bin/python3 /opt/paw-migration/scripts/paw-build-cjk-font.py \
  --unifont /usr/share/unifont/unifont.hex \
  --scan /opt/paw-migration/scripts \
  --out /opt/paw-migration/fonts/paw-cjk-16x16.psf \
  --fallback-out /opt/paw-migration/fonts/paw-cjk-8x16.psf \
  --manifest /opt/paw-migration/fonts/paw-cjk-font.json \
  --unifont-version "$(dpkg-query -W -f='${Version}' unifont)"
chmod 0644 /opt/paw-migration/fonts/paw-cjk-16x16.psf \
  /opt/paw-migration/fonts/paw-cjk-8x16.psf /opt/paw-migration/fonts/paw-cjk-font.json
HOOK
chmod 0755 "$work/config/hooks/live/0550-paw-console-font.hook.chroot"
cat >"$work/config/hooks/live/0600-paw-software-manifest.hook.chroot" <<'HOOK'
#!/bin/sh
set -eu
install -d -m 0755 /usr/share/doc/paw-migration
dpkg-query -W -f='${binary:Package}\t${Version}\t${Architecture}\n' | LC_ALL=C sort > /usr/share/doc/paw-migration/software-packages.lock
HOOK
chmod 0755 "$work/config/hooks/live/0600-paw-software-manifest.hook.chroot"
cat >"$work/config/hooks/live/0650-paw-repro-cleanup.hook.chroot" <<'HOOK'
#!/bin/sh
set -eu
# Files the chroot build generates on the *build host*. They describe the machine that
# built the image rather than the image, they differ between two builds of the same tree, and
# none of them serve a purpose in a live system: systemd regenerates machine-id at boot when
# it is missing, and the apt package caches are rebuilt on demand.
for path in /etc/nvme/hostid /var/lib/systemd/random-seed /etc/machine-id /var/lib/dbus/machine-id \
            /var/cache/apt/pkgcache.bin /var/cache/apt/srcpkgcache.bin; do
  if [ -e "$path" ]; then
    rm -f "$path"
    echo "repro-cleanup: removed $path"
  fi
done
exit 0
HOOK
chmod 0755 "$work/config/hooks/live/0650-paw-repro-cleanup.hook.chroot"
cd "$work"
lb config
lb build
dpkg-query --admindir="$work/chroot/var/lib/dpkg" -W -f='${binary:Package}\t${Version}\t${Architecture}\n' | LC_ALL=C sort >"$work/software-packages.lock"
mkdir -p "$src/boot/custom"
cp "$work/live-image-amd64.hybrid.iso" "$src/boot/custom/paw-live-amd64.iso"
sha256sum "$src/boot/custom/paw-live-amd64.iso" >"$src/boot/custom/paw-live-amd64.iso.sha256"
cp "$work/software-packages.lock" "$src/boot/custom/software-packages.lock"
printf 'Debian package source snapshot: 20261101T000000Z\nBuild SOURCE_DATE_EPOCH: %s\n' "$SOURCE_DATE_EPOCH" >"$src/boot/custom/build-provenance.txt"
echo "Build complete: $src/boot/custom/paw-live-amd64.iso"
