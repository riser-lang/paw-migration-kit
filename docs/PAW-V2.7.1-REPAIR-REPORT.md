# PAW v2.7.1 第一段遗留问题修复报告

执行日期：2026-11-10 / 2026-11-11（UTC）
历史证据分支：`fix/v2.6.2-final-readiness`（下文第 1–6 节保留该分支的历史记录）
当前干净交接分支：`vm/ds-clean-handover-20261110`
当前分支基线：`d64071251bb3075d9cb26a967dfcba6cf139250a`（远端最新开发分支）
历史实现提交：`376c35d00a943941e64ff2b38c627e9657a47cc9`
PR #2：保持 **Draft**，未合并。
Stage 3：**COMPLETE**（26 步均有真实执行证据：18–25 步 PASS 日志 + `target_boot`
独立 QEMU/SeaBIOS 复核，含真实块设备克隆、离线修复、扩容、自动重启）。Stage 4
最终 ISO：**已构建并复核**（Run `42941005270`，代码 HEAD `24c13f7`；ISO
953,155,584 bytes，SHA256
`822ae2c1b41768d0dcb48ab6494aa273dc06ea6be7121baac30a3791cf8c4c09`）。
真实硬件仍 OPEN。

## 0. 2026-11-10 干净交接与 P0-1 字体失败安全门禁

### 0.1 环境接管

- 旧 PAW 现场已按清单隔离后删除；删除明细、释放空间和保留工具见
  `reports/DS-CLEAN-ENVIRONMENT-TAKEOVER.md`。没有删除整个 `$HOME`，没有删除
  非 PAW 项目，没有触碰生产 VPS、生产磁盘、真实 TF 卡、Tailscale、Funnel、
  Xray、Nginx、443、防火墙或 COS。
- 新工作区从 GitHub 重新克隆到 `/home/agentuser/paw-migration-kit`，基线是
  `d640712`，没有复用旧工作树/旧未提交修改。
- 当前 VM 的 bash 执行通道仍设置 `NoNewPrivs: 1` 且 `sudo -n` 失败；因此本机
  只能执行不需要 root 的测试。需要 root/loop 的测试仍由 GitHub Actions 执行，
  本机结果如实标 BLOCKED，不冒充 PASS。

### 0.1 Stage 3 对离线修复的补充验证（2026-11-11）

Stage 3 在重建的 Ubuntu 24.04 目标盘上真实执行了完整
`paw-offline-repair.sh`，不是 loop 夹具：

- `offline-repair.json`：`status=PASS`、`simulation=false`、
  `grub_install=i386-pc`、`backup_path` 指向客机
  `/opt/paw-migration/tests/stage3/state/backups/offline-repair-20261111T011718Z`；
- netplan DHCP `e*`、cloud-init 网络禁用、旧 udev 覆盖禁用、machine-id/SSH
  host key 重新生成、clone-local Tailscale 状态清理、initramfs 加入实际存在的
  ahci/r8169、`update-initramfs` 与 GRUB 配置重建；
- `authorized_keys_touched=false`、`PAW_application_data_touched=false`；
- 修复后目标盘由 SeaBIOS 二次启动到 `ubuntu login:`；宿主证据副本
  `evidence/stage3-target-second-boot.log` SHA256
  `8fd245911592108c82df0cc9fb97c6266418a3259ee9c904eda2d2b1e70fa565`。

因此“完整项目离线修复未在真实克隆目标上执行”的旧缺口已在虚拟块设备范围内
关闭；真实 SSD 现场修复仍 OPEN。

### 0.2 P0-1 实现

**原则：只有本次启动、fbcon 已绑定、主 16x16 PSF2 字体的 manifest/实际
SHA256 一致、`setfont` 返回 0、且报告为 `PASS`，才允许破坏性磁盘写入。
8x16 回退只能是 `WARN`，永远不能打开写门禁；缺失、损坏、哈希不符、加载失败、
报告缺失/过期一律 `FAIL`/阻断。只读诊断仍允许。**

新增和修改：

- `scripts/paw-font-gate.py`：写门禁校验器。拒绝旧 schema、非 `PASS`、非
  `fbcon`、`fbcon_bound` 非 true、boot_id 不一致、tty 不符、字体路径不是
  `paw-cjk-16x16.psf`、大小/SHA256/manifest 不符、`setfont_exit_code != 0`，
  以及 PSF2 头部不是 512 槽/16x16/32 字节字形/带 Unicode 表/表有终止符。
