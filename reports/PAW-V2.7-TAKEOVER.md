# PAW Migration Kit v2.7 云端接管报告

生成时间：2026-11-09 UTC
接管分支：`fix/v2.6.2-final-readiness`（从 `fix/v2.6.1-migration-readiness` 的 `0128110` 建立）
基线主分支：`main` / `0d6aefd`
关联 PR：#1（Draft，未合并，保持原状）
当前状态：代码审查与云端取证完成；P0 整改进行中。本文不把任何虚拟结果写成真实硬件结果。

## 1. 云端工作环境

- Ubuntu 24.04.4 LTS，x86_64，2 vCPU，约 7.4 GiB 内存，根文件系统约 50 GiB（接管时可用约 24 GiB）。
- 当前会话为非 root 用户，`sudo` 被 `no_new_privs` 限制，不能在本机安装系统包或执行需要 root 的 loop/mount/QEMU 测试。
- 已具备：Git、GitHub CLI（账号 `riser-lang`，仓库 `ADMIN`）、Python 3.11、Bash、curl、jq、zstd、rsync。
- 本机缺少：QEMU、ShellCheck 系统包、Codex CLI。ShellCheck 已改用官方发布版解压到用户目录，仅用于静态检查。
- 因此：**GitHub Actions 的 Ubuntu 24.04 runner 是当前唯一可执行完整构建、loop 虚拟盘和 SeaBIOS/TCG 启动测试的平台**。本机负责代码、静态检查、GitHub 操作、产物核对和交付整理。

## 2. 仓库、分支与 PR 真实状态

| 项目 | 状态 |
|---|---|
| 仓库 | `riser-lang/paw-migration-kit`，Public，未改可见性 |
| 默认分支 | `main` |
| `main` HEAD | `0d6aefd` |
| 现有开发分支 | `fix/v2.6.1-migration-readiness` |
| 现有开发分支 HEAD | `0128110` |
| PR #1 | OPEN / Draft / MERGEABLE，未合并，未改动 |
| 最近成功运行 | Run `42595201074`，Run Number 32，`workflow_dispatch`，结论 success |
| 最近成功运行分支/提交 | `fix/v2.6.1-migration-readiness` / `0128110` |
| 最新产物 | Artifact `13663178266`，`paw-live-build-test-results`，938,774,343 bytes |
| 产物过期时间 | 2026-11-12 09:50:11 UTC；接管时仍未过期 |

未从旧 `main` 重新开发。新分支以 `0128110` 为祖先，后续修改不强制回退远程更新。

## 3. 当前真实代码结构

### 3.1 启动与总控

| 文件 | 实际职责 | 接管判断 |
|---|---|---|
| `scripts/paw-lib.sh` | 状态目录、日志、JSON 转义、目标登记、授权收据、模拟文件/loop 保护、Rescue SSH 封装 | 安全边界基本正确；目标授权只校验序列号/设备路径，未绑定完整身份 |
| `scripts/paw-live-controller.sh` | 启动后汇总 PAWDATA、Live 预检、源盘、目标盘、硬件、网络状态；写 `live-readiness.json` | 只报告，不自动初始化 PAWDATA；memtest 永远无法 PASS，导致正常路径被永久阻断 |
| `scripts/paw-final-confirm.sh` | 中文最终授权、目标序列号末六位、写授权收据、调用克隆/校验/修复/扩容/首启检查 | 有基本中文界面；未展示完整网络/硬件/来源证据，未在授权前重新执行完整源盘身份复核 |
| `scripts/paw-live-preflight.sh` | 架构、内存、Live 标记、网络/块设备只读盘点 | 基本可用；没有把“真实硬件”与“虚拟环境”写入报告 |
| `scripts/paw-firstboot-check.sh` | 校验克隆校验收据、无 incomplete、目标登记、硬件 PASS | 只校验报告文本，未校验收据与当前启动/设备的绑定 |

### 3.2 PAWDATA 持久化

| 文件 | 实际职责 | 接管判断 |
|---|---|---|
| `scripts/paw-data-check.sh` | 检查挂载点、ext4、卷标、可写、最小空间 | 逻辑正确；失败时退出 2，不伪造 PASS |
| `scripts/paw-data-prepare.sh` | 手动入口：识别当前 Live 可移动介质，要求序列号末六位，调用准备脚本 | **仍是手动命令，不满足 P0-2 自动引导** |
| `scripts/paw-prepare-data-partition.sh` | 只接受 DOS/MBR Hybrid ISO，追加 MBR 主分区、格式化新分区、挂载、迁移 `/run/paw-migration` | 只支持 MBR；未覆盖 GPT Hybrid；未验证重启后持久化；未自动接入启动流程 |
| `boot/paw-data.mount` | 按卷标挂载 `/var/lib/paw-migration` | 单元存在；分区不存在时依赖手动准备 |

