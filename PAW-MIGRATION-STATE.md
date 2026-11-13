# PAW Migration State

更新：2026-11-13。每次新对话必须重新核对GitHub；本文件是快照，不是实时状态。

## 当前分支
- 分支：vm/ds-final-prehardware-remediation-20261112
- 已验收运行时代码：7ec4dbf3d14fb7e23aa213f7f9021d24c569913a
- 基线：vm/ds-prehardware-acceptance-20261111 @ d7cb1e56028c0a4b5cd621e7dc02d17bd2cb8c32
- main：0d6aefd093984a65f40d19e1fae584dee623b8e9（未修改）
- 文档提交会在运行时提交之后更新，以上 HEAD 仅反映写入时刻。

## 最新 Actions
- 常规 CI（`build-live-and-test.yml`）：Run **`43398893910`**（https://github.com/riser-lang/paw-migration-kit/actions/runs/43398893910）
  - 代码提交：`7ec4dbf3d14fb7e23aa213f7f9021d24c569913a`
  - 结果：**`success`**（全部 24 步通过：静态检查、CJK 字体 416 字形、SeaBIOS、CJK 25/25、PAWDATA 12/12、Fault-injection 43/43、Offline repair 27/27、Network 28/28、P0 46/46、P1 24/24、SSD identity/controller 41/41、VLESS 25/25、Finalize 36/36、TTY 56/56）
- 50GiB 完整链路（`prehardware-50g.yml`）：Run **`43402874795`**（https://github.com/riser-lang/paw-migration-kit/actions/runs/43402874795）
  - 代码提交 & ISO 来源：`7ec4dbf3d14fb7e23aa213f7f9021d24c569913a` / Run `43398893910`
  - 状态：**`in_progress`**（写入本快照时仍在执行中，待完成后验收；在此之前真实克隆继续阻断）

## 最新已校验 Release ISO（来自 Run 43398893910）
- Artifact：`paw-live-build-test-results`，ID `14025033882`，ZIP 大小 `1030672881` bytes（`7z t` PASS）
- `paw-live-amd64.iso`：`953155584` bytes
- 独立复算 SHA256：`eec712f8f2b2677046d3aafabc8e76a7fce82219062f418bad19dbd46f696358`（与 sidecar `paw-live-amd64.iso.sha256`、`iso-identity.txt` 一致）
- 本地下载路径：`C:\PAW-Release\run-43398893910\paw-live-amd64.iso`
- 历史 Run #124（`43374947901` / `0ced6e8...`）及 Run #100 均仅作历史基线，不得替代本轮 ISO。

## 已通过 P0 修复（运行时提交 7ec4dbf3d14fb7e23aa213f7f9021d24c569913a）
- P0-1：`tests/prehardware/guest-chain.sh` 中断测试从 `target-identity.json` 写入双哈希至 `operator-authorization.json` 并留存 tx init 日志；
- P0-2：`tests/prehardware/verify-chain-evidence.py` 与 `run-prehardware-lab.py` 强制 `auto_reboot PASS` 后目标 Ubuntu login 并由 Host runner 印证；
- P0-3：`scripts/paw-source-discovery.sh` 将 `root_start == max_start` 检查前移至源盘发现阶段并保留 `paw-gpt-expand.sh` 第二道门禁；
- P0-4：`scripts/paw-live-controller.sh`、`paw-hardware-preflight.sh`、`paw-memtest-confirm.sh`、`paw-memory-test-report.sh` 与 `paw-final-confirm.sh` 全面支持无序列号 SSD（WWN/by-id/8 位硬件指纹）且严格校验唯一性与容量。

## 已有虚拟成果与边界
- Memtest86+ 7.20菜单：QEMU/SeaBIOS通过；真实12GB内存待测。
- P0授权事务26/26、源盘只读门禁、P1部分检查、VLESS/Tailscale均有虚拟/模拟通过记录。
- PAWDATA可写虚拟USB两次启动持久化通过；真实TF卡待测。
- QEMU xHCI + USB Mass Storage虚拟启动通过；真实ASUS BIOS/读卡器待测。
- CJK五场景、25项检查通过；真实HD4600待测。
- 12GiB Ubuntu 24.04.5虚拟源盘到240GB虚拟目标盘完整链路通过，SHA256：140081b5bdb716cac171d6d6a20e1487aa152e636b7ea793bbae3f701227ff6e；目标Ubuntu到达ubuntu login:。
- 12GiB通过不等于50GiB完整链路通过。50GiB完整克隆、校验、修复、扩容和目标启动仍未完成。
- 真实VPS Rescue、Tailnet、Exit Node、MCP、SSD、TF卡和ASUS均未实测。

## 必须解决：用户不知道SSD序列号
当前 paw-hardware-preflight.sh 仍要求 target-ssd.json 预先登记 serial 并精确匹配。用户不知道序列号，不能要求提前提供。必须改为：
1. 自动扫描并展示磁盘型号、容量、接口、序列号/WWN（如有）、分区、文件系统和系统特征；
2. 用户从列表选择并确认目标SSD；
3. 程序把本次实际检测到的身份绑定到迁移事务；
4. 每个写盘阶段重新识别核验；
5. 无序列号时使用稳定组合身份；
6. 无法区分时要求断开无关盘；
7. 不得仅凭 /dev/sda 或240GB容量自动选盘。

## 真实硬件/生产待测
ASUS Legacy BIOS、真实TF/读卡器、HD4600、12GB Memtest、Realtek网卡、240GB SATA SMART/温度/只读扫描、真实AHCI、腾讯云Rescue SSH、50GiB持续传输、中国移动家宽WAN/IPv6/CGNAT、真实Tailscale/VLESS/Exit Node、GPT/Claude/Spark MCP接管、旧VPS gateway-only。

## 保护边界
不修改/停止/重启旧VPS；不进入生产Rescue；不读生产整盘；不改生产PAW/MCP/Tailscale/Funnel/Xray/Nginx/443/防火墙/COS；不写真实TF卡或SSD；不删历史Artifact；不改main；不合并PR #2。真实克隆和破坏性操作必须另获用户明确授权。
