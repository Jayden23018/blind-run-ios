import SwiftUI

// MARK: - 跑步中（v7 ⑦）

/// 跑步中头卡的全部内容。纯类型，用例 `VolunteerRunningHeroTests`。
///
/// 数据只有跑者那一份 `blindStats`（与跑者端同一个端点、同一份数字），目标来自订单的
/// `plannedDistanceMeters`。**不画「折返」**：画布的「2.50 折返」默认原路往返，
/// 而契约里没有路线形状，绕圈跑时那个标记是错的。
struct VolunteerRunningHero: Equatable {
    struct Goal: Equatable {
        /// 0…1，跑过目标钳在 1。
        let progress: Double
        let text: String
        let isReached: Bool
    }

    let eyebrow: String
    /// 两位小数的公里数；还没有数据时 `--`（刚起跑的十几秒轨迹点不够，那是空态不是错误）。
    let distance: String
    let duration: String
    let pace: String
    /// `nil` = 订单没有计划里程 ⇒ 不画进度条。
    let goal: Goal?
    /// 头卡下方那一条提示（同一时间最多一条）。屏幕版带掩码姓名，读屏版不带。
    let notice: String?
    let noticeSpoken: String?
    let accessibilityLabel: String

    static let title = "陪跑中"
    /// 跑过目标不足 50 米不说「多跑了」：公里数是一位小数（#846 D8），十几米会写成「多跑了 0.1」。
    static let overrunThresholdMeters: Double = 50

    static func make(
        order: OrderDetailResponse,
        stats: TrackStats?,
        isPeerLocationFresh: Bool,
        isPeerAlertAcknowledged: Bool
    ) -> Self {
        let place = order.startAddress?.nilIfBlank
        let name = order.blindName?.nilIfBlank ?? VolunteerOrderFlowCopy.unknownRunnerName
        let spokenName = order.blindNameForSpeech

        let goal = order.plannedDistanceMeters.flatMap { planned -> Goal? in
            guard planned > 0 else { return nil }
            let target = RunPlanFormat.kilometresValue(Double(planned) / 1_000)
            guard let run = stats?.distanceMeters else {
                return Goal(progress: 0, text: "目标 \(target) 公里", isReached: false)
            }
            let over = run - Double(planned)
            if over >= 0 {
                let extra = over >= overrunThresholdMeters ? " · 多跑了 \(RunPlanFormat.kilometresValue(over / 1_000))" : ""
                return Goal(progress: 1, text: "已完成 \(target) 公里目标\(extra)", isReached: true)
            }
            return Goal(
                progress: run / Double(planned),
                text: "还剩 \(RunPlanFormat.kilometresValue(-over / 1_000)) 公里 · 目标 \(target)",
                isReached: false
            )
        }

        // 已确认的求助排在前面：那是「他还在求助、只是有人接手了」，比位置断了更要紧。
        // 未确认的不走这里 —— 全屏告警和求助结果区已经在说。
        let notice: (String, String)?
        if isPeerAlertAcknowledged {
            let status = EmergencySafetyCopy.volunteerPeerStatusAcknowledged
            notice = ("\(name)的求助\(status)", "\(spokenName)的求助\(status)")
        } else if !isPeerLocationFresh {
            let stale = EmergencySafetyCopy.volunteerPeerLocationStale
            notice = ("\(stale)\(name)的位置", "\(stale)\(spokenName)的位置")
        } else {
            notice = nil
        }

        func spoken(_ label: String, _ value: String?) -> String {
            value.map { "\(label) \($0)" } ?? "\(label)，正在获取"
        }
        let spokenParts = [
            place.map { "\(title)，\($0)" } ?? title,
            spoken("已跑", stats?.distanceText),
            spoken("时长", stats?.durationText),
            spoken("配速", stats?.averagePaceText),
            goal?.text.replacingOccurrences(of: " · ", with: "，"),
        ]

        return Self(
            eyebrow: place.map { "\(title) · \($0)" } ?? title,
            distance: stats?.distanceKilometersText ?? "--",
            duration: stats?.durationClockText ?? "--",
            pace: stats?.paceClockText ?? "--",
            goal: goal,
            notice: notice?.0,
            noticeSpoken: notice?.1,
            accessibilityLabel: spokenParts.compactMap { $0 }.joined(separator: "。")
        )
    }
}

