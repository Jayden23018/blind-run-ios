import Combine
import CoreLocation
import SwiftUI
// 长按结束那枚按钮要的触觉强度与读屏播报（`VolunteerFinishLongPressButton`）。
import UIKit

// MARK: - Volunteer Shared Models

struct VolunteerServiceRecord: Identifiable {
    let order: OrderDetailResponse

    var id: Int64 { order.orderId }
    var sortKey: String { order.createdAt ?? order.plannedStart ?? "" }

    // 这里此前是 `pointsText`，值恒为「+100 积分」——后端从来没有过积分字段，
    // 那个数字是客户端凭 `status == .completed` 现编的，还被念进了下面这条 label。
    // 真实的服务量在「服务成就」页（`VolunteerServiceRecognitionView`），
    // 来自 `GET /api/volunteer/achievements`。
    ///
    /// 姓名走 `unmaskedForSpeech`：这条字符串**只进读屏**，可见那份在行里另有一份。
    var accessibilityLabel: String {
        "时间：\(sortKey.displayDateTime)，盲人：\(order.blindName?.unmaskedForSpeech ?? "")，地点：\(order.startAddress ?? "")，状态：\(order.status.displayName)"
    }
}

private enum VolunteerSheet: Identifiable {
    case navigation(ExternalMapNavigationRequest)
    /// 汇合态的「找不到对方」。**纯本地**：契约里没有「我找不到他」这个动作。
    case cannotFindRunner
    /// 「上报问题」→ `POST /api/support/tickets`。
    case supportTicket
    /// 取消这次陪跑的确认层。
    case cancelOrder

    var id: String {
        switch self {
        case .navigation(let request):
            return "navigation-\(request.id.uuidString)"
        case .cannotFindRunner:
            return "cannotFindRunner"
        case .supportTicket:
            return "supportTicket"
        case .cancelOrder:
            return "cancelOrder"
        }
    }
}

// MARK: - Shared Guards and Helpers

extension VolunteerOrderActionGuard {
    static func acceptBlockMessage(
        profile: VolunteerProfileResponse?,
        registrationStatus: VolunteerRegistrationStatus? = nil,
        locationAuthorized: Bool
    ) -> String? {
        if let message = acceptBlockMessage(profile: profile, registrationStatus: registrationStatus) {
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
        // 中性、不归因：志愿者同样不该被告知自己是「第几个候选人」。
        case .pendingIntroCall:
            return "等待与跑者通话确认"
        // 说清**还没到点**，否则志愿者会以为现在就该出发。「请确认」那半句留给动作按钮，
        // 不写进状态名 —— 状态名会出现在列表、卡片、读屏 label 里，那些地方带一个祈使句是噪音。
        case .scheduledConfirmed:
            return "已接单，等出发前确认"
        case .pendingAccept:
            return "已接单，请前往约定地点"
        case .inProgress:
            return "服务进行中"
        case .driverEnRoute:
            return "正在前往约定地点"
        case .driverArrived:
            return "已到达，可开始服务"
        case .completed:
            // 不再说「获得 +100 积分」：后端没有积分字段，那个数字是编的。
            // 但也不能只剩「服务完成」——这是志愿者跑完一趟唯一的正反馈，
            // 把承诺删掉不该连同反馈一起删掉。一句感谢不涉及任何数字，零成本且是真的。
            return "服务完成，感谢你的陪伴"
        case .cancelled:
            return "订单已取消"
        case .rematching:
            return "订单正在重新匹配"
        case .noVolunteer:
            return "暂无志愿者"
        case .unknown:
            return "订单状态有更新，请刷新页面"
        }
    }

    var serviceStageTitle: String {
        switch self {
        // 单独一档：这一态的阶段目标既不是「前往」也不是「等待接单」，是「确认你还去」。
        case .scheduledConfirmed:
            return "确认这次预约"
        case .pendingAccept, .driverEnRoute:
            return "前往出发地点"
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
        case .pendingIntroCall:
            return "通话确认"
        case .unknown:
            return "订单状态未知"
        }
    }

    var volunteerServiceDisplayName: String {
        switch self {
        case .pendingAccept:
            return "待出发"
        default:
            return displayName
        }
    }

    var serviceStageSubtitle: String {
        switch self {
        // 🚨 **不写「距开跑还有 X 小时要确认」**：那个提前量是后端配置
        // （`app.order.departure-confirm-window-minutes`），客户端读不到，写死就是编一个数字。
        // 只说清后果（不确认会转给别人），因为那是他真正需要知道的。
        case .scheduledConfirmed:
            return "这次陪跑还没到时间。出发前请确认你还会去，没有确认这一单会转给其他志愿者"
        case .pendingAccept:
            return "请确认当前位置和出发地点，可使用外部地图步行导航"
        case .driverEnRoute:
            return "请按导航前往出发地点，盲人跑者正在等待"
        case .driverArrived:
            return "已到达集合地点，请点击开始服务，服务开始前不能结束订单"
        case .inProgress:
            return "完成本次陪跑后可结束服务"
        case .completed:
            return "感谢您的爱心陪伴"
        case .cancelled:
            return "本次服务已取消"
        case .rematching, .noVolunteer:
            return "本次服务已结束"
        case .pendingMatch:
            return "订单尚未进入服务流程"
        case .pendingIntroCall:
            return "跑者会打电话给你，聊完双方都说合适才算接单"
        case .unknown:
            return "当前状态无法识别，请刷新后再操作"
        }
    }
}

private func orderCoordinate(_ order: OrderDetailResponse) -> CLLocationCoordinate2D? {
    guard let lat = order.startLatitude, let lng = order.startLongitude else { return nil }
    return CLLocationCoordinate2D(latitude: lat, longitude: lng)
}

struct VolunteerServiceMapPresentation {
    let centerCoordinate: CLLocationCoordinate2D
    let annotations: [MapAnnotationItem]
    let isCurrentLocationAvailable: Bool
    let hasCurrentLocationMarker: Bool

    init(
        order: OrderDetailResponse,
        currentLocation: CLLocationCoordinate2D?,
        locationAuthorized: Bool,
        fallbackCoordinate: CLLocationCoordinate2D,
        includesCurrentLocationMarker: Bool = false,
        centersOnCurrentAndStart: Bool = false
    ) {
        self.init(
            id: "order-start-\(order.orderId)",
            startCoordinate: orderCoordinate(order),
            startAddress: order.startAddress,
            currentLocation: currentLocation,
            locationAuthorized: locationAuthorized,
            fallbackCoordinate: fallbackCoordinate,
            includesCurrentLocationMarker: includesCurrentLocationMarker,
            centersOnCurrentAndStart: centersOnCurrentAndStart
        )
    }

    init(
        dispatchOrder: WSNewOrder,
        currentLocation: CLLocationCoordinate2D?,
        locationAuthorized: Bool,
        fallbackCoordinate: CLLocationCoordinate2D
    ) {
        let startCoordinate: CLLocationCoordinate2D?
        if let lat = dispatchOrder.startLatitude, let lng = dispatchOrder.startLongitude {
            startCoordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        } else {
            startCoordinate = nil
        }
        self.init(
            id: "dispatch-start-\(dispatchOrder.orderId)",
            startCoordinate: startCoordinate,
            startAddress: dispatchOrder.startAddress,
            currentLocation: currentLocation,
            locationAuthorized: locationAuthorized,
            fallbackCoordinate: fallbackCoordinate,
            includesCurrentLocationMarker: false,
            centersOnCurrentAndStart: false
        )
    }

    private init(
        id: String,
        startCoordinate: CLLocationCoordinate2D?,
        startAddress: String?,
        currentLocation: CLLocationCoordinate2D?,
        locationAuthorized: Bool,
        fallbackCoordinate: CLLocationCoordinate2D,
        includesCurrentLocationMarker: Bool,
        centersOnCurrentAndStart: Bool
    ) {
        let displayCurrentLocation = locationAuthorized ? currentLocation.flatMap {
            BackendCoordinateNormalizer.normalize(
                LocatedCoordinate(coordinate: $0, system: .wgs84Device)
            )?.coordinate
        } : nil

        var items: [MapAnnotationItem] = []
        if includesCurrentLocationMarker, let displayCurrentLocation {
            items.append(
                MapAnnotationItem(
                    id: "current-location",
                    coordinate: displayCurrentLocation,
                    title: "我的位置",
                    subtitle: nil,
                    kind: .currentLocation
                )
            )
        }

        if let startCoordinate {
            items.append(
                MapAnnotationItem(
                    id: id,
                    coordinate: startCoordinate,
                    title: "出发地点",
                    subtitle: startAddress,
                    kind: .orderStart
                )
            )
        }

        annotations = items
        isCurrentLocationAvailable = displayCurrentLocation != nil
        hasCurrentLocationMarker = includesCurrentLocationMarker && displayCurrentLocation != nil

        if centersOnCurrentAndStart, let displayCurrentLocation, let startCoordinate {
            centerCoordinate = CLLocationCoordinate2D(
                latitude: (displayCurrentLocation.latitude + startCoordinate.latitude) / 2,
                longitude: (displayCurrentLocation.longitude + startCoordinate.longitude) / 2
            )
        } else if let startCoordinate {
            centerCoordinate = startCoordinate
        } else if let displayCurrentLocation {
            centerCoordinate = displayCurrentLocation
        } else {
            centerCoordinate = fallbackCoordinate
        }
    }
}

struct VolunteerServiceMapLayout {
    static func screenAnchorY(
        viewportHeight: CGFloat,
        topSafeAreaInset: CGFloat,
        bottomPanelMaxHeight: CGFloat
    ) -> CGFloat {
        guard viewportHeight > 1 else { return 0.5 }
        let upper = max(topSafeAreaInset, 0)
        let lower = max(viewportHeight - bottomPanelMaxHeight, upper + 1)
        let visibleCenterY = (upper + lower) / 2
        return min(max(visibleCenterY / viewportHeight, 0.18), 0.45)
    }
}

private func externalNavigationRequest(
    for order: OrderDetailResponse,
    currentLocation: CLLocationCoordinate2D?,
    locationAuthorized: Bool
) -> ExternalMapNavigationRequest? {
    guard let destination = orderCoordinate(order) else { return nil }
    return ExternalMapNavigationRequest(
        originCoordinate: locationAuthorized ? currentLocation : nil,
        originName: "我的位置",
        destinationCoordinate: destination,
        destinationName: (order.startAddress?.nilIfBlank ?? "出发地点")
    )
}

// MARK: - Order Detail

private enum VolunteerOrderActionError: Error {
    case timedOut
}

enum VolunteerOrderTransitionState: Equatable {
    case idle
    case submitting(target: RunOrderStatus)
    case awaitingConfirmation(target: RunOrderStatus)
    case confirmationDelayed(target: RunOrderStatus)
    case failed(message: String)

    var targetStatus: RunOrderStatus? {
        switch self {
        case .submitting(let target),
             .awaitingConfirmation(let target),
             .confirmationDelayed(let target):
            return target
        case .idle, .failed:
            return nil
        }
    }

    var blocksDuplicateSubmission: Bool {
        switch self {
        case .submitting, .awaitingConfirmation, .confirmationDelayed:
            return true
        case .idle, .failed:
            return false
        }
    }

    var message: String? {
        switch self {
        case .idle, .submitting, .failed:
            return nil
        case .awaitingConfirmation:
            return "操作已提交，状态待确认。页面其他功能仍可使用。"
        case .confirmationDelayed:
            return "状态确认延迟，请稍后点击“重新确认状态”。请勿重复提交同一操作。"
        }
    }
}

private extension RunOrderStatus {
    func satisfiesVolunteerTransition(target: RunOrderStatus) -> Bool {
        if self == target { return true }
        switch target {
        case .pendingAccept:
            return [.driverEnRoute, .driverArrived, .inProgress, .completed].contains(self)
        case .driverEnRoute:
            return [.driverArrived, .inProgress, .completed].contains(self)
        case .driverArrived:
            return [.inProgress, .completed].contains(self)
        case .inProgress:
            return self == .completed
        case .rematching:
            return [.cancelled, .noVolunteer].contains(self)
        case .completed:
            return false
        case .pendingMatch, .cancelled, .noVolunteer:
            return false
        // 通话磨合不是志愿者的状态机动作（它由双方表态驱动），永远不会是这里的目标状态。
        case .pendingIntroCall:
            return false
        // 同理：确认出发的**目标**是 `.pendingAccept`，没有任何志愿者动作以这一态为目标。
        // （它是接单那一刻由后端按「距开跑多远」决定的，客户端不驱动。）
        case .scheduledConfirmed:
            return false
        // `.unknown` 只可能来自解码兜底，永远不会是志愿者操作的目标状态。
        case .unknown:
            return false
        }
    }
}

private func withVolunteerOrderActionDeadline<T: Sendable>(
    nanoseconds: UInt64,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    do {
        return try await HomeLoadCoordinator.run(
            timeout: TimeInterval(nanoseconds) / 1_000_000_000,
            operationName: "volunteer-order-transition",
            operation: operation
        )
    } catch HomeLoadCoordinatorError.timedOut {
        throw VolunteerOrderActionError.timedOut
    }
}

@MainActor
final class VolunteerOrderDetailViewModel: ObservableObject {
    @Published var order: OrderDetailResponse?
    @Published var isLoading = false
    @Published var isPerformingAction = false
    @Published var errorMessage: String?
    @Published var didCancelOrder = false
    /// 接单被后端 403 `VOLUNTEER_NOT_VERIFIED` 拒绝后，错误区要长出「去上传资质证书」入口。
    @Published var needsCertificateUpload = false
    @Published private(set) var transitionState: VolunteerOrderTransitionState = .idle

    private weak var appState: AppState?
    private var speechService: SpeechService?
    private var realtimeRefreshCancellable: AnyCancellable?
    private var realtimeStatusCancellable: AnyCancellable?
    private var confirmationTask: Task<Void, Never>?
    private let actionDeadlineNanoseconds: UInt64
    private let confirmationTimeout: TimeInterval
    private let orderLoadTimeout: TimeInterval

    init(
        actionDeadlineNanoseconds: UInt64 = 12_000_000_000,
        confirmationTimeout: TimeInterval = HomeLoadPolicy.defaultTimeout,
        orderLoadTimeout: TimeInterval = HomeLoadPolicy.defaultTimeout
    ) {
        self.actionDeadlineNanoseconds = actionDeadlineNanoseconds
        self.confirmationTimeout = max(0.05, confirmationTimeout)
        self.orderLoadTimeout = max(0.05, orderLoadTimeout)
    }

