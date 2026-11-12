# PAW CJK 完成提示测试夹具修复记录

日期：2026-11-12
分支：`vm/ds-final-prehardware-remediation-20261112`
状态：**4/5 CJK 场景已由 Run #95 验证；render 夹具已修复，待新 CI 全量验证**

## 1. Run #95 结果

Run #95（43192695240，HEAD `1c18a4a`）CJK 步骤：

```
Summary: 26 passed, 0 failed   (ok)
Summary: 17 passed, 0 failed   (bad)
Summary: 17 passed, 0 failed   (timeout)
Summary: 25 passed, 0 failed   (final)
Summary: 2 passed, 7 failed    (render)
Cases: 4 passed, 1 failed, 0 blocked
```

字体、framebuffer 逐单元匹配、中文 PAWDATA 提示、错误序列号、超时和最终
授权均已通过。唯一失败是 `render`：这证明生产 finalizer 的门禁是有效的，
夹具没有构造最新事务证据，而不是中文显示坏了。

## 2. 差异

`tests/qemu/paw-cjk-render-probe.sh` 旧夹具：

- 未设置 `PAW_FINALIZE_TEST_MODE=1`，finalizer 会执行
  `assert_transaction_stage finalize`；
- 未生成 `preboot-handoff.json`；
- `completion.json.checks` 仍是旧字段 `firstboot`；
- 最新 finalizer 要求五项：
  `clone`、`sha256`、`offline_repair`、`gpt_ext4_expand`、`preboot_handoff`；
- 未提供 PASS 的 `preboot-handoff.json`，因此在中文成功提示前正确拒绝。

## 3. 修复

`paw-cjk-render-probe.sh` 现在：

- 导出 `PAW_FINALIZE_TEST_MODE=1`，仅本显示测试跳过事务状态与真实介质
  移除门禁；生产 finalizer 的默认行为不变；
- 生成 `{"schema":"paw.preboot-handoff.v1","status":"PASS"}`；
- `completion.json` 使用：
  ```json
  {"clone":"PASS","sha256":"PASS","offline_repair":"PASS",
   "gpt_ext4_expand":"PASS","preboot_handoff":"PASS"}
  ```
- 保留独立 SHA256、离线修复、GPT 扩容、完成记录原子写入、mock reboot
  状态检查；
- 不降低字体匹配率，不删除中文断言；
- 正式事务状态机测试仍由 `run-finalize-virtual-tests.sh` 独立保留，未被
  这个显示夹具替代。

## 4. 验证要求

新 CI 必须重新跑五种真实 QEMU framebuffer 场景：

1. `ok`：正确序列号；
2. `bad`：错误序列号；
3. `timeout`：输入超时；
4. `render`：迁移完成/自动重启提示；
5. `final`：最终授权正确与错误。

每种都检查实际中文、实际标点、ASCII 标记、16x16 PSF 位图、framebuffer、
tty1、键盘输入和错误提示；不能只看串口文本。

## 5. 证据

- `tests/qemu/paw-cjk-render-probe.sh`
- `tests/qemu/qemu_cjk_screen_test.py`
- Run #95 的 `qemu-cjk-test-report.txt`（4/5）
- 新 CI 的 `qemu-cjk-*.log` 与 `evidence/final/cjk-*.json`
