#!/usr/bin/env bash
# Deterministic identity/health tests.  No real disk is opened for writing:
# lsblk, blockdev, smartctl, badblocks and dmesg are mocks, and the only block
# special path is the pre-existing /dev/loop0 used as a gate fixture.
set -Eeuo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
out="${PAW_ARTIFACT_DIR:-$PWD/artifacts}"
work="$root/tests/virtual/ssd-identity-run"
mock="$work/mockbin"; state="$work/state"; db="$work/devices.json"
rm -rf "$work"; mkdir -p "$mock" "$state/configs" "$state/reports" "$state/logs" "$out" \
  "$work/sysfs/loop0" "$work/sysfs/loop1" "$work/by-id"
export PAW_ROOT="$root" PAW_STATE_DIR="$state" PAW_CONFIG_DIR="$state/configs" PAW_REPORT_DIR="$state/reports" PAW_LOG_DIR="$state/logs"
export PATH="$mock:$PATH" PAW_MOCK_DB="$db" PAW_IDENTITY_SYSFS_ROOT="$work/sysfs" PAW_IDENTITY_BY_ID_ROOT="$work/by-id"
report="$out/ssd-identity-test-report.txt"; passed=0; failed=0
pass(){ printf 'PASS %s\n' "$1" >>"$report"; passed=$((passed+1)); }
fail(){ printf 'FAIL %s\n' "$1" >>"$report"; failed=$((failed+1)); }
printf 'SSD stable identity, inventory and read-only health gate tests\n' >"$report"

cat >"$mock/lsblk" <<'MOCK'
#!/usr/bin/env python3
import json,os,sys
args=sys.argv[1:]
db=json.load(open(os.environ["PAW_MOCK_DB"],encoding="utf-8"))
dev=next((a for a in reversed(args) if a.startswith("/dev/")), "")
entry=db.get(dev)
def part_list(e):
    return [{"name":p.get("name",e["name"]+"p1"),"path":p.get("path",dev+"p1"),
             "type":"part","size":p.get("size",e["capacity"]-1048576),
             "start":p.get("start",2048),"partn":p.get("partn",1),
             "parttype":p.get("parttype",""),"partuuid":p.get("partuuid",""),
             "fstype":p.get("fstype",""),"mountpoints":p.get("mountpoints",[])}
            for p in e.get("parts",[])]
if "--json" in args and "--output" in args:
    devices=[]
    for path,e in db.items():
        devices.append({"name":e["name"],"path":path,"type":"disk","size":e["capacity"],
                        "model":e.get("model",""),"serial":e.get("serial",""),
                        "wwn":e.get("wwn",""),"tran":e.get("tran",""),
                        "rm":e.get("rm",0),"mountpoints":[],"children":part_list(e)})
    print(json.dumps({"blockdevices":devices})); raise SystemExit(0)
if "-J" in args:
    if not entry: print('{"blockdevices":[]}'); raise SystemExit(0)
    print(json.dumps({"blockdevices":[{"name":entry["name"],"path":dev,"type":"disk",
        "size":entry["capacity"],"children":part_list(entry)}]})); raise SystemExit(0)
if "-dn" in args:
    field=args[args.index("-o")+1] if "-o" in args else ""
    if not entry: print(""); raise SystemExit(0)
    if field=="SERIAL": print(entry.get("serial",""))
    elif field=="MODEL": print(entry.get("model",""))
    elif field=="WWN": print(entry.get("wwn",""))
    elif field=="TRAN": print(entry.get("tran",""))
    elif field=="TYPE": print("disk")
    elif field=="PKNAME": print("")
    else: print("")
    raise SystemExit(0)
if "-nrpo" in args:
    field=args[args.index("-nrpo")+1] if args.index("-nrpo")+1 < len(args) else ""
    if field in ("MOUNTPOINTS","MOUNTPOINT") and entry:
        if os.environ.get("PAW_MOCK_MOUNTED")=="1":
            print("/mnt/target"); raise SystemExit(0)
        for p in entry.get("parts",[]):
            for m in p.get("mountpoints",[]): print(m)
    raise SystemExit(0)
