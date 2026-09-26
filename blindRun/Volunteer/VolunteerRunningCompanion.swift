import SwiftUI

// MARK: - 跑步中加进旧页的新能力（DECISIONS-v2 V4–V8、V11；交付包 08 §二–§五）
//
// 旧跑步页布局不动（三数字卡、长按 2 秒结束）。这里只放**加进去**的东西：
// 节奏卡 / 信号卡、提示条、耳机语音播报开关、暂停灰条、跑步中求助面板。
// 判定都是纯函数，用例在 `RunningRhythmAndHelpTests`。

enum VolunteerRunCopy {
    static func rhythmLabel(_ name: String) -> String { "\(name)的节奏" }
    static let staleLabel = "上次反馈"
    static func noRhythmYet(_ name: String) -> String { "\(name)还没有发来节奏" }
    static func signalTitle(_ name: String, _ signal: String) -> String { "\(name)：\(signal)" }
    static let signalSubtitle = "刚刚 · 已震动两下提醒你"
    static func spokenSignal(_ name: String, _ signal: String) -> String { "\(name)说：\(signal)" }

    static let voiceToggleTitle = "耳机语音播报"
    static func voiceToggleSubtitle(_ name: String) -> String { "每 1 公里，以及\(name)的节奏信号" }
    static func kilometerAnnouncement(km: Int, duration: String) -> String { "\(km) 公里，用时 \(duration)" }

    static func separatedTitle(_ name: String) -> String { "你和\(name)好像走散了" }
    static let separatedBody = "先确认对方在身边。"
    static func batteryLowTitle(_ name: String) -> String { "\(name)的手机电量低" }
    static let batteryLowBody = "跑完记得提醒对方充电。"
    static let weakLocationTitle = "定位信号弱"
    static let weakLocationBody = "距离暂时可能不准，信号恢复后会校正。"

    static func pausedTitle(elapsed: String?) -> String {
        elapsed.map { "已暂停 · 计时停在 \($0)" } ?? "已暂停"
    }
    /// 🔴 不写「客服已收到通知」：暂停通知客服是后端的事，客户端拿不到送达结果（design.md D6）。
    static let pausedBody = "暂停期间不计志愿时长"
    static let resume = "继续陪跑"
    static let pausedSpoken = "已暂停计时"
    static let resumedSpoken = "继续陪跑，计时已恢复"

    // 求助面板
    static let helpTitle = "需要帮助？"
    static let helpSubtitle = "打开这里不会暂停计时"
    static func pauseRowTitle(_ name: String) -> String { "\(name)需要停下来" }
    /// 不写「并告知客服」：暂停后通知客服是后端的事（V8），客户端核实不了（同 `pausedBody`）。
    static let pauseRowSubtitle = "暂停计时，暂停期间不计志愿时长"
    static let supportRowTitle = "联系客服"
    /// 「不是紧急求助」打头：它和紧急按钮并排，工单不是即时通道（同 `SupportTicketCopy.notice` 的顾虑）。
    static let supportRowSubtitle = "不是紧急求助 · 提交后客服会尽快联系你"
    static let supportSubmittedTitle = "已提交"
    static let supportSubmitted = "客服会尽快联系你"
    static let supportFailed = "没有提交成功，再点一次重试"
    /// 固定内容：跑步中一只手握着引导绳，填不了表（design.md D5）。
    static let supportTicketContent = "跑步中，陪跑员请求客服联系。"
    static let emergencyTitle = "长按 3 秒，紧急求助"
    /// 🔴 不承诺任何人已收到（V6）。当前只附带陪跑员自己这台手机的位置（`locate` 取的是本机）。
    static let emergencySubtitle = "求助会附带你的当前位置"
    static func emergencyHolding(remaining: Int) -> String { "继续按住，还剩 \(remaining) 秒" }
    static let emergencyAccessibilityHint = "双击会先弹出确认框，确认后才发出"
    static let dismiss = "没事了，继续跑"

