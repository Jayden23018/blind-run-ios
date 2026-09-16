import SwiftUI

// MARK: - 跑步中（③）那张白卡的内容区

/// 设计交接 2026-09-16：**跑步中不是新页面，而是订单页原地变形。**
///
/// 所以这个类型不再是一屏，而是四步骨架（`BlindOrderFlowView`）那张状态卡在
/// `.running` 相位下的内容区 —— 上面是折叠后的「陪跑中 · 张伟」那一行，
/// 下面是骨架自己的两个按钮版位，两者都由骨架渲染。
///
/// 它只有三项数据：里程 / 时长 / 配速。**不加心率、卡路里、步频、地图。**
///
/// > 2026-09-16 之前它是一整屏深底白字的执行屏（产品定稿 2026-09-15），
/// > 与新设计的浅底白卡正面冲突，差一天。项目负责人当日拍板按新设计做，
/// > 并点名保留三件：① 顶行的定位新鲜度（在骨架的 `partnerRow` 上）；
/// > ② 求助失败 / 撤销求助那几个条件按钮（在 `BlindRunSafetyResultSection`）；
/// > ③「重复当前状态」（由主按钮「播报当前数据」承担，见 `PrimaryAction.announceStats`）。
/// > 三件都没有被删，只是换了落点。
struct BlindActiveRunView: View {
    let stats: TrackStats?

    var body: some View {
        VStack(spacing: 0) {
            distanceBlock
            secondaryBlock
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 26)
        .padding(.bottom, 24)
    }

    /// 里程。**全屏最大字号**，居中，等宽数字。
    private var distanceBlock: some View {
        VStack(spacing: 4) {
            Text(stats?.distanceKilometersText ?? "--")
                .flowFont(FlowFonts.runDistance(), monospacedDigit: true)
                .tracking(FlowMetrics.runDistanceTracking)
                .foregroundColor(AppColors.Flow.primaryText)
                // 设计稿 §23 给 AX5 的两条：裁掉这个数字等于裁掉这一屏本身，
                // 所以宁可缩到 70% 也不换行、不省略。
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(BlindRunCopy.distanceLabel)
                .flowFont(FlowFonts.runPrimaryLabel())
                .foregroundColor(AppColors.Flow.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        // 屏幕上是跑表体例（`3.20`），读屏念的是口语体例（`里程 3.20 公里`）——
        // 两套**不是重复**：`3.20` 单念出来没有单位，而这个数字是要被转述给别人的。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel(BlindRunCopy.distanceSpokenLabel, stats?.distanceText))
        .accessibilityIdentifier("blindActiveRunDistance")
    }

    /// 时长 / 配速两格，中间一条 1pt 竖分隔线。
    ///
    /// `ViewThatFits` 判的是**横向装不装得下**：默认字号走两列，字号放大到两列会挤
    /// （AX 档）就自动改竖排。写死两列的后果是 36pt 的等宽数字在 AX5 下互相压到一起，
    /// 而那是这一屏仅剩的两个数字。
    private var secondaryBlock: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                metric(BlindRunCopy.durationLabel, stats?.durationClockText, spoken: stats?.durationText)
                Rectangle()
                    .fill(AppColors.Flow.separator)
                    .frame(width: 1, height: FlowMetrics.runMetricDividerHeight)
                    .accessibilityHidden(true)
                metric(BlindRunCopy.paceLabel, stats?.paceClockText, spoken: stats?.averagePaceText)
            }
            VStack(spacing: 18) {
                metric(BlindRunCopy.durationLabel, stats?.durationClockText, spoken: stats?.durationText)
                metric(BlindRunCopy.paceLabel, stats?.paceClockText, spoken: stats?.averagePaceText)
            }
        }
        .padding(.horizontal, 16)
    }

    private func metric(_ label: String, _ value: String?, spoken: String?) -> some View {
        VStack(spacing: 4) {
            Text(value ?? "--")
                .flowFont(FlowFonts.runMetric(), monospacedDigit: true)
                .foregroundColor(AppColors.Flow.primaryText)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .flowFont(FlowFonts.runSecondaryLabel())
                .foregroundColor(AppColors.Flow.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel(label, spoken))
    }

    /// 拿不到数据时**说清是在获取，不念「杠杠」**。这一态的空态在契约里就是
    /// 「本次路线仍在采集，暂时没有足够的轨迹点」（`OrderTrackResponse.emptyStateText`），
    /// 不是错误 —— 刚起跑的头十几秒本来就没有足够的轨迹点。
    private func spokenLabel(_ label: String, _ value: String?) -> String {
        value.map { "\(label) \($0)" } ?? "\(label)，正在获取"
    }
}

