# Stage 2：Ubuntu 24.04 克隆盘真实启动证据（2026-11-10）

状态：**VIRTUAL_BOOT_PASS / BLOCK_CLONE_PATH_OPEN**
（真实 QEMU + SeaBIOS 启动通过；生产块设备/SSH 克隆入口尚未在本机执行）

本报告只记录实际执行过的命令和日志。所有磁盘都是 `/home/agentuser` 下的
虚拟镜像文件；没有写入真实 TF 卡、SSD、生产磁盘或腾讯云 VPS。

## 1. 源盘

- 镜像：Ubuntu 24.04.5 cloud image `noble-server-cloudimg-amd64.img`
- 下载 URL：<https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img>
- 下载文件格式：qcow2，虚拟大小 3.5 GiB
- 下载文件 SHA256（qcow2）：
  `04e8f2461a16a44e78a370284471f29616cdd9baf1893df25807b71f985b6c94`
- 转为 raw：`noble-server-cloudimg-amd64.raw`，3,758,096,384 bytes
- 该 raw 先用于一次真实 Ubuntu 启动验证（`source2.log` 中执行了真实
  `grub-install`/`update-grub`/`update-initramfs`），本次克隆的源状态就是这次
  验证后的 3.5GB 盘。
- 本次 clone 源盘全盘 SHA256（3,758,096,384 bytes）：
  `987a7c331e37ad0bfc150d96ce7dc47c671efc06a76f5e50700d8a1e289b7a09`

源盘为真实 GPT + BIOS Boot 布局：

| 分区 | 起始 LBA | 大小（sectors） | 类型 |
|---|---:|---:|---|
| p14 | 2048 | 8192 | BIOS Boot |
| p15 | 10240 | 217088 | EFI System |
| p16 | 227328 | 1869825 | Linux（`/boot` ext4） |
| p1 | 2099200 | 5240799 | Linux（root ext4，磁盘末尾） |

`p16` 中为真实 `/boot`：`vmlinuz-6.8.0-147-generic`、
`initrd.img-6.8.0-147-generic`、`grub/grub.cfg`；GRUB 配置使用
`console=tty1 console=ttyS0`，因此 SeaBIOS + 串口可完整观察启动。

## 2. 目标虚拟盘与项目克隆程序

- 目标：240 GiB 稀疏 raw 虚拟盘
  `tests/virtual/stage2/target-240g.raw`
- 逻辑大小：257,698,037,760 bytes
- 项目克隆入口：`scripts/paw-stream-clone.sh`
- 运行模式：`PAW_SIMULATION=1`。原因：当前宿主没有可用 root/loop，
  `/dev/kvm` 也不存在；该模式要求源/目标都在 `tests/virtual/` 下，并明确
  记录为 local simulation，不是 SSH/块设备生产路径。
- 实际传输：`dd | zstd -1 | pv | 计数 | zstd -d | 计数 | dd conv=notrunc,fsync`
- 源字节：3,758,096,384
- 压缩流字节：657,068,150
- 恢复字节：3,758,096,384
- 独立 SHA256：`987a7c331e37ad0bfc150d96ce7dc47c671efc06a76f5e50700d8a1e289b7a09`
- 项目验证入口：`scripts/paw-stream-verify.sh`，状态 `PASS`，
  `independent_sha256_verified=true`，`bytes_verified=3758096384`。

这不是 stub：clone 和 verify 都是项目脚本真实执行，独立计算源盘与目标盘
前 3.5GB 的 SHA256；但必须明确它**不是**生产块设备/SSH 克隆，也没有把
`PAW_SIMULATION=1` 当成生产 PASS。

## 3. 目标盘启动、GPT/ext4 扩容并安装 GRUB（target1/target2）

QEMU 命令要点（实际使用 portable QEMU 8.2.2，TCG，SeaBIOS）：

```text
qemu-system-x86_64 -machine pc -accel tcg -cpu max -m 2048 -smp 2
  -drive file=tests/virtual/stage2/target-240g.raw,format=raw,if=virtio
  -cdrom seed-target.iso
  -netdev user,id=n0 -device virtio-net-pci,netdev=n0
  -device virtio-rng-pci -display none -monitor none
  -serial file:target2.log -no-reboot
```

NoCloud seed 使用新 `instance-id`，只包含云初始化命令，不包含任何生产凭据。
target1 用源 seed 首次从目标盘启动到 Ubuntu，cloud-init 的早期 growpart 阶段
把 GPT 和 root ext4 扩到 240GB；由于 seed 的 `instance-id` 与源盘相同，`runcmd`
未重复执行。target2 使用新的 target seed `instance-id`，再次启动并执行 `runcmd`：

```text
growpart /dev/vda 1
resize2fs /dev/vda1
grub-install --target=i386-pc /dev/vda
update-grub
update-initramfs -u -k all
```

实际日志证据：

