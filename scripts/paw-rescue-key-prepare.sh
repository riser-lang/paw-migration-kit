#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/paw-lib.sh"
need ssh-keygen; need ssh-keyscan; need ssh
cfg="$PAW_CONFIG_DIR/source.json"
[[ -r "$cfg" ]] || die 'Source config missing.'
host="$(sed -n 's/.*"ssh_host"[[:space:]]*:[[:space:]]*"\([A-Za-z0-9.-]*\)".*/\1/p' "$cfg")"
port="$(sed -n 's/.*"ssh_port"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$cfg")"
[[ "$host" =~ ^[A-Za-z0-9.-]+$ && "$port" =~ ^[0-9]{1,5}$ ]] || die 'Rescue endpoint config malformed.'
install -d -m 700 /run/paw-network
key=/run/paw-network/rescue_ed25519
if [[ ! -s "$key" ]]; then ssh-keygen -q -t ed25519 -N '' -C paw-rescue-one-time -f "$key"; fi
chmod 600 "$key"; chmod 644 "$key.pub"
printf '%s\n' 'Temporary public key to add in the Rescue Mode VNC session:'
cat "$key.pub"
candidate=/run/paw-network/known_hosts.candidate
ssh-keyscan -T 8 -p "$port" -t ed25519 "$host" 2>/dev/null >"$candidate"
[[ -s "$candidate" ]] || die 'Could not obtain Rescue Mode SSH host key candidate.'
fingerprint="$(ssh-keygen -lf "$candidate" -E sha256 | awk 'NR==1 {print $2}')"
printf 'Compare this candidate fingerprint with the fingerprint shown in Tencent VNC: %s\n' "$fingerprint"
read -r -p 'Paste the VNC fingerprint exactly to pin this host key: ' confirmed
[[ "$confirmed" == "$fingerprint" ]] || die 'Host-key fingerprint mismatch; refusing SSH.'
mv "$candidate" /run/paw-network/known_hosts
chmod 600 /run/paw-network/known_hosts
unset confirmed fingerprint
log INFO 'Ephemeral rescue SSH key and pinned host key are ready in RAM.'
