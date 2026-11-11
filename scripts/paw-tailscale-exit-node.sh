#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/paw-lib.sh"
action="${1:-status}"
peer="${2:-}"
case "$action" in
  plan)
    cat <<'EOF'
Exit Node 只作为可选回退，不是迁移依赖。
1. 在旧 VPS 的 Tailscale 管理端确认它被批准为 Exit Node。
2. 新 PAW 在线后执行本脚本 enable <旧VPS Tailscale IP>。
3. 验证 tailscale status 显示 exit node，且新 PAW 仍能访问局域网。
4. 关闭时执行 disable，恢复直连出口。
EOF
    ;;
  status)
    tailscale status --json 2>/dev/null | python3 -c 'import json,sys; d=json.load(sys.stdin); print("exit_node="+str(d.get("ExitNodeStatus") or "none")); print("backend="+str(d.get("BackendState")))' || { echo 'tailscale=unavailable'; exit 2; }
    ;;
  enable)
    [[ "$peer" =~ ^[0-9.]+$ ]] || die 'Usage: paw-tailscale-exit-node.sh enable <tailscale-ipv4>'
    [[ "${PAW_EXIT_NODE_ARM:-}" == 'I_HAVE_CONFIRMED_EXIT_NODE' ]] || die 'Exit Node change is not armed; refusing to alter routing.'
    tailscale set --exit-node="$peer" --exit-node-allow-lan-access=true
    tailscale status --json | python3 -c 'import json,sys; d=json.load(sys.stdin); e=d.get("ExitNodeStatus") or {}; raise SystemExit(0 if e.get("Online") else 1)' || die 'Exit Node did not come online; run disable and keep direct route.'
    log INFO "Exit Node $peer enabled with LAN access preserved.";;
  disable)
    tailscale set --exit-node= --exit-node-allow-lan-access=false
    log INFO 'Exit Node disabled; direct route restored.';;
  *) die 'Usage: paw-tailscale-exit-node.sh plan|status|enable <ip>|disable';;
esac
