#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/paw-lib.sh"
need systemctl
read -r -p '阶段选择：R = Rescue Mode；U = 旧 Ubuntu 已恢复（只在确认旧 Ubuntu 已正常启动后选择）：' selection
case "${selection^^}" in
  R) phase=RESCUE ;;
  U)
    read -r -p '确认旧 Ubuntu 已恢复正常运行？输入 RESTORED：' confirmed
    [[ "$confirmed" == RESTORED ]] || die 'Restored Ubuntu phase was not confirmed.'
    phase=RESTORED_UBUNTU
    unset confirmed
    ;;
  *) die 'Unknown network phase selection.' ;;
esac
install -d -m 0700 /run/paw-network
printf '%s\n' "$phase" >/run/paw-network/network-phase
chmod 0600 /run/paw-network/network-phase
systemctl set-environment "PAW_NETWORK_PHASE=$phase"
unset selection phase
log INFO 'Network phase set in RAM for this boot only.'
if systemctl is-active --quiet paw-network-bootstrap.service; then
  systemctl restart paw-network-bootstrap.service
fi
if [[ "$(cat /run/paw-network/network-phase)" == RESTORED_UBUNTU ]]; then
  systemctl start paw-tailscale-join.service
fi
