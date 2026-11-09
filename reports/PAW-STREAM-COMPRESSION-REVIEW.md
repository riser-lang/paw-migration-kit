# SSH 流压缩复审

真实模式在 Rescue 源机运行 `dd | zstd -T1 -1`，压缩数据经 SSH 发送，在本机解压并写入目标盘。只有远端 bash/zstd 可用且报告可用内存不少于 256 MiB 时启用；否则报告明确标识 raw SSH fallback。`pipefail`、字节计数和 `CLONE-INCOMPLETE` 标记用于避免把中断误判为完成。

报告区分源盘字节数、SSH stdout payload 字节数和恢复字节数。payload 计数不包含 SSH/TCP framing。流结束后必须单独从 Rescue 源盘计算 SHA256，并与目标盘对应字节范围比较，才清除 incomplete 标记。

虚拟测试使用 mock SSH，只证明数据流控制和压缩/解压路径；不证明真实网络节省率或 Rescue SSH 环境兼容性。最终通过状态须来自候选提交的 Actions。
