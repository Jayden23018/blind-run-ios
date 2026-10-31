import SwiftUI

// 志愿者「我的」首屏的作业区（「需要你处理」）。主体与排序在 `VolunteerProfileFirstScreenView.swift`。

extension VolunteerProfileFirstScreen {
    // MARK: - 作业区

    /// 「需要你处理」。**全部条件渲染**，一件没有时整块不出现，首屏就等于设计稿。
    @ViewBuilder
    var todoSection: some View {
        let hasTodo = viewModel.activeOrder != nil
            || !viewModel.scheduledOrders.isEmpty
            || viewModel.scheduledOrdersMessage != nil
            || viewModel.acceptBlockMessage != nil
            || needsCertificateEntry
            || needsTrainingEntry
            || viewModel.locationDispatchWarning != nil
            || viewModel.displayedErrorMessage != nil

        if hasTodo {
            VStack(alignment: .leading, spacing: 12) {
                sectionLabel(VolunteerProfileCopy.todoSectionTitle)

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

                // 「为什么接不到单」和「去哪解决」必须在同一处 —— 所以资质入口跟着提示走，
                // 不留一行没有去处的说明（同下面 `trainingEntry` 与「重新定位」那两条判据）。
                if let acceptBlockMessage = viewModel.acceptBlockMessage {
                    Text(acceptBlockMessage)
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.warning)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(acceptBlockMessage)
                }

                if needsCertificateEntry {
                    VolunteerCertificateUploadEntryLink()
                }

                if needsTrainingEntry {
                    trainingEntry
                }

                if let warning = viewModel.locationDispatchWarning {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(warning, systemImage: "location.slash.fill")
                            .font(AppFonts.body())
                            .foregroundColor(AppColors.warning)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel(warning)
                            .accessibilityHint("请检查定位权限，并等待设备获取当前位置")
                            .accessibilityIdentifier("volunteerDispatchLocationWarning")

                        // 「为什么接不到单」和「去哪解决」必须在同一处 —— 同 `trainingEntry`
                        // 与资质入口那条判据。原文只有上面那行字：它告诉人出了什么事，
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
        }
    }

    /// 判据全在 `VolunteerProfileTodoGate`（纯函数，有验红用例），这里只做转发。
    private var needsCertificateEntry: Bool {
        VolunteerProfileTodoGate.needsCertificateEntry(
            summary: viewModel.dispatchSummary,
            apiRejectedAsUnapproved: viewModel.needsCertificateUpload
        )
    }

    private var needsTrainingEntry: Bool {
        VolunteerProfileTodoGate.needsTrainingEntry(summary: viewModel.dispatchSummary)
    }

    /// 必修培训入口。**整张卡可点**，不是「一行说明 + 旁边一个小链接」。
    ///
    /// 用户原话：「必须在派单工作台点进去再点击一个贼小的去培训，一点都不显眼」。
    /// 所以三件事同时成立才算修好：① 在首屏、不在任何二级页；② 原因本身就是入口，
    /// 不需要先读懂一句话再去找按钮；③ 点一下直达培训页，中间没有别的页。
    ///
    /// 🚩 **`NavigationLink` 而不是 `.sheet`**（旧实现是 sheet）。两条理由：
    /// 这一屏确定在 `NavigationStack` 里（`VolunteerHomeView.body`），旧注释说的
    /// 「首页不保证处在 NavigationStack 里」已经不成立；而 sheet 会盖住刻意挂在
    /// `NavigationStack` **外面**的派单弹窗（AGENTS §5：模态最高优先级），push 不会。
    private var trainingEntry: some View {
        NavigationLink {
            VolunteerTrainingView()
        } label: {
            HStack(spacing: 12) {
                // 图标只是装饰：档位与原因全在文字里，不靠颜色也不靠图标传达（WCAG 1.4.1）。
                Image(systemName: "graduationcap.fill")
                    .font(.title2)
                    .foregroundColor(AppColors.warning)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(VolunteerDispatchNotAvailableReason.trainingIncomplete.displayText)
                        .font(AppFonts.body().weight(.bold))
                        .foregroundColor(AppColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(VolunteerProfileCopy.trainingEntryDetail)
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
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            // 不写死高度，只给下限：文字自己跟 Dynamic Type 长，卡片跟着长。
            // 64 在这里不是触达下限（志愿者端走 Apple 的 44pt），而是「显眼」的量化形式 ——
            // 用户那句「一个贼小的去培训」说的就是这个维度。
            // 不加 `guard:allow small-touch-target`：那条规则既排除了 /blindRun/Volunteer/，
            // 判据又是 `< 64`，双重不触发，多余的标注只会稀释它在别处的信号。
            .frame(minHeight: 64)
            .background(AppColors.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: VolunteerHomeRadius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        // ⛔ **不加** `.accessibilityElement(children: .combine)`。打在 `NavigationLink` 自身上
        // 会新建一个合成元素，link/button trait 有丢失风险，而这是必修培训唯一的显眼入口。
        // 同屏两个同形状的兄弟节点（当前订单卡、最近陪跑行）也都只有
        // `buttonStyle(.plain)` + `accessibilityLabel`，这里保持一致。
        .accessibilityLabel(
            "\(VolunteerDispatchNotAvailableReason.trainingIncomplete.displayText)。"
                + VolunteerProfileCopy.trainingEntryDetail
        )
        .accessibilityHint(VolunteerProfileCopy.trainingEntryHint)
        .accessibilityIdentifier("volunteerHomeTrainingEntry")
    }
}
