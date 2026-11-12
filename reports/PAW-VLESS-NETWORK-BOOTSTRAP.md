# PAW VLESS 临时网络引导与 Tailscale 双阶段接入报告（补充三）

日期：2026-11-11 UTC
分支：`vm/ds-prehardware-acceptance-20261111`
状态：**代码与 25 项虚拟测试完成；真实网络/Tailnet 验收 NEEDS_TEST**

## 1. 交付内容

| 文件 | 作用 |
|---|---|
| `scripts/paw-network-wizard.sh` | 中文向导：直连优先 / VLESS 备用 / 取消 |
| `scripts/paw-vless-uri-import.py` | 从 stdin 读取一条 `vless://`，生成仅回环的 Xray 配置 |
| `scripts/paw-xray-proxy.sh` | 启停 Xray，校验 10808/10809 均为 127.0.0.1 |
| `scripts/paw-tailscale-join.sh` | 直连/代理两阶段加入，记录登录 URL/IP/peer |
| `scripts/paw-tailscaled-proxy.sh` | 为 tailscaled 写 systemd drop-in，并从 `/proc/PID/environ` 证明继承 |
| `scripts/paw-tailscale-exit-node.sh` | Exit Node 计划/状态/受控启停（默认不启用） |
| `scripts/paw-gateway-only-plan.py` | 旧 VPS gateway-only 允许清单/重复业务检测 |
| `scripts/paw-network-bootstrap.sh` | `RESCUE` / `LIVE` / `RESTORED_UBUNTU` 三阶段门禁 |
| `configs/xray-client.sha256` | Xray 26.3.27 资产与二进制 SHA256 |
| `scripts/ci/run-vless-network-tests.sh` | 25 项模拟测试 |

## 2. 两阶段策略

### A. 直连优先

1. 网卡/DHCP/DNS/默认路由由现有 network preflight 完成。
2. 直接访问 Tailscale 控制面。
3. 成功则不启动 Xray，不依赖 VPS。
4. 失败则明确提示“可使用旧 VPS 的 VLESS 作为临时出口”。

### B. VLESS 备用

1. 校验打包 Xray 是否存在、SHA256 是否为
   `8255dd939c34cf966cc91517b6324dd3c8d0bcf49ffac8beca049a38c46845ed`、
   版本是否为 `Xray 26.3.27`。
2. 中文终端接收一次 `vless://`，不回显、不进 shell history、不写普通日志。
3. 配置只落 `/run/paw-network/xray-client.json`（tmpfs），权限 0600、root 所有。
4. 校验入口 TCP 可达；不可达立即失败，不无限重试。
5. 启动 Xray 的 loopback SOCKS5 10808 / HTTP 10809，并做 HTTP 连通性检查。
6. 为 tailscaled 写 drop-in（HTTP_PROXY/HTTPS_PROXY/NO_PROXY），重启后从
   `/proc/<MainPID>/environ` 读取并证明继承，而不是只看当前 shell。
7. 打开 Tailscale 登录链接；用户浏览器授权。
8. 验证 `tailscale ip`、`tailscale status`，可选 peer 互通检查。

## 3. 身份隔离

- Live：允许 ephemeral auth key（`/run/paw-network/tailscale-authkey`，root 0600）；
  或普通网页登录，报告记录 Live 临时设备需清理。
- 最终 Ubuntu：独立持久节点，复用 `paw-tailscaled-proxy.sh apply-persistent`，
  不复制旧 VPS 的 `tailscaled.state`。
- `paw-offline-repair.sh` 会清空克隆目标的 `var/lib/tailscale` 状态，避免把旧
  VPS 身份带进新机。
- `paw-service-cutover-manifest.py` 要求 machine-id、SSH host key 变化，且
  Tailscale state 不存在。

## 4. 25 项模拟测试结果

命令：

```bash
bash scripts/ci/run-vless-network-tests.sh
```

结果：`RESULT passed=25 failed=0`（2026-11-11）。

