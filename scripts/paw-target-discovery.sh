#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/paw-lib.sh"
need lsblk; need python3; need findmnt; need blockdev
inventory="$PAW_LOG_DIR/target-inventory.json"
candidate_file="$PAW_LOG_DIR/target-candidates.txt"
boot_source="$(findmnt -n -o SOURCE --target /run/live/medium 2>/dev/null || true)"
boot_part="${boot_source%%\[*}"
boot_parent=''
[[ -n "$boot_part" ]] && boot_parent="$(lsblk -dn -o PKNAME "$boot_part" 2>/dev/null | xargs || true)"
boot_device="${boot_parent:+/dev/$boot_parent}"
source_device=''
if [[ -r "$PAW_CONFIG_DIR/source.json" ]]; then
  source_device="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1],encoding="utf-8")).get("device_path") or "")' "$PAW_CONFIG_DIR/source.json")"
fi

# Read-only scan of every local disk.  The helper records model, exact bytes,
# transport, serial, WWN, by-id, sysfs path, partitions and mount state.  It
# excludes the live boot medium and the registered source instead of trusting
# the operator to avoid them.
python3 "$PAW_ROOT/scripts/paw-identity.py" inventory \
  --boot-device "$boot_device" --source-device "$source_device" >"$inventory"
: >"$PAW_LOG_DIR/target-inventory.txt"
set +e
python3 - "$inventory" "$candidate_file" <<'PY' >"$PAW_LOG_DIR/target-inventory.txt"
import json,sys
inv=json.load(open(sys.argv[1],encoding="utf-8"))
out=open(sys.argv[2],"w",encoding="utf-8")
reason_map={"zero_capacity":"容量为0","removable":"可移动介质","mounted":"存在已挂载分区",
 "windows_or_ntfs":"Windows/NTFS 磁盘","current_boot_medium":"当前启动介质",
 "registered_source":"已登记的源盘","unstable_identity":"没有稳定身份锚点",
 "ambiguous_identity":"存在无法区分的同身份磁盘"}
n=0
for d in inv["devices"]:
    if d["eligible"]:
        n+=1; out.write(d["device_path"]+"\n")
        tag=f"候选{n}"
    else:
        tag="排除"
    reasons=", ".join(reason_map.get(r,r) for r in d["exclusion_reasons"]) or "-"
    parts=";".join(f"p{p.get('partn')}:{p.get('fstype') or '?'}:{p.get('size') or '?'}" for p in d["partition_table"]) or "none"
    print(f"[{tag}] device={d['device_path']} model={d['model'] or '?'} "
          f"capacity_bytes={d['capacity_bytes']} transport={d['transport'] or '?'} "
          f"serial={d['serial'] or '(none)'} wwn={d['wwn'] or '(none)'} "
          f"by_id={','.join(d['by_id']) or '(none)'} partitions={parts} "
          f"mounted={d['mounted']} windows={d['windows']} efi={d['efi']} reason={reasons}")
out.close()
if n == 0:
    raise SystemExit("NO_ELIGIBLE_DISK")
PY
inventory_rc=$?
set -e
mapfile -t candidates <"$candidate_file"

