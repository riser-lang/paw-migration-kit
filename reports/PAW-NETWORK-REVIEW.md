# 网络与阶段边界复审（v2.7）

Rescue Mode 仅允许使用内存中的临时 SSH 配置和已固定主机密钥的直连通道，不自动启动 Xray 或 Tailscale。进入恢复后的 Ubuntu 阶段需单独由操作员选择网络阶段。

## 网络配置

- Live 的 systemd-networkd 使用 `Name=en* eth*`。
- 离线修复生成的 Netplan 使用 `name: "e*"`，覆盖 `eth0`、`enp3s0`、`en*` 和 Realtek r8169；保留 DHCP，禁用 cloud-init 网络覆盖。
- 旧系统可能使用 `net.ifnames=0 biosdevname=0`，因此不再只匹配 `en*`。

## Xray / Tailscale

Xray 客户端 Reality 配置使用 `publicKey` 字段；UUID 输入隐藏，私钥不收集，配置只写入 `/run` RAM 文件并以 Xray 自检。监听必须仅为 `127.0.0.1`；非 loopback 监听直接拒绝。日志不得包含凭据。

Tailscale 加入只允许恢复后阶段；直连不可用时才启动 RAM-only Xray。登录 URL 只输出到控制台，不写 auth key。未授权/超时写 `AWAITING_USER_AUTH_OR_CONTROL_CONNECTIVITY`，不伪造 `ONLINE`。直连恢复后由单独脚本撤掉临时 Tailscale 代理。

## 测试

新增 mock 网络测试：Rescue 无直连阻断、Restored 缺 Xray 配置阻断、Xray 非 loopback 拒绝、Xray 临时代理路径、Tailscale 登录成功/等待超时、无 auth key 文件。mock/静态测试不等于真实腾讯云 Rescue 网络、真实 Tailscale 授权或真实 Xray 服务端验证。
