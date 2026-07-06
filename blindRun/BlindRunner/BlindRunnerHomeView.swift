import CoreLocation
import Combine
import SwiftUI

// MARK: - Blind Runner Route

private enum BlindRunnerRoute: Hashable {
    case booking
    case orderStatus(Int64)
    case settings
}

// MARK: - Blind Runner Home ViewModel

@MainActor
final class BlindRunnerHomeViewModel: ObservableObject {
    @Published var activeOrder: OrderDetailResponse?
    @Published var isLoading = false
    @Published var isPerformingAction = false
    @Published var errorMessage: String?

    private weak var appState: AppState?
    private var speechService: SpeechService?

    var currentStatusText: String {
        guard let activeOrder else {
            return "当前没有进行中的预约。"
        }
        return "当前订单：\(activeOrder.status.displayName)，\(activeOrder.startAddress ?? "")"
    }

    var canCancelActiveOrder: Bool {
        activeOrder?.status.canBlindRunnerCancel == true
    }

    func configure(with appState: AppState, speechService: SpeechService) {
        self.appState = appState
        self.speechService = speechService
    }

    func loadActiveOrder() async {
        guard let appState else { return }
        isLoading = true
        errorMessage = nil

        do {
            let paged: PagedOrderResponse = try await appState.apiClient.get("/api/orders/mine")
            activeOrder = paged.content
                .filter { $0.status.isActiveForBlindRunner }
                .sorted { $0.sortKey > $1.sortKey }
                .first
            isLoading = false
            speakCurrentStatus()
        } catch let error as APIError {
            isLoading = false
            errorMessage = error.localizedMessage
            speechService?.speakError(error.localizedMessage)
        } catch {
            isLoading = false
            errorMessage = "当前状态加载失败，请重试。"
            speechService?.speakError("当前状态加载失败，请重试。")
        }
    }

    func handleOrderCreated(_ response: OrderResponse) {
        speechService?.resetLastStatus()
        if let status = response.status {
            speechService?.speakStatusChange(status)
        }
    }

    func speakCurrentStatus(locationDescription: String? = nil) {
        if let activeOrder {
            speechService?.speakStatusChange(activeOrder.status, text: activeOrder.blindRunnerAnnouncement())
        } else {
            let locationText = locationDescription.map { "当前位置：\($0)。" } ?? ""
            speechService?.speak("欢迎来到助盲跑。\(locationText)可以点击开始约跑。")
        }
    }

    func repeatCurrentStatus(locationDescription: String) {
        if activeOrder != nil {
            speechService?.repeatCurrentStatus()
        } else {
            speechService?.speak("当前没有进行中的预约。当前位置：\(locationDescription)。可以点击开始约跑。")
        }
    }

    func cancelActiveOrder() async {
        guard let activeOrder, let appState else { return }
        guard activeOrder.status.canBlindRunnerCancel else {
            let message = "当前订单状态不能由盲人取消。"
            errorMessage = message
            speechService?.speakError(message)
            return
        }
        isPerformingAction = true
        errorMessage = nil
        do {
            let _: EmptyResponse = try await appState.apiClient.post("/api/orders/\(activeOrder.orderId)/cancel")
            let updated: OrderDetailResponse = try await appState.apiClient.get("/api/orders/\(activeOrder.orderId)")
            self.activeOrder = updated.status.isActiveForBlindRunner ? updated : nil
            self.speechService?.speakStatusChange(updated.status, text: updated.blindRunnerAnnouncement())
            isPerformingAction = false
        } catch let error as APIError {
            isPerformingAction = false
            errorMessage = error.localizedMessage
            speechService?.speakError(errorMessage ?? error.localizedMessage)
            if let updated: OrderDetailResponse = try? await appState.apiClient.get("/api/orders/\(activeOrder.orderId)") {
                self.activeOrder = updated.status.isActiveForBlindRunner ? updated : nil
            }
        } catch {
            isPerformingAction = false
            errorMessage = "取消失败。"
            speechService?.speakError(errorMessage ?? "取消失败。")
            if let updated: OrderDetailResponse = try? await appState.apiClient.get("/api/orders/\(activeOrder.orderId)") {
                self.activeOrder = updated.status.isActiveForBlindRunner ? updated : nil
            }
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

}

// MARK: - Blind Runner Home View

struct BlindRunnerHomeView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @EnvironmentObject private var locationService: LocationService
    @StateObject private var viewModel = BlindRunnerHomeViewModel()
    @State private var path: [BlindRunnerRoute] = []
    @State private var showCancelConfirmation = false

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    mapSection

                    if viewModel.isLoading {
                        ProgressView("正在加载当前状态...")
                            .tint(AppColors.primary)
                            .accessibilityLabel("正在加载当前状态")
                            .accessibilityHint("加载完成后会显示预约入口或当前订单")
                    }

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(AppFonts.body())
                            .foregroundColor(AppColors.destructive)
                            .accessibilityLabel(errorMessage)
                    }

