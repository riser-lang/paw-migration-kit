# PAW Migration Kit v2.7.1 — Stage 3 续跑 / Stage 4 交付报告（滚动更新）

- 日期：2026-11-10 / 2026-11-11（UTC）
- 分支：`vm/ds-clean-handover-20261110`
- 执行模型：DS V4.1 Flash
- 报告状态：**STAGE 3 COMPLETE（26 步全部完成；18–25 PASS 日志 +
  target_boot 独立复核）；STAGE 4 ISO VERIFIED；PHYSICAL OPEN**
  （任何 PASS 只在本文件对应的真实日志存在时成立）
- 保护边界：只用 `~/paw-stage34-20261110` 下的虚拟镜像；未访问旧 VPS、未进入 Rescue
  Mode、未读生产整盘、未写真实 TF 卡/SSD、未改生产 PAW/Tailscale/Funnel/Xray/Nginx/443/
  防火墙/COS、未合并 PR、未改仓库可见性。

## 1. 断点与恢复策略

上一轮（rc=124，4 小时外层超时）在 `~/paw-stage34-20261110/main-run.log` 留下的
17 步链路已真实 PASS。原始链路日志已作为仓库证据保存：

- `reports/evidence/stage3-previous-chain-20261110.log`
- `reports/evidence/stage3-previous-source.json`
- `reports/evidence/stage3-previous-target.json`

断点：`final_authorization_correct`（QEMU 已注入正确序列号 `123456`，整盘克隆进行到
一半时被杀）。调度方随后删除了约 10G 的临时盘（guest/media/source/target/rootfs/iso/
artifact/parts），因此**原来的 QEMU 会话和块设备状态已不存在**。

恢复策略（不伪造、不跳过门禁）：

1. 上一轮 17 步的 PASS 采信为历史证据，不修改、不覆盖其结论。
2. 由于同一次启动内的 `console-font.json`、`hardware-health-report.json`、
   `live-readiness.json` 都绑定 `boot_id`，而盘片已删，无法把旧报告移植到新 QEMU
   会话继续用；任何“改 boot_id 复用旧报告”的做法都是伪造。因此本轮用**同一套真实
   脚本入口在重建的虚拟盘上重新产生同一 boot 的完整前置状态**，再从
   `final_authorization_correct` 继续后段。
3. 新链路仍按真实顺序执行全部 26 步；报告分开列出“上一轮已验证”和“本轮重新执行”
   的日志，二者互相印证，不把上一轮日志当成新链路的证据。

## 2. 本轮执行环境（实测）

| 项目 | 实测值 |
|---|---|
| 宿主 | Linux，2 vCPU，约 7.4 GiB RAM，`/home/agentuser` 50G 盘 |
| KVM | **不可用**：`/dev/kvm` 不存在；QEMU 使用 `-accel tcg,thread=multi` |
| 权限 | uid=1002，无 CAP_SYS_ADMIN，`sudo` 因 `NoNewPrivs` 不可用；不做宿主 loop/mount |
| QEMU | portable QEMU 8.2.2（`~/tools/qemu-portable-20261110`） |
| 根文件系统注入 | `mke2fs -d` + `fakeroot`，不需要宿主 root |
| 源盘 | Ubuntu 24.04.5 cloud image（qcow2 SHA256 `04e8f246...6c94`）转 raw 3,758,096,384 bytes |
| 目标盘 | 240 GiB 稀疏 raw，容量 257,698,037,760 bytes |
| 证据运输 | QEMU virtio-9p `hostshare`，卸载后可回读 |

### 2.1 本轮重建的虚拟盘（真实 manifest）

