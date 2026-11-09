#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/paw-lib.sh"
for c in findmnt lsblk; do need "$c"; done

live_source="$(findmnt -n -o SOURCE --target /run/live/medium 2>/dev/null || true)"
[[ -n "$live_source" ]] || die 'Could not identify the physical device that booted this live system.'
live_part="${live_source%%\[*}"
parent="$(lsblk -dn -o PKNAME "$live_part" 2>/dev/null | xargs || true)"
[[ -n "$parent" && "$parent" =~ ^[A-Za-z0-9/]+$ ]] || die 'The live-media source has no identifiable physical parent disk.'
disk="/dev/$parent"
[[ -b "$disk" ]] || die 'The live-media parent is not a block device.'
[[ "$(lsblk -dn -o RM "$disk" | xargs)" == 1 ]] || die 'Live media is not identified as removable; no layout changes were made.'

printf '\nPAWDATA 首次准备只针对当前启动本系统的可移动设备。\n'
printf '物理设备：%s\n' "$disk"
lsblk -dn -o MODEL,SERIAL,SIZE "$disk"
printf '请确认它是本次启动所用 TF 卡。后续输入序列号末六位才会在该卡追加 PAWDATA 分区。\n'
PAW_MEDIA_ARM=I_HAVE_VERIFIED_LIVE_MEDIA "$PAW_ROOT/scripts/paw-prepare-data-partition.sh" "$disk"
