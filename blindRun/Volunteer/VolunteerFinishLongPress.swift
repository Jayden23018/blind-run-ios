import SwiftUI
import UIKit

// MARK: - 长按 2 秒结束陪跑

/// 「结束陪跑」那一枚按钮的全部具名落点：时长、震动节奏、按钮上的几句文字。
///
/// **为什么不复用 `SafetyLongPressGesture`**（`Safety/SafetyHubView.swift:445`，求助那条长按 3 秒）：
/// 四处对不上，且没有一处是加个参数能抹平的 ——
/// ① 时长写死在 `SafetyLongPress.duration`（3 秒），这里是 2 秒；
/// ② 它只回调「按下 / 松开」两个瞬间，**不给进度**，而填充进度与「还剩 0.8 秒」
///    要的正是按住过程中的连续读数；
/// ③ 它必须同时挂一条轻点路径（求助轻点＝走二次确认），而这里**刻意没有轻点**：
///    结束即不可撤销，长按本身就是那道确认（设计包 `状态清单.md` §11 逐字如此）；
/// ④ 那个文件同时被 `AGENTS.md` §6 的求助红线用着。
/// 复用的唯一办法是给它加进度回调 + 可变时长 + 可选轻点，等于为了省这几十行去改一个红线文件。
enum VolunteerFinishLongPress {
    /// 2 秒。**屏幕上印的那个数字由它生成**，不另写字面量 —— 分开写就会有一天对不上，
    /// 而对不上的表现是「说好按 2 秒，按了 2 秒没反应」。
    static let duration: TimeInterval = 2

    /// 读秒与填充的刷新间隔。20Hz —— 比读秒的精度（0.1 秒）快一档就够。
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

    /// 没按住时按钮上那一行（v2 画布 ⑤：「长按 2 秒，结束陪跑」）。
    static var idleTitle: String { "长按 \(durationText) 秒，\(title)" }

    /// 按满之后、后端还没回来那几百毫秒的文字。
    /// 不留着「还剩 0.1 秒」：那句话在请求已经发出之后是**假的**。
    static let submittingTitle = "正在结束本次陪跑"

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

