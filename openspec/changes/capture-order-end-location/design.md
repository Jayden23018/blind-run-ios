# Design

## 三元组打包，不许平铺

`BookingEndPlace`（`OrderModels.swift`）把 `address` / `latitude` / `longitude` 装在一起，
`init` 里把半个坐标降级成「只有地名」。

否掉的是三个平铺的 `@Published`。后端 SPEC A 的决策表引了 `VoiceOrderService.Slots.fillFrom()`
的教训注释：地址三元组分别赋值会拼出「新地址 + 旧坐标」，读回念的是新地点、实际派到旧坐标，
而盲人完全听不出来。打包之后要换就整个换，这个 bug 在类型层面就不成立。

## 终点的判据是**结构**，不是后端那个标志位

后端给了 `endAddressUnresolved`，并声明它恒等于「`endAddress` 非 null 且 `endLatitude` 为 null」。
客户端**解它但不用它做判断**（`ParseVoiceOrderResponse.resolvedEndPlace` 按三元组自己算）。

理由：同一个事实有两个来源时只信结构。这个字段 2026-08-09 刚因为算错被后端修过一次（N39），
而三元组本身那时是对的。解它是为了漂移可见（将来两者对不上时能被测试抓到），不是为了依赖它。

## 起点是 `if let`，终点是整体赋值

`parseFreeform` 里起点写 `if let place = parsed?.resolvedStartPlace`，终点写
`bookingViewModel?.endPlace = parsed?.resolvedEndPlace`（含 nil）。

不对称是有理由的：起点抽不出有正当默认（当前位置，且读回会念出来），保留上一轮反而更糟；
终点没有默认值，留着上一轮的就是凭空多出一个用户这次没说过的目的地，
而屏幕上**没有任何终点控件**能让他察觉。

## 读回位置：紧跟起点，不进选填需求段

最省事的做法是把终点塞进 `optionalReviewItems` —— 视觉行和语音摘要一次解决，零新增属性。
否掉了：那样终点会排在预约时间**之后**。后端 `api_spec.yaml:2843` 明说读回是「起终点被抽反了」
唯一能被用户发现的地方，而两句挨着才听得出反没反。为此多加一个 `endPointSummary` 属性是值得的。

## 表单不加终点输入

终点是纯可选槽位。表单里要加它就得再来一遍 POI 搜索 + 候选列表 + VoiceOver 遍历顺序，
对看不见屏幕的人是和起点等长的第二段交互 —— 为一个可选字段付这个代价不划算。
语音降级回表单时终点跟着留下来并显示在复核页，所以「语音说了、改用表单继续」这条路不断。

## 超时改全局而不是按端点传参

`VoiceOrderWizard.parseTimeout` 8 → 12（后端每次调大模型，实测 3.4–4.3s，服务端兜底 8s）。
`APIClient.defaultSession.timeoutIntervalForRequest` 10 → 15，保证向导那层先响。

否掉了给 `APIClientProtocol.request` 加 `timeout` 参数：那会牵动两个实现和测试里所有 stub，
一个 idle 超时值不值这么大的面。上限写在注释里 —— 真需要按端点分档（例如上传要更长）时再抽。

## Mock 的终点抽取是 Demo 设施，不是契约镜像

线上终点**只由大模型抽，没有正则链路**（`api_spec.yaml:2846`），百炼不可用时恒为 null。
Mock 没有模型，完全不抽的话终点这条链路在真机之前一次都走不到 —— 读回文案、「未定位到」降级、
志愿者那一行全部无从验证。

所以加了一条只认 `跑到` 前缀的启发式。**不认裸 `到`** 是被语料钉死的：
「明天早上8:00到五角场跑四十分钟」的期望是起点 = 五角场（口语里「到那儿去跑」就是出发地），
裸 `到` 会让同一段文字既当起点又当终点，正是后端 2026-08-09 修掉的 N38。

`五角场` 不在 `mockVoicePlaces` 里，于是 Mock 天然会走到「有地址无坐标」那条分支。

## 顺带补上的两道守卫（不是本变更范围，但不补 Mock 就是错的）

语料从 45 条涨到 85 条，新增的两族暴露出 Mock 比后端松：

- **认不了的日期表达**（「8月10号」「下周三」「大后天」「下个月十号」）：Mock 的日期词只认
  明天/后天/今天，碰上这些不会失败，而是只取钟点、把日期当没说，再套「已过就滚次日」——
  「8月10号早上8点」被静默解析成次日 08:00。差 1 天的单能过提前量校验、读回念得很顺。
- **程度副词后的「一点」**：「慢一点」长得像「慢 1 点」，正好落进「N点」分支 → 凌晨 1 点。
  用户根本没提时间，系统却造出一个能过校验的时刻读给他听。

两条都逐字照抄后端 `VoiceSlotParser`（`UNSUPPORTED_DATE` / `isDegreeLeadIn`）。
同时 `spokenClockTime` 改成扫描**每一个**「点」而不是只看第一个 ——
对齐后端 `while (clock.find())` 的「跳过本次继续找」，否则「跑慢一点，明天早上八点出发」
会停在被拒的「慢一点」上，而真正的钟点在后半句。

## `startToEndDistanceKm` 不接

后端在 `AvailableOrderResponse` 上给了「起点→终点」直线距离。App 不调
`GET /api/orders/available`（公开订单池链路已删除，`MockAPIClient.swift:302`），
派单走 WebSocket `NEW_ORDER`，而那个载荷后端没加终点字段。已在 handoff 通报。
