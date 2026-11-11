# PAW v2.7.1 第一段 BLOCKERS（本轮更新）

更新日期：2026-11-11（Stage 3 close / Stage 4 delivery）
历史证据分支：`fix/v2.6.2-final-readiness`
当前干净交接分支：`vm/ds-clean-handover-20261110`
当前代码 HEAD：`24c13f7`
当前分支基线：`d64071251bb3075d9cb26a967dfcba6cf139250a`
历史 HEAD：`bf1a705`（第二段）／`376c35d00a943941e64ff2b38c627e9657a47cc9`（第一段）
对应测试报告：`docs/PAW-V2.7.1-TEST-REPORT.md`
保护边界：只使用虚拟磁盘/QEMU；未触碰旧 VPS、生产 PAW、真实 TF 卡或真实硬盘。

> **Stage 3 已关闭**：18–26 步全部有真实 PASS 日志，包含 `auto_reboot` 先原子
> 持久化并 `sync` 再执行重启，以及 SeaBIOS 从克隆目标盘启动到 `ubuntu login:`。
> 证据见 `reports/PAW-STAGE3-RESUME-20261110.md`。Stage 4 正在等待代码 HEAD
> `24c13f7` 的最终 CI Run `42941005270` 和 ISO 文件本身的 SHA256 复核。
> 历史 Run `42804949796` 只对应 `bf1a705`，不是当前分支证据。

## 状态汇总

| ID | 级别 | 条目 | 状态 | 影响 |
|---|---|---|---|---|
| PAW-271-B01 | 高 | 中文控制台字形无法显示 | **CLOSED（QEMU/fbcon 已验证）** | 发布前仍需实机 B03 |
| PAW-271-B02 | 低 | 本机工具沙箱禁止 pty / sudo / loop attach | **OPEN（环境，已定根因）** | 本机 root/PTY 测试 BLOCKED；CI 真实执行 |
| PAW-271-B03 | 高 | 真实 ASUS B85M-G Plus 显示器/键盘未验证 | **OPEN（实机验收）** | QEMU 只证明虚拟 VGA + PS/2 键盘 |
| PAW-271-B04 | 中 | 最终发布 ISO 尚未完成下载复核 | **IN_PROGRESS** | Run `42941005270`（`24c13f7`）成功后下载 artifact，从 ISO 文件重算 SHA256，不采用 ZIP 哈希 |
| PAW-271-B05 | 中 | 真实 `systemctl reboot` 未执行 | **OPEN（设计边界）** | 只验证 mock/注入 reboot |
| PAW-271-B06 | 中 | 原有 79 项 loop/虚拟套件本机未执行 | **OPEN（环境；CI 执行）** | 本机无 CAP_SYS_ADMIN，不能 attach loop |
| PAW-271-B07 | 低 | tty1 占用为阶段性快照 | 已缓解 | 交互前后与菜单阶段 `max_holders=1` |
| PAW-271-B08 | 低 | Tailscale 登录链接改造未由本机网络套件执行 | OPEN | CI 网络 17 项覆盖 |
| PAW-271-B09 | 低 | vgacon 8x16 后备字体对复杂汉字可读性有限 | OPEN（已文档化） | 主路径是 fbcon 16x16；无 fb0 时才回退 |
| PAW-271-B10 | 中 | CI QEMU 仍是虚拟硬件，不是 ASUS 实机 | OPEN | 不能把虚拟测试说成实机验收 |
| PAW-271-B11 | 高 | 六个操作员脚本的面板只进 journal、不上屏幕 | **CLOSED（静态 55 + PTY 15，CI 绿）** | 实机屏幕仍归 B03 |
| PAW-271-B12 | 中 | 新增授权面板的中文字形未进 QEMU CJK 截图套件 | **CLOSED（QEMU final 用例，25 断言）** | 实机屏幕仍归 B03 |
| PAW-271-B13 | 低 | 本机 PTY 不可用（当前 Linux 沙箱 `/dev/ptmx` → Out of pty devices；历史 Windows 无 `termios`） | **OPEN（环境）** | 由 CI `PAW_REQUIRE_PTY=1` 覆盖 |
| PAW-271-B14 | 高 | 字体门禁只在“报告 PASS”时允许写盘；8x16 回退是 WARN，必须拒绝 | **CLOSED（Run 42825407549）** | 缺报告/哈希/字体/setfont/过期 boot_id 全部 fail-closed；CI 26/26 + QEMU CJK 25/25；Run 42817841755 的 `(M) frame buffer device` 回归已由 4572280 修复并复跑通过 |
| PAW-271-B15 | 高 | 第二阶段早期克隆用了 `PAW_SIMULATION=1`，生产块设备/SSH 入口和完整离线修复未执行 | **CLOSED（虚拟块设备范围）** | Stage 3 改用真实 `paw-stream-clone.sh`/`paw-stream-verify.sh` 在 QEMU virtio `/dev/vdb`→`/dev/vdc`、真实 loopback SSH、`mode=remote-zstd-level1-thread1` 上完成，并真实执行完整 `paw-offline-repair.sh`、GPT/ext4 扩容和两次目标启动。真实 SSD 仍归 P1-4/B03 之外的物理验收。见 `reports/PAW-STAGE3-RESUME-20261110.md` |
| PAW-271-B16 | 高 | 第三阶段完整迁移链路未完成 | **CLOSED（QEMU 虚拟块设备）** | 26 步全部有真实 PASS 日志；`auto_reboot` 状态先持久化+`sync` 再重启，目标盘由 SeaBIOS 二次启动到 `ubuntu login:`。物理硬件仍 OPEN。 |
| PAW-271-B17 | 高 | 第四阶段最终 ISO 尚未由当前代码 HEAD 下载并复核 | **IN_PROGRESS** | Run `42941005270`（`24c13f7`）必须是 success；下载 artifact 后从 ISO 文件计算 SHA256（不是 ZIP），写入 `PAW-V2.7.1-ISO-SHA256.txt` 和交付文档。 |

