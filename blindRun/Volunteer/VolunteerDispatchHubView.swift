import SwiftUI

// MARK: - 这一屏显示什么（纯函数）

/// 接单主页要显示的东西。
///
/// 抽成纯类型而不是散在视图里的一串 `if`：这是这一屏**唯一会悄悄坏掉**的地方 ——
/// 「下一次陪跑」取错一张单，屏幕上看起来完全正常（照样是一张深蓝卡、照样能点开），
/// 只是志愿者被带去了另一单。没有任何运行时信号。
struct VolunteerDispatchHubContent {
    /// 深蓝卡那一张。`nil` ⇒ 走空状态。
    let next: OrderDetailResponse?
    /// 「之后还有 N 次陪跑」里的 N。
    let laterCount: Int

    /// 🚩 **正在进行的那一单优先于预约单。**
    ///
    /// `activeOrder` 来自 `dispatch-summary.activeOrders`，后端白名单只有
    /// `IN_PROGRESS` / `DRIVER_EN_ROUTE` / `DRIVER_ARRIVED` —— 都是「人已经动起来了」。
    /// 那一刻把一张三天后的预约单顶在最上面，是把此刻唯一要紧的事推到列表里。
    ///
    /// `scheduledOrders` 已经由 `VolunteerHomeViewModel.applyScheduled` 按 `plannedStart`
    /// 升序排好且只含 `SCHEDULED_CONFIRMED`，这里**不再排一次** —— 两处各排一次迟早分叉。
    static func resolve(
        activeOrder: OrderDetailResponse?,
        scheduledOrders: [OrderDetailResponse]
    ) -> Self {
        if let activeOrder {
            return Self(next: activeOrder, laterCount: scheduledOrders.count)
        }
        return Self(
            next: scheduledOrders.first,
            laterCount: max(0, scheduledOrders.count - 1)
        )
    }

    /// 除了「下一次」之外的那几张，按原顺序。
    static func later(
        activeOrder: OrderDetailResponse?,
        scheduledOrders: [OrderDetailResponse]
    ) -> [OrderDetailResponse] {
        activeOrder == nil ? Array(scheduledOrders.dropFirst()) : scheduledOrders
    }
}

// MARK: - 空闲时间的一句话摘要

/// 把按周重复的时间段压成「周三晚、周六早」这一行。
///
/// ⚠️ **这是有损的**：`19:30–21:00` 压成「晚」丢掉了具体钟点。可以接受的理由是它只用在
/// 接单主页那一行**入口**上，点进去就是完整的时间段列表；而完整写法在 AX5 下两段就换行三次。
enum VolunteerAvailabilitySlotSummary {
    /// 一行最多列几段，多出来的并成「等 N 段」。
    static let inlineLimit = 2

    static func text(for slots: [VolunteerAvailableTimeSlot]) -> String? {
        let parts = slots.compactMap(phrase(for:))
        guard !parts.isEmpty else { return nil }
        guard parts.count > inlineLimit else { return parts.joined(separator: "、") }
        let head = parts.prefix(inlineLimit).joined(separator: "、")
        return "\(head) 等 \(parts.count) 段"
    }

    /// 「周三晚」。星期或开始时间缺一个就整段跳过 —— 一句「周三」或者一句「晚」都不是信息。
    static func phrase(for slot: VolunteerAvailableTimeSlot) -> String? {
        guard let day = weekdayName(slot.dayOfWeek), let period = period(slot.startTime) else { return nil }
        return day + period
    }

    static func weekdayName(_ raw: String?) -> String? {
        switch raw?.uppercased() {
        case "MONDAY": return "周一"
        case "TUESDAY": return "周二"
        case "WEDNESDAY": return "周三"
        case "THURSDAY": return "周四"
        case "FRIDAY": return "周五"
        case "SATURDAY": return "周六"
        case "SUNDAY": return "周日"
        default: return nil
        }
    }

    /// `"06:30:00"` → 「早」。**认不出的取值返回 nil**，不落到某个默认档 ——
    /// 后端换了时间格式时宁可这一行少一段，也不要把所有时段都说成「凌晨」。
    static func period(_ raw: String?) -> String? {
        guard let hour = hour(raw) else { return nil }
        switch hour {
        case 0..<6: return "凌晨"
        case 6..<11: return "早"
        case 11..<13: return "中午"
        case 13..<18: return "下午"
        case 18..<24: return "晚"
        default: return nil
        }
    }

    static func hour(_ raw: String?) -> Int? {
        guard let head = raw?.split(separator: ":").first, let hour = Int(head), (0..<24).contains(hour) else {
            return nil
        }
        return hour
    }

