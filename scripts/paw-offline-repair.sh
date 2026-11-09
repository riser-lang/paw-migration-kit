#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/paw-lib.sh"
dev="${1:-}"; [[ -n "$dev" && -b "$dev" ]] || die 'Usage: paw-offline-repair.sh ROOT_PARTITION'
require_sim_or_enrollment; assert_unmounted "$dev"; need e2fsck
if [[ ${PAW_SIMULATION:-0} == 1 ]]; then assert_sim_loop_device "$dev"; else assert_registered_target_device "$dev"; fi
[[ ${PAW_REPAIR_ARM:-} == 'I_HAVE_VERIFIED_OFFLINE_FILESYSTEM' ]] || die 'Repair requires explicit arm.'
if [[ ${PAW_SIMULATION:-0} == 1 ]]; then
  # The simulation guard above restricts this repair mode to disposable loop files.
  e2fsck -fy "$dev"
else
  e2fsck -f "$dev"
fi
