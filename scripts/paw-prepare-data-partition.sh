#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/paw-lib.sh"
disk="${1:-}"
[[ -n "$disk" && -b "$disk" ]] || die 'Usage: paw-prepare-data-partition.sh /dev/verified-live-media-disk'
for c in lsblk sfdisk blockdev partprobe partx udevadm blkid mkfs.ext4 mountpoint mount rsync python3; do need "$c"; done

if [[ ${PAW_SIMULATION:-0} == 1 ]]; then
  assert_sim_loop_device "$disk"
else
  [[ ${PAW_MEDIA_ARM:-} == I_HAVE_VERIFIED_LIVE_MEDIA ]] || die 'Media partition changes are not armed.'
  live_source="$(findmnt -n -o SOURCE --target /run/live/medium 2>/dev/null || true)"
  [[ -n "$live_source" ]] || die 'The running live system media could not be identified.'
  live_part="${live_source%%\[*}"
  live_type="$(lsblk -dn -o TYPE "$live_part" | xargs)"
  if [[ "$live_type" == disk ]]; then
    live_disk="$live_part"
  else
    live_parent="$(lsblk -dn -o PKNAME "$live_part" | xargs)"
    [[ -n "$live_parent" ]] || die 'The live-media partition has no identifiable parent disk.'
    live_disk="/dev/$live_parent"
  fi
  [[ "$live_disk" == "$disk" ]] || die 'Target is not the physical disk that booted this live system.'
  [[ "$(lsblk -dn -o RM "$disk" | xargs)" == 1 ]] || die 'Live medium is not reported as removable.'
  serial="$(lsblk -dn -o SERIAL "$disk" | xargs)"
  size="$(blockdev --getsize64 "$disk")"
  [[ -n "$serial" && "$size" =~ ^[0-9]+$ ]] || die 'Removable media serial or size is unavailable.'
  printf 'Boot media: removable device; capacity=%s bytes; model and serial are shown only here.\n' "$size"
  lsblk -dn -o MODEL,SERIAL "$disk"
  if [[ ${#PAW_DATA_CONFIRM_SUFFIX} -eq 6 ]]; then
    confirm="$PAW_DATA_CONFIRM_SUFFIX"
  else
    read -r -p '为保护其他磁盘，请输入该设备序列号最后 6 位：' confirm
  fi
  [[ ${#serial} -ge 6 && "$confirm" == "${serial: -6}" ]] || die 'Removable media confirmation did not match.'
  unset confirm serial PAW_DATA_CONFIRM_SUFFIX
fi

for child in $(lsblk -nrpo NAME "$disk"); do
  options="$(findmnt --noheadings --raw --source "$child" --output OPTIONS 2>/dev/null || true)"
  while IFS= read -r opts; do case ",$opts," in *,rw,*) die 'A media partition is mounted read-write; refusing layout change.' ;; esac; done <<<"$options"
done

existing=''
formatted_new=0
while IFS= read -r child; do
  [[ "$child" == "$disk" ]] && continue
  if [[ "$(blkid -s LABEL -o value "$child" 2>/dev/null || true)" == PAWDATA ]]; then existing="$child"; break; fi
done < <(lsblk -nrpo NAME "$disk")

table="$PAW_LOG_DIR/media-partition-table.before.txt"
layout="$PAW_LOG_DIR/media-partition-table.before.json"
sfdisk --dump "$disk" >"$table"
sfdisk --json "$disk" >"$layout"
table_label="$(python3 - "$layout" <<'PY'
import json,sys
print(json.load(open(sys.argv[1],encoding="utf-8"))["partitiontable"].get("label",""))
PY
)"
before_count="$(python3 - "$layout" <<'PY'
import json,sys
print(len(json.load(open(sys.argv[1],encoding="utf-8"))["partitiontable"].get("partitions") or []))
PY
)"

if [[ -n "$existing" ]]; then
  [[ "$(blkid -s TYPE -o value "$existing")" == ext4 ]] || die 'Existing PAWDATA label is not ext4; no reformat was attempted.'
  part_number="$(lsblk -dn -o PARTN "$existing" | xargs)"
else
  case "$table_label" in
    dos)
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
      read -r existing part_number < <(python3 - "$disk" "$start" "$size" <<'PY'
import json,re,subprocess,sys
disk,start,size=sys.argv[1],int(sys.argv[2]),int(sys.argv[3])
layout=json.loads(subprocess.check_output(["sfdisk","--json",disk],text=True))["partitiontable"]
found=[p for p in layout.get("partitions",[]) if int(p.get("start",-1))==start and int(p.get("size",-1))==size]
if len(found)!=1: raise SystemExit("appended MBR partition extent not found exactly once")
node=found[0].get("node","")
match=re.search(r"(\d+)$",node)
if not node.startswith("/dev/") or not match: raise SystemExit("appended MBR partition device path is invalid")
print(node,match.group(1))
PY
      ) || die 'Could not identify the appended MBR partition node.'
      ;;
    gpt)
      need sgdisk
      # Preserve the hybrid MBR boot entries while editing only the GPT side.
      mbr_backup="$PAW_LOG_DIR/media-mbr.before.bin"
      dd if="$disk" of="$mbr_backup" bs=512 count=1 status=none
      sgdisk --backup="$PAW_LOG_DIR/media-gpt.before.bin" "$disk" >/dev/null
      sgdisk --move-second-header "$disk" >/dev/null
      free_mib="$(python3 - "$layout" "$(blockdev --getsz "$disk")" <<'PY'
import json,sys
layout=json.load(open(sys.argv[1],encoding="utf-8"))["partitiontable"]
total=int(sys.argv[2]); parts=layout.get("partitions") or []
if not parts: raise SystemExit("GPT has no partitions")
last_end=max(int(p["start"])+int(p["size"]) for p in parts)
# Leave the backup GPT header and alignment gap.
free=(total-34-last_end)//2048
print(max(0,free))
PY
)"
      [[ "$free_mib" =~ ^[0-9]+$ ]] && ((free_mib >= 128)) || die 'Less than 128 MiB remains after the ISO GPT partitions.'
      sgdisk --largest-new=0 --typecode=0:8300 --change-name=0:PAWDATA "$disk" >"$PAW_LOG_DIR/media-partition-append.txt"
      dd if="$mbr_backup" of="$disk" bs=512 count=1 conv=notrunc status=none
      ;;
    *)
      die 'Live media partition table is neither DOS/MBR nor GPT; refusing to append.'
      ;;
  esac

  sfdisk --dump "$disk" >"$PAW_LOG_DIR/media-partition-table.after.txt"
  sfdisk --json "$disk" >"$PAW_LOG_DIR/media-partition-table.after.json"
  if [[ "$table_label" == dos ]]; then
    read -r existing part_number after_count < <(python3 - "$PAW_LOG_DIR/media-partition-table.after.json" "$before_count" "$existing" <<'PY'
import json,re,sys
path,before,node=sys.argv[1],int(sys.argv[2]),sys.argv[3]
parts=json.load(open(path,encoding="utf-8"))["partitiontable"].get("partitions") or []
if len(parts)!=before+1: raise SystemExit("expected exactly one new partition")
found=[p for p in parts if p.get("node","")==node]
if len(found)!=1: raise SystemExit("new MBR PAWDATA partition not found exactly once")
p=found[0]; match=re.search(r"(\d+)$",node)
if not match: raise SystemExit("new MBR partition device path is invalid")
if int(p.get("size",0)) < 128*1024*1024//512: raise SystemExit("new PAWDATA partition is smaller than 128 MiB")
print(node,match.group(1),len(parts))
PY
    ) || die 'Could not identify the newly appended MBR PAWDATA partition.'
  else
    read -r existing part_number after_count < <(python3 - "$PAW_LOG_DIR/media-partition-table.after.json" "$before_count" <<'PY'
import json,re,sys
path,before=sys.argv[1],int(sys.argv[2])
parts=json.load(open(path,encoding="utf-8"))["partitiontable"].get("partitions") or []
if len(parts)!=before+1: raise SystemExit("expected exactly one new partition")
new=[p for p in parts if str(p.get("name",""))=="PAWDATA"]
if len(new)!=1: raise SystemExit("new PAWDATA partition name not found exactly once")
p=new[0]; node=p.get("node","")
match=re.search(r"(\d+)$",node)
if not node.startswith("/dev/") or not match: raise SystemExit("new partition device path is invalid")
if int(p.get("size",0)) < 128*1024*1024//512: raise SystemExit("new PAWDATA partition is smaller than 128 MiB")
print(node,match.group(1),len(parts))
PY
    ) || die 'Could not identify the newly appended GPT PAWDATA partition.'
  fi
  [[ "$after_count" == "$((before_count + 1))" ]] || die 'Partition count changed unexpectedly; refusing to format.'
  [[ -n "$part_number" ]] || die 'New PAWDATA partition number is missing.'
  partprobe "$disk" || log WARN 'partprobe could not refresh the hybrid ISO partition table; trying partx.'
  partx --add --nr "$part_number" "$disk" || true
  udevadm settle
  for _ in $(seq 1 20); do
    [[ -b "$existing" ]] && break
    sleep 1
  done
  [[ -b "$existing" ]] || die 'PAWDATA partition node did not appear after partition table update.'
  [[ -z "$(blkid -s LABEL -o value "$existing" 2>/dev/null || true)" ]] || die 'New partition already has a filesystem label; refusing to format.'
  mkfs.ext4 -F -L PAWDATA "$existing" >/dev/null
  formatted_new=1
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

