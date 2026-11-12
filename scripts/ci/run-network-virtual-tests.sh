#!/usr/bin/env bash
set -Eeuo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
out="${PAW_ARTIFACT_DIR:-$PWD/artifacts}"
work="$root/tests/virtual/network-run"
state="$work/state"
mock="$work/mockbin"
run="$work/run"
mkdir -p "$work" "$out" "$state/configs" "$state/reports" "$state/logs" "$mock" "$run/paw-network"
export PAW_ROOT="$root" PAW_STATE_DIR="$state" PAW_CONFIG_DIR="$state/configs" PAW_REPORT_DIR="$state/reports" PAW_LOG_DIR="$state/logs"
export PAW_RUN_ROOT="$run" PAW_TEST_MODE=1
export PATH="$mock:$PATH"
report="$out/network-virtual-test-report.txt"
passed=0; failed=0
cleanup(){ rm -rf "$work"; }
trap cleanup EXIT
pass(){ printf 'PASS %s\n' "$1" >>"$report"; passed=$((passed+1)); }
fail(){ printf 'FAIL %s\n' "$1" >>"$report"; failed=$((failed+1)); }
printf 'Network and staged connectivity virtual tests\n' >"$report"

cat >"$mock/curl" <<'MOCKCURL'
#!/usr/bin/env bash
if [[ ${PAW_TEST_CURL_FAIL:-0} == 1 && " $* " == *" --noproxy "* ]]; then exit 7; fi
if [[ " $* " == *" -w "* ]]; then printf '200'; fi
exit 0
MOCKCURL
cat >"$mock/systemctl" <<'MOCKSYSTEMCTL'
#!/usr/bin/env bash
case "$1" in
  is-active) exit 0 ;;
  start|stop|restart|daemon-reload|set-environment) exit 0 ;;
  *) exit 0 ;;
esac
MOCKSYSTEMCTL
mock_tailscale_ip="$(printf '%s.%s.%s.%s' 100 64 0 1)"
cat >"$mock/tailscale" <<MOCKTAILSCALE
#!/usr/bin/env bash
case "\$1" in
  up) echo 'To authenticate, visit: https://login.tailscale.com/a/testlogin'; exit 0 ;;
  status)
    h="\${PAW_TEST_TS_HOSTNAME:-paw-final-node}"
    if [[ \${PAW_TEST_TS_PENDING:-0} == 1 ]]; then
      printf '{"BackendState":"NeedsLogin","Self":{"Online":false,"HostName":"%s","DNSName":"%s.tailnet.test.","ID":"nTEST"}}\n' "\$h" "\$h"
    else
      printf '{"BackendState":"Running","Self":{"Online":true,"HostName":"%s","DNSName":"%s.tailnet.test.","ID":"nTEST"}}\n' "\$h" "\$h"
    fi
    exit 0 ;;
  ip) echo '$mock_tailscale_ip'; exit 0 ;;
  ping) [[ \${PAW_TEST_PEER_FAIL:-0} == 1 ]] && exit 1; exit 0 ;;
  *) exit 0 ;;
esac
MOCKTAILSCALE
cat >"$mock/xray" <<'MOCKXRAY'
#!/usr/bin/env bash
exit 0
MOCKXRAY
chmod 0755 "$mock/curl" "$mock/systemctl" "$mock/tailscale" "$mock/xray"
export PAW_XRAY_BIN="$mock/xray"

# Xray config generator rejects malformed input and keeps the public key only.
test_uuid="$(python3 -c 'import uuid; print(uuid.uuid4())')"
if printf '%s\0' 'vless.example' '443' "$test_uuid" 'xtls-rprx-vision' 'front.example' 'chrome' 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA' '0123456789abcdef' \
  | python3 "$root/scripts/paw-xray-client-configure.py" "$work/xray-valid.json"; then
  python3 - "$work/xray-valid.json" <<'PY' && pass 'Xray Reality config uses publicKey, loopback inbounds and no privateKey' || fail 'Xray Reality config validation'
