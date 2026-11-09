# v3 照的真实截图

负责人 2026-11-09 要求照具体 App 的截图出图。截图是 App Store 官方截图（第三方版权），**不进仓库**。

| 本包的屏 | 照的截图 | 借了什么 |
|---|---|---|
| ② 出发、④ 已到达 | Uber（App Store id 368677368，v3.746.10001，2026-11-02 版）第 1 张「Meet at your pickup spot」 | 地图上标距离与上车点、已走实线 + 剩余点线；抽屉一句标题 + 蓝字副标题；人像行右侧放认人信息（Uber 是车牌）；「Send a message」输入条 + 电话圆钮 |
| ③ 匹配中 | United（id 449945214，v4.2.102，2026-10-28 版）第 3 张「Connection」 | 深色头部：小字行程名 + 大字状态 + 一行下一步；阶段胶囊（当前段白底）；信息卡（小标题 + 大字 + 三格小卡） |
| ⑤ 陪跑中 | United 第 2 张「Pre-boarding has started」；Uber 第 7 张「Share trip status」 | 三格小卡；安全一节只放分享状态 |
| ① 已约好 | 负责人原稿 `owner-draft-2-scheduled.png` | 完整竖向时间轴 |
| ⑥ 已完成 | 不改，沿用 `order-done-review-20261107/` | — |

参考过但没用：Lyft 第 5 张（完成后打分，我们评价放在跑步详情）；滴滴、Flighty（App Store 截图里没有同功能、同时刻的页面）。

## 重抓

```bash
# 例：Uber。country=us；United 换 id=449945214
curl -s "https://itunes.apple.com/lookup?id=368677368&country=us" | python3 -c "import sys,json;print('\n'.join(json.load(sys.stdin)['results'][0]['screenshotUrls']))"
```

URL 末段 `392x696bb.png` 换成 `1000x0w.jpg` 可拿 1000px 宽的图。本机要走代理：`curl -x http://127.0.0.1:7897`。
