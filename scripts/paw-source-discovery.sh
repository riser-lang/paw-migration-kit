#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/paw-lib.sh"
need lsblk; need python3; need ssh-keygen; need base64; need rescue_ssh
network_dir="${PAW_NETWORK_DIR:-/run/paw-network}"
rm -f "$network_dir/source-discovery-session.json"

expected_uuid="${PAW_EXPECTED_ROOT_UUID:-}"
if [[ -z "$expected_uuid" ]]; then
  # The expected UUID is never stored in the repository (the public-safety scan
  # forbids committed UUIDs), so it is typed at the console.  The panel has to
  # reach the physical display: paw-console.service sends stdout to the journal.
  # shellcheck source=scripts/paw-tty-lib.sh
  source "$PAW_ROOT/scripts/paw-tty-lib.sh"
  export PAW_TTY_SESSION_NAME=source-discovery
  paw_tty_open_optional || die '无法打开交互终端;未登记源盘.'
  paw_tty_clear
  paw_tty_marker PAW-TTY1-SOURCE-PANEL
  paw_tty_say 'PAW Rescue 源盘身份识别'
  paw_tty_say '下一步会用已固定的主机指纹,通过临时 SSH 只读读取旧 VPS(Rescue Mode)的磁盘清单.'
  paw_tty_say '需要核对旧系统根分区的 UUID;不是新电脑的 UUID,也不是 PAWDATA 的 UUID.'
  paw_tty_say '本程序只读取清单,不写任何磁盘;UUID 不会写入日志.'
  paw_tty_marker PAW-TTY1-SOURCE-PROMPT
  paw_tty_prompt '请输入旧 VPS 根分区 UUID(输入不回显):'
  if ! paw_tty_read_secret expected_uuid; then
    paw_tty_marker PAW-TTY1-SOURCE-TIMEOUT
    paw_tty_say ''
    paw_tty_say '错误:UUID 输入超时或中断,已安全停止,未登记任何源盘.'
    paw_tty_close
    die 'Root UUID input timed out or was aborted; no source was registered.'
  fi
  paw_tty_say ''
  paw_tty_say '已接收 UUID;开始只读识别源盘身份.'
  paw_tty_close
fi
[[ "$expected_uuid" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]] || die 'Expected root UUID is malformed.'
[[ -r "$network_dir/rescue-endpoint.json" && -s "$network_dir/known_hosts" && -s "$network_dir/rescue_ed25519" ]] || die 'RAM-only endpoint, pinned host key, or temporary SSH key missing.'
key_lines="$(grep -vcE '^[[:space:]]*(#|$)' "$network_dir/known_hosts" || true)"
[[ "$key_lines" -eq 1 ]] || die 'Rescue known_hosts must contain exactly one pinned host key.'
host_key_fp="$(ssh-keygen -lf "$network_dir/known_hosts" -E sha256 | awk 'NR==1 {print $2}')"
[[ "$host_key_fp" == SHA256:* ]] || die 'Could not derive the pinned Rescue host-key fingerprint.'

inventory="$(rescue_ssh 'lsblk --json --bytes --output NAME,PATH,TYPE,SIZE,MODEL,SERIAL,RO,FSTYPE,UUID,MOUNTPOINTS,PTTYPE,PARTN,PARTTYPE,PARTUUID,START')" || die 'Authenticated Rescue Mode lsblk query failed.'
inventory_file="$network_dir/remote-lsblk.json"
printf '%s\n' "$inventory" >"$inventory_file"; chmod 0600 "$inventory_file"
inventory_sha="$(sha256sum "$inventory_file" | awk '{print $1}')"
candidate_err="$PAW_REPORT_DIR/.source-discovery-error.json"
rm -f "$candidate_err"
candidate="$(python3 - "$expected_uuid" "${PAW_EXPECTED_SOURCE_BYTES:-53687091200}" "$inventory_file" "$host_key_fp" "$inventory_sha" "$candidate_err" <<'PY'
import hashlib,json,re,sys
expected,size_s,path,host_fp,inventory_sha,err_path=sys.argv[1:]
def fail(reason,extra=None):
    doc={"status":"BLOCKED","reason":reason}
    if extra: doc.update(extra)
    with open(err_path,"w",encoding="utf-8") as h: json.dump(doc,h,indent=2)
    raise SystemExit(reason)
def parse_pos_int(val,label):
    if val is None or isinstance(val,bool): fail(f"source partition {label} is missing")
    s=str(val).strip()
    if not s.isdecimal(): fail(f"source partition {label} is invalid: {val!r}")
    n=int(s)
    if n<=0: fail(f"source partition {label} must be > 0: {n}")
    return n
if not size_s.isdecimal(): fail("invalid expected capacity")
expected_size=int(size_s)
d=json.load(open(path,encoding="utf-8"))
found=[]
def visit(node,parent=None):
    if (node.get("uuid") or "").casefold()==expected.casefold():
        found.append((node,parent))
    for child in node.get("children") or []: visit(child,node)
