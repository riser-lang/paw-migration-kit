#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/paw-lib.sh"
need lsblk; need python3; need findmnt; need ssh-keygen; need rescue_ssh
rm -f /run/paw-network/source-discovery-session.json

expected_uuid="${PAW_EXPECTED_ROOT_UUID:-}"
if [[ -z "$expected_uuid" ]]; then
  # The expected UUID is never stored in the repository (the public-safety scan
  # forbids committed UUIDs), so it is typed at the console.  The panel has to
  # reach the physical display: paw-console.service sends stdout to the journal.
  # shellcheck source=scripts/paw-tty-lib.sh
  source "$PAW_ROOT/scripts/paw-tty-lib.sh"
  export PAW_TTY_SESSION_NAME=source-discovery
  paw_tty_open_optional || die '无法打开交互终端；未登记源盘。'
  paw_tty_clear
  paw_tty_marker PAW-TTY1-SOURCE-PANEL
  paw_tty_say 'PAW Rescue 源盘身份识别'
  paw_tty_say '下一步会用已固定的主机指纹，通过临时 SSH 只读读取旧 VPS（Rescue Mode）的磁盘清单。'
  paw_tty_say '需要核对旧系统根分区的 UUID；不是新电脑的 UUID，也不是 PAWDATA 的 UUID。'
  paw_tty_say '本程序只读取清单，不写任何磁盘；UUID 不会写入日志。'
  paw_tty_marker PAW-TTY1-SOURCE-PROMPT
  paw_tty_prompt '请输入旧 VPS 根分区 UUID（输入不回显）：'
  if ! paw_tty_read_secret expected_uuid; then
    paw_tty_marker PAW-TTY1-SOURCE-TIMEOUT
    paw_tty_say ''
    paw_tty_say '错误：UUID 输入超时或中断，已安全停止，未登记任何源盘。'
    paw_tty_close
    die 'Root UUID input timed out or was aborted; no source was registered.'
  fi
  paw_tty_say ''
  paw_tty_say '已接收 UUID；开始只读识别源盘身份。'
  paw_tty_close
fi
[[ "$expected_uuid" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]] || die 'Expected root UUID is malformed.'
[[ -r /run/paw-network/rescue-endpoint.json && -s /run/paw-network/known_hosts && -s /run/paw-network/rescue_ed25519 ]] || die 'RAM-only endpoint, pinned host key, or temporary SSH key missing.'
key_lines="$(grep -vcE '^[[:space:]]*(#|$)' /run/paw-network/known_hosts || true)"
[[ "$key_lines" -eq 1 ]] || die 'Rescue known_hosts must contain exactly one pinned host key.'
host_key_fp="$(ssh-keygen -lf /run/paw-network/known_hosts -E sha256 | awk 'NR==1 {print $2}')"
[[ "$host_key_fp" == SHA256:* ]] || die 'Could not derive the pinned Rescue host-key fingerprint.'

inventory="$(rescue_ssh 'lsblk --json --bytes --output NAME,PATH,TYPE,SIZE,MODEL,SERIAL,RO,FSTYPE,UUID,MOUNTPOINTS,PTTYPE,PARTN,PARTTYPE,PARTUUID,START')" || die 'Authenticated Rescue Mode lsblk query failed.'
inventory_file=/run/paw-network/remote-lsblk.json
printf '%s\n' "$inventory" >"$inventory_file"; chmod 0600 "$inventory_file"
inventory_sha="$(sha256sum "$inventory_file" | awk '{print $1}')"
candidate="$(python3 - "$expected_uuid" "${PAW_EXPECTED_SOURCE_BYTES:-53687091200}" "$inventory_file" "$host_key_fp" "$inventory_sha" <<'PY'
import hashlib,json,re,sys
expected,size_s,path,host_fp,inventory_sha=sys.argv[1:]
if not size_s.isdecimal(): raise SystemExit("invalid expected capacity")
expected_size=int(size_s)
d=json.load(open(path,encoding="utf-8"))
found=[]
def visit(node,parent=None):
    here=node.get("path") or ("/dev/"+node["name"] if node.get("name") else "")
    if (node.get("uuid") or "").casefold()==expected.casefold():
        found.append((node,parent))
    for child in node.get("children") or []: visit(child,node)
for top in d.get("blockdevices",[]): visit(top)
if len(found)!=1: raise SystemExit("expected exactly one root UUID match")
root,parent=found[0]
if root.get("type")!="part" or str(root.get("fstype","")).lower()!="ext4" or not parent or parent.get("type")!="disk":
    raise SystemExit("UUID is not an ext4 root partition on a whole disk")
disk_path=parent.get("path") or ("/dev/"+parent.get("name",""))
root_path=root.get("path") or ("/dev/"+root.get("name",""))
if not re.fullmatch(r"/dev/[A-Za-z0-9/]+",disk_path) or not re.fullmatch(r"/dev/[A-Za-z0-9/]+",root_path):
    raise SystemExit("invalid device path")
if str(parent.get("ro","0")).lower() in ("true","1"): raise SystemExit("source disk is read-only")
if int(parent.get("size") or 0)!=expected_size: raise SystemExit("source disk capacity mismatch")
if str(parent.get("pttype","")).lower()!="gpt": raise SystemExit("source disk is not GPT")
parts=parent.get("children") or []
if not parts: raise SystemExit("source GPT has no partitions")
part_numbers=[int(p.get("partn") or 0) for p in parts]
if any(n<1 for n in part_numbers) or len(set(part_numbers))!=len(part_numbers): raise SystemExit("source GPT partition numbers are invalid")
bios_guid="21686148-6449-6e6f-744e-656564454649"
bios=[p for p in parts if str(p.get("parttype","")).lower()==bios_guid]
if len(bios)!=1 or not 524288 <= int(bios[0].get("size") or 0) <= 4194304:
    raise SystemExit("GPT BIOS Boot partition missing or size outside 512 KiB-4 MiB")
