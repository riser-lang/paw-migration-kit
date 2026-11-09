#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/paw-lib.sh"
source "$(dirname "$0")/paw-tty-lib.sh"
need python3

export PAW_TTY_SESSION_NAME=console-menu
paw_tty_open || die '无法打开 /dev/tty1；PAW 控制台菜单未启动。'
trap 'paw_tty_close || true' EXIT

readiness="$PAW_REPORT_DIR/live-readiness.json"
status_text(){
  python3 - "$readiness" <<'PY' 2>/dev/null || printf '尚未生成（请先完成 PAWDATA、源盘、目标盘和硬件检查）'
import json,sys
d=json.load(open(sys.argv[1],encoding="utf-8"))
print(f"状态={d.get('status','UNKNOWN')} " + " ".join(f"{k}={v}" for k,v in (d.get("checks") or {}).items()))
PY
}
target_dev(){
  python3 - "$PAW_CONFIG_DIR/target-ssd.json" <<'PY' 2>/dev/null || true
import json,sys
print(json.load(open(sys.argv[1],encoding="utf-8")).get("device_path") or "")
PY
}
tailscale_login(){
  python3 - "$PAW_REPORT_DIR/tailscale-login.json" <<'PY' 2>/dev/null || true
import json,sys
print(json.load(open(sys.argv[1],encoding="utf-8")).get("login_url") or "")
PY
}
pause(){
  paw_tty_prompt $'\n按 Enter 返回菜单...'
  local _
  if ! paw_tty_read_line _; then exit 0; fi
  paw_tty_record menu pause 'operator returned to menu'
}
menu_marker_recorded=0

while :; do
  paw_tty_clear
  printf '[PAW-MENU-TTY1]\n' >&3
  if ((menu_marker_recorded == 0)); then
    paw_tty_record menu shown 'Chinese console menu on tty1' 'PAW-MENU-TTY1'
    menu_marker_recorded=1
  fi
  paw_tty_say '=============================================='
  paw_tty_say ' PAW 迁移准备控制台（v2.7）'
  paw_tty_say '=============================================='
  paw_tty_say '[PAW-MENU-KEYS] 1 Memtest 2 PAWDATA 3 RescueSSH 4 TargetSSD 5 HWCheck 6 Migrate 7 Reports 8 Network 0 Redraw'
  paw_tty_say "当前：$(status_text)"
  paw_tty_say '1) 登记 Memtest86+ 人工确认结果'
  paw_tty_say '2) 初始化/修复 PAWDATA 持久分区'
  paw_tty_say '3) 配置 Rescue SSH 并识别旧 VPS 源盘'
  paw_tty_say '4) 登记目标 SSD（只读盘点）'
  paw_tty_say '5) 运行目标 SSD 硬件检查（SMART/只读扫描/温度/内存）'
  paw_tty_say '6) 最终中文授权并开始迁移'
  paw_tty_say '7) 查看状态和报告'
  paw_tty_say '8) 选择 Rescue / Restored 网络阶段'
  paw_tty_say '0) 重新显示状态'
  local_login="$(tailscale_login)"
  if [[ -n "$local_login" ]]; then paw_tty_say "Tailscale 登录链接：$local_login"; fi
  paw_tty_record menu prompt 'menu choice requested on tty1'
  paw_tty_prompt '请输入编号：'
  choice=''
  if ! paw_tty_read_line choice; then exit 0; fi
  paw_tty_record menu input "choice=${choice}"
  case "$choice" in
    1) "$PAW_ROOT/scripts/paw-memtest-confirm.sh" || true; pause ;;
    2) "$PAW_ROOT/scripts/paw-data-prepare.sh" manual || true; pause ;;
    3)
      paw_tty_say '下一步需要 Tencent Rescue VNC 中的临时 SSH 地址、端口和主机指纹。'
      "$PAW_ROOT/scripts/paw-rescue-key-prepare.sh" || true
      "$PAW_ROOT/scripts/paw-source-discovery.sh" || true
      pause ;;
    4) "$PAW_ROOT/scripts/paw-target-discovery.sh" || true; pause ;;
    5)
      dev="$(target_dev)"
      if [[ -z "$dev" ]]; then paw_tty_say '尚未登记目标 SSD，请先选 4。'; else
        "$PAW_ROOT/scripts/paw-hardware-preflight.sh" "$dev" || true
      fi
      pause ;;
    6)
      paw_tty_say '最终授权会整盘覆盖目标 SSD。请确认已阅读屏幕上的数据损失说明。'
      "$PAW_ROOT/scripts/paw-final-confirm.sh" || true
      pause ;;
    7)
      if [[ -r "$readiness" ]]; then
        while IFS= read -r line; do paw_tty_say "$line"; done <"$readiness"
      fi
      paw_tty_say ''
      paw_tty_say "报告目录：$PAW_REPORT_DIR"
      if [[ -d "$PAW_REPORT_DIR" ]]; then
        while IFS= read -r line; do paw_tty_say "$line"; done < <(ls -l "$PAW_REPORT_DIR" 2>/dev/null || true)
      fi
      pause ;;
    8) "$PAW_ROOT/scripts/paw-network-phase-select.sh" || true; pause ;;
    0) ;;
    *) paw_tty_say '编号无效。'; sleep 1 ;;
  esac
done
