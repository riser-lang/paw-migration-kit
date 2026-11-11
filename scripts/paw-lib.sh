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
require_console_font_pass(){
  # A same-boot PASS report for the primary 16x16 font on a bound fbcon is the
  # only state that may open a destructive write.  WARN/BLOCKED/missing reports
  # remain read-only.  Simulation uses explicit loop-backed fixtures and is
  # gated separately by assert_sim_loop_device.
  [[ ${PAW_SIMULATION:-0} == 1 ]] && return 0
  local report manifest expected_font expected_tty boot_id
  report="${PAW_FONT_GATE_REPORT:-$PAW_REPORT_DIR/console-font.json}"
  manifest="${PAW_FONT_MANIFEST:-$PAW_ROOT/fonts/paw-cjk-font.json}"
  expected_font="${PAW_CONSOLE_FONT_PATH:-$PAW_ROOT/fonts/paw-cjk-16x16.psf}"
  expected_tty="${PAW_INTERACTIVE_TTY:-/dev/tty1}"
  boot_id="$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || true)"
  need python3
  python3 "$PAW_ROOT/scripts/paw-font-gate.py" \
    --report "$report" \
    --manifest "$manifest" \
    --expected-font "$expected_font" \
    --expected-tty "$expected_tty" \
    --boot-id "$boot_id" \
    || die '控制台字体安全门禁未通过：只有本次启动的 fbcon 16x16 中文字体 PASS 才允许磁盘写入；只读诊断仍可用。'
}
require_sim_or_enrollment(){
  [[ ${PAW_SIMULATION:-0} == 1 ]] && return 0
  require_console_font_pass
  require_target_enrollment
  [[ ${PAW_DESTRUCTIVE_ARM:-} == 'I_HAVE_VERIFIED_THE_TARGET_SERIAL' ]] || die 'Destructive operation not armed.'
  [[ -r "$PAW_REPORT_DIR/operator-authorization.json" ]] || die 'Fresh operator authorization receipt is missing.'
  # Expiry is enforced by assert_transaction_stage at the clone-start edge,
  # not here: a clone that has already started must survive the six-hour
  # authorization window through verify/repair/expand.
  python3 - "$PAW_REPORT_DIR/operator-authorization.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
if d.get("status") not in ("AUTHORIZED","CONSUMED"):
    raise SystemExit("authorization is not active")
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
if d.get("status") not in ("AUTHORIZED","CONSUMED") or d.get("target_serial")!=sys.argv[2] or d.get("target_device")!=sys.argv[3] or sys.argv[3]!=sys.argv[4]:
    raise SystemExit("authorization does not match the current target")
PY
}
transaction_path(){ printf '%s\n' "${PAW_TRANSACTION_FILE:-$PAW_REPORT_DIR/migration-transaction.json}"; }
assert_transaction_stage(){
  local stage="$1" tx
  tx="$(transaction_path)"
  [[ -r "$tx" && -r "$PAW_CONFIG_DIR/source.json" && -r "$PAW_CONFIG_DIR/target-ssd.json" && -r "$PAW_REPORT_DIR/operator-authorization.json" ]] \
    || die "迁移事务状态不完整，拒绝进入 $stage 阶段。"
  python3 "$PAW_ROOT/scripts/paw-transaction.py" assert \
    --transaction "$tx" \
    --authorization "$PAW_REPORT_DIR/operator-authorization.json" \
    --source-config "$PAW_CONFIG_DIR/source.json" \
    --target-config "$PAW_CONFIG_DIR/target-ssd.json" \
    --stream-verify "$PAW_REPORT_DIR/stream-verify.json" \
    --stage "$stage" \
    || die "迁移事务状态机拒绝进入 $stage 阶段。"
}
transaction_event(){
  local event="$1" tx; shift
  tx="$(transaction_path)"
  python3 "$PAW_ROOT/scripts/paw-transaction.py" event --transaction "$tx" --event "$event" "$@" \
    || die "迁移事务无法记录事件 $event。"
}
transaction_init(){
  python3 "$PAW_ROOT/scripts/paw-transaction.py" init \
    --transaction "$(transaction_path)" \
    --authorization "$PAW_REPORT_DIR/operator-authorization.json" \
    --source-config "$PAW_CONFIG_DIR/source.json" \
    --target-config "$PAW_CONFIG_DIR/target-ssd.json" || die '无法创建迁移事务。'
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
  ssh -T -i "$identity" -p "$port" -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$known" -o HostKeyAlgorithms=ssh-ed25519 -o ConnectTimeout=12 -o ServerAliveInterval=15 -o ServerAliveCountMax=3 "$user@$host" "$@"
}
assert_unmounted(){ local m; command -v lsblk >/dev/null 2>&1 || return 0; m="$(lsblk -nrpo MOUNTPOINT "$1" | sed '/^$/d')"; [[ -z "$m" ]] || die "Device has mounted filesystem(s): $1 $m"; }
mark_incomplete(){ printf 'INCOMPLETE %s\n' "$(date -u +%FT%TZ)" >"$PAW_REPORT_DIR/CLONE-INCOMPLETE"; }
trap 'rc=$?; if ((rc != 0)); then log ERROR "exit=$rc"; fi' EXIT