    var isTransitionPending: Bool { transitionState.blocksDuplicateSubmission }
    var transitionMessage: String? { transitionState.message }
    var canRetryTransitionConfirmation: Bool {
        if case .confirmationDelayed = transitionState { return true }
        return false
    }

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
        if realtimeRefreshCancellable == nil {
            realtimeRefreshCancellable = appState.realtimeCoordinator.$pendingOrderRefreshIDs
                .receive(on: DispatchQueue.main)
                .sink { [weak self] orderIDs in
                    guard let self, let orderID = self.order?.orderId, orderIDs.contains(orderID) else { return }
                    Task { await self.load(orderId: orderID) }
                }
        }
        if realtimeStatusCancellable == nil {
            realtimeStatusCancellable = appState.realtimeCoordinator.statusUpdatePublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] update in
                    guard let self,
                          let current = self.order,
                          current.orderId == update.orderId else { return }
                    self.apply(
                        current.replacingStatus(with: update.toStatus),
                        speakChanges: true
                    )
                    self.isLoading = false
                    self.errorMessage = nil
                }
        }
    }

    func load(orderId: Int64) async {
        guard let appState else { return }
        appState.realtimeCoordinator.registerActiveOrder(orderId)
        var refreshedAuthoritativeOrder = false
        defer {
            if refreshedAuthoritativeOrder {
                appState.realtimeCoordinator.completeOrderRefresh(orderId)
            } else {
                appState.realtimeCoordinator.failOrderRefresh(orderId)
            }
        }
        isLoading = order == nil
        errorMessage = nil

        do {
            let orders = appState.orders
            let requestToken = appState.realtimeCoordinator.beginOrderStatusRequest(orderID: orderId)
            let candidate: OrderDetailResponse = try await HomeLoadCoordinator.run(
                timeout: orderLoadTimeout,
                operationName: "volunteer-order-detail"
            ) {
                try await orders.orderDetail(orderId: orderId)
            }
            guard let loaded = appState.realtimeCoordinator.reconcileOrderDetail(
                candidate,
                requestToken: requestToken
            ) else {
                isLoading = false
                return
            }
            refreshedAuthoritativeOrder = true
            apply(loaded, speakChanges: false)
            isLoading = false
        } catch let error as APIError {
            isLoading = false
            if appState.handleAuthenticatedAPIError(error) {
                return
            }
            errorMessage = error.localizedMessage
            speechService?.speakError(error.localizedMessage)
        } catch {
            isLoading = false
            errorMessage = "订单加载失败，请重试"
            speechService?.speakError("订单加载失败，请重试")
        }
    }

    func accept(currentLocation: CLLocationCoordinate2D?, locationAuthorized: Bool) async {
        guard let order, let appState else { return }
        if let message = VolunteerOrderActionGuard.acceptBlockMessage(
            profile: appState.volunteerProfile,
            registrationStatus: appState.volunteerRegistrationStatus,
            locationAuthorized: locationAuthorized
        ) {
            errorMessage = message
            speechService?.speakError(message)
            return
        }
        VolunteerLocationReporter.reportIfNeeded(
            appState: appState,
            currentLocation: currentLocation,
            locationAuthorized: locationAuthorized
        )
        let orders = appState.orders
        let orderID = order.orderId
        await submitTransition(target: .pendingAccept, orderID: orderID, appState: appState) {
            try await orders.respond(orderId: orderID, action: .accept)
        }
    }

    func enRoute() async {
        guard let order, let appState else { return }
        let orders = appState.orders
        let orderID = order.orderId
        await submitTransition(target: .driverEnRoute, orderID: orderID, appState: appState) {
            try await orders.enRoute(orderId: orderID)
        }
    }

    func arrive() async {
        guard let order, let appState else { return }
        let orders = appState.orders
        let orderID = order.orderId
        await submitTransition(target: .driverArrived, orderID: orderID, appState: appState) {
            try await orders.arrived(orderId: orderID)
        }
    }

    func startService() async {
        guard let order, let appState else { return }
        guard order.status.canStartService else {
            let message = order.status.startServiceBlockedMessage
            errorMessage = message
            speechService?.speakError(message)
            return
        }
        let orders = appState.orders
        let orderID = order.orderId
        await submitTransition(target: .inProgress, orderID: orderID, appState: appState) {
            try await orders.startService(orderId: orderID)
        }
    }

    func cancel() async {
        guard let order, let appState else { return }
        let orders = appState.orders
        let orderID = order.orderId
        await submitTransition(target: .rematching, orderID: orderID, appState: appState) {
            try await orders.cancel(orderId: orderID)
        }
    }

    func retryTransitionConfirmation() {
        guard let order, let appState, let target = transitionState.targetStatus else { return }
        transitionState = .awaitingConfirmation(target: target)
        errorMessage = nil
        startTransitionConfirmation(orderID: order.orderId, target: target, appState: appState)
    }

    private func submitTransition(
        target: RunOrderStatus,
        orderID: Int64,
        appState: AppState,
        operation: @escaping @Sendable () async throws -> Void
    ) async {
        guard !isPerformingAction else { return }
        if transitionState.blocksDuplicateSubmission {
            guard transitionState.targetStatus != target else { return }
            let message = "上一项操作的状态尚未确认，请先重新确认状态。"
            errorMessage = message
            speechService?.speakError(message)
            return
        }
        confirmationTask?.cancel()
        confirmationTask = nil
        transitionState = .submitting(target: target)
        ClientFlowDiagnostics.record(event: "submitted", operation: "volunteer-detail-transition") // guard:allow legacy-status 诊断事件名，非订单状态
        isPerformingAction = true
        errorMessage = nil
        needsCertificateUpload = false
        defer { isPerformingAction = false }
        do {
            try await withVolunteerOrderActionDeadline(
                nanoseconds: actionDeadlineNanoseconds,
                operation: operation
            )
            transitionState = .awaitingConfirmation(target: target)
            ClientFlowDiagnostics.record(event: "awaiting_confirmation", operation: "volunteer-detail-transition")
            startTransitionConfirmation(orderID: orderID, target: target, appState: appState)
        } catch VolunteerOrderActionError.timedOut {
            markTransitionOutcomeUnknown(target: target, orderID: orderID, appState: appState)
        } catch let error as APIError {
            if appState.handleAuthenticatedAPIError(error) {
                transitionState = .failed(message: error.localizedMessage)
                return
            }
            switch error {
            case .networkError, .decodingError:
                markTransitionOutcomeUnknown(target: target, orderID: orderID, appState: appState)
            case .serverError, .rateLimited, .unknown, .invalidURL, .missingCredentials:
                transitionState = .failed(message: error.localizedMessage)
                // 403 VOLUNTEER_NOT_VERIFIED 的唯一解法是上传资质证书，错误区必须给出入口。
                needsCertificateUpload = error.errorCode == .volunteerNotApproved
                errorMessage = error.localizedMessage
                speechService?.speakError(error.localizedMessage)
            case .unauthorized:
                transitionState = .failed(message: error.localizedMessage)
            }
        } catch {
            markTransitionOutcomeUnknown(target: target, orderID: orderID, appState: appState)
        }
    }

    private func markTransitionOutcomeUnknown(
        target: RunOrderStatus,
        orderID: Int64,
        appState: AppState
    ) {
        transitionState = .awaitingConfirmation(target: target)
        speechService?.speakError("操作结果尚未确认，正在后台同步状态。请勿重复提交同一操作。")
        startTransitionConfirmation(orderID: orderID, target: target, appState: appState)
    }

    private func startTransitionConfirmation(
        orderID: Int64,
        target: RunOrderStatus,
        appState: AppState
    ) {
        confirmationTask?.cancel()
        let orders = appState.orders
        let requestToken = appState.realtimeCoordinator.beginOrderStatusRequest(orderID: orderID)
        confirmationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let candidate: OrderDetailResponse = try await HomeLoadCoordinator.run(
                    timeout: self.confirmationTimeout,
                    operationName: "volunteer-detail-transition-confirmation"
                ) {
                    try await orders.orderDetail(orderId: orderID)
                }
                guard !Task.isCancelled,
                      self.order?.orderId == orderID,
                      self.transitionState.targetStatus == target else { return }
                guard let updated = appState.realtimeCoordinator.reconcileOrderDetail(
                    candidate,
                    requestToken: requestToken
                ) else { return }
                self.apply(updated, speakChanges: true)
                if !updated.status.satisfiesVolunteerTransition(target: target) {
                    self.transitionState = .confirmationDelayed(target: target)
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled,
                      self.order?.orderId == orderID,
                      self.transitionState.targetStatus == target else { return }
                self.transitionState = .confirmationDelayed(target: target)
                ClientFlowDiagnostics.record(event: "confirmation_delayed", operation: "volunteer-detail-transition")
            }
            self.confirmationTask = nil
        }
    }

    private func apply(_ updated: OrderDetailResponse, speakChanges: Bool) {
        let previousStatus = order?.status
        order = updated
        appState?.liveEscortCoordinator.updateOwnedOrder(orderID: updated.orderId, status: updated.status)
        if speakChanges, previousStatus != updated.status {
            speechService?.speakStatusChange(updated.status)
        }
        if let target = transitionState.targetStatus,
           updated.status.satisfiesVolunteerTransition(target: target) {
            transitionState = .idle
            ClientFlowDiagnostics.record(event: "confirmed", operation: "volunteer-detail-transition")
            confirmationTask?.cancel()
            confirmationTask = nil
            errorMessage = nil
        }
        if updated.status == .rematching || updated.status == .cancelled {
            appState?.realtimeCoordinator.unregisterActiveOrder(updated.orderId)
            appState?.liveEscortCoordinator.clearOwnedOrder()
            didCancelOrder = true
            speechService?.speak("订单已取消，系统将为盲人重新匹配。")
        }
    }
}

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
                            .buttonStyle(.bordered)
                            .accessibilityHint("只重新查询订单状态，不会重复提交当前操作")
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
            locationService.requestPermission()
            locationService.startUpdating()
            await viewModel.load(orderId: orderId)
            if viewModel.order?.status == .completed {
                await trackViewModel.load(orderID: orderId, appState: appState)
            }
        }
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
            Text("确认接单后将显示盲人联系方式。")
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
            // `.scheduledConfirmed` 在列：跨天单的「确认我还会去」在服务页的动作条上
            // （`VolunteerServiceActions.actionKinds`），这里给的是通往它的第二条路 ——
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

// MARK: - In Service

@MainActor
final class VolunteerInServiceViewModel: ObservableObject {
    @Published var order: OrderDetailResponse?
    @Published var isLoading = false
    @Published var isPerformingAction = false
    @Published var errorMessage: String?
    @Published var dispatchSummary: VolunteerDispatchSummaryResponse?
    @Published var didCancelOrder = false
    @Published private(set) var latestBlindSample: LocatedCoordinate?
    /// 与盲人同步的里程 / 时长 / 配速。只在 `IN_PROGRESS` 有值。
    @Published private(set) var blindStats: TrackStats?
    @Published private(set) var transitionState: VolunteerOrderTransitionState = .idle
    @Published private(set) var isAcknowledgingEmergency = false

    // 陪跑员订单页 v2（交付包 02 ③④）。
    /// 跑者最近一次位置的精度（米），汇合页方位盘的扇形宽度用它。与 `latestBlindSample` 同生同灭。
    @Published private(set) var latestBlindAccuracyMeters: Double?
    /// 响铃到这一刻为止（后端 `ringingUntil`）。之前按钮不可点。
    @Published private(set) var ringingUntil: Date?
    /// 响铃 / 快捷消息那一下的结果：「对方可能没收到」或 429 的等待。
    @Published private(set) var nudgeNotice: String?
    /// 快捷消息的「已发送」冷却起点（对接说明：客户端按 type 冷却 60 秒，后端只按单限 3 条）。
    @Published private(set) var quickMessageSentAt: [QuickMessageCode: Date] = [:]
    /// 结束等待成功 ⇒ 宿主关页。**不进**「跑者已取消」那一屏：这一单是陪跑员等满后结束的。
    @Published private(set) var didEndWaiting = false
    static let quickMessageCooldown: TimeInterval = 60
    private var orderLiveUpdateCancellable: AnyCancellable?
    /// 结束等待的请求在路上。那期间收到的 `CANCELLED` 是它自己造成的，不播「跑者取消了」。
    private var isEndingWait = false

    /// 轨迹节流。订单每 5 秒轮一次，而三个数字没必要跟得那么紧 ——
    /// 与盲人端 `BlindOrderStatusViewModel.trackPollingInterval` 取同一个值，
    /// 两端刷新频率不同会让「他那边已经 3.2 公里，我这边还是 3.1」变成常态。
    static let trackPollingInterval: TimeInterval = 10
    private var lastTrackFetchAt: Date?

    private weak var appState: AppState?
    private var speechService: SpeechService?
    private var pollingTask: Task<Void, Never>?
    private var realtimeRefreshCancellable: AnyCancellable?
    private var realtimeStatusCancellable: AnyCancellable?
    private var peerLocationCancellable: AnyCancellable?
    private var confirmationTask: Task<Void, Never>?
    private var dispatchSummaryTask: Task<Void, Never>?
    private var peerExpiryTask: Task<Void, Never>?
    private var acceptsPeerLocations = true
    private let actionDeadlineNanoseconds: UInt64
    private let confirmationTimeout: TimeInterval
    private let orderLoadTimeout: TimeInterval
    private let peerFreshness: TimeInterval

    init(
        actionDeadlineNanoseconds: UInt64 = 12_000_000_000,
        confirmationTimeout: TimeInterval = HomeLoadPolicy.defaultTimeout,
        orderLoadTimeout: TimeInterval = HomeLoadPolicy.defaultTimeout,
        peerFreshness: TimeInterval = LiveEscortSessionCoordinator.peerFreshness
    ) {
        self.actionDeadlineNanoseconds = actionDeadlineNanoseconds
        self.confirmationTimeout = max(0.05, confirmationTimeout)
        self.orderLoadTimeout = max(0.05, orderLoadTimeout)
        self.peerFreshness = max(0.01, peerFreshness)
    }

    var isTransitionPending: Bool { transitionState.blocksDuplicateSubmission }
    var transitionMessage: String? { transitionState.message }
    var canRetryTransitionConfirmation: Bool {
        if case .confirmationDelayed = transitionState { return true }
        return false
    }

