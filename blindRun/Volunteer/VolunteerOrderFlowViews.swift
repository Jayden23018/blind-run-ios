import Combine
import CoreLocation
import SwiftUI

// MARK: - Volunteer Shared Models

struct VolunteerAvailableOrderRow: Identifiable {
    let order: OrderDetailResponse
    let distanceMeters: CLLocationDistance?

    var id: Int64 { order.orderId }

    var distanceText: String {
        guard let distanceMeters else { return "距离不可用" }
        return DistanceCalculator.formattedDistance(distanceMeters)
    }

    var annotation: MapAnnotationItem? {
        guard let lat = order.startLatitude, let lng = order.startLongitude else { return nil }
        return MapAnnotationItem(
            id: String(order.orderId),
            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
            title: order.startAddress ?? "",
            subtitle: order.blindName
        )
    }

    func accessibilityLabel(locationAuthorized: Bool) -> String {
        let distance = locationAuthorized ? distanceText : "距离不可用"
        return "盲人：\(order.blindName ?? "")，距离：\(distance)，地点：\(order.startAddress ?? "")，时间：\((order.plannedStart ?? "").displayDateTime)"
    }

    static func sortedRows(
        orders: [OrderDetailResponse],
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
    let order: OrderDetailResponse

    var id: Int64 { order.orderId }
    var pointsText: String { order.status == .completed ? "+100 积分" : "—" }
    var sortKey: String { order.createdAt ?? order.plannedStart ?? "" }

    var accessibilityLabel: String {
        "时间：\(sortKey.displayDateTime)，盲人：\(order.blindName ?? "")，地点：\(order.startAddress ?? "")，状态：\(order.status.displayName)，积分：\(pointsText)"
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
    static func acceptBlockMessage(profile: VolunteerProfileResponse?, locationAuthorized: Bool) -> String? {
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
        case .pendingMatch:
            return "可接订单"
        case .pendingAccept:
            return "已接单，请前往约定地点"
        case .inProgress:
            return "服务进行中"
        case .driverEnRoute:
            return "正在前往约定地点"
        case .driverArrived:
            return "已到达，等待开始服务"
        case .completed:
            return "服务完成，获得 +100 积分"
        case .cancelled:
            return "订单已取消"
        case .rematching:
            return "订单正在重新匹配"
        case .noVolunteer:
            return "暂无志愿者"
        }
    }

    var serviceStageTitle: String {
        switch self {
        case .pendingAccept:
            return "前往集合地点"
        case .driverEnRoute:
            return "正在前往"
        case .driverArrived:
            return "已到达集合地点"
        case .inProgress:
            return "服务进行中"
        case .completed:
            return "行程结算"
        case .cancelled:
            return "订单已取消"
        case .rematching, .noVolunteer:
            return "订单异常"
        case .pendingMatch:
            return "等待接单"
        }
    }

    var serviceStageSubtitle: String {
        switch self {
        case .pendingAccept:
            return "请尽快到达集合地点"
        case .driverEnRoute:
            return "盲人跑者正在等待"
        case .driverArrived, .inProgress:
            return "完成本次陪跑后可结束服务"
        case .completed:
            return "感谢您的爱心陪伴"
        case .cancelled:
            return "本次服务已取消"
        case .rematching, .noVolunteer:
            return "本次服务已结束"
        case .pendingMatch:
            return "订单尚未进入服务流程"
        }
    }
}

private func orderCoordinate(_ order: OrderDetailResponse) -> CLLocationCoordinate2D? {
    guard let lat = order.startLatitude, let lng = order.startLongitude else { return nil }
    return CLLocationCoordinate2D(latitude: lat, longitude: lng)
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
            let profile: VolunteerProfileResponse = try await appState.apiClient.get("/api/volunteer/profile")
            appState.updateVolunteerProfile(profile)
            isAvailable = profile.isAvailable ?? false

            let paged: PagedOrderResponse = try await appState.apiClient.get("/api/orders/available")
            rows = VolunteerAvailableOrderRow.sortedRows(
                orders: paged.content,
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
            let request = VolunteerProfileUpdateRequest(isAvailable: value)
            let profile: VolunteerProfileResponse = try await appState.apiClient.put(
                "/api/volunteer/profile",
                body: request
            )
            appState.updateVolunteerProfile(profile)
            isAvailable = profile.isAvailable ?? false
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
                            VolunteerOrderDetailView(orderId: row.order.orderId)
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
    @Published var order: OrderDetailResponse?
    @Published var isLoading = false
    @Published var isPerformingAction = false
    @Published var errorMessage: String?

    private weak var appState: AppState?
    private var speechService: SpeechService?

    var canAccept: Bool {
        order?.status == .pendingMatch
    }

    var canShowPhone: Bool {
        guard let order else { return false }
        return order.status != .pendingMatch && order.blindPhone?.trimmed.isEmpty == false
    }

    func configure(with appState: AppState, speechService: SpeechService) {
        self.appState = appState
        self.speechService = speechService
    }

    func load(orderId: Int64) async {
        guard let appState else { return }
        isLoading = order == nil
        errorMessage = nil

        do {
            let loaded: OrderDetailResponse = try await appState.apiClient.get("/api/orders/\(orderId)")
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
            let _: OrderResponse = try await appState.apiClient.post("/api/orders/\(order.orderId)/accept")
            let updated: OrderDetailResponse = try await appState.apiClient.get("/api/orders/\(order.orderId)")
            self.order = updated
        }
    }

    func enRoute() async {
        guard let order, let appState else { return }
        await performAction(failureMessage: "操作失败，请重试") {
            let _: OrderResponse = try await appState.apiClient.post("/api/orders/\(order.orderId)/en-route")
            let updated: OrderDetailResponse = try await appState.apiClient.get("/api/orders/\(order.orderId)")
            self.order = updated
        }
    }

    func arrive() async {
        guard let order, let appState else { return }
        await performAction(failureMessage: "操作失败，请重试") {
            let _: OrderResponse = try await appState.apiClient.post("/api/orders/\(order.orderId)/arrived")
            let updated: OrderDetailResponse = try await appState.apiClient.get("/api/orders/\(order.orderId)")
            self.order = updated
        }
    }

    func cancel() async {
        guard let order, let appState else { return }
        await performAction(failureMessage: "取消失败，请重试") {
            let _: OrderResponse = try await appState.apiClient.post("/api/orders/\(order.orderId)/cancel")
            let updated: OrderDetailResponse = try await appState.apiClient.get("/api/orders/\(order.orderId)")
            self.order = updated
        }
    }

    func emergency() async {
        guard let order, let appState else { return }
        let request = EmergencyTriggerRequest(orderId: order.orderId, gpsLat: nil, gpsLng: nil)
        await performAction(failureMessage: "求助操作失败，请重试") {
            let _: OrderResponse = try await appState.apiClient.post("/api/emergency/trigger", body: request)
            let updated: OrderDetailResponse = try await appState.apiClient.get("/api/orders/\(order.orderId)")
            if order.status != updated.status {
                self.speechService?.speakStatusChange(updated.status)
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
    @State private var showCancelConfirm = false
    @State private var showEmergencyConfirm = false
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
                    VolunteerOrderMap(order: order)
                    VolunteerBlindRunnerInfoCard(order: order, showPhone: viewModel.canShowPhone)
                    VolunteerOrderInfoSection(order: order, distanceText: distanceText(for: order))
                    actionSection(order)
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
        .confirmationDialog("取消订单", isPresented: $showCancelConfirm) {
            Button("确认取消", role: .destructive) {
                Task { await viewModel.cancel() }
            }
            Button("不取消", role: .cancel) {}
        } message: {
            Text("确认取消本次预约？")
        }
        .emergencyConfirmationAlert(isPresented: $showEmergencyConfirm) {
            Task {
                await viewModel.emergency()
            }
        }
    }

    private func actionSection(_ order: OrderDetailResponse) -> some View {
        VStack(spacing: 12) {
            if order.status == .pendingMatch {
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
            } else if order.status == .pendingAccept || order.status == .inProgress || order.status == .driverEnRoute || order.status == .driverArrived {
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

                if order.status.canCancel {
                    Button("取消订单", role: .destructive) {
                        showCancelConfirm = true
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
                    .accessibilityLabel("取消订单")
                    .accessibilityHint("需要确认后取消")
                }

                if order.status.canTriggerEmergency {
                    EmergencyActionButton(isLoading: viewModel.isPerformingAction) {
                        showEmergencyConfirm = true
                    }
                }
            }
        }
    }

    private func distanceText(for order: OrderDetailResponse) -> String? {
        guard locationService.isAuthorized, let coordinate = orderCoordinate(order) else { return nil }
        let meters = DistanceCalculator.distance(
            from: locationService.effectiveLocation,
            to: coordinate
        )
        return DistanceCalculator.formattedDistance(meters)
    }
}

// MARK: - In Service

@MainActor
final class VolunteerInServiceViewModel: ObservableObject {
    @Published var order: OrderDetailResponse?
    @Published var isLoading = false
    @Published var isPerformingAction = false
    @Published var errorMessage: String?

    private weak var appState: AppState?
    private var speechService: SpeechService?
    private var pollingTask: Task<Void, Never>?

    func configure(with appState: AppState, speechService: SpeechService, initialOrder: OrderDetailResponse?) {
        self.appState = appState
        self.speechService = speechService
        if order == nil {
            order = initialOrder
        }
    }

    func startPolling(orderId: Int64) {
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

    func load(orderId: Int64, speakChanges: Bool) async {
        guard let appState else { return }
        isLoading = order == nil
        do {
            let loaded: OrderDetailResponse = try await appState.apiClient.get("/api/orders/\(orderId)")
            apply(loaded, speakChanges: speakChanges)
            isLoading = false
        } catch {
            isLoading = false
            if order == nil {
                errorMessage = "获取订单状态失败"
            }
        }
    }

    func enRoute() async {
        guard let order, let appState else { return }
        await performAction(failureMessage: "操作失败，请重试") {
            let _: OrderResponse = try await appState.apiClient.post("/api/orders/\(order.orderId)/en-route")
            let updated: OrderDetailResponse = try await appState.apiClient.get("/api/orders/\(order.orderId)")
            apply(updated, speakChanges: false)
        }
    }

    func arrive() async {
        guard let order, let appState else { return }
        await performAction(failureMessage: "操作失败，请重试") {
            let _: OrderResponse = try await appState.apiClient.post("/api/orders/\(order.orderId)/arrived")
            let updated: OrderDetailResponse = try await appState.apiClient.get("/api/orders/\(order.orderId)")
            apply(updated, speakChanges: false)
        }
    }

    func cancel() async {
        guard let order, let appState else { return }
        await performAction(failureMessage: "取消失败，请重试") {
            let _: OrderResponse = try await appState.apiClient.post("/api/orders/\(order.orderId)/cancel")
            let updated: OrderDetailResponse = try await appState.apiClient.get("/api/orders/\(order.orderId)")
            apply(updated, speakChanges: false)
        }
    }

    func complete(summary: String) async {
        guard let order, let appState else { return }
        await performAction(failureMessage: "操作失败，请重试") {
            let _: OrderResponse = try await appState.apiClient.post("/api/orders/\(order.orderId)/finish")
            let updated: OrderDetailResponse = try await appState.apiClient.get("/api/orders/\(order.orderId)")
            apply(updated, speakChanges: false)
        }
    }

    func emergency() async {
        guard let order, let appState else { return }
        let request = EmergencyTriggerRequest(orderId: order.orderId, gpsLat: nil, gpsLng: nil)
        await performAction(failureMessage: "求助操作失败，请重试") {
            let _: OrderResponse = try await appState.apiClient.post("/api/emergency/trigger", body: request)
            let updated: OrderDetailResponse = try await appState.apiClient.get("/api/orders/\(order.orderId)")
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

    private func apply(_ updated: OrderDetailResponse, speakChanges: Bool) {
        let previousStatus = order?.status
        order = updated
        if speakChanges, previousStatus != updated.status {
            speechService?.speakStatusChange(updated.status)
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
    @State private var showCancelConfirm = false
    @State private var showEmergencyConfirm = false
    @State private var activeSheet: VolunteerSheet?
    let orderId: Int64
    let initialOrder: OrderDetailResponse?

    init(orderId: Int64, initialOrder: OrderDetailResponse? = nil) {
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
                        onEnRoute: { Task { await viewModel.enRoute() } },
                        onArrive: { Task { await viewModel.arrive() } },
                        onCancel: { showCancelConfirm = true },
                        onComplete: { activeSheet = .completion },
                        onEmergency: { showEmergencyConfirm = true }
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
        .confirmationDialog("取消订单", isPresented: $showCancelConfirm) {
            Button("确认取消", role: .destructive) {
                Task { await viewModel.cancel() }
            }
            Button("不取消", role: .cancel) {}
        } message: {
            Text("确认取消本次预约？")
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

    private func distanceText(for order: OrderDetailResponse) -> String? {
        guard locationService.isAuthorized, let coordinate = orderCoordinate(order) else { return nil }
        let meters = DistanceCalculator.distance(
            from: locationService.effectiveLocation,
            to: coordinate
        )
        return DistanceCalculator.formattedDistance(meters)
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
            let paged: PagedOrderResponse = try await appState.apiClient.get("/api/orders/mine")
            records = paged.content
                .filter { [.completed, .cancelled].contains($0.status) }
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
    @Published var errorMessage: String?

    private weak var appState: AppState?

    func configure(with appState: AppState) {
        self.appState = appState
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
                    Text("--")
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
                .accessibilityLabel("积分商城占位")

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
        }
    }
}

// MARK: - Settings

@MainActor
final class VolunteerSettingsViewModel: ObservableObject {
    @Published var errorMessage: String?

    func switchToBlindRunner(appState: AppState) async {
        do {
            let request = SetRoleRequest(role: .blind)
            let response: SetRoleResponse = try await appState.apiClient.post("/api/user/role", body: request)
            appState.handleRoleSwitchSuccess(response: response, requestedRole: .blind)
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
                settingsRow("昵称", value: appState.volunteerProfile?.name ?? "未填写")
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
                Text(row.order.blindName ?? "盲人跑者")
                    .font(.headline)
                    .foregroundColor(AppColors.textPrimary)
                Spacer()
                Text(locationAuthorized ? row.distanceText : "距离隐藏")
                    .font(AppFonts.caption().weight(.semibold))
                    .foregroundColor(locationAuthorized ? AppColors.primary : AppColors.textSecondary)
            }
            Text(row.order.startAddress ?? "")
                .font(AppFonts.body())
                .foregroundColor(AppColors.textPrimary)
            Text((row.order.plannedStart ?? "").displayDateTime)
                .font(AppFonts.caption())
                .foregroundColor(AppColors.textSecondary)
            if let notes = row.order.routeNotes?.nilIfBlank {
                Text(notes)
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
    let order: OrderDetailResponse

    var body: some View {
        if let coordinate = orderCoordinate(order) {
            MapViewWrapper(
                centerCoordinate: coordinate,
                showsUserLocation: locationService.isAuthorized,
                annotations: [
                    MapAnnotationItem(
                        id: String(order.orderId),
                        coordinate: coordinate,
                        title: order.startAddress ?? "",
                        subtitle: order.blindName
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
}

struct VolunteerServiceMapBackdrop: View {
    @EnvironmentObject private var locationService: LocationService
    let order: OrderDetailResponse

    var body: some View {
        let coordinate = orderCoordinate(order) ?? locationService.effectiveLocation
        MapViewWrapper(
            centerCoordinate: coordinate,
            showsUserLocation: locationService.isAuthorized,
            annotations: orderCoordinate(order).map { coord in
                [MapAnnotationItem(
                    id: String(order.orderId),
                    coordinate: coord,
                    title: order.startAddress ?? "",
                    subtitle: order.blindName
                )]
            } ?? [],
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

struct VolunteerServiceBottomPanel: View {
    let order: OrderDetailResponse
    let distanceText: String?
    let errorMessage: String?
    let isPerformingAction: Bool
    let maxHeight: CGFloat
    let onEnRoute: () -> Void
    let onArrive: () -> Void
    let onCancel: () -> Void
    let onComplete: () -> Void
    let onEmergency: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                VolunteerServiceStageHeader(status: order.status)
                VolunteerServiceRunnerCard(order: order)
                VolunteerServiceOrderEssentials(order: order, distanceText: distanceText)

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
                    onEnRoute: onEnRoute,
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
    let order: OrderDetailResponse

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
                Text(order.blindName ?? "盲人跑者")
                    .font(.title3.weight(.bold))
                    .foregroundColor(AppColors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 10)

            if let phone = order.blindPhone?.nilIfBlank {
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
    let order: OrderDetailResponse
    let distanceText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            serviceRow(systemImage: "mappin.and.ellipse", title: "出发地点", value: order.startAddress ?? "")
            serviceRow(systemImage: "clock", title: "预约时间", value: (order.plannedStart ?? "").displayDateTime)

            if let distanceText {
                serviceRow(systemImage: "location", title: "当前位置距离", value: distanceText)
            }

            if let routeNotes = order.routeNotes?.nilIfBlank {
                serviceRow(systemImage: "point.topleft.down.curvedto.point.bottomright.up", title: "路线备注", value: routeNotes)
            }

            if let notes = order.specialNotes?.nilIfBlank {
                serviceRow(systemImage: "text.bubble", title: "特殊说明", value: notes)
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
    let onEnRoute: () -> Void
    let onArrive: () -> Void
    let onCancel: () -> Void
    let onComplete: () -> Void
    let onEmergency: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            if status == .pendingAccept {
                PrimaryButton("我已出发", isLoading: isPerformingAction, action: onEnRoute)
                    .accessibilityLabel("我已出发")
                    .accessibilityHint("点击后通知盲人您正在前往")
                secondaryDangerButton("取消订单", hint: "取消当前订单", action: onCancel)
            } else if status == .driverEnRoute {
                PrimaryButton("我已到达约定地点", isLoading: isPerformingAction, action: onArrive)
                    .accessibilityLabel("我已到达约定地点")
                secondaryDangerButton("取消订单", hint: "取消当前订单", action: onCancel)
            } else if status == .driverArrived || status == .inProgress {
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
            } else if status == .cancelled || status == .noVolunteer {
                Text(status.volunteerDescription)
                    .font(AppFonts.body().weight(.semibold))
                    .foregroundColor(AppColors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 64)
                    .background(AppColors.secondaryBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .accessibilityLabel(status.volunteerDescription)
            }

            if status.canTriggerEmergency {
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
    let order: OrderDetailResponse
    let showPhone: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("盲人跑者")
                .font(.headline)
                .foregroundColor(AppColors.textPrimary)
            Text(order.blindName ?? "盲人跑者")
                .font(AppFonts.body())
                .foregroundColor(AppColors.textPrimary)
                .accessibilityLabel("盲人：\(order.blindName ?? "")")

            if showPhone, let phone = order.blindPhone {
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
    let order: OrderDetailResponse
    let distanceText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("订单信息")
                .font(.headline)
                .foregroundColor(AppColors.textPrimary)
            infoRow("出发地点", order.startAddress ?? "")
            infoRow("预约时间", (order.plannedStart ?? "").displayDateTime)
            if let distanceText {
                infoRow("距离", distanceText)
            }
            if let routeNotes = order.routeNotes?.nilIfBlank {
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
            if order.hasGuideDogThisRun == true {
                infoRow("导盲犬", "本次携带")
            }
            if let notes = order.specialNotes?.nilIfBlank {
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
            Text("盲人：\(record.order.blindName ?? "")")
                .font(AppFonts.body())
            Text(record.order.startAddress ?? "")
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
    let order: OrderDetailResponse

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VolunteerStatusBanner(status: order.status)
                VolunteerBlindRunnerInfoCard(order: order, showPhone: order.status != .pendingMatch && order.blindPhone?.trimmed.isEmpty == false)
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
        VStack(spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundColor(AppColors.textPrimary)
            Text(message)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)，\(message)")
    }
}

// MARK: - Complete Service Sheet

struct CompleteServiceSheet: View {
    let isPerformingAction: Bool
    let onComplete: (String) async -> Void
    @State private var summaryText = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                Text("服务已结束")
                    .font(.largeTitle.bold())
                    .foregroundColor(AppColors.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                Text("如果有需要记录的内容，可以在下方添加服务总结。")
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textSecondary)

                TextEditor(text: $summaryText)
                    .frame(minHeight: 120)
                    .padding(8)
                    .background(AppColors.secondaryBackground)
                    .cornerRadius(8)
                    .accessibilityLabel("服务总结，选填")
                    .accessibilityHint("可以记录本次服务的要点")

                PrimaryButton("确认完成服务", isLoading: isPerformingAction) {
                    Task { await onComplete(summaryText) }
                }
                .accessibilityLabel("确认完成服务")
                .accessibilityHint("确认后订单标记为已完成")

                Spacer()
            }
            .padding(24)
            .navigationTitle("结束服务")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}

#if DEBUG
#Preview("Order List") {
    NavigationStack {
        VolunteerOrderListView()
            .environmentObject(AppState())
            .environmentObject(SpeechService())
            .environmentObject(LocationService())
    }
}
#endif