    static let navButtonLabel = "求助与安全"
    static let navButtonHint = "打开求助面板：暂停、联系客服或紧急求助"
}

// MARK: - 节奏卡

struct VolunteerRhythmCardPresentation: Equatable {
    enum Style: Equatable { case empty, fresh, stale, signal(RunRhythmSignal) }

    /// 过期：距上次信号超过 5 分钟（08 §二）。
    static let staleAfter: TimeInterval = 5 * 60
    /// 信号卡保持 8 秒（08 §三）。
    static let highlightDuration: TimeInterval = 8

    let style: Style
    let label: String
    let title: String
    let trailing: String?

    var spoken: String {
        [label, title, trailing].compactMap { $0 }.joined(separator: "，")
    }

    static func make(run: RunView?, name: String, highlightUntil: Date?, now: Date) -> Self {
        guard let signal = run?.lastSignal, let text = signal.title else {
            return .init(style: .empty, label: VolunteerRunCopy.rhythmLabel(name), title: VolunteerRunCopy.noRhythmYet(name), trailing: nil)
        }
        if let highlightUntil, now < highlightUntil, signal != .ok {
            return .init(
                style: .signal(signal),
                label: VolunteerRunCopy.signalSubtitle,
                title: VolunteerRunCopy.signalTitle(name, text),
                trailing: nil
            )
        }
        let at = run?.lastSignalAt?.backendTimestamp
        let age = at.map { max(0, now.timeIntervalSince($0)) }
        if let age, age > staleAfter {
            return .init(style: .stale, label: VolunteerRunCopy.staleLabel, title: text, trailing: agoText(age))
        }
        return .init(style: .fresh, label: VolunteerRunCopy.rhythmLabel(name), title: text, trailing: age.map(agoText))
    }

    static func agoText(_ age: TimeInterval) -> String {
        age < 60 ? "刚刚" : "\(Int(age / 60)) 分钟前"
    }
}

/// 信号到达判定。**推送只当刷新信号**，到达从 `run.lastSignalAt` 的变化推出来（design.md D1）。
enum RunSignalArrival {
    /// 比这更旧的「新值」不提醒：切回前台补拉到的旧信号不是「刚刚」。
    static let freshness: TimeInterval = 30

    static func detect(previous: OrderDetailResponse?, updated: OrderDetailResponse, now: Date) -> RunRhythmSignal? {
        // 首次加载只显示不提醒（08：冷启动能恢复，但不是新到达）。
        guard let previous, previous.orderId == updated.orderId, updated.status == .inProgress,
              let signal = updated.run?.lastSignal, signal != .unknown,
              let rawAt = updated.run?.lastSignalAt?.nilIfBlank,
              rawAt != previous.run?.lastSignalAt,
              let at = rawAt.backendTimestamp,
              abs(now.timeIntervalSince(at)) <= freshness else { return nil }
        return signal
    }
}

struct VolunteerRhythmCard: View {
    let presentation: VolunteerRhythmCardPresentation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let titleFont: FlowV2Fonts.Spec = (18, .heavy, .headline)
    private static let signalTitleFont: FlowV2Fonts.Spec = (22, .heavy, .title3)

    private var signal: RunRhythmSignal? {
        if case .signal(let signal) = presentation.style { return signal }
        return nil
    }

