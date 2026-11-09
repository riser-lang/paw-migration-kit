#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/paw-lib.sh"
for c in findmnt lsblk blockdev; do need "$c"; done
mode="${1:-manual}"
[[ "$mode" == auto || "$mode" == manual ]] || die 'Usage: paw-data-prepare.sh [auto|manual]'

if "$PAW_ROOT/scripts/paw-data-check.sh" >/dev/null 2>&1; then
  log INFO 'PAWDATA is already mounted and healthy; no partition change was made.'
  exit 0
fi
if [[ ${PAW_SKIP_DATA_AUTO:-0} == 1 ]]; then
  log WARN 'PAWDATA automatic initialization was explicitly skipped; clone remains blocked.'
  exit 2
fi

if [[ ${PAW_SIMULATION:-0} == 1 && -n ${PAW_LIVE_DISK_OVERRIDE:-} ]]; then
  disk="$PAW_LIVE_DISK_OVERRIDE"
  assert_sim_loop_device "$disk"
else
  live_source="$(findmnt -n -o SOURCE --target /run/live/medium 2>/dev/null || true)"
  [[ -n "$live_source" ]] || die 'Could not identify the physical device that booted this live system.'
  live_part="${live_source%%\[*}"
  live_type="$(lsblk -dn -o TYPE "$live_part" 2>/dev/null | xargs || true)"
  if [[ "$live_type" == disk ]]; then
    parent="${live_part##*/}"
  else
    parent="$(lsblk -dn -o PKNAME "$live_part" 2>/dev/null | xargs || true)"
  fi
  [[ -n "$parent" && "$parent" =~ ^[A-Za-z0-9/]+$ ]] || die 'The live-media source has no identifiable physical parent disk.'
  disk="/dev/$parent"
  [[ -b "$disk" ]] || die 'The live-media parent is not a block device.'
  [[ "$(lsblk -dn -o RM "$disk" | xargs)" == 1 ]] || { log WARN 'Live media is not identified as removable; automatic PAWDATA initialization is blocked.'; exit 2; }
fi

printf '\nPAWDATA 首次自动准备\n'
printf '%s\n' '只针对当前启动本系统的可移动设备；不会碰其他磁盘。'
printf '物理设备：%s\n' "$disk"
model="$(lsblk -dn -o MODEL "$disk" | xargs)"
serial="$(lsblk -dn -o SERIAL "$disk" | xargs)"
capacity="$(blockdev --getsize64 "$disk")"
[[ -n "$serial" ]] || die '该启动介质没有可读序列号，无法安全确认；拒绝自动分区。'
[[ "$capacity" =~ ^[0-9]+$ ]] || die '无法读取启动介质容量。'
printf '型号：%s\n容量：%s bytes（约 %s GiB）\n序列号：%s\n' "${model:-未知}" "$capacity" "$((capacity / 1073741824))" "$serial"
printf '%s\n' '将只追加一个新的 PAWDATA 分区并格式化该新分区；ISO 启动分区不会被格式化。'
if [[ ${PAW_SIMULATION:-0} == 1 && -n ${PAW_DATA_CONFIRM_SUFFIX:-} ]]; then
  confirm="$PAW_DATA_CONFIRM_SUFFIX"
else
  read -r -p '请输入该设备序列号最后 6 位以继续：' confirm || die '未收到确认；PAWDATA 未创建。'
fi
[[ ${#serial} -ge 6 && "$confirm" == "${serial: -6}" ]] || die '序列号末六位不匹配；没有写入任何分区。'
unset confirm

PAW_MEDIA_ARM=I_HAVE_VERIFIED_LIVE_MEDIA \
PAW_VERIFY_REMOUNT=1 \
  "$PAW_ROOT/scripts/paw-prepare-data-partition.sh" "$disk"
"$PAW_ROOT/scripts/paw-data-check.sh"
log INFO 'PAWDATA automatic guided initialization completed; only the newly appended partition was formatted.'