# The panel must reach the physical console: paw-console.service sends stdout
# only to the journal, so use the verified tty1 fd (or inherited stdio in CI).
# shellcheck source=scripts/paw-tty-lib.sh
source "$PAW_ROOT/scripts/paw-tty-lib.sh"
export PAW_TTY_SESSION_NAME=target-discovery
paw_tty_open_optional || die '无法打开交互终端;未登记任何目标盘.'
paw_tty_clear
paw_tty_marker PAW-TTY1-TARGET-PANEL
paw_tty_say 'PAW 目标 SSD 只读盘点(只登记,不写磁盘)'
paw_tty_say '已扫描全部本地磁盘;不可用磁盘会显示排除原因:'
while IFS= read -r line; do [[ -n "$line" ]] && paw_tty_say "$line"; done <"$PAW_LOG_DIR/target-inventory.txt"
if ((inventory_rc != 0 || ${#candidates[@]} == 0)); then
  paw_tty_say '没有找到可用的非移动,未挂载,身份稳定的本地磁盘;未登记任何目标盘.'
  paw_tty_close
  die '没有找到可用的非移动,未挂载本地磁盘;未登记目标盘.'
fi
paw_tty_marker PAW-TTY1-TARGET-PROMPT
paw_tty_prompt '输入目标 SSD 对应的候选编号(只登记,不写磁盘):'
choice=''
if ! paw_tty_read choice; then
  paw_tty_marker PAW-TTY1-TARGET-TIMEOUT
  paw_tty_close
  die '编号输入超时或中断;未登记任何目标盘.'
fi
[[ "$choice" =~ ^[1-9][0-9]*$ ]] && ((choice <= ${#candidates[@]})) || { paw_tty_say '错误:目标编号无效.'; paw_tty_close; die '目标编号无效.'; }
dev="${candidates[$((choice-1))]}"

# Re-read the chosen device immediately before enrollment.  The operator's
# choice is an index into a previous scan, never a device name trusted alone.
identity_tmp="$PAW_REPORT_DIR/.target-enrollment-identity.json"
if ! python3 "$PAW_ROOT/scripts/paw-identity.py" identity "$dev" >"$identity_tmp" 2>/dev/null; then
  paw_tty_say '错误:所选磁盘没有可用的稳定身份;已拒绝登记.'
  paw_tty_close
  die 'Target has no stable identity; refusing enrollment.'
fi
# A Windows/NTFS disk must never be enrolled even if it appeared between the
# inventory and the choice.  Keep the explicit fstype and GPT type checks.
if ! python3 - "$inventory" "$dev" <<'PY'
import json,sys
inv=json.load(open(sys.argv[1],encoding="utf-8")); wanted=sys.argv[2]
d=next((x for x in inv["devices"] if x["device_path"]==wanted),None)
if d is None or not d["eligible"] or d["windows"]:
    raise SystemExit(1)
if any(str(p.get("fstype") or "").lower() in ("ntfs","ntfs3","exfat") or
       str(p.get("parttype") or "").lower().startswith("ebd0a0a2-") for p in d["partition_table"]):
    raise SystemExit(1)
PY
then
  paw_tty_say '错误:所选磁盘已不可用或包含 NTFS/Windows 分区,已拒绝登记.'
  paw_tty_close
  die 'Windows/NTFS or changed target disk refused.'
fi
read -r serial capacity model wwn basis hw comp < <(python3 - "$identity_tmp" <<'PY'
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
print((d.get("serial") or "-").replace(" ","_"), d.get("capacity_bytes"), (d.get("model") or "-").replace(" ","_"),
      (d.get("wwn") or "-"), (d.get("identity_basis") or "-"),
      d.get("hardware_identity_sha256") or "-", d.get("composite_identity_sha256") or "-")
PY
)
[[ "$capacity" =~ ^[0-9]+$ && "$hw" =~ ^[0-9a-f]{64}$ ]] || { paw_tty_close; die '目标盘容量或稳定身份不可读.'; }
paw_tty_say ''
paw_tty_say "已选择:设备=$dev 型号=${model/-/未知} 容量=$capacity bytes"
paw_tty_say "目标序列号:${serial/-/不可用(使用 WWN/by-id/sysfs 组合身份)}"
paw_tty_say "身份依据:$basis"
paw_tty_say "硬件指纹:$hw"
if [[ "$serial" != "-" && ${#serial} -ge 6 ]]; then
  confirm_value="${serial: -6}"; confirm_label='序列号最后 6 位'
else
  confirm_value="${hw: -8}"; confirm_label='硬件指纹最后 8 位'
fi
paw_tty_prompt "请按上方显示输入${confirm_label}以登记:"
suffix=''
if ! paw_tty_read suffix; then
  paw_tty_marker PAW-TTY1-TARGET-TIMEOUT
  paw_tty_close
  die '确认输入超时或中断;未登记任何目标盘.'
fi
if [[ "$suffix" != "$confirm_value" ]]; then
  paw_tty_marker PAW-TTY1-TARGET-BAD
  paw_tty_say '错误:目标稳定身份确认值不匹配;未登记任何目标盘.'
  paw_tty_close
  die '目标稳定身份确认值不匹配.'
fi
paw_tty_marker PAW-TTY1-TARGET-OK
paw_tty_say '目标 SSD 已按稳定身份登记;未写入任何扇区.'
paw_tty_close
if [[ -n "$(lsblk -nrpo MOUNTPOINTS "$dev" | sed '/^$/d')" ]]; then die '目标 SSD 存在已挂载分区;拒绝登记.'; fi
python3 - "$PAW_CONFIG_DIR/target-ssd.json" "$identity_tmp" <<'PY'
import datetime,json,os,sys
path,identity_path=sys.argv[1:]
d=json.load(open(identity_path,encoding="utf-8"))
data={"approved":True,"schema":"paw.target-ssd.v2",
 "device_path":d["device_path"],"model":d["model"],"capacity_bytes":int(d["capacity_bytes"]),
 "serial":d["serial"],"wwn":d["wwn"],"by_id":d["by_id"],"sysfs_path":d["sysfs_path"],
 "transport":d["transport"],"partition_fingerprint":d["partition_fingerprint"],
 "identity_basis":d["identity_basis"],"identity_strength":d["identity_strength"],
 "hardware_identity_sha256":d["hardware_identity_sha256"],
 "composite_identity_sha256":d["composite_identity_sha256"],
 "device_name_used_as_identity":False,
 "registered_at":datetime.datetime.now(datetime.timezone.utc).isoformat(),
 "registered_by":"interactive read-only stable-identity inventory"}
tmp=path+".tmp"
with open(tmp,"w",encoding="utf-8") as handle: json.dump(data,handle,indent=2,ensure_ascii=False)
os.chmod(tmp,0o600); os.replace(tmp,path)
PY
rm -f "$identity_tmp"
unset serial suffix
log INFO 'Target SSD enrolled from a read-only inventory with a stable identity; no target sectors were written.'
