import Combine
import CoreLocation
import SwiftUI

// MARK: - Volunteer Shared Models

struct VolunteerAvailableOrderRow: Identifiable {
    let order: AvailableOrderDto
    let distanceMeters: CLLocationDistance?

    var id: String { order.id }

    var distanceText: String {
        guard let distanceMeters else { return "距离不可用" }
        return DistanceCalculator.formattedDistance(distanceMeters)
    }

    var annotation: MapAnnotationItem {
        MapAnnotationItem(
            id: order.id,
            coordinate: CLLocationCoordinate2D(
                latitude: order.startLocation.latitude,
                longitude: order.startLocation.longitude
            ),
            title: order.startLocation.displayAddress,
            subtitle: order.blindRunnerNickname
        )
    }

    func accessibilityLabel(locationAuthorized: Bool) -> String {
        let distance = locationAuthorized ? distanceText : "距离不可用"
        return "盲人：\(order.blindRunnerNickname)，距离：\(distance)，地点：\(order.startLocation.displayAddress)，时间：\(order.appointmentTime.displayDateTime)"
    }

    static func sortedRows(
        orders: [AvailableOrderDto],
        from location: CLLocationCoordinate2D?,
        locationAuthorized: Bool
    ) -> [VolunteerAvailableOrderRow] {
        guard locationAuthorized, let location else {
            return orders.map { VolunteerAvailableOrderRow(order: $0, distanceMeters: nil) }
        }

        return DistanceCalculator
            .sortOrdersByDistance(orders: orders, from: location)
            .map { VolunteerAvailableOrderRow(order: $0.order, distanceMeters: $0.distance) }
    }
}

struct VolunteerServiceRecord: Identifiable {
    let order: RunOrderDto

    var id: String { order.id }
    var pointsText: String { order.status == .completed ? "+100 积分" : "—" }
    var sortKey: String { order.completedAt ?? order.cancelledAt ?? order.emergencyAt ?? order.updatedAtSortKey }

    var accessibilityLabel: String {
        "时间：\(sortKey.displayDateTime)，盲人：\(order.blindRunnerNickname)，地点：\(order.startLocation.displayAddress)，状态：\(order.status.displayName)，积分：\(pointsText)"
    }
}

private enum VolunteerSheet: Identifiable {
    case completion

    var id: String {
        switch self {
        case .completion: return "completion"
        }
    }
}

// MARK: - Shared Guards and Helpers

extension VolunteerOrderActionGuard {
    static func acceptBlockMessage(profile: VolunteerProfileDto?, locationAuthorized: Bool) -> String? {
        if let message = acceptBlockMessage(profile: profile) {
            return message
        }
        guard locationAuthorized else {
            return "需要开启定位权限才能接单"
        }
        return nil
    }
}

extension RunOrderStatus {
    var volunteerDescription: String {
        switch self {
        case .matching:
            return "可接订单"
        case .accepted:
            return "已接单，请前往约定地点"
        case .arrived:
            return "已到达，等待盲人确认开始服务"
        case .inProgress:
            return "服务进行中"
        case .completed:
            return "服务完成，获得 +100 积分"
        case .cancelled:
            return "订单已取消"
        case .emergency:
            return "已进入求助状态"
        }
    }

    var serviceStageTitle: String {
        switch self {
        case .accepted:
            return "前往集合地点"
        case .arrived:
            return "已到达集合地点"
        case .inProgress:
            return "服务进行中"
        case .completed:
            return "行程结算"
        case .cancelled:
            return "订单已取消"
        case .emergency:
            return "求助状态"
        case .matching:
            return "等待接单"
        }
    }

    var serviceStageSubtitle: String {
        switch self {
        case .accepted:
            return "请尽快到达集合地点"
        case .arrived:
            return "等待盲人确认开始服务"
        case .inProgress:
            return "完成本次陪跑后可结束服务"
        case .completed:
            return "感谢您的爱心陪伴"
        case .cancelled:
            return "本次服务已取消"
        case .emergency:
            return "本次服务已标记为异常"
        case .matching:
            return "订单尚未进入服务流程"
        }
    }
}

private func shouldShowVolunteerPhone(for order: RunOrderDto) -> Bool {
    order.status != .matching && order.blindRunnerPhone?.trimmed.isEmpty == false
}

private func orderCoordinate(_ point: LocationPoint) -> CLLocationCoordinate2D {
    CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
}

// MARK: - Order List

@MainActor
final class VolunteerOrderListViewModel: ObservableObject {
    @Published var isAvailable = false
    @Published var rows: [VolunteerAvailableOrderRow] = []
    @Published var isLoading = false
    @Published var isUpdatingAvailability = false
    @Published var errorMessage: String?

    private weak var appState: AppState?
    private var speechService: SpeechService?

    func configure(with appState: AppState, speechService: SpeechService) {
        self.appState = appState
        self.speechService = speechService
        isAvailable = appState.volunteerProfile?.isAvailable ?? false
    }

    func load(currentLocation: CLLocationCoordinate2D?, locationAuthorized: Bool) async {
        guard let appState else { return }
        isLoading = rows.isEmpty
        errorMessage = nil

        do {
            let response: UserMeResponse = try await appState.apiClient.get("/api/users/me")
            appState.updateUserMe(response)
            isAvailable = response.volunteerProfile?.isAvailable ?? false

            let orders: [AvailableOrderDto] = try await appState.apiClient.get("/api/orders/available")
            rows = VolunteerAvailableOrderRow.sortedRows(
                orders: orders,
                from: currentLocation,
                locationAuthorized: locationAuthorized
            )
            isLoading = false
        } catch let error as APIError {
            isLoading = false
            errorMessage = error.localizedMessage
            speechService?.speakError(error.localizedMessage)
        } catch {
            isLoading = false
            errorMessage = "加载失败，下拉重试"
            speechService?.speakError("加载失败，下拉重试")
        }
    }

