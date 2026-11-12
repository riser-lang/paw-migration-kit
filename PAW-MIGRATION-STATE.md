# PAW Migration State

更新：2026-11-12。每次新对话必须重新核对GitHub；本文件是快照，不是实时状态。

## 当前分支
- 分支：vm/ds-final-prehardware-remediation-20261112
- 文档整理前HEAD：ee9e49ed18e2d4d3fa44fd2c494d0e33cfc08c79
- 最新运行时代码：fe6100e16f4c032310e3eb0b351d37f655d1d1a6
- 基线：vm/ds-prehardware-acceptance-20261111 @ d7cb1e56028c0a4b5cd621e7dc02d17bd2cb8c32
- main：0d6aefd093984a65f40d19e1fae584dee623b8e9（本次核实时未修改）
- 文档整理会产生新提交，以上HEAD随即过期。

## 最新Actions
Run #100：https://github.com/riser-lang/paw-migration-kit/actions/runs/43206559080
- Run ID 43206559080；代码提交 fe6100e16f4c032310e3eb0b351d37f655d1d1a6；结果 FAILURE。
- 静态检查、Public Safety/History、Debian签名、Xray/Tailscale准备、ISO构建、字体、SeaBIOS、CJK五场景5/5、PAWDATA虚拟介质、故障注入39/39通过。
- 失败在 Offline repair and rollback suite on loop ext4。日志出现 netplan 期望文件缺失、后续 offline-repair.json 不存在；报告还提fixture缺 /bin/sh、/usr/bin/env。必须定位第一个真实失败原因。
- 后续网络、P0/P1、VLESS、Finalize被跳过，Run #100不是完整PASS。

## Run #100 ISO（构建成功但workflow失败，不是最终放行）
- paw-live-amd64.iso：953,155,584 bytes
- SHA256：bc37ebaebe469e40b61b0f7c841fee95690b68ccbaf4dfa73d5414fea3a9b0fe
- Artifact：paw-live-build-test-results，ID 13939752294，1,030,656,870 bytes
- 到期：2026-11-15T11:29:27Z
- 报告记录下载后独立复算与sidecar一致。
- 不知道实体TF卡是否已写入该ISO；不得假设已更新，不得未经授权重写。

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
