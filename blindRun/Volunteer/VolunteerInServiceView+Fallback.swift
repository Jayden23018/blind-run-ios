import SwiftUI

extension VolunteerInServiceView {
    // MARK: - 兜底（订单还没拉到 / 首次加载失败 / 认不出的状态）

    /// 没有流转动作、没有地图：这几种情况下陪跑员要么还不是、要么已经不是这一单的参与者。
    /// 求助仍在右上角 —— 走得到这里的都不是 `IN_PROGRESS`，`resolve` 只会给本地拨号。
    var fallbackContent: some View {
        let helpMode = VolunteerOrderSOSMode.resolve(status: viewModel.order?.status)
        return VStack(spacing: 0) {
            // v7 顶栏（#945），压在深色头那一截上，与其余各态同一个位置。
            VolunteerOrderTopBar(
                surface: .onDark,
                onBack: { dismiss() },
                isCloudHelp: helpMode == .cloud,
                onHelp: {
                    if helpMode == .cloud { showEmergencyConfirm = true } else { showsLocalHelp = true }
                }
            )
            .background(BlindOrderV7Palette.headerTop.ignoresSafeArea(edges: .top))
            ScrollView {
                Group {
                    switch VolunteerOrderFallback.resolve(status: viewModel.order?.status, errorMessage: viewModel.errorMessage) {
                    case .loading:
                        ProgressView(VolunteerOrderFallback.loadingTitle)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 32)
                    case let .message(title, message):
                        EmptyStateView(title: title, message: message)
                    }
                }
                .padding(.horizontal, FlowMetrics.v2ScreenPadding)
            }
        }
        .background(AppColors.Flow.surface.ignoresSafeArea())
        .emergencyCallOptionsDialog(isPresented: $showsLocalHelp, context: .volunteerBeforeRun, primaryContact: nil)
    }

    /// 取消对话框的四句话。**按状态换，不是一句通用文案。**
    ///
    /// 跨天预约那一态走的是 `.releaseScheduled`，而新增那个 case 的**唯一理由**就是换掉
    /// 「取消订单」这个词 —— 对志愿者它读起来像在替盲人取消这一单，而实际后果是
    /// 「这一单回到派单池换个人」。按钮上换了、确认框里还写「确认取消本次预约？」的话，
    /// 那次改名等于没做，而对话框才是他真正下决心的那一屏。
    ///
    /// 抽成一个元组而不是在 `confirmationDialog` 里写四个三元表达式：那样写在 SwiftUI 里
    /// 会把类型检查器拖到超时（本文件 `VolunteerRecentOrderCard` 上有同一个坑的记录）。
    /// 2026-09-17 搬到 `VolunteerOrderFlowCopy.cancelDialog(for:)`：它此前是 View 的
    /// private 计算属性，**测试够不着**，而 `ScheduledOrderTests.testReleaseAndCancelDoNotShareCopy`
    /// 的注释逐字记着这个洞（「这条只覆盖按钮标题，覆盖不到确认对话框」）。走 `AGENTS.md` §1.2。
    var cancelSheetCopy: VolunteerOrderFlowCopy.CancelSheetCopy {
        VolunteerOrderFlowCopy.cancelSheet(
            for: viewModel.order?.status,
            plannedStart: viewModel.order?.plannedStart?.nilIfBlank?.backendTimestamp,
            lateCancelWindowHours: appState.ruleParams.lateCancelWindowHours
        )
    }

    /// 紧急信息区（挂在跑步中页头卡下方）。**「代盲人发起求助」的按钮不在这里** ——
    /// 它是跑步中页顶栏右上的求助胶囊（`VolunteerOrderHelpPill`，#945）。
    ///
    /// 2026-08-19 把触发按钮搬走：它此前是这个 `VStack` 的第一个子视图，而这个 `VStack` 底部对齐、
    /// 上方就是高度自适应的底部面板（已随旧地图路径删除），于是一个全宽红色 `PrimaryButton` 浮在屏幕
    /// 30–36% 处、且垂直位置随面板内容漂移 —— 和「结束服务」「取消订单」同一个组件同一个宽度，
    /// 落在拇指自然区。理由与对标见 `docs/research/volunteer-sos-button-placement-20260819.md`。
    ///
    /// 留在这里的两样东西都**不是主动触发的动作**，全宽横条对它们是对的形态：
    ///
    /// - 上半：被陪同者发出求助时的**唯一**响应「确认需要帮助」。**没有「误触」按钮** —— 后端对
    ///   `action=FALSE_ALARM` 恒 403 `EMERGENCY_VOLUNTEER_CANNOT_DISMISS`：一对一陪跑里陪同者本身
    ///   可能就是威胁来源，撤销权只在受助者本人和客服手里。
    /// - 下半：求助结果文案。它的渲染条件与触发按钮**拆开**了 —— 原先包在同一个
    ///   `canVolunteerTriggerEmergency` 的 `if` 里，按钮搬走时若一并带走，
    ///   「求助已记录 / 求助未发出」就会没有地方显示，直接违反 `AGENTS.md` §6
    ///   「每一种结果都必须可见且可听地如实告知」。
    ///
    /// 两者都不成立时这个 section 渲染为空 —— 那正是绝大多数时刻的样子。
    @ViewBuilder
    func emergencySection(for order: OrderDetailResponse) -> some View {
        let coordinator = appState.emergencyCoordinator
        VStack(spacing: 10) {
            if let alert = coordinator.volunteerAlert, !alert.isAcknowledged {
                EmergencyStatusNotice(message: alert.message, isFailure: true)
                PrimaryButton(
                    EmergencySafetyCopy.volunteerNeedHelpButtonTitle,
                    isDestructive: true,
                    isLoading: viewModel.isAcknowledgingEmergency
                ) {
                    Task { await viewModel.acknowledgeEmergency(eventID: alert.eventID) }
                }
                .accessibilityLabel(EmergencySafetyCopy.volunteerNeedHelpButtonTitle)
                .accessibilityHint("确认跑者需要帮助")
            }

            if order.status.canVolunteerTriggerEmergency, let message = coordinator.statusMessage {
                EmergencyStatusNotice(message: message, isFailure: coordinator.state.isFailure)
            }
        }
    }

    func distanceText(for order: OrderDetailResponse) -> String? {
        guard locationService.isAuthorized,
              let deviceCoordinate = locationService.currentLocation,
              let coordinate = orderCoordinate(order) else { return nil }
        let meters = DistanceCalculator.distanceFromDeviceToBackend(
            deviceCoordinate: deviceCoordinate,
            backendCoordinate: coordinate
        )
        return DistanceCalculator.formattedDistance(meters)
    }

    @ViewBuilder
    var completedTrackContent: some View {
        ScrollView {
            if let track = trackViewModel.track {
                CompletedTrackSummaryView(track: track, recordOrderId: orderId, role: .volunteer) {
                    speechService.speak(track.spokenSummary)
                }
                .padding(20)
                .readableContentColumn()
            } else if trackViewModel.isLoading {
                ProgressView("正在加载本次路线")
                    .padding(24)
                    .accessibilityLabel("正在加载本次路线")
                    .accessibilityIdentifier("volunteerCompletedTrackLoading")
            } else {
                let message = trackViewModel.errorMessage ?? "本次路线暂时无法加载。"
                VStack(alignment: .leading, spacing: 16) {
                    Text("服务已完成")
                        .font(AppFonts.title())
                        .accessibilityAddTraits(.isHeader)
                    Text(message)
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.textSecondary)
                        .accessibilityLabel(message)

                    PrimaryButton("重试加载本次路线") {
                        Task {
                            await trackViewModel.load(orderID: orderId, appState: appState)
                            if let summary = trackViewModel.track?.spokenSummary {
                                speechService.speak(summary)
                            }
                        }
                    }
                    .accessibilityLabel("重试加载本次路线")
                    .accessibilityHint("重新获取已完成服务的路线和统计")
                    .accessibilityIdentifier("volunteerCompletedTrackRetry")

                    Button {
                        speechService.speak("服务已完成。\(message)")
                    } label: {
                        Text("重复当前状态")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .accessibilityHint("朗读服务完成和本次路线暂时不可用状态")
                    .accessibilityIdentifier("volunteerCompletedTrackRepeatStatus")
                }
                .padding(20)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("volunteerCompletedTrackUnavailable")
            }
        }
        .background(AppColors.background)
    }
}