    func configure(with appState: AppState, speechService: SpeechService, initialOrder: OrderDetailResponse?) {
        self.appState = appState
        self.speechService = speechService
        acceptsPeerLocations = true
        if order == nil {
            order = initialOrder
        }
        if let order {
            appState.liveEscortCoordinator.updateOwnedOrder(orderID: order.orderId, status: order.status)
        }
        if realtimeRefreshCancellable == nil {
            realtimeRefreshCancellable = appState.realtimeCoordinator.$pendingOrderRefreshIDs
                .receive(on: DispatchQueue.main)
                .sink { [weak self] orderIDs in
                    guard let self, let orderID = self.order?.orderId, orderIDs.contains(orderID) else { return }
                    Task { await self.load(orderId: orderID, speakChanges: true) }
                }
        }
        if realtimeStatusCancellable == nil {
            realtimeStatusCancellable = appState.realtimeCoordinator.statusUpdatePublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] update in
                    guard let self,
                          let current = self.order,
                          current.orderId == update.orderId else { return }
                    self.apply(
                        current.replacingStatus(with: update.toStatus),
                        speakChanges: true
                    )
                    self.isLoading = false
                }
        }
        if peerLocationCancellable == nil {
            peerLocationCancellable = appState.realtimeCoordinator.peerLocationPublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] sample in
                    self?.handleBlindLocationUpdate(sample)
                }
        }
        // ETA / 汇合距离档位。不落通知日志，只就地合进手上这份订单，重连后以详情为准。
        if orderLiveUpdateCancellable == nil {
            orderLiveUpdateCancellable = appState.realtimeCoordinator.orderLiveUpdatePublisher
                .receive(on: DispatchQueue.main)
                .sink { [weak self] update in
                    guard let self, let current = self.order else { return }
                    self.order = current.merging(update)
                }
        }
    }

    func startPolling(orderId: Int64) {
        if order?.orderId != orderId {
            clearPeerLocation()
        }
        acceptsPeerLocations = true
        appState?.realtimeCoordinator.registerActiveOrder(orderId)
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
        confirmationTask?.cancel()
        confirmationTask = nil
        acceptsPeerLocations = false
        clearPeerLocation()
    }

    func load(orderId: Int64, speakChanges: Bool) async {
        guard let appState else { return }
        var refreshedAuthoritativeOrder = false
        defer {
            if refreshedAuthoritativeOrder {
                appState.realtimeCoordinator.completeOrderRefresh(orderId)
            } else {
                appState.realtimeCoordinator.failOrderRefresh(orderId)
            }
        }
        isLoading = order == nil
        do {
            let orders = appState.orders
            let requestToken = appState.realtimeCoordinator.beginOrderStatusRequest(orderID: orderId)
            let candidate: OrderDetailResponse = try await HomeLoadCoordinator.run(
                timeout: orderLoadTimeout,
                operationName: "volunteer-order-poll"
            ) {
                try await orders.orderDetail(orderId: orderId)
            }
            guard let loaded = appState.realtimeCoordinator.reconcileOrderDetail(
                candidate,
                requestToken: requestToken
            ) else {
                isLoading = false
                return
            }
            refreshedAuthoritativeOrder = true
            apply(loaded, speakChanges: speakChanges)
            isLoading = false
            await refreshBlindStatsIfNeeded(for: loaded, appState: appState)
        } catch {
            isLoading = false
            if order == nil {
                errorMessage = "获取订单状态失败"
            }
        }
    }

    /// 陪跑中那屏上跟盲人同步的三个数字。
    ///
    /// 走的是**和盲人端同一个端点** `GET /api/orders/{id}/track`，取的也是同一份
    /// `blindStats` —— 后端按订单参与方鉴权，志愿者读得到。两端各算一份的话，
    /// 「你俩看到的公里数不一样」会变成一个没人能复现的投诉。
    ///
    /// 🚩 **张梦蝶（2023）点名的助跑者痛点就是「无法了解视障跑者的状态」**，
    /// 而在此之前志愿者端这一态只有一张地图和几个流转按钮。
    ///
    /// 失败时**不清空已有数字、不播报**，理由与盲人端 `refreshTrackStatsIfNeeded` 逐字相同：
    /// 跑动中一次网络抖动把屏幕上的距离归零，比暂时不更新糟得多。
    private func refreshBlindStatsIfNeeded(for order: OrderDetailResponse, appState: AppState) async {
        guard order.status == .inProgress else {
            blindStats = nil
            lastTrackFetchAt = nil
            return
        }
        let now = Date()
        if let last = lastTrackFetchAt, now.timeIntervalSince(last) < Self.trackPollingInterval { return }
        lastTrackFetchAt = now
        do {
            blindStats = try await appState.safety.orderTrack(orderId: order.orderId).blindStats
        } catch {
            return
        }
    }

    func enRoute() async {
        guard let order, let appState else { return }
        let orders = appState.orders
        let orderID = order.orderId
        await submitTransition(target: .driverEnRoute, orderID: orderID, appState: appState) {
            try await orders.enRoute(orderId: orderID)
        }
    }

    func arrive() async {
        guard let order, let appState else { return }
        let orders = appState.orders
        let orderID = order.orderId
        await submitTransition(target: .driverArrived, orderID: orderID, appState: appState) {
            try await orders.arrived(orderId: orderID)
        }
    }

    /// 跨天预约单的临期确认：`SCHEDULED_CONFIRMED → PENDING_ACCEPT`。
    ///
    /// 走与其余流转动作**同一条** `submitTransition`，而不是自己写一遍 —— 那条路径自带
    /// 提交去重、「已提交待确认」态、超时后的「重新确认状态」。这个动作恰恰最需要它们：
    /// 提交成功但确认没回来时，志愿者会以为没点上而重复点，而重复点在 409 之后
    /// 看起来和「真的没确认成功」一模一样。
    ///
    /// 🚩 目标是 `.pendingAccept` 而不是 `.scheduledConfirmed`：确认之后订单就进即时链路了。
    /// 它与 `/en-route` **不是一回事**（那条会打开位置互推），别把两个动作合并。
    func confirmDeparture() async {
        guard let order, let appState else { return }
        let orders = appState.orders
        let orderID = order.orderId
        await submitTransition(
            target: .pendingAccept,
            orderID: orderID,
            appState: appState,
            // 不断言成因（转走了 / 盲人取消了 / 上一次其实已经成功），客户端分不出这三种。
            // 这句话对三种都为真，而且这条路径紧接着会 `load()` 刷新，屏幕自己会给出真相。
            statusConflictMessage: "这一单的状态已经变了，不用再确认。"
        ) {
            try await orders.confirmDeparture(orderId: orderID)
        }
    }

    // MARK: - 快捷消息 / 响铃 / 结束等待（交付包 02 ③④）

    /// 「我快到了」「再等我 5 分钟」。按 type 冷却 60 秒，冷却内按钮显示「已发送」。
    func sendQuickMessage(_ code: QuickMessageCode) async {
        guard let order, let appState else { return }
        if let sent = quickMessageSentAt[code], Date().timeIntervalSince(sent) < Self.quickMessageCooldown { return }
        do {
            let response = try await appState.orders.sendQuickMessage(code, orderId: order.orderId)
            quickMessageSentAt[code] = Date()
            reportNudge(delivered: response.delivered, success: "已告诉\(order.blindNameForSpeech)：\(code.title)")
        } catch {
            reportNudgeFailure(error, appState: appState)
        }
    }

    /// 让跑者的手机响起来。`ringingUntil` 之前按钮不可点（宿主按它置灰）。
    func ringRunner() async {
        guard let order, let appState else { return }
        if let ringingUntil, ringingUntil > Date() { return }
        do {
            let response = try await appState.orders.ringRunner(orderId: order.orderId)
            ringingUntil = response.ringingUntil?.backendTimestamp
            reportNudge(delivered: response.delivered, success: "\(order.blindNameForSpeech)的手机正在响")
        } catch {
            reportNudgeFailure(error, appState: appState)
        }
    }

    /// 等满时限后结束等待：订单转 `CANCELLED`（`cancelledBy=SYSTEM`），宿主直接关页。
    ///
    /// 🚩 **不走 `submitTransition`**：那条路径以「订单落到目标状态」为确认，而这里的目标
    /// `CANCELLED` 恰好也是「跑者取消」那一屏的入口 —— 走过去等于让陪跑员看到一句不属于他的话。
    func endWaiting() async {
        guard let order, let appState, !isPerformingAction else { return }
        isPerformingAction = true
        isEndingWait = true
        errorMessage = nil
        defer {
            isPerformingAction = false
            isEndingWait = false
        }
        do {
            try await appState.orders.endWaiting(orderId: order.orderId)
            appState.realtimeCoordinator.unregisterActiveOrder(order.orderId)
            appState.liveEscortCoordinator.clearOwnedOrder()
            stopPolling()
            speechService?.speak("已结束等待。这一单取消了，不算你的取消。")
            didEndWaiting = true
        } catch let error as APIError {
            if appState.handleAuthenticatedAPIError(error) { return }
            errorMessage = error.localizedMessage
            speechService?.speakError(error.localizedMessage)
            // 409 `END_WAIT_TOO_EARLY`：手上的 `earliestEndWaitAt` 过期了，刷一次让主按钮换回去。
            if case .serverError(let response) = error, response.errorCode == .endWaitTooEarly {
                await load(orderId: order.orderId, speakChanges: false)
            }
        } catch {
            errorMessage = "结束等待失败，请重试。"
            speechService?.speakError("结束等待失败，请重试。")
        }
    }

    private func reportNudge(delivered: Bool?, success: String) {
        guard delivered != false else {
            let message = "对方可能没收到，可以打电话。"
            nudgeNotice = message
            speechService?.speakError(message)
            return
        }
        nudgeNotice = nil
        HapticFeedback.play(.tick)
        speechService?.speak(success)
    }

    private func reportNudgeFailure(_ error: Error, appState: AppState) {
        let message: String
        switch error as? APIError {
        case .some(let apiError) where appState.handleAuthenticatedAPIError(apiError):
            return
        case .some(.rateLimited(let info)):
            message = info.retryAfterSeconds.map { "按得太频繁了，\($0) 秒后再试。" } ?? "按得太频繁了，请稍后再试。"
        case .some(let apiError):
            message = apiError.localizedMessage
        case .none:
            message = "没有发出去，请重试。"
        }
        nudgeNotice = message
        speechService?.speakError(message)
    }

    func handleBlindLocationUpdate(_ sample: RealtimePeerLocationSample) {
        guard acceptsPeerLocations,
              sample.ownerRole == .blind,
              sample.orderId == order?.orderId else { return }
        let capturedAt = Date(timeIntervalSince1970: TimeInterval(sample.timestampMilliseconds) / 1_000)
        let age = max(0, Date().timeIntervalSince(capturedAt))
        guard age <= peerFreshness,
              let located = BackendCoordinateNormalizer.backend(
                latitude: sample.latitude,
                longitude: sample.longitude,
                capturedAt: capturedAt
              ) else { return }

        latestBlindSample = located
        latestBlindAccuracyMeters = sample.accuracyMeters
        schedulePeerExpiry(for: located, orderID: sample.orderId, remaining: peerFreshness - age)
    }

    func startService() async {
        guard let order, let appState else { return }
        guard order.status.canStartService else {
            let message = order.status.startServiceBlockedMessage
            errorMessage = message
            speechService?.speakError(message)
            return
        }
        let orders = appState.orders
        let orderID = order.orderId
        await submitTransition(target: .inProgress, orderID: orderID, appState: appState) {
            try await orders.startService(orderId: orderID)
        }
    }

    func cancel() async {
        guard let order, let appState else { return }
        let orders = appState.orders
        let orderID = order.orderId
        await submitTransition(target: .rematching, orderID: orderID, appState: appState) {
            try await orders.cancel(orderId: orderID)
        }
    }

    /// 结束服务。**没有参数** —— 2026-09-16 之前这里收一个 `summary: String`，
    /// 由一张「服务总结」表单填，而 `POST /api/orders/{id}/finish` 根本没有请求体
    /// （`api_spec.yaml:2110-2129`），那段文字从来没离开过这台手机。
    /// 那张表单随长按结束一起删了，见 `VolunteerFinishLongPress`。
    func complete() async {
        guard let order, let appState else { return }
        guard order.status.canFinishService else {
            let message = order.status.finishBlockedMessage
            errorMessage = message
            speechService?.speakError(message)
            return
        }
        let orders = appState.orders
        let orderID = order.orderId
        await submitTransition(target: .completed, orderID: orderID, appState: appState) {
            try await orders.finish(orderId: orderID)
        }
    }

    func retryTransitionConfirmation() {
        guard let order, let appState, let target = transitionState.targetStatus else { return }
        transitionState = .awaitingConfirmation(target: target)
        errorMessage = nil
        startTransitionConfirmation(
            orderID: order.orderId,
            target: target,
            appState: appState
        )
    }

    // MARK: - 紧急求助（志愿者侧）

    /// 代被陪同的盲人发起求助。与盲人侧同一条路径、同一个 GPS 严格门槛（拿不到真实定位就不发），
    /// 区别只在后端把事件挂在订单的盲人身上、并用 `VOLUNTEER_BUTTON` 标注来源。
    func enterEmergency(
        locate: @escaping () async -> LocatedCoordinate?,
        locationFailureReason: @escaping () -> LocationError? = { nil }
    ) async {
        guard let order, let appState else { return }
        let outcome = await appState.emergencyCoordinator.trigger(
            order: order,
            role: appState.activeRole,
            userID: appState.userId,
            safety: appState.safety,
            locate: locate,
            locationFailureReason: locationFailureReason
        )
        if outcome.isFailure {
            speechService?.speakError(outcome.message)
        } else {
            speechService?.speak(outcome.message)
        }
    }

    /// 对被陪同者的求助回一句「确认需要帮助」。这是志愿者唯一能做的响应。
    func acknowledgeEmergency(eventID: Int64) async {
        guard let appState, !isAcknowledgingEmergency else { return }
        isAcknowledgingEmergency = true
        let succeeded = await appState.emergencyCoordinator.acknowledgeAsVolunteer(
            eventID: eventID,
            safety: appState.safety
        )
        isAcknowledgingEmergency = false
        if succeeded {
            speechService?.speak(EmergencySafetyCopy.volunteerAcknowledged)
        } else {
            let message = "确认失败，请重试。若情况危急请立即拨打110。"
            errorMessage = message
            speechService?.speakError(message)
        }
    }

    /// - Parameter statusConflictMessage: 409 `ORDER_STATUS_NOT_ALLOWED` 时替换掉那句通用文案。
    ///   加它是因为**同一个错误码在不同动作下要说的话不一样**：`ErrorCode.invalidOrderStatus`
    ///   在后端有 13 个抛出点，全局文案只能是「当前订单状态不允许此操作」，而
    ///   `confirm-departure` 的契约 description 明写这条 409 最常见的成因是
    ///   「闸门已经把这一单退回重新匹配了」，要告诉志愿者「这一单已经转走了」而不是「操作失败」——
    ///   后者会让他以为再点一次就好。默认 nil = 沿用全局文案，其余调用点行为不变。
    private func submitTransition(
        target: RunOrderStatus,
        orderID: Int64,
        appState: AppState,
        statusConflictMessage: String? = nil,
        operation: @escaping @Sendable () async throws -> Void
    ) async {
        guard !isPerformingAction else { return }
        if transitionState.blocksDuplicateSubmission {
            guard transitionState.targetStatus != target else { return }
            let message = "上一项操作的状态尚未确认，请先重新确认状态。"
            errorMessage = message
            speechService?.speakError(message)
            return
        }
        confirmationTask?.cancel()
        confirmationTask = nil
        transitionState = .submitting(target: target)
        ClientFlowDiagnostics.record(event: "submitted", operation: "volunteer-service-transition") // guard:allow legacy-status 诊断事件名，非订单状态
        isPerformingAction = true
        errorMessage = nil
        defer { isPerformingAction = false }
        do {
            try await withVolunteerOrderActionDeadline(
                nanoseconds: actionDeadlineNanoseconds,
                operation: operation
            )
            transitionState = .awaitingConfirmation(target: target)
            ClientFlowDiagnostics.record(event: "awaiting_confirmation", operation: "volunteer-service-transition")
            startTransitionConfirmation(orderID: orderID, target: target, appState: appState)
            simulateRealtimeConfirmationIfRequested(
                orderID: orderID,
                fromStatus: order?.status,
                target: target,
                appState: appState
            )
        } catch VolunteerOrderActionError.timedOut {
            markTransitionOutcomeUnknown(target: target, orderID: orderID, appState: appState)
        } catch let error as APIError {
            if appState.handleAuthenticatedAPIError(error) {
                transitionState = .failed(message: error.localizedMessage)
                return
            }
            switch error {
            case .networkError, .decodingError:
                markTransitionOutcomeUnknown(target: target, orderID: orderID, appState: appState)
            case .serverError(let response) where response.errorCode == .invalidOrderStatus
                && statusConflictMessage != nil:
                // 走到这里说明订单已经不在本次动作的前置状态上了。**同时刷新一次订单**：
                // 只播一句「已经转走了」而屏幕还停在旧状态，等于让志愿者对着一个已经不成立的界面。
                let message = statusConflictMessage ?? error.localizedMessage
                transitionState = .failed(message: message)
                errorMessage = message
                speechService?.speakError(message)
                await load(orderId: orderID, speakChanges: false)
            case .serverError, .rateLimited, .unknown, .invalidURL, .missingCredentials:
                transitionState = .failed(message: error.localizedMessage)
                errorMessage = error.localizedMessage
                speechService?.speakError(error.localizedMessage)
            case .unauthorized:
                transitionState = .failed(message: error.localizedMessage)
            }
        } catch {
            markTransitionOutcomeUnknown(target: target, orderID: orderID, appState: appState)
        }
    }

    private func simulateRealtimeConfirmationIfRequested(
        orderID: Int64,
        fromStatus: RunOrderStatus?,
        target: RunOrderStatus,
        appState: AppState
    ) {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["AIDRUN_UI_TEST_CONFIRM_TRANSITION_VIA_REALTIME"] == "1",
              let fromStatus else { return }
        Task { @MainActor in
            await Task.yield()
            appState.realtimeCoordinator.simulateIncomingEventForTesting(
                .orderStatusChanged(
                    WSOrderStatusChanged(
                        type: WSMessageType.orderStatusChanged.rawValue,
                        orderId: orderID,
                        fromStatus: fromStatus.rawValue,
                        toStatus: target.rawValue,
                        message: nil,
                        ttsText: nil,
                        priority: "NORMAL",
                        timestamp: nil
                    )
                )
            )
        }
        #endif
    }

    private func markTransitionOutcomeUnknown(
        target: RunOrderStatus,
        orderID: Int64,
        appState: AppState
    ) {
        transitionState = .awaitingConfirmation(target: target)
        let message = "操作结果尚未确认，正在后台同步状态。请勿重复提交同一操作。"
        errorMessage = nil
        speechService?.speakError(message)
        startTransitionConfirmation(orderID: orderID, target: target, appState: appState)
    }

    private func startTransitionConfirmation(
        orderID: Int64,
        target: RunOrderStatus,
        appState: AppState
    ) {
        confirmationTask?.cancel()
        let orders = appState.orders
        let requestToken = appState.realtimeCoordinator.beginOrderStatusRequest(orderID: orderID)
        confirmationTask = Task { [weak self] in
            guard let self else { return }
            do {
                let candidate: OrderDetailResponse = try await HomeLoadCoordinator.run(
                    timeout: self.confirmationTimeout,
                    operationName: "volunteer-transition-confirmation"
                ) {
                    try await orders.orderDetail(orderId: orderID)
                }
                guard !Task.isCancelled,
                      self.order?.orderId == orderID,
                      self.transitionState.targetStatus == target else { return }
                guard let updated = appState.realtimeCoordinator.reconcileOrderDetail(
                    candidate,
                    requestToken: requestToken
                ) else { return }
                self.apply(updated, speakChanges: true)
                if !updated.status.satisfiesVolunteerTransition(target: target) {
                    self.transitionState = .confirmationDelayed(target: target)
                    self.errorMessage = nil
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled,
                      self.order?.orderId == orderID,
                      self.transitionState.targetStatus == target else { return }
                self.transitionState = .confirmationDelayed(target: target)
                ClientFlowDiagnostics.record(event: "confirmation_delayed", operation: "volunteer-service-transition")
                self.errorMessage = nil
            }
            self.confirmationTask = nil
        }
    }

    private func apply(_ updated: OrderDetailResponse, speakChanges: Bool) {
        let previousStatus = order?.status
        order = updated
        appState?.liveEscortCoordinator.updateOwnedOrder(orderID: updated.orderId, status: updated.status)
        if speakChanges, previousStatus != updated.status {
            speechService?.speakStatusChange(updated.status)
        }
        if let target = transitionState.targetStatus,
           updated.status.satisfiesVolunteerTransition(target: target) {
            transitionState = .idle
            ClientFlowDiagnostics.record(event: "confirmed", operation: "volunteer-service-transition")
            confirmationTask?.cancel()
            confirmationTask = nil
            errorMessage = nil
        }
        if updated.status == .rematching {
            appState?.realtimeCoordinator.unregisterActiveOrder(updated.orderId)
            appState?.liveEscortCoordinator.clearOwnedOrder()
            stopPolling()
            didCancelOrder = true
            order = nil
            speechService?.speak("订单已取消，系统将为盲人重新匹配。")
            return
        }
        if updated.status.isTerminal {
            appState?.realtimeCoordinator.unregisterActiveOrder(updated.orderId)
            stopPolling()
            if updated.status == .completed, let appState {
                refreshDispatchSummary(using: appState)
            }
            if updated.status == .cancelled, !isEndingWait, !didEndWaiting {
                // 🔴 **`order` 留着，不再置 nil。** 此前这里一置 nil，两个渲染分支就都取不到
                // 订单 ⇒ 屏幕退化成一片空白背景，只播一句 TTS，志愿者得自己按返回才能离开。
                // 现在它落在骨架的「跑者已取消」那一屏（`cancelledByRunner`）。
                //
                // `didCancelOrder` 也**不在这里置位**：它的含义是「这一单是我自己退掉的，
                // 关页面吧」（`REMATCHING` 那条分支），而这一次是盲人取消的，
                // 要留在页面上把「不算你的取消」说清楚。
                speechService?.speak(
                    "\(VolunteerOrderFlowCopy.runnerCancelledTitle(name: updated.blindNameForSpeech))。"
                    + VolunteerOrderFlowCopy.runnerCancelledSubtitle
                )
            }
        }
    }

    private func schedulePeerExpiry(
        for sample: LocatedCoordinate,
        orderID: Int64,
        remaining: TimeInterval
    ) {
        peerExpiryTask?.cancel()
        peerExpiryTask = Task { [weak self] in
            do {
                try await Task.sleep(
                    nanoseconds: UInt64(max(0.01, remaining) * 1_000_000_000)
                )
            } catch {
                return
            }
            guard !Task.isCancelled,
                  let self,
                  self.order?.orderId == orderID,
                  self.latestBlindSample == sample else { return }
            self.clearPeerLocation()
        }
    }

    private func clearPeerLocation() {
        peerExpiryTask?.cancel()
        peerExpiryTask = nil
        latestBlindSample = nil
        latestBlindAccuracyMeters = nil
    }

    private func refreshDispatchSummary(using appState: AppState) {
        guard dispatchSummaryTask == nil else { return }
        let orders = appState.orders
        dispatchSummaryTask = Task { [weak self] in
            guard let self else { return }
            defer { self.dispatchSummaryTask = nil }
            do {
                let summary: VolunteerDispatchSummaryResponse = try await HomeLoadCoordinator.run(
                    timeout: self.orderLoadTimeout,
                    operationName: "volunteer-service-summary-refresh"
                ) {
                    try await orders.dispatchSummary()
                }
                guard !Task.isCancelled else { return }
                self.dispatchSummary = summary
                ClientFlowDiagnostics.record(event: "confirmed", operation: "volunteer-service-summary-refresh")
            } catch is CancellationError {
                return
            } catch {
                ClientFlowDiagnostics.record(event: "failed", operation: "volunteer-service-summary-refresh")
            }
        }
    }
}