    var body: some View {
        HStack(spacing: 14) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                if signal == nil {
                    Text(presentation.label)
                        .flowFont(FlowV2Fonts.subhead())
                        .foregroundColor(AppColors.Flow.secondaryText)
                }
                Text(presentation.title)
                    .flowFont(signal == nil ? Self.titleFont : Self.signalTitleFont)
                    .foregroundColor(titleColor)
                if signal != nil {
                    Text(presentation.label)
                        .flowFont(FlowV2Fonts.subhead(bold: true))
                        .foregroundColor(AppColors.Flow.onCTA)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            if let trailing = presentation.trailing {
                Text(trailing)
                    .flowFont(FlowV2Fonts.subhead())
                    .foregroundColor(AppColors.Flow.secondaryText)
            }
        }
        .padding(16)
        .background(signal == nil ? AppColors.Flow.surface : AppColors.Flow.cta)
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(signal == nil ? Color.clear : AppColors.Flow.ctaStroke, lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        // 减弱动态效果：只留颜色过渡（08 §六），高度与缩放不动。
        .animation(reduceMotion ? .easeInOut(duration: 0.25) : .spring(response: 0.35, dampingFraction: 0.85), value: presentation.style)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.spoken)
        .accessibilityIdentifier("volunteerRunRhythmCard")
    }

    private var titleColor: Color {
        if signal != nil { return AppColors.Flow.onCTA }
        return presentation.style == .stale ? AppColors.Flow.secondaryText : AppColors.Flow.primaryText
    }

    @ViewBuilder
    private var icon: some View {
        if let signal {
            Image(systemName: signal == .slower ? "arrow.down" : signal == .faster ? "arrow.up" : "checkmark")
                .font(.system(size: 20, weight: .heavy))
                .foregroundColor(AppColors.Flow.onCTA)
                .frame(width: 48, height: 48)
                .background(Circle().fill(Color.black.opacity(0.1)))
                .accessibilityHidden(true)
        } else {
            Circle()
                .fill(presentation.style == .stale ? AppColors.Flow.decorMutedInk : AppColors.Flow.accent)
                .frame(width: 10, height: 10)
                .frame(width: 40, height: 40)
                .background(Circle().fill(AppColors.Flow.blueTint))
                .accessibilityHidden(true)
        }
    }
}

// MARK: - 提示条

enum VolunteerRunTip: Equatable {
    case separated, runnerBatteryLow, weakLocation

    /// 走散提示显示多久。现有 `ESCORT_DISTANCE_ALERT` 是一次性事件、没有「已恢复」（V7），
    /// 所以跟前台横幅一样按时间收起，不自己算距离（design.md D3）。
    static let separationDisplay: TimeInterval = 60
    static let weakAccuracyMeters: Double = 50
    static let weakSustain: TimeInterval = 20

    /// 同一时刻只显示优先级最高的一条（08 §五）。
    static func resolve(separationAlertAt: Date?, runnerBatteryLow: Bool, weakLocationSince: Date?, now: Date) -> Self? {
        if let at = separationAlertAt, now.timeIntervalSince(at) < separationDisplay { return .separated }
        if runnerBatteryLow { return .runnerBatteryLow }
        if let since = weakLocationSince, now.timeIntervalSince(since) >= weakSustain { return .weakLocation }
        return nil
    }

    /// 本机定位精度的持续判定：精度差于阈值时记下开始时刻，恢复就清掉。`nil` 精度不改变状态。
    static func weakSince(previous: Date?, accuracy: Double?, now: Date) -> Date? {
        guard let accuracy else { return previous }
        return accuracy > weakAccuracyMeters ? (previous ?? now) : nil
    }
}

struct VolunteerRunTipBar: View {
    let tip: VolunteerRunTip
    let name: String

    private var copy: (title: String, body: String) {
        switch tip {
        case .separated: return (VolunteerRunCopy.separatedTitle(name), VolunteerRunCopy.separatedBody)
        case .runnerBatteryLow: return (VolunteerRunCopy.batteryLowTitle(name), VolunteerRunCopy.batteryLowBody)
        case .weakLocation: return (VolunteerRunCopy.weakLocationTitle, VolunteerRunCopy.weakLocationBody)
        }
    }

