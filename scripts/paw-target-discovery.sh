#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/paw-lib.sh"
need lsblk; need python3; need findmnt
out="$PAW_LOG_DIR/target-inventory.json"
lsblk --json --bytes --output NAME,PATH,TYPE,SIZE,MODEL,SERIAL,RM,MOUNTPOINTS >"$out"
boot_source="$(findmnt -n -o SOURCE --target /run/live/medium 2>/dev/null || true)"
boot_part="${boot_source%%\[*}"
boot_parent=''
[[ -n "$boot_part" ]] && boot_parent="$(lsblk -dn -o PKNAME "$boot_part" 2>/dev/null | xargs || true)"
boot_device="${boot_parent:+/dev/$boot_parent}"

# The candidate list and the serial numbers must be visible on the physical
# console; paw-console.service sends stdout to the journal only, so the panel
# goes through the tty1 fd (or inherited stdio when piped).
# shellcheck source=scripts/paw-tty-lib.sh
source "$PAW_ROOT/scripts/paw-tty-lib.sh"
export PAW_TTY_SESSION_NAME=target-discovery
paw_tty_open_optional || die '无法打开交互终端；未登记任何目标盘。'
paw_tty_clear
paw_tty_marker PAW-TTY1-TARGET-PANEL
paw_tty_say 'PAW 目标 SSD 只读盘点（只登记，不写磁盘）'
paw_tty_say '以下为本机可用的非移动、未挂载本地磁盘（NTFS/Windows 磁盘已排除）：'
if ! candidate_text="$(python3 - "$out" "$boot_device" <<'PY'
import json,re,sys
d=json.load(open(sys.argv[1],encoding="utf-8")); boot=sys.argv[2]
devices=[]
for item in d.get("blockdevices",[]):
    if item.get("type")!="disk": continue
    path=item.get("path") or "/dev/"+str(item.get("name",""))
    if not re.fullmatch(r"/dev/[A-Za-z0-9/]+",path) or path==boot: continue
    if str(item.get("rm","0"))=="1" or not item.get("serial") or int(item.get("size") or 0)<=0: continue
    if any(m for child in item.get("children") or [] for m in child.get("mountpoints") or [] if m): continue
    # A Windows installation disk must never be offered as the PAW target.
    # Detect it from both filesystem type and the Microsoft basic-data GPT
    # type, so an unmounted NTFS volume cannot slip through.
    kids=item.get("children") or []
    if any(str(c.get("fstype") or "").lower() in ("ntfs","ntfs3","exfat") or
           str(c.get("parttype") or "").lower().startswith("ebd0a0a2-") for c in kids):
        continue
    devices.append(item)
if not devices: raise SystemExit("No eligible non-removable, unmounted local disk was found.")
for n,item in enumerate(devices,1):
    print(f"{n}. device={item.get('path') or '/dev/'+item.get('name','')} model={str(item.get('model') or '').strip()} capacity_bytes={item.get('size')} serial={str(item.get('serial')).strip()}")
PY
)"; then
  paw_tty_say '没有找到可用的非移动、未挂载本地磁盘；未登记任何目标盘。'
  paw_tty_close
  die '没有找到可用的非移动、未挂载本地磁盘；未登记目标盘。'
fi
while IFS= read -r line; do [[ -n "$line" ]] && paw_tty_say "$line"; done <<<"$candidate_text"
unset candidate_text
mapfile -t candidates < <(python3 - "$out" "$boot_device" <<'PY'
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8")); boot=sys.argv[2]
for x in d.get("blockdevices",[]):
 p=x.get("path") or "/dev/"+str(x.get("name",""))
 kids=x.get("children") or []
 is_windows=any(str(c.get("fstype") or "").lower() in ("ntfs","ntfs3","exfat") or str(c.get("parttype") or "").lower().startswith("ebd0a0a2-") for c in kids)
 if x.get("type")=="disk" and p!=boot and str(x.get("rm","0"))!="1" and x.get("serial") and int(x.get("size") or 0)>0 and not is_windows and not any(m for c in kids for m in c.get("mountpoints") or [] if m): print(p)
PY
)
paw_tty_marker PAW-TTY1-TARGET-PROMPT
paw_tty_prompt '输入目标 SSD 对应的编号（只登记，不写磁盘）：'
choice=''
if ! paw_tty_read choice; then
  paw_tty_marker PAW-TTY1-TARGET-TIMEOUT
  paw_tty_close
  die '编号输入超时或中断；未登记任何目标盘。'
