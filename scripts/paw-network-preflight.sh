#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/paw-lib.sh"
need ip; need getent; need curl; need timedatectl; need timeout
out="$PAW_REPORT_DIR/network-boot-$(date -u +%Y%m%dT%H%M%SZ).txt"
{
  echo "generated_utc=$(date -u +%FT%TZ)"
  echo '== LINKS =='; ip -brief link || true
  echo '== ADDRESSES =='; ip -brief address || true
  echo '== DEFAULT ROUTE =='; ip route show default || true
  echo '== DNS =='; getent ahostsv4 deb.debian.org | head -n 1 || echo DNS_FAIL
  for url in https://deb.debian.org/ https://api.github.com/zen https://controlplane.tailscale.com/key\?v=1; do
    if code="$(curl --noproxy '*' -L -sS -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 12 "$url" 2>/dev/null)"; then :; else code=000; fi
    echo "https_${url#https://}=$code"
  done
  rescue_host="${PAW_RESCUE_TCP_HOST:-}"
  if [[ -z "$rescue_host" ]]; then
    echo 'rescue_endpoint_tcp443=SKIPPED_ENDPOINT_UNCONFIGURED'
  elif [[ "$rescue_host" =~ ^[A-Za-z0-9.-]+$ ]]; then
    if timeout 5 bash -c '>/dev/tcp/$1/443' _ "$rescue_host" 2>/dev/null; then echo 'rescue_endpoint_tcp443=PASS'; else echo 'rescue_endpoint_tcp443=FAIL'; fi
  else
    echo 'rescue_endpoint_tcp443=BLOCKED_INVALID_ENDPOINT'
  fi
  echo "ntp_synchronized=$(timedatectl show -p NTPSynchronized --value 2>/dev/null || echo unknown)"
} | tee "$out"
log INFO "network preflight saved to $out; this is local-link evidence only."