    func setAvailability(_ value: Bool) {
        guard !isUpdatingAvailability, let appState else { return }
        let previousValue = isAvailable
        isAvailable = value
        Task {
            await updateAvailability(value, previousValue: previousValue, appState: appState)
        }
    }

    private func updateAvailability(_ value: Bool, previousValue: Bool, appState: AppState) async {
        isUpdatingAvailability = true
        errorMessage = nil
        do {
            let profile: VolunteerProfileDto = try await appState.apiClient.patch(
                "/api/volunteer/availability",
                body: AvailabilityRequest(isAvailable: value)
            )
            appState.updateVolunteerProfile(profile)
            isAvailable = profile.isAvailable
            isUpdatingAvailability = false
        } catch let error as APIError {
            isAvailable = previousValue
            isUpdatingAvailability = false
            errorMessage = error.localizedMessage
            speechService?.speakError(error.localizedMessage)
        } catch {
            isAvailable = previousValue
            isUpdatingAvailability = false
            errorMessage = "可服务状态更新失败，请重试"
            speechService?.speakError("可服务状态更新失败，请重试")
        }
    }
}

struct VolunteerOrderListView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @EnvironmentObject private var locationService: LocationService
    @StateObject private var viewModel = VolunteerOrderListViewModel()

    var body: some View {
        List {
            Section {
                Toggle(
                    "可服务",
                    isOn: Binding(
                        get: { viewModel.isAvailable },
                        set: { viewModel.setAvailability($0) }
                    )
                )
                .disabled(!appState.isVolunteerProfileApproved || viewModel.isUpdatingAvailability)
                .accessibilityLabel("可服务开关")
                .accessibilityHint("关闭后仍可浏览订单，但不能接单")

                if !locationService.isAuthorized {
                    Text("需要定位权限。订单仍可浏览，但距离隐藏，接单禁用。")
                        .font(AppFonts.caption())
                        .foregroundColor(AppColors.warning)
                        .accessibilityLabel("需要定位权限，订单仍可浏览，但距离隐藏，接单禁用")
                }
            }

            Section("可接订单") {
                if viewModel.isLoading {
                    ProgressView("正在加载订单...")
                        .accessibilityLabel("正在加载订单")
                } else if viewModel.rows.isEmpty {
                    EmptyStateView(title: "暂无可用订单", message: "下拉刷新试试。")
                        .listRowSeparator(.hidden)
                } else {
                    ForEach(viewModel.rows) { row in
                        NavigationLink {
                            VolunteerOrderDetailView(orderId: row.order.id, initialOrder: row.order)
                        } label: {
                            VolunteerAvailableOrderCard(row: row, locationAuthorized: locationService.isAuthorized)
                        }
                        .accessibilityLabel(row.accessibilityLabel(locationAuthorized: locationService.isAuthorized))
                        .accessibilityHint("点击查看详情")
                    }
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundColor(AppColors.destructive)
                        .accessibilityLabel(errorMessage)
                }
            }
        }
        .navigationTitle("可接订单")
        .task {
            viewModel.configure(with: appState, speechService: speechService)
            locationService.requestPermission()
            locationService.startUpdating()
            await viewModel.load(
                currentLocation: locationService.effectiveLocation,
                locationAuthorized: locationService.isAuthorized
            )
        }
        .refreshable {
            await viewModel.load(
                currentLocation: locationService.effectiveLocation,
                locationAuthorized: locationService.isAuthorized
            )
        }
    }
}

// MARK: - Order Detail

@MainActor
final class VolunteerOrderDetailViewModel: ObservableObject {
    @Published var order: RunOrderDto?
    @Published var isLoading = false
    @Published var isPerformingAction = false
    @Published var errorMessage: String?

    private weak var appState: AppState?
    private var speechService: SpeechService?

    var canAccept: Bool {
        order?.status == .matching
    }

    var canShowPhone: Bool {
        guard let order else { return false }
        return shouldShowVolunteerPhone(for: order)
    }

    func configure(with appState: AppState, speechService: SpeechService) {
        self.appState = appState
        self.speechService = speechService
    }

    func load(orderId: String) async {
        guard let appState else { return }
        isLoading = order == nil
        errorMessage = nil

        do {
            let loaded: RunOrderDto = try await appState.apiClient.get("/api/orders/\(orderId)")
            order = loaded
            isLoading = false
        } catch let error as APIError {
            isLoading = false
            errorMessage = error.localizedMessage
            speechService?.speakError(error.localizedMessage)
        } catch {
            isLoading = false
            errorMessage = "订单加载失败，请重试"
            speechService?.speakError("订单加载失败，请重试")
        }
    }

    func accept(locationAuthorized: Bool) async {
        guard let order, let appState else { return }
        if let message = VolunteerOrderActionGuard.acceptBlockMessage(
            profile: appState.volunteerProfile,
            locationAuthorized: locationAuthorized
        ) {
            errorMessage = message
            speechService?.speakError(message)
            return
        }
        await performAction(failureMessage: "接单失败，请重试") {
            let updated: RunOrderDto = try await appState.apiClient.post("/api/orders/\(order.id)/accept")
            self.order = updated
        }
    }

    func arrive() async {
        guard let order, let appState else { return }
        await performAction(failureMessage: "操作失败，请重试") {
            let updated: RunOrderDto = try await appState.apiClient.post("/api/orders/\(order.id)/arrive")
            self.order = updated
        }
    }

    func cancel(reason: ManualCancellationReason) async {
        guard let order, let appState else { return }
        let request = CancelOrderRequest(cancelledBy: .volunteer, cancelledReason: reason, otherReasonText: nil)
        await performAction(failureMessage: "取消失败，请重试") {
            let updated: RunOrderDto = try await appState.apiClient.post("/api/orders/\(order.id)/cancel", body: request)
            self.order = updated
        }
    }

