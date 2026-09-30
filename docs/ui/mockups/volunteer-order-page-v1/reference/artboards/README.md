# 画板源码

来自设计画布 https://claude.ai/artifact/C9MMGSpVz9NtThjckXkUDV 的 v2 画板。

这些文件依赖设计工具的运行时（support.js），**不能直接在浏览器里打开**，也不要移植成代码。请当作文本读取，用来核对精确的颜色、字号、间距和 SVG 坐标。

| 文件 | 状态 |
|---|---|
| Invite.dc.html | ① 邀请 |
| Main.dc.html | ② 约好 · 前一晚 |
| MainSoon.dc.html | ②b 约好 · 出发前 30 分钟 |
| Depart.dc.html | ③ 出发 |
| Meet.dc.html | ④ 汇合 |
| Done.dc.html | ⑤ 完成 |
| LiveActivity.dc.html | 锁屏实时活动 |
| Rope.dc.html | 引导绳组件的五个状态 |

画板与文档冲突时，以 handoff 文档为准（例如出发提醒时间、锁屏只用姓氏）。
