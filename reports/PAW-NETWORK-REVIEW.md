# 网络与阶段边界复审

Rescue Mode 仅允许使用内存中的临时 SSH 配置和已固定主机密钥的直连通道，不自动启动 Xray 或 Tailscale。进入恢复后的 Ubuntu 阶段需单独由操作员选择网络阶段。

Xray 客户端 Reality 配置使用 `publicKey` 字段；UUID 输入隐藏，私钥不收集，配置只写入 `/run` RAM 文件并以 Xray 自检。日志不得包含凭据。Tailscale 加入只允许恢复后阶段。

mock/静态测试不等于实际腾讯云 Rescue 网络验证。实际服务器地址、账号密钥和令牌不得写入仓库、构建产物或日志。