    func emergency() async {
        guard let order, let appState else { return }
        await performAction(failureMessage: "求助操作失败，请重试") {
            let updated: RunOrderDto = try await appState.apiClient.post("/api/orders/\(order.id)/emergency")
            if order.status != updated.status {
                speechService?.speakStatusChange(updated.status)
            }
            self.order = updated
        }
    }

    private func performAction(failureMessage: String, operation: () async throws -> Void) async {
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

struct VolunteerOrderDetailView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @EnvironmentObject private var locationService: LocationService
    @StateObject private var viewModel = VolunteerOrderDetailViewModel()
    @State private var showAcceptConfirm = false
    @State private var showCancelReasons = false
    @State private var showEmergencyConfirm = false
    let orderId: String
    let initialOrder: AvailableOrderDto?

    init(orderId: String, initialOrder: AvailableOrderDto? = nil) {
        self.orderId = orderId
        self.initialOrder = initialOrder
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if viewModel.isLoading && viewModel.order == nil {
                    ProgressView("正在加载订单...")
                        .accessibilityLabel("正在加载订单")
                }

                if let order = viewModel.order {
                    VolunteerStatusBanner(status: order.status)
                    VolunteerOrderMap(order: order)
                    VolunteerBlindRunnerInfoCard(order: order, showPhone: viewModel.canShowPhone)
                    VolunteerOrderInfoSection(order: order, distanceText: distanceText(for: order))
                    actionSection(order)
                } else if let initialOrder {
                    VolunteerAvailableOrderInfoSection(order: initialOrder, distanceText: distanceText(for: initialOrder))
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.destructive)
                        .accessibilityLabel(errorMessage)
                }
            }
            .padding(20)
        }
        .navigationTitle("订单详情")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            viewModel.configure(with: appState, speechService: speechService)
            locationService.requestPermission()
            locationService.startUpdating()
            await viewModel.load(orderId: orderId)
        }
        .alert("确认接单", isPresented: $showAcceptConfirm) {
            Button("确认接单") {
                Task { await viewModel.accept(locationAuthorized: locationService.isAuthorized) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("确认接单后将显示盲人联系方式。")
        }
        .confirmationDialog("取消订单", isPresented: $showCancelReasons) {
            ForEach(ManualCancellationReason.allCases, id: \.self) { reason in
                Button(reason.displayName, role: .destructive) {
                    Task { await viewModel.cancel(reason: reason) }
                }
            }
            Button("不取消", role: .cancel) {}
        } message: {
            Text("请选择取消原因。")
        }
        .emergencyConfirmationAlert(isPresented: $showEmergencyConfirm) {
            Task {
                await viewModel.emergency()
            }
        }
    }

    private func actionSection(_ order: RunOrderDto) -> some View {
        VStack(spacing: 12) {
            if order.status == .matching {
                let blockMessage = VolunteerOrderActionGuard.acceptBlockMessage(
                    profile: appState.volunteerProfile,
                    locationAuthorized: locationService.isAuthorized
                )
                PrimaryButton("接单", isLoading: viewModel.isPerformingAction) {
                    showAcceptConfirm = true
                }
                .disabled(blockMessage != nil || viewModel.isPerformingAction)
                .opacity(blockMessage == nil ? 1 : 0.45)
                .accessibilityLabel("接单")
                .accessibilityHint(blockMessage ?? "确认接单后将显示盲人联系方式")

                if let blockMessage {
                    Text(blockMessage)
                        .font(AppFonts.caption())
                        .foregroundColor(AppColors.warning)
                        .accessibilityLabel(blockMessage)
                }
            } else if order.status == .accepted || order.status == .arrived || order.status == .inProgress {
                NavigationLink {
                    VolunteerInServiceView(orderId: order.id, initialOrder: order)
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

                if order.status == .accepted {
                    PrimaryButton("我已到达", isLoading: viewModel.isPerformingAction) {
                        Task { await viewModel.arrive() }
                    }
                    .accessibilityLabel("我已到达约定地点")
                }

                if order.status == .accepted || order.status == .arrived {
                    Button("取消订单", role: .destructive) {
                        showCancelReasons = true
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
                    .accessibilityLabel("取消订单")
                    .accessibilityHint("需要选择取消原因并确认")
                }

                if order.status.canEnterEmergency {
                    EmergencyActionButton(isLoading: viewModel.isPerformingAction) {
                        showEmergencyConfirm = true
                    }
                }
            }
        }
    }

    private func distanceText(for order: RunOrderDto) -> String? {
        guard locationService.isAuthorized else { return nil }
        let meters = DistanceCalculator.distance(
            from: locationService.effectiveLocation,
            to: orderCoordinate(order.startLocation)
        )
        return DistanceCalculator.formattedDistance(meters)
    }

    private func distanceText(for order: AvailableOrderDto) -> String? {
        guard locationService.isAuthorized else { return nil }
        let meters = DistanceCalculator.distance(
            from: locationService.effectiveLocation,
            to: orderCoordinate(order.startLocation)
        )
        return DistanceCalculator.formattedDistance(meters)
    }
}

// MARK: - In Service

@MainActor
final class VolunteerInServiceViewModel: ObservableObject {
    @Published var order: RunOrderDto?
    @Published var isLoading = false
    @Published var isPerformingAction = false
    @Published var errorMessage: String?

    private weak var appState: AppState?
    private var speechService: SpeechService?
    private var pollingTask: Task<Void, Never>?

    func configure(with appState: AppState, speechService: SpeechService, initialOrder: RunOrderDto?) {
        self.appState = appState
        self.speechService = speechService
        if order == nil {
            order = initialOrder
        }
    }

    func startPolling(orderId: String) {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            await self?.load(orderId: orderId, speakChanges: true)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(AppConstants.Timing.orderPollingInterval * 1_000_000_000))
                if Task.isCancelled { return }
                await self?.load(orderId: orderId, speakChanges: true)
                if self?.order?.status.isTerminal == true {
                    return
                }
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func load(orderId: String, speakChanges: Bool) async {
        guard let appState else { return }
        isLoading = order == nil
        do {
            let loaded: RunOrderDto = try await appState.apiClient.get("/api/orders/\(orderId)")
            apply(loaded, speakChanges: speakChanges)
            isLoading = false
        } catch {
            isLoading = false
            if order == nil {
                errorMessage = "获取订单状态失败"
            }
        }
    }

    func arrive() async {
        guard let order, let appState else { return }
        await performAction(failureMessage: "操作失败，请重试") {
            let updated: RunOrderDto = try await appState.apiClient.post("/api/orders/\(order.id)/arrive")
            apply(updated, speakChanges: false)
        }
    }

    func cancel(reason: ManualCancellationReason) async {
        guard let order, let appState else { return }
        let request = CancelOrderRequest(cancelledBy: .volunteer, cancelledReason: reason, otherReasonText: nil)
        await performAction(failureMessage: "取消失败，请重试") {
            let updated: RunOrderDto = try await appState.apiClient.post("/api/orders/\(order.id)/cancel", body: request)
            apply(updated, speakChanges: false)
        }
    }

    func complete(summary: String) async {
        guard let order, let appState else { return }
        let request = CompleteOrderRequest(summaryText: summary.nilIfBlank)
        await performAction(failureMessage: "操作失败，请重试") {
            let updated: RunOrderDto = try await appState.apiClient.post("/api/orders/\(order.id)/complete", body: request)
            apply(updated, speakChanges: false)
            let userMe: UserMeResponse = try await appState.apiClient.get("/api/users/me")
            appState.updateUserMe(userMe)
        }
    }

    func emergency() async {
        guard let order, let appState else { return }
        await performAction(failureMessage: "求助操作失败，请重试") {
            let updated: RunOrderDto = try await appState.apiClient.post("/api/orders/\(order.id)/emergency")
            apply(updated, speakChanges: true)
        }
    }

    private func performAction(failureMessage: String, operation: () async throws -> Void) async {
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
            if updated.status == .inProgress {
                speechService?.speak("服务已开始")
            } else if updated.status == .emergency {
                speechService?.speakStatusChange(updated.status)
            }
        }
        if updated.status.isTerminal {
            stopPolling()
        }
    }
}

struct VolunteerInServiceView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @EnvironmentObject private var locationService: LocationService
    @StateObject private var viewModel = VolunteerInServiceViewModel()
    @State private var showCancelReasons = false
    @State private var showEmergencyConfirm = false
    @State private var activeSheet: VolunteerSheet?
    let orderId: String
    let initialOrder: RunOrderDto?

    init(orderId: String, initialOrder: RunOrderDto? = nil) {
        self.orderId = orderId
        self.initialOrder = initialOrder
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                if let order = viewModel.order {
                    VolunteerServiceMapBackdrop(order: order)
                } else {
                    AppColors.secondaryBackground
                        .ignoresSafeArea()
                }

                if viewModel.isLoading && viewModel.order == nil {
                    ProgressView("正在获取订单状态...")
                        .padding()
                        .background(.regularMaterial)
                        .cornerRadius(8)
                        .accessibilityLabel("正在获取订单状态")
                }

                if let order = viewModel.order {
                    VolunteerServiceBottomPanel(
                        order: order,
                        distanceText: distanceText(for: order),
                        errorMessage: viewModel.errorMessage,
                        isPerformingAction: viewModel.isPerformingAction,
                        maxHeight: proxy.size.height * 0.62,
                        onArrive: { Task { await viewModel.arrive() } },
                        onCancel: { showCancelReasons = true },
                        onComplete: { activeSheet = .completion },
                        onEmergency: { showEmergencyConfirm = true },
                        debugControls: { debugMockControls(order) }
                    )
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                }
            }
        }
        .navigationTitle("服务中")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task {
            viewModel.configure(with: appState, speechService: speechService, initialOrder: initialOrder)
            locationService.startUpdating()
            viewModel.startPolling(orderId: orderId)
        }
        .onDisappear {
            viewModel.stopPolling()
        }
        .confirmationDialog("取消订单", isPresented: $showCancelReasons) {
            ForEach(ManualCancellationReason.allCases, id: \.self) { reason in
                Button(reason.displayName, role: .destructive) {
                    Task { await viewModel.cancel(reason: reason) }
                }
            }
            Button("不取消", role: .cancel) {}
        } message: {
            Text("请选择取消原因。")
        }
        .emergencyConfirmationAlert(isPresented: $showEmergencyConfirm) {
            Task {
                await viewModel.emergency()
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .completion:
                CompleteServiceSheet(isPerformingAction: viewModel.isPerformingAction) { summary in
                    await viewModel.complete(summary: summary)
                    activeSheet = nil
                }
            }
        }
    }

    private func distanceText(for order: RunOrderDto) -> String? {
        guard locationService.isAuthorized else { return nil }
        let meters = DistanceCalculator.distance(
            from: locationService.effectiveLocation,
            to: orderCoordinate(order.startLocation)
        )
        return DistanceCalculator.formattedDistance(meters)
    }

    @ViewBuilder
    private func debugMockControls(_ order: RunOrderDto) -> some View {
        #if DEBUG
        if appState.currentEnvironment == .mock, order.status == .arrived {
            Button("模拟盲人确认开始") {
                Task {
                    let updated: RunOrderDto? = try? await appState.apiClient.post("/api/orders/\(order.id)/confirm-start")
                    if let updated {
                        viewModel.order = updated
                    }
                }
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("模拟盲人确认开始")
        }
        #endif
    }
}

