# 参考过的真实截图

截图是 App Store 官方截图（第三方版权），**不进仓库**。

| 本包的屏 | 照的截图 | 借了什么 |
|---|---|---|
| ⑤ 出发、⑥ 汇合 | Uber Driver（App Store id 1131342792，v4.592.10001）第 7 张「Picking up」 | 司机去接人：地图满屏，底部抽屉一行「8 min · 1.2 km」+「Picking up Jenny」。陪跑员去集合点与此同功能同时刻 |
| ①–④、⑦–⑨ | 盲人端 v7 定稿 `../blind-order-tracking-20261109/draft.png` | 两端同一套版式，只换陪跑员视角内容 |

## 重抓

```bash
curl -s -x http://127.0.0.1:7897 "https://itunes.apple.com/lookup?id=1131342792&country=us" | python3 -c "import sys,json;print('\n'.join(json.load(sys.stdin)['results'][0]['screenshotUrls']))"
```

URL 末段 `392x696bb.jpg` 换成 `1000x0w.jpg` 可拿大图。
