#!/usr/bin/env bash
set -Eeuo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="${RUNNER_TEMP:-/tmp}/paw-dependencies"
mkdir -p "$tmp/tailscale" "$root/boot/bin" "$PAW_ARTIFACT_DIR"

# Tailscale package payload is fetched through its signed Debian APT repository.
install -d -m 0755 /usr/share/keyrings
curl --fail --location --silent --show-error \
  https://pkgs.tailscale.com/stable/debian/trixie.noarmor.gpg \
  -o /usr/share/keyrings/tailscale-archive-keyring.gpg
curl --fail --location --silent --show-error \
  https://pkgs.tailscale.com/stable/debian/trixie.tailscale-keyring.list \
  -o /etc/apt/sources.list.d/tailscale.list
apt-get update -qq
(cd "$tmp/tailscale" && apt-get download tailscale)
deb="$(find "$tmp/tailscale" -maxdepth 1 -name 'tailscale_*.deb' -print -quit)"
[[ -n "$deb" ]]
tailscale_version="$(dpkg-deb -f "$deb" Version)"
dpkg-deb -x "$deb" "$tmp/tailscale/root"
install -m 0755 "$tmp/tailscale/root/usr/bin/tailscale" "$root/boot/bin/tailscale"
install -m 0755 "$tmp/tailscale/root/usr/sbin/tailscaled" "$root/boot/bin/tailscaled"

# Xray archive digest is published by its official GitHub release.
xray_base="https://github.com/XTLS/Xray-core/releases/download/v26.3.27"
# Let curl apply its capped exponential backoff for transient GitHub release 5xx responses.
curl --fail --location --silent --show-error --retry 10 --retry-all-errors --retry-max-time 600 --max-time 300 "$xray_base/Xray-linux-64.zip" -o "$tmp/Xray-linux-64.zip"
curl --fail --location --silent --show-error --retry 10 --retry-all-errors --retry-max-time 600 --max-time 300 "$xray_base/Xray-linux-64.zip.dgst" -o "$tmp/Xray-linux-64.zip.dgst"
xray_expected="$(awk -F'= *' '/^SHA2-256=/ {print $2; exit}' "$tmp/Xray-linux-64.zip.dgst" | tr '[:upper:]' '[:lower:]')"
xray_actual="$(sha256sum "$tmp/Xray-linux-64.zip" | awk '{print $1}')"
[[ -n "$xray_expected" && "$xray_actual" == "$xray_expected" ]] || { echo 'Xray release digest mismatch.' >&2; exit 1; }
unzip -p "$tmp/Xray-linux-64.zip" xray >"$root/boot/bin/xray"
chmod 0755 "$root/boot/bin/xray"

{
  echo 'Verified dependency manifest'
  echo "Tailscale package: $tailscale_version (Debian package from Tailscale signed stable repository)"
  echo "Tailscale binary: $("$root/boot/bin/tailscale" version | head -n1)"
  echo "Xray release: v26.3.27"
  echo "Xray archive SHA2-256: $xray_actual"
  echo "Tailscale binary SHA256: $(sha256sum "$root/boot/bin/tailscale" | awk '{print $1}')"
  echo "Tailscaled binary SHA256: $(sha256sum "$root/boot/bin/tailscaled" | awk '{print $1}')"
  echo "Xray binary SHA256: $(sha256sum "$root/boot/bin/xray" | awk '{print $1}')"
} >"$PAW_ARTIFACT_DIR/software-manifest.txt"
