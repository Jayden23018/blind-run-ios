import SwiftUI

// 陪跑员首页「已约好」的预约单区块。从 `VolunteerHomeView.swift` 原样搬出，行为零改动 ——
// 那个文件只许变短（SwiftLint 棘轮 #488）。

/// 预约卡上已确认那一态（`PENDING_ACCEPT`）的按钮文案（#457）。
enum VolunteerScheduledOrderCopy {
    static let openOrder = "打开订单页"
    static let openOrderHint = "你已确认会去。到时间在订单页按「我出发了」"
}

/// 首页的「我的预约」区块 —— 跨天预约单（`SCHEDULED_CONFIRMED`）以及它们的临期确认动作。
///
/// **为什么它必须独立于「当前订单」和「近期服务」两块**：
/// - 与「当前订单」共用一个位会被即时单顶掉（见 `VolunteerHomeViewModel.scheduledOrders`）。
/// - 「近期服务」在语义上是历史（空态文案逐字是「完成服务后会显示在这里」），
///   而且只渲染 `prefix(3)`。把一个 60 分钟到期的待办混进历史列表，可发现性接近零。
///
/// 确认按钮直接摆在卡上、**不进二级页也不进溢出菜单** —— Rover 把改期藏进三点菜单、
/// 把接受放在会话线程里，是本轮调研里唯一被点名的反面教材。
struct VolunteerScheduledOrdersSection: View {
    let orders: [OrderDetailResponse]
    let submittingOrderID: Int64?
    let message: String?
    let onConfirm: (Int64) -> Void
    let onRelease: (Int64) -> Void
    /// `PENDING_ACCEPT` 的卡：打开这一单的订单页（`CardAction.openOrder`）。
    let onOpen: (OrderDetailResponse) -> Void
    /// 「我去不了」确认层里「会记一次临时取消」那句的窗口，取自 `AppState.ruleParams`。
    /// **不给默认值**，理由同 `VolunteerOrderFlowCopy.cancelSheet`。
    let lateCancelWindowHours: Int

    /// 要释放的那一单。二次确认是因为释放不可逆 —— 订单回派单池，抢不回同一个盲人
    /// （负责人 2026-10-17：保留二次确认，不跟邀请卡的「5 秒撤销」，#463）。
    @State private var pendingReleaseOrder: OrderDetailResponse?

