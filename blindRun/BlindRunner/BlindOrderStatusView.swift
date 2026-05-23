import Combine
import SwiftUI

// MARK: - Blind Order Status ViewModel

@MainActor
final class BlindOrderStatusViewModel: ObservableObject {
    @Published var order: RunOrderDto?
    @Published var isLoading = false
    @Published var isPerformingAction = false
    @Published var errorMessage: String?
    @Published var selectedCancellationReason: ManualCancellationReason = .timeConflict

    private weak var appState: AppState?
    private var speechService: SpeechService?
    private var pollingTask: Task<Void, Never>?
    private var currentOrderId: String?

    var canShowEmergency: Bool {
        order?.status.canEnterEmergency == true
    }

    var canShowConfirmStart: Bool {
        order?.status == .arrived
    }

    var canShowCancel: Bool {
        order?.status.canCancelBeforeStart == true
    }

    var shouldPoll: Bool {
        order?.status.shouldPollOnBlindRunnerPage ?? true
    }

    func configure(appState: AppState, speechService: SpeechService) {
        self.appState = appState
        self.speechService = speechService
    }

    func startPolling(orderId: String) {
        currentOrderId = orderId
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            await self?.loadOrder(orderId: orderId, speakChanges: true)

            while !Task.isCancelled {
                guard let self else { return }
                if !self.shouldContinuePolling {
                    return
                }
                try? await Task.sleep(nanoseconds: UInt64(AppConstants.Timing.orderPollingInterval * 1_000_000_000))
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

    func confirmStart() async {
        guard let order, let appState else { return }
        await performAction(failureMessage: "操作失败，请重试。") {
            let updated: RunOrderDto = try await appState.apiClient.post("/api/orders/\(order.id)/start")
            apply(updated, speakChanges: true)
        }
    }

    func cancelOrder(reason: ManualCancellationReason) async {
        guard let order, let appState else { return }
        let request = CancelOrderRequest(
            cancelledBy: .blindRunner,
            cancelledReason: reason,
            otherReasonText: nil
        )
        await performAction(failureMessage: "取消失败。") {
            let updated: RunOrderDto = try await appState.apiClient.post("/api/orders/\(order.id)/cancel", body: request)
            apply(updated, speakChanges: true)
        }
    }

    func enterEmergency() async {
        guard let order, let appState else { return }
        await performAction(failureMessage: "求助操作失败，请重试。") {
            let updated: RunOrderDto = try await appState.apiClient.post("/api/orders/\(order.id)/emergency")
            apply(updated, speakChanges: true)
        }
    }

    private var shouldContinuePolling: Bool {
        guard let order else { return true }
        return order.status.shouldPollOnBlindRunnerPage
    }

    private func loadOrder(orderId: String, speakChanges: Bool) async {
        guard let appState else { return }
        if order == nil {
            isLoading = true
        }
        errorMessage = nil

        do {
            let updated: RunOrderDto = try await appState.apiClient.get("/api/orders/\(orderId)")
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

    private func apply(_ updated: RunOrderDto, speakChanges: Bool) {
        let previousStatus = order?.status
        order = updated
        if speakChanges, previousStatus != updated.status {
            speechService?.speakStatusChange(updated.status)
        }
        if !updated.status.shouldPollOnBlindRunnerPage {
            stopPolling()
        }
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
    let orderId: String
    let onOrderUpdated: (RunOrderDto) -> Void

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
            ForEach(ManualCancellationReason.allCases, id: \.self) { reason in
                Button(reason.displayName, role: .destructive) {
                    Task {
                        await viewModel.cancelOrder(reason: reason)
                        if let order = viewModel.order {
                            onOrderUpdated(order)
                        }
                    }
                }
            }
            Button("不取消", role: .cancel) {}
        } message: {
            Text("请选择取消原因。取消后本次预约将结束。")
        }
        .alert("一键求助", isPresented: $showEmergencyConfirmation) {
            Button("确认求助", role: .destructive) {
                Task {
                    await viewModel.enterEmergency()
                    if let order = viewModel.order {
                        onOrderUpdated(order)
                    }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("是否确认进入求助状态？确认后，本次服务将标记为异常，系统会记录当前订单状态。")
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

    private func statusHeader(_ order: RunOrderDto) -> some View {
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
    private func volunteerSection(_ order: RunOrderDto) -> some View {
        if let volunteerName = order.volunteerNickname, !volunteerName.trimmed.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("志愿者信息")
                    .font(.title3.bold())
                    .foregroundColor(AppColors.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                Text("志愿者：\(volunteerName)")
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textPrimary)
                    .accessibilityLabel("志愿者：\(volunteerName)")
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.secondaryBackground)
            .cornerRadius(8)
        }
    }

    private func orderInfoSection(_ order: RunOrderDto) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("预约信息")
                .font(.title3.bold())
                .foregroundColor(AppColors.textPrimary)
                .accessibilityAddTraits(.isHeader)

            infoRow("预约时间", order.appointmentTime.displayDateTime)
            infoRow("出发地点", order.startLocation.displayAddress)
            if let destinationText = order.destinationText, !destinationText.trimmed.isEmpty {
                infoRow("目的地或路线", destinationText)
            }
            if let duration = order.estimatedDurationMinutes {
                infoRow("预计时长", "\(duration) 分钟")
            }
            if let distance = order.estimatedDistanceKm {
                infoRow("预计距离", "\(distance.formatted()) 公里")
            }
            if let pace = order.pacePreference, !pace.trimmed.isEmpty {
                infoRow("配速偏好", pace)
            }
            if order.preferSameGender == true {
                infoRow("同性志愿者", "需要")
            }
            if let remark = order.remark, !remark.trimmed.isEmpty {
                infoRow("备注", remark)
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

    private func actionSection(_ order: RunOrderDto) -> some View {
        VStack(spacing: 14) {
            if viewModel.canShowConfirmStart {
                PrimaryButton("确认开始服务", isLoading: viewModel.isPerformingAction) {
                    Task {
                        await viewModel.confirmStart()
                        if let order = viewModel.order {
                            onOrderUpdated(order)
                        }
                    }
                }
                .accessibilityLabel("确认开始服务")
                .accessibilityHint("点击后正式开始跑步")
            }

            if viewModel.canShowEmergency {
                PrimaryButton("一键求助", isDestructive: true, isLoading: viewModel.isPerformingAction) {
                    showEmergencyConfirmation = true
                }
                .accessibilityLabel("一键求助，遇到紧急情况时点击")
                .accessibilityHint("需要二次确认，确认后订单进入求助状态")
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
                .accessibilityHint("需要选择取消原因并确认")
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
    private func debugMockControls(_ order: RunOrderDto) -> some View {
        #if DEBUG
        if appState.currentEnvironment == .mock {
            VStack(alignment: .leading, spacing: 10) {
                Text("Mock 状态测试")
                    .font(.headline)
                    .foregroundColor(AppColors.textPrimary)

                if order.status == .matching {
                    Button("模拟志愿者接单") {
                        Task {
                            let updated: RunOrderDto? = try? await appState.apiClient.post("/api/orders/\(order.id)/accept")
                            if let updated {
                                onOrderUpdated(updated)
                                viewModel.startPolling(orderId: updated.id)
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("模拟志愿者接单")
                }

                if order.status == .accepted {
                    Button("模拟志愿者到达") {
                        Task {
                            let updated: RunOrderDto? = try? await appState.apiClient.post("/api/orders/\(order.id)/arrive")
                            if let updated {
                                onOrderUpdated(updated)
                                viewModel.startPolling(orderId: updated.id)
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("模拟志愿者到达")
                }

                if order.status == .inProgress {
                    Button("模拟服务完成") {
                        Task {
                            let updated: RunOrderDto? = try? await appState.apiClient.post("/api/orders/\(order.id)/complete")
                            if let updated {
                                onOrderUpdated(updated)
                                viewModel.startPolling(orderId: updated.id)
                            }
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
        BlindOrderStatusView(orderId: "30000000-0000-0000-0000-000000000001") { _ in }
            .environmentObject(AppState())
            .environmentObject(SpeechService())
    }
}
#endif
