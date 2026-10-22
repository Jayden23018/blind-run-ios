import SwiftUI

// 志愿者「我的」首屏的最近陪跑。主体与排序在 `VolunteerProfileFirstScreenView.swift`。

extension VolunteerProfileFirstScreen {
    // MARK: - 最近陪跑

    /// 日期 + 一行主语 + 一行副信息，行高压得很紧，靠分隔线不靠卡片（调研 §2.5）。
    ///
    /// 数据用**已经在手的** `dispatchSummary.recentOrders`，不新开一条请求 ——
    /// 「全部 ›」进 `RunRecordHistoryView(role: .volunteer)`，那一页自己拉月度记录与 `GET /api/orders/mine`。
    @ViewBuilder
    var recentSection: some View {
        let orders = viewModel.dispatchSummary?.recentOrders ?? []

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                sectionLabel(VolunteerProfileCopy.recentSectionTitle)
                Spacer(minLength: 8)
                NavigationLink {
                    RunRecordHistoryView(role: .volunteer)
                } label: {
                    linkLabel(VolunteerProfileCopy.recentLinkTitle)
                }
                .accessibilityLabel("我的陪跑记录")
                .accessibilityHint(VolunteerProfileCopy.recentLinkHint)
                .accessibilityIdentifier("volunteerProfileRecentAllLink")
            }

            if orders.isEmpty {
                Text(VolunteerProfileCopy.recentEmpty)
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(orders.prefix(3).enumerated()), id: \.element.id) { index, order in
                        NavigationLink {
                            VolunteerOrderDetailView(orderId: order.orderId)
                        } label: {
                            recentRow(order, showsDivider: index < min(orders.count, 3) - 1)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("点击查看订单详情")
                        .accessibilityIdentifier("volunteerProfileRecentRow.\(order.orderId)")
                    }
                }
            }
        }
    }

    /// 🔴 **这一行不显示 `pointsText`，而改版前那张卡显示。这是必须的，不是漏了。**
    ///
    /// 积分与志愿服务时长**刻意分两屏**（中央网信办 2026-06-19 通知第 2 条，理由逐字在
    /// `VolunteerPoints.swift` 顶部与 `VolunteerHomeIncentiveSummary` 的注释里）。
    /// 改版前的首页**不显示累计时长**（时长只在成就页），所以那张卡上有积分是安全的；
    /// 而这一屏的 3 列统计第一格就是「陪伴时长 186 小时」——
    /// 再把积分放进同屏，两个数就会挨在一起，那正是两屏分法要防的事。
    ///
    /// 顺带一提 `pointsDelta` 后端至今没发过（恒 nil），所以删掉它在**今天**没有可见差异 ——
    /// 但别因此把它当无关紧要的顺手改动加回来：后端哪天真发了，加回来就是违规。
    private func recentRow(
        _ order: VolunteerDispatchSummaryRecentOrder,
        showsDivider: Bool
    ) -> some View {
        let date = VolunteerProfileRecentDate.parts(from: order.completedAt ?? order.plannedStartTime)
        return VStack(spacing: 0) {
            HStack(spacing: 12) {
                if let date {
                    VStack(spacing: 2) {
                        Text(date.day)
                            .font(AppFonts.body().weight(.bold))
                            .foregroundColor(AppColors.textPrimary)
                        Text(date.month)
                            .font(AppFonts.caption())
                            .foregroundColor(AppColors.textSecondary)
                    }
                    .frame(width: 40)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(VolunteerProfileCopy.recentRowTitle(blindName: order.blindName))
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(order.startAddress?.nilIfBlank ?? "地点待同步") · \(order.status.displayName)")
                        .font(AppFonts.caption())
                        .foregroundColor(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppColors.textSecondary.opacity(0.6))
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 10)

            if showsDivider {
                Rectangle()
                    .fill(AppColors.textSecondary.opacity(0.14))
                    .frame(height: 1)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            [
                date.map { "\($0.month)\($0.day)日" },
                // 上面那行 `Text` 用原样（带星号），这一份是念出来的，去掉星号。
                VolunteerProfileCopy.recentRowTitle(blindName: order.blindName?.unmaskedForSpeech),
                "地点：\(order.startAddress ?? "")",
                "状态：\(order.status.displayName)"
            ]
            .compactMap { $0 }
            .joined(separator: "，")
        )
    }
}