// MARK: - Service Records

@MainActor
final class VolunteerServiceRecordsViewModel: ObservableObject {
    @Published var records: [VolunteerServiceRecord] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private weak var appState: AppState?
    private var speechService: SpeechService?

    func configure(with appState: AppState, speechService: SpeechService) {
        self.appState = appState
        self.speechService = speechService
    }

    func load() async {
        guard let appState else { return }
        isLoading = records.isEmpty
        errorMessage = nil
        do {
            let orders: [RunOrderDto] = try await appState.apiClient.get("/api/orders/my")
            records = orders
                .filter { [.completed, .cancelled, .emergency].contains($0.status) && $0.volunteerUserId != nil }
                .map(VolunteerServiceRecord.init(order:))
                .sorted { $0.sortKey > $1.sortKey }
            isLoading = false
        } catch let error as APIError {
            isLoading = false
            errorMessage = error.localizedMessage
            speechService?.speakError(error.localizedMessage)
        } catch {
            isLoading = false
            errorMessage = "加载失败，下拉重试"
            speechService?.speakError("加载失败，下拉重试")
        }
    }
}

struct VolunteerServiceRecordsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @StateObject private var viewModel = VolunteerServiceRecordsViewModel()

    var body: some View {
        List {
            if viewModel.isLoading {
                ProgressView("正在加载服务记录...")
                    .accessibilityLabel("正在加载服务记录")
            } else if viewModel.records.isEmpty {
                EmptyStateView(title: "暂无服务记录", message: "完成服务后记录将显示在这里。")
                NavigationLink {
                    VolunteerOrderListView()
                } label: {
                    Text("去接单")
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 64)
                }
                .accessibilityLabel("去接单")
                .accessibilityHint("点击查看可接订单")
            } else {
                ForEach(viewModel.records) { record in
                    NavigationLink {
                        VolunteerReadOnlyOrderView(order: record.order)
                    } label: {
                        VolunteerServiceRecordRow(record: record)
                    }
                    .accessibilityLabel(record.accessibilityLabel)
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundColor(AppColors.destructive)
                    .accessibilityLabel(errorMessage)
            }
        }
        .navigationTitle("服务记录")
        .task {
            viewModel.configure(with: appState, speechService: speechService)
            await viewModel.load()
        }
        .refreshable {
            await viewModel.load()
        }
    }
}