if [[ ${PAW_VERIFY_REMOUNT:-0} == 1 ]]; then
  marker="$mount_dir/.paw-remount-marker"
  printf '%s\n' "$(date -u +%FT%TZ)" >"$marker"
  sync
  umount "$mount_dir"
  mount -t ext4 -o rw,noatime,errors=remount-ro,noexec,nosuid,nodev "$existing" "$mount_dir"
  [[ -s "$marker" ]] || die 'PAWDATA remount persistence check failed.'
  rm -f "$marker"; sync
fi

python3 - "$PAW_REPORT_DIR/media-partition.json" "$disk" "$existing" "$part_number" "$table_label" "$before_count" "${after_count:-$before_count}" "$formatted_new" <<'PY'
import datetime,json,os,sys
path,disk,node,part,label,before,after,formatted=sys.argv[1:]
data={"schema":"paw.media-partition.v1","status":"PASS","disk":disk,"data_partition":node,
 "partition_number":int(part) if str(part).isdigit() else None,"table":label,
 "partitions_before":int(before),"partitions_after":int(after),
 "formatted_only_new_partition":formatted=="1","remount_verified":os.environ.get("PAW_VERIFY_REMOUNT","0")=="1",
 "completed_at":datetime.datetime.now(datetime.timezone.utc).isoformat()}
os.makedirs(os.path.dirname(path),exist_ok=True)
tmp=path+".tmp"
with open(tmp,"w",encoding="utf-8") as handle: json.dump(data,handle,indent=2)
os.chmod(tmp,0o600); os.replace(tmp,path)
PY
log INFO "PAWDATA ext4 partition is mounted root-only; table=$table_label; new_partition=$existing; only the new partition was formatted."