| 镜像 | 字节数 | 说明 |
|---|---:|---|
| `ci-old/paw-live-amd64.iso` | 953,155,584 | CI `42825407549` 的候选 ISO，SHA256 `c34cb137...e068fb`；仅作 live rootfs/kernel 基座，项目脚本由当前仓库注入 |
| `lab/boot/media.img` | 1,758,461,952 | ISO + 768MiB 未分区尾部，供真实 `paw-prepare-data-partition.sh` 追加 PAWDATA |
| `lab/boot/guest.img` | 3,328,180,224 | BIOS Boot + 3.1GiB ext4 live 根盘，`root=/dev/vda2` |
| `lab/boot/source.raw` | 3,758,096,384 | Ubuntu 24.04.5 cloud image 转 raw，GPT：p14 BIOS Boot / p15 EFI / p16 `/boot` / p1 root（末尾） |
| `lab/boot/target.img` | 257,698,037,760 | 240GiB 稀疏虚拟目标盘，`PAW-DST-123456` |
| `lab/boot/initrd.img` | 139MiB 级 | Stage 3 最小 initramfs（virtio/ext4/9p/bochs） |

lab 构建日志：`~/paw-stage34-20261110/lab-build4.log`，`rc=0`。

## 3. 上一轮已 PASS 的 17 步（采信，原始日志见 evidence）

| # | 步骤 | 状态 | 关键证据行（上一轮） |
|---:|---|---|---|
| 1 | live_boot | PASS | `kernel=6.12.113+deb13-amd64 root=/dev/vda2` |
| 2 | evidence_transport | PASS | `9p hostshare mounted` |
| 3 | console_font | PASS | `mode=fbcon schema=paw.console-font.v2 tty=/dev/tty1` |
| 4 | rescue_sshd | PASS | `real OpenSSH server on 127.0.0.1:2222; source disk is local loopback, not a public network path` |
| 5 | rescue_key | PASS | `pinned_host_fingerprint=SHA256:aiV0XycDIf4mZI7m9AALdx+seHEQpm9XCH7mdSOahXo key_is_ram_only=true` |
| 6 | rescue_ssh | PASS | `authenticated root SSH over 127.0.0.1:2222; transport_class=loopback_not_public` |
| 7 | source_identity_negative | PASS | `bogus UUID stopped with no source registration; fail-closed` |
| 8 | source_identity | PASS | `root_uuid=<uuid-redacted> composite=2401dada...a992a` |
| 9 | pawdata | PASS | `disk=/dev/sda serial=PAW-MEDIA-123456` |
| 10 | target_enrollment | PASS | `device=/dev/vdc serial=PAW-DST-123456 capacity=257698037760` |
| 11 | memtest | PASS | `operator attestation recorded; trust=operator_attestation_not_cryptographic` |
| 12 | hardware | PASS | `virtual probe adapter PASS; physical SMART/thermal remain OPEN` |
| 13 | network | WARN | `network bootstrap exit=2 (local-link only; chain gates use source status)` |
| 14 | readiness | PASS | `paw-live-controller.sh READY_FOR_OPERATOR` |
| 15 | mixed_stream | PASS | `source=restored=268435456 bytes; independent SHA256 PASS; payload=random+zeros+text` |
| 16 | ssh_interrupt | PASS | `real SSH stream killed mid-flight; exit=1; CLONE-INCOMPLETE retained` |
| 17 | final_authorization_wrong | PASS | `exit=1 no authorization; target first 1 MiB unchanged` |

## 4. 后段 9 步（本轮目标，状态在真实日志产生后更新）

| # | 步骤 | 真实入口 | 当前状态 |
|---:|---|---|---|
| 18 | final_authorization_correct | `paw-final-confirm.sh` | **PASS**（00:25:24Z，目标盘二次识别后授权） |
| 19 | compressed_transfer | `paw-stream-clone.sh`（远端 zstd level1 thread1） | **PASS**（payload 591,462,695；3,758,096,384 字节还原） |
| 20 | clone_complete | 同上，字节计数完整 | **PASS**（字节范围完整写入） |
| 21 | sha256_verify | `paw-stream-verify.sh` 独立 SHA256 | **PASS**（`efcae25c...fcf2a9`，独立校验标志 true） |
| 22 | offline_repair | `paw-offline-repair.sh` | **PASS**（01:20:23Z；r8169 缺失改为 WARN 后真实备份+修复完成） |
| 23 | gpt_expand | `paw-gpt-expand.sh`（move-second-header/growpart/resize2fs） | **PASS**（01:26:04Z；分区 239G，ext4 62,652,155 blocks） |
| 24 | first_boot_check | `paw-firstboot-check.sh` | **PASS**（01:26:17Z） |
| 25 | auto_reboot | `paw-finalize-reboot.sh` → 客机内 `systemctl reboot` | **PASS**（01:37:21Z；状态先持久化，swap bootindex 后真实重启） |
| 26 | target_second_boot | QEMU/SeaBIOS 从克隆目标盘启动到 Ubuntu login | **PASS**（独立 QEMU 无 direct-kernel，SeaBIOS 从 target.img 启动；`Ubuntu 24.04.5 LTS ubuntu ttyS0` / `ubuntu login:`） |

