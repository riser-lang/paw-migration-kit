#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/paw-lib.sh"
phase="${PAW_NETWORK_PHASE:-LIVE}"
run_root="${PAW_RUN_ROOT:-/run}"
ram_dir="$run_root/paw-network"
case "$phase" in LIVE|RESTORED_UBUNTU) ;; *) die 'Network wizard only runs in Live or final Ubuntu phase.' ;; esac
bin="${PAW_XRAY_BIN:-/opt/paw-migration/bin/xray}"
cfg="${PAW_XRAY_CONFIG:-$ram_dir/xray-client.json}"
xray_sha='8255dd939c34cf966cc91517b6324dd3c8d0bcf49ffac8beca049a38c46845ed'
choice="${PAW_NETWORK_CHOICE:-}"
if [[ -z "$choice" ]]; then
  # shellcheck source=scripts/paw-tty-lib.sh
  source "$PAW_ROOT/scripts/paw-tty-lib.sh"
  export PAW_TTY_SESSION_NAME=network-wizard
  paw_tty_open_optional || die '无法打开中文终端;未改变任何网络设置.'
  paw_tty_clear
  paw_tty_marker PAW-TTY1-VLESS-PANEL
  paw_tty_say 'PAW 网络接入向导(只影响本次启动,Xray 配置保存在 /run)'
  paw_tty_say '1 = 先尝试家庭宽带直连 Tailscale(推荐,不启动 Xray)'
  paw_tty_say '2 = 使用旧 VPS 的 VLESS 作为临时出口(仅当直连失败)'
  paw_tty_say 'Q = 取消,不改变网络'
  paw_tty_prompt '选择 1/2/Q:'
  if ! paw_tty_read choice; then paw_tty_close; die '网络向导输入超时;未改变网络.'; fi
  case "${choice^^}" in
    1) choice=direct ;; 2) choice=vps ;; Q) paw_tty_close; log INFO 'Operator cancelled network wizard.'; exit 0 ;;
    *) paw_tty_marker PAW-TTY1-VLESS-BAD; paw_tty_say '错误:未识别的选择;未改变网络.'; paw_tty_close; die 'Unknown network wizard choice.' ;;
  esac
fi
case "$choice" in direct|vps|cancel) ;; *) die 'PAW_NETWORK_CHOICE must be direct, vps or cancel.' ;; esac
[[ "$choice" == cancel ]] && { log INFO 'Operator cancelled network wizard.'; exit 0; }

if [[ "$choice" == direct ]]; then
  if curl --noproxy '*' -fsS -o /dev/null --connect-timeout 5 --max-time 12 'https://controlplane.tailscale.com/key?v=1'; then
    PAW_NETWORK_PHASE="$phase" "$PAW_ROOT/scripts/paw-network-bootstrap.sh"
    PAW_NETWORK_PHASE="$phase" "$PAW_ROOT/scripts/paw-tailscale-join.sh"
    exit $?
  fi
  log WARN 'Direct Tailscale control access failed; choose option 2 to use the VPS VLESS path.'
  exit 2
fi

# VLESS path: verify the packaged client, accept one secret URI without echo,
# prove the VPS TCP endpoint is reachable, then start only loopback proxies.
[[ -x "$bin" ]] || die 'Bundled Xray client is missing; cannot use the VPS path.'
actual_sha="$(sha256sum "$bin" | awk '{print $1}')"
[[ "$actual_sha" == "$xray_sha" ]] || die 'Bundled Xray client SHA256 mismatch; refusing to run an unverified binary.'
[[ "$("$bin" version 2>/dev/null | head -n1)" == 'Xray 26.3.27 '* ]] || die 'Bundled Xray client is not the pinned v26.3.27.'
if [[ ! -s "$cfg" ]]; then
  [[ "${PAW_TEST_MODE:-0}" == 1 || "$(findmnt -n -o FSTYPE --target /run 2>/dev/null || true)" == tmpfs ]] || die '/run is not tmpfs; refusing to store VLESS credentials.'
  if [[ -r "$ram_dir/tailscale-authkey" ]]; then :; fi
  # shellcheck source=scripts/paw-tty-lib.sh
  source "$PAW_ROOT/scripts/paw-tty-lib.sh"
  export PAW_TTY_SESSION_NAME=network-wizard
  paw_tty_say '请粘贴自己的 vless:// 连接链接(输入时不回显,不进入 shell history).'
  paw_tty_prompt 'VLESS 链接(直接粘贴后回车):'
  uri=''
  if ! paw_tty_read_secret uri; then paw_tty_close; die 'VLESS input timed out; nothing was started.'; fi
  printf '%s' "$uri" | python3 "$PAW_ROOT/scripts/paw-vless-uri-import.py" "$cfg" || { unset uri; paw_tty_close; die 'VLESS link was rejected; no credential was logged.'; }
  unset uri
  chmod 0600 "$cfg"; chown root:root "$cfg"
  paw_tty_say 'VLESS 配置已校验并只保存在 RAM.'
fi
read -r endpoint_host endpoint_port < <(python3 - "$cfg" <<'PY'
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
o=d["outbounds"][0]["settings"]["vnext"][0]
print(o["address"], o["port"])
PY
)
[[ "$endpoint_host" =~ ^[A-Za-z0-9.-]+$ && "$endpoint_port" =~ ^[0-9]+$ ]] || die 'VLESS endpoint is malformed.'
if ! timeout 6 bash -c "exec 3<>/dev/tcp/$endpoint_host/$endpoint_port" 2>/dev/null; then
  log ERROR '旧 VPS 的 VLESS 端口不可达.请确认旧 VPS 已正常启动,Xray/VLESS 服务正在运行;不会无限重试.'
  exit 2
fi
"$PAW_ROOT/scripts/paw-xray-proxy.sh" start || { log ERROR 'Xray 或本地回环 HTTP 代理校验失败;已停止,不会退回直连假象.'; exit 2; }
PAW_NETWORK_PHASE="$phase" "$PAW_ROOT/scripts/paw-tailscale-join.sh"
rc=$?
if ((rc != 0)); then log WARN 'Tailscale 未在线;Xray 保持运行以便用户重试,未设置 Exit Node.'; fi
exit "$rc"
