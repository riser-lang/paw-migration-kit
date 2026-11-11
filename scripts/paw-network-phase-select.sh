#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/paw-lib.sh"
need systemctl
# shellcheck source=scripts/paw-tty-lib.sh
source "$PAW_ROOT/scripts/paw-tty-lib.sh"
export PAW_TTY_SESSION_NAME=network-phase
paw_tty_open_optional || die '无法打开交互终端；未设置任何网络阶段。'
paw_tty_clear
paw_tty_marker PAW-TTY1-NETPHASE-PANEL
paw_tty_say 'PAW 网络阶段选择（只对本次启动生效，不写入磁盘）'
paw_tty_say 'R = Rescue Mode（正在通过临时 SSH 连接旧 VPS 取证）'
paw_tty_say 'U = 旧 Ubuntu 已恢复（只在确认旧 Ubuntu 已正常启动后选择）'
paw_tty_marker PAW-TTY1-NETPHASE-PROMPT
paw_tty_prompt '阶段选择 R/U：'
selection=''
if ! paw_tty_read selection; then
  paw_tty_marker PAW-TTY1-NETPHASE-TIMEOUT
  paw_tty_close
  die '阶段选择输入超时或中断；未设置任何网络阶段。'
fi
case "${selection^^}" in
  R) phase=RESCUE ;;
  U)
    paw_tty_prompt '确认旧 Ubuntu 已恢复正常运行？输入 RESTORED：'
    confirmed=''
    if ! paw_tty_read confirmed; then
      paw_tty_marker PAW-TTY1-NETPHASE-TIMEOUT
      paw_tty_close
      die '恢复阶段确认输入超时或中断；未设置任何网络阶段。'
    fi
    if [[ "$confirmed" != RESTORED ]]; then
      paw_tty_marker PAW-TTY1-NETPHASE-BAD
      paw_tty_say '错误：没有确认旧 Ubuntu 已恢复；未设置任何网络阶段。'
      paw_tty_close
      die 'Restored Ubuntu phase was not confirmed.'
    fi
    phase=RESTORED_UBUNTU
    unset confirmed
    ;;
  *)
    paw_tty_marker PAW-TTY1-NETPHASE-BAD
    paw_tty_say '错误：未识别的阶段选择；未设置任何网络阶段。'
    paw_tty_close
    die 'Unknown network phase selection.' ;;
esac
paw_tty_marker PAW-TTY1-NETPHASE-OK
paw_tty_say "已选择网络阶段：$phase"
paw_tty_close
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