print("")
MOCK
cat >"$mock/blockdev" <<'MOCK'
#!/usr/bin/env python3
import json,os,sys
db=json.load(open(os.environ["PAW_MOCK_DB"],encoding="utf-8"))
print(db.get(sys.argv[-1],{}).get("capacity",240000000000))
MOCK
cat >"$mock/findmnt" <<'MOCK'
#!/usr/bin/env bash
if [[ ${PAW_MOCK_LIVE_MEDIUM:-0} == 1 ]]; then printf '/dev/loop0[/live]\n'; exit 0; fi
exit 1
MOCK
cat >"$mock/dmesg" <<'MOCK'
#!/usr/bin/env bash
[[ ${PAW_MOCK_DMESG_ERROR:-0} == 1 ]] && echo 'ata1.00: failed command: READ FPDMA QUEUED' || true
MOCK
cat >"$mock/sensors" <<'MOCK'
#!/usr/bin/env bash
printf 'Package id 0:  +45.0°C  (high = +80.0°C)\n'
MOCK
cat >"$mock/badblocks" <<'MOCK'
#!/usr/bin/env bash
[[ ${PAW_MOCK_SCAN_FAIL:-0} == 1 ]] && exit 1
echo 'Pass completed, 0 bad blocks found.'
MOCK
cat >"$mock/smartctl" <<'MOCK'
#!/usr/bin/env bash
mode="${PAW_MOCK_SMART_MODE:-pass}"
case "$1" in
  -x) echo 'SMART support is: Available - device has SMART capability.'
      echo 'ID# ATTRIBUTE_NAME FLAG VALUE WORST THRESH TYPE UPDATED WHEN_FAILED RAW_VALUE'
      echo '  5 Reallocated_Sector_Ct 0x0033 100 100 010 Pre-fail Always - 0'
      echo '194 Temperature_Celsius 0x0022 035 040 000 Old_age Always - '"${PAW_MOCK_TEMP:-35}"' (Min/Max 20/45)'
      echo '199 UDMA_CRC_Error_Count 0x0032 200 200 000 Old_age Always - '"${PAW_MOCK_CRC:-0}" ;;
  -H) if [[ "$mode" == healthfail ]]; then echo 'SMART overall-health self-assessment test result: FAILED!'; exit 1; fi
      echo 'SMART overall-health self-assessment test result: PASSED' ;;
  -c) echo 'Self-test execution status: 0'
      echo 'Short self-test routine recommended polling time: 1 minutes'
      echo 'Extended self-test routine recommended polling time: 10 minutes' ;;
  -t) echo 'Please wait 1 minutes for test to complete.' ;;
  -l) if [[ "$mode" == selffail ]]; then echo '# 1  Short offline  Completed: read failure  90%  1234 -'; else echo '# 1  Short offline  Completed without error  00%  1234 -'; fi ;;
  *) exit 0 ;;
esac
MOCK
chmod 0755 "$mock/"*