// MARK: - Points Placeholder

@MainActor
final class VolunteerPointsViewModel: ObservableObject {
    @Published var pointsBalance: Int?
    @Published var errorMessage: String?

    private weak var appState: AppState?

    func configure(with appState: AppState) {
        self.appState = appState
        pointsBalance = appState.volunteerProfile?.pointsBalance
    }

    func load() async {
        guard let appState else { return }
        do {
            let response: UserMeResponse = try await appState.apiClient.get("/api/users/me")
            appState.updateUserMe(response)
            pointsBalance = response.volunteerProfile?.pointsBalance
        } catch {
            errorMessage = "积分加载失败"
        }
    }
}

struct VolunteerPointsPlaceholderView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = VolunteerPointsViewModel()

    private let products: [(name: String, icon: String)] = [
        ("运动腰包", "bag"),
        ("运动水壶", "waterbottle"),
        ("运动毛巾", "tshirt"),
        ("跑步腰灯", "flashlight.on.fill")
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text(viewModel.pointsBalance.map(String.init) ?? "--")
                        .font(.system(size: 48, weight: .bold))
                        .foregroundColor(AppColors.textPrimary)
                    Text("积分")
                        .font(.headline)
                    Text("每完成一次服务 +100 积分")
                        .font(AppFonts.caption())
                        .foregroundColor(AppColors.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(AppColors.secondaryBackground)
                .cornerRadius(8)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("当前积分：\(viewModel.pointsBalance.map(String.init) ?? "--")分")

                VStack(spacing: 8) {
                    Image(systemName: "gift.fill")
                        .font(.system(size: 42))
                        .foregroundColor(AppColors.primary)
                    Text("积分商城即将上线，敬请期待")
                        .font(AppFonts.title())
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("积分商城即将上线，敬请期待")

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(products, id: \.name) { product in
                        VStack(spacing: 10) {
                            Image(systemName: product.icon)
                                .font(.title)
                                .foregroundColor(AppColors.primary)
                            Text(product.name)
                                .font(.headline)
                            Text("敬请期待")
                                .font(AppFonts.caption())
                                .foregroundColor(AppColors.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(AppColors.secondaryBackground)
                        .cornerRadius(8)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(product.name)，敬请期待")
                    }
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .foregroundColor(AppColors.destructive)
                        .accessibilityLabel(errorMessage)
                }
            }
            .padding(20)
        }
        .navigationTitle("积分商城")
        .task {
            viewModel.configure(with: appState)
            await viewModel.load()
        }
    }
}

// MARK: - Settings

@MainActor
final class VolunteerSettingsViewModel: ObservableObject {
    @Published var errorMessage: String?

    func switchToBlindRunner(appState: AppState) async {
        do {
            let user: UserDto = try await appState.apiClient.patch(
                "/api/users/me/active-role",
                body: SwitchRoleRequest(activeRole: .blindRunner)
            )
            appState.updateCurrentUser(user, fallbackActiveRole: .blindRunner)
        } catch let error as APIError {
            errorMessage = error.localizedMessage
        } catch {
            errorMessage = "切换角色失败，请重试"
        }
    }
}