    /// 完整写法「周三 19:30 – 21:00」，给空闲时间编辑页与读屏用。
    static func fullText(for slot: VolunteerAvailableTimeSlot) -> String? {
        guard let day = weekdayName(slot.dayOfWeek) else { return nil }
        let start = clock(slot.startTime)
        let end = clock(slot.endTime)
        guard let start, let end else { return day }
        return "\(day) \(start) – \(end)"
    }

    /// `"06:30:00"` → `"06:30"`。
    static func clock(_ raw: String?) -> String? {
        guard let raw = raw?.nilIfBlank else { return nil }
        let parts = raw.split(separator: ":")
        guard parts.count >= 2 else { return nil }
        return "\(parts[0]):\(parts[1])"
    }
}

// MARK: - 文案

enum VolunteerDispatchHubCopy {
    static let title = "接单"
    static let acceptingPill = "接单中"
    static let emptyTitle = "暂时没有约好的陪跑"
    static let emptySubtitle = "你的空闲时间里有合适的陪跑，会邀请你"
    static let scheduleRowLabel = "空闲时间"
    static let scheduleRowEmptyValue = "还没设置"
    static let pauseTitle = "暂停接单"

    /// 逐字取自设计交付文档 v3 §4.3。
    static let pauseConfirmMessage = "暂停后不会收到新邀请，已约好的陪跑不受影响。"

    /// 🔴 **主按钮就是「暂停接单」，不是设计稿的黄色「保持接单」。**
    ///
    /// 设计稿把「保持接单」做成黄色主按钮、「暂停」做成灰字，那正是 Uber 在司机点下线时
    /// 弹当日收入目标劝其继续的那个形状（被 NYT 点名，在 gig 平台设计分类法里归入 dark pattern）。
    /// 说明本身有用（消除「会不会连已约好的单一起取消」这个真实担心），挽留式的按钮主次没用。
    static let pauseConfirmPrimary = "暂停接单"

    static let introCallCardTitle = "1 个待回复的邀请"
    static let introCallCardSubtitle = "通话磨合中，聊完记得表态"

    static func laterRowTitle(_ count: Int) -> String { "之后还有 \(count) 次陪跑" }
}

// MARK: - 接单主页

/// 滑动开始接单之后落到的那一屏（设计交付文档 v3 的 S3 / S4）。
///
/// 🚩 **它和首页的分工**：首页回答「我做过什么」（统计、勋章、最近一次），
/// 这一屏回答「我接下来要做什么」。两屏都能看到「接单中」——首页靠底部滑块的两态，
/// 这里靠标题右边那枚胶囊。
///
/// **没有黄色主按钮**：没有单是常态，不催促（设计交付 v3 §4.3）。
struct VolunteerDispatchHubView: View {
    /// 与首页共用同一个 view model —— 数据（预约单、派单摘要、接单开关）本来就只有一份，
    /// 这一屏再起一个会让两屏显示不同的「下一次陪跑」。
    @ObservedObject var viewModel: VolunteerHomeViewModel
    let onReload: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var route: Route?
    @State private var showsPauseConfirm = false
    @State private var showsLaterOrders = false

    /// 三个落点共用**一条** `navigationDestination(isPresented:)`。
    ///
    /// 🔴 不是三条 —— 同一个视图上挂多条 `isPresented` 版本在 iOS 16 上会互相顶掉
    /// （`VolunteerHomeView.swift:1098-1099` 已经为同一件事留过注释）。
    private enum Route {
        case order(id: Int64, initial: OrderDetailResponse?)
        case introCall(orderId: Int64)
        case schedule
    }

    private var content: VolunteerDispatchHubContent {
        .resolve(activeOrder: viewModel.activeOrder, scheduledOrders: viewModel.scheduledOrders)
    }