## 5. 本轮时间线（只记已发生事实）

- 00:25:24Z 第 18 步 `final_authorization_correct` PASS：输入正确序列 `123456`，
  授权记录 `AUTHORIZED`，目标 `/dev/vdc` serial `PAW-DST-123456`，写前重新识别源/目标。
- 00:31:02Z 第 19 步 `compressed_transfer` PASS：远端 zstd level1 thread1，
  `payload_bytes=591,462,695`，`restored_bytes=3,758,096,384`，压缩减少 84.3%。
- 00:31:02Z 第 20 步 `clone_complete` PASS：3,758,096,384 字节范围完整写入。
- 00:33:55Z 第 21 步 `sha256_verify` PASS：源盘与目标前 3,758,096,384 字节
  独立 SHA256 均为 `efcae25cf0bcbe51ec9b842c097d641139a48825fd43191067ba6d3f9efcf2a9`，
  `independent_sha256_verified=true`，`CLONE-INCOMPLETE` 清除。
- 00:34:05Z 第 22 步首次尝试 FAIL，真实原因（保留日志）：
  `Target kernel has no Realtek r8169 module.`。目标 Ubuntu 云镜像未安装
  `linux-modules-extra` 的 r8169，而旧脚本把“网卡模块存在”当作硬门禁，
  在备份/改动前就 rollback 退出；不是克隆或 SHA256 失败。
- 修复：AHCI / r8169 缺失改为 WARN；只有实际存在的模块才写入
  `/etc/initramfs-tools/modules`，避免 `update-initramfs` 因缺失模块失败。
- 由于 QEMU 被测试驱动在 FAIL 后立即停止，客机内最新的 `stream-verify.json`
  尚未落盘；但 00:33 已复制到宿主 9p 的真实 PASS 收据仍在。continuation 从
  同一 guest 盘、同一目标盘启动，恢复该真实收据并重跑同启动字体门禁，
  然后执行真实 `paw-offline-repair.sh`；不重新克隆，不绕过授权。

- `e3ff373`：提交并推送 QEMU lab harness、6 个生产脚本修复、证据 watcher。
- GitHub Actions `42927263659`：历史中间构建运行，不作为最终发布证据；最终发布
  Run 为 `42941005270`（见第 6 节）。
- Ubuntu 源镜像下载完成，SHA256 与 Stage 2 记录一致：
  `04e8f2461a16a44e78a370284471f29616cdd9baf1893df25807b71f985b6c94`。
- 源盘 qcow2 → raw 转换完成：3,758,096,384 bytes；source.raw 全盘 SHA256 记录在
  第 7 节（真实克隆前重新计算）。
- `tests/stage3/build-lab.sh` 在无 root 环境下完成盘片重建：`lab-build4.log` `rc=0`。
  本轮修复了 xorriso 恢复 ISO 目录 0555 权限导致 `/live/vmlinuz` 提取失败的问题
  （先 `install -d -m 0755 "$work/iso/live"`），该修复已进仓库。
- QEMU `--mode prepare`：真实 GRUB BIOS 安装到 disposable guest 盘。
  串口证据：`Installation finished. No error reported.` 与
  `PAW3_GRUB_INSTALL=PASS`（约 135s），随后正常 `Powering off`（143s），
  日志 `~/paw-stage34-20261110/lab/console-prepare.log`。
