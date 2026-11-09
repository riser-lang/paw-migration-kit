# PAW v2.7.1 第 1 段 BLOCKERS

更新日期：2026-11-10（本地）
适用分支：`fix/v2.6.2-final-readiness`
对应测试报告：`docs/PAW-V2.7.1-TEST-REPORT.md`
保护边界：只使用虚拟磁盘/QEMU；未触碰旧 VPS、生产 PAW、真实 TF 卡或真实硬盘。

## 状态汇总

| ID | 级别 | 条目 | 状态 | 影响 |
|---|---|---|---|---|
| PAW-271-B01 | 高 | 中文控制台字形无法在现有 vgacon 字体下显示 | OPEN / 需第 3 段 | 现场中文菜单可能显示空白，仅 ASCII 键位行可读 |
| PAW-271-B02 | 低 | 本机沙箱禁止 pty，pty 行为测试未本地执行 | OPEN（环境） | 已由 QEMU tty1 用例覆盖；CI 强制 pty |
| PAW-271-B03 | 高 | 真实 ASUS 主板显示器/键盘未验证 | OPEN / 实机验收 | QEMU 只证明虚拟 VGA + PS/2 键盘路径 |
| PAW-271-B04 | 中 | 最终 ISO 未在本段重建，哈希未复核 | 预期 / 第 3 段 | 本段证据基于一次性 Debian 13 测试盘，不是发布 ISO |
| PAW-271-B05 | 中 | 真实 `systemctl reboot` 未执行 | 设计边界 / 第 3 段 | 只验证可注入 reboot 与默认命令配置 |
| PAW-271-B06 | 中 | 原有 79 项 loop/虚拟套件未在本机重跑 | OPEN（环境） | 本机无 root/`losetup`；需 CI 完整回归 |
| PAW-271-B07 | 低 | tty1 占用为阶段性快照，不是全程连续审计 | 已缓解 | 交互前后与菜单阶段 `max_holders=1`，非逐毫秒跟踪 |
| PAW-271-B08 | 低 | Tailscale 登录链接改造未由网络套件本地执行 | OPEN | 只做静态检查；CI 网络套件覆盖 |

## PAW-271-B01 中文控制台字形（高）

**现象**

QEMU VGA 文本帧缓存和 screendump 中，菜单/提示的 ASCII 结构、数字和英文标识正常，
但中文 UTF-8 字符没有对应字形，显示为空白。原因是当前 ISO 包列表没有 CJK 控制台
字体或用户态终端（只有内核 vgacon/systemd），内核默认 8x16 字体不含 CJK。

**证据**

- `artifacts/qemu-tty/ok/screen-ok-menu.ppm` 与 `screen-ok-menu.txt`：
  `[PAW-MENU-TTY1]`、数字、`Memtest86+`、`Rescue SSH`、`SSD`、`SMART` 可见；
  中文标题/说明为空白。
- 同目录 `vga.bin` 的 VGA 文本内存只有 8-bit 字符单元，中文码点无法落入。
- 状态文件 `data-init.json` / `console-menu.json` 证明提示确实写到了 `/dev/tty1`，
  因此这不是 TTYPath 或输入通道问题。

**已做缓解**

- 所有交互界面增加 ASCII 键位/状态行：
  `[PAW-MENU-KEYS] 1 Memtest 2 PAWDATA 3 RescueSSH 4 TargetSSD 5 HWCheck 6 Migrate 7 Reports 8 Network 0 Redraw`，
  `[PAW-TTY1-PROMPT] Enter the last 6 characters ...`。
- PAW 菜单仍保留中文原文；ASCII 行只用于无 CJK 字体时的可操作性。

**未做/不能声称**

- 不能声称“中文菜单字形正常显示”。本段只证明提示/菜单写到 tty1，且 ASCII 可判定标记
  在真实 QEMU 帧缓存中 100% 字形匹配。
- 不能用 OCR 作为唯一证据。

**建议后续（第 3 段）**

1. 在发布 ISO 中引入 CJK 控制台方案（例如加入 `fbterm` + `fonts-wqy-zenhei`/Noto CJK，
   或生成只含 UI 所需汉字的 PSF 字体并在早期 unit 加载）。
2. 用同一 QEMU screendump + 字形匹配脚本做发布 ISO 的中文回归；若仍只能 ASCII，
   则必须在用户指南明确写“控制台仅 ASCII，中文见报告/图形界面”。
