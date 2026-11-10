"""Build a single-file, offline HTML quick guide for on-site use.

Everything is embedded (screenshots as base64 data URLs), so the file opens from a USB
stick or a phone without a network.  The text is a condensed version of
docs/PAW-START-HERE-ZH.md and reports/PAW-SCREEN-EXPECTATIONS-ZH.md; the full documents
stay authoritative and are referenced at the bottom.

Usage:  python scripts/build-offline-guide.py <delivery-dir>
"""

import base64
import os
import sys

DELIVERY = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "delivery")
SCREENS = [
    ("console-menu.png", "1. 控制台菜单", "必须看到 1) 登记 Memtest86+ … 6) 最终中文授权并开始迁移；中文不能是方块。"),
    ("pawdata-panel.png", "2. PAWDATA 初始化面板", "物理设备必须是你的 TF 卡，型号/容量/序列号要对得上；不对就不输入。"),
    ("pawdata-reject.png", "3. 输错后缀时的拒绝画面", "这是正确行为：明确说明没有改动任何东西。"),
    ("final-authorization.png", "4. 最终迁移授权面板", "逐行核对：源/目标/指纹/数据来源/数据损失。犹豫就 Ctrl-C，什么都不写。"),
    ("final-reject.png", "5. 最终确认输错时的样子", "会安全停止且不写入；重新按 6 再来。"),
]

HEAD = """<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>PAW v2.7 现场速查（离线）</title>
<style>
 body{font-family:-apple-system,"Segoe UI","Microsoft YaHei",sans-serif;margin:0;background:#f6f7f9;color:#1f2328;line-height:1.65}
 main{max-width:900px;margin:0 auto;padding:24px 18px 60px}
 h1{font-size:24px;margin:6px 0 10px}
 h2{font-size:18px;margin:28px 0 8px;border-left:4px solid #2f6feb;padding-left:10px}
 .lede{background:#fff;border:1px solid #e3e6ea;border-radius:10px;padding:14px 16px}
 .warn{background:#fff8e6;border:1px solid #f0d9a8;border-radius:10px;padding:12px 14px;margin:14px 0}
 .stop{background:#fdecec;border:1px solid #f0b8b8;border-radius:10px;padding:12px 14px;margin:14px 0}
 figure{margin:16px 0;background:#fff;border:1px solid #e3e6ea;border-radius:10px;padding:10px}
 figure img{width:100%;display:block;border-radius:6px}
 figcaption{font-size:13px;color:#57606a;margin-top:8px}
 ol,ul{padding-left:22px}
 code{background:#eef1f4;padding:1px 5px;border-radius:4px;font-family:ui-monospace,Consolas,monospace;font-size:92%}
 pre{background:#0d1117;color:#e6edf3;padding:12px 14px;border-radius:8px;overflow-x:auto;font-size:13px}
 pre code{background:none;color:inherit;padding:0}
 table{border-collapse:collapse;width:100%;font-size:14px;background:#fff}
 th,td{border:1px solid #e3e6ea;padding:7px 9px;text-align:left;vertical-align:top}
 th{background:#f1f3f6}
 footer{margin-top:34px;font-size:12px;color:#57606a}
</style>
</head>
<body><main>
"""


def img(name: str) -> str:
    path = os.path.join(DELIVERY, "screens", name)
    with open(path, "rb") as handle:
        blob = base64.b64encode(handle.read()).decode("ascii")
    return "data:image/png;base64," + blob