- `scripts/paw-console-font.sh`：重写为 `paw.console-font.v2` 报告。PASS/WARN/FAIL
  所有路径都先原子写报告再退出；WARN（vgacon 8x16）退出 0 供只读诊断，FAIL
  退出非零。报告记录 `boot_id`、`fbcon_bound`、`fbcon` 名称/分辨率、字体实际
  与 manifest 期望 SHA256、`setfont` 退出码/输出。
- `scripts/paw-lib.sh`：新增 `require_console_font_pass`，并在
  `require_sim_or_enrollment` 的真实路径最先调用。`paw-stream-clone.sh`、
  `paw-offline-repair.sh`、`paw-gpt-expand.sh` 因此都在动盘前过门禁。
- `scripts/paw-final-confirm.sh`：在显示一次性破坏性授权面板前过门禁；没有
  PASS 就不出现授权输入。
- `scripts/paw-prepare-data-partition.sh`：在任何 `sfdisk`/`sgdisk`/`mkfs`/
  mount 写操作前过门禁。
- `boot/paw-data-init.service`、`boot/paw-console.service`：显式
  `After=paw-console-font.service`；字体服务原有 `Before` 顺序保留。
- `scripts/ci/font-gate-tests.py` + `scripts/ci/make-font-gate-fixture.py`：
  26 项故障注入，覆盖 PASS、8x16 WARN、缺字体、字体损坏、manifest 哈希不符、
  `setfont` 失败、报告缺失、boot_id 过期、WARN 状态、vgacon 冒充、fbcon 未绑定、
  非零退出码、8x16 冒充主字体、manifest 缺失，以及三个破坏性入口调用断言。
- `.github/workflows/build-live-and-test.yml`：新增
  `Run console-font fail-closed gate fault injection`，并把报告加入测试汇总。
- `scripts/ci/run-virtual-tests.sh` 在 `PAW_SIMULATION=0` 的 loop 授权测试中
  导出合成的同启动 PASS fixture；`tests/qemu/paw-cjk-final-probe.sh` 把门禁指向
  真实 Live 字体报告，避免测试夹具覆盖真实报告。

### 0.3 已执行与未执行

本机实际执行（不冒充 CI/实机）：

- `font-gate-tests.py --out artifacts`：**26 assertions, 0 failed**。
- `run-finalize-virtual-tests.sh`：**36 passed, 0 failed**。
- `run-tty-virtual-tests.sh`：静态 **55 passed, 0 failed**；PTY 1 项 BLOCKED
  （本机 `/dev/ptmx` 不可用）。
- ShellCheck 0.11.0 `--severity=error` 无命中；Bash `-n`、Python compile、
  `PUBLIC-SAFETY=PASS`、`PUBLIC-HISTORY=PASS`（849 objects）。

未执行/未声称：

- 新分支的 GitHub Actions 已实际运行并暴露回归：Run `42812469612` 字体槽位
  超限，Run `42817841755` 误判 `(M) frame buffer device` 为未绑定 fbcon。
  后者已由提交 `4572280` 修复；Run `42824906347` 因共享 concurrency 排队后
  取消，提交 `4af304e` 按分支隔离。Run `42825407549`（`4af304e`）已 **SUCCESS**：
  font gate 26/26、CJK 25/25、PAWDATA 12/12、虚拟故障 39/39、repair 19/19、
  network 17/17、finalize 36/36、TTY 56/56；测试 ISO SHA256
  `c34cb13712acbe49247fadf3f088a1a4d9765d481303df6e2856c26da2e068fb`。旧 Run
  `42804949796` 只对应 `bf1a705`，不能当作新分支 CI 结果。
- 真实 ASUS 屏幕、真实 TF 卡/SSD、真实腾讯云 Rescue 和正式迁移全部 OPEN；
  最终发布 ISO 已由 Run `42941005270` 构建并复核（SHA256
  `822ae2c1b41768d0dcb48ab6494aa273dc06ea6be7121baac30a3791cf8c4c09`）。
- 第二阶段：真实 Ubuntu 24.04 raw → 240GB 稀疏虚拟盘，项目 clone/verify（显式
  `PAW_SIMULATION=1`）、GPT/ext4 扩容、真实 `grub-install`/`update-grub`/
  `update-initramfs`、QEMU/SeaBIOS 启动及无 seed 第三次启动登录已完成；生产块/SSH
  clone 入口和完整 `paw-offline-repair.sh` 仍未执行，故记为
  **VIRTUAL_BOOT_PASS / BLOCK_CLONE_PATH_OPEN**。证据：
  `reports/PAW-STAGE2-REAL-UBUNTU-BOOT-20261110.md`。
