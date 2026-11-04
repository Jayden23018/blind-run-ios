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

/// 派单状态：收不到单时的原因一句 + 覆盖范围 + 「保持 App 开着」。
///
/// 🚩 2026-11-04 起它在**接单页最上面的状态卡里**（陪跑员首页 v3，#694），不再在首页底部。
/// 它自己不再画底色和圆角 —— 外面那张白卡（`VolunteerDispatchHubView.statusCard`）负责。
/// 「接单中」那半句由状态卡标题说，这里只在**收不到单**时说原因，不重复一遍「可以接单」。
///
/// 🔴 **卡里不再有「去培训」按钮。** 那个入口小得用户找不到
/// （原话「一个贼小的去培训，一点都不显眼」），已整体升级成首页作业区里的整卡入口。
///
/// 🔴 **卡里不再有统计**（负责人 2026-10-06）。接单率与派单 / 接受 / 拒绝 / 超时计数
/// 对无偿志愿者读起来像考核，整组删掉，不挪去别处。
/// 状态句也不重复作业区已经画成整卡的原因（培训、资质）。
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

    /// 收不到单时才有原因句；可派单时状态卡标题「接单中」已经说了。
    private var reasonText: String? {
        guard summary.canDispatch != true else { return nil }
        return statusText
    }

    private var coverageLine: String {
        "\(summary.coverageText) · \(VolunteerAvailabilityCopy.keepAppOpenNote)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let reasonText {
                Text(reasonText)
                    .font(AppFonts.body().weight(.semibold))
                    .foregroundColor(AppColors.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(coverageLine)
                .font(.subheadline)
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "派单状态：" + [reasonText, summary.coverageText, VolunteerAvailabilityCopy.keepAppOpenNote]
                .compactMap { $0 }
                .joined(separator: "，")
        )
        .accessibilityIdentifier("volunteerDispatchSummaryCard")
    }
}
