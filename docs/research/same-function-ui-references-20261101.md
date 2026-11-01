# 与助盲跑同功能的界面截图对照（2026-11-01）

问题：两端每一屏，市面上哪些产品有同一功能、同一时刻的页面？

负责人否决静音版方案后要求只找同功能截图。本篇只列对应关系，不给改法。

## 选图规则

- 先看功能和时刻是否一致，再看好不好看。
- 功能对不上的不收，宁可写「没找到」。
- 只用 App Store 官方截图和本地已有截图。它们是营销图，常带外框和贴纸。

截图目录被 gitignore。重抓命令：

```bash
node scripts/fetch-reference-screenshots.mjs
```

对照板是本机文件：`docs/ui/reference-screenshots/_boards/same-function-*.jpg`。

## 对应关系

路径都相对 `docs/ui/reference-screenshots/`。

| 我们的页面 | 同功能页面 |
|---|---|
| 角色选择 | `be-my-eyes/01`（`I need visual assistance` / `I'd like to volunteer`） |
| 盲人首页 | `be-my-eyes/03`、`aira-explorer/02` |
| 匹配中 | `aira-explorer/03`（等待接线员） |
| 陪跑员赶来 / 已到达 | `uber/00`、`t3/05` |
| 跑步中 | `runna/01` |
| 结束后评价 | `lyft/04`、`xiaoai-bangbang/04` |
| 跑步记录列表 | `run-tracking/nike-run-club/02` |
| 求助与安全 | `caocao/04`、`t3/02`、`huaxiaozhu/05`、`ruqi/03` |
| 志愿者首页与接单开关 | `huaxiaozhu-driver/05`、`ruqi-driver/02` |
| 收到邀请 | `uber-driver/00`、`ruqi-driver/01`、`xiaoai-bangbang/01` |
| 前往集合点 | `uber-driver/06` |
| 成长与成就 | `ruqi-driver/04`（只算相近：司机等级与权益） |

## 没找到

- 语音说一句话下单：滴滴「小滴」有报道，没有界面截图。
- 跑步 App 手机端跑步中的真实页面：Nike Run Club、Keep、Strava 的官方截图都没有这一屏，只有 Runna 有。
- 打车 App 等待接单的页面：Uber、滴滴官方截图都没有。
- 跑后记录详情：`B32` 当天巡游失败（#639），没有我们自己的现状图，这一行没有对照。
- 下单表单、登录、通话磨合页、我的：本轮没有找。

## 被排除的

- `uber-driver/05` 收入页：我们的志愿者没有收入，功能不同。
- `xiaoai-bangbang/02`：是盲人接受志愿者，方向相反。

## 来源

- iTunes Lookup API，2026-11-01 抓取，App 编号见 `scripts/fetch-reference-screenshots.mjs`。
- [Be My Eyes 注册说明](https://support.bemyeyes.com/hc/en-us/articles/360005528717-Download-and-sign-up-for-Be-My-Eyes)：第一步选盲人用户或明眼志愿者。
- [Uber 帮助：如何叫车](https://help.uber.com/h/67f41961-e0aa-4670-af32-58be02c7c492)：只有文字说明，没有等待页截图。
- [新华网 2026-03-17 报道](https://www.news.cn/tech/20260317/5df749b54baa416d8587216b2b8a0164/c.html)：滴滴「小滴」支持一句话叫车。
