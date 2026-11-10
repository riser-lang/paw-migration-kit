# PAW Migration Kit v2.7.1 — Stage 3 续跑 / Stage 4 交付报告（滚动更新）

- 日期：2026-11-10 / 2026-11-11（UTC）
- 分支：`vm/ds-clean-handover-20261110`
- 执行模型：DS V4.1 Flash
- 报告状态：**IN_PROGRESS（滚动写入，任何 PASS 只在本文件对应的真实日志存在时成立）**
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
| 18 | final_authorization_correct | `paw-final-confirm.sh` | PENDING |
| 19 | compressed_transfer | `paw-stream-clone.sh`（远端 zstd level1 thread1） | PENDING |
| 20 | clone_complete | 同上，字节计数完整 | PENDING |
| 21 | sha256_verify | `paw-stream-verify.sh` 独立 SHA256 | PENDING |
| 22 | offline_repair | `paw-offline-repair.sh` | PENDING |
| 23 | gpt_expand | `paw-gpt-expand.sh`（move-second-header/growpart/resize2fs） | PENDING |
| 24 | first_boot_check | `paw-firstboot-check.sh` | PENDING |
| 25 | auto_reboot | `paw-finalize-reboot.sh` → 客机内 `systemctl reboot` | PENDING |
| 26 | target_second_boot | QEMU/SeaBIOS 从克隆目标盘启动到 Ubuntu login | PENDING |

## 5. 本轮时间线（只记已发生事实）

- `e3ff373`：提交并推送 QEMU lab harness、6 个生产脚本修复、证据 watcher。
- GitHub Actions `42927263659`：分支完整构建/测试发布候选 ISO（进行中，结果见后续更新）。
- Ubuntu 源镜像下载完成，SHA256 与 Stage 2 记录一致：
  `04e8f2461a16a44e78a370284471f29616cdd9baf1893df25807b71f985b6c94`。
- 源盘 qcow2 → raw 转换、lab 盘片重建：见后续更新。

## 6. Stage 4（尚未开始，状态 PENDING）

最终发布 ISO 构建、ISO 文件本身 SHA256 复核、全部中文交付文档和最终交付报告
在 Stage 3 链路完成后执行；五项真实硬件项保持 OPEN。
