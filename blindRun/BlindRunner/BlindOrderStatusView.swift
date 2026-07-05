import Combine
import CoreLocation
import SwiftUI

// MARK: - Blind Order Status ViewModel

@MainActor
final class BlindOrderStatusViewModel: ObservableObject {
    @Published var order: OrderDetailResponse?
    @Published var isLoading = false
    @Published var isPerformingAction = false
    @Published var isSubmittingReview = false
    @Published var reviewRating = 5
    @Published var reviewComment = ""
    @Published var didSubmitReview = false
    @Published var volunteerDistanceToStartText: String?
    @Published var errorMessage: String?

    private weak var appState: AppState?
    private var speechService: SpeechService?
    private var pollingTask: Task<Void, Never>?
    private var currentOrderId: Int64?
    private var latestVolunteerCoordinate: CLLocationCoordinate2D?
    private var cancellables = Set<AnyCancellable>()

    /// Active blind-runner orders keep the 5-second REST fallback even when WebSocket is connected.
    var effectivePollingInterval: TimeInterval {
        return AppConstants.Timing.orderPollingInterval
    }

    var canShowEmergency: Bool {
        order?.status.showsEmergencyPlaceholder == true
    }

    var canShowCancel: Bool {
        order?.status.canBlindRunnerCancel == true
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
            speechService?.speak(order.blindRunnerAnnouncement(distanceText: volunteerDistanceToStartText))
        } else {
            speechService?.speak("正在获取订单状态。")
        }
    }

    func cancelOrder() async {
        guard let order, let appState else { return }
        guard order.status.canBlindRunnerCancel else {
            let message = "当前订单状态不能由盲人取消。"
            errorMessage = message
            speechService?.speakError(message)
            return
        }
        isPerformingAction = true
        errorMessage = nil
        do {
            let _: EmptyResponse = try await appState.apiClient.post("/api/orders/\(order.orderId)/cancel")
            isPerformingAction = false
            await self.loadOrder(orderId: order.orderId, speakChanges: true)
        } catch let error as APIError {
            isPerformingAction = false
            let message = error.localizedMessage
            speechService?.speakError(error.localizedMessage)
            await self.loadOrder(orderId: order.orderId, speakChanges: true)
            errorMessage = message
        } catch {
            isPerformingAction = false
            let message = "取消失败。"
            speechService?.speakError(message)
            await self.loadOrder(orderId: order.orderId, speakChanges: true)
            errorMessage = message
        }
    }

    func enterEmergency() async {
        errorMessage = EmergencySafetyCopy.deferredActionMessage
        speechService?.speak(EmergencySafetyCopy.deferredActionMessage)
    }

    func submitReview() async {
        guard let order, let appState, order.status == .completed else { return }
        guard (1...5).contains(reviewRating) else {
            errorMessage = "请选择 1 到 5 星评分。"
            speechService?.speakError("请选择 1 到 5 星评分。")
            return
        }

        isSubmittingReview = true
        errorMessage = nil
        do {
            let request = CreateReviewRequest(
                rating: reviewRating,
                comment: reviewComment.nilIfBlank
            )
            let _: EmptyResponse = try await appState.apiClient.post(
                "/api/orders/\(order.orderId)/review",
                body: request
            )
            isSubmittingReview = false
            didSubmitReview = true
            speechService?.speak("评价已提交，感谢反馈。")
        } catch let error as APIError {
            isSubmittingReview = false
            errorMessage = error.localizedMessage
            speechService?.speakError(error.localizedMessage)
        } catch {
            isSubmittingReview = false
            errorMessage = "评价提交失败，请稍后重试。"
            speechService?.speakError("评价提交失败，请稍后重试。")
        }
    }

    func skipReview() {
        didSubmitReview = true
        speechService?.speak("已跳过评价，返回首页。")
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
        refreshVolunteerDistance()
        if speakChanges, previousStatus != updated.status {
            speechService?.speakStatusChange(
                updated.status,
                text: updated.blindRunnerAnnouncement(distanceText: volunteerDistanceToStartText)
            )
        }
        if !updated.status.shouldPoll {
            stopPolling()
        }
    }

    func handleVolunteerLocationUpdate(_ message: WSVolunteerLocationUpdate) {
        guard message.orderId == activeOrderId else { return }
        latestVolunteerCoordinate = CLLocationCoordinate2D(latitude: message.lat, longitude: message.lng)
        refreshVolunteerDistance()
    }

    static func shouldSuppressDirectNotificationSpeech(_ text: String) -> Bool {
        let normalizedText = text.trimmed
        guard !normalizedText.isEmpty else { return true }
        let lifecycleFragments = [
            "志愿者已接单",
            "已接单",
            "待确认",
            "待出发",
            "志愿者已出发",
            "已出发",
            "正在前往",
            "正在赶来",
            "距您",
            "距出发地点",
            "志愿者已到达",
            "已到达",
            "服务已开始",
            "服务已完成",
            "订单已完成",
            "订单已取消",
            "预约已取消",
            "本次预约已取消",
            "已为您匹配",
            "正在确认行程",
            "请按预约时间前往或等待在出发地点",
            "志愿者已取消",
            "重新匹配",
            "正在重新匹配",
            "暂无志愿者",
            "暂无可用志愿者",
            "暂时没有可用志愿者",
            "仍在等待",
            "测试志愿者",
            "志愿者测试"
        ]
        return lifecycleFragments.contains { normalizedText.contains($0) }
    }

    private var activeOrderId: Int64? {
        order?.orderId ?? currentOrderId
    }

    private func refreshVolunteerDistance() {
        guard let order,
              [.pendingAccept, .driverEnRoute, .driverArrived].contains(order.status) else {
            volunteerDistanceToStartText = nil
            return
        }
        volunteerDistanceToStartText = order.volunteerDistanceToStartText(from: latestVolunteerCoordinate)
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
                    let speechText = notification.ttsText?.nilIfBlank ?? notification.body
                    if self.activeOrderId == nil ||
                        !Self.shouldSuppressDirectNotificationSpeech(speechText) {
                        self.speechService?.speak(speechText)
                    }
                case .volunteerLocation(let location):
                    self.handleVolunteerLocationUpdate(location)
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
                    lifecycleSection(order)
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
    private func lifecycleSection(_ order: OrderDetailResponse) -> some View {
        switch order.status.blindRunnerRoute {
        case .tracking:
            if order.status.isArrivedWaitingForServiceStart {
                waitingForServiceStartSection(order)
            }
        case .inService:
            inServiceSection(order)
        case .completion:
            completionRatingSection(order)
        case .terminal:
            terminalSection(order)
        }
    }

    private func waitingForServiceStartSection(_ order: OrderDetailResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("等待志愿者开始服务")
                .font(.title3.bold())
                .foregroundColor(AppColors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(order.status.arrivedWaitingCopy)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.secondaryBackground)
        .cornerRadius(8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("等待志愿者开始服务，\(order.status.arrivedWaitingCopy)")
    }

    private func inServiceSection(_ order: OrderDetailResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("服务进行中")
                .font(.title3.bold())
                .foregroundColor(AppColors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("请与志愿者保持沟通，注意安全。系统会持续同步订单状态，服务完成后进入评价页面。")
                .font(AppFonts.body())
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.success.opacity(0.12))
        .cornerRadius(8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("服务进行中，请与志愿者保持沟通，注意安全")
    }

    private func completionRatingSection(_ order: OrderDetailResponse) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("服务已完成")
                .font(.title3.bold())
                .foregroundColor(AppColors.textPrimary)
                .accessibilityAddTraits(.isHeader)

            if viewModel.didSubmitReview {
                Text("感谢反馈，可以返回首页。")
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textSecondary)
                    .accessibilityLabel("感谢反馈，可以返回首页")
            } else {
                Picker("评分", selection: $viewModel.reviewRating) {
                    ForEach(1...5, id: \.self) { value in
                        Text("\(value) 星").tag(value)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("服务评分")
                .accessibilityHint("选择一到五星评分")

                TextEditor(text: $viewModel.reviewComment)
                    .frame(minHeight: 96)
                    .padding(8)
                    .background(AppColors.background)
                    .cornerRadius(8)
                    .accessibilityLabel("评价内容，选填")

                PrimaryButton("提交评价", isLoading: viewModel.isSubmittingReview) {
                    Task { await viewModel.submitReview() }
                }
                .accessibilityLabel("提交评价")
                .accessibilityHint("提交本次服务评分和评价")

                Button("跳过评价并返回首页") {
                    viewModel.skipReview()
                    dismiss()
                }
                .font(AppFonts.body().weight(.semibold))
                .foregroundColor(AppColors.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
                .accessibilityLabel("跳过评价并返回首页")
            }

            if viewModel.didSubmitReview {
                PrimaryButton("返回首页") {
                    dismiss()
                }
                .accessibilityLabel("返回首页")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.secondaryBackground)
        .cornerRadius(8)
    }

    private func terminalSection(_ order: OrderDetailResponse) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(order.status.displayName)
                .font(.title3.bold())
                .foregroundColor(AppColors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(order.status.blindRunnerDescription)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textSecondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.secondaryBackground)
        .cornerRadius(8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(order.status.displayName)，\(order.status.blindRunnerDescription)")
    }

    @ViewBuilder
    private func volunteerSection(_ order: OrderDetailResponse) -> some View {
        let volunteerPhone = order.volunteerPhone?.nilIfBlank
        let distanceText = viewModel.volunteerDistanceToStartText
        if volunteerPhone != nil || distanceText != nil {
            VStack(alignment: .leading, spacing: 12) {
                Text("志愿者信息")
                    .font(.title3.bold())
                    .foregroundColor(AppColors.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                if let volunteerPhone {
                    Text("志愿者电话：\(volunteerPhone)")
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.textPrimary)
                        .accessibilityLabel("志愿者电话：\(volunteerPhone)")
                }

                if let distanceText {
                    Text("志愿者\(distanceText)")
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.textPrimary)
                        .accessibilityLabel("志愿者\(distanceText)")
                }
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
                EmergencyPlaceholderNotice()
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

            if order.status.isTerminal && order.status != .completed {
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
                            let request = OrderRespondRequest(action: .accept)
                            let _: EmptyResponse? = try? await appState.apiClient.post(
                                "/api/orders/\(order.orderId)/respond",
                                body: request
                            )
                            viewModel.startPolling(orderId: order.orderId)
                        }
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("模拟志愿者接单")
                }

                if order.status == .driverEnRoute || order.status == .pendingAccept {
                    Button("模拟志愿者到达") {
                        Task {
                            let _: EmptyResponse? = try? await appState.apiClient.post("/api/orders/\(order.orderId)/arrived")
                            viewModel.startPolling(orderId: order.orderId)
                        }
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("模拟志愿者到达")
                }

                if order.status == .driverArrived {
                    Button("模拟服务开始") {
                        Task {
                            let _: EmptyResponse? = try? await appState.apiClient.post("/api/orders/\(order.orderId)/start-service")
                            viewModel.startPolling(orderId: order.orderId)
                        }
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("模拟服务开始")
                }

                if order.status == .inProgress {
                    Button("模拟服务完成") {
                        Task {
                            let _: EmptyResponse? = try? await appState.apiClient.post("/api/orders/\(order.orderId)/finish")
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