3. 在真实 ASUS 主板上确认 `/dev/fb0`、键盘事件设备和字体加载顺序。

## PAW-271-B02 本机 pty 测试（低，环境）

- `scripts/ci/pty_tty_test.py` 通过真实 pty 注入正确/错误/超时/EOF，并断言
  `menu_tty == input_tty`、`max_holders == 1`。
- 本机沙箱禁止 `/dev/ptmx`，返回 `out of pty devices`，测试标记 BLOCKED 而非 PASS。
- 同一 `paw-tty-lib.sh` 已由 QEMU `/dev/tty1` 用例真实覆盖。
- CI 步骤以 `PAW_REQUIRE_PTY=1` 运行；pty 不可用会使 CI 失败，防止静默跳过。

## PAW-271-B03 真实 ASUS 主板（高，实机）

- QEMU 使用 `-vga std` + PS/2 键盘通道，能证明 VGA 帧缓存和 `sendkey` 路径，
  但不能证明真实 ASUS 主板的 UEFI/CSM、显示器时序、USB 键盘、getty 竞争。
- 实机验收至少需要：显示器出现 `[PAW-MENU-TTY1]`/PAWDATA 提示、键盘输入被接受、
  `systemctl status paw-data-init paw-console getty@tty1` 无双重占用。
- 本段未接触任何真实硬盘/TF 卡，符合保护边界。

## PAW-271-B04 最终 ISO（中，第 3 段）

- 本段测试盘是复用既有 Debian 13 rootfs 生成的一次性 ext4 镜像，注入了当前脚本/单元；
  不是 `boot/custom/paw-live-amd64.iso`。
- 因此不能把本段结果当成发布 ISO 的构建/哈希/启动验收。
- 第 3 段必须重新构建 ISO，复核 SHA256，并用 QEMU 对 ISO 重跑本报告中的 tty 用例。

## PAW-271-B05 真实 reboot（中，设计边界）

- 测试只执行注入的 mock reboot（成功/失败/取消），默认 `systemctl reboot` 未在宿主机执行，
  以避免重启真实机器。
- 代码默认值仍是 `systemctl reboot`；`PAW_REBOOT_CMD`/`PAW_REBOOT_DRY_RUN` 仅用于测试。
- 真实重启应由第 3 段在一次性虚拟机或实机验收中执行，并确认重启后进入正式 Ubuntu。

## PAW-271-B06 原有 79 项套件（中，环境）

- 本机沙箱 `sudo` 不可用（`no_new_privs`），`losetup` 类套件无法运行；
  本段只真实执行了不依赖 root 的 36 项 finalize、29 项 tty 静态和 24 项 QEMU 断言。
- 修改涉及的旧路径：
  - `paw-data-prepare.sh` 的非交互模拟分支保持原行为；
  - `paw-prepare-data-partition.sh` 仅新增复用已确认 suffix 的分支；
  - `paw-console-menu.sh`、`paw-tailscale-join.sh` 不在旧 79 项的直接断言内。
- CI 的 loop/虚拟套件必须完整跑一遍后才能宣称“79 项不回归”。

## PAW-271-B07 tty1 单占用审计粒度（低）

- 每个交互阶段扫描 `/proc/*/fd`，排除当前 shell 的临时子进程，记录
  `max_holders=1`；同时用 unit 的 `Conflicts`/`After` 约束 getty。
- 这不是逐毫秒的持续跟踪；若需更强证明，可在第 3 段加 eBPF/audit 或
  在 getty 启动点加 `ExecStartPre` 断言。当前证据足以证明交互时刻只有一个非辅助持有者。

## PAW-271-B08 Tailscale 登录链接（低）

- `paw-tailscale-join.service` 不再占用 tty，登录 URL 写入
  `tailscale-login.json`，由控制台菜单显示。
- 本机未运行网络套件（需要 root/宿主 systemd 路径）；只做静态检查和单元结构检查。
- CI 的 `run-network-virtual-tests.sh` 应覆盖 tailscale join 的 online/pending 路径；
  若该套件未跑，不能宣称网络行为无回归。

## 明确未违反的保护边界

- 未修改/停止/重启旧 VPS；未进入 Tencent Rescue Mode。
- 未读取生产整盘；未执行真实克隆。
- 未修改生产 PAW、Tailscale、Funnel、Xray、Nginx、443、防火墙、COS。
- 未格式化/写入真实 TF 卡；未操作真实硬盘。
- 未删除历史 Artifact；未修改仓库可见性；未合并 PR #2。