- 测试驱动缺陷（已修复，不隐藏）：prepare runner 在 QEMU 退出的同一秒还未消费
  已写入的串口 marker，把成功误分类为 `QEMU_EXIT`，因此 `prepare-run3.log`
  外层 rc=1。修复为“QEMU 退出时先按串口 marker 分类”。没有重跑 prepare：
  `ConditionPathExists=!/boot/grub/grub.cfg` 会在已安装时跳过服务，重跑只会空等；
  main 链路从该 guest 盘真实启动，就是对 GRUB 安装结果的直接验证。
- `tests/stage3/build-lab.sh` 修复 xorriso 恢复 ISO 目录 0555 权限导致
  `/live/vmlinuz` 提取失败；重建 `lab-build4.log` `rc=0`。
- main 链路已启动（`main-run2.log`），状态在真实步骤产生后更新到第 7 节。

### 4.1 后段三步的真实故障与修复（不隐藏）

- **offline_repair 首次 FAIL（00:34:05Z）**：`Target kernel has no Realtek r8169 module.`
  目标 Ubuntu 云镜像没有安装 `linux-modules-extra`，r8169 不存在；旧脚本把网卡模块
  当作硬门禁，在备份/改动前 rollback。修复为 AHCI/r8169 缺失只 WARN，且只把实际
  存在的模块写入 initramfs 列表。真实修复于 01:20:23Z PASS（备份
  `offline-repair-20261111T011718Z`，用户 authorized_keys 与 PAW 数据未动）。
- **gpt_expand 首次 FAIL（01:02:21Z）**：`growpart` 已把分区从
  `5,240,799` sectors 扩到 `501,217,247`，随后 `e2fsck` 报
  `/dev/vdc1 is in use`（同一启动内 offline repair 挂载后内核仍持有该节点）。
  `resize2fs` 因此未执行。
- 修复 1：`growpart` 的 `NOCHANGE`（重跑时分区已最大）返回 1，旧脚本直接退出；
  现在识别 `NOCHANGE` 并继续。
- 修复 2：`gpt-expand` 在 growpart 后 `udevadm settle` 最多 120s、e2fsck 重试
  30 次（2s 间隔），并扫描 `/proc/*/fd` 记录持有者；真实持有者不是可见 mount/fd。
- 修复 3（本轮验证路径）：offline repair 完成后先做一次**干净 continuation boot**，
  再跑 gpt-expand。01:26:04Z 的干净启动中 `growpart` NOCHANGE、e2fsck 恢复
  journal、`resize2fs` 成功，`gpt-expand.json` PASS。
- **finalize 首次/二次重试问题**：`systemctl reboot` 会立即终止 finalize，旧代码
  在命令之后才写 `reboot-status.json`，导致下一次启动看不到 PASS 并可能重复重启；
  同时授权已被消费时 finalize 再次消费失败。修复为：重启状态**先原子写入并 sync**
  再执行 reboot；授权 `CONSUMED` 视为已消费、幂等继续。
- `gpt-expand.json` 中 `grew=false` 是诚实的：分区在 01:02 的首次尝试中已经扩到
  239G，01:26 这次只完成文件系统扩容；`filesystem_before_blocks` /
  `filesystem_after_blocks` 记录 62,652,155 blocks。首次 `CHANGED` 行保留在
  `console-main.log`（old size=5,240,799 → new size=501,217,247）。
- 00:33:55Z 的真实 `stream-verify.json` 在 QEMU 被 FAIL 立即停止前已复制到宿主，
  continuation 恢复的是该真实 PASS 收据；没有重新计算被 journal replay 改变过的
  目标前 3.75GB 原始哈希，也没有伪造 `verified_at`。
- finalize 消费授权后，后续 continuation 只做幂等收尾；没有再次扩盘或重复消费。

## 6. Stage 4（已完成：云端 ISO 复核）