### 3.3 Rescue 源盘与克隆

| 文件 | 实际职责 | 接管判断 |
|---|---|---|
| `scripts/paw-rescue-key-prepare.sh` | 生成一次性 SSH 密钥、扫描并人工核对 Rescue 主机指纹 | 方向正确；未记录主机指纹到源盘身份收据 |
| `scripts/paw-source-discovery.sh` | 通过固定 Host Key SSH 读取远端 `lsblk`，核对根 UUID、50 GiB、GPT、BIOS Boot、ext4、无 rw 挂载 | **强制要求云盘序列号；Virtio 无序列号时直接失败**；缺少组合身份哈希与主机指纹绑定 |
| `scripts/paw-stream-clone.sh` | 远端 `dd | zstd` 经 SSH，本地解压写目标；记录 payload 字节；失败留 `CLONE-INCOMPLETE` | 远端压缩顺序正确；但 `restored_bytes` 是假定的源大小，没有实际解压计数；`pv` 在压缩模式下按原始大小显示进度会失真；测试只用全零 |
| `scripts/paw-stream-verify.sh` | 远端源盘 SHA256 与目标前 N 字节 SHA256 独立比较 | 逻辑正确；真实 SSH 未验证 |
| `scripts/paw-count-bytes.py` | 流式复制并原子写字节计数 | 可复用；需要增加“解压后计数”实例 |

### 3.4 硬件、内存、修复、扩容

| 文件 | 实际职责 | 接管判断 |
|---|---|---|
| `scripts/paw-hardware-preflight.sh` | SMART、只读读扫、内核 I/O 错误、温度、NVMe、CRC、内存报告 | 只接受内存 `PASS`；当前内存脚本永远 WARN，实际无法通过 |
| `scripts/paw-ssd-smart-check.sh` | `smartctl -x/-H/-c`、短测、可选长测、轮询 | 基本可用；真实 SSD 未验证 |
| `scripts/paw-ssd-read-scan.sh` | `badblocks -sv` 只读扫描 + timeout | 基本可用；真实 SSD 未验证 |
| `scripts/paw-memory-test-report.sh` | 读取 `memtest-attestation.json`，但一律 WARN | **与 P0-1 冲突：没有人工确认入口，也没有可用状态** |
| `scripts/paw-offline-repair.sh` | 只读 fsck、挂载、备份、替换 netplan、禁用 cloud-init 网络、machine-id/SSH host key、清理 Tailscale 状态、update-initramfs/grub | 真实适配逻辑较完整；模拟模式只做 fsck，未测试实际改写；未执行 `grub-install`；Netplan 仅匹配 `en*` |
| `scripts/paw-gpt-expand.sh` | `sgdisk --move-second-header`、`growpart`、`e2fsck`、`resize2fs` | 基本正确；需增加失败回滚/边界测试 |

### 3.5 网络

| 文件 | 实际职责 | 接管判断 |
|---|---|---|
| `scripts/paw-network-preflight.sh` | 链路、地址、默认路由、DNS、HTTPS、Rescue 443、NTP | 会输出本机地址到运行时报告，属运行时数据，不提交仓库 |
| `scripts/paw-network-bootstrap.sh` | Rescue 阶段只允许直连；恢复 Ubuntu 阶段可启动 Xray | 阶段隔离正确；没有真实网络/Xray/Tailscale 授权测试 |
| `scripts/paw-network-phase-select.sh` | 中文选择 RESCUE / RESTORED_UBUNTU | 可用；只写 RAM |
| `scripts/paw-xray-client-configure.sh` | 交互输入 VLESS/Reality，写 `/run`，Xray 自检 | 配置字段与模板基本正确；未测试错误配置/监听边界 |
| `scripts/paw-xray-proxy.sh` | 启动 loopback SOCKS/HTTP 代理并做 HTTPS 检查 | 依赖 systemd；未在虚拟环境验证 |
| `scripts/paw-tailscale-join.sh` | 恢复阶段直连或经 Xray，等待用户授权，检查 online | 未测试授权等待/超时/代理回退 |
| `scripts/paw-tailscale-direct-recovery.sh` | 直连可用后撤掉临时代理 | 状态转换逻辑存在；未测试 |

### 3.6 构建、CI 与公开安全