    private var colors: (background: Color, foreground: Color) {
        switch tip {
        case .separated: return (AppColors.Flow.helpBackground, AppColors.Flow.helpText)
        case .runnerBatteryLow: return (AppColors.Flow.warmCard, AppColors.Flow.warmCardTitle)
        case .weakLocation: return (AppColors.Flow.surfaceSubtle, AppColors.Flow.primaryText)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(copy.title).flowFont(FlowV2Fonts.callout(bold: true))
            Text(copy.body).flowFont(FlowV2Fonts.subhead())
        }
        .foregroundColor(colors.foreground)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(colors.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("volunteerRunTipBar")
    }
}

// MARK: - 耳机语音播报开关

enum VolunteerRunVoiceBroadcast {
    /// 本地设置，跨订单保留，默认关（08 §二）。
    static let defaultsKey = "volunteerRunVoiceBroadcastEnabled"
}

struct VolunteerRunVoiceToggle: View {
    let name: String
    @AppStorage(VolunteerRunVoiceBroadcast.defaultsKey) private var isOn = false

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                Image(systemName: "speaker.wave.2.fill")
                    .foregroundColor(AppColors.Flow.accent)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(VolunteerRunCopy.voiceToggleTitle)
                        .flowFont(FlowV2Fonts.callout(bold: true))
                        .foregroundColor(AppColors.Flow.primaryText)
                    Text(VolunteerRunCopy.voiceToggleSubtitle(name))
                        .flowFont((13, .regular, .footnote))
                        .foregroundColor(AppColors.Flow.secondaryText)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(minHeight: FlowMetrics.actionButtonMinHeight)
        .background(AppColors.Flow.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(AppColors.Flow.ghostStroke, lineWidth: 1)
        )
        .accessibilityIdentifier("volunteerRunVoiceToggle")
    }
}

// MARK: - 暂停灰条

struct VolunteerRunPausedStrip: View {
    let elapsedText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(VolunteerRunCopy.pausedTitle(elapsed: elapsedText))
                .flowFont(FlowV2Fonts.callout(bold: true), monospacedDigit: true)
            Text(VolunteerRunCopy.pausedBody)
                .flowFont(FlowV2Fonts.subhead())
        }
        .foregroundColor(.white)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppColors.Flow.statePaused, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("volunteerRunPausedStrip")
    }
}

// MARK: - 跑步中求助面板（V5 / V6）

enum VolunteerSupportRequestState: Equatable { case idle, submitting, submitted, failed }

