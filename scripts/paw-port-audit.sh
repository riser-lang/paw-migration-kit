#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/paw-lib.sh"
output="${1:-$PAW_REPORT_DIR/home-port-audit.json}"
policy="${PAW_PORT_POLICY:-$PAW_ROOT/configs/home-port-policy.json}"
ss_out="${PAW_SS_FIXTURE:-}"
tmp_ss=''
if [[ -n "$ss_out" ]]; then :; else
  need ss
  tmp_ss="$(mktemp)"; trap 'rm -f "$tmp_ss"' EXIT
  ss -ltnuH >"$tmp_ss" 2>/dev/null || true
  ss_out="$tmp_ss"
fi
python3 - "$policy" "$output" "$ss_out" <<'PY'
import datetime,json,os,sys
policy_path,out_path,ss_path=sys.argv[1:]
policy=json.load(open(policy_path,encoding="utf-8"))
allowed=policy.get("ports",{})
def cls(addr):
    a=addr.strip()
    if a.startswith("127.") or a in ("[::1]","::1","localhost"): return "loopback"
    if a.startswith("100.") or "%tailscale" in a: return "tailnet"
    if a.startswith("10.") or a.startswith("192.168.") or a.startswith("172.16.") or a.startswith("172.17.") or a.startswith("172.18.") or a.startswith("172.19.") or a.startswith("172.2") or a.startswith("172.30.") or a.startswith("172.31."): return "lan"
    if a in ("0.0.0.0","*","[::]","::"): return "public"
    return "other"
rows=[]
for line in open(ss_path,encoding="utf-8"):
    parts=line.split()
    if len(parts)<5: continue
    proto,state,local=parts[0],parts[1],parts[4]
    if ":" not in local: continue
    host,port=local.rsplit(":",1)
    host=host.strip("[]")
    c=cls(host)
    p=allowed.get(port)
    action="UNKNOWN"
    public=False
    if p:
        binds=p.get("bind",[])
        if c=="public": public=True
        action="ALLOW" if (c in binds or "outbound" in binds and c=="outbound") else "REVIEW"
        if c=="public" and p.get("listen_wildcard_allowed") and proto=="udp": action="ALLOW_WILDCARD"
        elif c=="public" and not p.get("public",False): action="VIOLATION_PUBLIC"
    elif c=="public":
        action="VIOLATION_UNKNOWN_PUBLIC"
    rows.append({"proto":proto,"state":state,"local":local,"host":host,"port":port,
                 "class":c,"policy":p,"action":action,"public_bind":public})
viol=[r for r in rows if r["action"].startswith("VIOLATION")]
doc={"schema":"paw.home-port-audit.v1","status":"FAIL" if viol else "PASS",
 "default_no_public_ipv4":policy.get("default_no_public_ipv4"),
 "default_no_router_port_forward":policy.get("default_no_router_port_forward"),
 "rows":rows,"violations":viol,
 "notes":["Loopback is not reachable from LAN/Tailnet.","Tailscale Funnel ingress is public but does not create a home public bind or port-forward requirement.","This audit never changes firewall or listener state."],
 "generated_at":datetime.datetime.now(datetime.timezone.utc).isoformat()}
tmp=out_path+".tmp"
with open(tmp,"w",encoding="utf-8") as h: json.dump(doc,h,indent=2,ensure_ascii=False)
os.chmod(tmp,0o600); os.replace(tmp,out_path)
print(json.dumps({"status":doc["status"],"listeners":len(rows),"violations":len(viol)},separators=(",",":")))
raise SystemExit(0 if not viol else 2)
PY
