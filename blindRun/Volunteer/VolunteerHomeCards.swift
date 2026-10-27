import SwiftUI

// 陪跑员首页的当前订单卡、派单摘要卡与数字格。从 `VolunteerHomeView.swift` 原样搬出，行为零改动 ——
// 那个文件只许变短（SwiftLint 棘轮 #488）。

struct VolunteerCurrentOrderCard: View {
    let order: OrderDetailResponse

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: order.status.statusSymbolName)
                .font(.title3)
                .foregroundColor(order.status.statusColor)
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("当前订单")
                        .font(AppFonts.caption().weight(.semibold))
                        .foregroundColor(AppColors.textSecondary)
                    Text(order.status.displayName)
                        .font(AppFonts.caption().weight(.semibold))
                        .foregroundColor(order.status.statusColor)
                }

                Text(order.blindName ?? "盲人跑者")
                    .font(AppFonts.body().weight(.bold))
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)

                Text(order.startAddress ?? "")
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Text((order.plannedStart ?? "").displayDateTime)
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.76)

                Label("进入", systemImage: "chevron.right")
                    .labelStyle(.titleAndIcon)
                    .font(AppFonts.caption().weight(.semibold))
                    .foregroundColor(AppColors.primary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppColors.background.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: VolunteerHomeRadius.card, style: .continuous))
        .shadow(color: Color.black.opacity(0.12), radius: 14, x: 0, y: 5)
    }
}

/// 派单状态卡：覆盖范围 + 完成·评分·接单率 + 派单·接受·拒绝·超时。
///
/// 🚩 **internal 而不是 private**：唯一的渲染点在 `VolunteerProfileFirstScreen.dispatchSection`
/// （另一个文件）。它被刻意摆在首屏**最底部**、接替 2026-09-15 删掉的那行工作台入口 ——
/// 「等待派单」页出来时搬走它 = 删首屏 `VStack` 里的一行 + 整个 struct 挪过去，不用重构。
/// 调研 §1 的三档分类里它是第三档「普通信息卡片」，不该占中段。
///
/// 🔴 **卡里不再有「去培训」按钮。** 那个入口以前是这张卡的兄弟节点，小得用户找不到
/// （原话「一个贼小的去培训，一点都不显眼」），已整体升级成首屏作业区里的整卡入口。
struct VolunteerDispatchSummaryCard: View {
    let summary: VolunteerDispatchSummaryResponse

    /// 三格，不是四格。此前第一格是「积分」，值是 `totalCompleted * 100` ——
    /// 后端从来没有 `pointsBalance` 字段，那个数字只是「完成 N 单」换了个说法，
    /// 却被命名成一种可累积、可兑换的东西。
    ///
    /// ponytail: 删掉后**不补第四格凑数**。`totalDispatched` / `totalDeclined` /
    /// `totalTimeout` 在下面本来就有一行专门展示，挪上来只是重复。
    private var metrics: [(String, String)] {
        [
            ("完成", "\(summary.completedCount)"),
            ("评分", summary.ratingText),
            ("接单率", summary.acceptanceRateText)
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: summary.canDispatch == true ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(summary.canDispatch == true ? AppColors.success : AppColors.warning)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.dispatchStatusText)
                        .font(AppFonts.body().weight(.bold))
                        .foregroundColor(AppColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(summary.coverageText)
                        .font(AppFonts.caption())
                        .foregroundColor(AppColors.textSecondary)
                }

                Spacer(minLength: 0)
            }

            // 列数跟着 `metrics` 走，不写字面量 —— `be4e030` 删掉「积分」那格时列数留在 4，
            // 于是三格挤在左边、右边空一格挂了很久。
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: metrics.count), spacing: 8) {
                ForEach(metrics, id: \.0) { metric in
                    VolunteerMetricTile(title: metric.0, value: metric.1)
                }
            }

            HStack(spacing: 8) {
                Text("派单 \(summary.totalDispatched ?? 0)")
                Text("接受 \(summary.totalAccepted ?? 0)")
                Text("拒绝 \(summary.totalDeclined ?? 0)")
                Text("超时 \(summary.totalTimeout ?? 0)")
            }
            .font(AppFonts.caption())
            .foregroundColor(AppColors.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
        }
        .padding(14)
        .background(AppColors.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: VolunteerHomeRadius.card, style: .continuous))
        .accessibilityElement(children: .combine)
        // 「积分 N」也从这条 label 里删掉 —— 数字从视觉上消失了，但读屏用户还在听，
        // 这一处最容易漏。
        .accessibilityLabel("派单状态：\(summary.dispatchStatusText)，\(summary.coverageText)，完成 \(summary.completedCount) 次，评分 \(summary.ratingText)")
    }
}

/// internal 与 `VolunteerDispatchSummaryCard` 同理：它只被那张卡用，而那张卡已经跨文件了。
struct VolunteerMetricTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline.weight(.bold))
                .foregroundColor(AppColors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(title)
                .font(AppFonts.caption())
                .foregroundColor(AppColors.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(AppColors.background)
        .clipShape(RoundedRectangle(cornerRadius: VolunteerHomeRadius.tile, style: .continuous))
    }
}
