import SwiftUI

// 志愿者首页的作业区（「需要你处理」）。主体与排序在 `VolunteerProfileFirstScreenView.swift`。

extension VolunteerProfileFirstScreen {
    // MARK: - 作业区

    /// 「需要你处理」。**全部条件渲染**，一件没有时整块不出现，首屏就等于设计稿。
    ///
    /// 🚩 **只放有时限或要当场处理的事**（#706，负责人 2026-11-05）：订单、跨天预约确认、
    /// 定位异常、加载出错。必修培训、资质、接不了单的原因**不放这里** —— 底部胶囊
    /// 「暂不能接单」已经说了，点进去的接单前进度页五步各有入口，再放一遍是重复且挡视野。
    @ViewBuilder
    var todoSection: some View {
        let hasTodo = viewModel.activeOrder != nil
            || !viewModel.scheduledOrders.isEmpty
            || viewModel.scheduledOrdersMessage != nil
            || viewModel.locationDispatchWarning != nil
            || viewModel.displayedErrorMessage != nil

        if hasTodo {
            VStack(alignment: .leading, spacing: 12) {
                sectionLabel(VolunteerProfileCopy.todoSectionTitle)
                    .padding(.horizontal, 4)

                if let activeOrder = viewModel.activeOrder {
                    NavigationLink {
                        VolunteerInServiceView(orderId: activeOrder.orderId, initialOrder: activeOrder)
                    } label: {
                        VolunteerCurrentOrderCard(order: activeOrder)
                    }
                    .buttonStyle(.plain)
                    // 姓名去掉掩码星号 —— 只念不显示，见 `String.unmaskedForSpeech`。
                    .accessibilityLabel("当前订单：\(activeOrder.status.displayName)，盲人 \(activeOrder.blindName?.unmaskedForSpeech ?? "")，地点 \(activeOrder.startAddress ?? "")")
                    .accessibilityHint("点击进入当前订单")
                    .accessibilityIdentifier("volunteerHomeCurrentOrderCard")
                }

                VolunteerScheduledOrdersSection(
                    orders: viewModel.scheduledOrders,
                    submittingOrderID: viewModel.submittingScheduledOrderID,
                    message: viewModel.scheduledOrdersMessage,
                    onConfirm: { orderID in
                        Task { await viewModel.confirmScheduledDeparture(orderID: orderID) }
                    },
                    onRelease: { orderID in
                        Task { await viewModel.releaseScheduledOrder(orderID: orderID) }
                    },
                    onOpen: { order in viewModel.openUpcomingOrder(order) },
                    lateCancelWindowHours: appState.ruleParams.lateCancelWindowHours
                )

                if let warning = viewModel.locationDispatchWarning {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(warning, systemImage: "location.slash.fill")
                            .font(AppFonts.body())
                            .foregroundColor(AppColors.warning)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel(warning)
                            .accessibilityHint("请检查定位权限，并等待设备获取当前位置")
                            .accessibilityIdentifier("volunteerDispatchLocationWarning")

                        // 「为什么接不到单」和「去哪解决」必须在同一处。原文只有上面那行字：它告诉人出了什么事，
                        // 却没有任何能促成一次取点的动作，而站着不动时 Core Location
                        // 本来就不推新样本（`distanceFilter` 10 米）。
                        Button("重新定位") {
                            locationService.requestOneTimeLocation()
                            Task { await onReload() }
                        }
                        .buttonStyle(OutlineSecondaryButtonStyle())
                        .accessibilityHint("立即重新获取一次当前位置，并刷新派单状态")
                        .accessibilityIdentifier("volunteerDispatchRelocateButton")
                    }
                }

                if let errorMessage = viewModel.displayedErrorMessage {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(errorMessage)
                            .font(AppFonts.body())
                            .foregroundColor(AppColors.destructive)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel(errorMessage)
                        Button("重试加载") {
                            Task { await onReload() }
                        }
                        .buttonStyle(OutlineSecondaryButtonStyle())
                        .accessibilityHint("重新加载派单和当前订单状态")
                    }
                }
            }
            .padding(.top, 14)
        }
    }
}
