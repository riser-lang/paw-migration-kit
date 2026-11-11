# PAW Migration Kit v2.7.1 — Stage 3/4 任务复核材料

提交复核时间：2026-11-11 10:40 CST
执行方：DeepSeek V4.1 Flash（DSH headless，云端虚拟机）
复核材料整理方：Hermes Agent（调度方，已做宿主级独立验证）

---

## 一、仓库与代码位置

- 仓库：https://github.com/riser-lang/paw-migration-kit
- 开发分支：`vm/ds-clean-handover-20261110`
- 关键提交：`4e6d528b9aa81aa6ea63cd816542ffcbfb67205b`（"Stage 4: record verified ISO and standalone target boot"，34 个文件，2026-11-11T02:31:23Z）
- 关联 PR：https://github.com/riser-lang/paw-migration-kit/pull/2（保持 Draft，未合并）
- 代码 HEAD（CI 构建用）：`24c13f731bfd6c8a70f2331eb0abe30686c29975`

## 二、任务结果（最终状态）

**COMPLETE（云端/虚拟范围）**。Stage 3 链路与 Stage 4 交付 ISO 均闭环；真实硬件验收仍 OPEN。

### Stage 3 — 迁移链路（17 步，虚拟机 QEMU 环境）

已 PASS 的链路步（多轮接力累计，未重跑已 PASS 项）：
live_boot / evidence_transport / console_font / rescue_sshd / rescue_key / rescue_ssh /
source_identity_negative（假UUID拒绝，fail-closed）/ source_identity（组合身份核验）/
pawdata / target_enrollment / memtest / hardware（虚拟探针，物理SMART保持OPEN）/
readiness（READY_FOR_OPERATOR）/ mixed_stream（256MB 混合数据+独立SHA256）/
ssh_interrupt（真实SSH中断，CLONE-INCOMPLETE 保留）/ final_authorization_wrong（错误序列号000000→拒绝授权，目标盘前1MiB未动）/
final_authorization_correct（正确序列号123456，整盘克隆完成）

关键证据点：
- 克隆扩容：分区 2.5G → 239G（growpart CHANGED 日志 + resize2fs 至 62,652,155 blocks）
- SHA256 复核：源盘/目标盘前 3.758GB 独立校验 PASS，receipt 从中断前宿主副本恢复，CLONE-INCOMPLETE 已清除
- 目标盘独立启动验证（本棒补做）：target.img 作为唯一磁盘、SeaBIOS 直接启动（无 -kernel/-initrd），结果 TARGET_BOOT_SEEN，串口捕获 "Ubuntu 24.04.5 LTS ubuntu ttyS0" / "ubuntu login:"，内核 6.8.0-147-generic
  - 仓库证据（去标识化文本摘录）：reports/evidence/stage3-target-standalone-boot-20261111.evidence.txt
  - 宿主原始文件（含 UUID，不入库）：串口日志 56,275 bytes SHA256 `083ea333df9d89177767fc8ada81090ca1da382fa1bfde4758af74173ec63a08`；登录画面 PNG SHA256 `23626d20cabe9c94668c8ca21d7480d89737023e6bc78e140e914ebc3f94e94d`
- 诚实记录：链路内一次 target_boot=False / qemu_rc=-9 如实标注为外层调度误杀 QEMU，未伪装成链路内成功

### Stage 4 — 交付 ISO

- CI Run：https://github.com/riser-lang/paw-migration-kit/actions/runs/42941005270（**success**，20m12s，完成于 2026-11-11T02:03:39Z）
- Artifact：`13822300189`，1,030,665,613 bytes，有效期至 2026-11-14 02:03 UTC
- 交付物：`paw-live-amd64.iso`，953,155,584 bytes
- ISO SHA256：`822ae2c1b41768d0dcb48ab6494aa273dc06ea6be7121baac30a3791cf8c4c09`
- 与同 Run 侧车 iso-identity.txt 一致（未把 ZIP 哈希冒充 ISO 哈希）
- 仓库固化文件：`PAW-V2.7.1-ISO-SHA256.txt`（分支根目录，公开可访问）

### 文档更新（均已提交）

PAW-MIGRATION-ACCEPTANCE.md（A2 与测试计数）、PAW-MIGRATION-STATE.md、
PAW-MIGRATION-BLOCKERS.md、reports/PAW-STAGE3-RESUME-20261110.md、
reports/PAW-STAGE4-DELIVERY-20261111.md、DELIVERY.md、README.md、中文用户指南。

## 三、调度方（Hermes）宿主级独立验证记录

以下为调度方不经 DS、直接在宿主机上复核的结果（供复核方交叉验证）：

1. GitHub API 确认 commit `4e6d528` 存在（34 files）且 Run 42941005270 conclusion=success。
2. `PAW-V2.7.1-ISO-SHA256.txt` 通过 raw.githubusercontent.com 拉取成功，内容含上述 SHA256 与 HEAD。
3. 宿主原始串口日志与登录截图 SHA256 实测与报告值完全一致（见上）。
4. 宿主 targetboot/run1/verdict.json：status=TARGET_BOOT_SEEN，disk=target.img，boot 方式与报告一致，生成时间 2026-11-11T02:20 UTC。
5. run 日志佐证：resume-run1..17 迭代记录在宿主 ~/paw-stage34-20261110/，最终行 `chain_pass=True`。

## 四、过程事故记录（如实披露）

1. 2026-11-11 09:44 job 曾被调度层误杀（run-job.sh 默认 30 分钟超时，非 4 小时任务超时；DS 主进程被连带终止）。DS 现场全部落盘并推送远端，损失为零；随后以接力任务书重启（明确告知死因，要求采信已 PASS 项）。已于 10:14 后将默认超时改为 6 小时。
2. 更早一次（2026-11-10）Stage 3 首棒因 4 小时 timeout 截断（rc=124），属正常超时收尾。

## 五、边界遵守情况

已遵守（复核方可专项检查）：
- 未合并 PR #2、未改动 main、未删除任何历史 GitHub Artifact
- 未修改仓库 Public/Private 权限
- 未操作真实硬件（未写 TF 卡/SSD、未进 Tencent Rescue Mode、未访问生产 VPS）
- 未修改 Tailscale/Funnel/Xray/Nginx/443/防火墙/COS
- PUBLIC-SAFETY=PASS、PUBLIC-HISTORY=PASS（去标识化检查：原始日志含 UUID，仅去标识化摘录入库）

## 六、仍 OPEN 的事项

- 真实硬件验收（PHYSICAL OPEN）：ASUS 主板物理启动、TF 卡写入与启动盘安装、腾讯云 Rescue 相关项、物理 SMART、正式迁移执行
- PR #2 保持 Draft，待物理验收后由用户决定合并

## 七、复核建议切入点

1. 拉取分支核对 commit 4e6d528 的 diff（34 文件，重点：reports/ 与三个 MIGRATION-*.md 数据一致性）
2. 从 Artifact 13822300189 重新下载 ISO 独立算 SHA256，与 `PAW-V2.7.1-ISO-SHA256.txt` 对照
3. 检查 stage3-target-standalone-boot 证据链：verdict schema、boot 参数（确无 -kernel/-initrd）、login 行
4. 检查 PUBLIC-SAFETY：全仓库搜真实 UUID / 主机名 / IP 泄漏
5. 核对 PAW-MIGRATION-ACCEPTANCE.md 的测试计数与 reports/ 中各报告数字自洽