- `Ubuntu 24.04.5 LTS`，kernel `6.8.0-147-generic`
- 启动参数 `root=UUID=<cloud-image-root-uuid>`，真实 GRUB 引导
- `growpart`：`NOCHANGE: partition 1 is size 501217247. it cannot be grown`
  （cloud-init 已在更早阶段完成扩容，所以这里是 no-op，不是失败）
- `resize2fs 1.47.0`：
  `The filesystem is already 62652155 (4k) blocks long.  Nothing to do!`
  （62,652,155 × 4096 = 256,623,230,464 bytes 分区对应文件系统）
- `grub-install (GRUB) 2.12-1ubuntu7.3`：
  `Installing for i386-pc platform.` / `Installation finished. No error reported.`
- `update-initramfs: Generating /boot/initrd.img-6.8.0-147-generic`
- 结束标记：`PAW_STAGE2_OK`，随后 `Powering off.`，QEMU 返回 0

启动后目标 GPT：

```text
label: gpt
last-lba: 503316446
target-240g.raw1 : start=2099200 size=501217247 type=Linux filesystem
target-240g.raw14: start=2048 size=8192 type=BIOS boot
target-240g.raw15: start=10240 size=217088 type=EFI System
target-240g.raw16: start=227328 size=1869825 type=Linux filesystem
```

`lsblk` / `df` 证据：

```text
vda     257698037760 disk
└─vda1  256623230464 part ext4
/dev/vda1 248505155584 1B-blocks ... 1% /
```

因此 GPT 末尾、BIOS Boot、EFI、`/boot` 和 root 分区均保留；root 从 2.5GB
扩展到约 248.5GB 可用文件系统。

## 4. 第三次启动（target3）：不提供 seed，仅从目标盘启动

再次用同一目标盘启动，但**不挂载 seed ISO**，确认不是“只有 seed 才能启动”：

- GRUB 加载 `vmlinuz-6.8.0-147-generic`，cmdline 为
  `BOOT_IMAGE=/vmlinuz-6.8.0-147-generic root=UUID=<cloud-image-root-uuid> ro console=tty1 console=ttyS0`
- 内核正常启动，systemd 到 multi-user
- 串口出现：
  `Ubuntu 24.04.5 LTS paw-stage2-target ttyS0`
  `paw-stage2-target login:`
- `getty@tty1.service` 和 `serial-getty@ttyS0.service` 均启动

第三次启动没有自动 poweroff，日志捕获到 login 后由外层 `timeout` 终止 QEMU
（`qemu_rc=124`）；这是观察结束方式，不是启动失败。

## 5. 证据文件

本机保留（未提交大镜像）：

- `/home/agentuser/paw-stage2-evidence-20261110/target1.log`
  SHA256 `0451b59aaf6a814e9f50b7eb54cd0a9c9daeed940ce2699a88e1e084ba68c196`
  （克隆盘首次启动；cloud-init 早期扩容，seed 的 instance-id 与源盘相同，故
  `runcmd` 未重复执行；这是随后 target2 显示 `NOCHANGE`/already expanded 的原因）
- `/home/agentuser/paw-stage2-evidence-20261110/target2.log`
  SHA256 `6e52b4c22479723506982001d265560f783069d5614a66b12e816379ec9ce235`
- `/home/agentuser/paw-stage2-evidence-20261110/target3.log`
  SHA256 `9bbf3e9f98aa00c438b353ddd39a9ff09f7d00a5e36a66c3ab2247cb6de1960e`
- `/home/agentuser/paw-stage2-evidence-20261110/source2.log`
  SHA256 `737db50b90651f996571057162c80046d7fb3ed02a5b186b7ba54177b98c3cb0`
- 克隆验证报告：
  `tests/virtual/stage2/state/reports/stream-transfer-report.json`
  和 `stream-verify.json`（均为 `PASS`）

## 6. 仍未完成 / 不能声称

- 生产块设备或 SSH 真实克隆入口未执行；本机没有 root/loop，不能把
  `PAW_SIMULATION=1` 当作生产 PASS。
- 项目 `paw-offline-repair.sh` 没有对这个 Ubuntu 目标盘执行完整的
  mount/chroot 离线修复；现有 CI 的 loop ext4 离线修复和真实
  `grub-install --target=i386-pc` 是独立证据，不等同于本目标盘全链路。
- P0-1 字体门禁属于 PAW Live ISO 的写盘入口；本 Ubuntu 云镜像不包含
  PAW Live 服务，不能拿这次启动替代字体门禁测试。
- 真实 ASUS/TF/SSD/腾讯云 Rescue 仍未执行。

结论：Stage 2 的“真实 Ubuntu 24.04 虚拟盘克隆后由 SeaBIOS 启动、GPT/ext4
扩容、真实 GRUB 安装和 initramfs 生成、无 seed 第三次启动”已经实际完成；
生产块设备克隆和项目离线修复全链路仍为 OPEN，因此 Stage 2 只能记为
`VIRTUAL_BOOT_PASS / BLOCK_CLONE_PATH_OPEN`，不能记为完全 CLOSED。
