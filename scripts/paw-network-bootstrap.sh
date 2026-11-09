#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/paw-lib.sh"
"$PAW_ROOT/scripts/paw-network-preflight.sh"
if curl --noproxy '*' -fsS -o /dev/null --connect-timeout 5 --max-time 12 'https://controlplane.tailscale.com/key?v=1'; then
  log INFO 'Direct Tailscale control HTTPS works; Xray stays stopped.'
  printf '{"state":"DIRECT_NETWORK_READY","xray_started":false,"updated_at":"%s"}\n' "$(date -u +%FT%TZ)" >"$PAW_REPORT_DIR/network-bootstrap.json"
  exit 0
fi
if [[ ! -r "${PAW_XRAY_CONFIG:-/run/paw-network/xray-client.json}" ]]; then
  printf '{"state":"BLOCKED_MISSING_XRAY_CLIENT_CONFIG","xray_started":false,"updated_at":"%s"}\n' "$(date -u +%FT%TZ)" >"$PAW_REPORT_DIR/network-bootstrap.json"
  log WARN 'Direct Tailscale control check failed and no protected Xray client config is provisioned.'; exit 2
fi
"$PAW_ROOT/scripts/paw-xray-proxy.sh" start
printf '{"state":"XRAY_PROXY_READY_TAILSCALE_NOT_JOINED","xray_started":true,"updated_at":"%s"}\n' "$(date -u +%FT%TZ)" >"$PAW_REPORT_DIR/network-bootstrap.json"
log WARN 'Temporary Xray is available; Tailscale login requires the dedicated join step and user authorization.'