struct VolunteerSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = VolunteerSettingsViewModel()
    @State private var showLogoutConfirm = false
    @State private var showRoleSwitchConfirm = false

    var body: some View {
        List {
            Section {
                settingsRow("昵称", value: appState.volunteerProfile?.nickname ?? appState.currentUser?.nickname ?? "未填写")
                settingsRow("手机号", value: appState.currentUser?.phoneNumber ?? appState.volunteerProfile?.phoneNumber ?? "未获取")
                settingsRow("当前角色", value: "志愿者")
            }

            Section {
                NavigationLink("个人资料") {
                    VolunteerProfileView()
                }
                .accessibilityLabel("个人资料")
                .accessibilityHint("编辑志愿者资料")

                Button("切换角色") {
                    showRoleSwitchConfirm = true
                }
                .accessibilityLabel("切换角色")

                Picker("API 环境", selection: $appState.currentEnvironment) {
                    ForEach(APIEnvironment.allCases, id: \.self) { environment in
                        Text(environment.displayName).tag(environment)
                    }
                }
                .accessibilityLabel("API 环境，\(appState.currentEnvironment.displayName)")

                NavigationLink("关于") {
                    AboutAidRunView()
                }
            }

            Section {
                Button("退出登录", role: .destructive) {
                    showLogoutConfirm = true
                }
                .accessibilityLabel("退出登录")
                .accessibilityHint("退出后需要重新登录，需要二次确认")
            }

            if let errorMessage = viewModel.errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundColor(AppColors.destructive)
                        .accessibilityLabel(errorMessage)
                }
            }
        }
        .navigationTitle("设置")
        .alert("确认退出", isPresented: $showLogoutConfirm) {
            Button("确认退出", role: .destructive) {
                appState.clearSession()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("确认后将清除当前登录状态，返回登录页。")
        }
        .alert("切换角色", isPresented: $showRoleSwitchConfirm) {
            Button("切换到盲人跑者") {
                Task { await viewModel.switchToBlindRunner(appState: appState) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("如果有进行中的订单，系统会阻止切换角色。")
        }
    }

    private func settingsRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value)
                .foregroundColor(AppColors.textSecondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)：\(value)")
    }
}

struct AboutAidRunView: View {
    var body: some View {
        List {
            Section {
                Text("助盲跑 MVP")
                Text("iOS SwiftUI Demo")
                    .foregroundColor(AppColors.textSecondary)
            }
        }
        .navigationTitle("关于")
    }
}

// MARK: - Reusable Views

struct VolunteerAvailableOrderCard: View {
    let row: VolunteerAvailableOrderRow
    let locationAuthorized: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(row.order.blindRunnerNickname)
                    .font(.headline)
                    .foregroundColor(AppColors.textPrimary)
                Spacer()
                Text(locationAuthorized ? row.distanceText : "距离隐藏")
                    .font(AppFonts.caption().weight(.semibold))
                    .foregroundColor(locationAuthorized ? AppColors.primary : AppColors.textSecondary)
            }
            Text(row.order.startLocation.displayAddress)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textPrimary)
            Text(row.order.appointmentTime.displayDateTime)
                .font(AppFonts.caption())
                .foregroundColor(AppColors.textSecondary)
            if let remark = row.order.remark?.nilIfBlank {
                Text(remark)
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.secondaryBackground)
        .cornerRadius(8)
    }
}

struct VolunteerStatusBanner: View {
    let status: RunOrderStatus

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: status.statusSymbolName)
                .font(.title)
                .foregroundColor(status.statusColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(status.displayName)
                    .font(.headline)
                    .foregroundColor(AppColors.textPrimary)
                Text(status.volunteerDescription)
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.textSecondary)
            }
            Spacer()
        }
        .padding()
        .background(AppColors.secondaryBackground)
        .cornerRadius(8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(status.displayName)，\(status.volunteerDescription)")
    }
}

struct VolunteerOrderMap: View {
    @EnvironmentObject private var locationService: LocationService
    let order: RunOrderDto

    var body: some View {
        MapViewWrapper(
            centerCoordinate: orderCoordinate(order.startLocation),
            showsUserLocation: locationService.isAuthorized,
            annotations: [
                MapAnnotationItem(
                    id: order.id,
                    coordinate: orderCoordinate(order.startLocation),
                    title: order.startLocation.displayAddress,
                    subtitle: order.blindRunnerNickname
                )
            ],
            zoomLevel: 15
        )
        .frame(height: 210)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityLabel("地图，显示出发点位置")
        .accessibilityHint("不提供路线导航")
    }
}

struct VolunteerServiceMapBackdrop: View {
    @EnvironmentObject private var locationService: LocationService
    let order: RunOrderDto

    var body: some View {
        MapViewWrapper(
            centerCoordinate: orderCoordinate(order.startLocation),
            showsUserLocation: locationService.isAuthorized,
            annotations: [
                MapAnnotationItem(
                    id: order.id,
                    coordinate: orderCoordinate(order.startLocation),
                    title: order.startLocation.displayAddress,
                    subtitle: order.blindRunnerNickname
                )
            ],
            zoomLevel: 15
        )
        .ignoresSafeArea()
        .overlay(alignment: .bottom) {
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.12)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 260)
            .allowsHitTesting(false)
        }
        .accessibilityLabel("地图，显示出发点位置")
        .accessibilityHint("不提供路线导航或实时轨迹")
    }
}

struct VolunteerServiceBottomPanel<DebugControls: View>: View {
    let order: RunOrderDto
    let distanceText: String?
    let errorMessage: String?
    let isPerformingAction: Bool
    let maxHeight: CGFloat
    let onArrive: () -> Void
    let onCancel: () -> Void
    let onComplete: () -> Void
    let onEmergency: () -> Void
    @ViewBuilder let debugControls: () -> DebugControls

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                VolunteerServiceStageHeader(status: order.status)
                VolunteerServiceRunnerCard(order: order)
                VolunteerServiceOrderEssentials(order: order, distanceText: distanceText)
                debugControls()

