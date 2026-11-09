#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/paw-lib.sh"
phase="${PAW_NETWORK_PHASE:-$(cat /run/paw-network/network-phase 2>/dev/null || echo RESCUE)}"
[[ "$phase" == RESTORED_UBUNTU ]] || { log WARN 'Direct-route recovery is disabled during Rescue Mode.'; exit 2; }
dropin=/run/systemd/system/tailscaled.service.d/50-paw-temporary-proxy.conf
backup=/run/paw-network/50-paw-temporary-proxy.conf
[[ -f "$dropin" ]] || { log INFO 'No temporary Tailscale proxy override is active.'; exit 0; }
curl --noproxy '*' -fsS -o /dev/null --connect-timeout 5 --max-time 12 'https://controlplane.tailscale.com/key?v=1' || { log WARN 'Direct Tailscale control HTTPS still fails; keeping Xray.'; exit 2; }
peer="${PAW_TS_PEER_IP:-}"
[[ -n "$peer" && "$peer" =~ ^[A-Za-z0-9:.]+$ ]] || { log WARN 'Tailscale peer is not configured; keeping Xray.'; exit 2; }
timeout 15 tailscale ping "$peer" >/dev/null 2>&1 || { log WARN 'Configured Tailscale peer is not reachable; keeping Xray.'; exit 2; }
cp -p "$dropin" "$backup"; rm -f "$dropin"; systemctl daemon-reload; systemctl restart tailscaled
if curl --noproxy '*' -fsS -o /dev/null --connect-timeout 5 --max-time 12 'https://controlplane.tailscale.com/key?v=1' && timeout 15 tailscale ping "$peer" >/dev/null 2>&1; then
  "$PAW_ROOT/scripts/paw-xray-proxy.sh" stop; rm -f "$backup"; log INFO 'Direct Tailscale control and peer checks passed; Xray stopped.'
else
  install -d -m 755 "$(dirname "$dropin")"; cp -p "$backup" "$dropin"; systemctl daemon-reload; systemctl restart tailscaled
  log WARN 'Direct-route transition failed; Xray route was restored.'; exit 3
fi
