## 1. 模型与错误码

- [ ] 1.1 `OrderDetailResponse` 加 `earliestBlindCancelAt`（宽容解码），`replacingStatus` 带过去，单测覆盖缺键 / null / 非字符串 / 正常
- [ ] 1.2 `ErrorCode` 加 `BLIND_CANCEL_TOO_EARLY`，`APIError.localizedMessage` 对它优先念后端 message；`node scripts/validate-error-codes.mjs` 通过

## 2. 跑者汇合页

- [ ] 2.1 `BlindArrivalCancelGate` + `BlindOrderFlowPresentation.arrivalCancel`，单测覆盖 null 不显示 / 到点前锁 / 到点开 / 坏值开
- [ ] 2.2 视图加「取消本单」行（64pt、置灰时读屏念时刻与打电话建议），点按走既有二次确认
- [ ] 2.3 `cancelOrder` 放行汇合态；409 两种错误的朗读；跨点自动变可按并播报一次
- [ ] 2.4 Mock：种子可带 `earliestBlindCancelAt`，取消按门槛回 409

## 3. 陪跑员端

- [ ] 3.1 `ORDER_CANCELLED_BY_BLIND_AFTER_ARRIVAL` 不进 `lifecycleStatus`（用例钉住）；陪跑中页面从汇合态进取消时念「可以离开集合点了」

## 4. 验证与收尾

- [ ] 4.1 UI 用例：到点前置灰并念时刻 / 到点可按 / null 不显示，真机跑通
- [ ] 4.2 `AGENTS.md` §5 更新
- [ ] 4.3 回帖后端 #696 并关闭