                if let errorMessage {
                    Text(errorMessage)
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.destructive)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel(errorMessage)
                }

                VolunteerServiceActions(
                    status: order.status,
                    isPerformingAction: isPerformingAction,
                    onArrive: onArrive,
                    onCancel: onCancel,
                    onComplete: onComplete,
                    onEmergency: onEmergency
                )
            }
            .padding(.horizontal, 22)
            .padding(.top, 26)
            .padding(.bottom, 22)
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: maxHeight)
        .background(AppColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: Color.black.opacity(0.16), radius: 22, x: 0, y: -8)
        .accessibilityElement(children: .contain)
    }
}

struct VolunteerServiceStageHeader: View {
    let status: RunOrderStatus

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: status.statusSymbolName)
                    .foregroundColor(status.statusColor)
                    .accessibilityHidden(true)
                Text(status.displayName)
                    .font(AppFonts.caption().weight(.semibold))
                    .foregroundColor(status.statusColor)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(status.statusColor.opacity(0.12))
            .cornerRadius(999)

            Text(status.serviceStageTitle)
                .font(.system(size: 34, weight: .bold))
                .foregroundColor(AppColors.textPrimary)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.72)
                .lineLimit(2)

            Text(status.serviceStageSubtitle)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(status.displayName)，\(status.serviceStageTitle)，\(status.serviceStageSubtitle)")
    }
}

struct VolunteerServiceRunnerCard: View {
    @Environment(\.openURL) private var openURL
    let order: RunOrderDto

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.pink.opacity(0.18))
                Image(systemName: "person.fill")
                    .font(.title2)
                    .foregroundColor(.pink)
            }
            .frame(width: 56, height: 56)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("盲人跑者")
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.textSecondary)
                Text(order.blindRunnerNickname)
                    .font(.title3.weight(.bold))
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 10)

            if let phone = order.blindRunnerPhone?.nilIfBlank {
                Button {
                    if let url = URL(string: "tel://\(phone)") {
                        openURL(url)
                    }
                } label: {
                    Label(phone, systemImage: "phone.fill")
                        .labelStyle(.titleAndIcon)
                        .font(AppFonts.body().weight(.semibold))
                        .foregroundColor(AppColors.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                .accessibilityLabel("拨打盲人电话 \(phone)")
            } else {
                Text("电话暂不可用")
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.textSecondary)
                    .accessibilityLabel("盲人电话暂不可用")
            }
        }
        .padding(16)
        .background(AppColors.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

struct VolunteerServiceOrderEssentials: View {
    let order: RunOrderDto
    let distanceText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            serviceRow(systemImage: "mappin.and.ellipse", title: "出发地点", value: order.startLocation.displayAddress)
            serviceRow(systemImage: "clock", title: "预约时间", value: order.appointmentTime.displayDateTime)

            if let distanceText {
                serviceRow(systemImage: "location", title: "当前位置距离", value: distanceText)
            }

            if let destination = order.destinationText?.nilIfBlank {
                serviceRow(systemImage: "point.topleft.down.curvedto.point.bottomright.up", title: "目的地 / 路线", value: destination)
            }

            if let remark = order.remark?.nilIfBlank {
                serviceRow(systemImage: "text.bubble", title: "备注", value: remark)
            }
        }
        .padding(16)
        .background(AppColors.secondaryBackground.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func serviceRow(systemImage: String, title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundColor(AppColors.textPrimary)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.textSecondary)
                Text(value)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)：\(value)")
    }
}

struct VolunteerServiceActions: View {
    let status: RunOrderStatus
    let isPerformingAction: Bool
    let onArrive: () -> Void
    let onCancel: () -> Void
    let onComplete: () -> Void
    let onEmergency: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            if status == .accepted {
                PrimaryButton("我已到达约定地点", isLoading: isPerformingAction, action: onArrive)
                    .accessibilityLabel("我已到达约定地点")
                secondaryDangerButton("取消订单", hint: "服务开始前取消当前订单，需要选择取消原因并确认", action: onCancel)
            } else if status == .arrived {
                Text("等待盲人确认开始服务")
                    .font(AppFonts.body().weight(.semibold))
                    .foregroundColor(AppColors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 64)
                    .background(AppColors.secondaryBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityLabel("已到达，等待盲人确认开始服务")

                secondaryDangerButton("取消订单", hint: "服务开始前取消当前订单，需要选择取消原因并确认", action: onCancel)
            } else if status == .inProgress {
                PrimaryButton("结束服务", isDestructive: true, isLoading: isPerformingAction, action: onComplete)
                    .accessibilityLabel("结束服务")
                    .accessibilityHint("需要使用二次确认")
            } else if status == .completed {
                Text("服务完成，获得 +100 积分")
                    .font(AppFonts.body().weight(.semibold))
                    .foregroundColor(AppColors.success)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 64)
                    .background(AppColors.success.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityLabel("服务完成，获得一百积分")
            } else if status == .cancelled || status == .emergency {
                Text(status.volunteerDescription)
                    .font(AppFonts.body().weight(.semibold))
                    .foregroundColor(status == .emergency ? AppColors.destructive : AppColors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 64)
                    .background(AppColors.secondaryBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityLabel(status.volunteerDescription)
            }

            if status.canEnterEmergency {
                EmergencyActionButton(isLoading: isPerformingAction, action: onEmergency)
            }
        }
    }

