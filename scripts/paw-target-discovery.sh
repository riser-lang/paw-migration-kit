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

python3 - "$out" "$boot_device" <<'PY'
import json,re,sys
d=json.load(open(sys.argv[1],encoding="utf-8")); boot=sys.argv[2]
devices=[]
for item in d.get("blockdevices",[]):
    if item.get("type")!="disk": continue
    path=item.get("path") or "/dev/"+str(item.get("name",""))
    if not re.fullmatch(r"/dev/[A-Za-z0-9/]+",path) or path==boot: continue
    if str(item.get("rm","0"))=="1" or not item.get("serial") or int(item.get("size") or 0)<=0: continue
    if any(m for child in item.get("children") or [] for m in child.get("mountpoints") or [] if m): continue
    devices.append(item)
if not devices: raise SystemExit("No eligible non-removable, unmounted local disk was found.")
for n,item in enumerate(devices,1):
    print(f"{n}. device={item.get('path') or '/dev/'+item.get('name','')} model={str(item.get('model') or '').strip()} capacity_bytes={item.get('size')} serial={str(item.get('serial')).strip()}")
PY
mapfile -t candidates < <(python3 - "$out" "$boot_device" <<'PY'
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8")); boot=sys.argv[2]
for x in d.get("blockdevices",[]):
 p=x.get("path") or "/dev/"+str(x.get("name",""))
 if x.get("type")=="disk" and p!=boot and str(x.get("rm","0"))!="1" and x.get("serial") and int(x.get("size") or 0)>0 and not any(m for c in x.get("children") or [] for m in c.get("mountpoints") or [] if m): print(p)
PY
)
read -r -p '输入目标 SSD 对应的编号（只登记，不写磁盘）：' choice
[[ "$choice" =~ ^[1-9][0-9]*$ ]] && ((choice <= ${#candidates[@]})) || die '目标编号无效。'
dev="${candidates[$((choice-1))]}"
serial="$(lsblk -dn -o SERIAL "$dev" | xargs)"; capacity="$(blockdev --getsize64 "$dev")"; model="$(lsblk -dn -o MODEL "$dev" | xargs)"
[[ -n "$serial" && "$capacity" =~ ^[0-9]+$ ]] || die '目标盘序列号或容量不可读。'
read -r -p '请按屏幕显示的目标序列号输入最后 6 位以登记：' suffix
[[ ${#serial} -ge 6 && "$suffix" == "${serial: -6}" ]] || die '目标序列号后缀不匹配。'
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
