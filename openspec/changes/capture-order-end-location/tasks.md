# Tasks

## 1. 契约层

- [x] 1.1 `ParseVoiceOrderResponse` 加 `endAddress` / `endLatitude` / `endLongitude` / `endAddressUnresolved`，`init` 参数带默认值
- [x] 1.2 加 `resolvedEndPlace`，规则比 `resolvedStartPlace` 松一档：有地名即算数，只有坐标不算，半个坐标降级
- [x] 1.3 新增 `BookingEndPlace` 值类型，`init` 守住「坐标成对」不变式
- [x] 1.4 `OrderDetailResponse` / `CreateOrderRequest` 加终点三字段；不加默认值，让编译器找齐 9 + 5 个构造点
- [x] 1.5 `replacingStatus` 带过终点三项（7 个 WS 状态更新调用点都经过它）

## 2. 下单与语音

- [x] 2.1 `BlindBookingViewModel.endPlace`
- [x] 2.2 `endPointSummary`：有坐标 / 无坐标两条文案；nil 返回空串
- [x] 2.3 `confirmPrompt` 与 `reviewSummarySpeech` 里紧跟 `startPointSummary` 插入
- [x] 2.4 `makeCreateOrderRequest` 带上三字段
- [x] 2.5 `resetVoiceFilledSlots` 清 `endPlace`
- [x] 2.6 `parseFreeform` 整体赋值（含 nil）

## 3. 展示

- [x] 3.1 `OrderDetailResponse.endAddressForDisplay`（nil = 整行不渲染；无坐标标「（未定位到）」）
- [x] 3.2 盲人端 `BlindOrderStatusView.orderInfoRows`
- [x] 3.3 志愿者端服务面板 + 订单信息两处
- [x] 3.4 语音读回卡 `voiceOrderRecap` 与表单复核页 `reviewSection`
- [x] 3.5 派单卡不动（`WSNewOrder` 无终点字段，且接单前刻意不给终点地址）

## 4. 超时

- [x] 4.1 `VoiceOrderWizard.parseTimeout` 8 → 12
- [x] 4.2 `APIClient.defaultSession.timeoutIntervalForRequest` 10 → 15（> 12，让向导那层先响）

## 5. Mock 与语料

- [x] 5.1 `mockVoiceEndSpan`（只认「跑到」）+ `matchedVoiceEndPlace`（与起点同段则丢弃）
- [x] 5.2 `handleVoiceParseOrder` 返回终点四字段
- [x] 5.3 补 `UNSUPPORTED_DATE` 守卫（逐字照抄后端）
- [x] 5.4 补程度副词守卫 + `spokenClockTime` 改为扫描每一个「点」
- [x] 5.5 黄金语料镜像补齐到 85 条（新增 START_TIME/none 整族）

## 6. 验证

- [x] 6.1 `build-for-testing` 编译门禁
- [x] 6.2 `validate-golden-corpus` / `validate-spec-coverage` / `validate-error-codes` / `validate-docs` / `validate-guard`
- [x] 6.3 `generate-api-client.sh` 重新生成并提交
- [x] 6.4 真机全量：535 passed / 0 断言失败；本变更新增的 10 条用例逐条 Passed
- [ ] 6.5 **UI 测试未执行** —— 设备走网络配对，runner bootstrap 时 `Lost connection to testmanagerd`。插 USB 后补跑 `blindRunUITests`
- [ ] 6.6 真机手测：语音说「从人民广场跑到五角场」→ 听读回起终点没抽反 → 志愿者接单后看「结束地点」行

## 7. 收尾

- [x] 7.1 `docs/handoff.md` 答复后端三条待答项 + 通报不消费 `startToEndDistanceKm`
- [ ] 7.2 commit + push + PR
