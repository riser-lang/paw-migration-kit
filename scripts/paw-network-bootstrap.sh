#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/paw-lib.sh"
phase="${PAW_NETWORK_PHASE:-$(cat /run/paw-network/network-phase 2>/dev/null || echo RESCUE)}"
case "$phase" in RESCUE|RESTORED_UBUNTU) ;; *) die 'Network phase must be RESCUE or RESTORED_UBUNTU.' ;; esac
"$PAW_ROOT/scripts/paw-network-preflight.sh"
direct_ready=0
if curl --noproxy '*' -fsS -o /dev/null --connect-timeout 5 --max-time 12 'https://controlplane.tailscale.com/key?v=1'; then direct_ready=1; fi

if [[ "$phase" == RESCUE ]]; then
  if ((direct_ready)); then
    printf '{"phase":"RESCUE","state":"DIRECT_NETWORK_READY_FOR_RESCUE_SSH","xray_started":false,"tailscale_joined":false,"updated_at":"%s"}\n' "$(date -u +%FT%TZ)" >"$PAW_REPORT_DIR/network-bootstrap.json"
    log INFO 'Rescue phase has direct network access. Xray and Tailscale join stay stopped; Rescue SSH is independent.'
    exit 0
  fi
  printf '{"phase":"RESCUE","state":"BLOCKED_DIRECT_NETWORK_UNAVAILABLE","xray_started":false,"tailscale_joined":false,"updated_at":"%s"}\n' "$(date -u +%FT%TZ)" >"$PAW_REPORT_DIR/network-bootstrap.json"
  log WARN 'Rescue phase has no direct control-plane access. Xray/Tailscale are not started to avoid a dependency loop.'
  exit 2
fi

if ((direct_ready)); then
  printf '{"phase":"RESTORED_UBUNTU","state":"DIRECT_NETWORK_READY","xray_started":false,"updated_at":"%s"}\n' "$(date -u +%FT%TZ)" >"$PAW_REPORT_DIR/network-bootstrap.json"
  log INFO 'Restored Ubuntu phase has direct network access; Xray stays stopped.'
  exit 0
fi
if [[ ! -r /run/paw-network/xray-client.json ]]; then
  printf '{"phase":"RESTORED_UBUNTU","state":"BLOCKED_MISSING_RAM_ONLY_XRAY_CONFIG","xray_started":false,"updated_at":"%s"}\n' "$(date -u +%FT%TZ)" >"$PAW_REPORT_DIR/network-bootstrap.json"
  log WARN 'Restored Ubuntu phase lacks a user-supplied RAM-only Xray config.'
  exit 2
fi
"$PAW_ROOT/scripts/paw-xray-proxy.sh" start
printf '{"phase":"RESTORED_UBUNTU","state":"XRAY_PROXY_READY_TAILSCALE_NOT_JOINED","xray_started":true,"updated_at":"%s"}\n' "$(date -u +%FT%TZ)" >"$PAW_REPORT_DIR/network-bootstrap.json"
log WARN 'Temporary Xray is ready in restored Ubuntu phase; Tailscale still requires interactive user authorization.'
