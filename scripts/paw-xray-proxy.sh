#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/paw-lib.sh"
action="${1:-status}"; bin="${PAW_XRAY_BIN:-/opt/paw-migration/bin/xray}"; cfg="${PAW_XRAY_CONFIG:-/run/paw-network/xray-client.json}"
unit="paw-xray-client.service"
case "$action" in
  start)
    [[ "$cfg" == /run/paw-network/xray-client.json ]] || die 'Xray client config must be the approved RAM-only path.'
    [[ -x "$bin" && -r "$cfg" ]] || die 'Xray binary or RAM-only client config missing.'
    [[ "$(stat -c %u "$cfg")" == 0 && ( "$(stat -c %a "$cfg")" == 600 || "$(stat -c %a "$cfg")" == 400 ) ]] || die 'Client config must be root-owned and mode 0600/0400.'
    python3 - "$cfg" <<'PY'
import json,sys
d=json.load(open(sys.argv[1])); ins=d.get('inbounds',[])
assert any(x.get('protocol')=='socks' and x.get('listen')=='127.0.0.1' and x.get('port')==10808 for x in ins)
assert any(x.get('protocol')=='http' and x.get('listen')=='127.0.0.1' and x.get('port')==10809 for x in ins)
PY
    install -d -m 700 /run/paw-network
    "$bin" run -test -config "$cfg" >/dev/null 2>&1 || die 'Xray configuration check failed; detail withheld.'
    systemctl start "$unit"
    for _ in $(seq 1 20); do systemctl is-active --quiet "$unit" && break; sleep 1; done
    systemctl is-active --quiet "$unit" || die 'Xray service did not become active.'
    code="$(curl --proxy socks5h://127.0.0.1:10808 -sS -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 15 'https://controlplane.tailscale.com/key?v=1' 2>/dev/null || echo 000)"
    [[ "$code" == 200 ]] || { systemctl stop "$unit" || true; die 'SOCKS proxy connectivity check failed.'; }
    code="$(curl --proxy http://127.0.0.1:10809 -sS -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 15 'https://controlplane.tailscale.com/key?v=1' 2>/dev/null || echo 000)"
    [[ "$code" == 200 ]] || { systemctl stop "$unit" || true; die 'HTTP proxy connectivity check failed.'; }
    log INFO 'Xray temporary loopback proxies passed HTTP checks; secret config remains in RAM.';;
  stop) systemctl stop "$unit"; log INFO 'Temporary Xray service stopped.';;
  status) systemctl is-active "$unit" || true;;
  *) die 'Usage: paw-xray-proxy.sh start|stop|status';;
esac