    private func secondaryDangerButton(_ title: String, hint: String, action: @escaping () -> Void) -> some View {
        Button(role: .destructive, action: action) {
            Text(title)
                .font(AppFonts.body().weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
                .background(AppColors.destructive.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .disabled(isPerformingAction)
        .accessibilityLabel(title)
        .accessibilityHint(hint)
    }
}

struct VolunteerBlindRunnerInfoCard: View {
    @Environment(\.openURL) private var openURL
    let order: RunOrderDto
    let showPhone: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("盲人跑者")
                .font(.headline)
                .foregroundColor(AppColors.textPrimary)
            Text(order.blindRunnerNickname)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textPrimary)
                .accessibilityLabel("盲人：\(order.blindRunnerNickname)")

            if showPhone, let phone = order.blindRunnerPhone {
                Button {
                    if let url = URL(string: "tel://\(phone)") {
                        openURL(url)
                    }
                } label: {
                    Label(phone, systemImage: "phone.fill")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityLabel("拨打盲人电话 \(phone)")
            } else {
                Text("联系方式将在接单后显示")
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.textSecondary)
                    .accessibilityLabel("联系方式将在接单后显示")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.secondaryBackground)
        .cornerRadius(8)
    }
}

struct VolunteerOrderInfoSection: View {
    let order: RunOrderDto
    let distanceText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("订单信息")
                .font(.headline)
                .foregroundColor(AppColors.textPrimary)
            infoRow("出发地点", order.startLocation.displayAddress)
            infoRow("预约时间", order.appointmentTime.displayDateTime)
            if let distanceText {
                infoRow("距离", distanceText)
            }
            if let destination = order.destinationText?.nilIfBlank {
                infoRow("目的地 / 路线", destination)
            }
            if let minutes = order.estimatedDurationMinutes {
                infoRow("预计时长", "\(minutes) 分钟")
            }
            if let distance = order.estimatedDistanceKm {
                infoRow("预计距离", String(format: "%.1f 公里", distance))
            }
            if let pace = order.pacePreference?.nilIfBlank {
                infoRow("配速偏好", pace)
            }
            if let preferSameGender = order.preferSameGender {
                infoRow("同性志愿者", preferSameGender ? "需要" : "不需要")
            }
            if let remark = order.remark?.nilIfBlank {
                infoRow("备注", remark)
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

struct VolunteerAvailableOrderInfoSection: View {
    let order: AvailableOrderDto
    let distanceText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("订单信息")
                .font(.headline)
            infoRow("盲人", order.blindRunnerNickname)
            infoRow("出发地点", order.startLocation.displayAddress)
            infoRow("预约时间", order.appointmentTime.displayDateTime)
            if let distanceText {
                infoRow("距离", distanceText)
            }
            if let destination = order.destinationText?.nilIfBlank {
                infoRow("目的地 / 路线", destination)
            }
            if let minutes = order.estimatedDurationMinutes {
                infoRow("预计时长", "\(minutes) 分钟")
            }
            if let distance = order.estimatedDistanceKm {
                infoRow("预计距离", String(format: "%.1f 公里", distance))
            }
            if let pace = order.pacePreference?.nilIfBlank {
                infoRow("配速偏好", pace)
            }
            if let preferSameGender = order.preferSameGender {
                infoRow("同性志愿者", preferSameGender ? "需要" : "不需要")
            }
            if let remark = order.remark?.nilIfBlank {
                infoRow("备注", remark)
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

struct VolunteerServiceRecordRow: View {
    let record: VolunteerServiceRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(record.sortKey.displayDateTime)
                    .font(.headline)
                Spacer()
                Text(record.order.status.displayName)
                    .font(AppFonts.caption().weight(.semibold))
                    .foregroundColor(record.order.status == .completed ? AppColors.success : AppColors.textSecondary)
            }
            Text("盲人：\(record.order.blindRunnerNickname)")
                .font(AppFonts.body())
            Text(record.order.startLocation.displayAddress)
                .font(AppFonts.caption())
                .foregroundColor(AppColors.textSecondary)
            Text(record.pointsText)
                .font(AppFonts.caption().weight(.semibold))
                .foregroundColor(record.order.status == .completed ? AppColors.success : AppColors.textSecondary)
        }
        .padding(.vertical, 4)
    }
}

struct VolunteerReadOnlyOrderView: View {
    let order: RunOrderDto

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VolunteerStatusBanner(status: order.status)
                VolunteerBlindRunnerInfoCard(order: order, showPhone: shouldShowVolunteerPhone(for: order))
                VolunteerOrderInfoSection(order: order, distanceText: nil)
            }
            .padding(20)
        }
        .navigationTitle("订单详情")
    }
}

struct EmptyStateView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "figure.run")
                .font(.largeTitle)
                .foregroundColor(AppColors.textSecondary)
            Text(title)
                .font(.headline)
                .foregroundColor(AppColors.textPrimary)
            Text(message)
                .font(AppFonts.caption())
                .foregroundColor(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)，\(message)")
    }
}

struct CompleteServiceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var speechService: SpeechService
    @EnvironmentObject private var speechInputService: SpeechInputService
    @State private var summary = ""
    @State private var showConfirm = false
    let isPerformingAction: Bool
    let onConfirm: (String) async -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                VoiceTextField(
                    title: "服务总结（选填）",
                    placeholder: "例如：顺利完成慢跑陪伴",
                    text: $summary,
                    isMultiline: true,
                    speechInputService: speechInputService,
                    speechService: speechService,
                    speechField: .volunteerServiceSummary,
                    accessibilityLabel: "服务总结，选填",
                    accessibilityHint: "可以使用语音或键盘输入本次服务总结"
                )

                PrimaryButton("确认结束服务", isLoading: isPerformingAction) {
                    showConfirm = true
                }
                .accessibilityLabel("确认结束服务")
                .accessibilityHint("点击后弹出二次确认")

                Spacer()
            }
            .padding(20)
            .navigationTitle("结束服务")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .alert("确认结束服务", isPresented: $showConfirm) {
                Button("确认结束", role: .destructive) {
                    Task { await onConfirm(summary) }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("确认结束本次服务？结束后订单将标记为已完成。")
            }
        }
    }
}

#if DEBUG
#Preview("Volunteer order list") {
    NavigationStack {
        VolunteerOrderListView()
            .environmentObject(AppState())
            .environmentObject(SpeechService())
            .environmentObject(SpeechInputService())
            .environmentObject(LocationService())
    }
}
#endif