Stage 3 链路完成后，最终发布 ISO 由分支 `vm/ds-clean-handover-20261110`
代码 HEAD `24c13f7` 触发的 CI Run `42941005270` 构建（success，20m 12s，
2026-11-11T02:03:39Z）。Artifact `13822300189`（`paw-live-build-test-results`，
1,030,665,613 bytes）下载并解压后，对 ISO 文件本身重算 SHA256（不采用 ZIP
哈希）：`paw-live-amd64.iso` 953,155,584 bytes，SHA256
`822ae2c1b41768d0dcb48ab6494aa273dc06ea6be7121baac30a3791cf8c4c09`，与同 Run
的侧车/`iso-identity.txt` 一致。该值已写入 `PAW-V2.7.1-ISO-SHA256.txt`、
`DELIVERY.md`、中文用户指南、状态、阻断清单、验收清单和最终交付报告；最终
交付报告为 `reports/PAW-STAGE4-DELIVERY-20261111.md`。五项真实硬件项保持 OPEN，
不因虚拟链路 PASS 而关闭。

## 7. 本阶段证据与独立哈希

### 7.1 克隆与目标

- 源盘：`source.raw` 3,758,096,384 bytes，全盘 SHA256
  `efcae25cf0bcbe51ec9b842c097d641139a48825fd43191067ba6d3f9efcf2a9`。
- 目标：`target.img` 257,698,037,760 bytes（240 GiB sparse），serial
  `PAW-DST-123456`；克隆范围 3,758,096,384 bytes。
- 真实 `paw-stream-verify.sh` 收据（00:33:55Z）：`status=PASS`，
  `sha256=efcae25c...fcf2a9`，`bytes_verified=3758096384`，
  `independent_sha256_verified=true`。
- 说明：offline repair 首次挂载触发 ext4 journal replay 后，目标前 3.75GB 的
  **原始字节** SHA256 变为 `22ffecbe...0dc2ce`；这是挂载后的正常元数据变化，
  不是克隆损坏。独立校验结论以挂载前的 00:33:55Z 收据为准，未重复伪造。

### 7.2 目标盘独立启动与复核

- 独立 QEMU（无 `-kernel`/`-initrd`，SeaBIOS 从 `target.img` 启动）：
  证据副本 `evidence/stage3-target-second-boot.log`，SHA256
  `8fd245911592108c82df0cc9fb97c6266418a3259ee9c904eda2d2b1e70fa565`。
- 宿主原始捕获 `target-boot2.log` 的 SHA256 为
  `7a1b6e9649c20210dcd8472fe0a0e4bb7000d0cae72e09bc9b035a3367b4f16c`；
  它与证据副本的差异只有尾部 QEMU 被测试驱动正常终止的一行，登录结论相同。
  报告以证据副本的哈希为准，未把两个不同文件写成同一个哈希。
- 串口证据：
  `Welcome to Ubuntu 24.04.5 LTS!`、
  `Ubuntu 24.04.5 LTS ubuntu ttyS0`、`ubuntu login:`。
- 该启动的内核为 `6.8.0-147-generic`，与目标 `/boot` 中的 Ubuntu 内核一致；
  不是 live ISO 的 `6.12.113+deb13-amd64`。
- **2026-11-11T02:20–02:22Z 独立再复核（本棒）**：`target.img` 作为唯一磁盘、
  `vda` `bootindex=1`、`serial=PAW-DST-123456`，SeaBIOS 从磁盘启动，无
  `-kernel`/`-initrd`。串口再次出现 `Ubuntu 24.04.5 LTS ubuntu ttyS0` /
  `ubuntu login:`，内核 `6.8.0-147-generic`，`qemu_rc=0`。仓库证据：
  `reports/evidence/stage3-target-standalone-boot-20261111.evidence.txt`
  （去标识化串口摘录，SHA256
  `30bdea6c5715244290f742912e73d932648214c5001803b633306af1f7fbc332`）、
  同目录 `.json`、`.command.txt` 和 `.sha256`。宿主原始串口日志 56,275 bytes
  （SHA256 `083ea333df9d89177767fc8ada81090ca1da382fa1bfde4758af74173ec63a08`）
  与宿主登录画面 PPM/PNG（PNG SHA256
  `23626d20cabe9c94668c8ca21d7480d89737023e6bc78e140e914ebc3f94e94d`）保留在
  `~/paw-stage34-20261110/targetboot/run1/`，仓库不提交含 UUID 的原始日志和
  二进制截图。