| 文件 | 实际职责 | 接管判断 |
|---|---|---|
| `scripts/build-debian-live.sh` | `live-build` 生成 Hybrid ISO，复制脚本/服务/Memtest，生成软件清单和 SHA256 | 依赖 root；本机不能跑；CI 可跑 |
| `scripts/ci/verify-debian-base.sh` | Debian CD 公钥指纹、签名、SHA256 校验 | 证据链正确 |
| `scripts/ci/stage-verified-tools.sh` | Tailscale 签名 APT 仓库、Xray 官方 release digest | 固定版本；需继续保留 |
| `scripts/ci/qemu-live-smoke.sh` | SeaBIOS/TCG 启动，等待 `AUTOSTART_GATE`，要求 BLOCKED 且 clone_started=false | 只证明虚拟启动，不证明真实主板 |
| `scripts/ci/run-pawdata-virtual-tests.sh` | ISO 追加 PAWDATA、持久化、损坏/空间耗尽 | 6 项通过；未覆盖自动引导和 GPT Hybrid |
| `scripts/ci/run-virtual-tests.sh` | mock SSH、压缩/raw、SHA、目标错误、SMART/坏块/内存注入、GPT/ext4 扩容 | 覆盖一部分；内存注入断言与当前 memory 脚本语义不一致，需复核；仅全零数据 |
| `.github/workflows/build-live-and-test.yml` | 单一 job：静态检查、Debian 校验、工具、ISO、QEMU、PAWDATA、虚拟测试、产物 3 天 | Actions 是当前主构建平台；需要新增 P0/P1 测试步骤 |

## 4. 已有证据与实际结论

### 4.1 已通过（仅限对应环境）

- GitHub Actions Run `42595201074` 整体 success。
- Debian Live ISO 构建成功；Debian 官方签名与哈希校验步骤通过。
- SeaBIOS + QEMU TCG 虚拟启动到达 `AUTOSTART_GATE`，且缺少目标/源时保持 `BLOCKED`、`clone_started=false`。
- PAWDATA 虚拟测试 6/6：追加分区、ext4 标签、卸载重挂载持久化、健康检查、缺失阻断、空间耗尽阻断。
- mock SSH 的远端 zstd、raw fallback、独立 SHA256、目标序列号错误、SSH 中断/marker、SMART FAIL、坏块、GPT/ext4 扩容等测试在该 runner 上通过。
- 当前工作区公开安全扫描和可达 Git 对象扫描通过；未发现私钥、Token、用户 IPv4、个人路径等配置模式。

### 4.2 未通过 / 尚未形成闭环

- **Memtest86+ 可信结果闭环不存在**。独立菜单存在，但没有回到 PAW Live 的中文人工确认入口；`paw-memory-test-report.sh` 对任何输入都返回 WARN。硬件报告因此无法 PASS，正常克隆流程被永久阻断。
- **PAWDATA 仍要手动运行命令**，不满足“自动引导初始化”；且只支持 DOS/MBR。
- **源盘身份强制序列号**，Virtio 无序列号场景不满足 P0-3。
- **压缩流没有实际解压后字节计数**，报告中的 `restored_bytes` 只是源大小的复制；测试数据为全零，不能证明混合数据路径。
- **最终授权界面信息不完整**，且没有在授权前重新执行完整源盘身份复核。
- **离线修复模拟模式没有执行真实改写路径**，`grub-install` 未执行，Netplan 只匹配 `en*`。
- **真实 Rescue SSH、真实云盘、真实 SSD、真实 TF 卡、真实主板启动、真实 PAW 迁移全部未执行**。

### 4.3 需要特别说明的测试语义

`run-virtual-tests.sh` 中内存注入用例要求 `memory-test.json` 出现 `FAIL`，但当前 `paw-memory-test-report.sh` 只会写 WARN。接管时必须用最新 artifact 的真实报告核对这一断言是否确实执行；不能因为 job 显示 success 就推断记忆测试已通过。该问题纳入 P0-1 一并修复：内存未完成/错误/人工确认必须是不同状态，且测试必须断言真实状态。

## 5. 与生产环境的边界

接管期间未连接旧 VPS，未执行 SSH，未进入 Rescue Mode，未读取生产整盘，未修改 PAW 数据库/服务/Tailscale/Funnel/Xray/Nginx/防火墙/COS。后续所有克隆、修复、扩容、故障注入均只使用 `tests/virtual` 下的文件或 loop 设备。任何新的生产访问都需要用户单独授权。

## 6. 下一步执行顺序

