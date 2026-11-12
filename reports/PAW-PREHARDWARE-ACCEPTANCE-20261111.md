# PAW v2.8 预硬件验收报告（P0/P1 + 补充三/四）

- 日期：2026-11-12（UTC）
- 分支：`vm/ds-prehardware-acceptance-20261111`
- 代码基线：初始 `b9f5c5b`；本报告对应分支 `vm/ds-prehardware-acceptance-20261111` 上的修复提交（见 `git log`）
- 执行模型：DS V4.1 Flash
- 环境：QEMU/TCG、Debian Live 6.12.113+deb13-amd64、4 vCPU（宿主 2 核）、3 GiB guest RAM
- 范围：**仅虚拟块设备与模拟网络端点**
- 状态：**虚拟全链路 CHAIN_PASS；生产/物理项 NEEDS_TEST/OPEN**

## 1. 结论摘要

| 层级 | 状态 | 依据 |
|---|---|---|
| P0 修复（Memtest 菜单、授权事务、source 只读挂载门） | **PASS（虚拟）** | 26/26 P0 套件；真实 ISOLINUX 菜单选择；完整 Memtest pass |
| P1 修复（O_DIRECT、NTFS、GRUB/by-id、AHCI/r8169、SMART、firstboot 等） | **PASS（虚拟/静态）** | 24/24 P1 套件 |
| 补充三：VLESS/Tailscale 双阶段 | **PASS（模拟）** | 25/25 VLESS 套件 |
| 补充四：武汉家宽端口/公网访问架构 | **设计 PASS；生产 NEEDS_TEST** | 策略文件 + 开发机负向审计；未登录生产 |
| 全链路预硬件迁移（12 GiB source → 240 GB target） | **PASS（虚拟，`CHAIN_PASS`）** | `PAW3_CHAIN_RESULT=PASS`；克隆目标到 `ubuntu login:`；独立 SHA256；39/39 |
| 物理 ASUS/TF/SSD/Rescue/生产 | **OPEN / NEEDS_TEST** | 本会话未触碰 |

本报告不把 QEMU、loop、mock SSH、模拟 Tailscale/Xray 或操作员目视确认写成物理
或密码学证明。

## 2. P0 修复与证据

### P0-1 Memtest86+ 真正从启动菜单进入

- 根因：`memtest.cfg` 误用 `kernel` 指令加载 bzImage，ISOLINUX 无法按 Linux
  bzImage 方式启动；且没有固定二进制来源。
- 修复：改为 `linux /boot/memtest86+x64.bin`；固定 Memtest86+ v7.20，
  SHA256 `487bfe56b84f2016b12f393641f1acb765ef0b648c71ea9a2e3d42b62411f71f`；
  `build-debian-live.sh` 在构建时校验哈希与版本字符串。
- **真实菜单验证**：`tests/prehardware/memtest-isolinux-menu.py` 把 release ISO
  作为 CD 挂载，SeaBIOS 启动 ISOLINUX；3 s 时按顶层热键 `m`
  （`^Memory test (Memtest86+ x64...)`）并回车。前后 screendump 哈希不同，
  证明进入的是菜单项而不是 `-kernel` 直启。
  - `RESULT=PASS`：`Memtest86+ v7.20`、`Status: Testing`、`Errors: 0`。
  - serial SHA256 `c36cfeb580d9e807515bb5a634468f53f674d0512bbd195943db39d1c3b569cd`
  - menu SHA256 `105c6d3ae1aae5b508bce5759adef6f09d1de9a0347e732554889f5ba23b5d91`
  - selected SHA256 `67e6088140067abc24ad1369472a47a096ab46b8a50596ef3c09a80f88ddc0dc`
- **完整一遍**：先前同一固定二进制的 3 GiB QEMU 运行在
  `Time: 0:22:30` 首次达到 `Status: Pass`、`Pass: 1`、`Errors: 0`；
  截图 `full-pass-1.txt` 为 `Time: 0:24:03` 的持续 Pass
  （`memtest-full-3g/serial.log` SHA256
  `8539326b79c0ae4b83e93150e5bc539bf3c57b5e03d2dcfb6cd11e20392cdf69`）。
- 证据汇总：`reports/evidence/prehardware-20261111/memtest86-20261111.txt`。
- 边界：虚拟内存测试；真实 ASUS DIMM 仍 `NEEDS_TEST`。链内
  `OPERATOR_CONFIRMED` 是操作员确认，`trust_level=operator_attestation_not_cryptographic`。

