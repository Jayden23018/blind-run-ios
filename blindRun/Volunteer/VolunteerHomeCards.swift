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

/// 派单状态卡：派单状态一句 + 覆盖范围。
///
/// 🚩 **internal 而不是 private**：唯一的渲染点在 `VolunteerProfileFirstScreen.dispatchSection`
/// （另一个文件）。它被刻意摆在首屏**最底部**、接替 2026-09-15 删掉的那行工作台入口 ——
/// 「等待派单」页出来时搬走它 = 删首屏 `VStack` 里的一行 + 整个 struct 挪过去，不用重构。
/// 调研 §1 的三档分类里它是第三档「普通信息卡片」，不该占中段。
///
/// 🔴 **卡里不再有「去培训」按钮。** 那个入口以前是这张卡的兄弟节点，小得用户找不到
/// （原话「一个贼小的去培训，一点都不显眼」），已整体升级成首屏作业区里的整卡入口。
///
/// 🔴 **卡里不再有统计**（负责人 2026-10-06）。完成次数、评分在同一屏「我的陪伴」里已有一份；
/// 接单率与派单 / 接受 / 拒绝 / 超时计数对无偿志愿者读起来像考核，整组删掉，不挪去别处。
/// 状态句也不重复作业区已经画成整卡的原因（培训、资质）—— 同一屏说两遍「尚未完成必修培训」
/// 是 2026-10-05 零上下文评审点名的问题。
struct VolunteerDispatchSummaryCard: View {
    let summary: VolunteerDispatchSummaryResponse

    /// 作业区已经各自画成整卡入口的原因，判据与 `VolunteerProfileTodoGate` 一致。
    static let reasonsShownInTodoSection: Set<VolunteerDispatchNotAvailableReason> = [
        .trainingIncomplete,
        .notVerified
    ]

    private var statusText: String? {
        summary.dispatchStatusText(omitting: Self.reasonsShownInTodoSection)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if statusText != nil {
                Image(systemName: summary.canDispatch == true ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(summary.canDispatch == true ? AppColors.success : AppColors.warning)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 4) {
                if let statusText {
                    Text(statusText)
                        .font(AppFonts.body().weight(.bold))
                        .foregroundColor(AppColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(summary.coverageText)
                    .font(statusText == nil ? AppFonts.body() : AppFonts.caption())
                    .foregroundColor(statusText == nil ? AppColors.textPrimary : AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(AppColors.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: VolunteerHomeRadius.card, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "派单状态：" + [statusText, summary.coverageText].compactMap { $0 }.joined(separator: "，")
        )
        .accessibilityIdentifier("volunteerDispatchSummaryCard")
    }
}
