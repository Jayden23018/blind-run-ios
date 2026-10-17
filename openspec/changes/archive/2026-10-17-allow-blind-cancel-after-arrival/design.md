## Context

见 proposal.md。跑者订单页汇合态已有一个同形的先例：「开始跑步」按 `earliestServiceStartAt` 置灰、读屏说钟点、靠 5 秒轮询到点变亮（`BlindOrderFlowPresentation.startRunOpensAt`）。陪跑员端「结束等待」按 `earliestEndWaitAt` 原位换按钮。

## Goals / Non-Goals

**Goals:** 跑者在汇合态有一个按后端时刻开闭的取消入口；陪跑员在集合点听得到「可以离开了」。

**Non-Goals:** 不改契约；不动 `canBlindRunnerCancel`（它只按状态判，首页与旧滚动列表也在读）；不给陪跑员端的跑者取消完成屏换文案（取消后的订单详情里没有「是不是到达后取消的」这一信息，硬推断就是编）。

## Decisions

1. **入口是信息卡里一行新的「取消本单」，放在「遇到问题」上面。** 不复用最后一行：最后一行在不能取消的态打开求助中心，置灰它会让到点前「遇到问题」这条路一起消失。不放底栏：底栏两个版位（主按钮 + 求助与安全）按设计永不变化，视障用户靠位置记忆。
2. **门槛判定抽成纯值 `BlindArrivalCancelGate`（`nil` / `.locked(opensAt:)` / `.open`）**，由 `BlindOrderFlowPresentation.make` 带出，视图只渲染。字段有值但解析不出 ⇒ `.open`（由后端判，同 `startRunOpensAt` 的口径）。
3. **解码宽容用属性包装 `LenientOptionalString`** + `KeyedDecodingContainer.decode` 重载：调用方仍是 `String?`，缺键 / `null` / 非字符串都得 `nil`。不改整个 `OrderDetailResponse` 的手写 `init(from:)`——那会让 60 个字段一起换写法。
4. **跨点播报不另起定时器**：`apply` 每 5 秒一次（轮询），记住上一次的门槛，`.locked → .open` 时播一句。并发模型与轮询同一条（AGENTS 硬约束）。判据是静态纯函数，可单测。
5. **`BLIND_CANCEL_TOO_EARLY` 走 `ErrorCode.prefersServerMessage`**：`APIError.localizedMessage` 对这一类码优先念后端 `message`（非空时），否则用本地兜底。`ORDER_HAS_ACTIVE_EMERGENCY` 的本地文案是写给陪跑员「结束服务」的，跑者取消这一路在 `cancelOrder` 里换成跑者口径。
6. **陪跑员端不把新事件映射进 `lifecycleStatus`**：映射就会在「有活跃订单」时被吞掉，而那正是陪跑员站在集合点的时刻。后端 `ttsText` 已含「你可以离开集合点了」。陪跑中页面自己的那句按「上一态是不是 `DRIVER_ARRIVED`」加同一句话 —— 两句谁后到都说清了能离开。

## Risks / Trade-offs

- [到点最多晚 5 秒变亮] → 与「开始跑步」同口径；按下早了后端 409 会念出时刻。
- [陪跑员可能连听两句相近的话（通知 + 页面）] → 后到的会打断先到的，两句都含「可以离开」，不丢信息。
- [#340 / #391 也在改 `OrderDetailResponse` 与实时协调器] → 合并前 rebase 解冲突。
