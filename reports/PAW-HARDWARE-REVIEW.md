# PAW 硬件检测复审（v2.7）

SMART 流程读取健康状态、发起短测并轮询到完成或超时；支持时再发起长测。读扫仅使用只读 `badblocks -sv`，并由 `timeout` 限时。预检收集温度、NVMe 日志、磁盘错误/重置及可用的 SATA CRC 计数。

## 内存检测

Memtest86+ 有独立 BIOS 菜单项和镜像文件。v2.7 增加 `paw-memtest-confirm.sh`：

- 中文界面要求操作员目视确认完成轮次和错误数。
- 记录当前 Live `boot_id`、目标 SSD 设备/序列号、确认时间。
- 结果只能是 `OPERATOR_CONFIRMED`、`WARN` 或 `FAIL`；`PASS` 保留给未来可信机器证明。
- 错误数 >0 为 FAIL；未完成/不确定为 WARN；两者都阻断克隆。
- 硬件门槛只接受 `PASS` 或 `OPERATOR_CONFIRMED`，并在报告中保留 `operator_attestation_not_cryptographic`。

这解决“永远 WARN 导致无法继续”的 P0 阻断，但**不是密码学证明**，也不是机器自动验证。

CI 的 SMART/坏块/内存状态使用虚拟设备或 stub；真实 SSD、主板传感器、读卡器和物理 Memtest 仍未验证。