    /// 按住过程中按钮上那一行（v2 画布「长按结束陪跑」：「继续按住，还剩 1 秒」，精度仍是 0.1 秒）。
    static func holdingTitle(elapsed: TimeInterval) -> String {
        "继续按住，还剩 \(remainingText(elapsed: elapsed)) 秒"
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

    /// 填充进度 0…1。超时钳在 1：触发与最后一次读秒之间有几毫秒空当，
    /// 那几毫秒里填充不该越过满格。
    static func progress(elapsed: TimeInterval) -> Double {
        min(1, max(0, elapsed / duration))
    }

    /// 按钮底色**该填**多少。🔴 **不是直接读 `elapsed`。**
    ///
    /// 触发之后 `elapsed` 停在满格，而结束请求失败时按钮会回到可按状态
    /// （`VolunteerOrderTransitionState.failed.blocksDuplicateSubmission == false`，
    /// `isPerformingAction` 也经 `defer` 归回 false），于是屏幕上会留下
    /// **「整枚填满 + 文字说『长按 2 秒』」** 这种自相矛盾的样子，且会一直留着。
    ///
    /// 对不开读屏的低视力志愿者，填满是「已经结束了」唯一的视觉读数 ——
    /// 而那一刻订单其实还在跑。所以：没按住、也没在提交，就必须是 0。
    static func fillProgress(elapsed: TimeInterval, isHolding: Bool, hasFired: Bool) -> Double {
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

/// 陪跑员端结束服务的**唯一**入口：按满 2 秒才结束，松手即取消（填充归零、不播报、无提示）。
///
/// 🔴 **没有轻点路径。** `POST /api/orders/{id}/finish` 之后不可撤销，所以这里不给
/// 「按一下弹个确认框」那种入口 —— 长按本身就是确认，多一个弹框只会让人习惯性点掉。
///
/// 外观（2026-11-12 起，#972）：订单页底部那枚藏青胶囊（同 `BlindOrderStageButton`，负责人「藏青，开始改」），
/// 按住时从左往右填成跑步中彩色卡的青绿。暂停中「继续跑步」是实心，这枚退成灰底描边（一屏只有一枚实心），
/// 按住时填成浅藏青。
/// 「减弱动态效果」下**不需要分档**：这枚按钮全程没有位移与缩放，填充是**信息**
/// （还差多久）不是装饰，两种设置下一模一样。
struct VolunteerFinishLongPressButton: View {
    enum Style { case solid, outline }

    let isPerformingAction: Bool
    let isEnabled: Bool
    var style: Style = .solid
    let onFinish: () -> Void

    @State private var elapsed: TimeInterval = 0
    @State private var holdTask: Task<Void, Never>?
    /// 渐强那一路用的生成器。**存下来是为了给 `fire()` 复用同一个已 `prepare()` 的实例** ——
    /// 新建一个再立刻 `impactOccurred` 常被系统丢掉（理由见 `startHold` 里那段注释），
    /// 而触发那一记正是「成了，可以松手」唯一的触觉信号，最不能丢的就是它。
    @State private var generator: UIImpactFeedbackGenerator?
    /// 走满 2 秒那一刻 SwiftUI 也会送来一次「松手了」。没有这个标志位，
    /// 松手那条分支会把填充立刻归零 —— 用户按到底看到的是进度条弹回去。
    @State private var didFire = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: AppButtonMetrics.cornerRadius, style: .continuous)
        HStack(spacing: 8) {
            if isPerformingAction {
                ProgressView().tint(ink)
            } else {
                Image(systemName: "clock")
                    .font(.system(size: 17, weight: .bold))
                    .accessibilityHidden(true)
            }
            Text(label)
                .flowFont((16, .bold, .callout), monospacedDigit: true)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundColor(ink)
        .padding(.vertical, AppButtonMetrics.labelVerticalPadding)
        .padding(.horizontal, AppButtonMetrics.labelHorizontalPadding)
        .frame(maxWidth: .infinity)
        .frame(minHeight: AppButtonMetrics.visibleHeight)
        .background(alignment: .leading) {
            // 底色 + 从左往右的填充：填充是「还差多久」唯一的视觉读数。
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    base
                    progressFill.frame(width: proxy.size.width * fill)
                }
            }
        }
        .clipShape(shape)
        .overlay {
            if style == .outline {
                shape.strokeBorder(AppColors.ButtonPalette.neutralStroke, lineWidth: AppButtonMetrics.strokeWidth)
            }
        }
        .opacity(isEnabled ? 1 : 0.5)
        // 胶囊看得见的部分 52pt，上下左右留透明可点区凑足 64pt（同 `capsuleButtonChrome`）。
        .padding(.horizontal, AppButtonMetrics.horizontalInset)
        .padding(.vertical, AppButtonMetrics.verticalInset)
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
        // 失败后按钮回到可按状态，填充必须跟着回到 0，否则它在说一件没发生的事。
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

    private var ink: Color { style == .solid ? .white : AppColors.Flow.primaryText }

    private var base: Color { style == .solid ? AppColors.Flow.navy : AppColors.ButtonPalette.neutralFill }

    /// 实心：跑步中彩色卡的青绿（白字压它 6.7:1）；描边：浅藏青，深字照样看得清。
    private var progressFill: Color {
        style == .solid ? BlindRunCardsPalette.runningBottom : AppColors.Flow.navy.opacity(0.18)
    }

    private var label: String {
        if isPerformingAction { return VolunteerFinishLongPress.submittingTitle }
        guard holdTask != nil else { return VolunteerFinishLongPress.idleTitle }
        return VolunteerFinishLongPress.holdingTitle(elapsed: elapsed)
    }

    private var fill: Double {
        VolunteerFinishLongPress.fillProgress(elapsed: elapsed, isHolding: holdTask != nil, hasFired: didFire)
    }

    private func pressingChanged(_ pressing: Bool) {
        guard pressing else {
            cancelHold()
            // 松手即取消：填充归零，**一个字都不多说**。没按满 2 秒什么都没发生过，
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