### P0-2 授权/事务/过期

- 新增 `scripts/paw-transaction.py`，状态机：
  `AUTHORIZED → CLONING → CLONE_INCOMPLETE/CLONE_VERIFIED → REPAIRING →
  REPAIRED → EXPANDING → READY_TO_BOOT → COMPLETE`，失败为 `FAILED`。
- 六小时 expiry 只在 clone 开始前强制；clone 中断后仍允许在有效授权下完成
  verify/repair/expand（不会因为跨过 6 小时而把已完成克隆判废）。
- clone 在任何 marker/目标写入前校验授权、目标 serial/capacity、事务阶段；
  旧授权不能重启新事务；目标身份变化阻断 finalizer。
- P0 套件 26/26 PASS，证据
  `reports/evidence/prehardware-20261111/p0-remediation-report.txt`。

### P0-3 source 只读挂载 fail-closed

- `scripts/paw-source-mount-check.py` 解析 `/proc/self/mountinfo`；读改写、
  错误/缺失 `findmnt`、异常 mountinfo 均阻断；未挂载块设备才放行。
- source discovery 不再吞掉 `findmnt` 错误。
- P0 套件覆盖 7 个 mount 场景，全部 PASS。

## 3. P1 修复与证据

| 修复 | 实现/证据 |
|---|---|
| O_DIRECT 独立回读 | `paw-stream-verify.sh` 使用 `iflag=direct` 并记录 `target_readback_method` |
| NTFS/Windows 磁盘排除 | `paw-target-discovery.sh` 识别 `ebd0a0a2-` Microsoft basic data + NTFS，拒绝误选 |
| GRUB/initramfs 非交互 | `DEBIAN_FRONTEND=noninteractive`，`GRUB_DISABLE_OS_PROBER=true`，`timeout 180` 防止卡死 |
| initramfs 模块独立核对 | `lsinitramfs` 检查 AHCI/r8169/filesystem 模块；缺失即 die |
| fstab/GRUB UUID | 修复后重新读取 root UUID/label，并检查 fstab 与 grub.cfg |
| HD4600 i915 | 检查模块存在并分类；不把 QEMU 显卡当物理 i915 |
| BIOS media order | `paw-reboot-media-check.sh` 记录 `boot_order_control`；PAW-LIVE 介质在位时禁止自动重启 |
| firstboot 语义 | `paw-preboot-handoff-check.sh` 明确 `actual_first_boot_performed=false`；真检查只在 post-boot |
| SMART PASS/WARN/FAIL | health PASS + 非零 smartctl mask 归为 `WARN/SMART_HEALTH_PASSED_NONZERO_RC`，不再假 FAIL；FAIL 永不 PASS |
| AHCI/r8169 硬阻断 | 目标内核缺 AHCI 或 Realtek r8169 时 `die`，不再只 warn |
| grub-pc by-id/debconf | 解析 `/dev/disk/by-id/*`，`debconf-set-selections` 固定 `install_devices`，`dpkg-reconfigure -f noninteractive grub-pc` 后 `debconf-show` 回读校验；lab 无 `grub-pc` 时如实记录 `grub-pc_not_installed` |
| 服务身份隔离 | `paw-service-cutover-manifest.py`：machine-id/SSH host key 必须变化，Tailscale state 不得复制 |

P1 套件 **24/24 PASS**：`reports/evidence/prehardware-20261111/p1-remediation-report.txt`。
本地 shellcheck `-S warning` 对改动脚本返回 0。

## 4. 全链路预硬件迁移

### 4.1 已完成的 12 GiB 尝试（不是 PASS）

2026-11-12T02:45–03:01Z 使用重建的 12 GiB Ubuntu 24.04.5 源盘运行：

- `live_boot`、`cpu`、`sata`、`source_os`、`console_font`、`rescue_sshd`、
  `rescue_key`、`rescue_ssh`、`source_identity_negative`、`source_identity`、
  `pawdata`、`target_enrollment`、`memtest`、`hardware`、`readiness`、
  `mixed_stream`、`ssh_interrupt`、`final_authorization_wrong` 均 PASS。
- `network` 为 WARN（QEMU user networking 无真实直接网络；链路门禁不依赖它）。
- `source_os` 实际输出：
  `pretty=Ubuntu 24.04.5 LTS version=24.04 kernel=6.8.0-147-generic i915_module=yes r8169_module=yes read_only_mount=true`。
