#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/paw-lib.sh"
out="$PAW_REPORT_DIR/memory-test.json"
evidence="${PAW_MEMTEST_ATTESTATION:-$PAW_STATE_DIR/memtest-attestation.json}"

# Only an operator attestation produced by paw-memtest-confirm.sh in this PAW
# Live session is accepted. A plain text transcript is never accepted as proof.
if [[ ! -s "$evidence" ]]; then
  python3 - "$out" <<'PY'
import datetime,json,os,sys,tempfile
path=sys.argv[1]
data={"schema":"paw.memory-test.v1","status":"WARN","method":"none",
 "reason":"Memtest86+ 尚未完成人工确认；普通文本日志不能作为可信证据。",
 "trust_level":"unverified","generated_at":datetime.datetime.now(datetime.timezone.utc).isoformat()}
tmp=path+".tmp"
with open(tmp,"w",encoding="utf-8") as handle: json.dump(data,handle,indent=2,ensure_ascii=False)
os.chmod(tmp,0o600); os.replace(tmp,path)
PY
  log WARN 'Memtest result is WARN; operator confirmation has not been recorded.'
  exit 2
fi

set +e
python3 - "$evidence" "$out" "$PAW_CONFIG_DIR/target-ssd.json" /proc/sys/kernel/random/boot_id <<'PY'
import datetime,hashlib,json,os,sys,tempfile
evidence,out,target_cfg,boot_path=sys.argv[1:]
raw=open(evidence,"rb").read()
try:
    d=json.loads(raw.decode("utf-8"))
except Exception:
    raise SystemExit("attestation is not valid JSON")
def fail(reason,status="WARN"):
    data={"schema":"paw.memory-test.v1","status":status,"method":"manual_operator_observation",
      "reason":reason,"trust_level":"unverified","attestation_sha256":hashlib.sha256(raw).hexdigest(),
      "generated_at":datetime.datetime.now(datetime.timezone.utc).isoformat()}
    tmp=out+".tmp"
    with open(tmp,"w",encoding="utf-8") as handle: json.dump(data,handle,indent=2,ensure_ascii=False)
    os.chmod(tmp,0o600); os.replace(tmp,out)
    raise SystemExit(1 if status=="FAIL" else 2)
if d.get("schema")!="paw.memtest-attestation.v1": fail("attestation schema mismatch")
if d.get("method")!="manual_operator_observation": fail("attestation method is not an operator observation")
if d.get("trust_level")!="operator_attestation_not_cryptographic": fail("attestation trust level is invalid")
status=d.get("status")
if status not in ("OPERATOR_CONFIRMED","FAIL","WARN"):
    fail("attestation status is not recognized")
boot=open(boot_path,encoding="ascii").read().strip()
if d.get("boot_id")!=boot: fail("attestation was recorded in a different Live boot; re-run the confirmation")
try:
    target=json.load(open(target_cfg,encoding="utf-8"))
except Exception:
    fail("target SSD enrollment is missing")
if d.get("target_serial")!=target.get("serial") or d.get("target_device")!=target.get("device_path"):
    fail("attestation target does not match the currently enrolled SSD")
if status=="FAIL":
    fail("Memtest86+ operator-confirmed error count is nonzero", "FAIL")
if status=="WARN":
    fail("Memtest86+ completion was not confirmed by the operator", "WARN")
if not isinstance(d.get("completed_passes"),int) or d["completed_passes"]<1:
    fail("completed passes are missing or less than 1")
if d.get("error_count")!=0:
    fail("error_count must be 0 for OPERATOR_CONFIRMED", "FAIL")
data={"schema":"paw.memory-test.v1","status":"OPERATOR_CONFIRMED",
 "method":"manual_operator_observation",
 "trust_level":"operator_attestation_not_cryptographic",
 "completed_passes":d["completed_passes"],"error_count":0,
 "target_serial":d["target_serial"],"target_device":d["target_device"],
 "boot_id":boot,"attestation_sha256":hashlib.sha256(raw).hexdigest(),
 "recorded_at":d.get("recorded_at"),
 "limits":"operator observation; not a cryptographic or machine-verified memory test",
 "generated_at":datetime.datetime.now(datetime.timezone.utc).isoformat()}
tmp=out+".tmp"
with open(tmp,"w",encoding="utf-8") as handle: json.dump(data,handle,indent=2,ensure_ascii=False)
os.chmod(tmp,0o600); os.replace(tmp,out)
PY
rc=$?
set -e
if ((rc != 0)); then
  log WARN 'Memtest result is not acceptable for cloning; no PASS was fabricated.'
  exit "$rc"
fi
log INFO 'Memtest operator attestation accepted as OPERATOR_CONFIRMED; clone gate may use it.'
