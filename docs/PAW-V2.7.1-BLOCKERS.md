# PAW v2.7.1 第一段 BLOCKERS（本轮更新）

更新日期：2026-11-10
分支：`fix/v2.6.2-final-readiness`
本轮 HEAD：`376c35d00a943941e64ff2b38c627e9657a47cc9`
对应测试报告：`docs/PAW-V2.7.1-TEST-REPORT.md`
保护边界：只使用虚拟磁盘/QEMU；未触碰旧 VPS、生产 PAW、真实 TF 卡或真实硬盘。

## 状态汇总

| ID | 级别 | 条目 | 状态 | 影响 |
|---|---|---|---|---|
| PAW-271-B01 | 高 | 中文控制台字形无法显示 | **CLOSED（QEMU/fbcon 已验证）** | 发布前仍需实机 B03 |
| PAW-271-B02 | 低 | 本机工具沙箱禁止 pty / sudo / loop attach | **OPEN（环境，已定根因）** | 本机 root/PTY 测试 BLOCKED；CI 真实执行 |
| PAW-271-B03 | 高 | 真实 ASUS B85M-G Plus 显示器/键盘未验证 | **OPEN（实机验收）** | QEMU 只证明虚拟 VGA + PS/2 键盘 |
| PAW-271-B04 | 中 | 最终发布 ISO 未构建/未复核哈希 | **OPEN（后续段）** | CI 构建的是测试 Live ISO |
| PAW-271-B05 | 中 | 真实 `systemctl reboot` 未执行 | **OPEN（设计边界）** | 只验证 mock/注入 reboot |
| PAW-271-B06 | 中 | 原有 79 项 loop/虚拟套件本机未执行 | **OPEN（环境；CI 执行）** | 本机无 CAP_SYS_ADMIN，不能 attach loop |
| PAW-271-B07 | 低 | tty1 占用为阶段性快照 | 已缓解 | 交互前后与菜单阶段 `max_holders=1` |
| PAW-271-B08 | 低 | Tailscale 登录链接改造未由本机网络套件执行 | OPEN | CI 网络 17 项覆盖 |
| PAW-271-B09 | 低 | vgacon 8x16 后备字体对复杂汉字可读性有限 | OPEN（已文档化） | 主路径是 fbcon 16x16；无 fb0 时才回退 |
| PAW-271-B10 | 中 | CI QEMU 仍是虚拟硬件，不是 ASUS 实机 | OPEN | 不能把虚拟测试说成实机验收 |
| PAW-271-B11 | 高 | 六个操作员脚本的面板只进 journal、不上屏幕 | **CLOSED（静态 55 + PTY 15，CI 绿）** | 实机屏幕仍归 B03 |
| PAW-271-B12 | 中 | 新增授权面板的中文字形未进 QEMU CJK 截图套件 | **OPEN（下一轮）** | 只有静态断言，没有像素级证据 |
| PAW-271-B13 | 低 | 本机换成 Windows 11，无 `termios`，PTY 无法本地执行 | **OPEN（环境）** | 由 CI `PAW_REQUIRE_PTY=1` 覆盖 |

## PAW-271-B11 操作员面板不上屏幕（第二段修复）

- `paw-console.service` 为 `StandardOutput=journal`，菜单之外的六个操作员脚本仍用
  裸 `printf`，面板只进日志。最终授权面板（含数据损失警告）在屏幕上根本不存在，
  操作员只看到“输入最后 6 位”。
- 修复：统一走 `paw_tty_open_optional()` + `paw_tty_say/paw_tty_prompt/
  paw_tty_read/paw_tty_read_secret`（300 秒超时、ASCII 标记、回退时不记录 tty1
  会话）。`paw-data-prepare.sh` 保持严格绑定。
- 证据：本机静态 **55 passed / 0 failed**；CI Run `42778468039` TTY 套件
  **56 passed / 0 failed / 0 blocked**（含 15 项 PTY）。
- 仍未证明：真实 ASUS 屏幕上的字形与可读性（B03）。

## PAW-271-B12 授权面板缺少像素级证据

QEMU CJK 套件当前只驱动菜单与 PAWDATA 面板（ok/bad/timeout/render 四例、71 断言），
新改的授权/内存/目标盘/Rescue/网络阶段/UUID 面板只有静态断言与 PTY 交互证据，
没有 screendump 字形匹配。不能声称这些面板已在真实字形下被验证。

下一步：在 QEMU 套件中增加 `final` 用例，注入完整源/目标/硬件/内存 fixture，
对授权面板做同样的逐单元格字模匹配。