import json,sys
d=json.load(open(sys.argv[1]))
assert d['inbounds'][0]['listen']=='127.0.0.1' and d['inbounds'][1]['listen']=='127.0.0.1'
r=d['outbounds'][0]['streamSettings']['realitySettings']
assert 'publicKey' in r and 'privateKey' not in r
PY
else fail 'valid Xray config was rejected'; fi
if printf '%s\0' 'bad address' '443' "$test_uuid" '' 'front.example' 'chrome' 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA' '0123456789abcdef' \
  | python3 "$root/scripts/paw-xray-client-configure.py" "$work/xray-bad.json" >/dev/null 2>&1; then
  fail 'malformed Xray address was accepted'
else pass 'malformed Xray address rejected before writing config'; fi

# Loopback-only proxy start with a bad inbound must fail closed.
install -d -m 0700 $run/paw-network
cp "$work/xray-valid.json" $run/paw-network/xray-client.json
chmod 0600 $run/paw-network/xray-client.json
"$root/scripts/paw-xray-proxy.sh" start >/dev/null 2>&1 && pass 'Valid loopback Xray proxy start passed the connectivity checks' || fail 'Valid Xray proxy start'
any4="$(printf '%s.%s.%s.%s' 0 0 0 0)"
python3 - "$work/xray-valid.json" "$any4" <<'PY' > $run/paw-network/xray-client.json
import json,sys
d=json.load(open(sys.argv[1])); d['inbounds'][0]['listen']=sys.argv[2]; json.dump(d,sys.stdout)
PY
chmod 0600 $run/paw-network/xray-client.json
if "$root/scripts/paw-xray-proxy.sh" start >/dev/null 2>&1; then fail 'Non-loopback Xray inbound was accepted'; else pass 'Non-loopback Xray inbound rejected before start'; fi

# Rescue phase never starts Xray/Tailscale; restored phase may use a RAM-only config.
PAW_TEST_CURL_FAIL=1 PAW_NETWORK_PHASE=RESCUE "$root/scripts/paw-network-bootstrap.sh" >/dev/null 2>&1 && fail 'Rescue phase accepted missing direct network' || pass 'Rescue phase fails closed without direct network'
grep -q 'BLOCKED_DIRECT_NETWORK_UNAVAILABLE' "$PAW_REPORT_DIR/network-bootstrap.json" && pass 'Rescue phase report records blocked direct network' || fail 'Rescue network report state'
PAW_TEST_CURL_FAIL=0 PAW_NETWORK_PHASE=RESCUE "$root/scripts/paw-network-bootstrap.sh" >/dev/null 2>&1 && pass 'Rescue phase passes with direct network and no proxy' || fail 'Rescue phase direct network'
rm -f $run/paw-network/xray-client.json
PAW_TEST_CURL_FAIL=1 PAW_NETWORK_PHASE=RESTORED_UBUNTU "$root/scripts/paw-network-bootstrap.sh" >/dev/null 2>&1 && fail 'Restored phase accepted missing Xray config' || pass 'Restored phase without Xray config is blocked'
grep -q 'BLOCKED_MISSING_RAM_ONLY_XRAY_CONFIG' "$PAW_REPORT_DIR/network-bootstrap.json" && pass 'Restored phase missing-config state is explicit' || fail 'Restored missing-config state'
cp "$work/xray-valid.json" $run/paw-network/xray-client.json
chmod 0600 $run/paw-network/xray-client.json
PAW_TEST_CURL_FAIL=1 PAW_NETWORK_PHASE=RESTORED_UBUNTU "$root/scripts/paw-network-bootstrap.sh" >/dev/null 2>&1 && pass 'Restored phase starts the RAM-only Xray proxy when direct network is unavailable' || fail 'Restored phase Xray path'
grep -q 'XRAY_PROXY_READY' "$PAW_REPORT_DIR/network-bootstrap.json" && pass 'Restored phase records temporary Xray state' || fail 'Restored Xray state'

