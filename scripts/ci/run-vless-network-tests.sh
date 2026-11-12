#!/usr/bin/env bash
set -Eeuo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d /tmp/paw-vless-tests.XXXXXX)"
trap 'rm -rf "$tmp"; [[ -n ${listener_pid:-} ]] && kill "$listener_pid" 2>/dev/null || true; [[ -n ${tail_pid:-} ]] && kill "$tail_pid" 2>/dev/null || true' EXIT
export PAW_STATE_DIR="$tmp/state" PAW_RUN_ROOT="$tmp/run" PAW_REPORT_DIR="$tmp/state/reports" PAW_LOG_DIR="$tmp/state/logs" PAW_CONFIG_DIR="$tmp/state/configs"
export PAW_TEST_MODE=1 PAW_SYSTEMD_ROOT="$tmp/systemd" PAW_PROC_ROOT=/proc
# Most proxy checks in this suite expect the simulated loopback proxy to answer
# 200; the failure-path cases override this to 0 on the individual command.
export PAW_FAKE_PROXY_OK=1
mkdir -p "$PAW_STATE_DIR" "$PAW_RUN_ROOT/paw-network" "$PAW_SYSTEMD_ROOT/run/systemd/system" "$PAW_SYSTEMD_ROOT/etc/systemd/system" "$tmp/bin"
fake="$tmp/bin"
cat >"$fake/curl" <<'C'
#!/bin/sh
proxied=0
for a in "$@"; do case "$a" in --proxy*) proxied=1;; esac; done
if [ "$proxied" = 1 ]; then
  [ "${PAW_FAKE_PROXY_OK:-0}" = 1 ] && { printf 200; exit 0; }
else
  [ "${PAW_FAKE_DIRECT_OK:-0}" = 1 ] && { printf 200; exit 0; }
fi
printf 000; exit 7
C
cat >"$fake/tailscale" <<'T'
#!/bin/sh
case "$1" in
 up) printf 'https://login.tailscale.com/a/test123\n'; exit 0;;
 status)
  if [ "${PAW_TS_PENDING:-0}" = 1 ]; then printf '{"BackendState":"NeedsLogin","Self":{"Online":false}}\n'; else
   if [ "${PAW_TS_EXIT_ONLINE:-0}" = 1 ]; then printf '{"BackendState":"Running","Self":{"Online":true},"ExitNodeStatus":{"Online":true}}\n'; else printf '{"BackendState":"Running","Self":{"Online":true}}\n'; fi
  fi;;
 ip) printf '100.%s.0.5\n' 64;;
 ping) exit 0;;
 set) exit 0;;
 version) echo '1.80.0';;
 *) exit 0;;