- Stage 3 已完成（26 步均有真实执行证据；`target_boot` 另有独立 QEMU/SeaBIOS
  复核到 `ubuntu login:`）；Stage 4 最终 ISO 已由代码 HEAD `24c13f7` 的 Run
  `42941005270` 构建并复核，SHA256
  `822ae2c1b41768d0dcb48ab6494aa273dc06ea6be7121baac30a3791cf8c4c09`。见
  `PAW-MIGRATION-BLOCKERS.md`。

## 1. 本轮做了什么（历史，`fix/v2.6.2-final-readiness`）

## 1. 本轮做了什么

只处理第一段遗留问题，不重写已经通过的 finalize / tty1 核心逻辑：

1. **P0 中文控制台字体**：新增 GNU Unifont 16x16 PSF2 字体栈，在 fbcon
   （内核 framebuffer 控制台）上加载，保留 `/dev/tty1` 单一 fd 和原键盘路径。
2. **P0 完整 CI 回归**：工作流补齐 CJK 字体校验、CJK QEMU 显示器/键盘套件，
   并把第一段全部测试放进同一次 `workflow_dispatch` 运行。
3. **P0 sudo / losetup 矛盾调查**：确认是本机工具层 Landlock 沙箱设置
   `NoNewPrivs=1` 导致，不是容器限制，也不是 sudo 配置错误；root 虚拟磁盘测试
   改由 GitHub Actions runner 执行。
4. **P1 回归**：Finalize 36 项、TTY 静态检查、PTY（CI 强制）、QEMU tty1 全部保留。
5. **报告**：新增/更新 REPAIR / TEST / BLOCKERS / USER-GUIDE 四份文档。

没有执行真实克隆、没有触碰旧 VPS/生产 PAW/真实 TF 卡/真实硬盘，没有修改
Tailscale、Funnel、Xray、Nginx、443、防火墙、COS，没有删除历史 Artifact，
没有修改仓库可见性，没有合并 PR #2。

## 2. P0 中文控制台：方案与实现

### 2.1 先验证显示环境，再选方案

实际检查结果（证据见 TEST-REPORT）：

| 环境 | 内核 | `/dev/fb0` | 结论 |
|---|---|---|---|
| 旧 QEMU 测试盘（cloud 内核） | 6.12.115+deb13.1-cloud-amd64 | 无 | `CONFIG_DRM is not set`，`FB_VESA/UVESA` 关闭，SeaBIOS 下只有 EFI FB；vgacon 只能 8x16 ASCII |
| 本轮本地 QEMU | 6.12.94+deb13-amd64（generic） | `bochs-drmdrmfb` 1280x800 | SeaBIOS + `-vga std` 可走 bochs DRM → fbcon |
| CI Live ISO 内核 | Debian generic `linux-image-amd64` | 由 bochs DRM 提供（CI QEMU 验证） | `DRM_BOCHS=m`、`DRM_FBDEV_EMULATION=y`、`FRAMEBUFFER_CONSOLE=y`、`FB_VESA=y` |
| ASUS B85M-G Plus Legacy BIOS | 同上 generic | 预期 i915 KMS 提供 fb0；VESA FB 为后备 | **仍需现场验收** |

关键结论：

- vgacon 的字库是 8 像素宽、256/512 槽，不能靠“装一个大字体”显示中文。
- 当前 QEMU 的 cloud 内核完全没有 DRM/VESA framebuffer，不能用于验证 fbterm；
  必须换 generic 内核并真正启动 fbcon。
- ASUS B85M-G Plus 的 Haswell iGPU 在 Legacy BIOS 下由 i915 KMS 提供 framebuffer；
  Debian generic 内核同时编入 `FB_VESA`，作为极端后备。现场仍需确认。

### 2.2 方案比较

| 方案 | 评估 | 结论 |
|---|---|---|
| A. fbterm + CJK 字体 | fbterm 要自己占有 `/dev/tty1` 和 `/dev/fb0`，菜单必须运行在它创建的 pty 上；会改变现有“同一个 `/dev/tty1` fd”与单一占用证明，且测试内核无 DRM 时无法启动验证 | 未采用 |
| B. fbcon + 自建 PSF 字体 | 内核 framebuffer console 仍是 `/dev/tty1` 文本控制台，键盘/read/fd3 路径完全不变；16x16 字形可读；QEMU 可逐像素验证 | **采用** |
| C. 轻量图形界面 | 需要 SDL/Qt/DPI、键盘事件和 tty 抢占，资源与 Legacy BIOS 风险更高；本轮无需引入 | 未采用 |

