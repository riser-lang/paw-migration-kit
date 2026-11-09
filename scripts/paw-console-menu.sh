#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/paw-lib.sh"
need python3

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
pause(){ printf '\n按 Enter 返回菜单...'; read -r _ || true; }

while :; do
  clear 2>/dev/null || true
  printf '%s\n' '=============================================='
  printf '%s\n' ' PAW 迁移准备控制台（v2.7）'
  printf '%s\n' '=============================================='
  printf '当前：%s\n' "$(status_text)"
  printf '%s\n' '1) 登记 Memtest86+ 人工确认结果'
  printf '%s\n' '2) 初始化/修复 PAWDATA 持久分区'
  printf '%s\n' '3) 配置 Rescue SSH 并识别旧 VPS 源盘'
  printf '%s\n' '4) 登记目标 SSD（只读盘点）'
  printf '%s\n' '5) 运行目标 SSD 硬件检查（SMART/只读扫描/温度/内存）'
  printf '%s\n' '6) 最终中文授权并开始迁移'
  printf '%s\n' '7) 查看状态和报告'
  printf '%s\n' '8) 选择 Rescue / Restored 网络阶段'
  printf '%s\n' '0) 重新显示状态'
  read -r -p '请输入编号：' choice || exit 0
  case "$choice" in
    1) "$PAW_ROOT/scripts/paw-memtest-confirm.sh" || true; pause ;;
    2) "$PAW_ROOT/scripts/paw-data-prepare.sh" manual || true; pause ;;
    3)
      printf '%s\n' '下一步需要 Tencent Rescue VNC 中的临时 SSH 地址、端口和主机指纹。'
      "$PAW_ROOT/scripts/paw-rescue-key-prepare.sh" || true
      "$PAW_ROOT/scripts/paw-source-discovery.sh" || true
      pause ;;
    4) "$PAW_ROOT/scripts/paw-target-discovery.sh" || true; pause ;;
    5)
      dev="$(target_dev)"
      if [[ -z "$dev" ]]; then printf '%s\n' '尚未登记目标 SSD，请先选 4。'; else
        "$PAW_ROOT/scripts/paw-hardware-preflight.sh" "$dev" || true
      fi
      pause ;;
    6)
      printf '%s\n' '最终授权会整盘覆盖目标 SSD。请确认已阅读屏幕上的数据损失说明。'
      "$PAW_ROOT/scripts/paw-final-confirm.sh" || true
      pause ;;
    7)
      [[ -r "$readiness" ]] && cat "$readiness" || true
      printf '\n报告目录：%s\n' "$PAW_REPORT_DIR"
      ls -l "$PAW_REPORT_DIR" 2>/dev/null || true
      pause ;;
    8) "$PAW_ROOT/scripts/paw-network-phase-select.sh" || true; pause ;;
    0) ;;
    *) printf '%s\n' '编号无效。'; sleep 1 ;;
  esac
done
