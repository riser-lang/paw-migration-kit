# PAW v2.7 回滚与中止说明

## 原则

旧 VPS 在 PAW 正式验收前仍是生产权威。任何阶段失败，优先保留旧 VPS 运行，不执行“再克隆一次”或手工改生产配置。目标是可逆，不是强行完成。

## 阶段 0：尚未开始克隆

- 目标 SSD 未被写入；直接停止即可。
- TF 卡上的 PAWDATA 只包含准备状态和报告；可保留，不要格式化。
- 不要删除旧 VPS 或 COS 备份。

## 阶段 1：已授权但克隆中断

- 程序会保留 `CLONE-INCOMPLETE` 和 `stream-transfer-report.json`。
- 目标 SSD 可能只写入了一部分，**不能启动**。
- 不要手工把目标盘当正式盘；重新执行时应重新识别目标盘并重新授权。
- 旧 VPS 未被修改，继续作为生产环境。

## 阶段 2：克隆完成、SHA256 通过，但离线修复失败

- `paw-offline-repair.sh` 在 PAWDATA 的 `backups/offline-repair-<时间>/` 保留：
  - `target-configs.before.tar`
  - `target-configs.before.tar.sha256`
  - `original-paths.txt`
  - 原 netplan、Tailscale 状态等。
- 失败时 trap 会自动回滚已改写的 netplan、machine-id、SSH Host Key、udev、initramfs modules。
- 如果自动回滚也失败，不要手工启动目标盘；保留备份并交给远程 Codex 分析。

## 阶段 3：目标盘首次启动失败

- 重新从 TF 卡启动 PAW Live。
- 不要再次自动克隆；先读取 PAWDATA 的 `reports/` 和备份。
- 旧 VPS 仍是生产环境；不要为了排查而重启/救援旧 VPS。
- 记录：屏幕照片、`offline-repair.json`、`stream-verify.json`、`gpt-before-expand-*.txt`、`backups/` 路径。

## 阶段 4：新 Ubuntu 已启动但 PAW 验收失败

- 不要删除旧 VPS、旧 DNS、旧 Funnel 或 COS 备份。
- 由远程 Codex 对比新旧节点；必要时把流量切回旧 VPS。
- Tailscale 节点身份、机器名、Funnel、MCP 的变更必须有单独记录。

## TF 卡回滚

- 重写 ISO 会清除 PAWDATA。重写前先把 `/var/lib/paw-migration/reports/` 和 `backups/` 复制到另一台电脑。
- 不要在 Windows 里“格式化”TF 卡来尝试修复；使用已验证 ISO 和 DD 模式重写，或停止并求助。
- 写入前重新核对读卡器型号、容量、序列号和 SHA256；不要凭盘符判断。

## 禁止事项

- 不停止、重启或进入旧 VPS 的 Rescue Mode 来“回滚”。
- 不修改旧 VPS 的 Tailscale、Funnel、Xray/VLESS、Nginx/443、防火墙、安全组、COS。
- 不删除生产数据、不清理 COS 备份、不执行真实克隆作为“测试”。
- 不把 `OPERATOR_CONFIRMED` 或 QEMU 成功写成真实硬件通过。
