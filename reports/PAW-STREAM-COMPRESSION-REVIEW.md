# SSH 流压缩复审（v2.7）

真实模式仍在 Rescue 源机运行 `dd | zstd -T1 -1`，压缩数据经 SSH stdout 发送，在本机解压并写入目标盘。只有远端 bash/zstd 可用且报告可用内存不少于 256 MiB 时启用；否则明确标识 raw SSH fallback。

## 字节计数

- `ssh-payload-bytes.pending`：SSH stdout 的压缩 payload 字节数，不含 SSH/TCP framing。
- `restored-bytes.pending`：本地解压后实际写向目标的字节数。
- 两者必须完整产生；`restored_bytes` 必须等于源盘字节数，否则失败并保留 `CLONE-INCOMPLETE`。
- 压缩模式 `pv` 不再用原始大小伪装百分比；raw fallback 才按源大小显示进度。
- `stream-transfer-report.json` 记录 `source_bytes`、`ssh_stream_bytes`、`restored_bytes`、模式、传输类型和压缩原因。
- `paw-stream-verify.sh` 额外验证 `byte_count_streams_complete` 与 `restored_bytes`。

## 失败与回退

`pipefail`、远端 `bash -o pipefail -c`、两条计数流和独立 SHA256 共同防止短读/中断被误判为完成。传输结束仍必须从 Rescue 源盘单独计算 SHA256，并与目标盘对应字节范围比较，才清除 incomplete 标记。

## 测试

虚拟测试使用 mock SSH，数据改为全零 + 确定性随机 + 重复文本的混合 8 MiB 源，并注入 SSH 中断和短读。mock 只证明流控制、压缩/解压、计数和失败闭合，不证明真实网络节省率或 Rescue SSH 环境。结果以候选提交的 Actions 为准。
