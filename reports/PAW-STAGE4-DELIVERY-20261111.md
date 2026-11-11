# PAW Migration Kit v2.7.1 — Stage 4 最终交付报告

- 日期：2026-11-11（UTC）
- 分支：`vm/ds-clean-handover-20261110`
- 代码 HEAD（本 ISO 对应）：`24c13f7`
- 文档 HEAD：本报告所在提交；文档提交不改变脚本/ISO
- 执行模型：DS V4.1 Flash
- 状态：**STAGE 3 COMPLETE / STAGE 4 ISO VERIFIED / PHYSICAL OPEN**
- PR #2：Draft，未合并；PR #1 未改动；`main` 未改动

## 1. 最终 CI 构建

| 项目 | 实测值 |
|---|---|
| Run | `42941005270` |
| URL | <https://github.com/riser-lang/paw-migration-kit/actions/runs/42941005270> |
| 触发 | `workflow_dispatch`，分支 `vm/ds-clean-handover-20261110` |
| 代码 HEAD | `24c13f7` |
| 结果 | **success** |
| 耗时 | `20m 12s` |
| 完成时间 | `2026-11-11T02:03:39Z` |
| Artifact | `paw-live-build-test-results`，ID `13822300189` |
| Artifact 大小 | `1,030,665,613` bytes |
| Artifact 过期 | `2026-11-14 02:03:21 UTC` |

## 2. ISO 与独立复核

| 项目 | 实测值 |
|---|---|
| 文件 | `paw-live-amd64.iso` |
| 字节数 | `953,155,584` |
| SHA256 | `822ae2c1b41768d0dcb48ab6494aa273dc06ea6be7121baac30a3791cf8c4c09` |
| 同 Run 侧车 | `paw-live-amd64.iso.sha256: 822ae2c1b41768d0dcb48ab6494aa273dc06ea6be7121baac30a3791cf8c4c09  boot/custom/paw-live-amd64.iso` |
| 复核方式 | 下载 artifact ZIP 后解压，对 **ISO 文件本身**执行 `sha256sum`；没有把 ZIP 哈希当作 ISO 哈希 |
| 系统区布局 | `MBR isohybrid cyl-align-on GPT APM` |

复核结论：计算值与同一 Run 的 `paw-live-amd64.iso.sha256` 和
`iso-identity.txt` 一致。ISO 构建不是字节级可复现，跨 Run 只比较“同一 Run
的侧车”，不跨 Run 比较哈希。

## 3. 本次 CI 的实际测试计数

| 套件 | 结果 |
|---|---|
| 字体门禁故障注入 | `26 assertions, 0 failed` |
| QEMU CJK / fbcon 中文面板 | `5 cases / 96 assertions, 0 failed, 0 blocked` |
| PAWDATA 介质 | `12 passed, 0 failed` |
| 虚拟磁盘/故障注入 | `39 passed, 0 failed` |
| 离线修复/回滚 | `19 passed, 0 failed` |
| 网络阶段 | `17 passed, 0 failed` |
| Finalize/reboot 门 | `36 passed, 0 failed` |
| TTY 静态 + PTY | `56 passed, 0 failed, 0 blocked (static 55 + PTY 15)` |
| CJK 字体校验 | `1 passed, 0 failed` |
| 静态/语法/PowerShell/公开安全 | `PASS (ShellCheck, Bash, Python, PowerShell, JSON/YAML, public safety/history)` |

以上计数取自本次 Run 的 artifact 报告和日志；没有把历史 Run 的计数冒充为
本次结果。

## 4. Stage 3 全链路证据（本 ISO 之前的链路）

26 步迁移链路均有真实执行证据；第 26 步 `target_boot` 的链路内检测器在
`chain_pass=True` 后被外层调度杀掉 QEMU（`qemu_rc=-9`）而报 `False`，
随后由独立 QEMU/SeaBIOS 复核补齐。关键项：

- 授权：目标 `/dev/vdc` serial `PAW-DST-123456`，输入序列号末六位；
- 克隆：`paw-stream-clone.sh`，`mode=remote-zstd-level1-thread1`，真实
  loopback SSH，无 `PAW_SIMULATION` 标志；源/目标为 QEMU virtio 块设备；
- 字节：`source_bytes=3,758,096,384`，`ssh_stream_bytes=591,462,695`，
  `restored_bytes=3,758,096,384`；
- 独立 SHA256：`efcae25cf0bcbe51ec9b842c097d641139a48825fd43191067ba6d3f9efcf2a9`；
- 离线修复：`simulation=false`，真实 `grub-install --target=i386-pc`，备份保留；
- GPT/ext4：`/dev/vdc1` 256,623,230,464 bytes，ext4 62,652,155 blocks；
- 首次启动：`firstboot-check.json` `status=PASS`；
- 自动重启：`reboot-status.json` 先原子持久化并 `sync`，再执行
  `systemctl reboot`；`status_persisted_before_reboot=true`、
  `reboot_invoked=true`；
