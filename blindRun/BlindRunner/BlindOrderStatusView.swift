import Combine
import SwiftUI

// MARK: - Blind Order Status ViewModel

@MainActor
final class BlindOrderStatusViewModel: ObservableObject {
    @Published var order: OrderDetailResponse?
    @Published var isLoading = false
    @Published var isPerformingAction = false
    @Published var errorMessage: String?

    private weak var appState: AppState?
    private var speechService: SpeechService?
    private var pollingTask: Task<Void, Never>?
    private var currentOrderId: Int64?
    private var cancellables = Set<AnyCancellable>()

    /// WebSocket 连接时轮询间隔加倍（降级模式用标准间隔）
    private var effectivePollingInterval: TimeInterval {
        if appState?.isWebSocketConnected == true {
            return AppConstants.Timing.orderPollingInterval * 3
        }
        return AppConstants.Timing.orderPollingInterval
    }

    var canShowEmergency: Bool {
        order?.status.canTriggerEmergency == true
    }

    var canShowCancel: Bool {
        order?.status.canCancel == true
    }

    var shouldPoll: Bool {
        order?.status.shouldPoll ?? true
    }

    func configure(appState: AppState, speechService: SpeechService) {
        self.appState = appState
        self.speechService = speechService
        subscribeToWebSocket(appState: appState)
    }

    func startPolling(orderId: Int64) {
        currentOrderId = orderId
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            await self?.loadOrder(orderId: orderId, speakChanges: true)

            while !Task.isCancelled {
                guard let self else { return }
                if !self.shouldContinuePolling {
                    return
                }
                try? await Task.sleep(nanoseconds: UInt64(self.effectivePollingInterval * 1_000_000_000))
                if Task.isCancelled { return }
                await self.loadOrder(orderId: orderId, speakChanges: true)
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func repeatStatus() {
        if let order {
            speechService?.speak(order.status.blindRunnerAnnouncement)
        } else {
            speechService?.speak("正在获取订单状态。")
        }
    }

    func cancelOrder() async {
        guard let order, let appState else { return }
        await performAction(failureMessage: "取消失败。") {
            let _: OrderResponse = try await appState.apiClient.post("/api/orders/\(order.orderId)/cancel")
            // Reload order to get updated status
            await self.loadOrder(orderId: order.orderId, speakChanges: true)
        }
    }

    func enterEmergency() async {
        guard let order, let appState else { return }
        let request = EmergencyTriggerRequest(
            orderId: order.orderId,
            gpsLat: nil,
            gpsLng: nil
        )
        await performAction(failureMessage: "求助操作失败，请重试。") {
            let _: OrderResponse = try await appState.apiClient.post("/api/emergency/trigger", body: request)
            // Reload order to get updated status
            await self.loadOrder(orderId: order.orderId, speakChanges: true)
        }
    }

    private var shouldContinuePolling: Bool {
        guard let order else { return true }
        return order.status.shouldPoll
    }

    private func loadOrder(orderId: Int64, speakChanges: Bool) async {
        guard let appState else { return }
        if order == nil {
            isLoading = true
        }
        errorMessage = nil

        do {
            let updated: OrderDetailResponse = try await appState.apiClient.get("/api/orders/\(orderId)")
            isLoading = false
            apply(updated, speakChanges: speakChanges)
        } catch let error as APIError {
            isLoading = false
            errorMessage = error.localizedMessage
            speechService?.speakError(error.localizedMessage)
        } catch {
            isLoading = false
            errorMessage = "获取订单状态失败。"
            speechService?.speakError("获取订单状态失败。")
        }
    }

    private func performAction(
        failureMessage: String,
        operation: () async throws -> Void
    ) async {
        isPerformingAction = true
        errorMessage = nil

        do {
            try await operation()
            isPerformingAction = false
        } catch let error as APIError {
            isPerformingAction = false
            errorMessage = error.localizedMessage
            speechService?.speakError(error.localizedMessage)
        } catch {
            isPerformingAction = false
            errorMessage = failureMessage
            speechService?.speakError(failureMessage)
        }
    }

    private func apply(_ updated: OrderDetailResponse, speakChanges: Bool) {
        let previousStatus = order?.status
        order = updated
        if speakChanges, previousStatus != updated.status {
            speechService?.speakStatusChange(updated.status)
        }
        if !updated.status.shouldPoll {
            stopPolling()
        }
    }

    // MARK: - WebSocket

    private func subscribeToWebSocket(appState: AppState) {
        guard let ws = appState.webSocketService else { return }
        ws.eventPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self else { return }
                switch event {
                case .orderStatusChanged(let statusMsg):
                    // 如果是当前订单的状态更新，立即刷新
                    if statusMsg.orderId == self.currentOrderId {
                        Task { await self.loadOrder(orderId: statusMsg.orderId, speakChanges: true) }
                    }
                case .notification(let notification):
                    self.speechService?.speak(notification.ttsText ?? notification.body)
                case .volunteerLocation:
                    break // 位置更新可后续显示在地图上
                case .emergencyResolved:
                    if let orderId = self.currentOrderId {
                        Task { await self.loadOrder(orderId: orderId, speakChanges: true) }
                    }
                    self.speechService?.speak("紧急求助已解除")
                case .emergencyContactNotified(let msg):
                    self.speechService?.speak(msg.ttsText ?? msg.message ?? "已通知紧急联系人")
                case .pong:
                    break
                default:
                    break
                }
            }
            .store(in: &cancellables)
    }
}

// MARK: - Blind Order Status View

struct BlindOrderStatusView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = BlindOrderStatusViewModel()
    @State private var showEmergencyConfirmation = false
    @State private var showCancelConfirmation = false
    let orderId: Int64
    let onOrderUpdated: (OrderDetailResponse) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if viewModel.isLoading && viewModel.order == nil {
                    ProgressView("正在获取订单状态...")
                        .tint(AppColors.primary)
                        .accessibilityLabel("正在获取订单状态")
                }

