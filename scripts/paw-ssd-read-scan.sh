#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/paw-lib.sh"
dev="${1:-}"; [[ -n "$dev" ]] || die 'Usage: paw-ssd-read-scan.sh /dev/disk'
[[ -b "$dev" ]] || die 'Device must be a block device.'; need badblocks; assert_unmounted "$dev"
[[ ${PAW_SIMULATION:-0} != 1 ]] || assert_sim_loop_device "$dev"
log INFO "Read-only badblocks scan on $dev."
badblocks -sv "$dev" 2>&1 | tee "$PAW_REPORT_DIR/badblocks-$(basename "$dev").txt"