- 目标二次启动：2026-11-11T02:22Z 以 `target.img` 为唯一磁盘、`vda`
  `bootindex=1`、无 direct kernel 的独立 QEMU/SeaBIOS 启动，内核
  `6.8.0-147-generic`，串口出现 `Ubuntu 24.04.5 LTS ubuntu ttyS0` /
  `ubuntu login:`，`qemu_rc=0`；日志
  `reports/evidence/stage3-target-standalone-boot-20261111.evidence.txt`（去标识化
  串口摘录）SHA256
  `30bdea6c5715244290f742912e73d932648214c5001803b633306af1f7fbc332`；
  宿主原始串口日志 56,275 bytes，SHA256
  `083ea333df9d89177767fc8ada81090ca1da382fa1bfde4758af74173ec63a08`；
  宿主登录画面 PNG SHA256
  `23626d20cabe9c94668c8ca21d7480d89737023e6bc78e140e914ebc3f94e94d`。
  09:42Z 的复核副本 `8fd245…0fa565` 同样记录到 `ubuntu login:`。

完整证据：`reports/PAW-STAGE3-RESUME-20261110.md`。这是 QEMU 虚拟块设备
证据，不是物理 SSD 验收。

## 5. 交付文档更新

- `PAW-MIGRATION-STATE.md`：当前阶段、Stage 3 证据、Stage 4 ISO 状态；
- `PAW-MIGRATION-BLOCKERS.md` / `docs/PAW-V2.7.1-BLOCKERS.md`：STAGE2/STAGE3
  关闭范围、Stage 4 与物理 OPEN 项；
- `PAW-MIGRATION-ACCEPTANCE.md`：虚拟链路与物理验收边界；
- `docs/PAW-V2.7.1-USER-GUIDE-ZH.md`：中文操作指南、Stage 3 验证范围和实机边界；
- `docs/PAW-V2.7.1-TEST-REPORT.md`：新增 Stage 3/4 实测章节；
- `docs/PAW-V2.7.1-REPAIR-REPORT.md`：真实目标盘离线修复补充；
- `docs/PAW-V2.7-HARDWARE-CHECKLIST-ZH.md`：最终 ISO 哈希和实机 7 项；
- `DELIVERY.md` / `README.md`：本 Run、Artifact、ISO 字节数和 SHA256；
- `PAW-V2.7.1-ISO-SHA256.txt`：交付 ISO 的权威侧车。

## 6. 验收矩阵

| 层级 | 状态 | 证据 |
|---|---|---|
| 当前分支 CI | **PASS** | Run `42941005270`，代码 `24c13f7` |
| 最终 ISO 构建 | **PASS** | Artifact `13822300189` |
| ISO 文件 SHA256 复核 | **PASS** | `822ae2c1b41768d0dcb48ab6494aa273dc06ea6be7121baac30a3791cf8c4c09`，与同 Run 侧车一致 |
| ISO 字节级可复现 | NOT PROVEN | 历史多次同尺寸不同哈希 |
| Stage 3 26 步链路 | **PASS（18–25 日志 + 第 26 步独立复核）** | `reports/PAW-STAGE3-RESUME-20261110.md` |
| 真实 TF 卡写入/回读 | **OPEN** | 需用户实体操作 |
| 真实 ASUS 主板启动 | **OPEN** | 需用户实体操作 |
| 真实 SSD SMART/扫描/温度 | **OPEN** | 需用户实体操作 |
| 真实腾讯云 Rescue / 正式迁移 | **OPEN** | 需另行授权 |

## 7. 边界与未做事项

- 未合并 PR #2，未改 `main`，未删除任何 GitHub Artifact；
- 未访问/修改生产 VPS、Rescue Mode、Tailscale/Funnel/Xray/Nginx/443/
  防火墙/COS；
- 未写真实 TF 卡、SSD 或任何物理磁盘；
- 未把 QEMU/loop/mock 结果写成物理或密码学证明；
- `OPERATOR_CONFIRMED` 仍只是操作员目视确认，不是机器证明；
- 真实迁移必须由用户在实体机现场完成并单独授权。

## 8. 结论

当前分支的最终 ISO 已由代码 HEAD `24c13f7` 的 CI 构建、下载，并从 ISO 文件
本身复核 SHA256；Stage 3 的 26 步真实程序链路在 QEMU 虚拟块设备上均有真实执行
证据，第 26 步 `target_boot` 由独立 QEMU/SeaBIOS（`target.img` 唯一磁盘、无 direct
kernel）复核到 `ubuntu login:`。因此云端/虚拟交付状态为
**STAGE 3 COMPLETE / STAGE 4 ISO VERIFIED**。物理 TF 卡、ASUS 主板、SSD、
腾讯云 Rescue 和真实迁移仍为 **OPEN**；在用户完成实机清单前，不能把本报告写成
“物理迁移完成”。
