import Foundation

// MARK: - 志愿者侧「接单前通话磨合」：导航值与本轮落点
//
// 从 `VolunteerIntroCallView.swift` 原样搬出（#920，那个文件超了 SwiftLint 行数棘轮）。

/// 进通话页要带的东西。**两条到达路径共用一个导航源**，区别只在 `dispatchOrder` 有没有。
///
/// - 推送路径（`INTERESTED` 发出去之后）：`dispatchOrder` 有值，本单信息与导盲犬提示位照常渲染。
/// - **冷启动恢复路径**（`dispatch-summary` 的 `introCallOrderId`）：`dispatchOrder` 是 nil。
///
/// 恢复路径上**出发地与时间照常有** —— 它们来自 `IntroCallView`（后端为这件事专门加的
/// `startAddress` / `plannedStartTime`，字段说明里点名了「杀掉 App 再打开就回不到通话页」）。
///
/// 拿不到的只有**距离**和**导盲犬**：前者要 `distanceKm`（只在派单推送里），
/// 后者要 `escortNeeds`（同上）。这两块在恢复路径上不渲染，**这是诚实不是缺陷** ——
/// 志愿者据此判断的是「要不要接这一单」，编一个距离比空着更糟。
/// 不加 `Equatable`：`WSNewOrder` 是 `Codable, Sendable` 而非 `Equatable`，
/// 为了一个导航值给整条派单载荷补 `Equatable` 是本末倒置。
/// 断言拿 `orderId` 和 `dispatchOrder == nil` 比即可（后者对任何类型都成立）。
struct VolunteerIntroCallRoute {
    let orderId: Int64
    let dispatchOrder: WSNewOrder?

    init(orderId: Int64, dispatchOrder: WSNewOrder? = nil) {
        self.orderId = orderId
        self.dispatchOrder = dispatchOrder
    }

    init(dispatchOrder: WSNewOrder) {
        self.orderId = dispatchOrder.orderId
        self.dispatchOrder = dispatchOrder
    }
}

/// 本轮通话在志愿者这边的落点。
enum VolunteerIntroCallOutcome: Equatable {
    /// 还在通话磨合中。
    case active
    /// 双方都说合适 ⇒ 正式接单，可以进服务流程了。
    case matched
    /// 本轮结束但这一单不是你的（对方换人 / 你自己说了不合适 / 窗口超时 / 盲人取消了订单）。
    ///
    /// 🚨 **四种成因在界面上不区分。** 后端把它们全都发成同一条中性的 `INTRO_CALL_CLOSED`，
    /// 理由与盲人侧的无声拒绝对称：告诉志愿者「跑者拒绝了你」同样是在制造挫败，
    /// 而这个功能存在的意义就是让退出不带评判。
    case closed
}
