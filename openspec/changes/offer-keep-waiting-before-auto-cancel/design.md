# 设计

## D1. 入口放在订单状态页，不放首页

首页那条常驻位已经被 SOS 条占着（`AGENTS.md` §6，唯一的例外形态），
而「继续等待」只在两个具体状态下有意义。放首页要么常驻（大多数时候是死按钮），
要么条件出现（首页的按钮会凭空长出来又消失，对读屏用户是最难跟的一种变化）。

订单状态页本来就按状态渲染，且已经有「重复当前状态」「问一句」两个按钮的版式。

## D2. 判定写成穷举 switch，与 `offersVolunteerCall` 同一套写法

```
var offersKeepWaiting: Bool {
    switch self {
    case .pendingMatch, .rematching: return true
    case .pendingAccept, .driverEnRoute, .driverArrived, .inProgress: return false
    case .completed, .cancelled, .noVolunteer: return false
    case .unknown: return false
    }
}
```

穷举而不是集合字面量：后端往 `OrderStatus` 加值时编译器在这里逼一次决策。
集合字面量会把新状态默默判成 `false` —— 那正是「点了没反应」的来源。

对照 `OrderDisplayHelpers.swift:77-90` 的 `offersVolunteerCall`，同一处文件、同一套理由。

## D3. 端点按状态分派，**不试第二个**

`PENDING_MATCH` → `keep-waiting`；`REMATCHING` → `keep-rematching`。

失败时**不许回退去试另一个端点**。两个端点的前置状态互斥，409 `ORDER_STATUS_NOT_ALLOWED`
的正确含义是「你手上的状态已经过期了」，此时该做的是刷新订单，不是换一个 URL 再打一次。
盲人听不见网络请求，连打两次的唯一可见结果是等待时间翻倍。

## D4. 不做二次确认

`AGENTS.md` §9 要求二次确认的是**危险操作**（取消订单、完成服务、退出登录、求助）。
「继续等待」是幂等的、可重复的、且方向是保住订单——误触的代价是多等一会儿，
而多一轮确认对读屏用户的代价是实打实的十几秒。

**取消订单那条仍然保留二次确认**，本变更不碰它。

## D5. 上限到了要如实说，并收起入口

后端 `websocket-protocol.md` 明写：**延长次数用尽后 `ORDER_CANCELLATION_WARNING` 不再推送** ——
「因为那时文案里的『点击继续等待可延长』已经不成立，发出去只会让用户去点一个必定失败的按钮」。

客户端要对齐这个口径：收到 409 `KEEP_WAITING_LIMIT_REACHED` 之后
① 播报「已经到了可延长的次数上限」并说明还能做什么（继续等系统匹配 / 取消重下）；
② 把该按钮从这一单的 UI 里移除，不留一个必定失败的按钮。

## D6. 乐观更新的边界

延长成功只返回 `{"success": true}`，订单状态**不变**（`PENDING_MATCH` 还是 `PENDING_MATCH`）。
所以不能靠「状态变了」来给用户反馈 —— 必须由客户端播一句本地文案。

文案不许承诺具体时长（「已为你延长 10 分钟」）：延长窗口是后端配置
（`app.match.max-keep-waiting-count` 及对应的超时值），客户端拿不到，编一个数字就是假信息。
说「已经告诉系统继续等」这类**进行时**表述，与 SOS 那条红线同一个道理。

## D7. 不新增 WebSocket 处理

`ORDER_CANCELLATION_WARNING` 目前走 `AppRealtimeCoordinator` 的通用分支被念出来
（`lifecycleStatus` 对它返回 nil，即「不是状态变化的重复播报，一律照播」），这已经是对的。
本变更只需要保证：那句播报响起时，**按钮已经在屏幕上**。

因为按钮由订单状态驱动（`PENDING_MATCH`/`REMATCHING` 恒显示），
而预警只在这两个状态下才会推送，所以不需要让通知去驱动 UI —— 少一条耦合。

## 被否掉的方案

- **自动续期**（收到预警就替用户调一次）：把「要不要继续等」这个决定从用户手里拿走了。
  用户可能正想让它取消。而且它会让延长次数在用户不知情的情况下耗尽。
- **把 `NO_VOLUNTEER` 改成非终态**：与后端定性相反（见 proposal「必须先纠正的认识」）。
- **在首页加入口**：见 D1。