                    if let order = viewModel.activeOrder {
                        activeOrderSection(order)
                    } else {
                        newBookingSection
                    }

                    repeatStatusButton

                    #if DEBUG
                    if AppBuildChannel.current.allowsEnvironmentSwitcher {
                        DebugTestingPanel()
                            .environmentObject(appState)
                    }
                    #endif
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 28)
            }
            .background(AppColors.background)
            .navigationTitle("")
            .navigationBarHidden(true)
            .navigationDestination(for: BlindRunnerRoute.self) { route in
                switch route {
                case .booking:
                    BlindBookingView { response in
                        viewModel.handleOrderCreated(response)
                        if let orderId = response.id {
                            path = [.orderStatus(orderId)]
                        }
                    }
                case .orderStatus(let orderId):
                    BlindOrderStatusView(orderId: orderId) { updatedOrder in
                        viewModel.activeOrder = updatedOrder.status.isActiveForBlindRunner ? updatedOrder : nil
                    }
                case .settings:
                    BlindRunnerSettingsView()
                }
            }
            .onAppear {
                viewModel.configure(with: appState, speechService: speechService)
                if locationService.isNotDetermined {
                    locationService.requestPermission()
                }
                locationService.startUpdating()
            }
            .task {
                await viewModel.loadActiveOrder()
            }
            .confirmationDialog("取消订单", isPresented: $showCancelConfirmation) {
                Button("确认取消", role: .destructive) {
                    Task {
                        await viewModel.cancelActiveOrder()
                    }
                }
                Button("不取消", role: .cancel) {}
            } message: {
                Text("确认取消本次预约？取消后将结束本次服务。")
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                HighContrastText("盲人跑者首页", style: .title)
                    .accessibilityAddTraits(.isHeader)

                Text(viewModel.currentStatusText)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textSecondary)
                    .accessibilityLabel(viewModel.currentStatusText)
                    .accessibilityHint("这里显示当前预约状态摘要")
            }

            Spacer()

            Button {
                path.append(.settings)
            } label: {
                Image(systemName: "gearshape")
                    .font(.title2)
                    .foregroundColor(AppColors.textPrimary)
            }
            .frame(minWidth: 64, minHeight: 64)
            .accessibilityLabel("设置")
            .accessibilityHint("进入设置页面，可以编辑资料、切换角色或退出登录")
        }
    }

    private var mapSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            MapViewWrapper(
                centerCoordinate: locationService.effectiveLocation,
                showsUserLocation: locationService.isAuthorized,
                annotations: []
            )
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityLabel("地图，显示当前位置")
            .accessibilityHint("地图为辅助显示，主要操作请使用下方按钮")

            Text(locationDescription)
                .font(AppFonts.body())
                .foregroundColor(locationService.isDenied ? AppColors.warning : AppColors.textSecondary)
                .accessibilityLabel(locationDescription)
                .accessibilityHint(locationService.isDenied ? "需要开启定位权限后才能创建预约" : "当前位置摘要")
        }
    }

    private var locationDescription: String {
        if locationService.isDenied {
            return "需要开启定位权限后才能创建预约。"
        }
        if let address = viewModel.activeOrder?.startAddress, !address.trimmed.isEmpty {
            return "订单出发点：\(address)。\(locationService.readableCurrentLocationSummary)"
        }
        return locationService.readableCurrentLocationSummary
    }

    private func activeOrderSection(_ order: OrderDetailResponse) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            BlindStatusCard(order: order)

            PrimaryButton("查看当前订单") {
                path.append(.orderStatus(order.orderId))
            }
            .accessibilityLabel("查看当前订单")
            .accessibilityHint("点击后查看订单状态详情")

            if viewModel.canCancelActiveOrder {
                Button("取消订单") {
                    showCancelConfirmation = true
                }
                .font(AppFonts.body().weight(.semibold))
                .foregroundColor(AppColors.destructive)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 64)
                .disabled(viewModel.isPerformingAction)
                .accessibilityLabel("取消订单")
                .accessibilityHint("需要确认后取消当前订单")
            }
        }
    }

    private var newBookingSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("准备好后，可以创建一次新的陪跑预约。")
                .font(AppFonts.body())
                .foregroundColor(AppColors.textSecondary)
                .accessibilityLabel("准备好后，可以创建一次新的陪跑预约")

            NavigationLink(value: BlindRunnerRoute.booking) {
                HStack {
                    Text("开始约跑")
                        .font(AppFonts.primaryButton())
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 64)
                .background(AppColors.primary)
                .cornerRadius(12)
            }
            .accessibilityLabel("开始约跑")
            .accessibilityHint("点击后创建跑步预约")
        }
    }

    private var repeatStatusButton: some View {
        PrimaryButton("重复当前状态") {
            viewModel.repeatCurrentStatus(locationDescription: locationDescription)
        }
        .accessibilityLabel("重复当前状态")
        .accessibilityHint("点击后重新播报当前页面信息")
    }
}

