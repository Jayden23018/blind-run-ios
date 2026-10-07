import SwiftUI

// MARK: - 跑步中加进旧页的新能力（DECISIONS-v2 V4–V8、V11；交付包 08 §二–§五）
//
// 挂在 #227 的 v2 跑步页 `VolunteerRunningPage` 上（V4 原定「旧页不动」，负责人 09-26 改为整页换 v2，
// 本变更随之移植）。这里只放**加进去**的东西：提示条、耳机语音播报开关、跑步中求助面板。
// 节奏卡 / 信号卡 2026-10-07 随跑者端节奏按钮一起删除（OpenSpec `redesign-blind-runner-screens-a`）。
// 判定都是纯函数，用例在 `RunningRhythmAndHelpTests`。

enum VolunteerRunCopy {
    static let voiceToggleTitle = "耳机语音播报"
    static let voiceToggleSubtitle = "每 1 公里播报一次里程和用时"
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
    /// 走散时让跑者手机响（后端 #445 起跑步中可按，推翻 DECISIONS-v2 V5 / V12 的「跑步中响铃不做」）。
    static func ringRowTitle(_ name: String) -> String { "让\(name)的手机响起来" }
    /// 只说这一按是做什么的，不说「对方会听到」：送没送到看接口的 `delivered`，没送到另有提示。
    static let ringRowSubtitle = "走散时用 · 请对方原地停下，你循着铃声找过去"
    static let ringingRowTitle = "正在响铃…"
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
    static let navButtonHint = "打开求助面板：暂停、让对方手机响、联系客服或紧急求助"
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

/// 跑步页头卡下面那**一条**提示：#227 的两条（跑者求助已确认 / 收不到跑者位置）与本变更的三条合成一个队列。
///
/// 顺序：已确认的求助（他还在求助，只是有人接手了）> 走散 > 收不到跑者位置 > 跑者电量低 > 本机定位弱。
/// 走散排在「收不到位置」前面：走散说的是「能定位但太远」，是更具体、更要立刻处理的那一个。
enum VolunteerRunningNotice: Equatable {
    /// 头卡自带的那一条（`VolunteerRunningHero.notice`）。
    case hero
    case tip(VolunteerRunTip)

    static func resolve(isPeerAlertAcknowledged: Bool, heroHasNotice: Bool, tip: VolunteerRunTip?) -> Self? {
        if isPeerAlertAcknowledged, heroHasNotice { return .hero }
        if tip == .separated { return .tip(.separated) }
        if heroHasNotice { return .hero }
        return tip.map { .tip($0) }
    }
}

// MARK: - 耳机语音播报开关

enum VolunteerRunVoiceBroadcast {
    /// 本地设置，跨订单保留，默认关（08 §二）。
    static let defaultsKey = "volunteerRunVoiceBroadcastEnabled"
}

struct VolunteerRunVoiceToggle: View {
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
                    Text(VolunteerRunCopy.voiceToggleSubtitle)
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
    /// 后端 `ringingUntil`。之前这一行不可点（同汇合期的响铃按钮）。
    let ringingUntil: Date?
    let onPause: () -> Void
    let onRing: () -> Void
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
                ringRow
                supportRow
                emergencyButton
                    .padding(.top, 4)

                // frame 要挂在 label 里面：挂在 Button 外面只撑大布局，不撑大点击区（真机审计报过 18pt）。
                Button { dismiss() } label: {
                    Text(VolunteerRunCopy.dismiss)
                        .flowFont(FlowV2Fonts.callout(bold: true))
                        .foregroundColor(AppColors.Flow.accent)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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

    /// 按下先收起面板：陪跑员接下来要抬头找人，回执（「正在响」/「对方可能没收到」）落在跑步页上。
    private var ringRow: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let isRinging = (ringingUntil ?? .distantPast) > context.date
            row(
                systemImage: "bell.and.waves.left.and.right.fill",
                title: isRinging ? VolunteerRunCopy.ringingRowTitle : VolunteerRunCopy.ringRowTitle(runnerName),
                subtitle: VolunteerRunCopy.ringRowSubtitle,
                isBusy: false,
                isEnabled: !isRinging,
                identifier: "volunteerRunHelpRing"
            ) {
                dismiss()
                onRing()
            }
        }
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
                    // 不写「SOS」文字：固定字号过不了 Dynamic Type 审计（真机报过），而这里只是装饰。
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14, weight: .bold))
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
