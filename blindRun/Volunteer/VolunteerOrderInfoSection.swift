import SwiftUI

struct VolunteerOrderInfoSection: View {
    let order: OrderDetailResponse
    let distanceText: String?

    /// 盲人填的自由文本（路线备注 / 特殊说明）只在**接单后**展示。判据集中在
    /// `RunOrderStatus.disclosesBlindRunnerNotesToVolunteer`（穷举 switch，含 `.unknown` 默认关），
    /// 不在这里就地写 `!= .pendingMatch` —— 这个视图的两个调用点里，
    /// `VolunteerOrderDetailView:921` 是从「可接订单」列表点进来的，那里的订单任何志愿者都能浏览。
    private var showsSensitiveNotes: Bool {
        order.status.disclosesBlindRunnerNotesToVolunteer
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("订单信息")
                .font(.headline)
                .foregroundColor(AppColors.textPrimary)
            infoRow("出发地点", order.startAddress ?? "")
            if let endAddress = order.endAddressForDisplay {
                infoRow("结束地点", endAddress)
            }
            infoRow("预约时间", (order.plannedStart ?? "").displayDateTime)
            if let plannedEnd = order.plannedEndForAnnouncement {
                infoRow("预计结束时间", plannedEnd)
            }
            if let distanceText {
                infoRow("距离", distanceText)
            }
            if showsSensitiveNotes, let routeNotes = order.routeNotes?.nilIfBlank {
                infoRow("路线备注", routeNotes)
            }
            if let minutes = order.expectedDurationMinutes {
                infoRow("预计时长", "\(minutes) 分钟")
            }
            if let pace = order.pacePreference {
                infoRow("配速偏好", pace.displayName)
            }
            if let route = order.routePreference {
                infoRow("路线偏好", route.displayName)
            }
            // 「导盲犬」那一行移进 `VolunteerRunnerNeedsBanner` —— 它和视力情况、引导方式
            // 是同一类信息（决定见面第一个动作），散在订单信息的第 8 行里等于没有。
            // 两处都渲染会让接单后同一句话出现两遍。
            if showsSensitiveNotes, let notes = order.specialNotes?.nilIfBlank {
                infoRow("特殊说明", notes)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.secondaryBackground)
        .cornerRadius(8)
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(AppFonts.caption())
                .foregroundColor(AppColors.textSecondary)
            Text(value)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textPrimary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)：\(value)")
    }
}
