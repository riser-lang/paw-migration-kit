#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/paw-lib.sh"
dev="${1:-}"; [[ -b "$dev" ]] || die 'Usage: paw-ssd-read-scan.sh /dev/disk'
need badblocks; need timeout; assert_unmounted "$dev"
[[ ${PAW_SIMULATION:-0} != 1 ]] || assert_sim_loop_device "$dev"
duration="${PAW_READ_SCAN_TIMEOUT:-24h}"
[[ "$duration" =~ ^[1-9][0-9]*(s|m|h|d)$ ]] || die 'Read-scan timeout must be a positive duration such as 24h.'
report="$PAW_REPORT_DIR/badblocks-$(basename "$dev").txt"
log INFO "Read-only surface scan on $dev; destructive write modes are not used; timeout=$duration."
set +e
timeout --foreground --signal=TERM --kill-after=30s "$duration" badblocks -sv "$dev" >"$report" 2>&1
rc=$?
set -e
cat "$report"
case "$rc" in
  0) log INFO 'Read-only surface scan completed.' ;;
  124|137) log WARN 'Read-only surface scan exceeded the timeout; incomplete result, not PASS.'; exit 2 ;;
  *) log ERROR "Read-only surface scan failed with exit=$rc."; exit 1 ;;
esac
