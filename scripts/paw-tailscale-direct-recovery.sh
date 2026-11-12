#!/usr/bin/env bash
# Switch Tailscale from the temporary VLESS/Xray proxy back to a direct route
# only after both control-plane HTTPS and a configured peer are reachable.
# Both RAM-only and persistent drop-ins must be removed, otherwise the next
# reboot silently reintroduces a proxy that points at a stopped Xray.
set -Eeuo pipefail
source "$(dirname "$0")/paw-lib.sh"
run_root="${PAW_RUN_ROOT:-/run}"
unit_root="${PAW_SYSTEMD_ROOT:-/}"
ram_dir="$run_root/paw-network"
phase="${PAW_NETWORK_PHASE:-$(cat "$ram_dir/network-phase" 2>/dev/null || echo RESCUE)}"
[[ "$phase" == RESTORED_UBUNTU ]] || { log WARN 'Direct-route recovery is disabled during Rescue Mode.'; exit 2; }
test_mode="${PAW_TEST_MODE:-0}"

live_dir="$unit_root/run/systemd/system/tailscaled.service.d"
persist_dir="$unit_root/etc/systemd/system/tailscaled.service.d"
live_dropin="$live_dir/50-paw-temporary-proxy.conf"
persist_dropin="$persist_dir/50-paw-vless-proxy.conf"
xray_cfg="$ram_dir/xray-client.json"
backup="$ram_dir/vless-recovery-backup"

direct_ok(){
  curl --noproxy '*' -fsS -o /dev/null --connect-timeout 5 --max-time 12 \
    'https://controlplane.tailscale.com/key?v=1'
}
peer_ok(){
  local peer="${PAW_TS_PEER_IP:-}"
  [[ -n "$peer" && "$peer" =~ ^[A-Za-z0-9:.]+$ ]] || return 1
  timeout 15 tailscale ping "$peer" >/dev/null 2>&1
}
reload_restart(){
  (( test_mode == 1 )) && return 0
  systemctl daemon-reload
  systemctl restart tailscaled
}
stop_xray(){
  (( test_mode == 1 )) && return 0
  systemctl stop paw-xray-client.service 2>/dev/null || true
}
start_xray(){
  (( test_mode == 1 )) && return 0
  systemctl start paw-xray-client.service 2>/dev/null || true
}
proxy_references(){
  grep -R -l -E '127\.0\.0\.1:10809|HTTP_PROXY|HTTPS_PROXY' \
    "$live_dir" "$persist_dir" 2>/dev/null || true
}

had_live=0; had_persist=0; had_xray=0
[[ -f "$live_dropin" ]] && had_live=1
[[ -f "$persist_dropin" ]] && had_persist=1
[[ -f "$xray_cfg" ]] && had_xray=1
if (( ! had_live && ! had_persist && ! had_xray )); then
  log INFO 'No temporary VLESS/Tailscale proxy state is present; nothing to recover.'
  exit 0
fi

# Direct control plane must already work before any proxy state is removed.
if ! direct_ok; then
  log WARN 'Direct Tailscale control HTTPS still fails; keeping Xray and both proxy drop-ins.'
  exit 2
fi
if ! peer_ok; then
  log WARN 'Configured Tailscale peer is not reachable over the direct route; keeping Xray.'
  exit 2
fi

rm -rf "$backup"
install -d -m 0700 "$backup/live" "$backup/persist" "$backup/run"
(( had_live )) && cp -p "$live_dropin" "$backup/live/"
(( had_persist )) && cp -p "$persist_dropin" "$backup/persist/"
(( had_xray )) && cp -p "$xray_cfg" "$backup/run/"
cat >"$backup/state.env" <<EOF
had_live=$had_live
had_persist=$had_persist
had_xray=$had_xray
live_dropin=$live_dropin
persist_dropin=$persist_dropin
xray_cfg=$xray_cfg
EOF
chmod 0600 "$backup/state.env"

rollback(){
  log WARN 'Direct-route verification failed after removing proxy state; restoring it atomically.'
  rm -f "$live_dropin" "$persist_dropin"
  if (( had_live )); then install -D -m 0600 "$backup/live/$(basename "$live_dropin")" "$live_dropin"; fi
  if (( had_persist )); then install -D -m 0600 "$backup/persist/$(basename "$persist_dropin")" "$persist_dropin"; fi
  if (( had_xray )); then install -D -m 0600 "$backup/run/$(basename "$xray_cfg")" "$xray_cfg"; start_xray; fi
  reload_restart
  exit 3
}

rm -f "$live_dropin" "$persist_dropin"
reload_restart
direct_ok || rollback
peer_ok || rollback
stop_xray

# The secret RAM-only Xray config is no longer needed once Tailscale is direct.
rm -f "$xray_cfg" "$ram_dir/tailscale-authkey"
if [[ -n "$(proxy_references)" ]]; then
  log ERROR 'A proxy reference still remains under /run or /etc after recovery.'
  rollback
fi

python3 - "$PAW_REPORT_DIR/vless-recovery.json" "$phase" "$live_dropin" "$persist_dropin" "$xray_cfg" <<'PY'
import datetime,json,os,sys
path,phase,live,persist,xray=sys.argv[1:]
doc={"schema":"paw.vless-recovery.v2","status":"PASS","phase":phase,
 "checked_paths":[live,persist],
 "live_dropin_removed":not os.path.exists(live),
 "persistent_dropin_removed":not os.path.exists(persist),
 "xray_config_removed":not os.path.exists(xray),
 "xray_service_stopped":True,
 "direct_control_https":"PASS","direct_peer_ping":"PASS",
 "rollback_on_failure":True,
 "residual_proxy_references":0,
 "updated_at":datetime.datetime.now(datetime.timezone.utc).isoformat()}
tmp=path+".tmp"
with open(tmp,"w",encoding="utf-8") as h: json.dump(doc,h,indent=2,ensure_ascii=False)
os.chmod(tmp,0o600); os.replace(tmp,path)
PY
rm -rf "$backup"
log INFO 'Direct Tailscale control and peer checks passed; both proxy drop-ins and the Xray config were removed.'
