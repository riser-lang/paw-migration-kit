# PAW 武汉家宽端口与公网访问架构审核（补充四）

日期：2026-11-11 UTC
分支：`vm/ds-prehardware-acceptance-20261111`
状态：**设计完成 / 生产实测未执行（NEEDS_TEST）**

## 1. 边界与结论摘要

本轮只做只读审计、策略设计、代码与虚拟测试。未登录生产 VPS，未修改
Tailscale/Funnel/Xray/Nginx/443/防火墙/COS，未开放任何生产端口。

默认方案一句话：

> 家庭 PAW 不申请公网 IPv4、不做路由器入站端口映射；管理面走 Tailscale
> （必要时 Tailscale SSH），云侧 MCP 走 Tailscale Funnel 或现有 GPT Tunnel，
> SSH 22 默认只在 Tailnet/局域网；Xray VLESS 只作为首次入网失败时的临时
> **出站**通道，监听仅 127.0.0.1。

## 2. PAW 实际服务与端口策略

策略文件：`configs/home-port-policy.json`。审计器：
`scripts/paw-port-audit.sh`。下表是设计目标，不是生产实测结果。

| 端口 | 协议 | 用途 | 默认监听 | 公网开放 | 依赖公网 IPv4 | 依赖端口映射 |
|---|---|---|---|---|---|---|
| 22 | TCP | SSH 管理 | Tailnet + LAN | 否 | 否 | 否 |
| 80 | TCP | HTTP | 不监听 | 否 | 否 | 否 |
| 443 | TCP | HTTPS / Tailscale Serve / Funnel | Tailnet（Serve） | 仅 Funnel 入口 | 否 | 否 |
| 8080 | TCP | 内部 API | 127.0.0.1 | 否 | 否 | 否 |
| 8800 | TCP | PAW Gateway / MCP 控制面 | 127.0.0.1 + Tailnet | 否 | 否 | 否 |
| 41641 | UDP | Tailscale 直连 | 出站 / 通配绑定 | 否 | 否 | 否 |
| 3478 | UDP | Tailscale STUN | 出站 | 否 | 否 | 否 |
| 10808 | TCP | 临时 Xray SOCKS5 | 127.0.0.1 | 否 | 否 | 否 |
| 10809 | TCP | 临时 Xray HTTP（tailscaled） | 127.0.0.1 | 否 | 否 | 否 |

补充说明：

- `41641/3478` 是 **出站 UDP**。Tailscale 可以在没有入站映射的情况下工作，
  直连失败时自动走 DERP 中继；因此“没有公网 IP”不等于“Tailscale 不可用”。
- `443` 的 Funnel 入口由 Tailscale 的边缘节点承接，家庭侧仍然是出站连接，
  不需要家宽公网 IPv4，也不需要路由器端口映射。
- `8800` 绝不能绑 `0.0.0.0`。代码和策略都把它限制在 loopback/Tailnet。
- Xray 的 10808/10809 只允许 loopback；`paw-xray-proxy.sh` 与
  `paw-vless-uri-import.py` 都会校验监听地址。

## 3. Tailscale Serve 与 Funnel

| 能力 | 适用场景 | 是否需要家宽公网 IP | 是否需要端口映射 | 备注 |
|---|---|---|---|---|
| Tailscale SSH / 私网 IP | 用户 Windows、管理员 | 否 | 否 | 仅同一 Tailnet 内可达 |
| Tailscale Serve | Tailnet 内 HTTPS 发布 443 | 否 | 否 | 证书由 Tailscale 处理 |
| Tailscale Funnel | 云侧 MCP/浏览器公网访问 | 否 | 否 | 公网入口在 Tailscale 边缘 |
| GPT Tunnel | GPT 侧既有独立接入 | 否 | 否 | 保持原有方式，不混用 |

Claude / Gemini 等云端 MCP 调用方**不能假设**能访问 Tailscale 的 CGNAT 私有地址段
（不写入具体网段文本）。它们要么走 Funnel/既有公网 Tunnel，要么由调用方自身具备
Tailnet 接入能力；这一点必须逐项实测，本报告标为 `NEEDS_TEST`。

## 4. CGNAT / 双重 NAT / 路由器