// MARK: - Shared Blind Runner Components

struct BlindStatusCard: View {
    let order: OrderDetailResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: order.status.statusSymbolName)
                    .font(.title)
                    .foregroundColor(order.status.statusColor)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(order.status.displayName)
                        .font(.title2.bold())
                        .foregroundColor(AppColors.textPrimary)
                    Text(order.status.blindRunnerDescription)
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.textSecondary)
                }
            }

            Divider()
                .background(AppColors.textSecondary.opacity(0.4))

            Text("预约时间：\((order.plannedStart ?? "").displayDateTime)")
                .font(AppFonts.body())
                .foregroundColor(AppColors.textPrimary)
            Text("出发地点：\(order.startAddress ?? "")")
                .font(AppFonts.body())
                .foregroundColor(AppColors.textPrimary)
            if let volunteerPhone = order.volunteerPhone, !volunteerPhone.trimmed.isEmpty {
                Text("志愿者电话：\(volunteerPhone)")
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textPrimary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.secondaryBackground)
        .cornerRadius(8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("当前订单：\(order.status.displayName)，预约时间 \((order.plannedStart ?? "").displayDateTime)，出发地点 \(order.startAddress ?? "")")
        .accessibilityHint("订单状态摘要")
    }
}

#if DEBUG
struct DebugTestingPanel: View {
    @EnvironmentObject private var appState: AppState
    @State private var showEnvironmentConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("测试入口")
                .font(.headline)
                .foregroundColor(AppColors.textPrimary)

            Button {
                appState.returnToRoleSelectionForTesting()
            } label: {
                Text("返回角色选择")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("返回角色选择")
            .accessibilityHint("回到角色选择页，用于测试不同身份")

            Button {
                showEnvironmentConfirmation = true
            } label: {
                Text("切换测试模式：\(appState.currentEnvironment.displayName)")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("切换测试模式")
            .accessibilityHint("当前模式 \(appState.currentEnvironment.displayName)，点击后可切换并重新登录")
        }
        .padding()
        .background(AppColors.secondaryBackground)
        .cornerRadius(8)
        .confirmationDialog("切换测试模式", isPresented: $showEnvironmentConfirmation) {
            Button("切换到 \(nextEnvironment.displayName) 并重新登录", role: .destructive) {
                appState.switchToNextEnvironmentForTesting()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("切换测试模式会清除当前登录状态，并返回登录页。")
        }
    }

    private var nextEnvironment: APIEnvironment {
        let allEnvironments = AppState.debugTestEnvironments
        guard let currentIndex = allEnvironments.firstIndex(of: appState.currentEnvironment) else {
            return .mock
        }
        return allEnvironments[(currentIndex + 1) % allEnvironments.count]
    }
}
#endif

#if DEBUG
#Preview {
    BlindRunnerHomeView()
        .environmentObject(AppState())
        .environmentObject(SpeechService())
        .environmentObject(LocationService())
}
#endif