root_part_no=int(root.get("partn") or 0)
if root_part_no<1 or root_part_no not in part_numbers: raise SystemExit("root partition number is invalid")
serial=str(parent.get("serial") or "").strip()
model=str(parent.get("model") or "").strip()
layout=[]
for p in sorted(parts,key=lambda x:int(x.get("partn") or 0)):
    layout.append({
        "partn":int(p.get("partn") or 0),
        "start":int(p.get("start") or 0),
        "size":int(p.get("size") or 0),
        "parttype":str(p.get("parttype") or "").lower(),
        "partuuid":str(p.get("partuuid") or "").lower(),
    })
if not all(x["size"]>0 for x in layout): raise SystemExit("source partition size is invalid")
composite_payload={"ssh_host_key_fingerprint":host_fp,"root_uuid":expected.lower(),
 "capacity_bytes":expected_size,"pttype":"gpt","partitions":layout,"serial":serial or None}
composite=hashlib.sha256(json.dumps(composite_payload,sort_keys=True,separators=(",",":")).encode()).hexdigest()
basis=["pinned SSH host-key fingerprint","root filesystem UUID","unique parent disk containing the root UUID",
 "exact 50 GiB capacity","GPT partition layout","BIOS Boot partition","no read-write source mount",
 "Rescue discovery timestamp recorded outside the stable identity hash"]
result={"device_path":disk_path,"root_partition":root_path,"model":model,
 "capacity_bytes":expected_size,"serial":serial,"serial_available":bool(serial),
 "root_uuid":expected.lower(),"bios_partition":bios[0].get("path") or ("/dev/"+bios[0].get("name","")),
 "partition_paths":[disk_path]+[p.get("path") or ("/dev/"+p.get("name","")) for p in parts],
 "partition_number":root_part_no,"partition_layout":layout,
 "ssh_host_key_fingerprint":host_fp,"inventory_sha256":inventory_sha,
 "composite_identity_sha256":composite,
 "identity_strength":"serial+layout+hostkey" if serial else "composite-no-serial+layout+hostkey",
 "identity_basis":basis}
print(json.dumps(result,separators=(",",":")))
PY
)" || {
  printf '{"status":"BLOCKED","reason":"Remote source did not match the required UUID, 50 GiB GPT, BIOS Boot and ext4 layout."}\n' >"$PAW_REPORT_DIR/source-discovery.json"
  chmod 0600 "$PAW_REPORT_DIR/source-discovery.json"
  die 'Rescue Mode disk layout or root UUID did not match the required source identity.'
}

while IFS= read -r path; do
  [[ "$path" =~ ^/dev/[A-Za-z0-9/]+$ ]] || die 'Remote inventory returned an invalid device path.'
  options="$(rescue_ssh "findmnt --noheadings --raw --source '$path' --output OPTIONS" 2>/dev/null || true)"
  while IFS= read -r opts; do
    [[ -z "$opts" ]] && continue
    case ",$opts," in *,rw,*)
      printf '{"status":"BLOCKED","reason":"A source device is mounted read-write; source registration withheld."}\n' >"$PAW_REPORT_DIR/source-discovery.json"
      chmod 0600 "$PAW_REPORT_DIR/source-discovery.json"
      die 'A Rescue Mode source disk or partition is mounted read-write.' ;;
    esac
  done <<<"$options"
done < <(python3 -c 'import json,sys; print("\n".join(json.load(sys.stdin)["partition_paths"]))' <<<"$candidate")

python3 - "$candidate" "$PAW_CONFIG_DIR/source.json" "$PAW_REPORT_DIR/source-discovery.json" /run/paw-network/rescue-endpoint.json <<'PY'
import datetime,json,os,sys
candidate_path,config_path,report_path,endpoint_path=sys.argv[1:]
facts=json.loads(candidate_path); endpoint=json.load(open(endpoint_path,encoding="utf-8"))
now=datetime.datetime.now(datetime.timezone.utc).isoformat()
registration={"source_mode":"rescue",**{k:v for k,v in facts.items() if k!="partition_paths"},
 "ssh_host":endpoint["host"],"ssh_port":int(endpoint["port"]),"ssh_user":"root",
 "identity_file":"/run/paw-network/rescue_ed25519","known_hosts_file":"/run/paw-network/known_hosts",
 "identity_confirmed_at":now}
report={"status":"PASS","method":"pinned-host-key SSH; remote lsblk+findmnt",
 "source":facts,"discovered_at":now,"inventory_sha256":facts["inventory_sha256"],
 "machine_verified_layout":True,"hardware_serial_available":facts["serial_available"]}
for path,data in ((config_path,registration),(report_path,report)):
    os.makedirs(os.path.dirname(path),exist_ok=True)
    tmp=path+".tmp"
    with open(tmp,"w",encoding="utf-8") as handle: json.dump(data,handle,indent=2)
    os.chmod(tmp,0o600); os.replace(tmp,path)
session_path="/run/paw-network/source-discovery-session.json"
with open(session_path+".tmp","w",encoding="utf-8") as handle:
    json.dump({"status":"PASS","boot_id":open("/proc/sys/kernel/random/boot_id").read().strip(),"registered_at":now},handle)
os.chmod(session_path+".tmp",0o600); os.replace(session_path+".tmp",session_path)
PY
unset expected_uuid inventory candidate
log INFO "Rescue Mode source identity confirmed: 50 GiB GPT, BIOS Boot, ext4 root UUID match, no read-write mounts, host-key fingerprint pinned."