- `final_authorization_correct` 于 03:00Z PASS（`serial=PAW-DST-123456`），
  随后被 12 小时外层超时杀死，**clone/verify/repair/expand 尚未执行**，
  因此该次尝试**不是** `CHAIN_PASS`。

### 4.2 同次尝试发现的真实失败

虚拟故障套件为 `37 passed, 2 failed`，失败项是“非最后一个 root 分区拒绝”
没有给出预期原因。根因：新 mkfs 的 loop 分区在 `lsblk -dn -o FSTYPE` 中短暂
为空，脚本在到达碰撞检查前就以 `Root partition is not ext4.` 退出。修复为
`blkid` 直接读取 superblock、短暂重试，并在失败时输出检测到的类型；拒绝路径
仍不移动 GPT 备份头、不调用 growpart。修复后同一虚拟套件重跑为
**39 passed, 0 failed**（`reports/evidence/prehardware-20261111/` 之外的宿主
副本：`~/prehardware-20261111/share/prehw-selftests/`）。

### 4.3 重跑中发现的第二个真实失败：源 UUID 在目标盘上重复

2026-11-12T03:24Z 的重跑在 `source_identity` 处 `CHAIN_FAIL`，真实错误是
`expected exactly one root UUID match`。根因不是源盘：`source50.raw` 的
ext4 根 UUID 在源盘上只出现一次；上一次尝试在 240 GB **一次性虚拟目标盘**
上留下了同一 UUID 的旧克隆，而 lab 把源盘和目标盘挂在同一 guest 内，远端
`lsblk` 因此看到两个匹配。真实生产链路中源是远端 VPS、目标是本机盘，不会
出现这种同机歧义；但 lab 必须每次从空白目标开始。

修复：`guest-chain.sh` 在身份识别前只对序列号
`PAW-DST-123456`、容量 240 GB 的一次性目标执行 `wipefs -a`，并把
`lab_target_blank` 作为显式前置步骤；生产入口不做隐式擦盘。源识别器的
错误信息改为 `expected exactly one root UUID match, found N`，保持 fail-closed，
不通过“忽略第二个匹配”来伪造 PASS。

### 4.4 本次重跑：CHAIN_PASS

2026-11-12 11:32–12:47（CST）重建 lab guest，跑完整链路。实际结果：

- `source_os` PASS：`Ubuntu 24.04.5 LTS`，`VERSION_ID=24.04`，
  `/mnt/paw-source/etc/os-release`，kernel `6.8.0-147-generic`，i915/r8169 存在，
  source 只读挂载。
- 虚拟故障套件 **39 passed, 0 failed**；`source_identity` 使用
  `exact 12 GiB capacity`，复合身份
  `6704e246b06ce693f394c1fed0e2c0db1b99f7da697f2ab3454f470933fbbc66`。
- 授权：错误序列号被拒绝且目标首 1 MiB 未变；正确序列号
  `PAW-DST-123456` 得到 `AUTHORIZED`，随后才进入写入阶段。
- 克隆：`remote-zstd-level1-thread1`，source **12,884,901,888** bytes，
  SSH payload **584,133,947** bytes，压缩减少 **95.5%**，restored
  **12,884,901,888** bytes。
- 独立校验：`sha256=140081b5bdb716cac171d6d6a20e1487aa152e636b7ea793bbae3f701227ff6e`，
  `bytes_verified=12,884,901,888`，`independent_sha256_verified=true`；
  `CLONE-INCOMPLETE` 清除。
- 离线修复 PASS；GRUB 安装到
  `/dev/disk/by-id/ata-QEMU_HARDDISK_PAW-DST-123456`，debconf 状态为
  `cloud_style_no_debconf`（未伪造 debconf 证明）。
- GPT 扩展：`/dev/sdc2` 从 **12,882,787,840** bytes 到
  **239,997,885,952** bytes，`grew=True`，GPT 备份头已移动。
- `preboot_handoff` PASS（`phase=pre_reboot`，不声称 first boot）；
  `auto_reboot` PASS（`invoked=true`）。
- **`PAW3_CHAIN_RESULT=PASS`** 于 12:39:59 实际输出。
- 克隆目标真实启动 `Ubuntu 24.04.5 LTS`（kernel 6.8.0-147-generic），
  在 ttyS0 出现 `ubuntu login:`；宿主结果为
  `main result=TARGET_BOOT_SEEN chain_pass=True target_boot=True qemu_rc=0`
  （12:47:07），截图 `screens/target-boot.ppm`。