# Tailscale login wait and online state are explicit; no auth key is written.
# The raw system hostname is dirty on purpose: DNS legalization must produce the
# final node's business name, not a fixed migration-only label.
PAW_NETWORK_PHASE=RESTORED_UBUNTU PAW_FINAL_TS_HOSTNAME='PAW Final_Node!!' PAW_TEST_TS_HOSTNAME='paw-final-node' PAW_TAILSCALE_WAIT_SECONDS=2 "$root/scripts/paw-tailscale-join.sh" >/dev/null 2>&1 && pass 'Final Tailscale join reaches ONLINE with legalized system hostname' || fail 'Tailscale join online path'
grep -q 'TAILSCALE_ONLINE' "$PAW_REPORT_DIR/tailscale-bootstrap.json" && pass 'Tailscale report records ONLINE' || fail 'Tailscale report state'
python3 - "$PAW_REPORT_DIR/tailscale-bootstrap.json" <<'PY' && pass 'Final identity preserves hostname semantics and is verified from status fields' || fail 'Final Tailscale identity fields'
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
assert d["hostname"]=="paw-final-node"
assert d["identity_scope"]=="persistent_final_ubuntu"
assert d["ephemeral"] is False
assert d["reported_hostname"]=="paw-final-node"
assert d["dns_name"].startswith("paw-final-node.")
assert d["identity_verified_from_status_fields"] is True
assert d["identity_inherited_from_old_vps"] is False
PY
rm -f "$PAW_REPORT_DIR/tailscale-bootstrap.json"
PAW_NETWORK_PHASE=RESTORED_UBUNTU PAW_FINAL_TS_HOSTNAME='PAW-Final-Node' PAW_TEST_TS_HOSTNAME='some-other-node' PAW_TAILSCALE_WAIT_SECONDS=2 "$root/scripts/paw-tailscale-join.sh" >/dev/null 2>&1 && fail 'Tailscale identity mismatch was accepted' || pass 'Tailscale identity mismatch fails closed'
[[ ! -e "$PAW_REPORT_DIR/tailscale-bootstrap.json" ]] && pass 'Mismatched Tailscale identity never writes an ONLINE success report' || fail 'Identity mismatch left a success report'
PAW_NETWORK_PHASE=LIVE PAW_LIVE_TS_HOSTNAME='paw-live-temp' PAW_TEST_TS_HOSTNAME='paw-live-temp' PAW_TAILSCALE_WAIT_SECONDS=2 "$root/scripts/paw-tailscale-join.sh" >/dev/null 2>&1 && pass 'Live Tailscale join uses a temporary ephemeral identity' || fail 'Live Tailscale join'
python3 - "$PAW_REPORT_DIR/tailscale-bootstrap.json" <<'PY' && pass 'Live identity is ephemeral and distinct from final Ubuntu' || fail 'Live Tailscale identity fields'
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
assert d["identity_scope"]=="temporary_live" and d["ephemeral"] is True
PY
PAW_NETWORK_PHASE=RESTORED_UBUNTU PAW_FINAL_TS_HOSTNAME='PAW-Final-Node' PAW_TEST_TS_HOSTNAME='paw-final-node' PAW_TAILSCALE_WAIT_SECONDS=2 PAW_TEST_TS_PENDING=1 "$root/scripts/paw-tailscale-join.sh" >/dev/null 2>&1 && fail 'Pending Tailscale authorization was accepted' || pass 'Pending Tailscale authorization times out without false ONLINE'
grep -q 'AWAITING_USER_AUTH_OR_CONTROL_CONNECTIVITY' "$PAW_REPORT_DIR/tailscale-bootstrap.json" && pass 'Tailscale pending state is explicit' || fail 'Tailscale pending state'
[[ ! -e "$state/reports/tailscale-auth-key" ]] && pass 'No Tailscale auth key file was created by the join flow' || fail 'Unexpected Tailscale auth key file'

