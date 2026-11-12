# PAW v2.8 Claude 审计整改报告（P0/P1，虚拟范围）

- 日期：2026-11-11（UTC）
- 分支：`vm/ds-prehardware-acceptance-20261111`
- 代码基线：`0e59cc2`（P0/P1 主体）→ `35647b0` → `d7080b3`
- 状态：**P0/P1 代码与虚拟测试关闭；P2/物理/生产项保留 OPEN 或 NEEDS_TEST**

## 1. 整改原则

1. 不把“警告”改成“静默通过”。缺 AHCI/r8169、缺 initramfs 验证、SMART 异常
   都必须阻断或明确分类。
2. 不把“模拟成功”写成物理 PASS。QEMU、loop、mock SSH、假 Tailscale/Xray
   一律标注 `virtual` / `simulation`。
3. 每个修复都有可重复测试；测试本身也会被审计，避免假 PASS。
4. 涉及生产 VPS、真实 SSD/TF、Rescue、Tailscale/Funnel/Xray/Nginx/443/
   防火墙/COS 的项，本轮不做，保持 `NEEDS_TEST`。

## 2. P0 整改

| 审计项 | 原问题 | 整改 | 验证 |
|---|---|---|---|
| Memtest 启动 | `memtest.cfg` 使用 `kernel` 加载 bzImage；无固定来源；无菜单实测 | 改 `linux`；固定 v7.20 + SHA256；构建时校验；新增真实 ISOLINUX 菜单测试 | 真实 ISO 菜单 hotkey `m` 启动，`Memtest86+ v7.20`；完整 pass `Pass: 1 / Errors: 0` |
| 授权与事务 | 仅一次授权检查；中断后可能重复 clone；过期语义不清 | `paw-transaction.py` 状态机；clone 前校验授权/目标/阶段；6h expiry 仅 clone 前；中断保留 `CLONE_INCOMPLETE` | P0 套件 26/26 |
| source 挂载门 | `findmnt` 错误被吞；读写挂载可能被当成只读 | `paw-source-mount-check.py` 解析 mountinfo，读写/缺失/畸形 fail-closed | P0 套件 7 个 mount 场景 |
| 链内内存确认 | 只记录 UI，不绑定 boot/target | `OPERATOR_CONFIRMED` 绑定 boot_id、target serial/device、pass/error；明确非密码学证明 | `memory-test.json` |

P0 证据：`reports/evidence/prehardware-20261111/p0-remediation-report.txt`（26/26）、
`memtest86-20261111.txt`。

## 3. P1 整改

| 审计项 | 整改 | 验证 |
|---|---|---|
| 目标回读非 O_DIRECT | `paw-stream-verify.sh` 用 `iflag=direct`，记录 readback method | P1 套件 |
| 可能误选 Windows/NTFS 盘 | `paw-target-discovery.sh` 排除 Microsoft basic data + NTFS | P1 套件 |
| GRUB/initramfs 交互卡死 | 全非交互 + `GRUB_DISABLE_OS_PROBER=true` + 180s timeout | P1 套件 |
| initramfs 模块未独立验证 | `lsinitramfs` 检查 AHCI/r8169/文件系统模块，缺则 die | P1 套件 |
| fstab/GRUB UUID 未回读 | 修复后重新 blkid 并检查 fstab/grub.cfg | P1 套件 |
| HD4600 i915 分类 | 检测模块并分类，不把 QEMU 显卡当物理 | P1 套件 |
| BIOS 启动顺序不可控 | `paw-reboot-media-check.sh` 记录 `boot_order_control`；介质在位禁止自动重启 | P1 套件 |
| firstboot 语义混淆 | 预重启 handoff 明确 `actual_first_boot_performed=false`；真检查仅 post-boot | P1 套件 |
| SMART 健康 PASS + 非零 mask 被误判 FAIL | 归为 `WARN/SMART_HEALTH_PASSED_NONZERO_RC`；FAIL 永不 PASS | P1 套件 |
| 缺 AHCI/r8169 只 warn | 改为硬阻断 `die`，不允许不可启动目标进入修复 | P1 套件 |
| grub-pc 安装设备漂移 | `/dev/disk/by-id` 解析；debconf 固定 `grub-pc/install_devices`；非交互 reconfigure + `debconf-show` 回读 | P1 套件；全链路 offline repair 验证 by-id |
| 新旧身份重复 | `paw-service-cutover-manifest.py` 要求 machine-id/SSH host key 变化、Tailscale state 不存在 | P1 + VLESS 17 |

P1 证据：`reports/evidence/prehardware-20261111/p1-remediation-report.txt`（24/24）。
本地 ShellCheck `-S warning` 返回 0；Python `py_compile` 通过。

## 4. P2 / 未关闭项

以下不是“已修复”，必须在真实环境补测：

- 真实 ASUS B85M-G Plus Legacy BIOS、键盘、显示与中文面板；
- 真实 TF/USB 写入、回读、容量/序列号；
- 真实 SSD SMART、全盘读扫描、温度；
- 腾讯云 Rescue 真实 SSH、source UUID/composite 身份；
- 真实 50 GiB→大容量 SSD 克隆与独立 SHA256；
- 真实 `systemctl reboot`、首次启动、离线修复；
- 真实 Tailscale 登录、Windows 互通、Funnel/Serve、三家云 MCP；
- 武汉家宽 UDP 41641/3478、CGNAT/双重 NAT、DERP 回退；
- 生产旧 VPS gateway-only 只读清单与切换。

这些项目在本报告中统一标记 `NEEDS_TEST`/`OPEN`，不得用虚拟结果替代。

## 5. 测试环境与边界

- 宿主：2 vCPU、约 3 GiB 可用内存、50 GiB 磁盘（本轮可用空间一度低至约 8.9 GiB）；无 host root/sudo/user namespace。
- Guest：Debian Live 6.12.113+deb13-amd64，4 vCPU、3 GiB RAM；QEMU/TCG。
- 源：12 GiB GPT/ext4 Ubuntu 24.04.5 云根文件系统（kernel 6.8.0-147-generic）；真实 50 GiB 源盘仍 NEEDS_TEST。
- 目标：240 GB 稀疏镜像；介质：32 GB ISO+PAWDATA 镜像。
- 未改生产 VPS；未进入 Rescue；未写物理盘；未合并 PR；未删 Artifact。
