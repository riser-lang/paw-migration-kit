#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/paw-lib.sh"
need tailscale; need curl; need systemctl
run_root="${PAW_RUN_ROOT:-/run}"
ram_dir="$run_root/paw-network"
phase="${PAW_NETWORK_PHASE:-$(cat "$ram_dir/network-phase" 2>/dev/null || echo RESCUE)}"
case "$phase" in
  LIVE|RESTORED_UBUNTU) ;;
  *) log WARN 'Tailscale join is disabled in Rescue Mode; only direct Rescue SSH is used.'; exit 2 ;;
esac
hostname='paw-live-temp'
[[ "$phase" == RESTORED_UBUNTU ]] && hostname="${PAW_FINAL_TS_HOSTNAME:-paw-migration-client}"
proxy_used=0
if ! curl --noproxy '*' -fsS -o /dev/null --connect-timeout 5 --max-time 12 'https://controlplane.tailscale.com/key?v=1'; then
  "$PAW_ROOT/scripts/paw-xray-proxy.sh" start
  if [[ "$phase" == LIVE ]]; then
    "$PAW_ROOT/scripts/paw-tailscaled-proxy.sh" apply-live
  else
    "$PAW_ROOT/scripts/paw-tailscaled-proxy.sh" apply-persistent
  fi
  proxy_used=1
else
  log INFO 'Direct Tailscale control HTTPS is available; Xray was not started.'
fi
set +e
ts_args=(up "--hostname=$hostname")
if [[ "$phase" == LIVE && -r "$ram_dir/tailscale-authkey" ]]; then
  [[ "$(stat -c %u "$ram_dir/tailscale-authkey")" == 0 && "$(stat -c %a "$ram_dir/tailscale-authkey")" == 600 ]] || die 'Ephemeral Tailscale auth key must be root-owned mode 0600.'
  ts_args+=("--auth-key=file:$ram_dir/tailscale-authkey" '--ephemeral')
fi
join_output="$(tailscale "${ts_args[@]}" 2>&1)"; rc=$?
unset ts_args
set -e
login_url="$(grep -Eo 'https://login\.tailscale\.com/a/[A-Za-z0-9]+' <<<"$join_output" | head -n1 || true)"
if [[ -n "$login_url" ]]; then
  python3 - "$PAW_REPORT_DIR/tailscale-login.json" "$login_url" "$phase" <<'PY' | python3 "$PAW_ROOT/scripts/paw-atomic-write.py" "$PAW_REPORT_DIR/tailscale-login.json"
import datetime,json,sys
path,url,phase=sys.argv[1:]
sys.stdout.write(json.dumps({"schema":"paw.tailscale-login.v1","phase":phase,
 "login_url":url,"created_at":datetime.datetime.now(datetime.timezone.utc).isoformat()},
 indent=2)+"\n")
PY
  log WARN 'Tailscale 需要一次性网页授权；登录链接已写入报告。'
fi
unset join_output
if ((rc != 0)) && [[ -z "$login_url" ]]; then log WARN 'Tailscale join did not complete; raw output suppressed.'; exit 2; fi
wait_seconds="${PAW_TAILSCALE_WAIT_SECONDS:-900}"
[[ "$wait_seconds" =~ ^[0-9]{1,5}$ ]] || die 'Invalid Tailscale wait timeout.'
for ((i=0; i<wait_seconds; i++)); do
  if tailscale status --json 2>/dev/null | python3 -c 'import json,sys; d=json.load(sys.stdin); s=d.get("Self",{}); raise SystemExit(0 if d.get("BackendState")=="Running" and s.get("Online") else 1)' 2>/dev/null; then
    ip="$(tailscale ip -4 2>/dev/null | head -n1 || true)"
    # A proxy drop-in is not proof of inheritance; verify /proc/PID/environ.
    if ((proxy_used)); then
      "$PAW_ROOT/scripts/paw-tailscaled-proxy.sh" verify || die 'tailscaled proxy inheritance check failed.'
      "$PAW_ROOT/scripts/paw-xray-proxy.sh" status | grep -qx active || die 'Xray exited after Tailscale came online.'
    fi
    python3 - "$PAW_REPORT_DIR/tailscale-bootstrap.json" "$phase" "$hostname" "$ip" "$proxy_used" <<'PY'
import datetime,json,os,sys
p,phase,hostname,ip,proxy_used=sys.argv[1:]
doc={"schema":"paw.tailscale-bootstrap.v2","state":"TAILSCALE_ONLINE",
 "phase":phase,"hostname":hostname,"ipv4":ip,
 "proxy_used":proxy_used=="1","identity_scope":"temporary_live" if phase=="LIVE" else "persistent_final_ubuntu",
 "exit_node_set":False,"updated_at":datetime.datetime.now(datetime.timezone.utc).isoformat()}
tmp=p+".tmp"
with open(tmp,"w",encoding="utf-8") as h: json.dump(doc,h,indent=2)
os.chmod(tmp,0o600); os.replace(tmp,p)
PY
    peer="${PAW_TS_PEER_IP:-}"
    if [[ -z "$peer" ]]; then
      log WARN 'Node is online; peer reachability remains unverified because PAW_TS_PEER_IP is unset.'
    elif [[ "$peer" =~ ^[A-Za-z0-9:.]+$ ]] && timeout 15 tailscale ping "$peer" >/dev/null 2>&1; then
      log INFO "Node online and configured peer reachable; ipv4=$ip"
      python3 - "$PAW_REPORT_DIR/tailscale-peer-check.json" "$peer" "$ip" <<'PY'
import datetime,json,os,sys
p,peer,ip=sys.argv[1:]
doc={"schema":"paw.tailscale-peer-check.v1","status":"PASS","peer":peer,"local_ipv4":ip,
 "checked_at":datetime.datetime.now(datetime.timezone.utc).isoformat()}
tmp=p+".tmp"
with open(tmp,"w",encoding="utf-8") as h: json.dump(doc,h,indent=2)
os.chmod(tmp,0o600); os.replace(tmp,p)
PY
    else
      log WARN 'Configured Tailscale peer test failed; keep Xray.'; exit 3
    fi
    exit 0
  fi
  sleep 1
done
python3 - "$PAW_REPORT_DIR/tailscale-bootstrap.json" "$phase" "$hostname" "$proxy_used" <<'PY'
import datetime,json,os,sys
p,phase,hostname,proxy_used=sys.argv[1:]
doc={"schema":"paw.tailscale-bootstrap.v2","state":"AWAITING_USER_AUTH_OR_CONTROL_CONNECTIVITY",
 "phase":phase,"hostname":hostname,"proxy_used":proxy_used=="1","exit_node_set":False,
 "updated_at":datetime.datetime.now(datetime.timezone.utc).isoformat()}
tmp=p+".tmp"
with open(tmp,"w",encoding="utf-8") as h: json.dump(doc,h,indent=2)
os.chmod(tmp,0o600); os.replace(tmp,p)
PY
log WARN 'Tailscale did not become online before timeout. Keep Xray; no Exit Node has been set.'; exit 2
