import SwiftUI

// MARK: - 「记录」里的「待进行的预约」（#660 B-5）

// 首页只显示 `GET /api/orders/active` 给的那**一张**（服务端取计划开始最早的一条），
// 而契约允许同时最多 3 张未完成预约（`TOO_MANY_SCHEDULED_ORDERS`）。第二张、第三张此前在 App 里没有落点：
// 打不开，也取消不了，只能等前一张走完 —— 到时可能已经被陪跑员接下，形成爽约。
// 数据仍从 `GET /api/orders/mine` 来（`RunRecordHistoryViewModel.loadUnfinished` 那一次请求），不加端点。

extension RunRecordHistoryViewModel {
    /// 全部还没走完的单，计划开始早的在前（跑者要先处理的是最近的那张）。
    ///
    /// 判据用 `isActiveForBlindRunner`，与首页、`GET /api/orders/active` 的「还没走完」同一口径：
    /// 未知状态也算（宁可多列一张让用户点开看，不替他判成已结束）。没有计划开始的排最后。
    static func upcomingBookings(from orders: [OrderDetailResponse]) -> [OrderDetailResponse] {
        orders
            .filter { $0.status.isActiveForBlindRunner }
            .sorted { lhs, rhs in
                switch (lhs.plannedStart?.backendTimestamp, rhs.plannedStart?.backendTimestamp) {
                case let (left?, right?): return left < right
                case (_?, nil): return true
                default: return false
                }
            }
    }

    /// 加载完念的那一句的开头。放在月度汇总前面：要处理的事比已经跑完的事急。
    static func upcomingAnnouncement(count: Int) -> String {
        count == 0 ? "" : "有 \(count) 张待进行的预约，在列表最上面。"
    }
}

/// 一行的文字。抽出来是为了让用例钉住「先说时间、再说状态」。
struct UpcomingBookingRowContent: Equatable {
    let timeText: String
    let statusText: String
    let placeText: String
    let accessibilityLabel: String

    init(order: OrderDetailResponse) {
        // 第一个词是时间：同时有几张预约时，用户靠时间认「是哪一张」。
        timeText = order.plannedStartForAnnouncement ?? "预约时间待确认"
        statusText = order.status.displayName
        placeText = order.startAddress?.nilIfBlank ?? "出发地点待确认"
        accessibilityLabel = "\(timeText)，\(statusText)，出发地 \(placeText)"
    }
}

/// 「待进行的预约」整段。列表为空时整段不渲染（不放「暂无」占位：多一次划动，没有信息）。
struct RunRecordUpcomingSection<Destination: View>: View {
    let orders: [OrderDetailResponse]
    @ViewBuilder let destination: (OrderDetailResponse) -> Destination

    var body: some View {
        if !orders.isEmpty {
            Section {
                ForEach(orders, id: \.orderId) { order in
                    NavigationLink {
                        destination(order)
                    } label: {
                        UpcomingBookingRow(content: UpcomingBookingRowContent(order: order))
                    }
                    .accessibilityHint("打开这张预约，可以查看进度或取消")
                }
            } header: {
                // 组标题色同「未完成的预约」：系统 `secondaryLabel` 浅色下对比度不够。
                Text("待进行的预约")
                    .foregroundColor(AppColors.textSecondary)
                    .accessibilityAddTraits(.isHeader)
            }
            .accessibilityIdentifier("runRecordUpcomingSection")
        }
    }
}

private struct UpcomingBookingRow: View {
    let content: UpcomingBookingRowContent

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(content.timeText)
                .font(AppFonts.body().weight(.semibold))
                .foregroundColor(AppColors.textPrimary)
            Text(content.statusText)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textSecondary)
            Text(content.placeText)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: FlowMetrics.actionButtonMinHeight, alignment: .leading)
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.accessibilityLabel)
    }
}