    private var laterOrders: [OrderDetailResponse] {
        VolunteerDispatchHubContent.later(
            activeOrder: viewModel.activeOrder,
            scheduledOrders: viewModel.scheduledOrders
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let next = content.next {
                    BlindHomeOrderCard(order: next, role: .volunteer) {
                        route = .order(id: next.orderId, initial: next)
                    }
                } else {
                    emptyState
                }

                introCallCard

                entryRows
            }
            .padding(.horizontal, FlowMetrics.pageHorizontalPadding)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .background(AppColors.Flow.page)
        .navigationTitle(VolunteerDispatchHubCopy.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                acceptingPill
            }
        }
        // 🔴 挂在**恒渲染**的 `ScrollView` 上，不是挂在「有约才显示」的那张卡上。
        // `.task` 附在条件为假时不存在的子树上就永远不会跑，而表现是「一直空着」——
        // 记忆 `task-on-empty-view-never-fires`，本仓库 2026-09-14 已经栽过一次。
        .task {
            await onReload()
        }
        .navigationDestination(
            isPresented: Binding(
                get: { route != nil },
                set: { if !$0 { route = nil } }
            )
        ) {
            switch route {
            case .order(let id, let initial):
                VolunteerInServiceView(orderId: id, initialOrder: initial)
            case .introCall(let orderId):
                VolunteerIntroCallView(route: VolunteerIntroCallRoute(orderId: orderId))
            case .schedule:
                VolunteerAvailabilityScheduleView()
            case nil:
                EmptyView()
            }
        }
        .confirmationDialog(
            VolunteerDispatchHubCopy.pauseTitle,
            isPresented: $showsPauseConfirm,
            titleVisibility: .visible
        ) {
            Button(VolunteerDispatchHubCopy.pauseConfirmPrimary) {
                viewModel.setAvailability(false)
                // 暂停之后这一屏没有任何可做的事了，退回首页 —— 留在原地只会看到
                // 一枚已经不成立的「接单中」胶囊。
                dismiss()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(VolunteerDispatchHubCopy.pauseConfirmMessage)
        }
    }

    // MARK: 顶部胶囊

