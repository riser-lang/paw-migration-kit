#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/paw-lib.sh"
need lsblk; need python3; need findmnt; need rescue_ssh
rm -f /run/paw-network/source-discovery-session.json

expected_uuid="${PAW_EXPECTED_ROOT_UUID:-}"
if [[ -z "$expected_uuid" ]]; then
  read -r -p '输入启动卡要求核对的 Rescue 根分区 UUID（不会写入日志）：' expected_uuid || die 'Root UUID input was not received.'
fi
[[ "$expected_uuid" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]] || die 'Expected root UUID is malformed.'
[[ -r /run/paw-network/rescue-endpoint.json && -s /run/paw-network/known_hosts && -s /run/paw-network/rescue_ed25519 ]] || die 'RAM-only endpoint, pinned host key, or temporary SSH key missing.'

inventory="$(rescue_ssh 'lsblk --json --bytes --output NAME,PATH,TYPE,SIZE,MODEL,SERIAL,RO,FSTYPE,UUID,MOUNTPOINTS,PTTYPE,PARTN,PARTTYPE')" || die 'Authenticated Rescue Mode lsblk query failed.'
inventory_file=/run/paw-network/remote-lsblk.json
printf '%s\n' "$inventory" >"$inventory_file"; chmod 0600 "$inventory_file"
candidate="$(python3 - "$expected_uuid" "${PAW_EXPECTED_SOURCE_BYTES:-53687091200}" "$inventory_file" <<'PY'
import json,re,sys
expected,size_s,path=sys.argv[1:]
if not size_s.isdecimal(): raise SystemExit("invalid expected capacity")
expected_size=int(size_s)
d=json.load(open(path,encoding="utf-8"))
found=[]
def visit(node,parent=None):
    here=node.get("path") or ("/dev/"+node["name"] if node.get("name") else "")
    if node.get("uuid","").casefold()==expected.casefold():
        found.append((node,parent))
    for child in node.get("children") or []: visit(child,node)
for top in d.get("blockdevices",[]): visit(top)
if len(found)!=1: raise SystemExit("expected exactly one root UUID match")
root,parent=found[0]
if root.get("type")!="part" or str(root.get("fstype","")).lower()!="ext4" or not parent or parent.get("type")!="disk": raise SystemExit("UUID is not an ext4 root partition on a whole disk")
disk_path=parent.get("path") or ("/dev/"+parent.get("name",""))
root_path=root.get("path") or ("/dev/"+root.get("name",""))
if not re.fullmatch(r"/dev/[A-Za-z0-9/]+",disk_path) or not re.fullmatch(r"/dev/[A-Za-z0-9/]+",root_path): raise SystemExit("invalid device path")
if int(parent.get("size") or 0)!=expected_size: raise SystemExit("source disk capacity mismatch")
if str(parent.get("pttype","")).lower()!="gpt": raise SystemExit("source disk is not GPT")
bios_guid="21686148-6449-6e6f-744e-656564454649"
parts=parent.get("children") or []
bios=[p for p in parts if str(p.get("parttype","")).lower()==bios_guid]
if len(bios)!=1 or not 524288 <= int(bios[0].get("size") or 0) <= 4194304: raise SystemExit("GPT BIOS Boot partition missing or size outside 512 KiB-4 MiB")
if not parent.get("serial"): raise SystemExit("source disk serial is unavailable")
paths=[disk_path]
for p in parts:
    path=p.get("path") or ("/dev/"+p.get("name",""))
    if not re.fullmatch(r"/dev/[A-Za-z0-9/]+",path): raise SystemExit("invalid partition path")
    paths.append(path)
result={"device_path":disk_path,"root_partition":root_path,"model":str(parent.get("model") or "").strip(),
 "capacity_bytes":expected_size,"serial":str(parent.get("serial")).strip(),"root_uuid":expected,
 "bios_partition":bios[0].get("path") or ("/dev/"+bios[0].get("name","")),"partition_paths":paths,
 "partition_number":int(root.get("partn") or 0)}
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
import json,os,sys,datetime
candidate_path,config_path,report_path,endpoint_path=sys.argv[1:]
facts=json.loads(candidate_path); endpoint=json.load(open(endpoint_path,encoding="utf-8"))
registration={"source_mode":"rescue",**{k:v for k,v in facts.items() if k!="partition_paths"},
 "ssh_host":endpoint["host"],"ssh_port":int(endpoint["port"]),"ssh_user":"root",
 "identity_file":"/run/paw-network/rescue_ed25519","known_hosts_file":"/run/paw-network/known_hosts",
 "identity_confirmed_at":datetime.datetime.now(datetime.timezone.utc).isoformat()}
for path,data in ((config_path,registration),(report_path,{"status":"PASS","method":"pinned-host-key SSH; remote lsblk+findmnt","source":facts,"registered_at":registration["identity_confirmed_at"]})):
    os.makedirs(os.path.dirname(path),exist_ok=True)
    tmp=path+".tmp"
    with open(tmp,"w",encoding="utf-8") as handle: json.dump(data,handle,indent=2)
    os.chmod(tmp,0o600); os.replace(tmp,path)
session_path="/run/paw-network/source-discovery-session.json"
with open(session_path+".tmp","w",encoding="utf-8") as handle:
    json.dump({"status":"PASS","boot_id":open("/proc/sys/kernel/random/boot_id").read().strip(),"registered_at":registration["identity_confirmed_at"]},handle)
os.chmod(session_path+".tmp",0o600); os.replace(session_path+".tmp",session_path)
PY
unset expected_uuid inventory candidate
log INFO 'Rescue Mode source identity confirmed: 50 GiB GPT, BIOS Boot, ext4 root UUID match, no read-write mounts.'
