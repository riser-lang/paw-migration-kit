#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/paw-lib.sh"
# Legacy BIOS exposes no portable API for changing the one-time boot device.
# The only safe automatic path is to prove the live USB/TF medium is no longer
# the intended boot source.  This check records that limitation instead of
# pretending a systemd reboot can change the firmware order.
report="$PAW_REPORT_DIR/reboot-media-order.json"
live_source="$(findmnt -n -o SOURCE --target /run/live/medium 2>/dev/null || true)"
live_parent=''
if [[ -n "$live_source" ]]; then
  live_parent="$(lsblk -dn -o PKNAME "$live_source" 2>/dev/null | xargs || true)"
fi
paw_live_devices=()
while read -r name label; do
  [[ "$label" == PAW-LIVE ]] || continue
  [[ "$name" == /dev/* ]] || name="/dev/$name"
  paw_live_devices+=("$name")
done < <(lsblk -nrpo NAME,LABEL 2>/dev/null || true)
armed=0
[[ ${PAW_LIVE_MEDIA_REMOVED:-} == 'I_HAVE_REMOVED_THE_LIVE_USB_AND_TF_MEDIA' ]] && armed=1
status='PASS'; reason='no live PAW medium is attached; firmware will boot the target disk'
if (( ${#paw_live_devices[@]} > 0 )); then
  if (( armed == 1 )); then
    status='PASS'; reason='operator confirmed live USB/TF removal; BIOS boot order remains operator-controlled'
  else
    status='BLOCKED'; reason='PAW-LIVE medium still attached; automatic reboot would likely re-enter the live system. Remove USB/TF and arm PAW_LIVE_MEDIA_REMOVED.'
  fi
fi
python3 - "$report" "$status" "$reason" "$live_source" "$live_parent" "${paw_live_devices[*]:-}" "$armed" <<'PY'
import datetime,json,os,sys
path,status,reason,live,parent,devices,armed=sys.argv[1:]
doc={"schema":"paw.reboot-media-order.v1","status":status,"reason":reason,
 "firmware":"legacy BIOS/CSM","boot_order_control":"operator/BIOS BBS; no OS API used",
 "live_medium_mount_source":live or None,"live_medium_parent":parent or None,
 "paw_live_devices":devices.split() if devices else [],
 "live_media_removal_armed":armed=="1",
 "auto_reboot_allowed":status=="PASS",
 "updated_at":datetime.datetime.now(datetime.timezone.utc).isoformat()}
tmp=path+".tmp"
with open(tmp,"w",encoding="utf-8") as h: json.dump(doc,h,indent=2,ensure_ascii=False)
os.chmod(tmp,0o600); os.replace(tmp,path)
PY
if [[ "$status" != PASS ]]; then
  log ERROR "$reason"
  exit 2
fi
log INFO "$reason"
