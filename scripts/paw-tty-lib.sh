#!/usr/bin/env bash
# PAW interactive terminal helper.
#
# Production default is /dev/tty1: the physical display and keyboard on the
# target ASUS machine.  All prompt output and all input go through one fd on
# that exact terminal; serial console output remains on journal/stderr only.
# PAW_INTERACTIVE_TTY exists so the QEMU and pty tests can substitute a
# terminal without changing production behaviour; it is never set by the ISO.
set -Eeuo pipefail

PAW_TTY_DEV="${PAW_INTERACTIVE_TTY:-/dev/tty1}"
PAW_TTY_TIMEOUT="${PAW_INPUT_TIMEOUT:-300}"
PAW_TTY_SESSION_NAME="${PAW_TTY_SESSION_NAME:-}"
PAW_TTY_SESSION_FILE="${PAW_TTY_SESSION_FILE:-}"
PAW_TTY_OPEN=0
PAW_TTY_READ_RC=0
PAW_TTY_IN_FD=3
PAW_TTY_FALLBACK=0

paw_tty_open(){
  [[ "$PAW_TTY_TIMEOUT" =~ ^[0-9]+$ ]] && ((PAW_TTY_TIMEOUT >= 1 && PAW_TTY_TIMEOUT <= 3600)) || {
    log ERROR "PAW_INPUT_TIMEOUT 必须是 1-3600 秒的整数."; return 1;
  }
  PAW_TTY_SESSION_NAME="${PAW_TTY_SESSION_NAME:-tty-session}"
  if [[ -z "$PAW_TTY_SESSION_FILE" ]]; then
    PAW_TTY_SESSION_FILE="$PAW_REPORT_DIR/$PAW_TTY_SESSION_NAME.json"
  fi
  [[ -c "$PAW_TTY_DEV" ]] || { log ERROR "交互终端不是字符设备:$PAW_TTY_DEV"; return 1; }
  exec 3<>"$PAW_TTY_DEV" || { log ERROR "无法打开交互终端:$PAW_TTY_DEV"; return 1; }
  PAW_TTY_RESOLVED="$(readlink -f "/proc/$$/fd/3" 2>/dev/null || true)"
  local expected; expected="$(readlink -f "$PAW_TTY_DEV" 2>/dev/null || true)"
  if [[ -z "$PAW_TTY_RESOLVED" || "$PAW_TTY_RESOLVED" != "$expected" ]]; then
    log ERROR "交互终端解析失败:fd3=$PAW_TTY_RESOLVED expected=$expected"
    exec 3>&-
    return 1
  fi
  PAW_TTY_RDEV="$(stat -Lc '%t:%T' "$PAW_TTY_RESOLVED" 2>/dev/null || echo unknown)"
  PAW_TTY_OPEN=1
  PAW_TTY_IN_FD=3
  PAW_TTY_MARKERS=()
  mkdir -p "$(dirname "$PAW_TTY_SESSION_FILE")"
  paw_tty_record init init 'terminal opened'
  return 0
}

# Bind /dev/tty1 when the machine really has a console.  CI runners, pty
# harnesses and any caller without a character device fall back to the
# inherited stdin/stdout so the operator code path stays testable.  A fallback
# is logged, is never recorded as a real tty1 session, and must not be reported
# as hardware console evidence.
paw_tty_open_optional(){
  # An explicit override (QEMU/pty harness) always uses the given terminal.
  if [[ -n "${PAW_INTERACTIVE_TTY:-}" ]]; then
    paw_tty_open
    return $?
  fi
  # Real console: the unit provides a character device and at least one of the
  # inherited streams is that terminal.  Automation that pipes stdin/stdout
  # keeps reading the pipe instead of stealing the physical console.
  if [[ -c "$PAW_TTY_DEV" ]] && { [[ -t 0 ]] || [[ -t 1 ]] || [[ -t 2 ]]; }; then
    paw_tty_open
    return $?
  fi
  PAW_TTY_FALLBACK=1
  PAW_TTY_IN_FD=0
  PAW_TTY_OPEN=1
  PAW_TTY_RESOLVED='(inherited stdin/stdout)'
  PAW_TTY_RDEV='fallback'
  exec 3>&1
  log WARN "交互终端 $PAW_TTY_DEV 不可用或输入被重定向;使用继承的 stdin/stdout(这不是实机 tty1 路径)."
  return 0
}