fi
[[ "$choice" =~ ^[1-9][0-9]*$ ]] && ((choice <= ${#candidates[@]})) || { paw_tty_say '错误：目标编号无效。'; paw_tty_close; die '目标编号无效。'; }
dev="${candidates[$((choice-1))]}"
# Re-check immediately before enrollment.  The inventory and the operator's
# typed choice are separate steps; a hot-plugged Windows disk must not become
# eligible between them.
python3 - "$out" "$dev" <<'PY' || { paw_tty_say '错误：所选磁盘包含 NTFS/Windows 分区，已拒绝登记。'; paw_tty_close; die 'Windows/NTFS target disk refused.'; }
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8")); wanted=sys.argv[2]
for item in d.get("blockdevices",[]):
    path=item.get("path") or "/dev/"+str(item.get("name",""))
    if path!=wanted or item.get("type")!="disk": continue
    kids=item.get("children") or []
    if any(str(c.get("fstype") or "").lower() in ("ntfs","ntfs3","exfat") or str(c.get("parttype") or "").lower().startswith("ebd0a0a2-") for c in kids):
        raise SystemExit(1)
    break
else:
    raise SystemExit(1)
PY
serial="$(lsblk -dn -o SERIAL "$dev" | xargs)"; capacity="$(blockdev --getsize64 "$dev")"; model="$(lsblk -dn -o MODEL "$dev" | xargs)"
[[ -n "$serial" && "$capacity" =~ ^[0-9]+$ ]] || { paw_tty_close; die '目标盘序列号或容量不可读。'; }
paw_tty_say ''
paw_tty_say "已选择：设备=$dev 型号=${model:-未知} 容量=$capacity bytes"
paw_tty_say "该目标序列号：$serial"
paw_tty_prompt '请按上方显示的序列号输入最后 6 位以登记：'
suffix=''
if ! paw_tty_read suffix; then
  paw_tty_marker PAW-TTY1-TARGET-TIMEOUT
  paw_tty_close
  die '序列号输入超时或中断；未登记任何目标盘。'
fi
if [[ ${#serial} -lt 6 || "$suffix" != "${serial: -6}" ]]; then
  paw_tty_marker PAW-TTY1-TARGET-BAD
  paw_tty_say '错误：目标序列号后缀不匹配；未登记任何目标盘。'
  paw_tty_close
  die '目标序列号后缀不匹配。'
fi
paw_tty_marker PAW-TTY1-TARGET-OK
paw_tty_say '目标 SSD 已按只读盘点登记；未写入任何扇区。'
paw_tty_close
if [[ -n "$(lsblk -nrpo MOUNTPOINTS "$dev" | sed '/^$/d')" ]]; then die '目标 SSD 存在已挂载分区；拒绝登记。'; fi
python3 - "$PAW_CONFIG_DIR/target-ssd.json" "$dev" "$model" "$capacity" "$serial" <<'PY'
import json,os,sys,datetime
path,dev,model,capacity,serial=sys.argv[1:]
data={"approved":True,"device_path":dev,"model":model,"capacity_bytes":int(capacity),"serial":serial,"registered_at":datetime.datetime.now(datetime.timezone.utc).isoformat(),"registered_by":"interactive read-only inventory"}
tmp=path+".tmp"
with open(tmp,"w",encoding="utf-8") as handle: json.dump(data,handle,indent=2)
os.chmod(tmp,0o600); os.replace(tmp,path)
PY
unset serial suffix
log INFO 'Target SSD enrolled from a read-only inventory; no target sectors were written.'
