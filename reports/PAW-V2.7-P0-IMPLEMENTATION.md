# PAW v2.7 P0 整改实现记录

更新时间：2026-11-09 UTC
状态：代码已提交，GitHub Actions 验证进行中；本文不把未完成的运行写成通过。

## P0-1 Memtest86+ 人工确认

新增 `scripts/paw-memtest-confirm.sh`：

- 中文控制台界面，明确声明这是操作员目视确认，不是机器自动验证或密码学证明。
- 读取当前登记的目标 SSD 型号、容量、序列号，要求操作员输入目标序列号末六位。
- 绑定当前 PAW Live 的 `/proc/sys/kernel/random/boot_id` 和目标 SSD 序列号。
- 支持四种结果语义：`PASS`（保留给未来可信机器证明）、`OPERATOR_CONFIRMED`、`WARN`、`FAIL`。
- 错误数 > 0 强制 FAIL；完成轮次 < 1 强制 WARN；未完成/不确定为 WARN。
- 生成 `memtest-attestation.json`，再由 `paw-memory-test-report.sh` 校验 schema、方法、信任级别、boot_id、目标身份和错误数。
- `paw-hardware-preflight.sh` 仅接受 `PASS` 或 `OPERATOR_CONFIRMED`；WARN/FAIL 不能产生硬件 PASS。
- Memtest 独立 ISOLINUX 菜单保留，帮助文本明确要求回到 PAW Live 登记。

限制：没有可信硬件签名或独立采集通道，因此 `OPERATOR_CONFIRMED` 永远不等于 `PASS`，报告中也保留 `operator_attestation_not_cryptographic`。

## P0-2 PAWDATA 自动引导

新增 `boot/paw-data-init.service`，在 `paw-preflight.service` 之前运行 `paw-data-prepare.sh auto`：

- 若 PAWDATA 已挂载且健康，直接跳过。
- 自动识别当前 Live 启动介质；支持 `findmnt` 返回整盘或分区两种情况。
- 只接受可移动介质；显示型号、容量、完整序列号。
- 要求操作员输入序列号末六位；不匹配不写入。
- 只调用 `paw-prepare-data-partition.sh` 追加分区，不重新格式化 ISO 启动分区。
- 支持 DOS/MBR 与 GPT：
  - MBR：按现有 Hybrid MBR 布局追加主分区，保留启动代码。
  - GPT：备份并恢复 Hybrid MBR，移动 GPT 备份头，追加 PAWDATA，保留原 GPT 分区。
- 只对刚追加并验证过的新分区执行 `mkfs.ext4 -L PAWDATA`。
- 挂载后迁移 `/run/paw-migration` 临时状态；用卸载/重挂载标记验证持久化。
- 写 `media-partition.json`，区分是否确实格式化了新分区。

限制：真实 TF 卡、真实读卡器和真实 ASUS 主板启动未验证；`PAW_VERIFY_REMOUNT` 只证明卸载/重挂载，不等于真实重启。

## P0-3 Rescue 源盘组合身份

`paw-source-discovery.sh` 改造：

- 固定 SSH Host Key 指纹参与身份记录，`ssh` 强制 `HostKeyAlgorithms=ssh-ed25519`。
- 根 UUID 必须唯一匹配一个 ext4 分区，父盘必须是整盘。
- 严格核对 50 GiB、GPT、唯一 BIOS Boot（512 KiB–4 MiB）、分区号、父盘只读状态。
- 有序列号时记录并参与组合哈希；无序列号时不再直接拒绝，而是要求：
  - 固定 Host Key 指纹
  - 根 UUID
  - 父盘唯一匹配
  - 精确容量
  - GPT 分区布局
  - BIOS Boot
  - Rescue 发现时间
  - 源盘无 rw 挂载
- 生成 `composite_identity_sha256`、`identity_strength`、`identity_basis`、`inventory_sha256`。
- `paw-final-confirm.sh` 在授权前重新执行源盘识别，并比较设备路径、根 UUID、容量、组合哈希、Host Key 指纹和序列号。

限制：组合身份仍是逻辑绑定，不是云厂商签名的硬件证明；真实腾讯云 Rescue 未连接。

## P0-4 压缩传输

`paw-stream-clone.sh`：

- 远端仍为 `dd | zstd -T1 -1`，SSH 传输压缩流，本地 `zstd -d`，顺序未改变。
- 增加 payload 字节计数和实际解压后字节计数两条独立计数流。
- 压缩模式不再用原始大小伪装 `pv` 百分比；raw fallback 才按原始大小显示进度。
- 校验 `restored_bytes == source_bytes`，否则失败并保留 `CLONE-INCOMPLETE`。
- `paw-stream-verify.sh` 额外校验 `byte_count_streams_complete` 和实际恢复字节数。
- 测试改用全零、确定性随机和重复文本的 8 MiB 混合数据；新增短读注入。

限制：mock SSH 只证明流控制/压缩/解压/计数，不证明真实网络节省率或 Rescue SSH 环境。

## P0-5 最终授权

`paw-final-confirm.sh` 现在展示：

- 源系统型号、容量、根分区号、序列号或“组合身份”。
- 源盘组合身份哈希、固定 SSH Host Key 指纹。
- 目标 SSD 设备、型号、容量、完整序列号。
- 硬件状态、内存验证方式。
- 数据来源、网络独立性、整盘覆盖的数据损失、备份边界。

操作员输入目标序列号末六位后，程序在写授权收据前重新识别源盘和目标盘；任何设备路径、UUID、容量、组合哈希、Host Key 指纹或序列号变化都会停止。

## P1 同步整改

- Netplan 改为 `name: "e*"`，覆盖 `eth0`、`enp3s0`、`en*` 和 Realtek r8169；保留 DHCP、禁用 cloud-init 网络覆盖。
- 离线修复在 loop ext4 上执行真实文件改写：netplan、cloud-init、udev、machine-id、SSH Host Key、Tailscale 状态、initramfs 模块、update-initramfs/update-grub。
- 真实模式增加 `grub-install --target=i386-pc --recheck`；模拟模式记录跳过，不伪造。
- 增加回滚测试：注入 update-grub 失败，验证 netplan、machine-id、SSH Host Key、initramfs 模块恢复。
- 增加网络阶段测试：Rescue 无直连阻断、Restored 缺少 Xray 配置阻断、Xray 非 loopback 监听拒绝、Tailscale 登录等待/超时、无 auth key 文件。
- 增加 Memtest、PAWDATA MBR/GPT、源盘无序列号、硬件门槛等测试。

## 当前未完成

- 本轮 GitHub Actions 尚未结束，所有“通过”以待运行日志和 artifact 为准。
- 真实 TF 卡写入、真实主板启动、真实 SSD、真实 Rescue SSH、真实 PAW 迁移仍未验证。
