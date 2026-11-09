# 恢复与离线修复复审

目标盘登记、源盘 UUID、容量/序列号、硬件 PASS、持久分区和操作员授权收据须同时满足，才显示可继续状态。最终确认要求输入目标设备序列号末六位；克隆后独立校验 SHA256，再进行离线修复与 GPT/ext4 扩容。

离线修复保留变更前网络、启动和系统身份文件的 PAWDATA 备份，生成 DHCP 网络配置、移除固定 MAC 绑定、更新 initramfs/GRUB，并更换 machine-id 与 SSH 主机密钥。不得访问 `authorized_keys`、PAW 数据库、OAuth、MCP、Codex 或 Agy 用户数据。

实现仍须由 loop 虚拟磁盘测试与目标 Ubuntu 启动测试验证。当前不连接真实源盘或目标 SSD。回滚和适配未在物理机证明前，不能报告迁移 READY。