paw_tty_holders_json(){
  python3 - "$PAW_TTY_RESOLVED" "$$" <<'PY'
import glob,json,os,sys
target=sys.argv[1]; root=int(sys.argv[2])

def parent_of(pid):
    try:
        with open(f"/proc/{pid}/stat",encoding="utf-8") as handle:
            fields=handle.read().rsplit(")",1)[1].split()
        return int(fields[1])
    except (OSError,IndexError,ValueError):
        return 0

def is_helper(pid):
    # Command substitutions and pipeline children inherit fd 3.  They are
    # transient helpers of the interactive shell, not competing terminal
    # owners, so exclude descendants of the shell but keep unrelated units.
    seen=set(); current=pid
    while current>1 and current not in seen:
        seen.add(current)
        current=parent_of(current)
        if current==root:
            return pid!=root
    return False

seen=set(); holders=[]
for entry in glob.glob("/proc/[0-9]*"):
    pid=int(entry.rsplit("/",1)[1])
    if is_helper(pid):
        continue
    try:
        fds=os.listdir(entry+"/fd")
    except OSError:
        continue
    for fd in fds:
        try:
            link=os.readlink(f"{entry}/fd/{fd}")
        except OSError:
            continue
        if link==target and pid not in seen:
            seen.add(pid)
            try:
                comm=open(entry+"/comm",encoding="utf-8").read().strip()
            except OSError:
                comm="?"
            holders.append({"pid":pid,"comm":comm})
print(json.dumps(sorted(holders,key=lambda x:x["pid"]),ensure_ascii=False))
PY
}

paw_tty_record(){
  local phase="$1" event="$2" detail="${3:-}" marker="${4:-}"
  # A fallback binding is not a tty1 session; recording it would misrepresent
  # CI captures as hardware console evidence.
  ((PAW_TTY_FALLBACK == 0)) || return 0
  local holders; holders="$(paw_tty_holders_json)"
  python3 - "$PAW_TTY_SESSION_FILE" "$PAW_TTY_SESSION_NAME" "$PAW_TTY_DEV" \
    "$PAW_TTY_RESOLVED" "$PAW_TTY_RDEV" "$PAW_TTY_TIMEOUT" "$phase" "$event" "$detail" "$marker" "$holders" <<'PY' | python3 "$PAW_ROOT/scripts/paw-atomic-write.py" "$PAW_TTY_SESSION_FILE"
import datetime,json,os,sys
(path,session,configured,resolved,rdev,timeout,phase,event,detail,marker,holders)=sys.argv[1:]
now=datetime.datetime.now(datetime.timezone.utc).isoformat()
if os.path.exists(path):
    with open(path,encoding="utf-8") as handle:
        document=json.load(handle)
else:
    document={"schema":"paw.tty-session.v1","session":session,"configured_path":configured,
              "tty_path":resolved,"tty_resolved":resolved,"tty_rdev":rdev,
              "is_character_device":True,"timeout_seconds":int(timeout),
              "started_at":now,"events":[],"markers":[],"max_holders":0,
              "menu_tty":None,"input_tty":None}
document["tty_path"]=resolved
document["updated_at"]=now
if phase=="menu":
    document["menu_tty"]=resolved
if phase=="serial-input":
    document["input_tty"]=resolved
parsed=json.loads(holders)
if marker:
    document["markers"].append(marker)
document["events"].append({"at":now,"phase":phase,"event":event,"detail":detail,
                           "holders":parsed,"holder_count":len(parsed)})
document["max_holders"]=max(document.get("max_holders",0),len(parsed))
sys.stdout.write(json.dumps(document,ensure_ascii=False,indent=2)+"\n")
PY
}

