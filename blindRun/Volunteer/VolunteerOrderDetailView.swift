import SwiftUI

struct VolunteerOrderDetailView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @EnvironmentObject private var locationService: LocationService
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = VolunteerOrderDetailViewModel()
    @StateObject private var trackViewModel = CompletedTrackSummaryViewModel()
    @State private var showAcceptConfirm = false
    @State private var showCancelConfirm = false
    @State private var serviceNavigationOrder: OrderDetailResponse?
    let orderId: Int64

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if viewModel.isLoading && viewModel.order == nil {
                    ProgressView("正在加载订单...")
                        .accessibilityLabel("正在加载订单")
                }

                if let order = viewModel.order {
                    VolunteerStatusBanner(status: order.status)
                    VolunteerRunnerNeedsBanner(order: order)
                    VolunteerOrderMap(order: order)
                    VolunteerBlindRunnerInfoCard(order: order, showPhone: viewModel.canShowPhone)
                    VolunteerOrderInfoSection(order: order, distanceText: distanceText(for: order))
                    // 这一页是志愿者首页「近期服务」点进来的落点。此前它没有轨迹，
                    // 而「服务记录」点进来的 `VolunteerReadOnlyOrderView` 有 ——
                    // 同一个已完成订单换个入口就看不到路线，用户报的就是这个。
                    completedTrackSection(order)
                    actionSection(order)
                }

                if let transitionMessage = viewModel.transitionMessage {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(transitionMessage, systemImage: "clock.arrow.circlepath")
                            .font(AppFonts.body())
                            .foregroundColor(AppColors.warning)
                            .accessibilityLabel(transitionMessage)
                        if viewModel.canRetryTransitionConfirmation {
                            Button("重新确认状态") {
                                viewModel.retryTransitionConfirmation()
                            }
                            .buttonStyle(OutlineSecondaryButtonStyle())
                            .accessibilityHint("刷新订单状态")
                        }
                    }
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.destructive)
                        .accessibilityLabel(errorMessage)
                }

                // 接单被后端 403 VOLUNTEER_NOT_VERIFIED 拒绝时，直接给出上传入口。
                if viewModel.needsCertificateUpload {
                    VolunteerCertificateUploadEntryLink()
                }
            }
            .padding(20)
            .readableContentColumn()
        }
        .navigationTitle("订单详情")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            viewModel.configure(with: appState, speechService: speechService)
            // #368：没有位置轨迹同意就不开定位、也不弹系统授权框（告知在前）。
            // 同行态的同意页由根视图盖上来，同意之后由同行会话打开定位。
            if appState.hasLocationTrackConsent(.volunteerLocationTrack) {
                locationService.requestPermission()
            }
            await viewModel.load(orderId: orderId)
            if viewModel.order?.status == .completed {
                await trackViewModel.load(orderID: orderId, appState: appState)
            }
        }
        // 离开页面只撤回这一页那一份（#425）：接单开关、同行会话要的定位照开。
        .requestsLocationUpdates(.volunteerOrderDetail, when: appState.hasLocationTrackConsent(.volunteerLocationTrack))
        .onChange(of: viewModel.order?.status) { status in
            guard status?.isActiveForVolunteer == true,
                  let order = viewModel.order else { return }
            serviceNavigationOrder = order
        }
        .alert("确认接单", isPresented: $showAcceptConfirm) {
            Button("确认接单") {
                Task {
                    await viewModel.accept(
                        currentLocation: locationService.currentLocation,
                        locationAuthorized: locationService.isAuthorized
                    )
                    if let order = viewModel.order, order.status.isActiveForVolunteer {
                        serviceNavigationOrder = order
                    }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("确认接单后将显示盲人联系方式，你的手机号也会提供给跑者。")
        }
        .confirmationDialog("取消订单", isPresented: $showCancelConfirm) {
            Button("确认取消", role: .destructive) {
                Task {
                    await viewModel.cancel()
                    if viewModel.didCancelOrder {
                        dismiss()
                    }
                }
            }
            Button("不取消", role: .cancel) {}
        } message: {
            Text("确认取消本次预约？")
        }
        .navigationDestination(
            isPresented: Binding(
                get: { serviceNavigationOrder != nil },
                set: { isPresented in
                    if !isPresented {
                        serviceNavigationOrder = nil
                    }
                }
            )
        ) {
            if let order = serviceNavigationOrder {
                VolunteerInServiceView(orderId: order.orderId, initialOrder: order)
            }
        }
    }

    @ViewBuilder
    private func completedTrackSection(_ order: OrderDetailResponse) -> some View {
        if order.status == .completed {
            if let track = trackViewModel.track {
                CompletedTrackSummaryView(track: track, recordOrderId: order.orderId, role: .volunteer) {
                    speechService.speak(track.spokenSummary)
                }
            } else if trackViewModel.isLoading {
                ProgressView("正在加载本次路线")
                    .accessibilityLabel("正在加载本次路线")
                    .accessibilityIdentifier("volunteerOrderDetailTrackLoading")
            } else if let message = trackViewModel.errorMessage {
                // 轨迹拉不到不该把整页判成失败：订单信息和联系方式仍然有用。
                Text(message)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textSecondary)
                    .accessibilityLabel(message)
            }
        }
    }

    private func actionSection(_ order: OrderDetailResponse) -> some View {
        VStack(spacing: 12) {
            if order.status == .pendingMatch {
                let blockMessage = VolunteerOrderActionGuard.acceptBlockMessage(
                    profile: appState.volunteerProfile,
                    registrationStatus: appState.volunteerRegistrationStatus,
                    locationAuthorized: locationService.isAuthorized
                )
                PrimaryButton("接单", isLoading: viewModel.isPerformingAction) {
                    showAcceptConfirm = true
                }
                .disabled(
                    blockMessage != nil
                        || viewModel.isPerformingAction
                        || viewModel.isTransitionPending
                )
                .opacity(blockMessage == nil ? 1 : 0.45)
                .accessibilityLabel("接单")
                .accessibilityHint(blockMessage ?? "确认接单后将显示盲人联系方式")

                if let blockMessage {
                    Text(blockMessage)
                        .font(AppFonts.caption())
                        .foregroundColor(AppColors.warning)
                        .accessibilityLabel(blockMessage)
                }
            // `.scheduledConfirmed` 在列：跨天单的「确认我还会去」是服务页上的主按钮
            // （`VolunteerOrderFlowPresentation.PrimaryAction.confirmDeparture`），这里给的是通往它的第二条路 ——
            // 主入口是首页的「我的预约」区块，这条兜住「从近期服务点进详情页」的人。
            } else if order.status == .scheduledConfirmed || order.status == .pendingAccept || order.status == .inProgress || order.status == .driverEnRoute || order.status == .driverArrived {
                NavigationLink {
                    VolunteerInServiceView(orderId: order.orderId, initialOrder: order)
                } label: {
                    Text("进入服务页面")
                        .font(AppFonts.primaryButton())
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 64)
                        .foregroundColor(.white)
                        .background(AppColors.primary)
                        .cornerRadius(8)
                }
                .accessibilityLabel("进入服务页面")
                .accessibilityHint("查看当前订单服务状态")

                if order.status.canVolunteerCancel {
                    Button("取消订单", role: .destructive) {
                        showCancelConfirm = true
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
                    .accessibilityLabel("取消订单")
                    .accessibilityHint("需要确认后取消")
                }
            }
        }
    }

    private func distanceText(for order: OrderDetailResponse) -> String? {
        guard locationService.isAuthorized,
              let deviceCoordinate = locationService.currentLocation,
              let coordinate = orderCoordinate(order) else { return nil }
        let meters = DistanceCalculator.distanceFromDeviceToBackend(
            deviceCoordinate: deviceCoordinate,
            backendCoordinate: coordinate
        )
        return DistanceCalculator.formattedDistance(meters)
    }
}