// MARK: - 求助的结果面

/// 求助发出之后屏幕上该出现的东西：进行时 / 失败文案、失败后的拨号兜底、撤销本次求助。
///
/// 🔴 **三块都不是装饰。** 云端求助最坏路径是等定位 5 秒 + 请求超时 15 秒，按下到听见
/// 「未发出」最长 20 秒；那之后如果屏幕上没有任何**能按的东西**，用户就只剩一句 TTS ——
/// 而不开读屏的低视力用户屏幕上零变化（记忆 `claimed-fallback-may-not-exist-in-release`）。
/// 撤销权同理：`AGENTS.md` §6 规定撤销只在受助者本人和客服手里，盲人端不能没有这个入口。
///
/// 🚩 **必须自己 `@ObservedObject` 持有 coordinator。** `AppState.emergencyCoordinator`
/// 是 `let` 不是 `@Published`，从 `AppState` 上读 `.state` 读得到但**不会触发重绘** ——
/// 症状是求助失败之后这一块半天不出现，直到下一次 5 秒轮询碰巧刷新了整页
/// （记忆 `nested-observableobject-does-not-republish`）。
struct BlindRunSafetyResultSection: View {
    @ObservedObject var coordinator: EmergencyCoordinator
    /// 云端求助失败后的一跳拨号兜底。**不能让用户再走一遍「求助 → 菜单 → 拨号」。**
    let onLocalCall: () -> Void
    /// 本人撤销自己刚发出的求助（`PUT /api/emergency/{id}/cancel`）。
    let onCancelOwnEmergency: () -> Void

    var body: some View {
        // 三块同时为空时整个 `VStack` 不占高度，所以不需要外面再包一层条件 ——
        // 正常状态下这一段在屏幕上什么都不是。
        VStack(spacing: 10) {
            if let message = coordinator.state.message {
                EmergencyStatusNotice(message: message, isFailure: coordinator.state.isFailure)
            }

            // 判据直接读 `state.isFailure`，新增失败态自动进来。
            if coordinator.state.isFailure {
                FlowActionButton(
                    EmergencySafetyCopy.homeCallTitle,
                    style: .ghost,
                    accessibilityHint: EmergencySafetyCopy.cloudFailedCallAccessibilityHint,
                    action: onLocalCall
                )
                .accessibilityIdentifier("blindActiveRunFailureCallButton")
            }

            // 只有本人发出、且还没结束的求助才谈得上撤销。
            if coordinator.activeEvent != nil {
                FlowActionButton(
                    EmergencySafetyCopy.cancelButtonTitleForOwner,
                    style: .ghost,
                    accessibilityHint: "误触时撤销本次求助，需要确认",
                    action: onCancelOwnEmergency
                )
                .accessibilityIdentifier("blindActiveRunCancelEmergencyButton")
            }
        }
    }
}

// MARK: - Previews

#if DEBUG
extension TrackStats {
    /// Preview 共用的一组数字（设计稿 ③ 那一屏的取值：3.20 公里 / 21:04 / 6'30"）。
    static let previewRunning = TrackStats(
        distanceMeters: 3_204,
        durationSeconds: 1_264,
        avgPaceSecPerKm: 390
    )
}

#Preview("跑步中 · 内容区") {
    VStack {
        FlowCard {
            BlindActiveRunView(stats: .previewRunning)
        }
        FlowCard {
            BlindActiveRunView(stats: nil)
        }
    }
    .padding(FlowMetrics.pageHorizontalPadding)
    .frame(maxHeight: .infinity)
    .background(AppColors.Flow.page)
}

#Preview("跑步中 · 内容区 · AX5") {
    FlowCard {
        BlindActiveRunView(
            stats: TrackStats(distanceMeters: 12_804, durationSeconds: 5_264, avgPaceSecPerKm: 411)
        )
    }
    .padding(FlowMetrics.pageHorizontalPadding)
    .background(AppColors.Flow.page)
    .environment(\.dynamicTypeSize, .accessibility5)
}
#endif