def build() -> str:
    parts = [HEAD]
    parts.append("<h1>PAW v2.7 现场速查（离线）</h1>")
    parts.append(
        '<div class="lede"><b>一句话：</b>云端构建与虚拟测试全部通过；'
        "实机 7 项还没做，所以现在不要拿它去覆盖你的生产盘。</div>"
    )
    parts.append("<h2>第 0 步：核对 ISO</h2>")
    parts.append(
        "<p>ISO 必须是 <b>953,155,584</b> 字节，SHA256 必须是</p>"
        "<pre><code>d9fe28799f9c18d1ec69900b66ea0c71d70b232c5e62a0c4ab0e902fb95a4476</code></pre>"
        "<p>Windows PowerShell 里：<code>Get-FileHash -Algorithm SHA256 .\\paw-live-amd64.iso</code>；"
        "或直接跑 <code>verify-delivery.ps1</code> 核对整包。</p>"
    )
    parts.append("<h2>前 3 件事（不碰你的 SSD）</h2>")
    parts.append(
        "<ol>"
        "<li>用 Rufus <b>DD 模式</b>把 ISO 写进 TF 卡，写完回读确认能列出分区。</li>"
        "<li>目标电脑从 TF 卡启动（Legacy/CSM），应出现 PAW 控制台菜单。</li>"
        "<li>启动菜单选 <b>Memtest86+</b> 跑至少一轮，回来后按 <code>1</code> 登记；再按 <code>2</code> "
        "初始化 PAWDATA（核对型号/容量/序列号，输入序列号最后 6 位）。</li>"
        "</ol>"
    )
    parts.append('<div class="warn">这两步只动 TF 卡上的 PAWDATA 分区，不写目标 SSD。</div>')
    parts.append("<h2>屏幕上应该是什么样</h2>")
    for name, title, note in SCREENS:
        parts.append("<h2>" + title + "</h2>")
        parts.append(
            '<figure><img src="' + img(name) + '" alt="' + title + '">'
            "<figcaption>" + note + "（CI 真实渲染截屏；图里是模拟数据，真机显示你的设备）</figcaption></figure>"
        )
    parts.append("<h2>之后再往下（需要你先做决定）</h2>")
    parts.append(
        "<ul>"
        "<li>按 <code>4</code> 登记目标 SSD，按 <code>5</code> 跑硬件检查（SMART / 只读扫描 / 温度 / 内存）。</li>"
        "<li>按 <code>3</code> 配置 Rescue SSH 并识别旧 VPS 源盘 —— <b>需要旧 VPS 进 Rescue Mode，会停机</b>。</li>"
        "<li>按 <code>6</code> 最终中文授权 → 整盘覆盖迁移，<b>目标 SSD 原有数据全部丢失</b>。</li>"
        "<li>迁移完关机换盘开机，做离线修复与首次启动检查。</li>"
        "</ul>"
    )
    parts.append("<h2>三条硬规矩</h2>")
    parts.append(
        '<div class="stop"><ol>'
        "<li>任何一步出现 <b>FAIL / WARN</b>，停下，不要\"再试一次\"绕过去。</li>"
        "<li>迁移成功并在新机验证通过之前，<b>旧 VPS 保持生产运行</b>，不要停、不要改。</li>"
        "<li><code>OPERATOR_CONFIRMED</code> 是\"你亲眼看过了\"，不是机器证明；别凭猜测填。</li>"
        "</ol></div>"
    )
    parts.append("<h2>出问题给我这些</h2>")
    parts.append(
        "<ol><li>出问题那一步的<b>屏幕照片</b>。</li>"
        "<li>菜单 <code>7) 查看状态和报告</code> 生成的报告文件。</li>"
        "<li>任何 FAIL/WARN 的原文。</li></ol>"
    )
    parts.append(
        "<footer>本页由 <code>scripts/build-offline-guide.py</code> 生成，图片内嵌、无外部引用，"
        "可离线打开。完整文档见交付包内 PAW-START-HERE-ZH.md、PAW-SCREEN-EXPECTATIONS-ZH.md、"
        "PAW-V2.7-HARDWARE-CHECKLIST-ZH.md。</footer>"
    )
    parts.append("</main></body></html>\n")
    return "".join(parts)


def main() -> int:
    html = build()
    out = os.path.join(DELIVERY, "PAW-QUICK-CARD-ZH.html")
    with open(out, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(html)

    problems = []
    # The five screenshots are 12-21 KB each, so an embedded page is ~120 KB. Assert the
    # real invariants instead of a guessed size: base64 payloads present, one per screen,
    # and no external reference anywhere.
    embedded = html.count("data:image/png;base64,")
    if embedded != len(SCREENS):
        problems.append("expected %d embedded images, found %d" % (len(SCREENS), embedded))
    if len(html) < 60000:
        problems.append("html looks truncated: %d bytes" % len(html))
    for token in ("http://", "https://", 'src="screens/', "src='screens/"):
        if token in html:
            problems.append("external reference found: " + token)
    if "</main></body></html>" not in html:
        problems.append("html is not closed")

    print("wrote %s (%d bytes)" % (out, os.path.getsize(out)))
    print("embedded_images=%d" % html.count("data:image/png;base64,"))
    if problems:
        for item in problems:
            print("FAIL " + item)
        return 1
    print("OFFLINE_GUIDE=PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
