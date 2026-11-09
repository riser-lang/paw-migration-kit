#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/paw-lib.sh"
need python3
[[ "$(findmnt -n -o FSTYPE --target /run 2>/dev/null || true)" == tmpfs ]] || die '/run is not tmpfs; refusing to write Xray credentials.'
install -d -m 0700 /run/paw-network
umask 077

read -r -p 'VLESS 服务端地址（按服务端配置输入；不会回显到日志）：' address
read -r -p 'VLESS 服务端端口：' port
read -r -s -p 'VLESS UUID（输入时不回显）：' uuid; printf '\n'
read -r -p 'flow（按服务端配置；无则留空）：' flow
read -r -p 'Reality serverName（按服务端配置）：' server_name
read -r -p 'uTLS fingerprint（按服务端配置/批准值）：' fingerprint
read -r -p 'Reality 客户端 publicKey（服务端公钥；不得输入 privateKey）：' public_key
read -r -p 'Reality shortId（按服务端配置）：' short_id

tmp=/run/paw-network/xray-client.json.tmp
out=/run/paw-network/xray-client.json
printf '%s\0' "$address" "$port" "$uuid" "$flow" "$server_name" "$fingerprint" "$public_key" "$short_id" | python3 "$PAW_ROOT/scripts/paw-xray-client-configure.py" "$tmp"
unset uuid public_key
if ! "${PAW_XRAY_BIN:-/opt/paw-migration/bin/xray}" run -test -config "$tmp" >/dev/null 2>&1; then
  rm -f "$tmp" "$out"
  die 'Xray rejected the RAM-only client configuration; credential values were not logged.'
fi
mv "$tmp" "$out"; chown root:root "$out"; chmod 0600 "$out"
log INFO 'Xray client config validated and stored in RAM only; no config values were logged.'