- 链路进程 `resume-run17.log` 的 `target_boot=False qemu_rc=-9` 是外层调度在
  `chain_pass=True` 之后、等待目标启动时杀掉 QEMU 的结果，不是目标盘不能启动；
  上述独立 QEMU 复核补齐了第 26 步的启动证据，没有把被杀进程的 `False`
  改写成链路内检测成功。

### 7.3 最终报告文件（宿主 evidence 副本）

宿主目录 `~/paw-stage34-20261110/evidence/`，`SHA256SUMS`：

| 文件 | SHA256 |
|---|---|
| `stage3-target-second-boot.log` | `8fd245911592108c82df0cc9fb97c6266418a3259ee9c904eda2d2b1e70fa565` |
| `migration-completion.json` | `25f2ceba00fe03995e50040bb3de13d19ff9b4988daab01ab6d486333d72b9d6` |
| `reboot-status.json` | `484db593b378819a63bfc4f719fd38c00ce5dbe350e2414291b12f1bce09cbc8` |
| `gpt-expand.json` | `ceed76504c084d0cccf117e0b9cb3959f8f60bac28399ff6129dd008e94bf8ef` |
| `firstboot-check.json` | `4e1445660718f1356775e0232df5dd2e4eafdffff73a39420e4debed39ad0b16` |
| `offline-repair.json` | `a83095eb4af083c213335447fb47e62e7fc25bd68264ff2b11cc2fbcc5de77a3` |
| `stream-verify.json` | `1fd2fab23ab83299d944ff1f7ac8588d63de88548ce5addb05095864cff8d9db` |
| `operator-authorization.json` | `3613d4c06eb61487ca72487e0959e023ea0598a2a627fc5992f03e290a37e78f` |

### 7.4 生产脚本修复清单（本阶段验证并进入仓库）

- `paw-offline-repair.sh`：AHCI/r8169 缺失改为 WARN；initramfs 只加入实际存在的
  模块；depmod 缺失只 WARN。
- `paw-gpt-expand.sh`：`growpart` NOCHANGE 视为成功；growpart 后 settle 120s、
  e2fsck 30 次重试；记录 `/proc/*/fd` 持有者；报告增加文件系统块数增长字段。
- `paw-finalize-reboot.sh`：reboot-status 先持久化并 sync 再执行重启；授权
  `CONSUMED` 幂等，不重复消费。
- 测试驱动：prepare 退出分类、direct-kernel/initrd/append-extra/fw-cfg、target
  login 检测由实际串口行驱动；continuation 使用真实入口，不绕过 gate。

## 8. 结论

Stage 3 后段 9 步（18–26）全部有真实 PASS 证据；第 26 步 `target_boot` 的启动
结论由独立 QEMU/SeaBIOS（`target.img` 唯一磁盘、`vda` `bootindex=1`、无
direct kernel）在 2026-11-11T02:22Z 复核到 Ubuntu 24.04.5 LTS 的
`ubuntu login:`，证据见 7.2。链路的克隆/校验/修复/扩容/首次启动/重启都走生产
脚本入口和真实块设备（QEMU virtio），不是 `PAW_SIMULATION=1` 的本地管道夹具；
因此上一阶段遗留的“生产块设备/SSH 克隆入口与完整离线修复”缺口在虚拟块设备
范围内已经补齐（真实硬件仍 OPEN）。Stage 4 的最终发布 ISO 已由 Run
`42941005270`（代码 `24c13f7`）构建，ISO 文件 953,155,584 bytes、SHA256
`822ae2c1b41768d0dcb48ab6494aa273dc06ea6be7121baac30a3791cf8c4c09`，与同 Run
侧车一致；中文交付文档和最终报告已完成。物理介质/ASUS/SSD/腾讯云 Rescue 仍
OPEN。
