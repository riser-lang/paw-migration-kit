#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/paw-lib.sh"
need tailscale; need curl; need systemctl
if ! curl --noproxy '*' -fsS -o /dev/null --connect-timeout 5 --max-time 12 'https://controlplane.tailscale.com/key?v=1'; then
  "$PAW_ROOT/scripts/paw-xray-proxy.sh" start
  install -d -m 755 /run/systemd/system/tailscaled.service.d
  cat >/run/systemd/system/tailscaled.service.d/50-paw-temporary-proxy.conf <<'EOF'
[Service]
Environment="HTTP_PROXY=http://127.0.0.1:10809"
Environment="HTTPS_PROXY=http://127.0.0.1:10809"
Environment="http_proxy=http://127.0.0.1:10809"
Environment="https_proxy=http://127.0.0.1:10809"
EOF
  systemctl daemon-reload; systemctl restart tailscaled
else
  log INFO 'Direct Tailscale control HTTPS is available; Xray was not started.'
fi
set +e
join_output="$(tailscale up --hostname=paw-wuhan-staging 2>&1)"; rc=$?
set -e
login_url="$(grep -Eo 'https://login\.tailscale\.com/a/[A-Za-z0-9]+' <<<"$join_output" | head -n1 || true)"
if [[ -n "$login_url" ]]; then printf 'Approve this one-time Tailscale login in your browser: %s\n' "$login_url"; fi
unset join_output
if ((rc != 0)) && [[ -z "$login_url" ]]; then log WARN 'Tailscale join did not complete; raw output suppressed.'; exit 2; fi
wait_seconds="${PAW_TAILSCALE_WAIT_SECONDS:-900}"
[[ "$wait_seconds" =~ ^[0-9]{1,5}$ ]] || die 'Invalid Tailscale wait timeout.'
for ((i=0; i<wait_seconds; i++)); do
  if tailscale status --json 2>/dev/null | python3 -c 'import json,sys; d=json.load(sys.stdin); s=d.get("Self",{}); raise SystemExit(0 if d.get("BackendState")=="Running" and s.get("Online") else 1)' 2>/dev/null; then
    ip="$(tailscale ip -4 2>/dev/null | head -n1 || true)"
    printf '{"state":"TAILSCALE_ONLINE","hostname":"paw-wuhan-staging","ipv4":"%s","updated_at":"%s"}\n' "$ip" "$(date -u +%FT%TZ)" >"$PAW_REPORT_DIR/tailscale-bootstrap.json"
    peer="${PAW_TS_PEER_IP:-}"
    if [[ -z "$peer" ]]; then
      log WARN 'Staging node is online; peer reachability remains unverified because PAW_TS_PEER_IP is unset.'
    elif [[ "$peer" =~ ^[A-Za-z0-9:.]+$ ]] && timeout 15 tailscale ping "$peer" >/dev/null 2>&1; then
      log INFO "Staging node online and configured peer reachable; ipv4=$ip"
    else
      log WARN 'Configured Tailscale peer test failed; keep Xray.'; exit 3
    fi
    exit 0
  fi
  sleep 1
done
printf '{"state":"AWAITING_USER_AUTH_OR_CONTROL_CONNECTIVITY","hostname":"paw-wuhan-staging","updated_at":"%s"}\n' "$(date -u +%FT%TZ)" >"$PAW_REPORT_DIR/tailscale-bootstrap.json"
log WARN 'Tailscale did not become online before timeout. Keep Xray; no Exit Node has been set.'; exit 2