for top in d.get("blockdevices",[]): visit(top)
if len(found)!=1: fail(f"expected exactly one root UUID match, found {len(found)}")
root,parent=found[0]
if root.get("type")!="part" or str(root.get("fstype","")).lower()!="ext4" or not parent or parent.get("type")!="disk":
    fail("UUID is not an ext4 root partition on a whole disk")
disk_path=parent.get("path") or ("/dev/"+parent.get("name",""))
root_path=root.get("path") or ("/dev/"+root.get("name",""))
if not re.fullmatch(r"/dev/[A-Za-z0-9/]+",disk_path) or not re.fullmatch(r"/dev/[A-Za-z0-9/]+",root_path):
    fail("invalid device path")
if str(parent.get("ro","0")).lower() in ("true","1"): fail("source disk is read-only")
if int(parent.get("size") or 0)!=expected_size: fail("source disk capacity mismatch")
if str(parent.get("pttype","")).lower()!="gpt": fail("source disk is not GPT")
parts=parent.get("children") or []
if not parts: fail("source GPT has no partitions")
part_numbers=[parse_pos_int(p.get("partn"),"partn") for p in parts]
if len(set(part_numbers))!=len(part_numbers): fail("source GPT partition numbers are duplicated")
bios_guid="21686148-6449-6e6f-744e-656564454649"
bios=[p for p in parts if str(p.get("parttype","")).lower()==bios_guid]
if len(bios)!=1 or not 524288 <= int(bios[0].get("size") or 0) <= 4194304:
    fail("GPT BIOS Boot partition missing or size outside 512 KiB-4 MiB")
root_part_no=parse_pos_int(root.get("partn"),"root partn")
if root_part_no not in part_numbers: fail("root partition number is invalid")
serial=str(parent.get("serial") or "").strip()
model=str(parent.get("model") or "").strip()
layout=[]
for p in sorted(parts,key=lambda x:int(x.get("partn"))):
    layout.append({
        "partn":parse_pos_int(p.get("partn"),"partn"),
        "start":parse_pos_int(p.get("start"),"START"),
        "size":parse_pos_int(p.get("size"),"SIZE"),
        "parttype":str(p.get("parttype") or "").lower(),
        "partuuid":str(p.get("partuuid") or "").lower(),
    })
starts=[x["start"] for x in layout]
if len(set(starts))!=len(starts):
    fail("source GPT partition START offsets are duplicated",{"partition_starts":starts})
root_entry=next((x for x in layout if x["partn"]==root_part_no),None)
if not root_entry:
    fail("root partition missing from parsed GPT layout")
root_start=root_entry["start"]
max_start=max(starts)
max_partn=max(layout,key=lambda x:x["start"])["partn"]
if root_start!=max_start:
    fail(
        f"root partition {root_part_no} (start={root_start}) is not the last partition on source disk (max_start={max_start}, partn={max_partn})",
        {"root_is_last_partition":False,"root_partition_number":root_part_no,"root_partition_start":root_start,"max_partition_start":max_start,"last_partition_number":max_partn},
    )
composite_payload={"ssh_host_key_fingerprint":host_fp,"root_uuid":expected.lower(),
 "capacity_bytes":expected_size,"pttype":"gpt","partitions":layout,"serial":serial or None}
composite=hashlib.sha256(json.dumps(composite_payload,sort_keys=True,separators=(",",":")).encode()).hexdigest()
size_gib=expected_size/2**30
basis=["pinned SSH host-key fingerprint","root filesystem UUID","unique parent disk containing the root UUID",
 f"exact {size_gib:g} GiB capacity","GPT partition layout","root partition is last partition by START offset",
 "BIOS Boot partition","no read-write source mount",
 "Rescue discovery timestamp recorded outside the stable identity hash"]
layout_check={"status":"PASS","root_partn":root_part_no,"root_start":root_start,"max_start":max_start,
 "root_is_last_partition":True,"partition_starts":[{"partn":x["partn"],"start":x["start"],"size":x["size"]} for x in layout]}
result={"device_path":disk_path,"root_partition":root_path,"model":model,
 "capacity_bytes":expected_size,"serial":serial,"serial_available":bool(serial),
 "root_uuid":expected.lower(),"bios_partition":bios[0].get("path") or ("/dev/"+bios[0].get("name","")),
 "partition_paths":[disk_path]+[p.get("path") or ("/dev/"+p.get("name","")) for p in parts],
 "partition_number":root_part_no,"root_partition_start":root_start,"max_partition_start":max_start,
 "root_is_last_partition":True,"partition_layout_check":layout_check,"partition_layout":layout,
 "ssh_host_key_fingerprint":host_fp,"inventory_sha256":inventory_sha,
 "composite_identity_sha256":composite,
 "identity_strength":"serial+layout+hostkey" if serial else "composite-no-serial+layout+hostkey",
 "identity_basis":basis}
