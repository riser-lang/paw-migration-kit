#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/paw-lib.sh"
dev="${1:-}"; [[ -n "$dev" ]] || die 'Usage: paw-ssd-smart-check.sh /dev/disk'
[[ -b "$dev" ]] || die 'Device must be a block device.'; need smartctl; assert_unmounted "$dev"
[[ ${PAW_SIMULATION:-0} != 1 ]] || assert_sim_loop_device "$dev"
report="$PAW_REPORT_DIR/smart-$(basename "$dev").txt"; mkdir -p "$(dirname "$report")"
smartctl -x "$dev" >"$report" 2>&1 || { log WARN 'SMART query failed/unsupported; inspect report; not PASS.'; exit 2; }
smartctl -H "$dev" | tee -a "$report" || die 'SMART health check failed or unsupported.'
if smartctl -c "$dev" | grep -qi 'short.*self-test.*available'; then smartctl -t short "$dev" | tee -a "$report"; else log WARN 'Short self-test unsupported.'; fi
[[ ${PAW_RUN_LONG_SMART:-0} == 1 ]] && smartctl -t long "$dev" | tee -a "$report"
log INFO "SMART report=$report; extended test completion requires later polling."