/// 跑步中右上角「求助」打开的面板。**其他状态的「求助」不走这里**（它们在 v2 页面上本地拨号）。
///
/// 🔴 紧急按钮：长按 3 秒直接走现有云端链路；轻点与读屏双击弹 `AGENTS.md` §6 锁定文案的确认框。
/// 与跑者端求助中心同一套手势（`safetyLongPress`）。**不给读屏「立即求助」自定义动作**：
/// V6 要求读屏走确认框。陪跑员没有撤销入口（§6），所以不走可撤回的倒计时（design.md D4）。
struct VolunteerRunHelpPanel: View {
    @ObservedObject var coordinator: EmergencyCoordinator
    let runnerName: String
    let isPaused: Bool
    let isTogglingPause: Bool
    let supportState: VolunteerSupportRequestState
    let onPause: () -> Void
    let onContactSupport: () -> Void
    let onEmergency: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showsConfirm = false
    @State private var pressStartedAt: Date?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(VolunteerRunCopy.helpTitle)
                        .flowFont((24, .heavy, .title2))
                        .foregroundColor(AppColors.Flow.primaryText)
                        .accessibilityAddTraits(.isHeader)
                    Text(VolunteerRunCopy.helpSubtitle)
                        .flowFont(FlowV2Fonts.callout())
                        .foregroundColor(AppColors.Flow.secondaryText)
                }
                .padding(.bottom, 8)

                if !isPaused {
                    row(
                        systemImage: "pause.circle.fill",
                        title: VolunteerRunCopy.pauseRowTitle(runnerName),
                        subtitle: VolunteerRunCopy.pauseRowSubtitle,
                        isBusy: isTogglingPause,
                        identifier: "volunteerRunHelpPause"
                    ) {
                        dismiss()
                        onPause()
                    }
                }
                supportRow
                emergencyButton
                    .padding(.top, 4)

                Button(VolunteerRunCopy.dismiss) { dismiss() }
                    .flowFont(FlowV2Fonts.callout(bold: true))
                    .foregroundColor(AppColors.Flow.accent)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityIdentifier("volunteerRunHelpDismiss")
            }
            .padding(EdgeInsets(top: 24, leading: 24, bottom: 34, trailing: 24))
        }
        .background(AppColors.Flow.surface)
        .emergencyConfirmationAlert(isPresented: $showsConfirm, audience: .volunteer) {
            dismiss()
            onEmergency()
        }
        .accessibilityIdentifier("volunteerRunHelpPanel")
    }

    private var supportRow: some View {
        let submitted = supportState == .submitted
        return row(
            systemImage: submitted ? "checkmark.circle.fill" : "phone.circle.fill",
            title: submitted ? VolunteerRunCopy.supportSubmittedTitle : VolunteerRunCopy.supportRowTitle,
            subtitle: submitted
                ? VolunteerRunCopy.supportSubmitted
                : supportState == .failed ? VolunteerRunCopy.supportFailed : VolunteerRunCopy.supportRowSubtitle,
            subtitleIsProblem: supportState == .failed,
            isBusy: supportState == .submitting,
            isEnabled: !submitted,
            identifier: "volunteerRunHelpSupport",
            action: onContactSupport
        )
    }

    private func row(
        systemImage: String,
        title: String,
        subtitle: String,
        subtitleIsProblem: Bool = false,
        isBusy: Bool,
        isEnabled: Bool = true,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Group {
                    if isBusy { ProgressView() } else { Image(systemName: systemImage).font(.system(size: 28)) }
                }
                .foregroundColor(AppColors.Flow.accent)
                .frame(width: 36)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .flowFont(FlowV2Fonts.headline())
                        .foregroundColor(AppColors.Flow.primaryText)
                    Text(subtitle)
                        .flowFont(FlowV2Fonts.subhead())
                        .foregroundColor(subtitleIsProblem ? AppColors.Flow.helpText : AppColors.Flow.secondaryText)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 72)
            .background(AppColors.Flow.surfaceSubtle, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isBusy || !isEnabled)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }

    private var emergencyButton: some View {
        TimelineView(.periodic(from: .now, by: 0.2)) { context in
            let elapsed = pressStartedAt.map { context.date.timeIntervalSince($0) }
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.35), lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: min(1, (elapsed ?? 0) / SafetyLongPress.duration))
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("SOS").font(.system(size: 11, weight: .heavy))
                }
                .frame(width: 36, height: 36)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(elapsed.map {
                        VolunteerRunCopy.emergencyHolding(remaining: max(1, Int((SafetyLongPress.duration - $0).rounded(.up))))
                    } ?? VolunteerRunCopy.emergencyTitle)
                        .flowFont((18, .heavy, .headline), monospacedDigit: true)
                    Text(VolunteerRunCopy.emergencySubtitle)
                        .flowFont((13, .regular, .footnote))
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .frame(minHeight: 72)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(AppColors.Flow.helpText.opacity(pressStartedAt == nil ? 1 : 0.8))
            )
        }
        .safetyLongPress(
            onTap: { showsConfirm = true },
            onLongPress: {
                dismiss()
                onEmergency()
            },
            onPressingChanged: { pressStartedAt = $0 ? Date() : nil }
        )
        .disabled(coordinator.state.isBusy)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("\(VolunteerRunCopy.emergencyTitle)，\(VolunteerRunCopy.emergencySubtitle)")
        .accessibilityHint(VolunteerRunCopy.emergencyAccessibilityHint)
        // 读屏双击 = 确认框，不是直接发（V6）。显式挂上，不赌 SwiftUI 把激活映射到哪个手势。
        .accessibilityAction { showsConfirm = true }
        .accessibilityIdentifier("volunteerRunHelpEmergency")
    }
}
