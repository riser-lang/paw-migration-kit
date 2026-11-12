# PAW v2.8.1 Tailscale/VLESS 网络切换报告

日期：2026-11-12
分支：`vm/ds-final-prehardware-remediation-20261112`
状态：**代码与虚拟测试 PASS；真实 Tailnet/VLESS/Exit Node NEEDS_TEST**

## 1. 修复的实际问题

### 1.1 Tailscale 设备名

旧实现把系统原始 hostname 直接交给 `tailscale up --hostname`。真实 Ubuntu
hostname 可能包含空格、下划线、大写或超长，Tailscale 会拒绝或生成与预期
不一致的 DNS 名，导致后续按固定名字查找设备失败。

`paw-tailscale-join.sh` 现在：

- `legalize_dns_label()`：转小写；非 `[a-z0-9-]` 折叠为 `-`；去首尾 `-`；
  连续 `-` 折叠；最长 63；
- 最终 Ubuntu 使用 `${PAW_FINAL_TS_HOSTNAME:-$(hostname -s)}` 的合法化结果，
  继承旧服务器的业务身份；
- Live 使用 `${PAW_LIVE_TS_HOSTNAME:-paw-live-temp}`，并加 `--ephemeral`，
  不允许临时节点冒充最终节点；
- join 后强制读取 `tailscale status --json`，要求
  `Self.HostName`、`Self.DNSName` 前缀、`Self.ID` 与本次请求一致；
- 身份不一致直接 exit 4，且不写 ONLINE 成功报告；
- 不写 auth key 文件；待授权状态明确写
  `AWAITING_USER_AUTH_OR_CONTROL_CONNECTIVITY`。

### 1.2 VLESS 重启后残留代理

旧恢复脚本只删除 `/run` 下的临时 drop-in，重启后 `/etc` 下的
`50-paw-vless-proxy.conf` 仍可能让 `tailscaled` 继承已停止的 Xray 代理，
表现为“直连已恢复但 Tailscale 控制面超时”。

`paw-tailscale-direct-recovery.sh` 现在同时处理：

```
$unit_root/run/systemd/system/tailscaled.service.d/50-paw-temporary-proxy.conf
$unit_root/etc/systemd/system/tailscaled.service.d/50-paw-vless-proxy.conf
$run_root/paw-network/xray-client.json
```

流程：备份三处文件 -> 删除 -> `daemon-reload` -> 重启 tailscaled ->
检查直连控制面和 peer -> 停止 Xray -> 扫描残留代理环境 -> 成功才写
`paw.vless-recovery.v2`。任一步失败则恢复备份并重启，exit 3；直连不可用
exit 2；绝不把“删了配置”当成“网络已恢复”。

## 2. 测试结果

```
scripts/ci/run-network-virtual-tests.sh   => 28 passed, 0 failed
scripts/ci/run-vless-network-tests.sh     => 25 passed, 0 failed
```

证据：`evidence/suites/network-final.log`、
`evidence/suites/vless-network-tests.log`。

覆盖：DNS 标签合法化、最终/临时身份区分、身份不匹配 fail-closed、
待授权不伪造 ONLINE、无 auth key 文件、双 drop-in 清理、Xray 停止、
残留扫描、直连失败回滚、成功报告 schema。

## 3. 保留的原有实现

- 既有 Rescue SSH 固定主机指纹校验；
- 既有 Tailscale 安装包签名/哈希校验；
- 既有 Xray 客户端与 VLESS 配置格式；
- 既有网络阶段机（RESCUE / LIVE / RESTORED_UBUNTU）；
- 既有 `PAW_NETWORK_PHASE` 调用约定。

本轮只改身份合法化、匹配校验和代理恢复顺序，没有更换 Tailscale/Xray
二进制，也没有改生产 VPS。

## 4. 真实环境待办

- 真实 Tailnet 中加入最终 Ubuntu，确认 DNS 名与设备列表：**NEEDS_TEST**
- 旧 VPS 作为 Exit Node 的 `tailscale up --exit-node` 与广告路由：
  **NEEDS_TEST**
- 真实 VLESS 客户端重启后的残留代理检查：**NEEDS_TEST**
- 真实腾讯云 Rescue SSH 主机指纹：**NEEDS_TEST**

生产 VPS `paw-main / 公网地址已安全省略` 本轮**未登录、未修改、未重启**。