- 武汉家宽可能处于 CGNAT 或双重 NAT；设计不依赖入站。
- Tailscale 出站 UDP 41641/3478 若被运营商阻断，会降级到 DERP 中继，
  功能可用但延迟/带宽下降；需要在家宽现场实测。
- 不做 UPnP、不做 DMZ、不做端口映射。
- 若用户以后确实需要公网入站，应单独评审，不复用本轮“默认不开放”结论。

## 5. 只读审计结果

### 5.1 生产 PAW / 旧 VPS

本轮**没有**生产 SSH 会话，无法采集真实 `ss -ltnuH`。因此：

- 生产端口现状：`NEEDS_TEST`
- 生产 Tailscale Serve/Funnel 现状：`NEEDS_TEST`
- 云侧 MCP 到 Funnel/Tunnel 的实际连通性：`NEEDS_TEST`
- 旧 VPS 作为 Exit Node 的批准状态：`NEEDS_TEST`

不得把开发机的监听表当成生产 PAW 的审计结果。

### 5.2 开发机审计器验证（负向样例）

在本开发机执行：

```bash
PAW_STATE_DIR=~/prehardware-20261111/port-audit/state \
PAW_REPORT_DIR=~/prehardware-20261111/port-audit/reports \
  bash scripts/paw-port-audit.sh ~/prehardware-20261111/port-audit/home-port-audit.json
```

结果：`status=FAIL, listeners=30, violations=13`（11 个未知公网/通配监听 +
2 个 SSH `0.0.0.0:22`/`[::]:22` 策略违规）。开发机本身是云工作站，存在
`0.0.0.0:22`、`0.0.0.0:5900`、`0.0.0.0:6080` 等公网监听；审计器按策略将
未知监听判为 `VIOLATION_UNKNOWN_PUBLIC`、将 SSH 判为 `VIOLATION_PUBLIC`。
这证明审计器能区分两类违规，**不是** PAW 生产环境违规。

证据：`reports/evidence/prehardware-20261111/devhost-home-port-audit.json`。

## 6. 迁移期间的身份与路径隔离

正式克隆期间旧 VPS 进入 Rescue Mode，原 Ubuntu 的 Xray/Tailscale 停止：

- 克隆走“新电脑 → 武汉家宽 → 腾讯云 Rescue 公网 SSH”的直连路径；
- 不依赖旧 VPS 的 VLESS，也不依赖 Exit Node；
- 旧 VPS 恢复正常 Ubuntu 后，只恢复 SSH + Xray/VLESS 网关和可选的
  Tailscale Exit Node；PAW/MCP/Nginx/Funnel/COS/轮询等业务身份默认不启动，
  避免新旧服务器重复身份。详见 `reports/PAW-SERVICE-CUTOVER-MANIFEST.md`。

## 7. 验收表

| 项目 | 状态 | 证据/说明 |
|---|---|---|
| 端口策略文件 | PASS（静态） | `configs/home-port-policy.json` |
| 监听分类审计器 | PASS（开发机负向测试） | 30 listeners / 13 violations（11 unknown + 2 SSH） |
| 未知公网监听检测 | PASS | 开发机 0.0.0.0/[::] 监听被标记 |
| 生产端口只读审计 | NEEDS_TEST | 未登录生产 VPS |
| Tailscale Serve | NEEDS_TEST | 需目标机在线 |
| Tailscale Funnel 公网入口 | NEEDS_TEST | 需 Tailnet/域名授权 |
| 云侧 MCP 经 Funnel 访问 | NEEDS_TEST | 需三家 MCP 实测 |
| GPT Tunnel 保持独立 | NEEDS_TEST | 不改动，待现场确认 |
| UDP 41641/3478 出站 | NEEDS_TEST | 需武汉家宽现场 |
| CGNAT/双重 NAT 影响 | NEEDS_TEST | 需现场路由信息 |
| 旧 VPS Exit Node | NEEDS_TEST | 需生产 Tailnet 只读确认 |
| 不依赖公网 IPv4/端口映射 | 设计 PASS | 架构本身不要求入站 |

## 8. 结论

架构层面已满足“无公网 IPv4、无端口映射”的默认部署要求；代码层面只把
本应私有的监听收紧到 loopback/Tailnet。所有生产现状与云侧 MCP 连通性仍为
`NEEDS_TEST`，必须在获得生产只读授权后补测，不能以本报告替代实测。