### 2.3 实际字体方案

- 字形来源：Debian `unifont` 包的 `unifont.hex`（GNU Unifont，手工 16x16 位图）。
- 生成器：`scripts/paw-build-cjk-font.py`（仅 Python 标准库，不依赖 FreeType/PIL）。
- 产物：
  - `paw-cjk-16x16.psf`：PSF2，512 槽，16x16，**480 个 Unicode 映射**
    （95 个可打印 ASCII + 385 个运行时非 ASCII 字符）。
  - `paw-cjk-8x16.psf`：PSF1，512 槽，8x16，仅用于没有 `/dev/fb0` 的 vgacon
    应急后备；复杂汉字会被横向压缩，文档明确标注不是主路径。
- 槽位布局：ASCII 保持标准 VGA 位置（**空格必须在 32 槽**，否则内核填空格会显示
  成 `@`）；CJK 使用 0–31 和 127–511 的空闲槽。生成器在超过 512 槽时**构建失败**，
  不会静默缺字。
- 覆盖范围：生成时扫描 ISO 内全部 `paw-*.sh` / `paw-*.py` 的非 ASCII 字符；
  缺字即失败。当前 385 个非 ASCII 字符全部覆盖。
- 加载：`boot/paw-console-font.service` → `scripts/paw-console-font.sh`
  - `After=systemd-vconsole-setup.service`，`Before=paw-data-init.service paw-console.service paw-preflight.service getty@tty1.service`
  - 不声明 `TTYPath=`，不抢占交互终端；只 `setfont -C /dev/tty1 <font>`
  - 有 `/dev/fb0` 且 fbcon 已绑定时加载 16x16；没有 fb0 时加载 8x16 并记录
    `mode=vgacon-fallback`、`status=WARN`（只读诊断，禁止写盘）
  - 写 `/run/paw-migration/reports/console-font.json`，当前 schema 为
    `paw.console-font.v2`（boot_id、fbcon_bound、模式、fb 名称/分辨率、字体实际/
    manifest 期望 SHA256、setfont 退出码）；串口/journal 保留诊断日志
- 字体包版本：Debian trixie 快照 `unifont 1:15.1.01-1`（CI 的
  `software-packages.lock` 为准；本地验证用 15.1.01）。

### 2.4 ISO 构建集成

- `configs/live-build/package-lists/paw.list.chroot` 增加 `kbd`、`unifont`。
- `scripts/build-debian-live.sh`：
  - 复制字体生成器与 `paw-console-font.sh`；
  - 复制 `paw-console-font.service` 并 enable；
  - 新增 `0550-paw-console-font.hook.chroot`：在 chroot 内用同一快照的
    `unifont.hex` 生成两个 PSF 与 manifest；
  - 复制后 `chmod 0755` 所有 PAW 脚本，避免 checkout 权限位导致 unit 无法执行。
- 字体产物不提交仓库（二进制），由构建生成；`check-public-safety.py` 保持 PASS。

## 3. P0 GitHub Actions 完整回归

工作流：`.github/workflows/build-live-and-test.yml`
历史运行：**Run ID `42741425053`**（HEAD `376c35d`）；后续历史成功 Run 为
`42804949796`（HEAD `bf1a705`）。这些结果属于历史分支，不是当前
`vm/ds-clean-handover-20261110` 的新 CI 结果。当前分支已实际运行 CI：Run
`42812469612` 失败于字体槽位 418/417，Run `42817841755` 失败于
`(M) frame buffer device` 名称误判；修复后 Run `42825407549`（HEAD
`4af304e`）全绿，含 gate 26/26、CJK 25/25、TTY 56/56。不得把旧 Run 写成
新门禁的 CI 证据。

本轮工作流新增：

- `Validate generated CJK console font`：真实解析 PSF2/PSF1、空格槽、Unicode 表、
  全量运行时字符覆盖。
- `Run framebuffer CJK tty1 display and keyboard suite`：从真实 ISO 的 squashfs
  生成一次性 ext4 测试盘，用 ISO 内核/initrd、SeaBIOS + TCG + `-vga std` 启动，
  跑 ok / bad / timeout / render 四例，QEMU `sendkey` 注入键盘，`screendump` +
  PSF 字形逐像素匹配（不使用 OCR）。
