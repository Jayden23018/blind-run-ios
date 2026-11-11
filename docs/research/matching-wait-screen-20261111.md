# 匹配中的等待界面：别家怎么做，要不要做动画（#909，2026-11-11）

负责人 11-11 看完订单页 v7 后问：匹配界面要不要单独做一个动画？一般 App 的等待界面是怎么样的？

## 结论

**先分清等多久，再决定要不要动画。** 别家的等待界面按时长分成两类，做法相反：

| | 短等待（几秒到几分钟，人守在屏幕前） | 长等待（几小时到一天，人会离开） |
|---|---|---|
| 例子 | Aira「Waiting for Agent」、Be My Eyes 连线志愿者 | Airbnb 预订待房东确认、DoorDash「Confirming order」 |
| 主角 | 一个居中的转圈动画 + 一个挂断键 | 一句话说清谁在做什么 + 截止时间或时间区间 |
| 动画 | 有，循环转圈 | 没有循环动画；靠文字和时间说明进展 |
| 离开后 | 不需要离开 | 结果出来发通知；等待期间可以做别的、可以取消 |

**助盲跑的匹配属于长等待**：后端把转 `NO_VOLUNTEER` 的死线放在 `plannedStartTime - 30min`（`docs/api_spec.yaml` 第 2598、2832 行附近），提前一天约的单子可能等好几个小时。所以 **不建议做循环播放的整屏动画**；建议照长等待的做法，并在「找到陪跑员」那一刻做一次短动画。

## 别家的做法（按来源分级）

1. **Aira Explorer（App Store 截图，v4.20.3）**：等待接线员页只有三样东西：小字「Waiting for Agent」，中间一个大 Logo 外面绕一圈进度环，底部一个红色挂断键。这是短等待的典型做法，等的是几十秒到几分钟。
2. **Be My Eyes（官方帮助中心转述，原页被 Cloudflare 挡住，经搜索摘要）**：连线要先选一批志愿者、发通知、等人接，所以「自然比打电话慢」；第一批没人接就重来一批。官方的做法是**把为什么慢说出来**，而不是只放动画。
3. **DoorDash（App Store 截图第 3 张，v8.44.0）**：下单后「Confirming order」卡片上有：标题、到达时间区间「Arrives between 12:30 – 12:45 PM」、四格横向步骤、一句「We sent your order to CVS for final confirmation.」（说清订单现在在谁手上），卡片下面给一件等待时能做的事。截图里没有看到循环动画。
4. **Airbnb 帮助中心（原文已读，article 2810）**：预订请求发出后状态是 Pending，房东有 24 小时答复；期间可以联系房东、随时取消；没答复就转 Expired 并退款。长等待的要素是：状态名、截止时间、可以做的事、超时后会怎样。
5. **Uber（LottieFiles 官方案例访谈，原文已读）**：Uber 的动效团队把定制动画用在「庆祝时刻」，原话举例是匹配到女性司机、叫到电动车时的动画。动画放在**匹配成功的那一刻**，不是等待的过程中。
6. 打车 App 的「正在找司机」页：Uber、Lyft、滴滴、Grab 的 App Store 截图里都**没有**这一页（11-01 那份调研也没找到）。网上流传的雷达扩散图多是第三方仿制稿，不当参考。

## 规范原文

- **NN/g《Designing for Long Waits and Interruptions》（Kate Kaplan，2021-09-05，原文已读）**：循环动画「not appropriate for waits exceeding 10 seconds」，因为它不告诉用户值不值得等、要不要先去做别的；应给出已用时间（或已完成步骤）和剩余时间或步骤；长流程允许在后台跑，人可以先去做别的事。
- **Apple HIG《Progress indicators》（JSON 原文已读）**：能用确定进度就用确定进度；不确定进度只说明「在进行」，不帮人估计要等多久。指示器要一直在动，静止的指示器会让人以为卡住了。说明文字要具体，避免「loading」这类空话。
- **Apple HIG《Motion》（JSON 原文已读）**：「Don't add motion for the sake of adding motion」；动效要可选（Make motion optional），不能只靠动画传达重要信息，要同时用别的方式反馈。

## 用到助盲跑上

1. **等待中**：不做循环整屏动画。保留 v7 里「已等 N 分钟」（已用时间，NN/g 要求的那一半），加上**截止时间**：「开跑前 30 分钟还没找到，会通知你」（剩余时间的那一半；写法要等负责人定，死线规则以后端为准）。深色卡继续写「找到后陪跑员会先给你打电话」，这就是 DoorDash 那句「订单现在在谁手上」。
2. **让人知道没卡住**：竖线当前圆点做轻微呼吸（HIG：指示器要一直在动）；「已等 N 分钟」按分钟刷新。系统开了「减弱动态效果」时圆点不动，只靠分钟数刷新。
3. **找到陪跑员那一刻**：做一次 1 秒左右的短动画（照 Uber 的庆祝时刻），同时震动一次、播报一句。读屏用户靠震动和播报知道结果；不在等待期间循环放声音，以免和读屏抢话（记忆 `later-speak-silently-cuts-the-earlier-one`）。
4. **离开页面**：结果靠推送通知，不靠人守在页面上。

## 没查到

- Uber / 滴滴「正在找司机」页的官方截图或设计说明。
- Be My Eyes 等待页的官方截图（App Store 4 张截图里没有这一页）。
- 盲人用户对等待动画、等待提示音偏好的研究。

## 来源

- Aira Explorer App Store（id 1590186766）、DoorDash（id 719972451）、Lyft（id 529379082）、Grab（id 647268330）、Airbnb（id 401626263）、Be My Eyes（id 905177575）的官方截图，2026-11-11 用 iTunes lookup 接口取（重抓方法见 `docs/ui/mockups/blind-order-tracking-20261109/REFERENCES.md`）。截图有第三方版权，不进仓库。
- NN/g：https://www.nngroup.com/articles/designing-for-waits-and-interruptions/
- Apple HIG：https://developer.apple.com/tutorials/data/design/human-interface-guidelines/progress-indicators.json 、`.../motion.json`
- Airbnb 帮助中心：https://www.airbnb.com/help/article/2810
- Be My Eyes 帮助中心：https://support.bemyeyes.com/hc/en-us/articles/26540809142801-Calling-a-volunteer-FAQ （经搜索摘要转述）
- LottieFiles × Uber 案例：https://lottiefiles.com/case-studies/uber
