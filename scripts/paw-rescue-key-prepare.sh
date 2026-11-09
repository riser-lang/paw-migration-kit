#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/paw-lib.sh"
need ssh-keygen; need ssh-keyscan; need ssh; need python3
runtime=/run/paw-network
install -d -m 0700 "$runtime"
[[ "$(findmnt -n -o FSTYPE --target /run 2>/dev/null || true)" == tmpfs ]] || die '/run is not a tmpfs; refusing to store the Rescue Mode private key.'
read -r -p '输入 Tencent Rescue VNC 中显示的公网主机名或 IPv4（不会写入日志）：' host
read -r -p '输入 Rescue SSH 端口 [22]：' port
port="${port:-22}"
[[ "$host" =~ ^[A-Za-z0-9.-]+$ && "$port" =~ ^[0-9]{1,5}$ ]] || die '主机名或端口格式不正确。'
((port > 0 && port < 65536)) || die 'SSH 端口超出有效范围。'
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
printf '\n%s\n' '将以下一次性公钥添加到 Rescue Mode 的临时 authorized_keys：'
cat "$key.pub"

candidate="$runtime/known_hosts.candidate"
read -r scan_host scan_port < <(python3 - "$runtime/rescue-endpoint.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8")); print(d["host"],d["port"])
PY
)
ssh-keyscan -T 8 -p "$scan_port" -t ed25519 "$scan_host" 2>/dev/null >"$candidate"
[[ -s "$candidate" ]] || die 'Could not obtain a Rescue Mode SSH host-key candidate.'
fingerprint="$(ssh-keygen -lf "$candidate" -E sha256 | awk 'NR==1 {print $2}')"
printf '\n%s\n' '在 Tencent VNC 中核对 SSH 主机指纹；不要只相信 ssh-keyscan 返回值。'
printf '候选 SHA256 指纹：%s\n' "$fingerprint"
read -r -p '请把 VNC 显示的完整 SHA256 指纹粘贴到这里：' confirmed
[[ "$confirmed" == "$fingerprint" ]] || die '主机指纹不匹配；拒绝连接。'
mv "$candidate" "$runtime/known_hosts"
chmod 0600 "$runtime/known_hosts"
unset confirmed fingerprint scan_host scan_port
log INFO 'Rescue SSH key and endpoint are RAM-only; host key was explicitly pinned.'