1. **P0-1**：新增 `paw-memtest-confirm.sh` 中文人工确认；写 `OPERATOR_CONFIRMED` 收据，绑定当前 Live boot_id、目标 SSD 序列号和确认时间；区分 `PASS`（机器可信证明）、`OPERATOR_CONFIRMED`、`WARN`、`FAIL`；硬件门槛只接受前两者。
2. **P0-2**：新增自动引导服务/脚本，启动时识别当前 Live 介质，展示型号/容量/序列号，确认末六位后追加分区；MBR 与 GPT Hybrid 均支持；只格式化新分区；迁移临时状态；卸载重挂载验证持久化。
3. **P0-3**：移除源盘序列号硬门槛；有序列号则记录，无序列号则生成组合身份哈希（固定 Host Key 指纹、根 UUID、父盘唯一匹配、容量、GPT 布局、BIOS Boot、发现时间），并把主机指纹写入收据。
4. **P0-4**：增加解压后字节计数；压缩模式进度不再伪装百分比；SSH 中断/短读/计数不一致全部保持 `CLONE-INCOMPLETE`；测试改用全零+随机+文本混合数据。
5. **P0-5**：授权界面展示源/目标/容量/序列号/硬件/网络/数据来源/数据损失；输入目标序列号末六位；授权前重新执行源盘与目标盘身份复核。
6. **P1**：Netplan 改为覆盖 `en*`/`eth*`/`r8169`；离线修复在 loop ext4 上执行真实改写测试并增加 `grub-install`；补充网络失败、Xray 错误配置、Tailscale 等待、回滚测试。
7. 触发新分支 Actions，下载并核对 ISO SHA256、测试报告和产物；更新状态/阻断/验收文件；保持 PR #2 Draft。

## 7. 当前结论

项目已有可构建、可虚拟启动、可虚拟克隆的扎实基线，但距离“可安全交付的 PAW 自动迁移启动介质”仍差 P0-1 至 P0-5 的闭环，以及 P1 的真实适配测试。当前不能标记 READY，也不能写真实 TF 卡或连接生产环境。

---

# 第二轮接管（2026-11-10 UTC）

## 8. 本轮工作环境（与第一段不同，必须记录）

第一段的云端工作站是 Ubuntu 24.04 且带非 root 沙箱。本轮接手的工作站是
**Windows 11 家庭版（build 26200）**：i5-12450H（8 核 / 12 线程）、15.7 GiB 内存、
C 盘剩余 46.6 GiB、D 盘剩余 95.7 GiB；无 WSL 发行版、无 QEMU、无 ShellCheck、
无 Docker；有 Git、GitHub CLI 2.103.3（账号 `riser-lang`，`repo` 权限）、
Python 3.11、Git Bash 5.3.9（cygwin）、OpenSSH。

因此本轮的分工是：

- 本机：读代码、改代码、静态检查与**实际 `bash -n`**、Git/GitHub 操作、Actions
  触发、Artifact 下载与**真实 SHA256 复核**、文档与交付整理。
- GitHub Actions（ubuntu-24.04，root，含 loop / PTY / QEMU）：唯一的完整执行平台。

不得因为换了工作站就把“本机没跑”写成“通过”。

## 9. 本轮实际发现的缺陷（P0-5 级）

`boot/paw-console.service` 使用 `StandardOutput=journal`。菜单脚本自己用 tty1 fd
打印，但**从菜单进入的六个操作员脚本仍用裸 `printf` 写面板**，面板只进 journal：

| 脚本 | 面板内容 | 后果 |
|---|---|---|
| `paw-final-confirm.sh` | 数据损失警告、源系统、源盘序列号/组合身份、固定主机指纹、目标 SSD 型号容量序列号、数据来源、恢复边界 | 屏幕上只剩“输入最后 6 位”，操作员在看不到数据损失说明的情况下授权整盘覆盖 |
| `paw-memtest-confirm.sh` | 三选一含义、登记摘要、启动 ID | 操作员看不到选项含义 |
| `paw-target-discovery.sh` | 候选磁盘清单（含序列号） | 提示要求“按屏幕显示的序列号输入”，而屏幕上并没有序列号 |
| `paw-rescue-key-prepare.sh` | 一次性公钥、候选 SHA256 主机指纹 | 操作员无法复制公钥、无法核对指纹 |
| `paw-network-phase-select.sh` | R / U 的含义 | 阶段选择无说明 |
| `paw-source-discovery.sh` | 根 UUID 的用途与范围 | 只有一个裸提示 |

这是“用户不会用 Linux、关键确认必须在中文界面完成”这条要求上的真实破口，不是
排版问题：授权界面缺的正是最关键的“会丢什么数据”。

## 10. 本轮修复

