## Why

订单从来没有「终点」这个概念。盲人说「从人民广场跑到五角场」时，后半句被整段丢掉：`CreateOrderRequest` 只有 `startAddress` / `startLatitude` / `startLongitude`，志愿者接单后也无从知道这一趟要跑去哪。

后端已于 2026-08-08 / 08-09 补齐（`demo/docs/SPEC-A-order-end-location.md`、`SPEC-B-voice-end-location.md`）：订单实体、`POST /api/orders` 请求体、`GET /api/orders/{id}` 详情、以及语音端点 `POST /api/orders/voice/parse` 四处都能带终点，`docs/api_spec.yaml` 已同步。前端此前**一个字段都没接**。

同时后端提醒了一条会让语音下单直接失效的变化：`/parse` 为了抽终点**每次都调大模型**（实测 3.4–4.3 秒，服务端兜底 8 秒），而客户端 `VoiceOrderWizard.parseTimeout` 正好是 8 秒、`APIClient` 的 idle 超时只有 10 秒 —— 本该成功的响应会被判成超时，等于把口语化长尾表达的兜底一并废掉。

## What Changes

- **终点只从语音进**。表单向导不加终点输入框：终点在产品上是纯可选槽位，而在表单里再加一段 POI 搜索 + 候选列表，对看不见屏幕的人是又一段和起点同样长的交互。
- **读回必须念终点，且紧跟起点念**。起终点由大模型抽取，抽反了（把出发地听成目的地）只有读回能被用户发现，而两句挨着才听得出反没反 —— 中间隔着预约时间就听不出来了。
- **说了地名但高德查不到坐标时，照样带地名下单**，并在读回里说清「这个地点没能定位到」。后端允许「有地址无坐标」（只有半个坐标才返 400）。静默丢掉的话，用户明明说了「跑到老王家门口」、读回却不念终点，盲人无从分辨是没听到还是没存下。
- **没说终点就一个字都不提**。`null` 的语义是「用户未指定」，**不是**「原路返回起点」；多播一句「本次没有结束地点」会让人以为系统漏听了他没说过的话。
- **两端订单详情展示「结束地点」**，为空整行不渲染；查不到坐标的标注「（未定位到）」—— 志愿者据此决定是导航过去还是当面问。
- **解析超时 8 → 12 秒**，`APIClient` 的 idle 超时 10 → 15 秒（保证向导那层先响，用户听到的是人话而不是网络错误）。
- 顺带把 Mock 与黄金语料重新对齐（语料已从 45 条涨到 85 条），并补上后端两道新守卫：认不了的日期表达（「8月10号」「下周三」）整句认输、程度副词后的「一点」不许当钟点。这两条不补，Mock 会造出用户从没说过的时刻。

## Capabilities

### Added Capabilities

- `order-end-location`：订单可携带可选终点；语音是唯一录入通道；终点的读回、降级与展示口径。

## Impact

- iOS：`ParseVoiceOrderResponse` / `CreateOrderRequest` / `OrderDetailResponse` 三个 DTO 加终点字段；新增 `BookingEndPlace` 值类型；`BlindBookingViewModel.endPlace` + `endPointSummary`；`VoiceOrderWizard.parseFreeform` 与 `confirmPrompt`；`BlindOrderStatusView`、`VolunteerOrderFlowViews` 各加一行；`MockAPIClient` 的终点抽取与两道时间守卫；`APIClient.defaultSession` 超时。
- 契约：**无需后端改动**，全部是已上线的可选字段。生成代码 `Packages/AidRunAPI` 已重新生成。
- **不消费 `AvailableOrderResponse.startToEndDistanceKm`**：App 不调 `GET /api/orders/available`（公开订单池链路已删除），派单走 WebSocket `NEW_ORDER`，而该载荷后端没有终点字段。已在 handoff 通报后端。
- **WS `ROUTE_CONFIRM_REQUIRED` / `ROUTE_CONFIRM_REQUIRED_WITH_END` 零代码**：`AppRealtimeCoordinator.routeNotification` 对未知 `eventType` 已走通用分支播 `ttsText`。本轮只答复后端「先只播报，不做可点击确认」——真要留痕需要后端加端点与字段，在前端存本地状态换设备就没了，而这条防线的价值恰恰在于能证明确认发生过。
- 风险面：起终点被模型抽反。缓解是读回把两者相邻念出，且终点为空时不编。**不缓解**的部分：用户没在读回时听出来就会照错的地点成单 —— 这与起点现有的风险同级，不新增。
- 文档：`docs/05-page-specs.md` 预约页读回段、`docs/09-accessibility-and-voice-guidelines.md` 必播报节点。