/// 陪跑员跑步中那一屏（v7 ⑦，#945）：地图常驻 + 抽屉（距离 / 用时 / 配速、目标进度、一条提示、耳机播报）+
/// 底部长按结束（底部只有它，#962 删了取消）。右上角红色实心「求助」开跑步中求助面板（V5，面板本身不改）。
///
/// 求助走云端还是本地拨号只读 `VolunteerOrderSOSMode.resolve`（AGENTS §6）：这一页只在 `IN_PROGRESS` 出现，结果恒为云端。
/// 不画「折返」：契约里没有路线形状。地图画跑者位置、集合点和 `/track` 的实时轨迹（#962，同盲人端 v7 ⑦）。
///
/// 自己 `@ObservedObject` 持有 coordinator：`AppState.emergencyCoordinator` 是 `let`，
/// 在宿主 body 里读它**读得到值但不跟着更新**（记忆 `nested-observableobject-does-not-republish`）。
struct VolunteerRunningPage<Footer: View>: View {
    @ObservedObject var coordinator: EmergencyCoordinator
    let order: OrderDetailResponse
    let stats: TrackStats?
    let isPeerLocationFresh: Bool
    /// 跑者位置、集合点、本机位置。`nil` = 只画集合点。
    var mapInput: BlindTrackingMapInput?
    let isFinishing: Bool
    let isFinishEnabled: Bool
    let onBack: () -> Void
    let onHelp: () -> Void
    /// 底部唯一的结束入口。跑步中**没有取消入口**（负责人 2026-11-12 定「整个删掉」，#962）：
    /// 要离开走右上角求助面板或长按结束。别把取消加回来，也别收进「···」。
    let onFinish: () -> Void
    /// 提示（走散 / 电量低 / 定位弱）、暂停与继续。
    let tip: VolunteerRunTip?
    let isTogglingPause: Bool
    let onResume: () -> Void
    /// 求助结果、流转失败文案。**这一页唯一的可见失败面**。
    @ViewBuilder let footer: () -> Footer

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var hero: VolunteerRunningHero {
        .make(
            order: order,
            stats: stats,
            isPeerLocationFresh: isPeerLocationFresh,
            isPeerAlertAcknowledged: coordinator.volunteerAlert?.isAcknowledged == true
        )
    }

    private var isPaused: Bool { order.isRunPaused }

    private var notice: VolunteerRunningNotice? {
        .resolve(
            isPeerAlertAcknowledged: coordinator.volunteerAlert?.isAcknowledged == true,
            heroHasNotice: hero.notice != nil,
            tip: tip
        )
    }

    var body: some View {
        var input = mapInput ?? BlindTrackingMapInput(meetPoint: order.startCoordinate)
        input.peerTitle = "跑者"
        return BlindOrderTrackingView(
            status: order.status,
            mapInput: input,
            topBar: VolunteerOrderTopBar(
                surface: .onMap,
                onBack: onBack,
                isCloudHelp: VolunteerOrderSOSMode.resolve(status: order.status) == .cloud,
                isHelpBusy: coordinator.state.isBusy,
                onHelp: onHelp
            ),
            bottom: OrderFlowBottomActions(owner: .volunteer, primary: nil, secondary: AnyView(bottomControls), safetyHub: nil),
            drawer: { drawer },
            timeline: {
                BlindOrderTimelineView(
                    input: BlindOrderTimelineInput(position: .current(.startRun), folds: false, vocabulary: .volunteer)
                ) { _ in EmptyView() }
            },
            footer: { footer() }
        )
    }

    // MARK: 抽屉