print(json.dumps(result,separators=(",",":")))
PY
)" || {
  if [[ -s "$candidate_err" ]]; then
    mv -f "$candidate_err" "$PAW_REPORT_DIR/source-discovery.json"
  else
    printf '{"status":"BLOCKED","reason":"Remote source did not match the required UUID, declared capacity, GPT, last-partition root, BIOS Boot and ext4 layout."}\n' >"$PAW_REPORT_DIR/source-discovery.json"
  fi
  chmod 0600 "$PAW_REPORT_DIR/source-discovery.json"
  die 'Rescue Mode disk layout or root UUID did not match the required source identity.'
}
rm -f "$candidate_err"

mapfile -t source_paths < <(python3 -c 'import json,sys; print("\n".join(json.load(sys.stdin)["partition_paths"]))' <<<"$candidate")
(( ${#source_paths[@]} > 0 )) || die 'Remote inventory returned no source device paths.'
for path in "${source_paths[@]}"; do
  [[ "$path" =~ ^/dev/[A-Za-z0-9/]+$ ]] || die 'Remote inventory returned an invalid device path.'
done
# The remote helper proves both facts the old `findmnt ... || true` loop could
# not distinguish: findmnt executed successfully, and /proc/self/mountinfo has
# no read-write mount for any source device (matched by st_rdev major:minor).
# The helper is streamed over the authenticated SSH channel; it does not rely
# on any file being installed on the Rescue host.
mount_helper_b64="$(base64 -w0 "$PAW_ROOT/scripts/paw-source-mount-check.py")"
set +e
mount_json="$(printf '%s' "$mount_helper_b64" | rescue_ssh "base64 -d | python3 - ${source_paths[*]}")"
mount_rc=$?
set -e
if (( mount_rc != 0 )); then
  printf '%s\n' "${mount_json:-{\"status\":\"BLOCKED\",\"reason\":\"MOUNT_CHECK_NO_OUTPUT\"}}" >"$PAW_REPORT_DIR/source-discovery.json"
  chmod 0600 "$PAW_REPORT_DIR/source-discovery.json"
  die "Source mount safety could not be proven (rc=$mount_rc): ${mount_json:-no output}"
fi
printf '%s\n' "$mount_json" >"$PAW_REPORT_DIR/source-mount-check.json"
chmod 0600 "$PAW_REPORT_DIR/source-mount-check.json"
python3 - "$PAW_REPORT_DIR/source-mount-check.json" <<'PY' || die 'Source mount check did not return PASS.'
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
assert d.get("status")=="PASS", d
assert d.get("read_write_mounts")==0, d
PY

python3 - "$candidate" "$PAW_CONFIG_DIR/source.json" "$PAW_REPORT_DIR/source-discovery.json" "$network_dir/rescue-endpoint.json" "$network_dir" <<'PY'
import datetime,json,os,sys
candidate_path,config_path,report_path,endpoint_path,net_dir=sys.argv[1:]
facts=json.loads(candidate_path); endpoint=json.load(open(endpoint_path,encoding="utf-8"))
now=datetime.datetime.now(datetime.timezone.utc).isoformat()
registration={"source_mode":"rescue",**{k:v for k,v in facts.items() if k!="partition_paths"},
 "ssh_host":endpoint["host"],"ssh_port":int(endpoint["port"]),"ssh_user":"root",
 "identity_file":os.path.join(net_dir,"rescue_ed25519"),"known_hosts_file":os.path.join(net_dir,"known_hosts"),
 "identity_confirmed_at":now}
report={"status":"PASS","method":"pinned-host-key SSH; remote lsblk + fail-closed findmnt/mountinfo st_rdev check",
 "source":facts,"discovered_at":now,"inventory_sha256":facts["inventory_sha256"],
 "machine_verified_layout":True,"root_is_last_partition":facts["root_is_last_partition"],
 "partition_layout_check":facts["partition_layout_check"],
 "hardware_serial_available":facts["serial_available"]}
for path,data in ((config_path,registration),(report_path,report)):
    os.makedirs(os.path.dirname(path),exist_ok=True)
    tmp=path+".tmp"
    with open(tmp,"w",encoding="utf-8") as handle: json.dump(data,handle,indent=2)
    os.chmod(tmp,0o600); os.replace(tmp,path)
session_path=os.path.join(net_dir,"source-discovery-session.json")
with open(session_path+".tmp","w",encoding="utf-8") as handle:
    json.dump({"status":"PASS","boot_id":open("/proc/sys/kernel/random/boot_id").read().strip(),"registered_at":now},handle)
os.chmod(session_path+".tmp",0o600); os.replace(session_path+".tmp",session_path)
PY
unset expected_uuid inventory candidate
log INFO "Rescue Mode source identity confirmed: declared capacity, GPT, BIOS Boot, ext4 root UUID match, no read-write mounts, host-key fingerprint pinned."
