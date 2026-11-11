#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/paw-lib.sh"
action="${1:-status}"
proxy_url="${PAW_TAILSCALE_PROXY_URL:-http://127.0.0.1:10809}"
proc_root="${PAW_PROC_ROOT:-/proc}"
unit_root="${PAW_SYSTEMD_ROOT:-/}"
test_mode="${PAW_TEST_MODE:-0}"
dropin_dir="$unit_root/run/systemd/system/tailscaled.service.d"
persist_dir="$unit_root/etc/systemd/system/tailscaled.service.d"
live_dropin="$dropin_dir/50-paw-temporary-proxy.conf"
persist_dropin="$persist_dir/50-paw-vless-proxy.conf"

validate_proxy(){
  [[ "$proxy_url" =~ ^http://127\.0\.0\.1:10809$ ]] || die 'Tailscale proxy must be the loopback HTTP inbound http://127.0.0.1:10809.'
}
write_dropin(){
  local path="$1"
  install -d -m 0755 "$(dirname "$path")"
  umask 077
  cat >"$path" <<EOF
[Service]
Environment="HTTP_PROXY=$proxy_url"
Environment="HTTPS_PROXY=$proxy_url"
Environment="http_proxy=$proxy_url"
Environment="https_proxy=$proxy_url"
Environment="NO_PROXY=127.0.0.1,localhost,::1"
Environment="no_proxy=127.0.0.1,localhost,::1"
EOF
  chmod 0600 "$path"
}
reload_restart(){
  (( test_mode == 1 )) && return 0
  systemctl daemon-reload
  systemctl restart tailscaled
}
tailscaled_pid(){
  local pid
  if (( test_mode == 1 )); then
    pid="${PAW_TAILSCALED_TEST_PID:-}"
  else
    pid="$(systemctl show -p MainPID --value tailscaled 2>/dev/null || true)"
  fi
  [[ "$pid" =~ ^[1-9][0-9]*$ ]] || return 1
  printf '%s\n' "$pid"
}
verify_env(){
  local pid envf
  pid="$(tailscaled_pid)" || die 'tailscaled is not running; proxy inheritance cannot be verified.'
  envf="$proc_root/$pid/environ"
  [[ -r "$envf" ]] || die 'tailscaled process environment is unreadable; proxy inheritance cannot be proven.'
  local http https nop
  http="$(tr '\0' '\n' <"$envf" | awk -F= '$1=="HTTP_PROXY"{print $2; exit}')"
  https="$(tr '\0' '\n' <"$envf" | awk -F= '$1=="HTTPS_PROXY"{print $2; exit}')"
  nop="$(tr '\0' '\n' <"$envf" | awk -F= '$1=="NO_PROXY"{print $2; exit}')"
  [[ "$http" == "$proxy_url" && "$https" == "$proxy_url" ]] || die 'tailscaled did not inherit the loopback proxy environment.'
  [[ "$nop" == *127.0.0.1* ]] || die 'tailscaled NO_PROXY does not exempt loopback.'
  python3 - "$PAW_REPORT_DIR/tailscaled-proxy.json" "$pid" "$http" "$https" "$nop" <<'PY'
import datetime,json,os,sys
path,pid,http,https,nop=sys.argv[1:]
doc={"schema":"paw.tailscaled-proxy.v1","status":"PASS","main_pid":int(pid),
 "http_proxy":http,"https_proxy":https,"no_proxy":nop,
 "verified_from":"/proc/PID/environ","loopback_only":True,
 "updated_at":datetime.datetime.now(datetime.timezone.utc).isoformat()}
tmp=path+".tmp"
with open(tmp,"w",encoding="utf-8") as h: json.dump(doc,h,indent=2,ensure_ascii=False)
os.chmod(tmp,0o600); os.replace(tmp,path)
PY
}
case "$action" in
  apply-live)
    validate_proxy
    write_dropin "$live_dropin"
    reload_restart
    verify_env
    log INFO 'tailscaled inherited the RAM-only loopback HTTP proxy (Live).';;
  apply-persistent)
    validate_proxy
    write_dropin "$persist_dropin"
    reload_restart
    verify_env
    log INFO 'tailscaled inherited the persistent loopback HTTP proxy (final Ubuntu).';;
  remove)
    rm -f "$live_dropin" "$persist_dropin"
    (( test_mode == 1 )) || { systemctl daemon-reload; systemctl try-restart tailscaled || true; }
    log INFO 'Tailscale proxy drop-ins removed; direct mode restored.';;
  verify) validate_proxy; verify_env;;
  status)
    if tailscaled_pid >/dev/null 2>&1; then echo 'tailscaled=active'; else echo 'tailscaled=inactive'; fi
    [[ -e "$live_dropin" ]] && echo 'live_dropin=present' || echo 'live_dropin=absent'
    [[ -e "$persist_dropin" ]] && echo 'persistent_dropin=present' || echo 'persistent_dropin=absent';;
  *) die 'Usage: paw-tailscaled-proxy.sh apply-live|apply-persistent|remove|verify|status';;
esac