| # | 测试 | 结果 |
|---|---|---|
| 1 | Live 直连 Tailscale（模拟） | PASS |
| 2 | 直连失败 fail-closed | PASS |
| 3 | VPS 在线 + VLESS 向导路径 | PASS |
| 4 | Xray 配置仅回环、无私钥 | PASS |
| 5 | 打包 Xray v26.3.27 可启动 | PASS |
| 6 | HTTP 入站仅 127.0.0.1:10809 | PASS |
| 7 | tailscaled 代理从 `/proc` 证明 | PASS |
| 8 | 获取 Tailscale IPv4（模拟） | PASS |
| 9 | Windows peer 互通记录（模拟） | PASS |
| 10 | Xray 丢失 fail-closed，不伪造 ONLINE | PASS |
| 11 | Rescue 直连保持 Xray/Tailscale 关闭 | PASS |
| 12 | VLESS 中断快速失败 | PASS |
| 13 | Rescue SSH 路径独立于 VLESS | PASS |
| 14 | 克隆链不引用网络身份 | PASS |
| 15 | firstboot 预重启/真首次启动语义分离 | PASS |
| 16 | Xray v26.3.27 固定用于 Live ISO | PASS |
| 17 | 最终 Ubuntu 身份隔离 | PASS |
| 18 | gateway-only 允许清单 | PASS |
| 19 | 新旧重复业务检测 | PASS |
| 20 | Exit Node 仅可选计划 | PASS |
| 21 | Exit Node 状态观测（模拟） | PASS |
| 22 | 非法 VLESS 拒绝且不回显密钥 | PASS |
| 23 | 操作员取消不改变网络状态 | PASS |
| 24 | 移除代理恢复直连 | PASS |
| 25 | 代理丢失不伪造 PASS | PASS |

证据：`reports/evidence/prehardware-20261111/vless-network-test-report.txt`。

测试中修复的自身问题（避免伪 PASS）：

- 后台假 tailscaled 曾占住命令替换管道，导致套件挂起 300 秒；已重定向并解除。
- 假 `systemctl is-active` 未输出 `active`，导致状态检查误判；已修正。
- 端口 18443 固定，可能被上次残留监听器冒充；改为临时端口文件。
- 身份隔离断言字段名错误（应为 `isolation_checks`）；已修正。
- “克隆链不引用网络”断言过宽，误把 `var/lib/tailscale` 状态清理当网络依赖；
  已收紧为实际命令/URI。

## 5. 验收清单（补充三第十一节）

| 项目 | 状态 | 说明 |
|---|---|---|
| Live 直连 Tailscale | NEEDS_TEST | 需武汉家宽真实启动 |
| Live 经 VLESS 代理 Tailscale | NEEDS_TEST | 需真实 VPS/VLESS，且不得用用户密钥 |
| Windows 与 Live 互通 | NEEDS_TEST | 需真实 Tailnet |
| Rescue 阶段直接 SSH | NEEDS_TEST | 需腾讯云 Rescue 公网入口 |
| Rescue 下 VLESS 不可用行为 | PASS（设计/模拟） | 明确失败，不无限重试 |
| 最终 Ubuntu 独立登录 | NEEDS_TEST | 需真实首次启动 |
| Windows 与最终 Ubuntu 互通 | NEEDS_TEST | 需真实 Tailnet |
| 新旧身份隔离 | PASS（虚拟） | manifest + 25 项测试 |
| VPS gateway-only | NEEDS_TEST | 仅计划/虚拟测试，未改生产 |
| Exit Node | NEEDS_TEST | 未启用生产路由 |

## 6. 保护边界遵守

未修改旧 VPS；未停止/重启旧 VPS；未进入 Rescue；未读生产整盘；未修改生产
Xray/Tailscale/Funnel/Nginx/443/防火墙/COS；未使用用户真实 VLESS 密钥；
未写真实 TF 卡/硬盘；未合并 PR。所有测试只用临时目录、假端点与 loopback。
