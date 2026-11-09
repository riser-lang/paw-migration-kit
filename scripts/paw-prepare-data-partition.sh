#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/paw-lib.sh"
disk="${1:-}"
[[ -n "$disk" && -b "$disk" ]] || die 'Usage: paw-prepare-data-partition.sh /dev/verified-live-media-disk'
for c in lsblk sfdisk blockdev partprobe udevadm blkid mkfs.ext4 mountpoint mount rsync; do need "$c"; done

if [[ ${PAW_SIMULATION:-0} == 1 ]]; then
  assert_sim_loop_device "$disk"
else
  [[ ${PAW_MEDIA_ARM:-} == I_HAVE_VERIFIED_LIVE_MEDIA ]] || die 'Media partition changes are not armed.'
  live_source="$(findmnt -n -o SOURCE --target /run/live/medium 2>/dev/null || true)"
  [[ -n "$live_source" ]] || die 'The running live system media could not be identified.'
  live_part="${live_source%%\[*}"
  live_parent="$(lsblk -dn -o PKNAME "$live_part" | xargs)"
  [[ -n "$live_parent" && "/dev/$live_parent" == "$disk" ]] || die 'Target is not the physical disk that booted this live system.'
  [[ "$(lsblk -dn -o RM "$disk" | xargs)" == 1 ]] || die 'Live medium is not reported as removable.'
  serial="$(lsblk -dn -o SERIAL "$disk" | xargs)"
  size="$(blockdev --getsize64 "$disk")"
  [[ -n "$serial" && "$size" =~ ^[0-9]+$ ]] || die 'Removable media serial or size is unavailable.'
  printf 'Boot media: removable device; capacity=%s bytes; model and serial are shown only here.\n' "$size"
  lsblk -dn -o MODEL,SERIAL "$disk"
  read -r -p '为保护其他磁盘，请输入该设备序列号最后 6 位：' confirm
  [[ ${#serial} -ge 6 && "$confirm" == "${serial: -6}" ]] || die 'Removable media confirmation did not match.'
  unset confirm serial
fi

for child in $(lsblk -nrpo NAME "$disk"); do
  options="$(findmnt --noheadings --raw --source "$child" --output OPTIONS 2>/dev/null || true)"
  while IFS= read -r opts; do case ",$opts," in *,rw,*) die 'A media partition is mounted read-write; refusing layout change.' ;; esac; done <<<"$options"
done

existing=''
while IFS= read -r child; do
  [[ "$child" == "$disk" ]] && continue
  if [[ "$(blkid -s LABEL -o value "$child" 2>/dev/null || true)" == PAWDATA ]]; then existing="$child"; break; fi
done < <(lsblk -nrpo NAME "$disk")
if [[ -n "$existing" ]]; then
  [[ "$(blkid -s TYPE -o value "$existing")" == ext4 ]] || die 'Existing PAWDATA label is not ext4; no reformat was attempted.'
else
  table="$PAW_LOG_DIR/media-partition-table.before.txt"
  layout="$PAW_LOG_DIR/media-partition-table.before.json"
  sfdisk --dump "$disk" >"$table"
  sfdisk --json "$disk" >"$layout"
  read -r start size < <(python3 - "$layout" "$(blockdev --getsz "$disk")" <<'PY'
import json,sys
layout=json.load(open(sys.argv[1],encoding="utf-8"))["partitiontable"]
total=int(sys.argv[2])
if layout.get("label")!="dos": raise SystemExit("live media partition table is not MBR/DOS")
if int(layout.get("sectorsize",0))!=512: raise SystemExit("unsupported live media sector size")
parts=layout.get("partitions") or []
if not parts or len(parts)>=4: raise SystemExit("no free MBR primary partition slot")
last_end=max(int(p["start"])+int(p["size"]) for p in parts)
start=((last_end+2047)//2048)*2048
size=total-start
if size < 128*1024*1024//512: raise SystemExit("less than 128 MiB remains after the ISO partitions")
if size > 0xffffffff: raise SystemExit("PAWDATA exceeds the MBR partition size limit")
print(start,size)
PY
  ) || die 'Could not validate the hybrid MBR layout or append space.'
  [[ "$start" =~ ^[0-9]+$ && "$size" =~ ^[0-9]+$ ]] || die 'Calculated PAWDATA MBR extent is invalid.'
  printf '%s,%s,83\n' "$start" "$size" | sfdisk --append "$disk" >"$PAW_LOG_DIR/media-partition-append.txt"
  partprobe "$disk"
  udevadm settle
  for _ in $(seq 1 20); do
    while IFS= read -r child; do
      [[ "$child" == "$disk" ]] && continue
      if [[ "$(blkid -s LABEL -o value "$child" 2>/dev/null || true)" == PAWDATA ]]; then existing="$child"; break; fi
    done < <(lsblk -nrpo NAME "$disk")
    [[ -n "$existing" ]] && break
    sleep 1
  done
  [[ -n "$existing" ]] || die 'PAWDATA partition did not appear after MBR update.'
  mkfs.ext4 -F -L PAWDATA "$existing" >/dev/null
fi

mount_dir="${PAW_MOUNTPOINT_OVERRIDE:-/var/lib/paw-migration}"
install -d -m 0700 "$mount_dir"
if ! mountpoint -q "$mount_dir"; then
  mount -t ext4 -o rw,noatime,errors=remount-ro,noexec,nosuid,nodev "$existing" "$mount_dir"
fi
chmod 0700 "$mount_dir"
if [[ -d /run/paw-migration && ! -f "$mount_dir/.paw-state-migrated" ]]; then
  rsync -a --no-owner --no-group /run/paw-migration/ "$mount_dir/"
  install -m 0600 /dev/null "$mount_dir/.paw-state-migrated"
  sync
fi
[[ "$(findmnt -n -o FSTYPE --target "$mount_dir")" == ext4 ]] || die 'PAWDATA did not mount as ext4.'
[[ "$(findmnt -n -o SOURCE --target "$mount_dir")" == "$existing" ]] || die 'PAWDATA mount source mismatch.'
log INFO 'PAWDATA ext4 partition is mounted root-only; volatile progress, config and reports were copied if present.'