paw_tty_say(){ printf '%s\n' "$*" >&3; }
paw_tty_prompt(){ printf '%s' "$*" >&3; }
paw_tty_clear(){ printf '\033[2J\033[H' >&3; }

paw_tty_marker(){
  local marker="$1"
  printf '[%s]\n' "$marker" >&3
  paw_tty_record marker shown "$marker" "$marker"
}

paw_tty_read(){
  local __var="$1"
  PAW_TTY_READ_RC=0
  # The `||` form keeps errexit from terminating the caller before it can
  # distinguish a 300s safety timeout from an accepted value.
  IFS= read -r -t "$PAW_TTY_TIMEOUT" -u "$PAW_TTY_IN_FD" "$__var" || PAW_TTY_READ_RC=$?
  ((PAW_TTY_READ_RC == 0))
}

paw_tty_read_line(){
  local __var="$1"
  PAW_TTY_READ_RC=0
  IFS= read -r -u "$PAW_TTY_IN_FD" "$__var" || PAW_TTY_READ_RC=$?
  ((PAW_TTY_READ_RC == 0))
}

# Read a value that must not be echoed on the console (e.g. the expected
# Rescue root UUID).  Same fd and same timeout as every other prompt.
paw_tty_read_secret(){
  local __var="$1"
  PAW_TTY_READ_RC=0
  IFS= read -r -s -t "$PAW_TTY_TIMEOUT" -u "$PAW_TTY_IN_FD" "$__var" || PAW_TTY_READ_RC=$?
  printf '\n' >&3
  ((PAW_TTY_READ_RC == 0))
}

paw_tty_close(){
  if ((PAW_TTY_OPEN == 1)); then
    paw_tty_record close closed 'terminal released'
    exec 3>&-
    PAW_TTY_OPEN=0
  fi
}

# Confirm the last six characters of the media serial on the same tty fd used
# by the Chinese panel.  Return 0=accepted, 1=mismatch, 2=timeout/aborted.
paw_tty_confirm_serial_suffix(){
  local serial="$1" confirm='' rc=0
  paw_tty_marker PAW-TTY1-PROMPT
  paw_tty_record serial-input prompt 'serial suffix requested on the same tty'
  paw_tty_say 'Enter the last 6 characters of the media serial.'
  paw_tty_prompt '请输入该设备序列号最后 6 位以继续:'
  paw_tty_read confirm
  rc="$PAW_TTY_READ_RC"
  if ((rc > 128)); then
    paw_tty_marker PAW-TTY1-INPUT-TIMEOUT
    paw_tty_record serial-input timeout "no input within ${PAW_TTY_TIMEOUT}s"
    paw_tty_say ''
    paw_tty_say "错误:等待输入超过 ${PAW_TTY_TIMEOUT} 秒,已安全停止,没有写入任何分区."
    log WARN "PAWDATA serial confirmation timed out after ${PAW_TTY_TIMEOUT}s; nothing was written."
    return 2
  elif ((rc != 0)); then
    paw_tty_marker PAW-TTY1-INPUT-ABORTED
    paw_tty_record serial-input aborted 'input stream closed before confirmation'
    paw_tty_say ''
    paw_tty_say '错误:未收到完整输入,已安全停止,没有写入任何分区.'
    log WARN 'PAWDATA serial confirmation was aborted; nothing was written.'
    return 2
  fi
  if [[ ${#serial} -lt 6 || "$confirm" != "${serial: -6}" ]]; then
    paw_tty_marker PAW-TTY1-INPUT-BAD
    paw_tty_record serial-input rejected 'serial suffix mismatch'
    paw_tty_say ''
    paw_tty_say '错误:序列号末六位不匹配,已安全停止,没有写入任何分区.'
    log WARN 'PAWDATA serial suffix mismatched; nothing was written.'
    return 1
  fi
  paw_tty_marker PAW-TTY1-INPUT-OK
  paw_tty_record serial-input accepted 'serial suffix matched on tty1'
  paw_tty_say ''
  paw_tty_say '输入已确认;开始追加 PAWDATA 分区(仅新分区会被格式化).'
  return 0
}
