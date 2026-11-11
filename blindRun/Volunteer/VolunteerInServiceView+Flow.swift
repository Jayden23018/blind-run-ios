import SwiftUI
import UIKit

extension VolunteerInServiceView {
    // MARK: - 跑步中

    /// 求助只在这一态走云端（`VolunteerOrderSOSMode`）。右上角打开跑步中求助面板（V5），
    /// 面板里的紧急按钮轻点弹锁定文案的二次确认、长按 3 秒直发。
    ///
    /// 每秒一拍：信号卡 8 秒收起、5 分钟过期、走散提示 60 秒收起都是 `(状态, 现在)` 的函数，不存。
    func runningPage(order: OrderDetailResponse) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VolunteerRunningPage(
                coordinator: appState.emergencyCoordinator,
                order: order,
                stats: viewModel.blindStats,
                isPeerLocationFresh: viewModel.latestBlindSample != nil,
                mapInput: trackingMapInput(order: order),
                isFinishing: viewModel.isPerformingAction,
                isFinishEnabled: !viewModel.isTransitionPending,
                onBack: { dismiss() },
                onHelp: { activeSheet = .runHelp },
                // 按满 2 秒直接结束，中间没有确认框：长按本身就是那道确认
                // （设计包 `状态清单.md` §11：「结束跑步即结束服务，不可撤销 —— 因此不做轻点」）。
                onFinish: { Task { await viewModel.complete() } },
                onCancel: { activeSheet = .cancelOrder },
                tip: VolunteerRunTip.resolve(
                    separationAlertAt: viewModel.separationAlertAt,
                    runnerBatteryLow: order.run?.runnerBatteryLow == true,
                    weakLocationSince: viewModel.weakLocationSince,
                    now: context.date
                ),
                isTogglingPause: viewModel.isTogglingPause,
                onResume: { Task { await viewModel.resumeRun() } }
            ) {
                emergencySection(for: order)
                // 跑步中求助面板能按「让对方手机响」（后端 #445），失败或没送到要看得见。
                flowFooter(showsNudgeNotice: true)
            }
        }
    }

    // MARK: - 四步骨架（邀请 / 约好 / 出发）

    @ViewBuilder
    func flowPage(order: OrderDetailResponse, now: Date) -> some View {
        let distance = distanceText(for: order)
        if let presentation = VolunteerOrderFlowPresentation.make(
            order: order,
            distanceText: distance,
            peerDistanceText: peerDistanceText,
            now: now
        ), let phase = VolunteerOrderPhase.resolve(order: order, now: now) {
            let direction = meetDirection(order: order, phase: phase)
            let meet = meetPanel(order: order, phase: phase, direction: direction, now: now)
            // 后端放行时刻（#546）。`now` 来自外层每秒一拍的 `TimelineView`，所以到点按钮自己亮起。
            let gate = VolunteerActionGate.resolve(action: presentation.primaryAction, order: order, now: now)
            VolunteerOrderFlowPage(
                presentation: presentation,
                // 约好时的带绳一行、汇合时的开口一行、首单标签（#660，`VolunteerOrderPrepNotices.swift`）。
                hero: VolunteerOrderHero.make(order: order, phase: phase, now: now, direction: direction?.sector.text, distanceText: distance).withPrepNotices(order: order, phase: phase, totalCompleted: viewModel.dispatchSummary?.totalCompleted),
                order: order,
                phase: phase,
                meet: meet,
                quickReplies: quickReplies(order: order, phase: phase, now: now),
                mapInput: trackingMapInput(order: order),
                // 完成页没有返回：出口是主按钮「完成」。
                onBack: phase == .completed ? nil : { dismiss() },
                onRowAction: { handleFlowRowAction($0, order: order) },
                onPrimaryAction: { performFlowPrimaryAction(presentation.primaryAction) },
                // 只可能是 `IN_PROGRESS`（`VolunteerOrderSOSMode.resolve`），其余状态页面自己弹本地拨号。
                onCloudHelp: { showEmergencyConfirm = true },
                // POST 回来了但确认那条 GET 还挂着的那几秒里，同一次流转不许被提交第二次。
                isPrimaryLoading: viewModel.isPerformingAction,
                isPrimaryEnabled: !viewModel.isTransitionPending && !gate.isLocked,
                awaitingBlindConfirmation: viewModel.awaitingBlindConfirmation,
                gateCaption: gate.caption,
                counterpartSafety: CounterpartSafetyGate.orderPageTarget(order) == nil ? nil : counterpartSafety,
                // 汇合页的响铃结果挂在响铃按钮下，其余页挂在页脚。
                footer: {
                    flowFooter(showsNudgeNotice: meet == nil, showsStarProgress: phase == .completed)
                    // 举报 / 不再匹配此人在顶栏「···」，这里只留结果一行。
                    CounterpartBlockOutcome(viewModel: counterpartSafety)
                    VolunteerFirstRunLoader(viewModel: viewModel, phase: phase)
                }
            )
        } else {
            fallbackContent
        }
    }

    /// v7 地图（#945）：集合点、跑者实时位置、本机位置；完成页画整条路线。坐标一律 GCJ-02：
    /// 跑者位置只收后端坐标系那一份，「我」取 `effectiveBackendLocation`（唯一一次转换，同盲人端）。
    private func trackingMapInput(order: OrderDetailResponse) -> BlindTrackingMapInput {
        let runner = viewModel.latestBlindSample.flatMap { $0.system == .gcj02Backend ? $0.coordinate : nil }
        let route = order.status == .completed
            ? (trackViewModel.track?.primaryRouteCoordinates).flatMap { $0.count >= 2 ? $0 : nil } ?? []
            : []
        return BlindTrackingMapInput(
            meetPoint: order.startCoordinate,
            volunteer: runner,
            me: locationService.currentLocation == nil ? nil : locationService.effectiveBackendLocation,
            route: route,
            peerTitle: "跑者"
        )
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
    var meetCue: MeetCue? {
        guard let order = viewModel.order, order.status == .driverArrived else { return nil }
        return MeetCue(
            bucket: order.meet?.distanceBucket ?? .unknown,
            sector: meetDirection(order: order, phase: .arrived(canEndWait: false))?.sector
        )
    }

    /// 交付包 03 §三：只在方位描述或档位变化时播报，两次至少隔 3 秒；首次进 `WITHIN_10` 轻震一次。
    func handleMeetCueChange(_ cue: MeetCue?) {
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

    /// 两个云端求助入口共用。取坐标与跑者端同一道闸，精确位置关着先问一次临时精确位置（#407 第 1 项）；
    /// 确定没发出去时 view model 打开本地拨号兜底。
    func sendCloudEmergency() async {
        await viewModel.enterEmergency(
            locate: { await EmergencyCoordinator.freshEmergencyCoordinateAskingForPrecision(
                using: locationService, sharingBlocked: appState.isEmergencyLocationSharingBlocked
            ) },
            locationFailureReason: { EmergencyCoordinator.locationFailureReason(
                using: locationService, sharingBlocked: appState.isEmergencyLocationSharingBlocked
            ) }
        )
    }

    /// 号码只在这里出现一次，且只进 `tel:`。掩码串会被 `telURL` 的掩码闸拦掉
    /// （不拦则拼成 `tel://1381001`，一个可能真打给别人的号码）。
    func callRunner() {
        guard let url = dialableRunnerPhone else { return }
        EmergencyDialer.dial(url, open: { openURL($0) })
    }

    /// `nil` = 这一单没有能拨通的号码 ⇒ 任何拨号入口都不该出现。
    var dialableRunnerPhone: URL? {
        guard let phone = viewModel.order?.blindPhone?.nilIfBlank else { return nil }
        return EmergencyDialer.telURL(for: phone)
    }

    /// 两处入口共用同一份装配（已完成页的「上报问题」、汇合页「找不到对方」里的那一枚）。
    var supportTicketSheet: some View {
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
            // 成功之后这一页自己就换成跑步中页（`isRunning`）。
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
    private func flowFooter(showsNudgeNotice: Bool, showsStarProgress: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // 陪跑完成页：刚跑完这一单之后离下一星还差多少（负责人 2026-10-05，真机截图评审里这一屏
            // 吸引力 3/10、下面 60% 空白）。这是附加信息：拉不到就整块不出现，不挤占「完成」这个出口，
            // 也不报错 —— 成就页自己有完整的失败态。
            if showsStarProgress { VolunteerCompletionStarProgress() }
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
                    .accessibilityHint("刷新订单状态")
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
            let message = "此订单还没有集合点坐标"
            viewModel.errorMessage = message
            speechService.speakError(message)
        }
    }
}
