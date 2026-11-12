# PAW v2.8.1 SSD 身份与只读健康检查报告

日期：2026-11-12
分支：`vm/ds-final-prehardware-remediation-20261112`
状态：**逻辑/负向测试 PASS；物理 SSD SMART/温度 NEEDS_TEST**

## 1. 修复目标

上一轮只做 SMART 读取，未把“这块盘是否就是用户批准的目标盘”作为门禁，
存在把启动 U 盘、源盘或同容量其它盘当作目标盘的风险。本轮新增
`paw-hardware-preflight.sh` 身份前置门禁：

1. 读取人工登记的 `target-ssd.json`：序列号、真实容量、可选型号；
2. 用 `lsblk -dn -o SERIAL,MODEL` 与 `blockdev --getsize64` 读取实际值；
3. 序列号必填且精确匹配；容量按字节精确匹配；型号存在时必须匹配；
4. 拒绝：目标盘已挂载、目标是当前 Live 启动介质、目标与源盘同一块盘；
5. 通过后才执行 SMART 健康、短自检、温度解析和只读表面扫描；
6. 任何身份不明都返回 `BLOCKED`（exit 3），不写盘。

报告 schema：`paw.ssd-identity.v1`、`paw.ssd-thermal.v1`、
`paw.hardware-health.v1`。

## 2. 只读扫描不写盘

`paw-ssd-read-scan.sh` 只调用：

```
timeout --foreground --signal=TERM --kill-after=30s "$duration" \
  badblocks -sv "$dev"
```

没有 `-w`、`-n` 写模式，没有 `mkfs`、`wipefs`、`sfdisk`。扫描前先做
`assert_unmounted`。温度只作为 WARN/FAIL 信号，不替代 SMART 总体健康。

温度解析支持两种真实格式：

- smartctl 属性行：`194 Temperature_Celsius ... - 35 (Min/Max 20/45)`
- 文本行：`Current Drive Temperature: 35 C` / `Temperature: 35`

阈值默认 70°C WARN、80°C FAIL，可用
`PAW_SSD_TEMP_WARN_C/PAW_SSD_TEMP_FAIL_C` 覆盖；QEMU 虚拟盘无传感器时
明确记为未分类，不伪造温度。

## 3. 自动化结果

命令：

```
scripts/ci/run-ssd-health-tests.sh
```

结果：**11 passed, 0 failed**（`evidence/suites/ssd-final.log`）。

覆盖：

- healthy => PASS
- serial 不匹配 => BLOCKED / exit 3
- 容量不匹配 => BLOCKED / exit 3
- 目标就是 Live 介质 => BLOCKED
- 目标已挂载 => BLOCKED
- SMART overall FAILED => FAIL
- 温度 85°C => FAIL
- UDMA CRC 非零 => WARN
- SMART 自检失败 => FAIL
- 只读扫描失败 => FAIL
- 身份依据记录为 serial+real_capacity+model，且
  `device_name_used_as_identity=false`

测试使用 loop 设备与 mock `lsblk/blockdev/smartctl/badblocks/sensors`，
不接触真实 SSD。

## 4. 真实硬件待办

- 真实 240GB SATA SSD 的序列号/型号/容量登记：**NEEDS_TEST**
- 真实 SMART 健康、短自检、温度、CRC：**NEEDS_TEST**
- 真实 `badblocks -sv` 全盘只读扫描（可能数小时）：**NEEDS_TEST**
- 真实 ASUS B85M-G Plus 的 AHCI 模式与 `lspci -nnk`：**NEEDS_TEST**

主链在 QEMU 内使用有界只读适配器（64MiB 真读）验证门禁和调用顺序，
报告中明确 `physical_smart_verified=false`、
`physical_thermal_sensors_verified=false`，不得当作物理 SSD PASS。

## 5. 证据

- `scripts/paw-hardware-preflight.sh`
- `scripts/paw-ssd-read-scan.sh`
- `scripts/ci/run-ssd-health-tests.sh`
- `evidence/suites/ssd-final.log`
- 主链 `evidence/final/hardware-health.json`（虚拟探测）
