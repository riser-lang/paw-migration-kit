#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/paw-lib.sh"
need ssh-keygen; need ssh-keyscan; need ssh; need python3
runtime=/run/paw-network
install -d -m 0700 "$runtime"
[[ "$(findmnt -n -o FSTYPE --target /run 2>/dev/null || true)" == tmpfs ]] || die '/run is not a tmpfs; refusing to store the Rescue Mode private key.'
# The one-time public key and the host-key fingerprint must be readable on the
# physical console; paw-console.service sends stdout to the journal only.
# shellcheck source=scripts/paw-tty-lib.sh
source "$PAW_ROOT/scripts/paw-tty-lib.sh"
export PAW_TTY_SESSION_NAME=rescue-key
paw_tty_open_optional || die '无法打开交互终端；未生成任何 Rescue 凭据。'
paw_tty_clear
paw_tty_marker PAW-TTY1-RESCUE-PANEL
paw_tty_say 'PAW Rescue SSH 一次性凭据准备'
paw_tty_prompt '输入 Tencent Rescue VNC 中显示的公网主机名或 IPv4（不会写入日志）：'
host=''
if ! paw_tty_read host; then
  paw_tty_marker PAW-TTY1-RESCUE-TIMEOUT
  paw_tty_close
  die 'Rescue 主机名输入超时或中断；未生成任何凭据。'
fi
paw_tty_prompt '输入 Rescue SSH 端口 [22]：'
port=''
if ! paw_tty_read port; then
  paw_tty_marker PAW-TTY1-RESCUE-TIMEOUT
  paw_tty_close
  die 'Rescue 端口输入超时或中断；未生成任何凭据。'
fi
port="${port:-22}"
if ! [[ "$host" =~ ^[A-Za-z0-9.-]+$ && "$port" =~ ^[0-9]{1,5}$ ]]; then
  paw_tty_marker PAW-TTY1-RESCUE-BAD
  paw_tty_say '错误：主机名或端口格式不正确。'
  paw_tty_close
  die '主机名或端口格式不正确。'
fi
((port > 0 && port < 65536)) || { paw_tty_close; die 'SSH 端口超出有效范围。'; }
python3 - "$runtime/rescue-endpoint.json" "$host" "$port" <<'PY'
import json,os,sys
path,host,port=sys.argv[1:]
tmp=path+".tmp"
with open(tmp,"w",encoding="utf-8") as handle:
    json.dump({"host":host,"port":int(port)},handle)
    handle.write("\n")
os.chmod(tmp,0o600)
os.replace(tmp,path)
PY
unset host port

key="$runtime/rescue_ed25519"
if [[ -e "$key" || -e "$key.pub" ]]; then die 'A Rescue Mode key already exists in RAM; reboot or remove it through the migration UI before generating another.'; fi
ssh-keygen -q -t ed25519 -N '' -C paw-rescue-one-time -f "$key"
chmod 0600 "$key"; chmod 0644 "$key.pub"
paw_tty_say ''
paw_tty_say '将以下一次性公钥添加到 Rescue Mode 的临时 authorized_keys：'
while IFS= read -r line; do paw_tty_say "$line"; done <"$key.pub"

candidate="$runtime/known_hosts.candidate"
read -r scan_host scan_port < <(python3 - "$runtime/rescue-endpoint.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8")); print(d["host"],d["port"])
PY
)
ssh-keyscan -T 8 -p "$scan_port" -t ed25519 "$scan_host" 2>/dev/null >"$candidate"
[[ -s "$candidate" ]] || die 'Could not obtain a Rescue Mode SSH host-key candidate.'
fingerprint="$(ssh-keygen -lf "$candidate" -E sha256 | awk 'NR==1 {print $2}')"
paw_tty_say ''
paw_tty_say '在 Tencent VNC 中核对 SSH 主机指纹；不要只相信 ssh-keyscan 返回值。'
paw_tty_say "候选 SHA256 指纹：$fingerprint"
paw_tty_marker PAW-TTY1-RESCUE-PROMPT
paw_tty_prompt '请把 VNC 显示的完整 SHA256 指纹粘贴到这里：'
confirmed=''
if ! paw_tty_read confirmed; then
  paw_tty_marker PAW-TTY1-RESCUE-TIMEOUT
  paw_tty_say '错误：指纹核对输入超时或中断；拒绝连接。'
  paw_tty_close
  die '指纹核对输入超时或中断；拒绝连接。'
fi
if [[ "$confirmed" != "$fingerprint" ]]; then
  paw_tty_marker PAW-TTY1-RESCUE-BAD
  paw_tty_say '错误：主机指纹不匹配；拒绝连接。'
  paw_tty_close
  die '主机指纹不匹配；拒绝连接。'
fi
paw_tty_marker PAW-TTY1-RESCUE-OK
paw_tty_say '主机指纹已核对通过；Rescue SSH 端点已固定。'
paw_tty_close
mv "$candidate" "$runtime/known_hosts"
chmod 0600 "$runtime/known_hosts"
unset confirmed fingerprint scan_host scan_port
log INFO 'Rescue SSH key and endpoint are RAM-only; host key was explicitly pinned.'
