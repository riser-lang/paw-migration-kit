# PAW v2.8.1 USB 启动验收报告（虚拟）

日期：2026-11-12
分支：`vm/ds-final-prehardware-remediation-20261112`
状态：**虚拟 USB 启动 PASS；物理 BIOS/USB 启动 NEEDS_TEST**

## 1. 设备模拟

本轮不再使用 IDE 光驱或 UHCI 作为启动介质。主链由 QEMU 以 `qemu-xhci`
控制器加 `usb-storage` 设备启动，USB 镜像为 32,000,000,000 字节的稀疏文件，
写入与官方 ISO 相同字节的启动区。

实际 QEMU 设备参数（`tests/prehardware/run-prehardware-lab.py`）：

```
-device qemu-xhci,id=usb0
-drive file=.../tf32.img,if=none,id=media,format=raw,cache=unsafe
-device usb-storage,id=usb-media,drive=media,bus=usb0.0,
        removable=on,bootindex=0,serial=PAW-MEDIA-123456
```

早期使用 `piix3-usb-uhci` 时串口无输出，证明 UHCI 路径不能作为本验收依据；
该失败已保留在调试记录中，不作为 PASS 证据。

## 2. Guest 内证据

主链 `guest-chain.sh` 的 `usb_media` 步骤从 Guest 内读取而不是复述 QEMU 参数：

- `/dev/sdc`：`tran=usb`、`rm=1`、`serial=PAW-MEDIA-123456`；
- `booted_from_usb_mass_storage=true`；
- 控制器：`qemu-xhci`；
- 容量：32,000,000,000 字节；
- 启动介质分区不参与源盘/目标盘身份判断。

证据：

- `evidence/final/chain-console.log`（步骤 `usb_media PASS`）
- `evidence/final/chain-state/`（Guest 输出与报告）
- `labrun/screens/`（启动过程截屏）

## 3. PAWDATA 与持久化

PAWDATA 必须追加到 USB 启动介质尾部，不能把内部 SATA 盘误认成启动卡。
虚拟验收使用真实块设备 `/dev/sdc`，并检查 `lsblk RM=1`、序列号、容量后才
允许 `sfdisk` 追加分区；QEMU 的 USB 设备本轮为可写，符合真实 U 盘行为。

首次启动创建 `/var/lib/paw-migration/.paw-persistence-token`；第二次以
`paw3.test=usb-persistence` 启动读取同一 token。持久化结果见
`PAW-V2.8.1-FULL-CHAIN-TEST-REPORT.md` 与 `evidence/final/usb-persistence/`。

## 4. 中文菜单/字体

内核 fbcon 使用随 ISO 交付的 16x16 PSF2 字体。验收不是 OCR，而是用
`tests/prehardware/verify-console-glyphs.py` 将屏幕单元与 PSF2 位图逐像素
比对；同时 `paw-console-font` 报告 `fbcon_bound=true`、`setfont_exit_code=0`。

- 字体：`/opt/paw-migration/fonts/paw-cjk-16x16.psf`（512 槽，416 个运行时
  非 ASCII 字符 + U+FFFD，恰好落在内核 512 槽限制内）
- 回退：`paw-cjk-8x16.psf`（PSF1，vgacon 回退）
- 证据：`evidence/final/console-font.json`、`evidence/final/menu-glyphs.json`

ISO 的 ISOLINUX 启动菜单仍是英文（syslinux 字体不含 CJK），中文主界面由
Linux 启动后的 `paw-console` 提供；因此“完整中文菜单”指 PAW 控制台菜单，
不是固件/ISOLINUX 菜单。此区别在用户指南中明确写出。

## 5. 未完成/现场项

- 真实 ASUS B85M-G Plus BIOS 识别 U 盘：**NEEDS_TEST**（本轮无物理机）。
- 真实屏幕上的 BIOS 启动菜单与键盘：**NEEDS_TEST**。
- 真实 USB 拔出后的目标机独立启动：虚拟链已验证 QMP 拔出；物理拔出
  **NEEDS_TEST**。
- Memtest86+ 入口：ISO 菜单项和二进制校验 PASS；真实内存测试
  **NEEDS_TEST**（见 SSD/最终报告）。

## 6. 结论

虚拟 USB 启动、Guest 内 `tran=usb/rm=1`、PAWDATA 尾部追加和第二次持久化
启动均通过。物理 BIOS/USB/屏幕项目保留为现场验收，不冒充 PASS。