# VLESS recovery must remove both /run and /etc proxy drop-ins, stop Xray and
# prove direct control+peer before claiming success.  A failure must preserve
# the working proxy state (rollback).
rec="$work/recovery"
mkdir -p "$rec/run/systemd/system/tailscaled.service.d" "$rec/etc/systemd/system/tailscaled.service.d" "$rec/run/paw-network"
printf '[Service]\nEnvironment="HTTPS_PROXY=http://127.0.0.1:10809"\n' >"$rec/run/systemd/system/tailscaled.service.d/50-paw-temporary-proxy.conf"
printf '[Service]\nEnvironment="HTTPS_PROXY=http://127.0.0.1:10809"\n' >"$rec/etc/systemd/system/tailscaled.service.d/50-paw-vless-proxy.conf"
printf '{"inbounds":[]}\n' >"$rec/run/paw-network/xray-client.json"
PAW_NETWORK_PHASE=RESTORED_UBUNTU PAW_TEST_MODE=1 PAW_RUN_ROOT="$rec/run" PAW_SYSTEMD_ROOT="$rec" PAW_TS_PEER_IP='127.0.0.1' "$root/scripts/paw-tailscale-direct-recovery.sh" >/dev/null 2>&1 && pass 'Direct recovery passes with mock control+peer reachability' || fail 'Direct recovery happy path'
[[ ! -e "$rec/run/systemd/system/tailscaled.service.d/50-paw-temporary-proxy.conf" && ! -e "$rec/etc/systemd/system/tailscaled.service.d/50-paw-vless-proxy.conf" ]] && pass 'Both RAM-only and persistent proxy drop-ins were removed' || fail 'Proxy drop-in cleanup'
[[ ! -e "$rec/run/paw-network/xray-client.json" ]] && pass 'Stopped Xray config was removed from RAM' || fail 'Xray config cleanup'
grep -q '"status": "PASS"' "$PAW_REPORT_DIR/vless-recovery.json" && pass 'VLESS recovery report records PASS' || fail 'VLESS recovery report'
printf '[Service]\nEnvironment="HTTPS_PROXY=http://127.0.0.1:10809"\n' >"$rec/run/systemd/system/tailscaled.service.d/50-paw-temporary-proxy.conf"
printf '[Service]\nEnvironment="HTTPS_PROXY=http://127.0.0.1:10809"\n' >"$rec/etc/systemd/system/tailscaled.service.d/50-paw-vless-proxy.conf"
printf '{"inbounds":[]}\n' >"$rec/run/paw-network/xray-client.json"
PAW_NETWORK_PHASE=RESTORED_UBUNTU PAW_TEST_MODE=1 PAW_TEST_CURL_FAIL=1 PAW_RUN_ROOT="$rec/run" PAW_SYSTEMD_ROOT="$rec" PAW_TS_PEER_IP='127.0.0.1' "$root/scripts/paw-tailscale-direct-recovery.sh" >/dev/null 2>&1 && fail 'Recovery removed proxy state while direct control failed' || pass 'Recovery keeps proxy state when direct control fails'
[[ -e "$rec/run/systemd/system/tailscaled.service.d/50-paw-temporary-proxy.conf" && -e "$rec/etc/systemd/system/tailscaled.service.d/50-paw-vless-proxy.conf" ]] && pass 'Failed direct check preserves both proxy drop-ins' || fail 'Failed recovery destroyed proxy state'

grep -q 'Name=en\* eth\*' "$root/boot/20-wired.network" && grep -q 'name: "e\*"' "$root/scripts/paw-offline-repair.sh" && pass 'Wired network config covers en*, eth* and r8169-compatible e* names' || fail 'Netplan/networkd compatibility markers'

printf 'Summary: %s passed, %s failed\n' "$passed" "$failed" >>"$report"
cat "$report"
((failed == 0))