## PAW-271-B01 中文控制台字形（CLOSED for QEMU/fbcon）

**修复**

- 采用 **fbcon + GNU Unifont 16x16 PSF2**，不是“给 vgacon 装一个大字体”。
- 512 槽：95 ASCII（空格固定在 32 槽）+ 385 个运行时非 ASCII 字符，480 个映射。
- `paw-console-font.service` 在 PAWDATA/菜单之前 `setfont -C /dev/tty1`；
  有 `/dev/fb0` 用 16x16，无 fb0 用 8x16 应急后备。
- 不声明 `TTYPath=`，不改变 `paw-tty-lib.sh` 的 fd3 读写和键盘路径。

**证据**

- 本机 QEMU（generic 6.12.94 + bochs-drm，1280x800）：
  - 菜单/PAWDATA 面板/序列号提示/错误原因/超时/迁移完成提示均以真实字形出现；
  - `screendump` 逐单元格与 PSF 位图精确匹配，ratio ≥ 0.995；
  - ok/bad/timeout/render 四例，71 断言全过；
  - 状态文件 `tty_path=/dev/tty1`、`menu_tty=input_tty=/dev/tty1`、`max_holders=1`。
- CI：`Run framebuffer CJK tty1 display and keyboard suite` 从真实 ISO squashfs
  启动并重跑四例（Run ID 见 TEST-REPORT）。

**未做/不能声称**

- 不能声称 ASUS 实机已经显示中文；见 B03。
- 不能声称 vgacon 8x16 后备对全部复杂汉字都清晰；它只是无 fb0 时的应急。
- 不能用 OCR 代替字形匹配；本套件不是 OCR。

## PAW-271-B02 本机 sudo / pty / loop（环境，根因已定）

- 工具层 Landlock wrapper 对每条 bash 命令设置 `NoNewPrivs=1`，并清空有效
  capability；`sudo` 是 setuid，无法提权；`losetup --find --show` 需要
  `CAP_SYS_ADMIN`，失败。
- 不是容器：`systemd-detect-virt=kvm`，`/proc/1/cgroup=0::/init.scope`。
- 不是 sudoers 配置：调度方直接执行（NNP=0）`sudo -n id` 成功。
- 本机 pty：`/dev/ptmx` 不可用（`out of pty devices`），PTY 用例标记 BLOCKED。
- CI 以 root 执行 loop 套件，以 `PAW_REQUIRE_PTY=1` 强制 PTY；不可用即失败。

## PAW-271-B03 真实 ASUS 主板（高，实机）

现场至少确认：

1. 普通显示器出现完整中文菜单和 PAWDATA 面板；
2. `cat /sys/class/graphics/fb0/name` 有值（预期 i915drmfb）；
3. `cat /run/paw-migration/reports/console-font.json` 为 `mode=fbcon`、`status=PASS`；
4. `systemctl status paw-data-init paw-console getty@tty1` 无双重占用；
5. USB/PS2 键盘可输入序列号末六位，错误/超时路径中文可读。

未完成前，第一段整体只能标 **PARTIAL**，不能标 COMPLETE。

## PAW-271-B04 / B05 / B06 / B08 / B10

- B04：本轮 CI 构建并启动测试 Live ISO，但不是最终发布 ISO；发布哈希、
  签名、写入 TF 卡与现场启动属于后续段。
- B05：真实 `systemctl reboot` 未执行；只验证 mock reboot、失败
  `NEEDS_MANUAL_ACTION`、取消与不重复重启。
- B06：本机没有 root/loop；CI runner 的 PAWDATA/克隆/修复/网络套件是真实 loop
  执行，不以本机静态检查代替。
- B08：Tailscale 登录 URL 只写报告文件；CI 网络套件覆盖阶段选择/回退。
- B10：QEMU 使用 SeaBIOS + TCG + std VGA + PS/2 `sendkey`，不是 ASUS 实机；
  不能把 QEMU 结果写成硬件验收。

## 结论

- 中文**屏幕字形**阻塞在 QEMU/fbcon 范围已关闭；这是第一段的核心修复。
- 第二段（2026-11-10）关闭了“操作员面板不上屏幕”（B11），补充静态 55 项与
  PTY 15 项断言；新增 B12（面板缺像素级证据）与 B13（Windows 无 termios）。
- 整体仍为 **PARTIAL**：真实 ASUS、真实重启、最终发布 ISO 现场验收、真实硬件
  全部 OPEN。
- PR #2 保持 Draft，未合并。