    private var drawer: some View {
        let hero = hero
        return VStack(alignment: .leading, spacing: 16) {
            statsBlock(hero)
            // 同一时刻只有一条（`VolunteerRunningNotice`）。
            switch notice {
            case .hero:
                if let text = hero.notice {
                    FlowNoticeBar(text: text)
                        .accessibilityLabel(hero.noticeSpoken ?? text)
                        .accessibilityIdentifier("volunteerRunningNotice")
                }
            case .tip(let tip):
                VolunteerRunTipBar(tip: tip, name: order.runnerShortName)
            case .none:
                EmptyView()
            }
            VolunteerRunVoiceToggle()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeInOut(duration: 0.25), value: notice)
        .animation(.easeInOut(duration: 0.25), value: isPaused)
    }

    private var title: String {
        if isPaused { return VolunteerRunCopy.pausedTitle(elapsed: order.run?.elapsedClockText) }
        return "和\(order.runnerShortName)一起跑步中"
    }

    /// 标题 + 44pt 距离 + 用时 / 配速 + 目标进度。合成一个读屏元素，沿用 v2 头卡的 identifier。
    private func statsBlock(_ hero: VolunteerRunningHero) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .flowFont(FlowV2Fonts.title(), monospacedDigit: true)
                .foregroundColor(AppColors.Flow.primaryText)
                .fixedSize(horizontal: false, vertical: true)
            if isPaused {
                Text(VolunteerRunCopy.pausedBody)
                    .flowFont(FlowV2Fonts.callout())
                    .foregroundColor(AppColors.Flow.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            metricsRow(hero)
            if let goal = hero.goal { goalView(goal) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            isPaused
                ? "\(VolunteerRunCopy.pausedTitle(elapsed: order.run?.elapsedClockText))，\(VolunteerRunCopy.pausedBody)。\(hero.accessibilityLabel)"
                : hero.accessibilityLabel
        )
        .accessibilityIdentifier("volunteerRunningStatsCard")
    }

    /// 距离 44pt（盲人 v7 ⑦ 同值），用时 / 配速在右边；辅助字号下竖排。
    private func metricsRow(_ hero: VolunteerRunningHero) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .lastTextBaseline, spacing: 24))
        return layout {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(hero.distance)
                    .flowFont((44, .bold, .largeTitle), monospacedDigit: true)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text("公里").flowFont(FlowV2Fonts.heroUnit())
            }
            metric(value: hero.duration, label: "用时")
            metric(value: hero.pace, label: "配速")
        }
        .foregroundColor(AppColors.Flow.primaryText)
    }

    private func metric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .flowFont(FlowV2Fonts.subhead())
                .foregroundColor(AppColors.Flow.secondaryText)
            Text(value)
                .flowFont((22, .bold, .title2), monospacedDigit: true)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
    }

    private func goalView(_ goal: VolunteerRunningHero.Goal) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppColors.Flow.separator)
                    Capsule()
                        .fill(goal.isReached ? AppColors.Flow.stateDone : AppColors.Flow.navy)
                        .frame(width: proxy.size.width * goal.progress)
                }
            }
            .frame(height: 8)
            .accessibilityHidden(true)
            Text(goal.text)
                .flowFont(FlowV2Fonts.subhead(), monospacedDigit: true)
                .foregroundColor(AppColors.Flow.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 底部

    private var bottomControls: some View {
        VStack(spacing: 8) {
            // 暂停中本屏唯一的实心按钮（08 §五）；长按结束保持在它下面。
            if isPaused {
                BlindOrderStageButton(
                    title: VolunteerRunCopy.resume,
                    systemImage: "play.fill",
                    style: .solid,
                    isEnabled: !isTogglingPause,
                    accessibilityHint: "恢复计时",
                    action: onResume
                )
                .accessibilityIdentifier("volunteerRunResumeButton")
                .transition(.opacity)
            }
            VolunteerFinishLongPressButton(
                isPerformingAction: isFinishing,
                isEnabled: isFinishEnabled,
                onFinish: onFinish
            )
        }
        .animation(.easeInOut(duration: 0.25), value: isPaused)
    }
}