struct VolunteerInServiceView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @EnvironmentObject private var locationService: LocationService
    @EnvironmentObject private var amapGeocodingService: AMapGeocodingService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @StateObject private var viewModel = VolunteerInServiceViewModel()
    @StateObject private var trackViewModel = CompletedTrackSummaryViewModel()
    @State private var showEmergencyConfirm = false
    @State private var showsRunRecord = false
    @State private var activeSheet: VolunteerSheet?
    @Environment(\.scenePhase) private var scenePhase
    /// 汇合页的朝向源，只在 `DRIVER_ARRIVED` 开着。
    @StateObject private var meetHeading = MeetHeadingProvider()
    /// 方位描述的滞回基准（上一次说的是哪个方位）。
    @State private var meetSector: DirectionSector?
    /// 上一次汇合提示（档位 + 方位）。只在它**变了**时播报，首次进入不播（状态播报已经在说）。
    @State private var lastMeetCue: MeetCue?
    @State private var lastMeetAnnouncementAt: Date?
    @State private var didBuzzWithin10 = false
    let orderId: Int64
    let initialOrder: OrderDetailResponse?

    private struct MeetCue: Equatable {
        let bucket: DistanceBucket
        let sector: DirectionSector?
    }

    init(orderId: Int64, initialOrder: OrderDetailResponse? = nil) {
        self.orderId = orderId
        self.initialOrder = initialOrder
    }

    /// 这一态走不走这个页面。`nil` = 还是旧的地图 + 底部面板那条路。
    ///
    /// 🚩 **现在只剩跑步中走旧路径**（深蓝三数字 + 长按 2 秒结束 + 导航栏右侧的求助，已拍板不动）。
    /// 邀请 / 约好 / 出发 / 汇合 / 已完成 / 跑者已取消都在骨架上。
    /// `VolunteerServiceBottomPanel` 与 `VolunteerServiceActions` 因此只剩跑步中一个调用方，
    /// 跑中页改造那一轮可以连它们一起删 —— **现在就删会让回退没有退路。**
    private var flowPresentation: VolunteerOrderFlowPresentation? {
        guard let order = viewModel.order else { return nil }
        return .make(
            order: order,
            distanceText: distanceText(for: order),
            peerDistanceText: peerDistanceText
        )
    }

    /// 本机到**跑者**的距离，汇合那一屏的 hero 就靠它。
    ///
    /// `nil` 的三种成因（没授权 / 没收到过 / 收到的已经过期）在这里**合成同一种**：
    /// 对陪跑员来说它们的后果一样 —— 现在不知道他在哪。过期由 view model 的
    /// `peerExpiryTask` 把 `latestBlindSample` 清掉（阈值 `LiveEscortSessionCoordinator.peerFreshness`），
    /// 所以这里不需要再判一次时间戳，**也不许判** —— 两处各有一个新鲜度阈值必然漂。
    private var peerDistanceText: String? {
        guard locationService.isAuthorized,
              let deviceCoordinate = locationService.currentLocation,
              let peer = viewModel.latestBlindSample else { return nil }
        let meters = DistanceCalculator.distanceFromDeviceToBackend(
            deviceCoordinate: deviceCoordinate,
            backendCoordinate: peer.coordinate
        )
        return DistanceCalculator.formattedDistance(meters)
    }

    var body: some View {
        Group {
            if let order = viewModel.order, flowPresentation != nil {
                // 每秒一拍：解锁时刻、结束等待时刻、「N 分钟后出发」都是 `(订单, 现在)` 的函数，不存。
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    flowPage(order: order, now: context.date)
                }
            } else {
                legacyMapContent
            }
        }
        .navigationTitle(flowPresentation == nil ? "服务中" : VolunteerOrderFlowCopy.pageTitle)
        .navigationBarTitleDisplayMode(.inline)
        // 旧路径藏导航栏的底，是为了让地图透上去。
        .toolbarBackground(.hidden, for: .navigationBar)
        // v2 页面自带导航栏（左返回、右求助），系统那条要整条藏掉，否则两条叠着。
        .toolbar(flowPresentation == nil ? .visible : .hidden, for: .navigationBar)
        // 跑步中（旧路径）的求助入口放在导航栏右侧：不占内容区，横竖屏都不会被底部那一叠盖住或挤掉（#217）。
        // v2 页面的求助胶囊在它自己的导航栏上，这里只管旧路径。
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if flowPresentation == nil, let order = viewModel.order, order.status.canVolunteerTriggerEmergency {
                    VolunteerSOSNavButton(coordinator: appState.emergencyCoordinator) {
                        showEmergencyConfirm = true
                    }
                }
            }
        }
        // 订单页**不带标签栏**（设计交付 v3 §4.2 总表：S1/S2/S3/S4 的底部是「标签栏」，
        // 而 S6 是「求助与安全」；`03-订单页全流程.png` 五屏也都没有标签栏）。
        // 多一条 49pt 的标签栏会把底部操作区顶上去，而标签栏在这一刻能去的地方
        // （记录 / 我的）没有一个是陪跑中该去的。**两条路径都要藏**：地图那条是面板被顶，
        // 骨架那条是最后一行被盖掉半行（同一个形状已在 `VolunteerServiceRecognitionView` 上红过一次）。
        //
        // 🔴 **前提是每一屏都有出口。** 盲人端的订单页刻意保留了标签栏，理由在
        // `BlindOrderStatusView.swift:1642-1646`：那一页跑步中会藏返回箭头，
        // 标签栏是唯一出口。这一页：旧路径有系统返回箭头；v2 页面藏了系统导航栏，
        // 出口是它自己导航栏上的返回，完成页没有返回、出口是主按钮「完成」（`.doneReviewing` → dismiss）。
        // **谁将来去掉其中任何一个出口，这一行必须同时撤销。**
        //
        // ⚠️ 2026-09-17 合并时搬过一次位置：它原本挂在旧 body 的末尾，而那一段被
        // 四步骨架重构删掉了。取任一边都会让这一行静默消失，所以是手动搬进来的。
        .toolbar(.hidden, for: .tabBar)
        .task {
            viewModel.configure(with: appState, speechService: speechService, initialOrder: initialOrder)
            locationService.startUpdating()
            viewModel.startPolling(orderId: orderId)
        }
        .onDisappear {
            viewModel.stopPolling()
            meetHeading.stop()
        }
        // 从后台回来时手上的 ETA / 档位可能已经过时（实时推送不落通知日志），重拉一次详情。
        .onChange(of: scenePhase) { phase in
            guard phase == .active else { return }
            Task { await viewModel.load(orderId: orderId, speakChanges: true) }
        }
        .task(id: viewModel.order?.status == .driverArrived) {
            if viewModel.order?.status == .driverArrived { meetHeading.start() } else { meetHeading.stop() }
        }
        .onChange(of: meetCue) { handleMeetCueChange($0) }
        .onChange(of: viewModel.didEndWaiting) { ended in
            if ended { dismiss() }
        }
        .task(id: viewModel.order?.status) {
            guard viewModel.order?.status == .completed else { return }
            await trackViewModel.load(orderID: orderId, appState: appState)
            if let summary = trackViewModel.track?.spokenSummary { speechService.speak(summary) }
        }
        // `.volunteer`：他按下去之后撤销不了（后端恒 403），文案要把这一半后果说出来。
        .emergencyConfirmationAlert(isPresented: $showEmergencyConfirm, audience: .volunteer) {
            Task {
                await viewModel.enterEmergency(
                    locate: { locationService.latestBackendSample() },
                    locationFailureReason: { locationService.locationError }
                )
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .navigation(let request):
                ExternalMapNavigationSheet(request: request)
            case .cannotFindRunner:
                VolunteerCannotFindRunnerSheet(
                    canCall: dialableRunnerPhone != nil,
                    onCall: { callRunner() },
                    ticket: { supportTicketSheet }
                )
                .presentationDetents([.medium, .large])
            case .supportTicket:
                supportTicketSheet
            case .cancelOrder:
                VolunteerCancelSheet(
                    copy: cancelSheetCopy,
                    isSubmitting: viewModel.isPerformingAction,
                    onKeep: { activeSheet = nil },
                    onCancelOrder: {
                        Task {
                            await viewModel.cancel()
                            activeSheet = nil
                            if viewModel.didCancelOrder { dismiss() }
                        }
                    }
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
        }
        // 「查看跑步记录」。已完成那一屏只留一行入口，轨迹本身推到下一页 ——
        // 设计交付文档 v3 的已完成屏是「结果 + 两个去处」，不是把轨迹图直接铺在上面。
        .navigationDestination(isPresented: $showsRunRecord) {
            completedTrackContent
                .navigationTitle(VolunteerOrderFlowCopy.viewRunRecord)
                .navigationBarTitleDisplayMode(.inline)
        }
        // 屏 5：被陪同者发起求助时盖满整屏 + 警报音 + 震动。
        //
        // 在此之前它只是底部面板上方一条和其他提示长得一样的横幅（`emergencySection`），
        // 而那一刻志愿者多半正看着地图导航、或者根本没在看屏幕。
        // 那条横幅**保留**：确认之后它仍然承载求助结果文案（`AGENTS.md` §6 要求每一种结果
        // 都可见可听），只是不再独自承担「叫住志愿者」这件事。
        .volunteerEmergencyAlertCover(
            coordinator: appState.emergencyCoordinator,
            peerName: viewModel.order?.blindName,
            peerPhone: viewModel.order?.blindPhone,
            deviceCoordinate: locationService.currentLocation,
            isAcknowledging: viewModel.isAcknowledgingEmergency,
            reverseGeocode: { await amapGeocodingService.reverseGeocode(coordinate: $0)?.title },
            serverAddress: { try? await appState.safety.orderLocationAddress(orderId: $0) },
            onAcknowledge: { eventID in
                Task { await viewModel.acknowledgeEmergency(eventID: eventID) }
            }
        )
    }

    // MARK: - 四步骨架（邀请 / 约好 / 出发）

    @ViewBuilder
    private func flowPage(order: OrderDetailResponse, now: Date) -> some View {
        let distance = distanceText(for: order)
        if let presentation = VolunteerOrderFlowPresentation.make(
            order: order,
            distanceText: distance,
            peerDistanceText: peerDistanceText,
            now: now
        ), let phase = VolunteerOrderPhase.resolve(order: order, now: now) {
            let direction = meetDirection(order: order, phase: phase)
            let meet = meetPanel(order: order, phase: phase, direction: direction, now: now)
            VolunteerOrderFlowPage(
                presentation: presentation,
                hero: .make(order: order, phase: phase, now: now, direction: direction?.sector.text, distanceText: distance),
                order: order,
                phase: phase,
                meet: meet,
                quickReplies: quickReplies(order: order, phase: phase, now: now),
                // 完成页没有返回：出口是主按钮「完成」。
                onBack: phase == .completed ? nil : { dismiss() },
                onRowAction: { handleFlowRowAction($0, order: order) },
                onPrimaryAction: { performFlowPrimaryAction(presentation.primaryAction) },
                // 只可能是 `IN_PROGRESS`（`VolunteerOrderSOSMode.resolve`），其余状态页面自己弹本地拨号。
                onCloudHelp: { showEmergencyConfirm = true },
                // POST 回来了但确认那条 GET 还挂着的那几秒里，同一次流转不许被提交第二次。
                isPrimaryLoading: viewModel.isPerformingAction,
                isPrimaryEnabled: !viewModel.isTransitionPending,
                // 汇合页的响铃结果挂在响铃按钮下，其余页挂在页脚。
                footer: { flowFooter(showsNudgeNotice: meet == nil) }
            )
        } else {
            legacyMapContent
        }
    }

    /// 汇合页的方位。只在 `DRIVER_ARRIVED`、有定位授权时算。
    private func meetDirection(order: OrderDetailResponse, phase: VolunteerOrderPhase) -> MeetDirection? {
        guard case .arrived = phase, locationService.isAuthorized else { return nil }
        return .make(
            device: locationService.currentLocation,
            runner: viewModel.latestBlindSample,
            runnerAccuracyMeters: viewModel.latestBlindAccuracyMeters,
            heading: meetHeading.heading,
            bucket: order.meet?.distanceBucket ?? .unknown,
            previous: meetSector
        )
    }

    private func meetPanel(
        order: OrderDetailResponse,
        phase: VolunteerOrderPhase,
        direction: MeetDirection?,
        now: Date
    ) -> VolunteerOrderMeetPanel? {
        guard case .arrived(let canEndWait) = phase else { return nil }
        return VolunteerOrderMeetPanel(
            runnerName: order.blindName?.nilIfBlank ?? VolunteerOrderFlowCopy.unknownRunnerName,
            runnerNameSpoken: order.blindNameForSpeech,
            relativeDegrees: direction?.relativeDegrees,
            sectorWidth: direction?.sectorWidth ?? DirectionDialGeometry.minimumSector,
            canEndWait: canEndWait,
            endWaitRemainingSeconds: order.earliestEndWaitAt?.backendTimestamp.map {
                max(0, Int($0.timeIntervalSince(now).rounded(.up)))
            },
            isRinging: (viewModel.ringingUntil ?? .distantPast) > now,
            ringNotice: viewModel.nudgeNotice,
            onRing: { Task { await viewModel.ringRunner() } }
        )
    }

    /// 快捷回复只在出发中显示（汇合页的动作是响铃和打电话）。
    private func quickReplies(
        order: OrderDetailResponse,
        phase: VolunteerOrderPhase,
        now: Date
    ) -> VolunteerOrderQuickReplies? {
        guard case .departed = phase else { return nil }
        let codes: [QuickMessageCode] = [.almostThere, .waitFiveMinutes]
        return VolunteerOrderQuickReplies(
            runnerName: order.blindName?.nilIfBlank ?? VolunteerOrderFlowCopy.unknownRunnerName,
            items: codes.map { code in
                let sent = viewModel.quickMessageSentAt[code].map {
                    now.timeIntervalSince($0) < VolunteerInServiceViewModel.quickMessageCooldown
                } ?? false
                return .init(id: code.rawValue, title: code.title, isSent: sent, isEnabled: !sent)
            },
            onTap: { id in
                guard let code = QuickMessageCode(rawValue: id) else { return }
                Task { await viewModel.sendQuickMessage(code) }
            }
        )
    }

    /// 汇合提示（档位 + 方位）。`nil` = 不在汇合页。
    private var meetCue: MeetCue? {
        guard let order = viewModel.order, order.status == .driverArrived else { return nil }
        return MeetCue(
            bucket: order.meet?.distanceBucket ?? .unknown,
            sector: meetDirection(order: order, phase: .arrived(canEndWait: false))?.sector
        )
    }

    /// 交付包 03 §三：只在方位描述或档位变化时播报，两次至少隔 3 秒；首次进 `WITHIN_10` 轻震一次。
    private func handleMeetCueChange(_ cue: MeetCue?) {
        let previous = lastMeetCue
        lastMeetCue = cue
        meetSector = cue?.sector
        guard let cue, let order = viewModel.order else { return }
        if cue.bucket == .within10, !didBuzzWithin10 {
            didBuzzWithin10 = true
            HapticFeedback.play(.tick)
        }
        // 刚进汇合页那一下由状态播报说，这里不抢。
        guard previous != nil else { return }
        let now = Date()
        if let last = lastMeetAnnouncementAt, now.timeIntervalSince(last) < MeetDirection.announcementInterval { return }
        lastMeetAnnouncementAt = now
        let copy = MeetBucketCopy.make(bucket: cue.bucket, farKm: order.meet?.farDistanceKm, direction: cue.sector?.text)
        UIAccessibility.post(
            notification: .announcement,
            argument: "\(copy.title(order.blindNameForSpeech))，\(copy.subtitle)"
        )
    }

    private func handleFlowRowAction(
        _ action: VolunteerOrderFlowPresentation.Action,
        order: OrderDetailResponse
    ) {
        switch action {
        case .openMeetingPoint:
            openExternalNavigation(for: order)
        case .callRunner:
            callRunner()
        case .releaseOrder:
            activeSheet = .cancelOrder
        case .cannotFindRunner:
            activeSheet = .cannotFindRunner
        case .viewRunRecord:
            showsRunRecord = true
        case .reportIssue:
            activeSheet = .supportTicket
        case .declineInvite:
            // 这一行只在邀请态出现，而邀请态不走这个页面（它没有 `OrderDetailResponse`）。
            // 留一个显式分支而不是 `default`：加 `Action` 时编译器会逼一次决策。
            break
        }
    }

    /// 号码只在这里出现一次，且只进 `tel:`。掩码串会被 `telURL` 的掩码闸拦掉
    /// （不拦则拼成 `tel://1381001`，一个可能真打给别人的号码）。
    private func callRunner() {
        guard let url = dialableRunnerPhone else { return }
        EmergencyDialer.dial(url, open: { openURL($0) })
    }

    /// `nil` = 这一单没有能拨通的号码 ⇒ 任何拨号入口都不该出现。
    private var dialableRunnerPhone: URL? {
        guard let phone = viewModel.order?.blindPhone?.nilIfBlank else { return nil }
        return EmergencyDialer.telURL(for: phone)
    }

    /// 两处入口共用同一份装配（已完成页的「上报问题」、汇合页「找不到对方」里的那一枚）。
    private var supportTicketSheet: some View {
        SupportTicketView(
            orderID: viewModel.order?.orderId,
            appState: appState,
            speak: { speechService.speak($0) },
            speakError: { speechService.speakError($0) }
        )
    }

    private func performFlowPrimaryAction(_ action: VolunteerOrderFlowPresentation.PrimaryAction?) {
        switch action {
        case .confirmDeparture:
            Task { await viewModel.confirmDeparture() }
        // 「我已经出发了」（解锁前的白色次要按钮）与「我出发了」发的是同一个动作。
        case .enRoute, .alreadyDeparted:
            HapticFeedback.play(.medium)
            Task { await viewModel.enRoute() }
        case .arrived:
            HapticFeedback.play(.medium)
            Task { await viewModel.arrive() }
        case .endWaiting:
            Task { await viewModel.endWaiting() }
        case .startRun:
            // 「开始跑步」两端都能按，服务端以先到的为准 —— 客户端不判谁先。
            // 成功之后这一页自己就落回旧的跑中页（`flowPresentation` 对 `IN_PROGRESS` 判 nil）。
            Task { await viewModel.startService() }
        // 这两枚按钮只是关掉当前页，不发任何请求。
        case .doneReviewing, .backToHome:
            dismiss()
        // 接单发生在派单弹层 / 邀请页上，那条路没有订单详情，不经过这里。
        case .acceptInvite, .none:
            break
        }
    }

    /// 骨架那一页的**可见**失败面。
    ///
    /// 旧面板把 `errorMessage` / `transitionMessage` 夹在信息区和按钮之间；骨架里它挂在
    /// 信息卡之后、底部操作条之前，位置对应。**少了它，「接单失败」「状态没确认上」
    /// 只剩一句 TTS**，不开读屏的低视力志愿者屏幕上零变化。
    @ViewBuilder
    private func flowFooter(showsNudgeNotice: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsNudgeNotice, let notice = viewModel.nudgeNotice {
                Text(notice)
                    .flowFont(FlowFonts.rowValue())
                    .foregroundColor(AppColors.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .flowFont(FlowFonts.rowValue())
                    .foregroundColor(AppColors.destructive)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(errorMessage)
            }
            if let transitionMessage = viewModel.transitionMessage {
                Label(transitionMessage, systemImage: "clock.arrow.circlepath")
                    .flowFont(FlowFonts.rowValue())
                    .foregroundColor(AppColors.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(transitionMessage)
                if viewModel.canRetryTransitionConfirmation {
                    FlowActionButton("重新确认状态", style: .ghost) {
                        viewModel.retryTransitionConfirmation()
                    }
                    .accessibilityHint("只重新查询订单状态，不会重复提交当前操作")
                }
            }
        }
    }

    private func openExternalNavigation(for order: OrderDetailResponse) {
        if let request = externalNavigationRequest(
            for: order,
            currentLocation: locationService.currentLocation,
            locationAuthorized: locationService.isAuthorized
        ) {
            activeSheet = .navigation(request)
        } else {
            let message = "不支持导航，等待后端补齐坐标"
            viewModel.errorMessage = message
            speechService.speakError(message)
        }
    }

    // MARK: - 旧路径（只剩跑步中，以及订单还没拉到的那一瞬）

    private var legacyMapContent: some View {
        GeometryReader { proxy in
            let bottomPanelMaxHeight = proxy.size.height * 0.62
            let mapAnchor = CGPoint(
                x: 0.5,
                y: VolunteerServiceMapLayout.screenAnchorY(
                    viewportHeight: proxy.size.height,
                    topSafeAreaInset: proxy.safeAreaInsets.top,
                    bottomPanelMaxHeight: bottomPanelMaxHeight
                )
            )
            ZStack(alignment: .bottom) {
                if let order = viewModel.order {
                    VolunteerServiceMapBackdrop(
                        order: order,
                        screenAnchor: mapAnchor,
                        peerSample: viewModel.latestBlindSample
                    )
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

                // 求助入口不在这一层：它在系统导航栏右侧（`body` 的 `.toolbar`，#217）。
                // 以前它是这个 ZStack 里的一层悬浮圆盾，被后来加进底部那一叠的三数字卡整个盖住过。

                // 已完成不再走这里 —— 它现在是骨架上的一屏，轨迹由「查看跑步记录」
                // 推到下一页（`completedTrackContent` 仍然是那一页的内容）。
                if let order = viewModel.order {
                    VStack(spacing: 10) {
                            // 屏 4：与盲人同步的三个数字 + 他的状态 / 位置共享。
                            // 只在 `IN_PROGRESS` —— 其余状态那三个数字要么还没开始、要么已经结束，
                            // 而一张写着 `--` 的卡片只会占掉本来该给流转按钮的空间。
                            if order.status == .inProgress {
                                VolunteerEscortStatsCard(
                                    coordinator: appState.emergencyCoordinator,
                                    peerName: order.blindName,
                                    stats: viewModel.blindStats,
                                    isPeerLocationFresh: viewModel.latestBlindSample != nil
                                )
                            }
                            emergencySection(for: order)
                            VolunteerServiceBottomPanel(
                            order: order,
                            distanceText: distanceText(for: order),
                            errorMessage: viewModel.errorMessage,
                            transitionMessage: viewModel.transitionMessage,
                            isPerformingAction: viewModel.isPerformingAction,
                            transitionsDisabled: viewModel.isTransitionPending,
                            canRetryTransitionConfirmation: viewModel.canRetryTransitionConfirmation,
                            maxHeight: bottomPanelMaxHeight,
                            onNavigate: { openExternalNavigation(for: order) },
                            onEnRoute: { Task { await viewModel.enRoute() } },
                            onArrive: { Task { await viewModel.arrive() } },
                            onStartService: { Task { await viewModel.startService() } },
                            onCancel: { activeSheet = .cancelOrder },
                            // 按满 2 秒直接结束，中间没有确认框：长按本身就是那道确认
                            // （设计包 `状态清单.md` §11：「结束跑步即结束服务，不可撤销 —— 因此不做轻点」）。
                            onComplete: { Task { await viewModel.complete() } },
                            onConfirmDeparture: { Task { await viewModel.confirmDeparture() } },
                            onRetryTransitionConfirmation: {
                                viewModel.retryTransitionConfirmation()
                            },
                            )
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                }
            }
        }
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
    private var cancelSheetCopy: VolunteerOrderFlowCopy.CancelSheetCopy {
        VolunteerOrderFlowCopy.cancelSheet(
            for: viewModel.order?.status,
            plannedStart: viewModel.order?.plannedStart?.nilIfBlank?.backendTimestamp
        )
    }

    /// 面板上方那条紧急信息区。**「代盲人发起求助」的按钮不在这里** —— 它是导航栏右侧的
    /// `VolunteerSOSNavButton`（见 `body` 的 `.toolbar`，2026-09-26 从地图右上角的悬浮圆盾挪过去，#217）。
    ///
    /// 2026-08-19 把触发按钮搬走：它此前是这个 `VStack` 的第一个子视图，而这个 `VStack` 底部对齐、
    /// 上方就是高度自适应的 `VolunteerServiceBottomPanel`，于是一个全宽红色 `PrimaryButton` 浮在屏幕
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
    /// 两者都不成立时这个 section 渲染为空，面板直接贴底 —— 那正是绝大多数时刻的样子。
    @ViewBuilder
    private func emergencySection(for order: OrderDetailResponse) -> some View {
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
                .accessibilityHint("确认被陪同者确实需要帮助，客服会介入")
            }

            if order.status.canVolunteerTriggerEmergency, let message = coordinator.state.message {
                EmergencyStatusNotice(message: message, isFailure: coordinator.state.isFailure)
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

    @ViewBuilder
    private var completedTrackContent: some View {
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

                    Button("重复当前状态") {
                        speechService.speak("服务已完成。\(message)")
                    }
                    .buttonStyle(.borderedProminent)
                    .frame(minHeight: 64)
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

// MARK: - Service Recognition

/// 志愿者服务成就页。**取代了此前的「积分商城」占位页。**
///
/// 那一页的积分数字写死 `--`，4 个商品（运动腰包 / 水壶 / 毛巾 / 腰灯）硬编码在数组里
/// 全标「敬请期待」，`VolunteerPointsViewModel` 只有一个从不被赋值的 `errorMessage`。
/// 一个永远兑换不了的商城比没有激励更伤：它每次都在提醒志愿者，平台承诺过什么、
/// 又没有兑现 —— 调研里「没有实质的表彰」正是激励设计的首要陷阱
/// （`docs/research/live-trip-sharing-and-volunteer-incentives-20260813.md` §2）。
///
/// 现在页面上的**每个数字都来自后端真有的字段**：`totalCompleted` / `totalServiceMinutes` /
/// `avgRating` / `badges`，志愿者可以自己核对。此前那版还有一套**客户端自己编的**五档称号
/// （熟练 / 资深 / 金牌 / 荣誉陪跑员，阈值 1/10/25/50/100 单），后端没有这些名字 ——
/// 一页上并排放两套勋章体系，比少一套更让人看不懂自己到底拿到了什么。已随本次改版删除。
///
/// 🔴 **国标星级与平台勋章分两栏，不合并。** 平台最高的时长勋章是 50 小时，
/// 而国标一星要 100 小时（GB/T 40143—2021）。合并展示会让志愿者以为拿了最高勋章就能评星，
/// 去学校申报时才发现一星都评不上。理由与阈值见 `VolunteerStarLevel`。
///
/// 页面数据来自 `GET /api/volunteer/achievements`，**不再由首页的 `dispatchSummary` 喂**。
/// 后端刻意把它和 dispatch-summary 分开：`totalServiceMinutes` 要扫该志愿者的全部已完成订单，
/// 而 dispatch-summary 是首页、每次打开都调，不该让低频页面的代价压在最热的端点上
/// （`api_spec.yaml` 那条 description）。所以这一页有自己的一次加载。
///
/// 并发只用 async/await：一个 `.task`，没有 `AnyCancellable`（AGENTS.md 硬约束）。
@MainActor
final class VolunteerAchievementsViewModel: ObservableObject {
    @Published private(set) var achievements: VolunteerAchievementsResponse?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading = true

    private weak var appState: AppState?

    /// ⚠️ `appState` 是 `weak`：传临时对象等于传 nil，用例要自己持有它。
    func configure(appState: AppState) {
        self.appState = appState
    }

    /// 拉服务成就。**失败一定要留下东西**：`errorMessage` 驱动 `errorSection`
    /// （一行原因 + 一个「重新加载」）。这段原来住在 view body 里，
    /// 三个 `@State` 之间没有任何测试面。
    func load() async {
        guard let appState else {
            isLoading = false
            errorMessage = "暂时没能读到服务成就，请稍后重试。"
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            // 成就属于激励片（`IncentiveService`），不是订单片 —— 两片并行开发时
            // 各自实现了一遍 `GET /api/volunteer/achievements`，合并时以先落 main 的激励片为准。
            achievements = try await appState.incentive.volunteerAchievements()
            errorMessage = nil
        } catch let error as APIError {
            errorMessage = error.localizedMessage
        } catch {
            errorMessage = "暂时没能读到服务成就，请稍后重试。"
        }
    }
}

struct VolunteerServiceRecognitionView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = VolunteerAchievementsViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let achievements = viewModel.achievements {
                    header(achievements)
                    statsRow(achievements)
                    starSection(achievements.resolvedStarLevel)
                    badgeSection(achievements)
                    disclaimer
                } else if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("正在加载服务成就")
                } else {
                    errorSection
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            // 内层 `.infinity` 保留左对齐，外层把这条左对齐的列收进可读宽度并居中。
            .readableContentColumn()
        }
        .background(AppColors.background)
        .navigationTitle(VolunteerAchievementsCopy.navigationTitle)
        // 🔴 **这一行是修出来的，不是抄体例。** 2026-09-17 给志愿者端加标签栏之后，
        // `testVolunteerAchievementsPassesAccessibilityAudit` 当场红在
        // `volunteerAchievementsDisclaimer` 上（Contrast failed），失败截图里那句
        // 「向学校或单位申报星级需要通过全国志愿服务信息系统办理」**第二行被标签栏盖掉了半行**。
        //
        // 光靠给内容加底部留白救不回来：`ScrollView` 静止在顶部时那一行的 y 只由它上面的内容决定，
        // 加多少 padding 它都还在 775.7–806，而标签栏（iOS 26 的悬浮胶囊）从 793 起 ——
        // 唯一的解法是这一页不要那条栏。
        //
        // 设计交付 v3 也是这么分的：§4.2 总表里带标签栏的只有 S1/S2/S3/S4 那几屏根页面，
        // S7「空闲时间与出发地」那类二级页的底部是空的。
        .toolbar(.hidden, for: .tabBar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("volunteerServiceRecognitionView")
        .task {
            viewModel.configure(appState: appState)
            await viewModel.load()
        }
    }

    private func header(_ response: VolunteerAchievementsResponse) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // 🔴 **不要写回 `.font(.system(size: 48, weight: .bold))`。**
            // 固定磅值不跟 Dynamic Type 走 —— 这一页最大的那个数字，恰恰是低视力用户
            // 最需要放大的东西。旧版就是这么写的，而当时志愿者端**一条无障碍审计都没有**，
            // 所以没人发现。`testVolunteerAchievementsPassesAccessibilityAudit` 现在钉住它。
            Text("\(response.completedCount)")
                .font(AppFonts.largeTitle())
                .foregroundColor(AppColors.textPrimary)
            Text("已完成的陪跑服务")
                .font(AppFonts.body())
                .foregroundColor(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(AppColors.secondaryBackground)
        .cornerRadius(12)
        // 合成一个焦点：两行是同一件事的两种说法，分开念会让读屏用户听两遍同一个数。
        .accessibilityElement(children: .combine)
        .accessibilityLabel(VolunteerAchievementsCopy.summarySpeech(response))
        .accessibilityIdentifier("volunteerServiceRecognitionHeader")
    }

    /// 累计服务时长与评分都是后端真值，如实展示；没有评价时显示 `--` 而不是编一个数。
    private func statsRow(_ response: VolunteerAchievementsResponse) -> some View {
        HStack(spacing: 12) {
            statTile("累计服务", "\(max(0, response.totalServiceMinutes ?? 0) / 60) 小时")
            statTile(
                "评分",
                response.avgRating.map { String(format: "%.1f", $0) } ?? "--",
                // 视觉上的 `--` 念出来是「评分：破折号破折号」。审计把这条判为
                // `Label not human-readable`，而它确实不可读 —— 屏幕上的占位符号
                // 从来不是给耳朵用的。
                spoken: response.avgRating.map { "评分 \(String(format: "%.1f", $0))" } ?? "还没有收到评价"
            )
        }
    }

    private func statTile(_ title: String, _ value: String, spoken: String? = nil) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(AppFonts.title())
                .foregroundColor(AppColors.textPrimary)
            Text(title)
                .font(AppFonts.caption())
                .foregroundColor(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(AppColors.secondaryBackground)
        .cornerRadius(12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spoken ?? "\(title)：\(value)")
    }

    /// 国标星级栏。**与平台勋章分开的两栏，不合并** —— 平台最高的时长勋章是 50 小时，
    /// 够不着一星的 100 小时。合并展示会让志愿者以为拿了最高勋章就能去学校评星，
    /// 到申报时才发现一星都评不上。
    private func starSection(_ level: VolunteerStarLevelDto) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(VolunteerAchievementsCopy.starSectionTitle)
                .font(AppFonts.caption())
                .foregroundColor(AppColors.textSecondary)
            Text(VolunteerAchievementsCopy.starSectionStandard)
                .font(AppFonts.caption())
                .foregroundColor(AppColors.textSecondary)
            Text(VolunteerAchievementsCopy.starTitle(current: max(0, level.current ?? 0)))
                .font(AppFonts.title())
                .foregroundColor(AppColors.textPrimary)

            // 进度条对 VoiceOver 是空的，所以下面那行文字不是装饰 —— 它是这一栏
            // 唯一能被读出来的进度信息。两者顺序不能倒，也不能只留进度条。
            ProgressView(value: starProgress(level))
                .tint(AppColors.primary)
                .accessibilityHidden(true)

            Text(VolunteerAchievementsCopy.starProgressText(level))
                .font(AppFonts.body())
                .foregroundColor(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(AppColors.secondaryBackground)
        .cornerRadius(12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(VolunteerAchievementsCopy.starAccessibilityLabel(level))
        .accessibilityIdentifier("volunteerStarLevelSection")
    }

    private func starProgress(_ level: VolunteerStarLevelDto) -> Double {
        guard let nextTarget = level.nextTarget, nextTarget > 0 else { return 1 }
        let hours = Double(max(0, level.currentHours ?? 0))
        return min(1, hours / Double(nextTarget))
    }

    private func badgeSection(_ response: VolunteerAchievementsResponse) -> some View {
        let badges = response.unlockedBadges
        return VStack(alignment: .leading, spacing: 12) {
            Text(VolunteerAchievementsCopy.badgeSectionTitle)
                .font(AppFonts.title())
                .foregroundColor(AppColors.textPrimary)
                .accessibilityAddTraits(.isHeader)

            if badges.isEmpty {
                Text(VolunteerAchievementsCopy.badgeSectionEmpty)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                // 主页只露 4 枚，其余收二级页：全铺开会变成一片图标噪音，
                // 前几枚的意义随之被稀释（抄 Strava 的做法）。
                ForEach(VolunteerBadgeWall.preview(badges)) { badge in
                    badgeRow(badge)
                }
                if VolunteerBadgeWall.hasMore(badges) {
                    NavigationLink {
                        VolunteerBadgeWallView(badges: badges)
                    } label: {
                        Text(VolunteerBadgeWall.moreLinkTitle(badges))
                            .font(AppFonts.body())
                            .foregroundColor(AppColors.primary)
                    }
                    .accessibilityIdentifier("volunteerBadgeWallLink")
                }
            }

            // `nextBadge` 是后端 SPEC-D D1 的新增字段，尚未发布。没有它就整段不显示 ——
            // 不拿客户端阈值表编一个进度（理由见 `VolunteerStarLevel` 顶部）。
            if let next = response.nextBadge {
                nextBadgeRow(next)
            }
        }
    }

    private func badgeRow(_ badge: VolunteerBadgeDto) -> some View {
        HStack(spacing: 14) {
            // 图标 + 名称共同区分勋章，**颜色不是唯一指示**（WCAG 1.4.1）。
            Image(systemName: badge.symbolName)
                .font(.title2)
                .frame(width: 36)
                .foregroundColor(AppColors.primary)

            Text(badge.displayName)
                .font(AppFonts.body().weight(.semibold))
                .foregroundColor(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            Text("已解锁")
                .font(AppFonts.caption().weight(.semibold))
                .foregroundColor(AppColors.success)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.secondaryBackground)
        .cornerRadius(12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(VolunteerAchievementsCopy.badgeAccessibilityLabel(badge))
    }

    private func nextBadgeRow(_ next: VolunteerNextBadgeDto) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(VolunteerAchievementsCopy.nextBadgeSectionTitle)
                .font(AppFonts.caption())
                .foregroundColor(AppColors.textSecondary)
            Text(next.displayName)
                .font(AppFonts.body().weight(.semibold))
                .foregroundColor(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let fraction = next.progressFraction, let progressText = next.progressText {
                ProgressView(value: fraction)
                    .tint(AppColors.primary)
                    .accessibilityHidden(true)
                Text(progressText)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textPrimary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(AppColors.secondaryBackground)
        .cornerRadius(12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(VolunteerAchievementsCopy.nextBadgeAccessibilityLabel(next))
        .accessibilityIdentifier("volunteerNextBadgeSection")
    }

    private var disclaimer: some View {
        Text(VolunteerAchievementsCopy.disclaimer)
            .font(AppFonts.caption())
            .foregroundColor(AppColors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("volunteerAchievementsDisclaimer")
    }

    private var errorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(viewModel.errorMessage ?? "暂时没能读到服务成就。")
                .font(AppFonts.body())
                .foregroundColor(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Button("重新加载") {
                Task { await viewModel.load() }
            }
            .font(AppFonts.body().weight(.semibold))
            .foregroundColor(AppColors.primary)
            .accessibilityIdentifier("volunteerAchievementsRetryButton")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 勋章二级页：解锁超过 4 枚时从成就页 push 进来，这里才铺全部。
struct VolunteerBadgeWallView: View {
    let badges: [VolunteerBadgeDto]

    var body: some View {
        List(badges) { badge in
            HStack(spacing: 14) {
                Image(systemName: badge.symbolName)
                    .font(.title2)
                    .frame(width: 36)
                    .foregroundColor(AppColors.primary)
                Text(badge.displayName)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(VolunteerAchievementsCopy.badgeAccessibilityLabel(badge))
        }
        .navigationTitle(VolunteerAchievementsCopy.badgeSectionTitle)
        .accessibilityIdentifier("volunteerBadgeWallView")
    }
}

// MARK: - Settings

struct VolunteerSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @StateObject private var deletionViewModel = AccountDeletionViewModel()
    @State private var showLogoutConfirm = false
    @State private var showDeletionInitialConfirmation = false

    var body: some View {
        List {
            Section {
                settingsRow("昵称", value: appState.volunteerProfile?.name ?? "未填写")
                settingsRow("当前角色", value: "志愿者")
                settingsRow("资质审核", value: certificateState.displayName)

                // 空闲时间是**匹配前提**而不是普通偏好：空闲时间以外后端不发邀请，
                // 所以「我为什么收不到单」的第一个答案就在这里。放第一组，与资质并列。
                NavigationLink("空闲时间") {
                    VolunteerAvailabilityScheduleView()
                }
                .accessibilityLabel("空闲时间")
                .accessibilityHint("设置你每周哪些时间有空，这些时间之外不会给你发邀请")
                .accessibilityIdentifier("volunteerScheduleSettingsEntry")
            }

            // SPEC-E 激励体系的三个入口。
            //
            // 🔴 「我的积分」刻意**不放进「服务成就」页**：积分与志愿服务时长必须是两个数、
            // 两处文案，一次都不能混（中央网信办 2026-06-19 通知第 2 条）。放同一屏最容易混，
            // 所以在信息架构层就隔开，两屏之间用一句话互相指路。
            //
            // 也刻意不加进首页底部那条三格入口栏：那是一条固定横排，第 4 格在 AX5 下必然挤压，
            // 而挤压的表现正是本仓库已经发生过的「指标格截断成 …」。
            Section {
                NavigationLink("我的积分") {
                    VolunteerPointsView()
                }
                .accessibilityLabel("我的积分")
                .accessibilityHint("查看积分余额和每一笔的加分原因")
                .accessibilityIdentifier("volunteerPointsSettingsEntry")

                NavigationLink("固定搭档") {
                    VolunteerPartnersView()
                }
                .accessibilityLabel("固定搭档")
                .accessibilityHint("查看哪些跑者把你设为固定搭档，以及你们连续一起跑步的周数")
                .accessibilityIdentifier("volunteerPartnersSettingsEntry")

                NavigationLink("我的邀请码") {
                    InviteCodeView()
                }
                .accessibilityLabel("我的邀请码")
                .accessibilityHint("查看你的邀请码和已经邀请的人数")
                .accessibilityIdentifier("volunteerInviteCodeSettingsEntry")

                // 陪跑培训（后端迁移 0043）。
                //
                // 🚩 这里是**常驻**入口，而不是培训的唯一入口 —— 首页作业区在
                // `TRAINING_INCOMPLETE` 时另给一张整卡可点的大入口
                // （`VolunteerProfileFirstScreen.trainingEntry`）。两个都要有：
                // 首页那张解决「为什么我接不到单」，这里解决「我想复习/做选修」。
                // 只留首页那张的话，培训完之后入口就消失了，选修课再也找不到 ——
                // 所以 `VolunteerProfileCopy.settingsHint` 必须把「培训」列进齿轮的读屏提示。
                NavigationLink("陪跑培训") {
                    VolunteerTrainingView()
                }
                .accessibilityLabel("陪跑培训")
                .accessibilityHint("学习必修与选修课程，完成必修后才能接单")
                .accessibilityIdentifier("volunteerTrainingSettingsEntry")
            }

            Section {
                NavigationLink("个人资料") {
                    VolunteerProfileView()
                }
                .accessibilityLabel("个人资料")
                .accessibilityHint("编辑志愿者资料")

                NavigationLink("资质证书") {
                    VolunteerCertificateUploadView()
                }
                .accessibilityLabel("资质证书，\(certificateState.displayName)")
                .accessibilityHint(certificateState.guidanceMessage)
                .accessibilityIdentifier("volunteerCertificateSettingsEntry")

                #if DEBUG
                if AppBuildChannel.current.allowsEnvironmentSwitcher {
                    Picker("API 环境", selection: $appState.currentEnvironment) {
                        ForEach(AppState.debugTestEnvironments, id: \.self) { environment in
                            Text(environment.displayName).tag(environment)
                        }
                    }
                    .accessibilityLabel("API 环境，\(appState.currentEnvironment.displayName)")
                }
                #endif

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

                Button("删除账户", role: .destructive) {
                    showDeletionInitialConfirmation = true
                }
                .disabled(appState.accountDeletionState == .inProgress)
                .accessibilityLabel("删除账户")
                .accessibilityHint("永久停用当前账户，需要再次确认")
            }

        }
        .navigationTitle("设置")
        .alert("无法删除账户", isPresented: $deletionViewModel.isShowingPreflightBlock) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(deletionViewModel.preflightMessage ?? "")
        }
        .alert("确认退出", isPresented: $showLogoutConfirm) {
            Button("确认退出", role: .destructive) {
                Task { await appState.logout() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("确认后将清除当前登录状态，返回登录页。")
        }
        .alert("确认删除账户", isPresented: $showDeletionInitialConfirmation) {
            Button("继续删除账户", role: .destructive) {
                Task {
                    await deletionViewModel.preflight(
                        appState: appState,
                        speechService: speechService
                    )
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("系统将先检查是否存在进行中的服务。检查通过后仍需再次确认，才会提交账户删除请求。")
        }
        .alert("最终确认删除账户", isPresented: $deletionViewModel.showFinalConfirmation) {
            Button("永久删除账户", role: .destructive) {
                Task { await appState.deleteCurrentAccount() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(AccountDeletionViewModel.finalConfirmationMessage(for: .volunteer))
        }
    }

    /// 资料里的 `verificationStatus` 是后端 `VerificationStatus` 的四个取值之一；
    /// 尚未拉取到时按「状态未知」展示，不假装已提交或已通过。
    private var certificateState: VolunteerCertificateDisplayState {
        VolunteerCertificateDisplayState.from(
            status: VolunteerCertificateStatus.parse(appState.volunteerProfile?.verificationStatus),
            statusLoadFailed: false
        )
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

/// 盲人端与志愿者端共用。法律条款入口放在这里，两个角色的设置页各挂一次「关于」即可覆盖。
struct AboutAidRunView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        List {
            Section {
                Text("助盲跑 MVP")
                Text("iOS SwiftUI Demo")
                    .foregroundColor(AppColors.textSecondary)
            }

            // 地图左下角那行读屏是隐藏的，这里给一份能念的（后端 issue #382）。
            if let approvalNumber = AMapManager.mapContentApprovalNumber() {
                Section {
                    LabeledContent("地图审图号", value: approvalNumber)
                        .accessibilityIdentifier("aboutMapApprovalNumber")
                }
            }

            LegalDocumentsSection(links: appState.legalLinks)
        }
        .navigationTitle("关于")
        // 进页面才拉，不在启动时打这个请求：它只影响这一页，而且失败了也有回退文案。
        .task { await appState.loadLegalLinksIfNeeded() }
    }
}

// MARK: - Reusable Views

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
            .accessibilityLabel("地图，出发地点：\(order.startAddress ?? "地址待同步")")
            .accessibilityHint("地图用于视觉确认出发点；订单信息区域会读出地址和距离")
        }
    }
}

struct VolunteerServiceMapBackdrop: View {
    @EnvironmentObject private var locationService: LocationService
    let order: OrderDetailResponse
    let screenAnchor: CGPoint
    let peerSample: LocatedCoordinate?

    var body: some View {
        let presentation = VolunteerServiceMapPresentation(
            order: order,
            currentLocation: locationService.currentLocation,
            locationAuthorized: locationService.isAuthorized,
            fallbackCoordinate: locationService.effectiveBackendLocation,
            includesCurrentLocationMarker: false,
            centersOnCurrentAndStart: false
        )
        let peerAnnotations = peerSample.map { sample in
            [MapAnnotationItem(
                id: "associated-blind-runner",
                coordinate: sample.coordinate,
                title: "同行盲人跑者",
                subtitle: "位置刚刚更新",
                kind: .peer
            )]
        } ?? []
        MapViewWrapper(
            centerCoordinate: presentation.centerCoordinate,
            showsUserLocation: locationService.isAuthorized,
            annotations: presentation.annotations + peerAnnotations,
            zoomLevel: 15,
            screenAnchor: screenAnchor,
            tracksUserLocation: false,
            animatesCenterChanges: false
        )
        .ignoresSafeArea()
        .overlay(alignment: .topLeading) {
            VolunteerMapLegend(
                showsCurrentLocation: presentation.isCurrentLocationAvailable,
                showsMissingLocationNotice: !presentation.isCurrentLocationAvailable
            )
            .padding(.top, 56)
            .padding(.horizontal, 16)
        }
        .overlay(alignment: .bottom) {
            LinearGradient(
                colors: [.clear, Color.black.opacity(0.12)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 260)
            .allowsHitTesting(false)
        }
        .allowsHitTesting(false)
        .accessibilityLabel(
            presentation.isCurrentLocationAvailable
                ? "地图，显示我的位置和出发地点：\(order.startAddress ?? "地址待同步")"
                : "地图，出发地点：\(order.startAddress ?? "地址待同步")"
        )
        .accessibilityIdentifier("volunteerServiceMapBackdrop")
        .accessibilityHint("服务信息面板会读出出发地点和距离；同行位置过期后会自动隐藏")
    }
}

struct VolunteerMapLegend: View {
    let showsCurrentLocation: Bool
    let showsMissingLocationNotice: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsCurrentLocation {
                legendRow(color: .blue, title: "我的位置")
            } else if showsMissingLocationNotice {
                Text("定位不可用，仅显示出发地点")
                    .font(AppFonts.caption().weight(.semibold))
                    .foregroundColor(AppColors.warning)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityLabel("定位不可用，仅显示出发地点")
            }

            legendRow(color: .red, title: "出发地点")
        }
        .accessibilityElement(children: .contain)
    }

    private func legendRow(color: Color, title: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)
                .accessibilityHidden(true)
            Text(title)
                .font(AppFonts.caption().weight(.semibold))
                .foregroundColor(AppColors.textPrimary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityLabel(title)
    }
}

struct ExternalMapNavigationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let request: ExternalMapNavigationRequest

    private var providers: [ExternalMapNavigationProvider] {
        ExternalMapNavigationAvailability.availableProviders()
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(providers) { provider in
                        Button {
                            ExternalMapNavigationLauncher.open(provider: provider, request: request)
                            dismiss()
                        } label: {
                            Label(provider.displayName, systemImage: provider.systemImageName)
                                .font(AppFonts.body().weight(.semibold))
                        }
                        .accessibilityLabel("使用\(provider.displayName)导航到出发地点")
                        .accessibilityHint("打开外部地图进行步行导航")
                    }
                } footer: {
                    Text("默认使用步行导航。未安装的第三方地图不会显示。")
                }
            }
            .navigationTitle("选择地图导航")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct VolunteerServiceBottomPanel: View {
    let order: OrderDetailResponse
    let distanceText: String?
    let errorMessage: String?
    let transitionMessage: String?
    let isPerformingAction: Bool
    let transitionsDisabled: Bool
    let canRetryTransitionConfirmation: Bool
    let maxHeight: CGFloat
    let onNavigate: () -> Void
    let onEnRoute: () -> Void
    let onArrive: () -> Void
    let onStartService: () -> Void
    let onCancel: () -> Void
    let onComplete: () -> Void
    let onConfirmDeparture: () -> Void
    let onRetryTransitionConfirmation: () -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                VolunteerServiceStageHeader(status: order.status)
                // 排在跑者卡（姓名 + 电话）之前：先知道「这个人需要我怎么带」，
                // 再知道「他叫什么、怎么联系」。
                VolunteerRunnerNeedsBanner(order: order)
                VolunteerServiceRunnerCard(order: order)
                VolunteerServiceOrderEssentials(order: order, distanceText: distanceText)

                if let errorMessage {
                    Text(errorMessage)
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.destructive)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel(errorMessage)
                }

                if let transitionMessage {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(transitionMessage, systemImage: "clock.arrow.circlepath")
                            .font(AppFonts.body())
                            .foregroundColor(AppColors.warning)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityLabel(transitionMessage)
                        if canRetryTransitionConfirmation {
                            Button("重新确认状态", action: onRetryTransitionConfirmation)
                                .buttonStyle(.bordered)
                                .accessibilityHint("只重新查询订单状态，不会重复提交当前操作")
                        }
                    }
                }

                VolunteerServiceActions(
                    status: order.status,
                    isPerformingAction: isPerformingAction,
                    transitionsDisabled: transitionsDisabled,
                    onNavigate: onNavigate,
                    onEnRoute: onEnRoute,
                    onArrive: onArrive,
                    onStartService: onStartService,
                    onCancel: onCancel,
                    onComplete: onComplete,
                    onConfirmDeparture: onConfirmDeparture,
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
        .accessibilityIdentifier("volunteerServicePanel")
    }
}

struct VolunteerServiceStageHeader: View {
    @ScaledMetric(relativeTo: .largeTitle) private var stageTitleSize: CGFloat = 34
    let status: RunOrderStatus

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: status.statusSymbolName)
                    .foregroundColor(status.statusColor)
                    .accessibilityHidden(true)
                Text(status.volunteerServiceDisplayName)
                    .font(AppFonts.caption().weight(.semibold))
                    .foregroundColor(status.statusColor)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(status.statusColor.opacity(0.12))
            .cornerRadius(999)

            Text(status.serviceStageTitle)
                // 写死 34pt 不跟 Dynamic Type 走。下面的 `minimumScaleFactor(0.72)` 只在
                // 空间不够时**缩小**，永远不会放大 —— 两者方向相反，不能互相替代。
                .font(.system(size: stageTitleSize, weight: .bold))
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
        .accessibilityLabel("\(status.volunteerServiceDisplayName)，\(status.serviceStageTitle)，\(status.serviceStageSubtitle)")
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
                    if let url = EmergencyDialer.telURL(for: phone) {
                        EmergencyDialer.dial(url, open: { openURL($0) })
                    }
                } label: {
                    Label(
                        EmergencyContactResponse.maskPhone(phone) ?? phone,
                        systemImage: "phone.fill"
                    )
                        .labelStyle(.titleAndIcon)
                        .font(AppFonts.body().weight(.semibold))
                        .foregroundColor(AppColors.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
                .accessibilityLabel("拨打盲人电话")
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

/// 服务中面板的订单要点。**只被 `VolunteerServiceBottomPanel` 用**，那是接单之后的界面，
/// 所以这里的自由文本（路线备注 / 特殊说明）不加闸。
/// 要在接单前的界面复用它，先接 `RunOrderStatus.disclosesBlindRunnerNotesToVolunteer`。
/// 「本单为视障跑者」提示位。
///
/// 对标打车软件给司机弹的「此订单乘客为视障人士」：那条提示的价值不在于告知身份，
/// 而在于**改变司机接下来的动作**（下车接、口头引导、别按喇叭催）。这里同理，
/// 真正有用的是 `引导方式` 那一行 —— 递牵引绳 / 让对方挽手臂 / 只用口令是三种完全不同的做法。
///
/// 刻意**不做可折叠**：折叠等于把它降级成「想看再看」，而这几行正是志愿者见面前
/// 唯一必须先知道的东西。内容为空时整块不渲染（判定在 `OrderDetailResponse.escortNeeds`），
/// 所以「不可跳过」不会变成「每单都有一块空卡片」。
struct VolunteerRunnerNeedsBanner: View {
    private let needs: [EscortNeed]

    init(order: OrderDetailResponse) {
        self.needs = order.escortNeeds
    }

    /// 接单前的入口（通话磨合页）。那一刻拿不到 `OrderDetailResponse` ——
    /// 后端 `OrderQueryService.getOrder` 只认 `order.volunteer`，通话期它恒为 null → 403。
    /// 所以内容由派单载荷 `WSNewOrder.escortNeeds` 直接给（只剩导盲犬那一行）。
    init(needs: [EscortNeed]) {
        self.needs = needs
    }

    var body: some View {
        if !needs.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("本单为视障跑者", systemImage: "figure.walk.motion")
                    .font(AppFonts.body().weight(.bold))
                    .foregroundColor(AppColors.primary)

                ForEach(needs) { need in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: need.symbolName)
                            .font(AppFonts.caption().weight(.semibold))
                            .foregroundColor(AppColors.primary)
                            .frame(width: 20)
                            .accessibilityHidden(true)
                        Text("\(need.title)：\(need.value)")
                            .font(AppFonts.body())
                            .foregroundColor(AppColors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.primary.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(AppColors.primary.opacity(0.35), lineWidth: 1)
            )
            // 合成一个焦点，且朗读文本写死：逐行分开会让读屏用户滑过其中一条而不自知，
            // 而这几行的意义恰恰在于「一条都不能漏」。
            .accessibilityElement(children: .combine)
            .accessibilityLabel(needs.escortNeedsAnnouncement)
            .accessibilityIdentifier("volunteerRunnerNeedsBanner")
        }
    }
}

struct VolunteerServiceOrderEssentials: View {
    let order: OrderDetailResponse
    let distanceText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            serviceRow(systemImage: "mappin.and.ellipse", title: "出发地点", value: order.startAddress ?? "")
            if let endAddress = order.endAddressForDisplay {
                serviceRow(systemImage: "flag.checkered", title: "结束地点", value: endAddress)
            }
            serviceRow(systemImage: "clock", title: "预约时间", value: (order.plannedStart ?? "").displayDateTime)
            // 志愿者也要看得到约定的结束时间：超过它 15 分钟后端就推 `ORDER_OVERDUE`，
            // 而志愿者侧那条是 HIGH 优先级、会走 APNs。收到告警却不知道约定的是几点，
            // 那条推送就只是一次惊吓。
            if let plannedEnd = order.plannedEndForAnnouncement {
                serviceRow(systemImage: "clock.badge.checkmark", title: "预计结束时间", value: plannedEnd)
            }

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

enum VolunteerServiceActionKind: Hashable {
    case navigateToStart
    case markEnRoute
    case markArrived
    case startService
    case cancelOrder
    /// 跨天预约单的临期确认（`POST /api/orders/{id}/confirm-departure`）。
    case confirmDeparture
    /// 跨天预约单的「我去不了」。**动作与 `.cancelOrder` 完全相同**（同一个取消端点、同样转
    /// `REMATCHING`），单独一个 case 只为换文案。
    ///
    /// 换文案不是修饰：对志愿者，「取消订单」读起来像是在替盲人取消这一单，而实际后果是
    /// 「这一单回到派单池换个人」。这个差别在预约态下尤其要紧 —— 他要在几天前做这个决定，
    /// 而**确认与释放必须并置且同样好按**（对标志愿者排班软件的 confirm-or-release：
    /// 释放做得难，只会把 no-show 从「提前告知」变成「当天失联」，
    /// 见 `docs/research/volunteer-scheduled-order-confirm-ui-20260906.md` §二.1）。
    case releaseScheduled
    case completeService
    case completedMessage
    case terminalMessage

    var title: String {
        switch self {
        case .navigateToStart:
            return "导航到出发地点"
        case .confirmDeparture:
            return "确认我还会去"
        case .releaseScheduled:
            return "我去不了"
        case .markEnRoute:
            return "我已出发"
        case .markArrived:
            return "我已到达约定地点"
        case .startService:
            return "开始服务"
        case .cancelOrder:
            return "取消订单"
        case .completeService:
            // 设计包（`状态清单.md` §10 / §11）把这枚按钮定名「结束陪跑」，与读屏那条
            // 自定义动作同名。**两处必须是同一个词**：按钮上印一个、读屏念另一个，
            // 用户会以为自己找到的是别的东西。文案本身在 `VolunteerFinishLongPress.title`。
            return VolunteerFinishLongPress.title
        case .completedMessage:
            // 不再说「获得 +100 积分」：后端没有积分字段，那个数字是编的。
            // 但也不能只剩「服务完成」——这是志愿者跑完一趟唯一的正反馈，
            // 把承诺删掉不该连同反馈一起删掉。一句感谢不涉及任何数字，零成本且是真的。
            return "服务完成，感谢你的陪伴"
        case .terminalMessage:
            return "订单已结束"
        }
    }
}

struct VolunteerServiceActions: View {
    let status: RunOrderStatus
    let isPerformingAction: Bool
    let transitionsDisabled: Bool
    let onNavigate: () -> Void
    let onEnRoute: () -> Void
    let onArrive: () -> Void
    let onStartService: () -> Void
    let onCancel: () -> Void
    let onComplete: () -> Void
    let onConfirmDeparture: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            ForEach(Self.actionKinds(for: status), id: \.self) { action in
                actionView(action)
            }
        }
    }

    static func actionKinds(for status: RunOrderStatus) -> [VolunteerServiceActionKind] {
        switch status {
        // 跨天预约：确认与释放并置，**不给导航** —— 距开跑 1–7 天，导航到出发地点是纯噪音，
        // 而且它会和「确认我还会去」抢同一块视觉重量。
        //
        // 🚩 确认按钮在**整个** `SCHEDULED_CONFIRMED` 都给，不按「距开跑 X 分钟」开闸。
        // 那个 X 是后端配置（`departure-confirm-window-minutes`），客户端算它就是第二个源；
        // 后端调大它的那一天，通知到了而按钮还没出现 —— 那正是这次要防的事故。
        // 代价是志愿者可能提前几天就确认掉，闸门的临期复查失效；两相比较这个代价小得多。
        case .scheduledConfirmed:
            return [.confirmDeparture, .releaseScheduled]
        case .pendingAccept:
            return [.navigateToStart, .markEnRoute, .cancelOrder]
        case .driverEnRoute:
            return [.navigateToStart, .markArrived, .cancelOrder]
        case .driverArrived:
            return [.startService, .cancelOrder]
        case .inProgress:
            return [.completeService, .cancelOrder]
        case .completed:
            return [.completedMessage]
        case .cancelled, .noVolunteer:
            return [.terminalMessage]
        case .pendingMatch, .rematching:
            return []
        // 通话磨合期的三个动作（合适 / 不合适 / 没接到电话）在 `VolunteerIntroCallView` 上，
        // 走的是通话专用接口而不是订单状态流转端点，所以这条服务流程的动作条一个都不给。
        case .pendingIntroCall:
            return []
        // 认不出状态就一个按钮都不给：宁可让志愿者刷新，也不能在未知状态上放出取消/结束这类不可逆操作。
        case .unknown:
            return []
        }
    }

    @ViewBuilder
    private func actionView(_ action: VolunteerServiceActionKind) -> some View {
        switch action {
        case .navigateToStart:
            navigationButton(action: onNavigate)
        case .markEnRoute:
            PrimaryButton(action.title, isLoading: isPerformingAction, action: onEnRoute)
                .disabled(transitionsDisabled)
                .accessibilityLabel(action.title)
                .accessibilityHint("点击后通知盲人您正在前往")
        case .markArrived:
            PrimaryButton(action.title, isLoading: isPerformingAction, action: onArrive)
                .disabled(transitionsDisabled)
                .accessibilityLabel(action.title)
                .accessibilityHint("点击后通知盲人您已到达")
        case .startService:
            PrimaryButton(action.title, isLoading: isPerformingAction, action: onStartService)
                .disabled(transitionsDisabled)
                .accessibilityLabel(action.title)
                .accessibilityHint("点击后通知盲人服务已开始")
        case .confirmDeparture:
            PrimaryButton(action.title, isLoading: isPerformingAction, action: onConfirmDeparture)
                .disabled(transitionsDisabled)
                .accessibilityLabel(action.title)
                .accessibilityHint("告诉跑者你仍然会来。不确认这一单会转给其他志愿者")
        case .releaseScheduled:
            // 与确认同一组，走取消端点。**用 `secondaryDangerButton` 而不是再来一个主按钮**：
            // 并置不等于同等强调 —— 释放要好按（一跳、不藏进菜单），但不该和确认抢第一焦点。
            secondaryDangerButton(action.title, hint: "这一单会转给其他志愿者，需要确认后释放", action: onCancel)
        case .cancelOrder:
            secondaryDangerButton(action.title, hint: "取消当前订单", action: onCancel)
        case .completeService:
            // 唯一一个不是 `PrimaryButton` 的流转动作：它要长按 2 秒 + 环形进度 + 松手即取消。
            // 为什么没有轻点、为什么不复用求助那条长按，见 `VolunteerFinishLongPress`。
            VolunteerFinishLongPressButton(
                isPerformingAction: isPerformingAction,
                isEnabled: !transitionsDisabled,
                onFinish: onComplete
            )
        case .completedMessage:
            Text(action.title)
                .font(AppFonts.body().weight(.semibold))
                .foregroundColor(AppColors.success)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 64)
                .background(AppColors.success.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityLabel(action.title)
        case .terminalMessage:
            Text(status.volunteerDescription)
                .font(AppFonts.body().weight(.semibold))
                .foregroundColor(AppColors.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 64)
                .background(AppColors.secondaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .accessibilityLabel(status.volunteerDescription)
        }
    }

    private func navigationButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label("导航到出发地点", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                .font(AppFonts.body().weight(.semibold))
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
                .background(AppColors.primary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .accessibilityLabel("导航到出发地点")
        .accessibilityHint("选择高德、百度或苹果地图进行步行导航")
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

// MARK: - 长按 2 秒结束陪跑

/// 「结束陪跑」那一枚按钮的全部具名落点：时长、环形尺寸、震动节奏、两句副标题。
///
/// **为什么不复用 `SafetyLongPressGesture`**（`Safety/SafetyHubView.swift:445`，求助那条长按 3 秒）：
/// 四处对不上，且没有一处是加个参数能抹平的 ——
/// ① 时长写死在 `SafetyLongPress.duration`（3 秒），这里是 2 秒；
/// ② 它只回调「按下 / 松开」两个瞬间，**不给进度**，而环形进度与「还有 0.8 秒」
///    要的正是按住过程中的连续读数；
/// ③ 它必须同时挂一条轻点路径（求助轻点＝走二次确认），而这里**刻意没有轻点**：
///    结束即不可撤销，长按本身就是那道确认（设计包 `状态清单.md` §11 逐字如此）；
/// ④ 那个文件同时被 `AGENTS.md` §6 的求助红线用着。
/// 复用的唯一办法是给它加进度回调 + 可变时长 + 可选轻点，等于为了省这几十行去改一个红线文件。
enum VolunteerFinishLongPress {
    /// 2 秒。**屏幕上印的那个数字由它生成**，不另写字面量 —— 分开写就会有一天对不上，
    /// 而对不上的表现是「说好按 2 秒，按了 2 秒没反应」。
    static let duration: TimeInterval = 2

    /// 环形进度 ⌀40 / 线宽 3（设计包 `状态清单.md` §10）。两者都按 Dynamic Type 缩放，
    /// 见 `VolunteerFinishLongPressButton` 里的 `@ScaledMetric`。
    static let ringDiameter: CGFloat = 40
    static let ringLineWidth: CGFloat = 3

    /// 读秒与环形的刷新间隔。20Hz —— 比副标题的精度（0.1 秒）快一档就够。
    static let tickInterval: TimeInterval = 0.05

    static let title = "结束陪跑"

    /// 渐强震动：按住越久震得越重。这是「我按够了没」在触觉通道上的唯一读数。
    ///
    /// 与 `HapticFeedback` 那条「每一次触觉旁边都必须已经有一句话在播」的不变量不冲突，
    /// 破例理由与 `HapticFeedback.Kind.tick` 逐字相同：这几下不是几条独立消息，
    /// 而是同一个信息（还差多久）的几个节拍，而那个信息此刻正以「还有 0.8 秒」印在按钮上。
    ///
    /// 每一拍都**严格落在 `duration` 之前**，且最后一拍留 0.3 秒空当：踩在 2.0 上那一拍
    /// 会和触发时 `triggerIntensity` 那记满强度黏成一下，渐强就没有终点了。
    static let hapticRamp: [(elapsed: TimeInterval, intensity: CGFloat)] = [
        (0.0, 0.35),
        (0.5, 0.5),
        (1.0, 0.65),
        (1.4, 0.8),
        (1.7, 0.9),
    ]

    /// 走满那一刻的满强度一记：渐强的终点，也是「成了，可以松手」唯一的触觉信号。
    static let triggerIntensity: CGFloat = 1

    /// 没按住时的副标题。
    static var idleSubtitle: String { "长按 \(durationText) 秒 · 松手取消" }

    /// 按满之后、后端还没回来那几百毫秒的副标题。
    /// 不留着「还有 0.1 秒」：那句话在请求已经发出之后是**假的**。
    static let submittingSubtitle = "正在结束本次陪跑"

    /// 读屏标签。听见的数字和屏幕上印的是同一个。
    static var accessibilityLabel: String { "\(title)，长按 \(durationText) 秒" }

    static let accessibilityHint = "上下轻扫选择「结束陪跑」动作即可结束，不必按住"

    /// 读屏用户双击（`accessibilityActivate`）时念的那句。
    ///
    /// 🔴 **双击不结束。** 结束不可撤销，读屏路径上那道闸就是「要多做一个手势」——
    /// 与视力用户要按满 2 秒等价。但双击也不能什么都不发生：那正是红线里
    /// 「点了没反应就是事故」说的那种事故，所以这里改成把怎么做念出来。
    static var activationGuidance: String {
        "结束陪跑需要上下轻扫选择「结束陪跑」动作，或者按住 \(durationText) 秒"
    }

    /// 按住过程中的副标题。
    static func holdingSubtitle(elapsed: TimeInterval) -> String {
        "按住不要松手 · 还有 \(remainingText(elapsed: elapsed)) 秒"
    }

    /// 剩余秒数，向上取整到 0.1，且按住期间**永不显示 0.0** ——
    /// 显示 0.0 而按钮还没结束，读起来像是卡住了。
    static func remainingText(elapsed: TimeInterval) -> String {
        let remaining = max(0, duration - elapsed)
        // 先减一个微量再向上取整。二进制里 `2 - 1.7 == 0.30000000000000004`、
        // `2 - 1.9 == 0.10000000000000009`，直接 `ceil` 会把它们印成「0.4」「0.2」——
        // 比真实剩余多整整一格，而这是按住那两秒里用户唯一盯着的数字。
        // 1e-6 远小于 0.1 的显示精度，不会把真的 0.30 压成 0.2。
        //
        // ⚠️ 举例必须用 1.7 / 1.9 这种**真的不精确**的值：`2 - 0.3` 恰好是精确的 1.7，
        // 拿它写用例会两种实现都通过（2026-09-16 就这样假绿过一次）。
        let rounded = max(0.1, (remaining * 10 - 1e-6).rounded(.up) / 10)
        return String(format: "%.1f", rounded)
    }

    /// 环形进度 0…1。超时钳在 1：触发与最后一次读秒之间有几毫秒空当，
    /// 那几毫秒里环形不该越过满格。
    static func progress(elapsed: TimeInterval) -> Double {
        min(1, max(0, elapsed / duration))
    }

    /// 环形**该显示**多少。🔴 **不是直接读 `elapsed`。**
    ///
    /// 触发之后 `elapsed` 停在满格，而结束请求失败时按钮会回到可按状态
    /// （`VolunteerOrderTransitionState.failed.blocksDuplicateSubmission == false`，
    /// `isPerformingAction` 也经 `defer` 归回 false），于是屏幕上会留下
    /// **「环形满格 + 副标题说『长按 2 秒』」** 这种自相矛盾的样子，且会一直留着。
    ///
    /// 对不开读屏的低视力志愿者，满格环形是「已经结束了」唯一的视觉读数 ——
    /// 而那一刻订单其实还在跑。所以：没按住、也没在提交，就必须是 0。
    static func ringProgress(elapsed: TimeInterval, isHolding: Bool, hasFired: Bool) -> Double {
        if isHolding { return progress(elapsed: elapsed) }
        // 触发到 `isPerformingAction` 变 true 之间有一两帧空当，`hasFired` 只为填住它，
        // 请求一落地（成功或失败）就会被清掉。
        return hasFired ? 1 : 0
    }

    /// 从 `previous` 走到 `current` 这一拍里跨过的那一档强度；没跨过返回 nil。
    /// 一拍里跨过两档时取靠后那档 —— 掉一下总比一次震两下好。
    static func hapticIntensity(from previous: TimeInterval, to current: TimeInterval) -> CGFloat? {
        hapticRamp.last(where: { $0.elapsed > previous && $0.elapsed <= current })?.intensity
    }

    /// `2` 而不是 `2.0`。`%g` 去掉无意义的小数位，将来改成 2.5 秒时这句话照样通顺。
    private static var durationText: String { String(format: "%g", duration) }
}

/// 陪跑员端结束服务的**唯一**入口：按满 2 秒才结束，松手即取消（环形归零、不播报、无提示）。
///
/// 🔴 **没有轻点路径。** `POST /api/orders/{id}/finish` 之后不可撤销，所以这里不给
/// 「按一下弹个确认框」那种入口 —— 长按本身就是确认，多一个弹框只会让人习惯性点掉。
///
/// 「减弱动态效果」下**不需要分档**：这枚按钮全程没有位移与缩放，环形进度是**信息**
/// （还差多久）不是装饰，两种设置下一模一样。
struct VolunteerFinishLongPressButton: View {
    let isPerformingAction: Bool
    let isEnabled: Bool
    let onFinish: () -> Void

    @ScaledMetric(relativeTo: .body) private var ringDiameter: CGFloat = VolunteerFinishLongPress.ringDiameter
    @ScaledMetric(relativeTo: .body) private var ringLineWidth: CGFloat = VolunteerFinishLongPress.ringLineWidth
    @State private var elapsed: TimeInterval = 0
    @State private var holdTask: Task<Void, Never>?
    /// 渐强那一路用的生成器。**存下来是为了给 `fire()` 复用同一个已 `prepare()` 的实例** ——
    /// 新建一个再立刻 `impactOccurred` 常被系统丢掉（理由见 `startHold` 里那段注释），
    /// 而触发那一记正是「成了，可以松手」唯一的触觉信号，最不能丢的就是它。
    @State private var generator: UIImpactFeedbackGenerator?
    /// 走满 2 秒那一刻 SwiftUI 也会送来一次「松手了」。没有这个标志位，
    /// 松手那条分支会把环形立刻归零 —— 用户按到底看到的是进度条弹回去。
    @State private var didFire = false

    var body: some View {
        HStack(spacing: 12) {
            progressRing
            VStack(alignment: .leading, spacing: 2) {
                Text(VolunteerFinishLongPress.title)
                    .flowFont(FlowFonts.actionButton())
                Text(subtitle)
                    .flowFont(FlowFonts.actionButtonHint(), monospacedDigit: true)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        // 环形 + 文字作为一整块居中（设计稿 `screens/C-陪跑员端.png`），
        // 不是环形贴左、文字占满剩余宽度。
        .foregroundColor(AppColors.Flow.onCTA)
        .padding(.vertical, 10)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .frame(minHeight: FlowMetrics.actionButtonMinHeight)
        .background(isEnabled ? AppColors.Flow.cta : AppColors.Flow.ctaDisabled)
        .clipShape(RoundedRectangle(cornerRadius: FlowMetrics.buttonRadius, style: .continuous))
        // ⛔ 不用 `Button`：`Button` 把长按当成「取消这次点击」吃掉（同 `SafetyLongPressGesture`）。
        .contentShape(Rectangle())
        .onLongPressGesture(
            minimumDuration: VolunteerFinishLongPress.duration,
            perform: fire,
            onPressingChanged: pressingChanged
        )
        // `.disabled()` 同时阻断手势并给读屏打上「不可用」，不是在回调里静默 return。
        .disabled(!isEnabled || isPerformingAction)
        // 请求落地就把「已触发」清掉。成功时这一屏会被换掉，所以这行实际管的是**失败**：
        // 失败后按钮回到可按状态，环形必须跟着回到 0，否则它在说一件没发生的事。
        .onChange(of: isPerformingAction) { performing in
            guard !performing else { return }
            didFire = false
            elapsed = 0
        }
        .onDisappear(perform: cancelHold)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(VolunteerFinishLongPress.accessibilityLabel)
        .accessibilityHint(VolunteerFinishLongPress.accessibilityHint)
        .accessibilityAction {
            UIAccessibility.post(notification: .announcement, argument: VolunteerFinishLongPress.activationGuidance)
        }
        .accessibilityAction(named: VolunteerFinishLongPress.title, fire)
        .accessibilityIdentifier("volunteerFinishEscortButton")
    }

    private var subtitle: String {
        if isPerformingAction { return VolunteerFinishLongPress.submittingSubtitle }
        guard holdTask != nil else { return VolunteerFinishLongPress.idleSubtitle }
        return VolunteerFinishLongPress.holdingSubtitle(elapsed: elapsed)
    }

    @ViewBuilder
    private var progressRing: some View {
        if isPerformingAction {
            ProgressView()
                .tint(AppColors.Flow.onCTA)
                .frame(width: ringDiameter, height: ringDiameter)
        } else {
            ZStack {
                Circle()
                    .stroke(AppColors.Flow.onCTA.opacity(0.3), lineWidth: ringLineWidth)
                Circle()
                    .trim(
                        from: 0,
                        to: VolunteerFinishLongPress.ringProgress(
                            elapsed: elapsed,
                            isHolding: holdTask != nil,
                            hasFired: didFire
                        )
                    )
                    .stroke(
                        AppColors.Flow.onCTA,
                        style: StrokeStyle(lineWidth: ringLineWidth, lineCap: .round)
                    )
                    // 从 12 点方向开始走。这是静态旋转，不是动效。
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: ringDiameter, height: ringDiameter)
            // 读秒已经在副标题里念出来了，环形再报一次是重复。
            .accessibilityHidden(true)
        }
    }

    private func pressingChanged(_ pressing: Bool) {
        guard pressing else {
            cancelHold()
            // 松手即取消：环形归零，**一个字都不多说**。没按满 2 秒什么都没发生过，
            // 补一句「已取消」只会让人以为自己刚才误触了什么。
            if !didFire { elapsed = 0 }
            return
        }
        didFire = false
        startHold()
    }

    private func startHold() {
        holdTask?.cancel()
        elapsed = 0
        // 不 `prepare()` 的话第一下常被系统丢掉，而第一下正是最要紧的那次：
        // 用户刚按下去，还不知道这枚按钮认不认长按。
        let generator = UIImpactFeedbackGenerator(style: .heavy)
        generator.prepare()
        self.generator = generator
        let start = Date()
        holdTask = Task { @MainActor in
            var previous: TimeInterval = -1
            while !Task.isCancelled {
                let now = Date().timeIntervalSince(start)
                self.elapsed = min(now, VolunteerFinishLongPress.duration)
                if let intensity = VolunteerFinishLongPress.hapticIntensity(from: previous, to: now) {
                    generator.impactOccurred(intensity: intensity)
                }
                previous = now
                // 走满之后只停掉读秒，**不在这里结束订单** —— 触发的唯一判据是手势本身，
                // 两个地方都能触发就会有一天各触发一次。
                guard now < VolunteerFinishLongPress.duration else { return }
                try? await Task.sleep(nanoseconds: UInt64(VolunteerFinishLongPress.tickInterval * 1_000_000_000))
            }
        }
    }

    private func cancelHold() {
        holdTask?.cancel()
        holdTask = nil
        generator = nil
    }

    private func fire() {
        // **先震再 `cancelHold()`**：复用渐强那一路已经 `prepare()` 过的生成器，
        // 现造一个再立刻触发常被系统丢掉，而这一记是「按够了」唯一的触觉信号。
        // 读屏那条自定义动作进来时 `generator` 是 nil（没按过），只能现造 —— 那条路径上
        // 用户拿到的反馈是随后的状态播报，不指望这一下。
        let impact = generator ?? UIImpactFeedbackGenerator(style: .heavy)
        impact.impactOccurred(intensity: VolunteerFinishLongPress.triggerIntensity)
        cancelHold()
        didFire = true
        elapsed = VolunteerFinishLongPress.duration
        onFinish()
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
                // 上屏那份留掩码星号，念出来这份去掉。
                .accessibilityLabel("盲人：\(order.blindName?.unmaskedForSpeech ?? "")")

            if showPhone, let phone = order.blindPhone {
                Button {
                    if let url = EmergencyDialer.telURL(for: phone) {
                        EmergencyDialer.dial(url, open: { openURL($0) })
                    }
                } label: {
                    Label(
                        EmergencyContactResponse.maskPhone(phone) ?? phone,
                        systemImage: "phone.fill"
                    )
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityLabel("拨打盲人电话")
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

    /// 盲人填的自由文本（路线备注 / 特殊说明）只在**接单后**展示。判据集中在
    /// `RunOrderStatus.disclosesBlindRunnerNotesToVolunteer`（穷举 switch，含 `.unknown` 默认关），
    /// 不在这里就地写 `!= .pendingMatch` —— 这个视图的两个调用点里，
    /// `VolunteerOrderDetailView:921` 是从「可接订单」列表点进来的，那里的订单任何志愿者都能浏览。
    private var showsSensitiveNotes: Bool {
        order.status.disclosesBlindRunnerNotesToVolunteer
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("订单信息")
                .font(.headline)
                .foregroundColor(AppColors.textPrimary)
            infoRow("出发地点", order.startAddress ?? "")
            if let endAddress = order.endAddressForDisplay {
                infoRow("结束地点", endAddress)
            }
            infoRow("预约时间", (order.plannedStart ?? "").displayDateTime)
            if let plannedEnd = order.plannedEndForAnnouncement {
                infoRow("预计结束时间", plannedEnd)
            }
            if let distanceText {
                infoRow("距离", distanceText)
            }
            if showsSensitiveNotes, let routeNotes = order.routeNotes?.nilIfBlank {
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
            // 「导盲犬」那一行移进 `VolunteerRunnerNeedsBanner` —— 它和视力情况、引导方式
            // 是同一类信息（决定见面第一个动作），散在订单信息的第 8 行里等于没有。
            // 两处都渲染会让接单后同一句话出现两遍。
            if showsSensitiveNotes, let notes = order.specialNotes?.nilIfBlank {
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
            // 这里此前是 `record.pointsText`，恒为「+100 积分」——一个后端不存在的数字。
            // 删掉不补：完成状态已经在上面那行显示了，服务量在「服务成就」页。
        }
        .padding(.vertical, 4)
    }
}

struct VolunteerReadOnlyOrderView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @StateObject private var trackViewModel = CompletedTrackSummaryViewModel()
    let order: OrderDetailResponse

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VolunteerStatusBanner(status: order.status)
                // 只读回看也保留：导盲犬那一行原本在订单信息里，从那儿移走之后
                // 这个页面不补上就成了净丢失。
                VolunteerRunnerNeedsBanner(order: order)
                VolunteerBlindRunnerInfoCard(order: order, showPhone: order.status != .pendingMatch && order.blindPhone?.trimmed.isEmpty == false)
                VolunteerOrderInfoSection(order: order, distanceText: nil)
                if order.status == .completed, let track = trackViewModel.track {
                    CompletedTrackSummaryView(track: track, recordOrderId: order.orderId, role: .volunteer) {
                        speechService.speak(track.spokenSummary)
                    }
                } else if trackViewModel.isLoading {
                    ProgressView("正在加载本次路线")
                } else if let error = trackViewModel.errorMessage {
                    Text(error).foregroundColor(AppColors.textSecondary)
                }
            }
            .padding(20)
            .readableContentColumn()
        }
        .navigationTitle("订单详情")
        .task {
            guard order.status == .completed else { return }
            await trackViewModel.load(orderID: order.orderId, appState: appState)
        }
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