    private var acceptingPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(AppColors.Flow.acceptingText)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(VolunteerDispatchHubCopy.acceptingPill)
                .flowFont(FlowFonts.rowValueEmphasized())
        }
        .foregroundColor(AppColors.Flow.acceptingText)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(AppColors.Flow.acceptingBackground, in: Capsule())
        .accessibilityElement(children: .combine)
        // 值而不是标签：胶囊说的是「接单开关此刻是开的」，附上 view model 那半句
        // （「正在等待系统派单」/「不在空闲时间内」）才说得完整。
        .accessibilityLabel("\(VolunteerDispatchHubCopy.acceptingPill)，\(viewModel.statusText)")
        .accessibilityIdentifier("volunteerDispatchHubAcceptingPill")
    }

    // MARK: 空状态

    private var emptyState: some View {
        FlowCard(cornerRadius: FlowMetrics.homeCardRadius) {
            VStack(spacing: 10) {
                Image(systemName: "bell")
                    .font(.system(size: 30, weight: .regular))
                    .foregroundColor(AppColors.Flow.accent)
                    .frame(width: 64, height: 64)
                    .background(AppColors.Flow.avatarBackground, in: Circle())
                    .accessibilityHidden(true)
                    .padding(.top, 28)

                Text(VolunteerDispatchHubCopy.emptyTitle)
                    .flowFont(FlowFonts.bookingTitle())
                    .foregroundColor(AppColors.Flow.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)

                Text(VolunteerDispatchHubCopy.emptySubtitle)
                    .flowFont(FlowFonts.bookingSubtitle())
                    .foregroundColor(AppColors.Flow.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 28)
            }
            .padding(.horizontal, FlowMetrics.pageHorizontalPadding)
            .frame(maxWidth: .infinity)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("volunteerDispatchHubEmptyState")
    }

    // MARK: 待回复的邀请

    /// 🚩 **只有通话磨合中的那一单会出现在这里，不是设计稿里的「N 个新邀请」。**
    ///
    /// 后端没有「待回复邀请列表」这种持久态：派单是 WS 瞬时推送 + `dispatchTimeoutSeconds`
    /// （默认 30 秒）超时自动转下一位，已经由全屏的 `VolunteerDispatchOverlay` 接管。
    /// 唯一**持久、且确实等着志愿者表态**的是 `dispatch-summary.introCallOrderId`。
    /// 其余情况整块不画 —— 摆一个「0 个新邀请」的空壳，只会每次提醒志愿者他没单。
    /// 「预约单该有 1 小时回复期限」已投 handoff。
    @ViewBuilder
    private var introCallCard: some View {
        if let orderId = viewModel.dispatchSummary?.introCallOrderId {
            Button {
                route = .introCall(orderId: orderId)
            } label: {
                HStack(spacing: 16) {
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: FlowMetrics.bookingPlusDiameter, height: FlowMetrics.bookingPlusDiameter)
                        .background(AppColors.Flow.accent, in: Circle())
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(VolunteerDispatchHubCopy.introCallCardTitle)
                            .flowFont(FlowFonts.homeCardRowTitle())
                            .foregroundColor(AppColors.Flow.bookingTitle)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(VolunteerDispatchHubCopy.introCallCardSubtitle)
                            .flowFont(FlowFonts.bookingSubtitle())
                            .foregroundColor(AppColors.Flow.bookingSubtitle)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(AppColors.Flow.bookingTitle)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, FlowMetrics.bookingBlockHorizontalPadding)
                .padding(.vertical, 18)
                .background(AppColors.Flow.bookingBackground)
                .clipShape(RoundedRectangle(cornerRadius: FlowMetrics.homeCardRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(
                "\(VolunteerDispatchHubCopy.introCallCardTitle)，\(VolunteerDispatchHubCopy.introCallCardSubtitle)"
            )
            .accessibilityHint("双击打开通话页，给跑者打电话并表态")
            .accessibilityIdentifier("volunteerDispatchHubIntroCallCard")
        }
    }

    // MARK: 入口行

    private var entryRows: some View {
        FlowCard {
            VStack(spacing: 0) {
                if content.laterCount > 0 {
                    laterRow
                    if showsLaterOrders {
                        ForEach(laterOrders, id: \.orderId) { order in
                            FlowSeparator()
                            laterOrderRow(order)
                        }
                    }
                    FlowSeparator()
                }

                if content.next == nil {
                    scheduleRow
                    FlowSeparator()
                }

                pauseRow
            }
        }
    }

    private var laterRow: some View {
        FlowInfoRow(
            label: nil,
            kind: .navigable(action: { showsLaterOrders.toggle() }),
            accessibilityLabel: VolunteerDispatchHubCopy.laterRowTitle(content.laterCount),
            accessibilityHint: showsLaterOrders ? "双击收起" : "双击展开，逐条查看"
        ) {
            Text(VolunteerDispatchHubCopy.laterRowTitle(content.laterCount))
                .flowFont(FlowFonts.rowValue(), monospacedDigit: true)
                .foregroundColor(AppColors.Flow.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("volunteerDispatchHubLaterRow")
    }

    private func laterOrderRow(_ order: OrderDetailResponse) -> some View {
        FlowInfoRow(
            label: nil,
            kind: .navigable(action: { route = .order(id: order.orderId, initial: order) }),
            accessibilityLabel: laterOrderAnnouncement(order),
            accessibilityHint: "双击打开这一单"
        ) {
            VStack(alignment: .leading, spacing: 2) {
                Text(order.blindRunnerShortStartText() ?? order.status.displayName)
                    .flowFont(FlowFonts.rowValue(), monospacedDigit: true)
                    .foregroundColor(AppColors.Flow.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(order.startAddress?.nilIfBlank ?? "出发地点待确认")
                    .flowFont(FlowFonts.rowDetail())
                    .foregroundColor(AppColors.Flow.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 读屏念完整日期，不念「明天」——听的人没有屏幕可以回看。同深蓝卡的既定口径。
    private func laterOrderAnnouncement(_ order: OrderDetailResponse) -> String {
        let time = order.plannedStartForAnnouncement ?? order.status.displayName
        let place = order.startAddress?.nilIfBlank ?? "出发地点待确认"
        return "\(time)，\(place)"
    }

    private var scheduleRow: some View {
        let summary = VolunteerAvailabilitySlotSummary.text(
            for: viewModel.dispatchSummary?.availableTimeSlots ?? []
        )
        return FlowInfoRow(
            label: VolunteerDispatchHubCopy.scheduleRowLabel,
            kind: .navigable(action: { route = .schedule }),
            accessibilityLabel: "\(VolunteerDispatchHubCopy.scheduleRowLabel)，"
                + (summary ?? VolunteerDispatchHubCopy.scheduleRowEmptyValue),
            accessibilityHint: "双击修改你每周哪些时间有空"
        ) {
            Text(summary ?? VolunteerDispatchHubCopy.scheduleRowEmptyValue)
                .flowFont(FlowFonts.rowValue())
                .foregroundColor(AppColors.Flow.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityIdentifier("volunteerDispatchHubScheduleRow")
    }

    private var pauseRow: some View {
        FlowInfoRow(
            label: nil,
            kind: .navigable(action: { showsPauseConfirm = true }),
            accessibilityLabel: VolunteerDispatchHubCopy.pauseTitle,
            accessibilityHint: "双击后会先确认一次"
        ) {
            Text(VolunteerDispatchHubCopy.pauseTitle)
                .flowFont(FlowFonts.rowValue())
                .foregroundColor(AppColors.Flow.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("volunteerDispatchHubPauseRow")
    }
}