                if let order = viewModel.order {
                    statusHeader(order)
                    volunteerSection(order)
                    orderInfoSection(order)
                    actionSection(order)
                    debugMockControls(order)
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.destructive)
                        .accessibilityLabel(errorMessage)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
        }
        .background(AppColors.background)
        .navigationTitle("订单状态")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            repeatStatusArea
        }
        .confirmationDialog("取消订单", isPresented: $showCancelConfirmation) {
            Button("确认取消", role: .destructive) {
                Task {
                    await viewModel.cancelOrder()
                    if let order = viewModel.order {
                        onOrderUpdated(order)
                    }
                }
            }
            Button("不取消", role: .cancel) {}
        } message: {
            Text("确认取消本次预约？取消后将结束本次服务。")
        }
        .emergencyConfirmationAlert(isPresented: $showEmergencyConfirmation) {
            Task {
                await viewModel.enterEmergency()
                if let order = viewModel.order {
                    onOrderUpdated(order)
                }
            }
        }
        .onAppear {
            viewModel.configure(appState: appState, speechService: speechService)
            viewModel.startPolling(orderId: orderId)
        }
        .onDisappear {
            viewModel.stopPolling()
            if let order = viewModel.order {
                onOrderUpdated(order)
            }
        }
    }

    private func statusHeader(_ order: OrderDetailResponse) -> some View {
        VStack(spacing: 16) {
            Image(systemName: order.status.statusSymbolName)
                .font(.system(size: 56))
                .foregroundColor(order.status.statusColor)
                .accessibilityHidden(true)

            Text(order.status.displayName)
                .font(.largeTitle.bold())
                .foregroundColor(AppColors.textPrimary)
                .accessibilityLabel(order.status.displayName)
                .accessibilityHint(order.status.blindRunnerDescription)

            Text(order.status.blindRunnerDescription)
                .font(.title3)
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .accessibilityLabel(order.status.blindRunnerDescription)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(AppColors.secondaryBackground)
        .cornerRadius(8)
    }

    @ViewBuilder
    private func volunteerSection(_ order: OrderDetailResponse) -> some View {
        if let volunteerPhone = order.volunteerPhone, !volunteerPhone.trimmed.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("志愿者信息")
                    .font(.title3.bold())
                    .foregroundColor(AppColors.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                Text("志愿者电话：\(volunteerPhone)")
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textPrimary)
                    .accessibilityLabel("志愿者电话：\(volunteerPhone)")
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.secondaryBackground)
            .cornerRadius(8)
        }
    }

    private func orderInfoSection(_ order: OrderDetailResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("预约信息")
                .font(.title3.bold())
                .foregroundColor(AppColors.textPrimary)
                .accessibilityAddTraits(.isHeader)

            infoRow("预约时间", (order.plannedStart ?? "").displayDateTime)
            if let address = order.startAddress, !address.trimmed.isEmpty {
                infoRow("出发地点", address)
            }
            if let routeNotes = order.routeNotes, !routeNotes.trimmed.isEmpty {
                infoRow("路线备注", routeNotes)
            }
            if let duration = order.expectedDurationMinutes {
                infoRow("预计时长", "\(duration) 分钟")
            }
            if let pace = order.pacePreference {
                infoRow("配速偏好", pace.displayName)
            }
            if let route = order.routePreference {
                infoRow("路线偏好", route.displayName)
            }
            if order.hasGuideDogThisRun == true {
                infoRow("导盲犬", "本次携带")
            }
            if let notes = order.specialNotes, !notes.trimmed.isEmpty {
                infoRow("特殊说明", notes)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.secondaryBackground)
        .cornerRadius(8)
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
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

    private func actionSection(_ order: OrderDetailResponse) -> some View {
        VStack(spacing: 14) {
            if viewModel.canShowEmergency {
                EmergencyActionButton(isLoading: viewModel.isPerformingAction) {
                    showEmergencyConfirmation = true
                }
            }

            if viewModel.canShowCancel {
                Button("取消订单") {
                    showCancelConfirmation = true
                }
                .font(AppFonts.body().weight(.semibold))
                .foregroundColor(AppColors.destructive)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 64)
                .accessibilityLabel("取消订单")
                .accessibilityHint("需要确认后取消")
            }

            if order.status.isTerminal {
                PrimaryButton("返回首页") {
                    dismiss()
                }
                .accessibilityLabel("返回首页")
                .accessibilityHint("点击后返回盲人首页")
            }
        }
    }

    @ViewBuilder
    private func debugMockControls(_ order: OrderDetailResponse) -> some View {
        #if DEBUG
        if appState.currentEnvironment == .mock {
            VStack(alignment: .leading, spacing: 10) {
                Text("Mock 状态测试")
                    .font(.headline)
                    .foregroundColor(AppColors.textPrimary)

                if order.status == .pendingMatch {
                    Button("模拟志愿者接单") {
                        Task {
                            let _: OrderResponse? = try? await appState.apiClient.post("/api/orders/\(order.orderId)/accept")
                            viewModel.startPolling(orderId: order.orderId)
                        }
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("模拟志愿者接单")
                }

                if order.status == .driverEnRoute || order.status == .pendingAccept {
                    Button("模拟志愿者到达") {
                        Task {
                            let _: OrderResponse? = try? await appState.apiClient.post("/api/orders/\(order.orderId)/arrived")
                            viewModel.startPolling(orderId: order.orderId)
                        }
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("模拟志愿者到达")
                }

                if order.status == .inProgress || order.status == .driverArrived {
                    Button("模拟服务完成") {
                        Task {
                            let _: OrderResponse? = try? await appState.apiClient.post("/api/orders/\(order.orderId)/finish")
                            viewModel.startPolling(orderId: order.orderId)
                        }
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("模拟服务完成")
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.secondaryBackground)
            .cornerRadius(8)
        }
        #endif
    }

    private var repeatStatusArea: some View {
        PrimaryButton("重复当前状态") {
            viewModel.repeatStatus()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(.regularMaterial)
        .accessibilityLabel("重复当前状态")
        .accessibilityHint("点击后重新播报当前订单状态")
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        BlindOrderStatusView(orderId: 1) { _ in }
            .environmentObject(AppState())
            .environmentObject(SpeechService())
    }
}
#endif