write_db(){ cat >"$db"; }
mk_sysfs(){ mkdir -p "$work/sysfs/$1"; }
reset_symlinks(){ rm -f "$work/by-id"/*; }
add_byid(){ ln -sfn "/dev/$2" "$work/by-id/$1"; }

# One healthy 240 GB SATA disk with a real serial, WWN and by-id link.
healthy_db(){ write_db <<JSON
{"/dev/loop0":{"name":"loop0","model":"Samsung SSD 860","serial":"PAW-SSD-TEST",
 "wwn":"wwn-0x5002538e00000001","tran":"sata","capacity":240000000000,"rm":0,
 "parts":[{"partn":1,"fstype":"ext4","size":239000000000,"parttype":"0fc63daf-8483-4772-8e79-3d69d8477de4","mountpoints":[]}]}}
JSON
mk_sysfs loop0; reset_symlinks; add_byid ata-PAW-SSD-TEST loop0; }
healthy_db

identity_json(){ python3 "$root/scripts/paw-identity.py" identity "$1"; }
assert_json(){ python3 - "$1" "$2" <<'PY'
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
ns={}; exec(sys.argv[2],{"d":d,"json":json,"sys":sys},ns)
PY
}
run_check(){ local name="$1"; shift; if "$@" >/dev/null 2>&1; then pass "$name"; else fail "$name"; fi; }

# --- pure identity cases -----------------------------------------------------
if identity_json /dev/loop0 >"$work/id.json" 2>"$work/id.err"; then
  if assert_json "$work/id.json" 'assert d["serial"]=="PAW-SSD-TEST"; assert d["identity_basis"].startswith("serial+"); assert d["identity_strength"]=="strong"; assert len(d["hardware_identity_sha256"])==64; assert d["device_name_used_as_identity"] is False'; then
    pass 'serial identity uses serial/WWN/by-id/capacity, never dev name'
  else fail 'serial identity fields'; fi
else fail 'serial identity command'; fi

write_db <<'JSON'
{"/dev/loop0":{"name":"loop0","model":"Samsung SSD 870","serial":"","wwn":"wwn-0x5002538e00000002","tran":"sata","capacity":240000000000,"rm":0,"parts":[]}}
JSON
reset_symlinks
if identity_json /dev/loop0 >"$work/id.json" 2>/dev/null && assert_json "$work/id.json" 'assert d["serial"]==""; assert d["identity_basis"].startswith("wwn+"); assert d["identity_strength"]=="strong"'; then
  pass 'no serial but WWN is a strong identity'
else fail 'no-serial WWN identity'; fi

write_db <<'JSON'
{"/dev/loop0":{"name":"loop0","model":"Samsung SSD 870","serial":"","wwn":"","tran":"sata","capacity":240000000000,"rm":0,"parts":[]}}
JSON
reset_symlinks; add_byid ata-PAW-NOSERIAL loop0
if identity_json /dev/loop0 >"$work/id.json" 2>/dev/null && assert_json "$work/id.json" 'assert d["identity_basis"].startswith("by-id+"); assert d["identity_strength"]=="strong"'; then
  pass 'no serial/WWN but by-id is a strong identity'
else fail 'no-serial by-id identity'; fi

reset_symlinks
if identity_json /dev/loop0 >"$work/id.json" 2>/dev/null && assert_json "$work/id.json" 'assert d["identity_strength"]=="weak"; assert d["sufficient"] is True; assert "sysfs" in d["identity_basis"]'; then
  pass 'no serial/WWN/by-id falls back to model+capacity+sysfs+partition'
else fail 'no-anchor fallback identity'; fi

rm -rf "$work/sysfs/loop0"
set +e; identity_json /dev/loop0 >"$work/id.json" 2>"$work/id.err"; rc=$?; set -e
if ((rc != 0)) && assert_json "$work/id.json" 'assert d["sufficient"] is False; assert d["identity_strength"]=="insufficient"'; then
  pass 'no sysfs/by-id/serial/WWN is refused as insufficient'
else fail 'insufficient identity refusal'; fi
mk_sysfs loop0

# --- inventory exclusions and ambiguity ------------------------------------
write_db <<'JSON'
{"/dev/loop0":{"name":"loop0","model":"Same","serial":"SERIAL-A","wwn":"","tran":"sata","capacity":240000000000,"rm":0,"parts":[]},
 "/dev/loop1":{"name":"loop1","model":"Same","serial":"SERIAL-B","wwn":"","tran":"sata","capacity":240000000000,"rm":0,"parts":[]}}
JSON
mk_sysfs loop1
if python3 "$root/scripts/paw-identity.py" inventory >"$work/inv.json" 2>/dev/null && assert_json "$work/inv.json" 'assert d["eligible_count"]==2; assert all(not x["ambiguous"] for x in d["devices"])'; then
  pass 'two same-capacity disks with distinct serials are both eligible'
else fail 'same-capacity distinct identity inventory'; fi

write_db <<'JSON'
{"/dev/loop0":{"name":"loop0","model":"Same","serial":"DUP","tran":"sata","capacity":240000000000,"rm":0,"parts":[]},
 "/dev/loop1":{"name":"loop1","model":"Same","serial":"DUP","tran":"sata","capacity":240000000000,"rm":0,"parts":[]}}
JSON
if python3 "$root/scripts/paw-identity.py" inventory >"$work/inv.json" 2>/dev/null && assert_json "$work/inv.json" 'assert d["eligible_count"]==0; assert all(x["ambiguous"] for x in d["devices"])'; then
  pass 'duplicate serial disks are ambiguous and refused'
else fail 'duplicate serial ambiguity'; fi

write_db <<'JSON'
{"/dev/loop0":{"name":"loop0","model":"Windows","serial":"WIN","tran":"sata","capacity":240000000000,"rm":0,"parts":[{"partn":1,"fstype":"ntfs","parttype":"ebd0a0a2-b9e5-4433-87c0-68b6b72699c7","mountpoints":[]}]}}
JSON
if python3 "$root/scripts/paw-identity.py" inventory >"$work/inv.json" 2>/dev/null && assert_json "$work/inv.json" 'assert d["devices"][0]["windows"] is True; assert d["devices"][0]["eligible"] is False; assert "windows_or_ntfs" in d["devices"][0]["exclusion_reasons"]'; then
  pass 'Windows/NTFS disk is shown with exclusion reason'
else fail 'Windows exclusion'; fi

write_db <<'JSON'
{"/dev/loop0":{"name":"loop0","model":"Mounted","serial":"MNT","tran":"sata","capacity":240000000000,"rm":0,"parts":[{"partn":1,"fstype":"ext4","parttype":"0fc63daf-8483-4772-8e79-3d69d8477de4","mountpoints":["/mnt/target"]}]}}
JSON
if python3 "$root/scripts/paw-identity.py" inventory --boot-device /dev/loop1 --source-device /dev/loop1 >"$work/inv.json" 2>/dev/null && assert_json "$work/inv.json" 'assert d["devices"][0]["mounted"] is True; assert "mounted" in d["devices"][0]["exclusion_reasons"]'; then
  pass 'mounted disk is excluded'
else fail 'mounted exclusion'; fi

if python3 "$root/scripts/paw-identity.py" inventory --boot-device /dev/loop0 >"$work/inv.json" 2>/dev/null && assert_json "$work/inv.json" 'assert "current_boot_medium" in d["devices"][0]["exclusion_reasons"]'; then
  pass 'current boot media is excluded'
else fail 'boot media exclusion'; fi
if python3 "$root/scripts/paw-identity.py" inventory --source-device /dev/loop0 >"$work/inv.json" 2>/dev/null && assert_json "$work/inv.json" 'assert "registered_source" in d["devices"][0]["exclusion_reasons"]'; then
  pass 'registered source disk is excluded'
else fail 'source exclusion'; fi

# --- verify: path move, replacement, post-authorization change -------------
healthy_db
identity_json /dev/loop0 >"$work/id.json"
python3 - "$work/id.json" "$state/configs/target-ssd.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8")); d["approved"]=True
json.dump(d,open(sys.argv[2],"w",encoding="utf-8"),indent=2)
PY
# Same physical disk renumbered: same serial/WWN/sysfs/by-id, different path.
write_db <<'JSON'
{"/dev/loop1":{"name":"loop0","model":"Samsung SSD 860","serial":"PAW-SSD-TEST",
 "wwn":"wwn-0x5002538e00000001","tran":"sata","capacity":240000000000,"rm":0,
 "parts":[{"partn":1,"fstype":"ext4","size":239000000000,"parttype":"0fc63daf-8483-4772-8e79-3d69d8477de4","mountpoints":[]}]}}
JSON
reset_symlinks; add_byid ata-PAW-SSD-TEST loop1
if python3 "$root/scripts/paw-identity.py" verify --config "$state/configs/target-ssd.json" --device /dev/loop1 --phase prewrite >"$work/verify.json" 2>/dev/null && assert_json "$work/verify.json" 'assert d["status"]=="PASS"; assert d["device_path_changed"] is True'; then
  pass 'device path renumbering is accepted only by matching stable identity'
else fail 'path-change verification'; fi

write_db <<'JSON'
{"/dev/loop1":{"name":"loop1","model":"Samsung SSD 860","serial":"REPLACEMENT","wwn":"","tran":"sata","capacity":240000000000,"rm":0,"parts":[]}}
JSON
reset_symlinks
if ! python3 "$root/scripts/paw-identity.py" verify --config "$state/configs/target-ssd.json" --device /dev/loop1 --phase prewrite >"$work/verify.json" 2>/dev/null && assert_json "$work/verify.json" 'assert d["status"]=="BLOCKED"; assert any("hardware" in p for p in d["problems"])'; then
  pass 'replacement disk is refused'
else fail 'replacement refusal'; fi

# Authorization is bound to the hardware hash, not the current /dev path.
python3 - "$state/configs/target-ssd.json" "$state/reports/operator-authorization.json" <<'PY'
import json,sys,uuid
c=json.load(open(sys.argv[1],encoding="utf-8"))
a={"status":"AUTHORIZED","migration_id":str(uuid.uuid4()),"authorization_id":str(uuid.uuid4()),
   "target_device":c["device_path"],"target_serial":c["serial"],
   "target_hardware_identity_sha256":c["hardware_identity_sha256"],
   "target_composite_identity_sha256":c["composite_identity_sha256"]}
json.dump(a,open(sys.argv[2],"w",encoding="utf-8"),indent=2)
PY
if (export PAW_REPORT_DIR="$state/reports" PAW_CONFIG_DIR="$state/configs" PAW_ROOT="$root"; source "$root/scripts/paw-lib.sh"; assert_authorization_for_target /dev/loop0) >/dev/null 2>&1; then
  # loop0 now points at REPLACEMENT, so this must actually fail; the branch is
  # inverted deliberately to catch a helper that trusts the old path.
  fail 'post-authorization replacement unexpectedly authorized'
else pass 'post-authorization replacement is refused by hash'; fi

# --- interactive discovery / enrollment -----------------------------------
run_discovery(){
  local name="$1" expected_suffix="$2"
  rm -f "$state/configs/target-ssd.json"
  if printf '1\n%s\n' "$expected_suffix" | \
       "$root/scripts/paw-target-discovery.sh" >"$state/logs/$name.log" 2>&1; then
    if python3 - "$state/configs/target-ssd.json" "$name" <<'PY'
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
assert d["approved"] is True
assert len(d["hardware_identity_sha256"])==64
assert len(d["composite_identity_sha256"])==64
assert d["device_name_used_as_identity"] is False
assert d["identity_basis"]
PY
    then pass "discovery enrolls $name by stable identity"; else fail "discovery config $name"; fi
  else fail "discovery $name enrollment"; fi
}
healthy_db
serial_suffix="$(python3 -c 'print("PAW-SSD-TEST"[-6:])')"
run_discovery serial "$serial_suffix"
write_db <<'JSON'
{"/dev/loop0":{"name":"loop0","model":"NoSerial NVMe","serial":"","wwn":"wwn-0x5002538e00000009","tran":"nvme","capacity":240000000000,"rm":0,"parts":[]}}
JSON
reset_symlinks
wwn_hw="$(python3 "$root/scripts/paw-identity.py" identity /dev/loop0 | python3 -c 'import json,sys;print(json.load(sys.stdin)["hardware_identity_sha256"])')"
run_discovery no_serial_wwn "${wwn_hw: -8}"
write_db <<'JSON'
{"/dev/loop0":{"name":"loop0","model":"Windows","serial":"WIN","tran":"sata","capacity":240000000000,"rm":0,"parts":[{"partn":1,"fstype":"ntfs","parttype":"ebd0a0a2-b9e5-4433-87c0-68b6b72699c7","mountpoints":[]}]}}
JSON
rm -f "$state/configs/target-ssd.json"
set +e
printf '1\n' | "$root/scripts/paw-target-discovery.sh" >"$state/logs/discovery_windows.log" 2>&1
rc=$?
set -e
if ((rc != 0)) && grep -q 'Windows/NTFS' "$state/logs/discovery_windows.log" && [[ ! -e "$state/configs/target-ssd.json" ]]; then
  pass 'discovery shows Windows disk exclusion and enrolls nothing'
else fail 'discovery Windows exclusion'; fi

# --- hardware preflight gates ---------------------------------------------
healthy_db
identity_json /dev/loop0 >"$work/id.json"
python3 - "$work/id.json" "$state/configs/target-ssd.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8")); d["approved"]=True
json.dump(d,open(sys.argv[2],"w",encoding="utf-8"),indent=2)
PY
cat >"$state/memtest-attestation.json" <<JSON
{"schema":"paw.memtest-attestation.v1","method":"manual_operator_observation",
 "trust_level":"operator_attestation_not_cryptographic","status":"OPERATOR_CONFIRMED",
 "boot_id":"$(cat /proc/sys/kernel/random/boot_id)","target_serial":"PAW-SSD-TEST",
 "target_device":"/dev/loop0","completed_passes":1,"error_count":0}
JSON
export PAW_MEMTEST_ATTESTATION="$state/memtest-attestation.json"
run_preflight(){
  local name="$1" expected="$2"; shift 2
  rm -f "$state/reports/"*.json "$state/reports/"*.txt
  set +e
  env "$@" "$root/scripts/paw-hardware-preflight.sh" /dev/loop0 >"$state/logs/$name.log" 2>&1
  local rc=$?
  set -e
  local status
  status="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("status",""))' "$state/reports/paw-hardware-health-report.json" 2>/dev/null || true)"
  if [[ "$status" == "$expected" ]]; then pass "$name => $expected (rc=$rc)"; else fail "$name expected $expected got '${status:-missing}' rc=$rc"; fi
}
run_preflight healthy PASS
run_preflight utf8_sensor_c_locale PASS LC_ALL=C
run_preflight live_medium_excluded BLOCKED PAW_MOCK_LIVE_MEDIUM=1
run_preflight mounted_target BLOCKED PAW_MOCK_MOUNTED=1
run_preflight smart_health_failed FAIL PAW_MOCK_SMART_MODE=healthfail
run_preflight temperature_85c FAIL PAW_MOCK_TEMP=85
run_preflight crc_errors WARN PAW_MOCK_CRC=12
run_preflight selftest_failed FAIL PAW_MOCK_SMART_MODE=selffail
run_preflight scan_failure FAIL PAW_MOCK_SCAN_FAIL=1

# serial/capacity-mismatch fixtures are applied by rewriting the one-disk DB;
# keep the healthy DB as the baseline for every other case.
bad_serial(){
  healthy_db
  python3 - "$db" <<'PY'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); d["/dev/loop0"]["serial"]="OTHER-SSD"; json.dump(d,open(p,"w"))
PY
  run_preflight serial_mismatch BLOCKED
}
bad_capacity(){
  healthy_db
  python3 - "$db" <<'PY'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); d["/dev/loop0"]["capacity"]=256060514304; json.dump(d,open(p,"w"))
PY
  run_preflight capacity_mismatch BLOCKED
}
bad_serial
bad_capacity
healthy_db
run_preflight healthy PASS
python3 - "$state/reports/paw-ssd-identity.json" <<'PY' && pass 'identity report records basis/hashes, never device name' || fail 'identity report fields'
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
assert d["identity_basis"].startswith("serial+")
assert len(d["hardware_identity_sha256"])==64
assert d["device_name_used_as_identity"] is False
PY
# --- P0-4: paw-live-controller + no-serial SSD end-to-end flow -------------
# Add mountpoint/blkid mocks and teach findmnt to answer --target queries for
# paw-data-check.sh while preserving PAW_MOCK_LIVE_MEDIUM for /run/live/medium.
cat >"$mock/mountpoint" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK
cat >"$mock/blkid" <<'MOCK'
#!/usr/bin/env bash
printf 'PAWDATA\n'
MOCK
cat >"$mock/findmnt" <<'MOCK'
#!/usr/bin/env bash
if [[ "$*" == *"--target"* ]]; then
  if [[ "$*" == *"SOURCE"* ]]; then printf '/dev/pawdata1\n'; exit 0; fi
  if [[ "$*" == *"FSTYPE"* ]]; then printf 'ext4\n'; exit 0; fi
fi
if [[ ${PAW_MOCK_LIVE_MEDIUM:-0} == 1 ]]; then printf '/dev/loop0[/live]\n'; exit 0; fi
exit 1
MOCK
chmod 0755 "$mock/mountpoint" "$mock/blkid" "$mock/findmnt"

netdir="$work/net"; mkdir -p "$netdir"
export PAW_NETWORK_DIR="$netdir" PAW_MOUNTPOINT_OVERRIDE="$state"
boot_now="$(cat /proc/sys/kernel/random/boot_id)"
cat >"$state/configs/source.json" <<'JSON'
{"source_mode":"rescue","device_path":"/dev/vda","root_uuid":"11111111-2222-3333-4444-555555555555","model":"SRC","serial":"SRC1","capacity_bytes":53687091200,"composite_identity_sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","ssh_host_key_fingerprint":"SHA256:test"}
JSON
printf '{"status":"PASS","boot_id":"%s"}\n' "$boot_now" >"$netdir/source-discovery-session.json"

run_controller(){
  local name="$1" expected_status="$2" expected_id="$3" expected_hw="$4"
  set +e
  "$root/scripts/paw-live-controller.sh" >"$state/logs/$name.ctrl.out" 2>"$state/logs/$name.ctrl.err"
  local rc=$?
  set -e
  if python3 - "$state/reports/live-readiness.json" "$expected_status" "$expected_id" "$expected_hw" <<'PY'
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
exp_st,exp_id,exp_hw=sys.argv[2:]
assert d.get("status")==exp_st, d
assert d["checks"].get("target_identity")==exp_id, d
assert d["checks"].get("hardware")==exp_hw, d
PY
  then pass "$name (rc=$rc)"; else fail "$name got $(cat "$state/reports/live-readiness.json" 2>/dev/null || cat "$state/logs/$name.ctrl.err")"; fi
}

# 1) Normal serial SSD -> READY_FOR_OPERATOR
healthy_db
identity_json /dev/loop0 >"$work/id.json"
python3 - "$work/id.json" "$state/configs/target-ssd.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8")); d["approved"]=True
json.dump(d,open(sys.argv[2],"w",encoding="utf-8"),indent=2)
PY
printf '1\n1\n0\n确认\n' | "$root/scripts/paw-memtest-confirm.sh" >/dev/null 2>&1
"$root/scripts/paw-hardware-preflight.sh" /dev/loop0 >/dev/null 2>&1
run_controller 'P0-4 serial SSD READY_FOR_OPERATOR' READY_FOR_OPERATOR PASS PASS

# 2) No-serial WWN SSD -> memtest-confirm + hardware-preflight + live-controller PASS
write_db <<'JSON'
{"/dev/loop0":{"name":"loop0","model":"Samsung SSD 870","serial":"","wwn":"wwn-0x5002538e00000099","tran":"sata","capacity":240000000000,"rm":0,"parts":[]}}
JSON
mk_sysfs loop0; reset_symlinks; rm -f "$state/configs/target-ssd.json" "$state/reports/"*.json "$state/memtest-attestation.json"
printf '1\n' | "$root/scripts/paw-target-discovery.sh" >/dev/null 2>&1
printf '1\n1\n0\n确认\n' | "$root/scripts/paw-memtest-confirm.sh" >"$state/logs/noserial-wwn-memtest.log" 2>&1
"$root/scripts/paw-hardware-preflight.sh" /dev/loop0 >/dev/null 2>&1
run_controller 'P0-4 no-serial WWN SSD READY_FOR_OPERATOR' READY_FOR_OPERATOR PASS PASS
if assert_json "$state/reports/live-readiness.json" 'assert d.get("target_serial","")==""; assert d["target_identity_basis"].startswith("wwn+"); assert len(d["target_hardware_identity_sha256"])==64'; then
  pass 'P0-4 live-readiness records WWN hardware identity for no-serial SSD'
else fail 'P0-4 live-readiness WWN fields'; fi

# Verify final-confirm prompt uses 8-char hardware fingerprint when serial is empty
if grep -q 'target_hw_suffix' "$root/scripts/paw-final-confirm.sh" && grep -q '\${target_hw: -8}' "$root/scripts/paw-final-confirm.sh"; then
  pass 'P0-4 paw-final-confirm supports 8-char hardware fingerprint confirmation when serial is empty'
else fail 'P0-4 paw-final-confirm missing 8-char hardware fingerprint fallback'; fi

# 3) No-serial by-id SSD -> READY_FOR_OPERATOR
write_db <<'JSON'
{"/dev/loop0":{"name":"loop0","model":"WD Blue SN580","serial":"","wwn":"","tran":"nvme","capacity":240000000000,"rm":0,"parts":[]}}
JSON
mk_sysfs loop0; reset_symlinks; add_byid nvme-PAW-BYID-NOSERIAL loop0
rm -f "$state/configs/target-ssd.json" "$state/reports/"*.json "$state/memtest-attestation.json"
printf '1\n' | "$root/scripts/paw-target-discovery.sh" >/dev/null 2>&1
printf '1\n1\n0\n确认\n' | "$root/scripts/paw-memtest-confirm.sh" >/dev/null 2>&1
"$root/scripts/paw-hardware-preflight.sh" /dev/loop0 >/dev/null 2>&1
run_controller 'P0-4 no-serial by-id SSD READY_FOR_OPERATOR' READY_FOR_OPERATOR PASS PASS

# 4) Insufficient identity (no serial, no WWN, no by-id, no sysfs) -> BLOCKED
rm -rf "$work/sysfs/loop0"; reset_symlinks
rm -f "$state/configs/target-ssd.json" "$state/reports/"*.json "$state/memtest-attestation.json"
if printf '1\n' | "$root/scripts/paw-target-discovery.sh" >/dev/null 2>&1; then
  fail 'P0-4 insufficient identity unexpectedly allowed discovery'
else
  pass 'P0-4 insufficient identity refused during target discovery'
fi
"$root/scripts/paw-live-controller.sh" >"$state/logs/insuff.ctrl.out" 2>/dev/null || true
if assert_json "$state/reports/live-readiness.json" 'assert d["status"]=="BLOCKED" and d["checks"]["target_identity"]=="BLOCKED"'; then
  pass 'P0-4 insufficient identity BLOCKED in live-controller'
else fail 'P0-4 insufficient identity controller state'; fi
mk_sysfs loop0

# 5) Two identical-identity disks -> ambiguous BLOCKED
write_db <<'JSON'
{"/dev/loop0":{"name":"loop0","model":"Same","serial":"","wwn":"wwn-0x5002538e00000055","tran":"sata","capacity":240000000000,"rm":0,"parts":[]}}
JSON
reset_symlinks; rm -f "$state/configs/target-ssd.json" "$state/reports/"*.json "$state/memtest-attestation.json"
printf '1\n' | "$root/scripts/paw-target-discovery.sh" >/dev/null 2>&1
printf '1\n1\n0\n确认\n' | "$root/scripts/paw-memtest-confirm.sh" >/dev/null 2>&1
"$root/scripts/paw-hardware-preflight.sh" /dev/loop0 >/dev/null 2>&1
write_db <<'JSON'
{"/dev/loop0":{"name":"loop0","model":"Same","serial":"","wwn":"wwn-0x5002538e00000055","tran":"sata","capacity":240000000000,"rm":0,"parts":[]},
 "/dev/loop1":{"name":"loop1","model":"Same","serial":"","wwn":"wwn-0x5002538e00000055","tran":"sata","capacity":240000000000,"rm":0,"parts":[]}}
JSON
run_controller 'P0-4 duplicate identity disks BLOCKED' BLOCKED BLOCKED BLOCKED

# 6) Replacement disk with same capacity but different WWN after registration -> BLOCKED
write_db <<'JSON'
{"/dev/loop0":{"name":"loop0","model":"Same","serial":"","wwn":"wwn-0x5002538e00000077","tran":"sata","capacity":240000000000,"rm":0,"parts":[]}}
JSON
run_controller 'P0-4 replacement disk different WWN BLOCKED' BLOCKED BLOCKED BLOCKED

# 7) Health report WARN / FAIL -> live-controller BLOCKED
write_db <<'JSON'
{"/dev/loop0":{"name":"loop0","model":"Same","serial":"","wwn":"wwn-0x5002538e00000055","tran":"sata","capacity":240000000000,"rm":0,"parts":[]}}
JSON
PAW_MOCK_CRC=12 "$root/scripts/paw-hardware-preflight.sh" /dev/loop0 >/dev/null 2>&1 || true
run_controller 'P0-4 WARN health report BLOCKED in live-controller' BLOCKED PASS WARN
PAW_MOCK_SMART_MODE=healthfail "$root/scripts/paw-hardware-preflight.sh" /dev/loop0 >/dev/null 2>&1 || true
run_controller 'P0-4 FAIL health report BLOCKED in live-controller' BLOCKED PASS FAIL

printf 'Summary: %s passed, %s failed\n' "$passed" "$failed" >>"$report"
cat "$report"
((failed == 0))
