# PAW PAWDATA exit=32 根因确认与修复记录

日期：2026-11-12
分支：`vm/ds-final-prehardware-remediation-20261112`
HEAD（本报告所测代码）：`1c18a4a`
状态：**根因已复现；可写 USB 与干净介质修复已落地；专项按本报告执行**

## 1. 两次失败原始记录

`fullchain3.log`（`~/final-20261112/logs/fullchain3.log`）在 `source_os` 后
没有进入 PAWDATA：当时测试介质仍是旧生命周期，启动介质路径/覆盖层未满足
可写追加条件。

`fullchain4.log`（`~/final-20261112/logs/fullchain4.log`）第 32 行：

```
[16:52:09] prompt pawdata_serial_suffix: sending 123456
[16:52:15] STEP pawdata STATUS=FAIL paw-data-prepare.sh exit=32
```

`pawdata.log` 未能在失败前落盘：链在 `wait "$pawdata_pid"` 之后才执行
`copy_out`，而 `paw-data-prepare` 由 `set -e` 在 UI 前的介质识别处退出，
没有机会写报告。原始串口/控制台摘录显示：

```
lsblk: tmpfs: not a block device
```

## 2. exit=32 的准确来源

不是 `mount`，不是 `umount`，也不是 remount。复现命令：

```
$ lsblk -dn -o TYPE tmpfs; echo $?
lsblk: tmpfs: not a block device
32
```

util-linux `lsblk` 对非块设备返回 32。旧 `paw-data-prepare.sh` 从
`findmnt --target /run/live/medium` 取得 Live 介质来源；在 QEMU 测试中
`/run/live/medium` 可以是 `tmpfs`（toram/overlay），后续把该字符串当块设备
执行 `lsblk`，`lsblk` 以 32 退出，`set -e` 使整个脚本以 32 结束。
因此失败发生在 **介质识别阶段，尚未执行任何 sfdisk/mkfs/mount 写操作**。

## 3. 修复前 QEMU USB 参数

```
-drive file=.../tf32.img,if=none,id=media,format=raw,readonly=on,cache=unsafe
-device usb-storage,id=usb-media,drive=media,bus=usb0.0,removable=on,bootindex=0,serial=PAW-MEDIA-123456
```

`readonly=on` 与真实 U 盘必须可写矛盾：PAWDATA 需要
`sfdisk --append`、`mkfs.ext4`、读写挂载。修复前只读设备会在真正写入时失败；
这是继 exit=32 之后的第二个环境缺陷。

## 4. 修复后 QEMU USB 参数

```
-drive file=.../tf32.img,if=none,id=media,format=raw,cache=unsafe
-device usb-storage,id=usb-media,drive=media,bus=usb0.0,removable=on,bootindex=0,serial=PAW-MEDIA-123456
```

提交 `1c18a4a` 移除了 `readonly=on`。真实块设备 RO 由 Guest 再检查，
不能只信 QEMU 参数。

## 5. Guest 侧写前门禁

`guest-chain.sh` 在调用 `paw-data-prepare.sh` 前记录并硬停：

```
media_ro="$(blockdev --getro "$MEDIA_DEV")"
lsblk -dn -o NAME,RM,RO,TRAN,SERIAL,SIZE "$MEDIA_DEV"
findmnt -n -o SOURCE --target /run/live/medium
[[ "$media_ro" == 0 ]] || fail pawdata "USB live media is read-only..."
```

`paw-prepare-data-partition.sh` 增加：

```
stage_log=.../pawdata-stages.log
blockdev --getro "$disk" != 0 -> 立即 die，未写分区表
```

阶段日志覆盖：

- `preflight`：RO、RM、TRAN、SERIAL、SIZE、已挂载子分区；
- `partition_table_before/after`；
- `mbr_append` / `gpt_append`（含命令与 stderr、exit）；
- `partprobe`、`partx`、`udevadm_settle`、`partition_node_wait`；
- `mkfs`（只格式化新分区）；
- `first_mount`、`remount_umount`、`remount_mount`；
- 每次 mount/umount 记录完整命令、stderr、返回码、当时 RO、文件系统类型、
  挂载点状态；
- `remount_done`、`complete`。

## 6. 介质生命周期

`tests/prehardware/build-lab.sh` 修正为：

- `media32-base.img`：不可变 ISO 基础镜像，只生成一次；
- `media32.img`：每次独立首启默认从 base 做稀疏副本；
- 两次启动持久化测试显式 `PAW_REUSE_MEDIA=1` 复用同一张卡；
- 不再用“删除 PAWDATA 状态文件”伪造首次启动。

## 7. 修复前后分区表

修复前 `fullchain4` 在介质识别阶段退出，PAWDATA 未写入，分区表保持 ISO
原始 hybrid MBR/GPT；没有“失败后残留半分区”的证据路径。

修复后专项要求保存：

- `media-partition-table.before.txt/json`
- `media-partition-append.txt`
- `media-partition-table.after.txt/json`
- `pawdata-stages.log`
- `pawdata-media-precheck.log`

专项两次启动已补齐并复核这些文件：Boot 1 只新增 `/dev/sdc3` 并写 token，
Boot 2 对同一介质报告 `already mounted and healthy; no partition change was made`，
token SHA256 相同。证据：`reports/evidence/pawdata-persistence-20261112/`。
因此 PAWDATA 分区表修复与持久化在本虚拟范围内 PASS；物理 U 盘仍 NEEDS_TEST。

## 8. 结论

exit=32 的准确阶段是 **Live 介质识别（lsblk 对 tmpfs 返回 32）**，
不是 mount/umount。修复分两层：测试 USB 改为可写；Guest 在任何写操作前
用 `blockdev --getro=0` 和 `lsblk RM/RO/TRAN` 做硬门禁，并输出阶段化
mount/umount 错误，不再把失败统一成“PAWDATA 初始化失败”。