## PAW-271-B11 操作员面板不上屏幕（第二段修复）

- `paw-console.service` 为 `StandardOutput=journal`，菜单之外的六个操作员脚本仍用
  裸 `printf`，面板只进日志。最终授权面板（含数据损失警告）在屏幕上根本不存在，
  操作员只看到“输入最后 6 位”。
- 修复：统一走 `paw_tty_open_optional()` + `paw_tty_say/paw_tty_prompt/
  paw_tty_read/paw_tty_read_secret`（300 秒超时、ASCII 标记、回退时不记录 tty1
  会话）。`paw-data-prepare.sh` 保持严格绑定。
- 证据：本机静态 **55 passed / 0 failed**；CI Run `42804949796` TTY 套件
  **56 passed / 0 failed / 0 blocked**（含 15 项 PTY）。
- 仍未证明：真实 ASUS 屏幕上的字形与可读性（B03）。

## PAW-271-B12 授权面板像素级证据（第二段已关闭）

新增 QEMU 用例 `final`（`tests/qemu/paw-cjk-final-probe.sh` +
`paw-cjk-final.service`，由内核参数 `paw.final=1` 触发）在 tty1 上真实运行生产
脚本 `paw-final-confirm.sh`：

1. 造一套合成但完整的收据（readiness / source / target / hardware / memtest），
   并创建带 `PAWDATA` 标签的 loop ext4 与 loop 目标盘；
2. 第一次输入错误后缀 → 必须出现 `PAW-TTY1-FINAL-BAD` 与中文拒绝文案；
3. 第二次输入目标序列号末六位 → 必须出现 `PAW-TTY1-FINAL-OK` 与中文确认文案；
4. 用随包 PSF 字模逐单元格解码截图，断言授权面板标题、源系统、源盘组合身份、
   固定主机指纹、目标 SSD 行（含运行时序列号）、数据来源，以及**完整的整盘
   数据损失警告**和输入提示；并断言会话文件 `tty_path=/dev/tty1`、BAD/OK 两个标记、持有者中没有
   getty/login。

结果：Run `42804949796` — `Cases: 5 passed, 0 failed`，本例 25 断言全过。
未做克隆：授权通过后生产脚本按设计停在 Rescue 身份复核（该环境没有端点）。

三轮真实失败与修复（不隐藏）：`42784672282` 合成 source.json 缺
`partition_number` → 生产脚本在面板前按设计拒绝；`42788769956`
`max_holders=2` 是探针外壳自身持有 tty1 的夹具形态；`42792565444` 截图在中间行
出现即返回导致末行未画完（竞态）。

## PAW-271-B01 中文控制台字形（CLOSED for QEMU/fbcon）

**修复**

- 采用 **fbcon + GNU Unifont 16x16 PSF2**，不是“给 vgacon 装一个大字体”。
- 512 槽：95 ASCII（空格固定在 32 槽）+ 385 个运行时非 ASCII 字符，480 个映射。
- `paw-console-font.service` 在 PAWDATA/菜单之前 `setfont -C /dev/tty1`；
  有 `/dev/fb0` 且 fbcon 已绑定用 16x16；无 fb0 用 8x16 应急后备，但只记
  `WARN`，不打开写门禁。
- 不声明 `TTYPath=`，不改变 `paw-tty-lib.sh` 的 fd3 读写和键盘路径。

**证据**

- 本机 QEMU（generic 6.12.94 + bochs-drm，1280x800）：
  - 菜单/PAWDATA 面板/序列号提示/错误原因/超时/迁移完成提示均以真实字形出现；
  - `screendump` 逐单元格与 PSF 位图精确匹配，ratio ≥ 0.995；
  - ok/bad/timeout/render/final 五例，96 断言全过；
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
- 当前 Linux 本机 pty：`/dev/ptmx` 不可用（`out of pty devices`），PTY 用例
  标记 BLOCKED；历史 Windows 工作站无 `termios`。
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
- 第二段（2026-11-10）关闭了“操作员面板不上屏幕”（B11）与“授权面板缺像素级
  证据”（B12）：静态 55 项、PTY 15 项、QEMU 授权面板 25 项断言在 Run
  `42804949796` 全绿；新增 B13（Windows 无 termios）。
- 当前分支新增字体失败安全门禁：本机 26/26；CI 实际运行暴露两个回归
  （字体槽位 418/417、`(M) frame buffer device` 名称误判），均已修复；Run
  `42825407549` 已全绿（gate 26/26、CJK 25/25、TTY 56/56）。这是第一段收尾
  的必要条件，不是最终发布验收。
- 整体为 **STAGE 3 COMPLETE / STAGE 4 IN_PROGRESS / PHYSICAL OPEN**：
  26 步链路和真实块设备克隆入口已在 QEMU 中完成，最终发布 ISO 正在用当前
  代码 HEAD 的新 Run 生成并复核；真实 ASUS、真实重启、真实 TF/SSD 和现场验收
  仍 OPEN。
- 第二阶段/第三阶段已有 **虚拟块设备全链路 PASS**：真实 Ubuntu 24.04 raw、
  240GB 稀疏目标、真实项目 clone/verify（无 simulation 标志、loopback SSH）、
  完整离线修复、GPT/ext4 扩容、真实 GRUB/initramfs、SeaBIOS 二次启动登录。
  这仍不是物理 SSD 验收。
- PR #2 保持 Draft，未合并。