- `scripts/paw-tty-lib.sh`
  - 新增 `paw_tty_open_optional()`：显式 `PAW_INTERACTIVE_TTY` 优先；否则当
    `/dev/tty1` 是字符设备**且**继承的 stdin/stdout/stderr 至少一个是 tty 时走
    原有严格绑定；都不是则回退到继承 stdio。
  - 回退时不写 tty1 会话记录（`paw_tty_record` 直接返回），并在日志显式说明
    “这不是实机 tty1 路径”，防止把 CI 截图当成硬件证据。
  - 交互输入 fd 显式化为 `PAW_TTY_IN_FD`（默认 3）。
  - 新增 `paw_tty_read_secret()`：同一 fd、同一 300 秒超时、不回显。
- 六个脚本改为 `paw_tty_say / paw_tty_prompt / paw_tty_read / paw_tty_read_secret`，
  面板文本与原内容一致（信息未删减），并新增 ASCII 屏幕标记：
  `PAW-TTY1-FINAL-PANEL/PROMPT/OK/BAD/TIMEOUT/ABORTED`、
  `PAW-TTY1-MEMTEST-*`、`PAW-TTY1-TARGET-*`、`PAW-TTY1-RESCUE-*`、
  `PAW-TTY1-NETPHASE-*`、`PAW-TTY1-SOURCE-*`。
- 超时与中断都走“安全停止、不写入”路径（授权超时 `exit 2`，序列号不匹配 `exit 1`）。
- `paw-data-prepare.sh` 保持严格绑定：静态断言新增“PAWDATA 不允许回退”。
- `scripts/ci/run-tty-virtual-tests.sh`：静态断言 37 → **55**，新增覆盖
  “无隐式 stdin 提示”“统一可选绑定”“标记存在”“PAWDATA 不回退”。
- 工作流新增 `artifacts/iso-identity.txt`（ISO 字节数 + SHA256），交付核对不必
  先下载 1 GB。

## 11. 本轮验证（只写实际跑过的）

| 项 | 结果 | 出处 |
|---|---|---|
| Run `42775846760`（HEAD `c211dc9`） | success | Actions，全部步骤通过 |
| Run `42778468039`（HEAD `2c2a37d`） | success | Actions，20m37s，全部步骤通过 |
| 本机 `bash -n` 全脚本 | PASS，0 语法错误 | Git Bash 5.3.9 实跑 |
| 本机 TTY 静态断言 | 55 passed / 0 failed | `run-tty-virtual-tests.sh` 实跑 |
| 本机 PTY | BLOCKED（Windows Python 无 `termios`） | 不作为 PASS |
| CI TTY 套件 | 56 passed / 0 failed / 0 blocked（含 15 PTY） | Run `42778468039` |
| CI 其余套件 | PAWDATA 12、故障注入 35、修复 15、网络 17、finalize 36、CJK 字体 1、QEMU CJK 4 例 71 断言，均 0 failed | Run `42778468039` |
| ISO（Run `42747871471`）独立复核 | `2295eb0a…39336d` 与侧车一致；953,155,584 bytes | 本机下载后 `Get-FileHash` |
| ISO（Run `42778468039`） | `17789c04…6e0363`；953,155,584 bytes | 构建日志 `iso-identity.txt` |

## 12. 本轮仍未验证（不得写成通过）

- 真实 ASUS 主板屏幕与键盘上是否真的显示这些新面板（QEMU CJK 套件只覆盖菜单与
  PAWDATA 面板，未覆盖新授权面板）。
- 真实 TF 卡写入与回读、真实主板启动。
- 真实 SSD SMART / 只读扫描 / 温度，真实内存 Memtest86+ 运行与目视确认。
- 真实腾讯云 Rescue Mode SSH 与真实整盘克隆。
- ISO 字节级可复现（两次构建同尺寸不同 SHA256）。
- 本机 PTY 执行（环境限制，由 CI 覆盖）。

## 13. 下一轮建议顺序

1. 给 QEMU CJK 套件增加一个 `final` 用例：注入完整的源/目标/硬件/内存 fixture，
   证明授权面板在 tty1 上以真实字形出现（目前只有静态断言）。
2. 把 GRUB 修复从 stub 提升为在 loop 上真实执行 `grub-install --target=i386-pc`
   （CI 已装 `grub-pc-bin`），以关闭“GRUB 修复只有模拟证据”这一项。
3. 复核 `growpart` 对“根分区不是最后一个分区”的克隆布局，给出明确阻断而不是
   依赖 growpart 报错。
4. 真实硬件阶段：TF 卡写入、主板启动、SSD/内存、Rescue 与正式迁移，全部需要
   用户在场并单独授权。