- 保留原有 ShellCheck、Bash 语法、Python compile、PowerShell parse、Public safety、
  Public history、Debian 签名、Xray/Tailscale 校验、ISO 构建、SeaBIOS/TCG smoke、
  PAWDATA 12 项、克隆/故障注入 35 项、离线修复 15 项、网络 17 项、Finalize 36 项、
  TTY 静态检查、PTY（`PAW_REQUIRE_PTY=1`，不可用即失败）。
- 新增 `Summarize real test counts` 步骤，打印每份报告真实计数；缺报告会显式
  打印 `MISSING`。

## 4. P0 sudo / losetup 矛盾调查结论

**结论：本机工具执行通道（DSH bash 工具的 Landlock 沙箱）设置了
`PR_SET_NO_NEW_PRIVS=1` 并清空有效 capability；不是容器限制，不是 sudoers 配置
错误，也不是宿主 KVM 的 loop 设备缺失。**

证据（2026-11-10 02:15 UTC，详见 TEST-REPORT）：

```
id -un → agentuser
id     → uid=1002(agentuser) gid=1003(agentuser)
sudo -n true → sudo: The "no new privileges" flag is set ... rc=1
/proc/self/status → NoNewPrivs: 1, CapEff: 0000000000000000
父 node 进程     → NoNewPrivs: 0（工具 wrapper 给每条 bash 命令加了 NNP）
systemd-detect-virt → kvm
/proc/1/cgroup   → 0::/init.scope（无 docker/容器 cgroup）
/dev/loop-control、/dev/loop0 均存在
losetup --find → /dev/loop0（读查询可用）
losetup --find --show <8MiB file> → Permission denied（attach 需要 CAP_SYS_ADMIN）
```

每条命令 stderr 都出现 `landlock-run: partial enforcement (older Landlock ABI)`，
说明是工具层 Landlock wrapper；wrapper 为了让 Landlock 生效必须设置 NNP=1。
一旦设置 NNP 就不可逆，setuid `sudo` 无法再提权；同时有效 capability 为空，
`losetup` attach 必然失败。

因此：

- **没有**修改宿主安全策略、没有尝试绕过沙箱。
- 本机只把 loop/root 测试标记为 **BLOCKED（环境）**，不冒充 PASS。
- 需要 root 的虚拟磁盘测试全部交给 GitHub Actions runner；CI 的
  `run-pawdata`/`run-virtual`/`run-repair`/`run-network` 使用 `sudo` 真实执行
  loop 测试。
- 2026-11-10 本次干净接管再次实测：当前 bash 执行通道仍然
  `NoNewPrivs: 1`、`sudo -n id` 失败，`losetup --find --show` 无法 attach。
  不能声称本机 `sudo` 可用；需要 root 的证据只能来自 CI runner。

## 5. P1 回归结论

- Finalize：本机 36 passed / 0 failed；未改 finalizer 逻辑。
- TTY 静态：本机 55 passed / 0 failed（本地 pty 不可用 → PTY 项 BLOCKED）；
  CI 以 `PAW_REQUIRE_PTY=1` 强制 PTY。
- QEMU tty1：CI 5 例 96 断言全过（Run `42804949796`，含授权面板用例）。
- 中文字体加入后，交互仍使用 `paw-tty-lib.sh` 的 `exec 3<>/dev/tty1`、`read -u 3`；
  状态文件仍记录 `tty_path=/dev/tty1`、`menu_tty=input_tty=/dev/tty1`、
  `max_holders=1`。
- Tailscale 登录仍写报告文件，不占用交互终端；串口/journal 诊断日志保留。

## 6. 交付边界

本轮**没有**：

- 执行第二段开发；
- 构建“最终发布 ISO”（CI 构建的是测试 Live ISO）；
- 写入真实 TF 卡或任何真实硬盘；
- 访问/修改旧 VPS、生产 PAW、Tailscale/Funnel/Xray/Nginx/443/防火墙/COS；
- 删除历史 GitHub Artifact；
- 修改仓库 Public/Private；
- 合并 PR #2。

真实 ASUS 主板显示器/键盘、真实 `systemctl reboot`、最终发布 ISO 哈希与现场
验收仍是 **OPEN**，见 `PAW-V2.7.1-BLOCKERS.md`。
