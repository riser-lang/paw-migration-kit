#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/paw-lib.sh"
# Legacy BIOS offers no portable API to rewrite a one-time boot device.  The
# only acceptable automatic-reboot proof is observing that the live PAW medium
# has actually disappeared.  An operator-supplied flag alone is never accepted:
# it could be set while the USB/TF card is still attached.
report="$PAW_REPORT_DIR/reboot-media-order.json"
wait_seconds="${PAW_MEDIA_REMOVAL_WAIT_SECONDS:-300}"
[[ "$wait_seconds" =~ ^[0-9]{1,4}$ ]] || die 'PAW_MEDIA_REMOVAL_WAIT_SECONDS must be an integer number of seconds.'
console=/dev/console
announce(){
  printf '%s\n' "$*" >&2 || true
  [[ -w "$console" ]] && printf '%s\n' "$*" >"$console" || true
}
live_source="$(findmnt -n -o SOURCE --target /run/live/medium 2>/dev/null || true)"
live_parent=''
if [[ -n "$live_source" ]]; then
  live_parent="$(lsblk -dn -o PKNAME "$live_source" 2>/dev/null | xargs || true)"
fi
paw_live_devices=()
scan_live(){
  paw_live_devices=()
  while read -r name label; do
    [[ "$label" == PAW-LIVE ]] || continue
    [[ "$name" == /dev/* ]] || name="/dev/$name"
    paw_live_devices+=("$name")
  done < <(lsblk -nrpo NAME,LABEL 2>/dev/null || true)
}
scan_live
armed=0
[[ ${PAW_LIVE_MEDIA_REMOVED:-} == 'I_HAVE_REMOVED_THE_LIVE_USB_AND_TF_MEDIA' ]] && armed=1
observed=0
reason=''
if (( ${#paw_live_devices[@]} == 0 )); then
  observed=1
  reason='no PAW-LIVE medium is attached; firmware will boot the target disk'
else
  announce 'PAW_MEDIA_REMOVAL_REQUIRED 请立即拔出 PAW 启动 U 盘/TF 卡;检测到介质真正消失后才会自动重启.'
  deadline=$((SECONDS + wait_seconds))
  while (( SECONDS < deadline )); do
    sleep 1
    scan_live
    if (( ${#paw_live_devices[@]} == 0 )); then
      observed=1
      break
    fi
  done
  if (( observed == 1 )); then
    udevadm settle 2>/dev/null || true
    reason='live PAW medium disappearance was observed on the block layer; BIOS boot order remains operator-controlled'
    announce 'PAW_MEDIA_REMOVAL_OBSERVED 启动介质已移除;继续重启进入目标盘.'
  else
    reason="PAW-LIVE medium still attached after ${wait_seconds}s; automatic reboot refused. Remove USB/TF; the removal must be observable, an environment flag alone is not accepted."
  fi
fi
status=PASS
(( observed == 1 )) || status=BLOCKED
python3 - "$report" "$status" "$reason" "$live_source" "$live_parent" "${paw_live_devices[*]:-}" "$armed" "$observed" <<'PY'
import datetime,json,os,sys
path,status,reason,live,parent,devices,armed,observed=sys.argv[1:]
doc={"schema":"paw.reboot-media-order.v2","status":status,"reason":reason,
 "firmware":"legacy BIOS/CSM",
 "boot_order_control":"operator/BIOS BBS; no OS API used",
 "live_medium_mount_source":live or None,
 "live_medium_parent":parent or None,
 "paw_live_devices":devices.split() if devices else [],
 "removal_observed_on_block_layer":observed=="1",
 "operator_flag_present":armed=="1",
 "operator_flag_alone_accepted":False,
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