- 可提交证据：`reports/evidence/prehardware-20261111/chain-20261112/`
  （步骤摘要、stream-transfer、stream-verify、offline-repair、gpt-expand）。

**测试工具真实缺陷（已修复）**：getty 的 `login: ` 提示末尾没有换行，原来的
行缓冲读取器只把完整行放入队列，因此真实提示已经出现却未被分类。没有伪造
登录：目标确实启动了克隆后的 Ubuntu 并显示 getty；本次为让旧读取器收到行边界，
向串口控制台发送了无害的 SysRq-H 帮助输出。随后已把读取器改为同时检查完整
串口快照，避免未来再依赖额外控制台输出；该修复不改变 PASS 判定标准。

## 5. 补充三：VLESS/Tailscale 双阶段

## 5. 补充三：VLESS/Tailscale 双阶段

- Live：先直连 Tailscale；失败才由中文向导选择旧 VPS VLESS 临时出口。
- Xray v26.3.27，SHA256
  `8255dd939c34cf966cc91517b6324dd3c8d0bcf49ffac8beca049a38c46845ed`；
  VLESS URI 只从 stdin 读，不进 history/普通日志，配置只落 tmpfs 0600。
- SOCKS5 10808 / HTTP 10809 仅 `127.0.0.1`；tailscaled 代理通过 drop-in +
  `/proc/<MainPID>/environ` 证明继承，而非只看当前 shell。
- 身份隔离：Live ephemeral/authkey 与最终 Ubuntu 持久节点分离；offline repair
  清空目标 `var/lib/tailscale`，不复制旧 VPS 身份。
- 25/25 模拟测试 PASS：`reports/evidence/prehardware-20261111/vless-network-test-report.txt`。
- 真实 Tailnet、真实 VPS/VLESS、Windows 互通、Exit Node：`NEEDS_TEST`。
- 详见 `reports/PAW-VLESS-NETWORK-BOOTSTRAP.md`。

## 6. 补充四：武汉家宽端口与公网访问

- 默认不申请公网 IPv4、不做路由器端口映射。
- 管理面 Tailscale（SSH 仅 Tailnet/LAN）；443 用 Serve（Tailnet）/Funnel
  （公网入口在 Tailscale 边缘，家庭侧仍是出站）；PAW Gateway 8800 只
  loopback/Tailnet；Xray 10808/10809 只 loopback。
- 云侧 MCP 不能假设能访问 Tailscale 的 CGNAT 私有地址段，必须走 Funnel/既有 GPT Tunnel；
  实际连通性 `NEEDS_TEST`。
- 策略：`configs/home-port-policy.json`；审计器：`scripts/paw-port-audit.sh`。
- 开发机负向审计：`status=FAIL, listeners=30, violations=13`，证明能识别
  未知公网/通配监听；**这不是生产 PAW 的审计结果**。
- 生产端口/Serve/Funnel/云 MCP/UDP 41641/3478/CGNAT：全部 `NEEDS_TEST`。
- 详见 `reports/PAW-HOME-BROADBAND-PORT-ARCHITECTURE.md` 与
  `reports/PAW-SERVICE-CUTOVER-MANIFEST.md`。

## 7. 明确未做/不可声称

- 未登录、修改、停止或重启旧生产 VPS；未进入 Rescue Mode；未读生产整盘。
- 未修改生产 Tailscale/Funnel/Xray/Nginx/443/防火墙/COS。
- 未写真实 TF 卡/SSD；未在真实 ASUS B85M-G Plus 上启动。
- 未合并 PR、未改 `main`、未删除 Artifact、未改仓库可见性。
- QEMU `ata/ata` + `ich9-ahci` 只是虚拟 AHCI，不是物理 SATA 验收。
- 物理 Memtest、SMART/温度、真机重启、真实 Tailnet/MCP 均未完成。

## 8. 下一步（需用户现场/单独授权）

1. 在 ASUS B85M-G Plus 上实际从 TF/USB 启动，目视确认中文面板与 Memtest 菜单。
2. 真实 TF 卡写入/回读、容量/序列号核对。
3. 真实 SSD SMART、全盘读扫描、温度。
4. 腾讯云 Rescue 只读 source 身份核对，再执行真实克隆。
5. 在真实 PAW Ubuntu 上完成 Tailscale 独立登录、Funnel/Serve 与三家 MCP
   连通性测试；旧 VPS 仅按 gateway-only 清单恢复。
6. 武汉家宽现场验证 UDP 41641/3478、CGNAT/双重 NAT 与 Tailscale DERP 回退。
