# PAW 新旧服务器服务身份隔离与 gateway-only 清单

日期：2026-11-11 UTC
分支：`vm/ds-prehardware-acceptance-20261111`
状态：**设计 + 虚拟测试完成；生产只读核对 NEEDS_TEST**

## 1. 目标

旧腾讯云 VPS 保留为回退备份，但**不得**与新 PAW 同时运行相同业务身份。
正式迁移后旧 VPS 只恢复最小网关能力；新服务器接管业务身份。

本轮不修改旧 VPS，不 mask 生产服务；只读设计 + 虚拟 root 测试。

## 2. 身份边界

| 身份 | 旧 VPS | 新 PAW | 处理 |
|---|---|---|---|
| machine-id | 旧值 | 重新生成 | 必须不同 |
| SSH host key | 旧 key | 重新生成 | 必须不同 |
| Tailscale 节点 | 旧节点 | 独立持久节点 | 不复制 `tailscaled.state` |
| PAW 数据库 | 生产数据 | 克隆副本 | 迁移完成后新机唯一写入 |
| Xray/VLESS | 旧出口 | 临时出站客户端 | 不复制服务端凭据 |
| Funnel 域名 | 旧 | 新（或迁移后切换） | 同一域名不得双活 |
| COS 凭据 | 旧 | 新机确认后启用 | 避免重复上传 |
| 定时任务/轮询 | 旧 | 新机启用前旧机停用 | 避免双写 |

代码：`scripts/paw-service-cutover-manifest.py` 只记录 SHA256 摘要和 unit 名，
不保存 host key、token 或 machine-id 原文。虚拟测试验证：

- machine-id 变化 → PASS
- SSH host key 变化 → PASS
- Tailscale state 未复制 → PASS
- hostname 保留是预期行为，不强制 REVIEW

## 3. 服务分级

### A. 旧 VPS 恢复正常 Ubuntu 后允许先启动（gateway-only）

1. `ssh.service` / `sshd.service`：仅保留管理入口，建议限制来源。
2. `xray.service`（或实际 VLESS 单元）：仅作为新机首次 Tailscale 登录的
   出站网关；不在新机复制其服务端身份。
3. `tailscaled.service`：**仅**在确认不会与新机 PAW 业务身份冲突、且只承担
   Exit Node 时保留；否则先停用。
4. 基础系统单元（systemd-journald、rsyslog、cron 等）按需保留；cron 中与
   PAW/COS/API 轮询相关的条目必须先禁用。

### B. 必须等新服务器接管并确认后才可启动

- PAW MCP / GPT MCP / Claude MCP / Spark MCP
- Nginx / 443 站点 / Funnel
- COS 上传、API 轮询、定时同步
- 任何写入 PAW 数据库或共享业务状态的服务

### C. 新服务器首次启动时先保持停止

- 与旧 VPS 同名的 MCP、Funnel、Nginx、COS、轮询单元
- 旧 Tailscale 节点状态（绝不复制）
- 旧 Xray 服务端配置

新机先完成独立 Tailscale 登录、身份确认和 PAW 验收，再逐个启用业务单元。

## 4. 切换顺序

1. 旧 VPS 正常 Ubuntu 启动，只保留 SSH + Xray/VLESS 网关（gateway-only）。
2. 新 PAW 通过家宽直连或 VLESS 临时出口完成 Tailscale 登录。
3. 验证新机 Tailscale IP、设备名、与 Windows 节点互通。
4. 新机确认 machine-id/SSH host key/Tailscale state 均为独立身份。
5. 新机启用 PAW 业务，逐项验证；旧机对应业务保持停止。
6. 观察期结束后，用户决定旧 VPS 保留为 Exit Node 或回退备份。

## 5. 回退

- 旧 VPS 的 unit 启停清单在操作前导出（只读），回退时按清单恢复。
- 新机业务未确认前不删除旧机数据。
- 若 gateway-only 无法安全恢复（例如依赖启动顺序或共享凭据），报告
  `BLOCKED`，不得让旧 VPS 直接恢复全部业务。

## 6. 虚拟测试与证据

命令：

```bash
bash scripts/ci/run-p1-remediation-tests.sh
bash scripts/ci/run-vless-network-tests.sh
```

结果：

- P1：`P1 service manifest PASS with changed machine-id/SSH and preserved hostname`（P1 全套 24/24）
- VLESS：`PASS 17 final Ubuntu identity isolation`
- VLESS：`PASS 18 gateway-only allow-list and business disable plan`
- VLESS：`PASS 19 old/new duplicate business services detected`
- VLESS：`PASS 20 Exit Node remains optional plan`

证据：
`reports/evidence/prehardware-20261111/p1-remediation-report.txt`、
`reports/evidence/prehardware-20261111/vless-network-test-report.txt`。

## 7. 未完成 / NEEDS_TEST

| 项目 | 状态 | 原因 |
|---|---|---|
| 生产旧 VPS 实际 enabled unit 清单 | NEEDS_TEST | 未登录生产 |
| 生产 Tailscale/Funnel/Nginx/Xray 依赖关系 | NEEDS_TEST | 只读授权缺失 |
| gateway-only 在真实 systemd 上的启动顺序 | NEEDS_TEST | 需生产/克隆目标实测 |
| 新机业务逐项接管 | NEEDS_TEST | 依赖真实迁移 |
| Exit Node 真实可用性 | NEEDS_TEST | 需 Tailnet 管理端确认 |

本报告不构成生产变更授权，也不声称旧 VPS 已被隔离。
