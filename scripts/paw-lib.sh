#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
PAW_ROOT="${PAW_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
if [[ -z ${PAW_STATE_DIR:-} ]]; then
  if command -v mountpoint >/dev/null 2>&1 && mountpoint -q /var/lib/paw-migration; then PAW_STATE_DIR=/var/lib/paw-migration; else PAW_STATE_DIR=/run/paw-migration; fi
fi
PAW_LOG_DIR="${PAW_LOG_DIR:-$PAW_STATE_DIR/logs}"
PAW_CONFIG_DIR="${PAW_CONFIG_DIR:-$PAW_STATE_DIR/configs}"
PAW_REPORT_DIR="${PAW_REPORT_DIR:-$PAW_STATE_DIR/reports}"
mkdir -p "$PAW_LOG_DIR" "$PAW_REPORT_DIR"
PAW_LOG="${PAW_LOG:-$PAW_LOG_DIR/$(date -u +%Y%m%dT%H%M%SZ)-${0##*/}.log}"
log(){ printf '%s [%s] %s\n' "$(date -u +%FT%TZ)" "$1" "$2" | tee -a "$PAW_LOG" >&2; }
die(){ log ERROR "$*"; exit 1; }
need(){ command -v "$1" >/dev/null 2>&1 || die "Required command missing: $1"; }
json_escape(){ sed 's/\\/\\\\/g; s/"/\\"/g; s/\r//g' <<<"$1" | tr -d '\n'; }
write_status(){ local status="$1" reason="$2" dest="${3:-$PAW_REPORT_DIR/paw-hardware-health-report.json}"; mkdir -p "$(dirname "$dest")"; printf '{\n  "schema": "paw.hardware-health.v1",\n  "status": "%s",\n  "reason": "%s",\n  "generated_at": "%s",\n  "host": "%s"\n}\n' "$status" "$(json_escape "$reason")" "$(date -u +%FT%TZ)" "$(json_escape "$(hostname)")" >"$dest"; }
require_target_enrollment(){
  [[ -r "$PAW_CONFIG_DIR/target-ssd.json" ]] || die 'No target SSD enrollment: read-only mode only.'
  grep -q '"approved": true' "$PAW_CONFIG_DIR/target-ssd.json" || die 'Target SSD enrollment is not approved.'
}
require_sim_or_enrollment(){
  [[ ${PAW_SIMULATION:-0} == 1 ]] && return 0
  require_target_enrollment
  [[ ${PAW_DESTRUCTIVE_ARM:-} == 'I_HAVE_VERIFIED_THE_TARGET_SERIAL' ]] || die 'Destructive operation not armed.'
  [[ -r "$PAW_REPORT_DIR/operator-authorization.json" ]] || die 'Fresh operator authorization receipt is missing.'
  python3 - "$PAW_REPORT_DIR/operator-authorization.json" <<'PY'
import datetime,json,sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
if d.get("status")!="AUTHORIZED": raise SystemExit("authorization is not active")
expiry=datetime.datetime.fromisoformat(d.get("expires_at",""))
if expiry.tzinfo is None or expiry <= datetime.datetime.now(datetime.timezone.utc): raise SystemExit("authorization expired")
PY
  [[ -r "$PAW_CONFIG_DIR/source.json" ]] || die 'No source enrollment.'
  grep -q '"source_mode": "rescue"' "$PAW_CONFIG_DIR/source.json" || die 'Source must be Rescue Mode.'
  [[ -r "$PAW_REPORT_DIR/paw-hardware-health-report.json" ]] || die 'Hardware health report missing.'
  grep -q '"status"[[:space:]]*:[[:space:]]*"PASS"' "$PAW_REPORT_DIR/paw-hardware-health-report.json" || die 'Hardware health report is not PASS.'
}
assert_authorization_for_target(){
  local dev="$1" parent serial expected
  parent="$(parent_disk "$dev")"
  serial="$(lsblk -dn -o SERIAL "$parent" | xargs)"
  expected="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("device_path", ""))' "$PAW_CONFIG_DIR/target-ssd.json")"
  python3 - "$PAW_REPORT_DIR/operator-authorization.json" "$serial" "$parent" "$expected" <<'PY'
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
if d.get("status")!="AUTHORIZED" or d.get("target_serial")!=sys.argv[2] or d.get("target_device")!=sys.argv[3] or sys.argv[3]!=sys.argv[4]:
    raise SystemExit("authorization does not match the current target")
PY
}
parent_disk(){ local p; p="$(lsblk -dn -o PKNAME "$1" | xargs)"; [[ -n "$p" ]] && printf '/dev/%s\n' "$p" || printf '%s\n' "$1"; }
assert_sim_files(){
  local root src dst; root="$(realpath -e "$PAW_ROOT/tests/virtual" 2>/dev/null || true)"
  src="$(realpath -e "$1" 2>/dev/null || true)"; dst="$(realpath -e "$2" 2>/dev/null || true)"
  [[ -n "$root" && "$src" == "$root"/* && "$dst" == "$root"/* ]] || die 'Simulation files must both be under tests/virtual.'
}
assert_sim_loop_device(){
  local dev="$1" parent backing root
  [[ -b "$dev" ]] || die 'Simulation device must be block-special.'
  parent="$(parent_disk "$dev")"; [[ "$(lsblk -dn -o TYPE "$parent" | xargs)" == loop ]] || die 'Simulation accepts only loop devices.'
  need losetup; backing="$(losetup -n -O BACK-FILE "$parent" | head -n1)"; root="$(realpath -e "$PAW_ROOT/tests/virtual" 2>/dev/null || true)"
  [[ -n "$root" && -n "$backing" && "$(realpath -e "$backing" 2>/dev/null || true)" == "$root"/* ]] || die 'Loop backing file must be inside tests/virtual.'
}
assert_registered_target_device(){
  local dev="$1" expected actual parent
  expected="$(sed -n 's/.*"serial"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$PAW_CONFIG_DIR/target-ssd.json")"
  parent="$(parent_disk "$dev")"; actual="$(lsblk -dn -o SERIAL "$parent" | xargs)"
  [[ -n "$expected" && "$actual" == "$expected" ]] || die 'Registered target serial mismatch.'
}
rescue_ssh(){
  local host port user identity known endpoint
  endpoint=/run/paw-network/rescue-endpoint.json
  [[ -r "$endpoint" ]] || die 'RAM-only Rescue Mode endpoint is not configured.'
  read -r host port < <(python3 - "$endpoint" <<'PY'
import json,re,sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
h=str(d.get("host", "")); p=str(d.get("port", ""))
if not re.fullmatch(r"[A-Za-z0-9.-]+",h) or not p.isdecimal() or not 1 <= int(p) <= 65535:
    raise SystemExit("invalid Rescue Mode endpoint")
print(h,p)
PY
  ) || die 'Rescue SSH endpoint config is malformed.'
  user=root; identity=/run/paw-network/rescue_ed25519; known=/run/paw-network/known_hosts
  [[ "$host" =~ ^[A-Za-z0-9.-]+$ && "$port" =~ ^[0-9]{1,5}$ ]] || die 'Rescue SSH endpoint config is incomplete.'
  ((port > 0 && port < 65536)) || die 'Invalid Rescue SSH port.'
  [[ "$identity" == /run/paw-network/* && -r "$identity" && "$(stat -c %u "$identity")" == 0 && ( "$(stat -c %a "$identity")" == 600 || "$(stat -c %a "$identity")" == 400 ) ]] || die 'Rescue key must be a root-only RAM file.'
  [[ "$known" == /run/paw-network/* && -s "$known" ]] || die 'Pinned Rescue Mode host key missing.'
  need ssh
  ssh -T -i "$identity" -p "$port" -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$known" -o ConnectTimeout=12 -o ServerAliveInterval=15 -o ServerAliveCountMax=3 "$user@$host" "$@"
}
assert_unmounted(){ local m; command -v lsblk >/dev/null 2>&1 || return 0; m="$(lsblk -nrpo MOUNTPOINT "$1" | sed '/^$/d')"; [[ -z "$m" ]] || die "Device has mounted filesystem(s): $1 $m"; }
mark_incomplete(){ printf 'INCOMPLETE %s\n' "$(date -u +%FT%TZ)" >"$PAW_REPORT_DIR/CLONE-INCOMPLETE"; }
trap 'rc=$?; if ((rc != 0)); then log ERROR "exit=$rc"; fi' EXIT
