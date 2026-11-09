# 恢复与离线修复复审（v2.7）

目标盘登记、源盘 UUID/组合身份、容量/序列号、硬件 PASS、持久分区和操作员授权收据须同时满足，才显示可继续状态。最终确认要求输入目标设备序列号末六位；克隆后独立校验 SHA256，再进行离线修复与 GPT/ext4 扩容。

## 离线修复

`paw-offline-repair.sh` 在真实模式和 loop 模拟模式都执行实际文件改写：

- 只读 `e2fsck -f -n`；发现不一致拒绝自动修复。
- 备份 `/etc/netplan`、cloud-init、udev、machine-id、SSH、GRUB、initramfs modules、Tailscale 状态为 tar + SHA256。
- Netplan 使用 `name: "e*"`，覆盖 `eth0`（`net.ifnames=0`）、`enp3s0`、`en*` 和 Realtek r8169。
- 禁用 cloud-init 网络覆盖，禁用旧腾讯云/MAC udev 规则。
- 保留 `authorized_keys`、PAW 数据库、OAuth、MCP、Codex、Agy 和业务数据；不触碰这些路径。
- 重新生成 machine-id 和 SSH Host Key；备份并清理克隆带来的 Tailscale 节点状态。
- 把 `ahci`、`r8169` 加入 initramfs modules，运行 `update-initramfs` 和 `update-grub`。
- 真实模式额外运行 `grub-install --target=i386-pc --recheck`；模拟模式明确跳过并记录，不伪造。
- 失败时 trap 回滚 netplan、machine-id、SSH Host Key、udev、initramfs modules，并保留备份路径。

## 测试

新增 loop ext4 fixture 测试：实际执行改写，验证 Netplan、initramfs、machine-id、SSH、authorized_keys、PAW 数据、udev 和备份；再注入 `update-grub` 失败，验证回滚。真实 Ubuntu 目标启动仍未验证。
