#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/paw-lib.sh"
disk="${1:-}"; part="${2:-}"; [[ -n "$disk" && -n "$part" ]] || die 'Usage: paw-gpt-expand.sh DISK PARTITION'
require_sim_or_enrollment; [[ ${PAW_EXPAND_ARM:-} == 'I_HAVE_VERIFIED_CLONE' ]] || die 'Expansion requires explicit arm.'
if [[ ${PAW_SIMULATION:-0} == 1 ]]; then assert_sim_loop_device "$disk"; else assert_registered_target_device "$disk"; fi
need growpart; need resize2fs; need lsblk; [[ "$(lsblk -dn -o PTTYPE "$disk")" == gpt ]] || die 'Target is not GPT.'
n="$(lsblk -dn -o PARTN "$part" | xargs)"; [[ "$n" =~ ^[0-9]+$ ]] || die 'Cannot determine partition number.'; assert_unmounted "$part"
growpart "$disk" "$n"; resize2fs "$part"
