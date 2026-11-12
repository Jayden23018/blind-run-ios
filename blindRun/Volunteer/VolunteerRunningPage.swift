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

/// 陪跑员跑步中那一屏（v8 卡片页，#972；批准稿 `docs/ui/mockups/volunteer-run-finish-v8-20261112/`）。
/// 照盲人 v8 ⑦（`BlindRunCardsPage`，#968）同一套骨架：浅灰底，标题「陪跑中」→ 青绿彩色卡（里程、用时、每公里配速）
/// → 一条提示（走散 / 收不到位置 / 电量低 / 定位弱）→ 计划进度 → 耳机语音播报 → 让跑者手机响 → 结果面；
/// 底部长按 2 秒结束（底部只有它，#962 删了取消）。右上角红色实心「求助」开跑步中求助面板（V5，面板本身不改）。
/// 不放地图（改 v7 ⑦ 的「地图常驻 + 抽屉」，同盲人 v8 决定）。
///
/// 求助走云端还是本地拨号只读 `VolunteerOrderSOSMode.resolve`（AGENTS §6）：这一页只在 `IN_PROGRESS` 出现，结果恒为云端。
/// 不画「折返」：契约里没有路线形状。
///
/// 自己 `@ObservedObject` 持有 coordinator：`AppState.emergencyCoordinator` 是 `let`，
/// 在宿主 body 里读它**读得到值但不跟着更新**（记忆 `nested-observableobject-does-not-republish`）。
struct VolunteerRunningPage<Footer: View>: View {
    @ObservedObject var coordinator: EmergencyCoordinator
    let order: OrderDetailResponse
    let stats: TrackStats?
    let isPeerLocationFresh: Bool
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
    /// 「让跑者手机响」那张卡。`isRinging` = 后端 `ringingUntil` 之前；登录过期时不可点（同求助面板那一行）。
    var isRinging = false
    var isRingEnabled = true
    var onRing: () -> Void = {}
    /// 求助结果、响铃结果、流转失败文案。**这一页唯一的可见失败面**。
    @ViewBuilder let footer: () -> Footer

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
        let hero = hero
        return RunCardsScaffold(
            gap: BlindRunCardsMetrics.runningGap,
            topBar: VolunteerOrderTopBar(
                surface: .onMap,
                onBack: onBack,
                isCloudHelp: VolunteerOrderSOSMode.resolve(status: order.status) == .cloud,
                isHelpBusy: coordinator.state.isBusy,
                onHelp: onHelp
            ),
            bottom: OrderFlowBottomActions(owner: .volunteer, primary: nil, secondary: AnyView(bottomControls), safetyHub: nil),
            header: header
        ) {
            // 整张卡一个读屏元素，沿用 v7 统计块的 identifier 与念法（UI 用例拿它判「进了跑步中页」）。
            BlindRunHeroCard(stats: stats, isFinished: false, spokenLabel: heroSpoken(hero))
                .accessibilityIdentifier("volunteerRunningStatsCard")
            // 同一时刻只有一条（`VolunteerRunningNotice`），放在彩色卡正下方。
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
            BlindRunPlanCard(plannedMeters: order.plannedDistanceMeters, stats: stats)
                .accessibilityIdentifier("volunteerRunPlanCard")
            VolunteerRunVoiceToggle()
            VolunteerRunRingCard(
                runnerName: order.runnerShortName,
                runnerNameSpoken: order.runnerShortName.unmaskedForSpeech,
                isRinging: isRinging,
                isEnabled: isRingEnabled && !isRinging,
                onRing: onRing
            )
            footer()
        }
        .animation(.easeInOut(duration: 0.25), value: notice)
        .animation(.easeInOut(duration: 0.25), value: isPaused)
    }

    // MARK: 标题

    /// 「陪跑中」+「和李*一起 · ● 定位正常」（定位说的是跑者位置收不收得到）。暂停时标题换成「已暂停 · 18:32」，
    /// 下面多一行「暂停期间不计志愿时长」。
    private var header: some View {
        let companion = BlindRunCardsCopy.companion(name: order.blindName?.nilIfBlank ?? order.runnerShortName)
        let spokenCompanion = "和\(order.runnerShortName.unmaskedForSpeech)一起跑步中"
        let freshness = isPeerLocationFresh ? BlindRunCopy.locationFresh : BlindRunCopy.locationStale
        return RunCardsHeader(
            title: isPaused ? VolunteerRunCopy.pausedTitle(elapsed: order.run?.elapsedClockText) : VolunteerRunningHero.title,
            companion: companion,
            isLocationFresh: isPeerLocationFresh,
            note: isPaused ? VolunteerRunCopy.pausedBody : nil
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            isPaused
                ? "\(VolunteerRunCopy.pausedTitle(elapsed: order.run?.elapsedClockText))，\(VolunteerRunCopy.pausedBody)。\(spokenCompanion)"
                : "\(spokenCompanion)。\(freshness)"
        )
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("volunteerRunningHeader")
    }

    /// 彩色卡的念法沿用 v7 统计块：「陪跑中，地点。已跑 … 时长 … 配速 … 目标进度」，暂停时前面先说暂停。
    private func heroSpoken(_ hero: VolunteerRunningHero) -> String {
        isPaused
            ? "\(VolunteerRunCopy.pausedTitle(elapsed: order.run?.elapsedClockText))，\(VolunteerRunCopy.pausedBody)。\(hero.accessibilityLabel)"
            : hero.accessibilityLabel
    }

    // MARK: 底部

    private var bottomControls: some View {
        VStack(spacing: 8) {
            // 暂停中本屏唯一的实心按钮（08 §五）；长按结束保持在它下面，退成灰底描边（一屏只有一枚实心）。
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
                style: isPaused ? .outline : .solid,
                onFinish: onFinish
            )
        }
        .animation(.easeInOut(duration: 0.25), value: isPaused)
    }
}
