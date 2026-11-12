import SwiftUI

enum VolunteerSheet: Identifiable {
    case navigation(ExternalMapNavigationRequest)
    /// 汇合态的「找不到对方」。**纯本地**：契约里没有「我找不到他」这个动作。
    case cannotFindRunner
    /// 「上报问题」→ `POST /api/support/tickets`。
    case supportTicket
    /// 取消这次陪跑的确认层。
    case cancelOrder
    /// 跑步中右上角「求助」打开的面板（DECISIONS-v2 V5）。
    case runHelp

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
        case .runHelp:
            return "runHelp"
        }
    }
}

struct VolunteerInServiceView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var speechService: SpeechService
    @EnvironmentObject var locationService: LocationService
    @EnvironmentObject private var amapGeocodingService: AMapGeocodingService
    @Environment(\.dismiss) var dismiss
    @Environment(\.openURL) var openURL
    @StateObject var viewModel: VolunteerInServiceViewModel
    @StateObject var trackViewModel = CompletedTrackSummaryViewModel()
    /// 举报 / 不再匹配此人。入口在顶栏「···」，弹层挂在页面根上，结果一行在页脚（`CounterpartSafetyMenu`）。
    @StateObject var counterpartSafety = CounterpartBlockViewModel()
    @State var showEmergencyConfirm = false
    @State var showsRunRecord = false
    @State var activeSheet: VolunteerSheet?
    @Environment(\.scenePhase) private var scenePhase
    /// 汇合页的朝向源，只在 `DRIVER_ARRIVED` 开着。
    @StateObject var meetHeading = MeetHeadingProvider()
    /// 方位描述的滞回基准（上一次说的是哪个方位）。
    @State var meetSector: DirectionSector?
    /// 上一次汇合提示（档位 + 方位）。只在它**变了**时播报，首次进入不播（状态播报已经在说）。
    @State var lastMeetCue: MeetCue?
    @State var lastMeetAnnouncementAt: Date?
    @State var didBuzzWithin10 = false
    /// 兜底页右上的求助（只会是本地拨号，见 `fallbackContent`）。
    @State var showsLocalHelp = false
    let orderId: Int64
    let initialOrder: OrderDetailResponse?
    /// 收起面板的动画时长（系统 sheet 约 0.35 秒）。等它收完再出栈，见 `didLoseOrder` 那条。
    static let sheetDismissalDelayNanoseconds: UInt64 = 400_000_000

    struct MeetCue: Equatable {
        let bucket: DistanceBucket
        let sector: DirectionSector?
    }

    init(orderId: Int64, initialOrder: OrderDetailResponse? = nil) {
        self.orderId = orderId
        self.initialOrder = initialOrder
        // 有 `initialOrder` 时第一帧就画那一态，不先闪加载外壳（#962 第 1 项）。
        _viewModel = StateObject(wrappedValue: VolunteerInServiceViewModel(initialOrder: initialOrder))
    }

    /// 这一态走不走这个页面。`nil` = 走兜底页（`fallbackContent`）。
    ///
    /// 跑步中也不走这里，它有自己的 `runningPage`（#218）。
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
    /// 对陪跑员来说它们的后果一样 —— 现在不知道他在哪。过期由订单跟踪（`OrderLiveTrack`）发
    /// `.peerLocationExpired`、view model 把 `latestBlindSample` 清掉（阈值 `LiveEscortSessionCoordinator.peerFreshness`），
    /// 所以这里不需要再判一次时间戳，**也不许判** —— 两处各有一个新鲜度阈值必然漂。
    var peerDistanceText: String? {
        guard locationService.isAuthorized,
              let deviceCoordinate = locationService.currentLocation,
              let peer = viewModel.latestBlindSample else { return nil }
        let meters = DistanceCalculator.distanceFromDeviceToBackend(
            deviceCoordinate: deviceCoordinate,
            backendCoordinate: peer.coordinate
        )
        return DistanceCalculator.formattedDistance(meters)
    }

    /// 跑步中（v2 画布 ⑤，#218）。它不走 `flowPresentation` 那一套：没有信息行、引导绳和黄色主按钮。
    var isRunning: Bool { viewModel.order?.status == .inProgress }

    var body: some View {
        Group {
            if let order = viewModel.order, isRunning {
                runningPage(order: order)
            } else if let order = viewModel.order, flowPresentation != nil {
                // 每秒一拍：解锁时刻、结束等待时刻、「N 分钟后出发」都是 `(订单, 现在)` 的函数，不存。
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    flowPage(order: order, now: context.date)
                }
            } else {
                fallbackContent
            }
        }
        .navigationTitle(VolunteerOrderFlowCopy.pageTitle)
        .navigationBarTitleDisplayMode(.inline)
        // 每一路都自带导航栏（左返回、右求助），系统那条要整条藏掉，否则两条叠着。
        .toolbar(.hidden, for: .navigationBar)
        // 订单页**不带标签栏**（设计交付 v3 §4.2 总表：S1/S2/S3/S4 的底部是「标签栏」，
        // 而 S6 是「求助与安全」；`03-订单页全流程.png` 五屏也都没有标签栏）。
        // 多一条 49pt 的标签栏会把底部操作区顶上去，而标签栏在这一刻能去的地方
        // （记录 / 我的）没有一个是陪跑中该去的：多出来的标签栏会把最后一行盖掉半行
        // （同一个形状已在 `VolunteerServiceRecognitionView` 上红过一次）。
        //
        // 🔴 **前提是每一屏都有出口。** 盲人端的订单页刻意保留了标签栏，理由在
        // `BlindOrderStatusView.swift:1642-1646`：那一页跑步中会藏返回箭头，
        // 标签栏是唯一出口。这一页藏了系统导航栏，出口是每一路自带导航栏上的返回；
        // 完成页没有返回、出口是主按钮「完成」（`.doneReviewing` → dismiss）。
        // **谁将来去掉其中任何一个出口，这一行必须同时撤销。**
        //
        // ⚠️ 2026-09-17 合并时搬过一次位置：它原本挂在旧 body 的末尾，而那一段被
        // 四步骨架重构删掉了。取任一边都会让这一行静默消失，所以是手动搬进来的。
        .toolbar(.hidden, for: .tabBar)
        .counterpartSafetyPrompts(
            viewModel: counterpartSafety,
            target: viewModel.order.flatMap(CounterpartSafetyGate.orderPageTarget)
        )
        .task {
            viewModel.configure(with: appState, speechService: speechService, initialOrder: initialOrder)
            viewModel.startPolling(orderId: orderId)
            // 取消弹层的窗口小时数读它。从推送直接点进这一页时首页那次可能还没拉过；
            // 已经拉过就是一次空操作（`loadRuleParamsIfNeeded` 成功后置位）。
            await appState.loadRuleParamsIfNeeded()
        }
        .onDisappear {
            viewModel.stopPolling()
            meetHeading.stop()
        }
        // #368：没有位置轨迹同意就不开定位。离开页面只撤回这一页那一份（#425），同行会话那一份由协调器撤。
        .requestsLocationUpdates(.volunteerActiveOrder, when: appState.hasLocationTrackConsent(.volunteerLocationTrack))
        // 从后台回来时手上的 ETA / 档位可能已经过时（实时推送不落通知日志），重拉一次详情。
        .onChange(of: scenePhase) { phase in
            guard phase == .active else { return }
            Task { await viewModel.load(orderId: orderId, speakChanges: true) }
        }
        .task(id: viewModel.order?.status == .driverArrived) {
            if viewModel.order?.status == .driverArrived { meetHeading.start() } else { meetHeading.stop() }
        }
        .onChange(of: meetCue) { handleMeetCueChange($0) }
        // 跑步中求助面板只属于 `IN_PROGRESS`。订单一离开（完成 / 被取消 / 转重新匹配）就收起，
        // 不留一个按下去已经不成立的面板（云端求助另有 `EmergencyCoordinator.trigger` 的状态闸兜底）。
        // 反过来，取消弹层不属于 `IN_PROGRESS`：跑步中没有取消入口（#962）。汇合页开着弹层时跑者按了开始，收起。
        // 状态变化时把读屏焦点移到页头（#962 第 4 项，同盲人端 `BlindOrderStatusView` 的 `statusHeaderFocused`）
        // 在 `VolunteerOrderFlowPage` 里做：焦点状态是那个视图自己的。
        .onChange(of: viewModel.order?.status) { status in
            if case .runHelp = activeSheet, status != .inProgress { activeSheet = nil }
            if case .cancelOrder = activeSheet, status == .inProgress { activeSheet = nil }
        }
        .onReceive(locationService.$currentLocation) { _ in
            viewModel.observeOwnLocationAccuracy(locationService.latestDeviceSample?.horizontalAccuracy)
        }
        .onChange(of: viewModel.didEndWaiting) { ended in
            if ended { dismiss() }
        }
        // 这一单被系统转走了（#456）：先收起面板与拨号单 —— 「找不到对方」里的拨号、「上报问题」都还连着这一单 ——
        // 再回到接单主页。面板开着时等它收完再关页：同一拍里收面板又出栈，iOS 16 会丢掉其中一个。
        .onChange(of: viewModel.didLoseOrder) { lost in
            guard lost else { return }
            let hadPresentation = activeSheet != nil || showsLocalHelp || showEmergencyConfirm
                || viewModel.offersLocalCallAfterUnsentSOS
            activeSheet = nil
            showsLocalHelp = false
            showEmergencyConfirm = false
            viewModel.offersLocalCallAfterUnsentSOS = false
            guard hadPresentation else {
                dismiss()
                return
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: Self.sheetDismissalDelayNanoseconds)
                dismiss()
            }
        }
        // 自己按的取消、而 `REMATCHING` 推送晚于取消响应到达：取消面板的回调那时看到的还是 `false`、没关页，
        // 确认拉取又因为已不是参与者被后端 403，页面就停在兜底页转圈。推送先到的那一种面板还开着，
        // 由面板的回调关页，这里不抢。
        .onChange(of: viewModel.didCancelOrder) { cancelled in
            if cancelled, activeSheet == nil { dismiss() }
        }
        .volunteerFirstRunHelp(status: viewModel.order?.status, isBlocked: activeSheet != nil)
        .task(id: viewModel.order?.status) {
            // ⑨ 跑者已取消：竖线停在哪一步要读状态变更记录（#962，同盲人端已取消页）。拿到之前不画竖线。
            if viewModel.order?.status == .cancelled {
                await viewModel.loadStatusLogs(using: appState)
                return
            }
            guard viewModel.order?.status == .completed else { return }
            await trackViewModel.load(orderID: orderId, appState: appState)
            if let summary = trackViewModel.track?.spokenSummary { speechService.speak(summary) }
        }
        // `.volunteer`：他按下去之后撤销不了（后端恒 403），文案要把这一半后果说出来。
        .emergencyConfirmationAlert(isPresented: $showEmergencyConfirm, audience: .volunteer) {
            Task { await sendCloudEmergency() }
        }
        .emergencyCallOptionsDialog(
            isPresented: $viewModel.offersLocalCallAfterUnsentSOS, context: .volunteerCloudUnsent, primaryContact: nil
        )
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
            case .runHelp:
                if let order = viewModel.order {
                    VolunteerRunHelpPanel(
                        coordinator: appState.emergencyCoordinator,
                        runnerName: order.runnerShortName,
                        isPaused: order.isRunPaused,
                        isTogglingPause: viewModel.isTogglingPause,
                        supportState: viewModel.supportRequestState,
                        ringingUntil: viewModel.ringingUntil,
                        isSessionExpired: appState.isSessionExpiryDeferred,
                        onPause: { Task { await viewModel.pauseRun() } },
                        onRing: { Task { await viewModel.ringRunner() } },
                        onContactSupport: { Task { await viewModel.requestSupportCallback() } },
                        onEmergency: {
                            Task { await sendCloudEmergency() }
                        }
                    )
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                }
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

}