esac
T
cat >"$fake/systemctl" <<'S'
#!/bin/sh
case "$1" in is-active) if [ "${PAW_FAKE_XRAY_STATUS:-active}" = active ]; then echo active; exit 0; else echo inactive; exit 3; fi;; show) exit 0;; *) exit 0;; esac
S
cat >"$fake/ip" <<'I'
#!/bin/sh
echo '1: lo: <LOOPBACK,UP> mtu 65536'
echo '2: eth0: <BROADCAST,UP> mtu 1500'
I
cat >"$fake/getent" <<'G'
#!/bin/sh
echo '127.0.0.1 deb.debian.org'
G
cat >"$fake/timedatectl" <<'D'
#!/bin/sh
echo yes
D
chmod +x "$fake"/*
export PATH="$fake:$PATH"
xray="$root/boot/bin/xray"; [[ -x "$xray" ]] || { echo 'bundled xray missing'; exit 1; }
export PAW_XRAY_BIN="$xray"
# Detach the fake tailscaled from the command-substitution pipe; otherwise the
# substitution blocks until the 300s sleep exits and the suite never starts.
tail_pid="$(env HTTP_PROXY=http://127.0.0.1:10809 HTTPS_PROXY=http://127.0.0.1:10809 NO_PROXY=127.0.0.1,localhost sleep 300 >/dev/null 2>&1 & echo $!)"
pass=0; fail=0
ok(){ pass=$((pass+1)); printf 'PASS %02d %s\n' "$pass" "$1"; }
bad(){ fail=$((fail+1)); printf 'FAIL %02d %s\n' "$((pass+fail))" "$1"; }
check(){ local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }

# 1 direct success through the wizard
rm -rf "$PAW_RUN_ROOT/paw-network"; mkdir -p "$PAW_RUN_ROOT/paw-network"
if PAW_NETWORK_CHOICE=direct PAW_NETWORK_PHASE=LIVE PAW_FAKE_DIRECT_OK=1 "$root/scripts/paw-network-wizard.sh" >/dev/null 2>&1 && python3 - "$PAW_REPORT_DIR/tailscale-bootstrap.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1])); assert d["state"]=="TAILSCALE_ONLINE" and d["phase"]=="LIVE" and d["proxy_used"] is False
PY
then ok 'Live direct Tailscale path (simulated)'; else bad 'Live direct Tailscale path'; fi

# 2 direct failure fails closed, does not fabricate online
if ! PAW_NETWORK_CHOICE=direct PAW_NETWORK_PHASE=LIVE PAW_FAKE_DIRECT_OK=0 "$root/scripts/paw-network-wizard.sh" >/dev/null 2>&1; then ok 'direct failure fails closed'; else bad 'direct failure was accepted'; fi

# 3 VPS reachable + 4 VLESS path, 5 client, 6 HTTP inbound
# Bind an ephemeral port so a stale listener from an interrupted run cannot
# make the reachability check pass against the wrong process.
port_file="$tmp/vless-port"
python3 - "$port_file" <<'PY' &
import socket,sys,time
s=socket.socket(); s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1); s.bind(("127.0.0.1",0)); s.listen(8)
with open(sys.argv[1],"w") as h: h.write(str(s.getsockname()[1]))
while True:
    c,_=s.accept(); c.close()
PY
listener_pid=$!
for _ in $(seq 1 50); do [[ -s "$port_file" ]] && break; sleep 0.2; done
[[ -s "$port_file" ]] || { echo 'listener did not start'; exit 1; }
vless_port="$(cat "$port_file")"
cat >"$tmp/vless.uri" <<U
vless://11111111-2222-3333-4444-555555555555@127.0.0.1:$vless_port?type=tcp&security=reality&sni=example.test&fp=chrome&pbk=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA&sid=abcd&flow=xtls-rprx-vision
U
python3 "$root/scripts/paw-vless-uri-import.py" "$PAW_RUN_ROOT/paw-network/xray-client.json" <"$tmp/vless.uri" >/dev/null 2>&1 || true
chmod 0600 "$PAW_RUN_ROOT/paw-network/xray-client.json"
if PAW_NETWORK_CHOICE=vps PAW_NETWORK_PHASE=LIVE PAW_FAKE_DIRECT_OK=0 PAW_FAKE_PROXY_OK=1 PAW_TAILSCALED_TEST_PID="$tail_pid" "$root/scripts/paw-network-wizard.sh" >/dev/null 2>&1; then ok 'VPS online + VLESS wizard path (simulated)'; else bad 'VPS online + VLESS wizard path'; fi
python3 - "$PAW_RUN_ROOT/paw-network/xray-client.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1])); ins=d["inbounds"]
assert [i["port"] for i in ins]==[10808,10809] and all(i["listen"]=="127.0.0.1" for i in ins)
assert "privateKey" not in json.dumps(d)
PY
ok 'Xray config loopback-only, no private key'
check 'bundled Xray v26.3.27 test mode starts' "$root/scripts/paw-xray-proxy.sh" start
check 'HTTP proxy inbound is loopback 10809' grep -q '"port": 10809' "$PAW_RUN_ROOT/paw-network/xray-client.json"

# 7 tailscaled inherits proxy /proc/PID/environ
if PAW_TAILSCALED_TEST_PID="$tail_pid" "$root/scripts/paw-tailscaled-proxy.sh" apply-live >/dev/null 2>&1 && python3 -c 'import json,sys; assert json.load(open(sys.argv[1]))["status"]=="PASS"' "$PAW_REPORT_DIR/tailscaled-proxy.json"; then ok 'tailscaled proxy proven from /proc/PID/environ'; else bad 'tailscaled proxy proof'; fi

# 8/9/10 login, IP, Windows peer
python3 - "$PAW_REPORT_DIR/tailscale-bootstrap.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1])); assert d["ipv4"]=="100.%s.0.5" % 64
PY
ok 'Tailscale IPv4 obtained (simulated)'
TS_PEER="$(printf '100.%s.0.9' 64)"; PAW_NETWORK_PHASE=LIVE PAW_TS_PEER_IP="$TS_PEER" PAW_TAILSCALED_TEST_PID="$tail_pid" "$root/scripts/paw-tailscale-join.sh" >/dev/null 2>&1 || true
python3 - "$PAW_REPORT_DIR/tailscale-peer-check.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1])); assert d["status"]=="PASS" and d["peer"]=="100.%s.0.9" % 64
PY
ok 'Windows peer reachability recorded (simulated)'

# 11 Xray loss is not treated as online
if ! PAW_FAKE_XRAY_STATUS=inactive PAW_NETWORK_PHASE=LIVE PAW_FAKE_DIRECT_OK=0 PAW_FAKE_PROXY_OK=1 "$root/scripts/paw-tailscale-join.sh" >/dev/null 2>&1; then ok 'Xray loss fails closed, no false ONLINE'; else bad 'Xray loss fabricated ONLINE'; fi

# 12 Rescue never starts Xray/Tailscale
PAW_NETWORK_PHASE=RESCUE PAW_FAKE_DIRECT_OK=1 "$root/scripts/paw-network-bootstrap.sh" >/dev/null 2>&1
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["xray_started"] is False and d["tailscale_joined"] is False' "$PAW_REPORT_DIR/network-bootstrap.json"
ok 'Rescue direct path keeps Xray/Tailscale off'

# 13 VLESS interruption is bounded
if ! PAW_NETWORK_CHOICE=vps PAW_NETWORK_PHASE=LIVE PAW_FAKE_DIRECT_OK=0 PAW_FAKE_PROXY_OK=0 PAW_XRAY_CONFIG="$PAW_RUN_ROOT/paw-network/xray-client.json" timeout 20 "$root/scripts/paw-network-wizard.sh" >/dev/null 2>&1; then ok 'VLESS interruption fails fast'; else bad 'VLESS interruption retried forever'; fi

# 14 Rescue SSH is direct and separate
PAW_NETWORK_PHASE=RESCUE PAW_FAKE_DIRECT_OK=1 "$root/scripts/paw-network-bootstrap.sh" >/dev/null 2>&1
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert "RESCUE_SSH" in d["state"]' "$PAW_REPORT_DIR/network-bootstrap.json"
ok 'Rescue SSH direct path independent of VLESS'

# 15 clone/verify/repair/expand never call Tailscale/Xray
if ! grep -Eq 'tailscale (up|login|status|ip|ping|set)|xray run|paw-xray|paw-vless|vless://' "$root/scripts/paw-stream-clone.sh" "$root/scripts/paw-stream-verify.sh" "$root/scripts/paw-offline-repair.sh" "$root/scripts/paw-gpt-expand.sh"; then ok 'clone chain independent of network identity'; else bad 'clone chain references network identity'; fi

# 16 first boot distinguishes pre-reboot handoff from actual first boot
grep -q 'actual_first_boot_performed' "$root/scripts/paw-preboot-handoff-check.sh" && grep -q 'run/live' "$root/scripts/paw-firstboot-check.sh" && ok 'firstboot semantics separate preboot/first boot' || bad 'firstboot semantics'

# 17 Xray packaged and pinned in ISO build
grep -q '8255dd939c34cf966cc91517b6324dd3c8d0bcf49ffac8beca049a38c46845ed' "$root/scripts/build-debian-live.sh" && [[ "$(sha256sum "$xray" | awk '{print $1}')" == 8255dd939c34cf966cc91517b6324dd3c8d0bcf49ffac8beca049a38c46845ed ]] && ok 'Xray v26.3.27 pinned for Live ISO' || bad 'Xray ISO pin'

# 18 independent final identity (no tailscaled.state copied)
mkdir -p "$tmp/newroot/etc/ssh" "$tmp/newroot/etc/systemd/system/multi-user.target.wants" "$tmp/newroot/var/lib/tailscale"
printf 'new-machine\n' >"$tmp/newroot/etc/machine-id"; printf 'paw-new\n' >"$tmp/newroot/etc/hostname"; printf 'ssh-ed25519 AAAATEST new\n' >"$tmp/newroot/etc/ssh/ssh_host_ed25519_key.pub"
printf '{"device_path":"/dev/test"}\n' >"$tmp/source.json"
if python3 "$root/scripts/paw-service-cutover-manifest.py" --source-config "$tmp/source.json" --target-root "$tmp/newroot" --old-hostname paw-old --old-machine-id old-machine --old-ssh-fingerprint deadbeef --output "$tmp/identity.json" >/dev/null 2>&1 && python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); c=d["isolation_checks"]; assert c["machine_id_changed"] and c["ssh_host_key_changed"] and c["tailscale_state_not_copied"]' "$tmp/identity.json"; then ok 'final Ubuntu identity isolation'; else bad 'final Ubuntu identity isolation'; fi

# 19/20 gateway-only plan disables business and detects duplicates
cat >"$tmp/old.json" <<'J'
{"old":{"enabled_services":["ssh.service","xray.service","paw-mcp.service","gpt-mcp.service","claude-mcp.service","spark-mcp.service","nginx.service","cos-upload.timer"]}}
J
cat >"$tmp/new.json" <<'J'
{"new":{"enabled_services":["paw-mcp.service","xray.service","ssh.service"]}}
J
python3 "$root/scripts/paw-gateway-only-plan.py" --old-manifest "$tmp/old.json" --new-manifest "$tmp/new.json" --output "$tmp/gateway.json" >/dev/null 2>&1 || true
python3 - "$tmp/gateway.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1])); rows={r["unit"]:r for r in d["rows"]}
assert rows["xray.service"]["action"]=="KEEP" and rows["paw-mcp.service"]["action"]=="DISABLE"
assert rows["nginx.service"]["action"]=="DISABLE" and d["duplicate_business_units"]
PY
ok 'gateway-only allow-list and business disable plan'
ok 'old/new duplicate business services detected'

# 21 Exit Node plan is optional and armed
"$root/scripts/paw-tailscale-exit-node.sh" plan >/dev/null 2>&1 && ok 'Exit Node remains optional plan' || bad 'Exit Node plan'
PAW_TS_EXIT_ONLINE=1 "$root/scripts/paw-tailscale-exit-node.sh" status >/dev/null 2>&1 && ok 'Exit Node status observation (simulated)' || bad 'Exit Node status'

# 22 invalid VLESS config rejected without secret output
baduri="vless://not-a-uuid$(printf '@')example.test:443?security=reality"
if ! out="$(printf '%s' "$baduri" | python3 "$root/scripts/paw-vless-uri-import.py" "$tmp/bad.json" 2>&1)"; then [[ "$out" != *'not-a-uuid'* ]] && ok 'invalid VLESS rejected without echoing secret' || bad 'invalid VLESS leaked input'; else bad 'invalid VLESS accepted'; fi

# 23 authorization cancel changes nothing
before="$(find "$PAW_RUN_ROOT/paw-network" -type f | sort | xargs -r sha256sum)"
PAW_NETWORK_CHOICE=cancel PAW_NETWORK_PHASE=LIVE "$root/scripts/paw-network-wizard.sh" >/dev/null 2>&1
after="$(find "$PAW_RUN_ROOT/paw-network" -type f | sort | xargs -r sha256sum)"
[[ "$before" == "$after" ]] && ok 'operator cancel leaves network state unchanged' || bad 'cancel changed network state'

# 24 proxy removal restores direct mode
"$root/scripts/paw-tailscaled-proxy.sh" remove >/dev/null 2>&1 && [[ ! -e "$PAW_SYSTEMD_ROOT/run/systemd/system/tailscaled.service.d/50-paw-temporary-proxy.conf" ]] && ok 'proxy removal restores direct mode' || bad 'proxy removal'

# 25 proxy loss fails inheritance proof
tail_pid="$(env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy sleep 300 >/dev/null 2>&1 & echo $!)"
if ! PAW_TAILSCALED_TEST_PID="$tail_pid" "$root/scripts/paw-tailscaled-proxy.sh" verify >/dev/null 2>&1; then ok 'proxy loss fails closed (no false PASS)'; else bad 'proxy loss fabricated PASS'; fi

printf '\nRESULT passed=%d failed=%d\n' "$pass" "$fail"
[[ "$fail" == 0 ]]
