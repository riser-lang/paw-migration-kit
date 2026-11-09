#!/usr/bin/env bash
set -Eeuo pipefail
src="$(cd "$(dirname "$0")/.." && pwd)"
work="${PAW_BUILD_WORK:-$HOME/paw-live-build}"
[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo 'live-build requires root in the Linux build environment; this script will not sudo or elevate.' >&2; exit 2; }
command -v lb >/dev/null 2>&1 || { echo 'Install Debian live-build in the approved Linux build environment first.' >&2; exit 2; }
mkdir -p "$work/config/auto" "$work/config/package-lists" "$work/config/includes.chroot/opt/paw-migration" "$work/config/includes.chroot/opt/paw-migration/configs" "$work/config/includes.chroot/etc/systemd/system" "$work/config/hooks/live" "$work/config/includes.chroot/etc/systemd/network" "$work/config/includes.chroot/etc/default" "$work/config/includes.chroot/etc"
cp "$src/configs/live-build/auto/config" "$work/config/auto/config"
cp "$src/configs/live-build/package-lists/paw.list.chroot" "$work/config/package-lists/"
mkdir -p "$work/config/includes.chroot/opt/paw-migration/scripts"
cp "$src"/scripts/paw-*.sh "$work/config/includes.chroot/opt/paw-migration/scripts/"
cp -a "$src/boot/bin" "$work/config/includes.chroot/opt/paw-migration/"
cp "$src/configs/source.template.json" "$src/configs/target-ssd.template.json" "$src/configs/xray-client.template.json" "$work/config/includes.chroot/opt/paw-migration/configs/"
cp "$src/boot/paw-preflight.service" "$src/boot/paw-network-bootstrap.service" "$src/boot/paw-xray-client.service" "$src/boot/paw-tailscale-join.service" "$work/config/includes.chroot/etc/systemd/system/"
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
ln -sf ../paw-preflight.service /etc/systemd/system/multi-user.target.wants/paw-preflight.service
ln -sf ../paw-network-bootstrap.service /etc/systemd/system/multi-user.target.wants/paw-network-bootstrap.service
ln -sf ../paw-tailscale-join.service /etc/systemd/system/multi-user.target.wants/paw-tailscale-join.service
ln -sf ../var-lib-paw\\x2dmigration.mount /etc/systemd/system/local-fs.target.wants/var-lib-paw\\x2dmigration.mount
ln -sf /lib/systemd/system/systemd-networkd.service /etc/systemd/system/multi-user.target.wants/systemd-networkd.service
ln -sf /lib/systemd/system/systemd-resolved.service /etc/systemd/system/multi-user.target.wants/systemd-resolved.service
ln -sf /lib/systemd/system/systemd-networkd-wait-online.service /etc/systemd/system/network-online.target.wants/systemd-networkd-wait-online.service
rm -f /etc/systemd/system/multi-user.target.wants/ssh.service /etc/systemd/system/sockets.target.wants/ssh.socket
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
HOOK
chmod 0755 "$work/config/hooks/live/0500-paw-services.hook.chroot"
cd "$work"
lb config
lb build
mkdir -p "$src/boot/custom"
cp "$work/live-image-amd64.hybrid.iso" "$src/boot/custom/paw-live-amd64.iso"
sha256sum "$src/boot/custom/paw-live-amd64.iso" >"$src/boot/custom/paw-live-amd64.iso.sha256"
echo "Build complete: $src/boot/custom/paw-live-amd64.iso"