    var body: some View {
        // `message` 非空时即使没有卡片也要渲染：加载失败而列表恰好为空是最需要说话的一刻，
        // 只按 `orders.isEmpty` 判会让那条提示无处可去（见 `applyUpcoming` 的失败分支）。
        if !orders.isEmpty || message != nil {
            VStack(alignment: .leading, spacing: 10) {
                Text("我的预约")
                    .font(AppFonts.body().weight(.bold))
                    .foregroundColor(AppColors.textPrimary)

                if let message {
                    Text(message)
                        .font(AppFonts.caption())
                        .foregroundColor(AppColors.warning)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(message)
                }

                // 每 10 秒一拍：放行时刻（`confirmGate`）到点后按钮自己亮起。不用 `.everyMinute`：
                // 它只在整分钟拍，放行时刻带秒时会晚开将近一分钟。
                TimelineView(.periodic(from: .now, by: 10)) { context in
                    ForEach(orders) { order in
                        card(order, now: context.date)
                    }
                }
            }
            // 与订单页「约好」屏同一个确认层（`VolunteerCancelSheet`，#463）：
            // 默认动作是黄色的「保留这次陪跑」，「仍然取消」是一行灰字，不用红色。
            .sheet(item: $pendingReleaseOrder) { order in
                VolunteerCancelSheet(
                    copy: VolunteerOrderFlowCopy.cancelSheet(
                        for: order.status,
                        plannedStart: order.plannedStart?.nilIfBlank?.backendTimestamp,
                        lateCancelWindowHours: lateCancelWindowHours
                    ),
                    isSubmitting: submittingOrderID == order.orderId,
                    onKeep: { pendingReleaseOrder = nil },
                    onCancelOrder: {
                        pendingReleaseOrder = nil
                        onRelease(order.orderId)
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    /// 卡上「确认我还会去」的后端放行时刻（后端 #546）：没到 `earliestDepartureAt` 时原位不可按、说出几点可以按。
    /// **只看 `SCHEDULED_CONFIRMED`** —— `PENDING_ACCEPT` 时同一个字段管的是 `en-route`，不是这枚按钮。
    static func confirmGate(order: OrderDetailResponse, now: Date) -> VolunteerActionGate {
        guard order.status == .scheduledConfirmed else { return .open }
        return VolunteerActionGate.resolve(action: .confirmDeparture, order: order, now: now)
    }

    /// 卡上那枚主按钮做什么（#457）。
    enum CardAction: Equatable {
        /// `SCHEDULED_CONFIRMED`：临期确认「我还会去」（`confirm-departure`）。
        case confirmDeparture
        /// `PENDING_ACCEPT`：已经确认过了，再调 `confirm-departure` 只会 409。
        /// 下一步「我出发了」在订单页上，所以这里给一条去订单页的路。
        case openOrder
    }

    static func cardAction(for order: OrderDetailResponse) -> CardAction {
        order.status == .scheduledConfirmed ? .confirmDeparture : .openOrder
    }

    /// 一张预约卡。整块 `children: .contain` —— 容器上的无障碍设置会向下盖掉子元素，
    /// 而这张卡上的两个按钮必须各自可被读屏聚焦、也必须能被 UI 测试分别找到。
    ///
    /// 🎨 **照订单页 v2「约好」屏做**（负责人 2026-10-17 拍板，#463；`docs/ui/mockups/INDEX.md`）：
    /// 卡片是订单页行卡的底、圆角与阴影；按钮是那一屏底部同一组 —— 黄色主按钮
    /// `FlowActionButton(.raisedPrimary)` + 灰字 `FlowTextButton`；时刻小字也同样摆在主按钮正上方。
    /// 唯一不同：「我去不了」可点区撑到 64pt —— 44pt 只是订单页的例外（`design-direction.md` §6.1），首页不在其内。
    /// 读屏顺序就是视觉顺序：时间 → 跑者 · 地点 → 主按钮（时刻在它的提示里）→「我去不了」。
    private func card(_ order: OrderDetailResponse, now: Date) -> some View {
        let isSubmitting = submittingOrderID == order.orderId
        let anySubmitting = submittingOrderID != nil
        let gate = Self.confirmGate(order: order, now: now)
        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                // 缺 `plannedStart` 时给一句话而不是空串：这一行是整张卡最重要的内容
                // （「什么时候」就是这一态的全部），空 `Text` 对读屏用户等于这张卡没有时间。
                Text(order.plannedStart?.nilIfBlank?.displayDateTime ?? "开跑时间待同步")
                    .flowFont(FlowV2Fonts.headline())
                    .foregroundColor(AppColors.Flow.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                Text("\(order.blindName ?? "盲人跑者") · \(order.startAddress ?? "出发地待同步")")
                    .flowFont(FlowV2Fonts.subhead())
                    .foregroundColor(AppColors.Flow.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // 竖直堆叠而不是并排：对标产品无一把两个动作并排放
            // （`blind-ui-visual-benchmark-20260808.md`「次级操作一律整行铺满竖直堆叠」），
            // 而且并排会让每个按钮的可点宽度减半，AX5 下文字直接被压成省略号。
            VStack(spacing: 8) {
                switch Self.cardAction(for: order) {
                case .confirmDeparture:
                    if let caption = gate.caption {
                        Text(caption)
                            .flowFont(FlowV2Fonts.subhead())
                            .foregroundColor(AppColors.Flow.secondaryText)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .fixedSize(horizontal: false, vertical: true)
                            // 已经拼进按钮的 hint，不再单独念一遍。
                            .accessibilityHidden(true)
                    }
                    FlowActionButton(
                        VolunteerServiceActionKind.confirmDeparture.title,
                        style: .raisedPrimary,
                        isLoading: isSubmitting,
                        isEnabled: !anySubmitting && !gate.isLocked,
                        accessibilityHint: [gate.caption, "告诉跑者你仍然会来。不确认这一单会转给其他志愿者"]
                            .compactMap { $0 }.joined(separator: "。"),
                        action: { onConfirm(order.orderId) }
                    )
                    .accessibilityIdentifier("volunteerScheduledConfirm-\(order.orderId)")
                case .openOrder:
                    // 白色次要按钮：订单页 `PENDING_ACCEPT` 解锁前那枚「我已经出发了」同一个样子。
                    FlowActionButton(
                        VolunteerScheduledOrderCopy.openOrder,
                        style: .outlined,
                        isEnabled: !anySubmitting,
                        accessibilityHint: VolunteerScheduledOrderCopy.openOrderHint,
                        action: { onOpen(order) }
                    )
                    .accessibilityIdentifier("volunteerScheduledOpen-\(order.orderId)")
                }

                FlowTextButton(
                    title: VolunteerServiceActionKind.releaseScheduled.title,
                    tone: .neutral,
                    accessibilityHint: "这一单会转给其他志愿者，需要确认后释放",
                    minHeight: AppTouchTarget.blindPrimary,
                    action: { pendingReleaseOrder = order }
                )
                .disabled(anySubmitting)
                .accessibilityIdentifier("volunteerScheduledRelease-\(order.orderId)")
            }
        }
        .padding(FlowMetrics.v2CardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.Flow.surface)
        .clipShape(RoundedRectangle(cornerRadius: FlowMetrics.v2RowRadius, style: .continuous))
        .flowCardShadow()
        .accessibilityElement(children: .contain)
    }
}
