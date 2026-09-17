import SwiftUI

// MARK: - 阈值

/// 滑动开启「可服务」的判定。
///
/// 抽成纯函数而不是写在手势回调里：这是整个控件**唯一一处会悄悄坏掉**的地方 ——
/// 阈值改错了控件照常能用，只是变难（或变得一碰就开），没有任何运行时信号。
///
/// 依据是 Uber Base Design System 的 Sliding button 规格（原文见
/// `docs/research/volunteer-profile-first-screen-20260914.md` §3）：
///
/// | Threshold | Value |
/// |---|---|
/// | Low (Easy) | "Complete more than 20%" |
/// | High (Hard) | "Complete more than 80%" |
///
/// 🔴 **取 Low (Easy)。** 同页的无障碍告警逐字写着：要求高交互精度的动作
/// "proves difficult to users with physical and motor disabilities, as well as seniors"。
/// 我们的志愿者里有大量中老年人，High 那一档是在给他们设障。
enum VolunteerAvailabilitySlide {
    /// 滑过轨道的这个比例即触发。**不要往上调** —— 理由见类型注释。
    static let activationFraction: CGFloat = 0.2

    /// 滑块相对起点的实际位移，钳在 `0...trackWidth`。
    ///
    /// 非有限值（布局还没算出来时 `GeometryReader` 会给 NaN）一律当 0，
    /// 与 `VolunteerHomeTopLayout` 那批 `isFinite` 守卫同一个理由：
    /// 一个 NaN 会把滑块画到屏幕外，而屏幕上看起来只是「滑块不见了」。
    static func travel(dragX: CGFloat, trackWidth: CGFloat) -> CGFloat {
        guard dragX.isFinite, trackWidth.isFinite, trackWidth > 0 else { return 0 }
        return min(max(dragX, 0), trackWidth)
    }

    /// 松手时该不该真的开启。
    static func activates(dragX: CGFloat, trackWidth: CGFloat) -> Bool {
        guard trackWidth > 0 else { return false }
        return travel(dragX: dragX, trackWidth: trackWidth) / trackWidth >= activationFraction
    }

    /// 已滑过的比例，给轨道高亮用（0...1）。
    static func progress(dragX: CGFloat, trackWidth: CGFloat) -> CGFloat {
        guard trackWidth > 0 else { return 0 }
        return travel(dragX: dragX, trackWidth: trackWidth) / trackWidth
    }
}

// MARK: - 文案

/// 滑动 CTA 的文案挂在 `VolunteerAvailabilityCopy` 上（`VolunteerHomeView.swift:15`），
/// 不另起一个 enum —— 那个类型存在的全部理由就是「这个开关在全 App 只有一个名字」。
extension VolunteerAvailabilityCopy {
    /// 静止态。是**邀请**不是指令 —— 志愿者是无偿的，命令句式属于 controlling 型激励
    /// （Motivation Crowding，`docs/research/volunteer-home-incentive-layer-20260914.md` §3.2）。
    static let slideToOpenTitle = "滑动开始今天的陪跑"

    /// 拖过阈值之后。
    static let slideReleaseToOpenTitle = "松手即开启"

    /// 已开启时轨道上那半句。这一刻起才会收到派单推送，所以说的是「等待」而不是「已完成」。
    static let availableStatusTitle = "已开启"

    /// 关闭侧的动作名。**不得带任何激励挽留**。
    ///
    /// 🔄 **2026-09-17 由项目负责人推翻了这条红线的前半句。** 原文是「关闭是**普通点按**，
    /// 且**不得弹任何激励挽留**……摩擦力只加在「答应」这一侧」，现在关闭改成**向左滑**，
    /// 与开启对称。**后半句仍然有效且是硬约束**：
    ///
    /// Uber 在司机点下线时弹当日收入目标劝其继续，被 NYT 点名、在 gig 平台设计分类法里
    /// 归入 dark pattern。**左滑不是挽留** —— 它不问「确定吗」、不摆成绩、不弹任何对话框，
    /// 只是把两个方向做成同一种手势。同一条红线仍以注释钉在
    /// `VolunteerHomeIncentive.swift:99-107`，那一侧别绕过去。
    ///
    /// 机器守卫两条：`VolunteerProfileFirstScreenTests.testCloseCopyDoesNotBargain`
    /// （文案里不许出现挽留话术）、`AccessibilityAuditTests` 那条拖拽用例里的
    /// `XCTAssertEqual(app.alerts.count, 0)`（关闭路径上不许有任何对话框）。
    static let closeTitle = "今天先不跑了"

    /// 关闭方向拖过阈值之后。与 `slideReleaseToOpenTitle` 对称。
    static let slideReleaseToCloseTitle = "松手即结束"

    static let slideHint = "向右滑动开启，开启后才会收到系统派单。开启不影响你当前的订单"
    static let closeHint = "关闭后不会收到新的系统派单，但不影响当前订单"
}

// MARK: - 控件

/// 首屏底部的「可服务」滑动 CTA。
///
/// 🚩 **它绑的是 `setAvailability(_:)`，不是导航。** Uber Base 同页的 Caution 逐字写着
/// "If the action is not critical, a sliding button may be unnecessary and may add
/// unnecessary complexity to the interface" —— 滑动只有绑在一个**真有后果**的动作上才立得住，
/// 而「从这一刻起开始收派单」正是那种动作。
struct VolunteerAvailabilitySlider: View {
    /// 滑块与轨道之间的留白。滑块直径 = 轨道高 − 2×这个数。
    private static let knobInset: CGFloat = 5

    /// 轨道高度的上限。
    ///
    /// 🔴 **`@ScaledMetric` 必须封顶，否则 AX5 下这条 CTA 会吃掉半屏。**
    /// `.body` 在 AX5 是 53pt（默认 17pt，约 3.12×，见
    /// `docs/research/dynamic-type-scale-20260812.md`）⇒ 不封顶算出来是 **200pt**，
    /// 滑块跟着变成一个 190pt 的圆。iPhone 横屏视口只有约 393pt，
    /// 首屏的「需要你处理」（带 60 分钟到期的预约确认）会被压到几乎不可见。
    ///
    /// 96 = 1.5 × 64：字号跟着放大的诉求仍然满足（轨道里的文字自己是
    /// `AppFonts.body()`，两行 + `minimumScaleFactor` 兜底），而几何有界。
    /// 封的是**容器**不是文字 —— 这与「固定磅值不跟 Dynamic Type 走」那条不冲突。
    private static let maximumTrackHeight: CGFloat = 96

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 🔴 不写死 64pt。这一屏底部**唯一**的操作控件，低视力用户把系统字号调到 AX5 时
    /// 它必须跟着长 —— 本仓库为固定磅值栽过一次（成就页头部原本写死 48pt）。
    /// 但要封顶，见 `maximumTrackHeight`。
    @ScaledMetric(relativeTo: .body) private var scaledTrackHeight: CGFloat = 64

    private var trackHeight: CGFloat {
        min(scaledTrackHeight, Self.maximumTrackHeight)
    }

    let isAvailable: Bool
    let isEnabled: Bool
    let isUpdating: Bool
    /// 轨道上状态那半句（「等待系统派单」/「已关闭接单」），来自 `VolunteerHomeViewModel.statusText`。
    let statusText: String
    let onChange: (Bool) -> Void

    @State private var dragX: CGFloat = 0

    /// 🔴 **两态渲染同一个 `slideTrack`，高度恒为 `trackHeight`。**
    ///
    /// 改版前这里是 `if isAvailable { 状态条; 关闭按钮 } else { 滑轨 }`，两态高度分别是
    /// 约 64pt 和约 126pt（64 + 10 + 52）。这个控件挂在 `VolunteerHomeView` 的
    /// `.safeAreaInset(edge: .bottom)` 上，而 iOS 16 对 inset 视图的**运行时高度突变**
    /// 更新滞后 —— 2026-09-17 收到的现场报告是「底栏浮在离屏幕底部一段距离的位置、
    /// 盖住了内容，重启后消失」，高度突变是最可能的触发条件。
    ///
    /// 合并成一条之后触发条件消失。守卫在 `AccessibilityAuditTests` 那条拖拽用例里：
    /// 同一次运行中量拖开前后的 `frame.height`，不等就红。
    var body: some View {
        slideTrack
    }

    // MARK: 轨道（两个方向共用）

    /// 关闭态向右滑开启，开启态向左滑关闭。
    ///
    /// 🔴 **方向靠在视图层给 `dragX` 取反实现，`VolunteerAvailabilitySlide` 一行不改。**
    /// 阈值 0.2、NaN 守卫、`0...trackWidth` 钳位因此只有一份，两个方向不可能漂移出
    /// 两个阈值 —— 而「关闭比开启难一点」这种漂移在屏幕上没有任何信号。
    private var slideTrack: some View {
        GeometryReader { proxy in
            let knobSize = max(28, trackHeight - Self.knobInset * 2)
            // 滑块能走的距离 = 轨道宽 − 滑块直径 − 两侧留白。
            let travelWidth = max(0, proxy.size.width - knobSize - Self.knobInset * 2)
            let travel = VolunteerAvailabilitySlide.travel(dragX: dragX, trackWidth: travelWidth)
            let progress = VolunteerAvailabilitySlide.progress(dragX: dragX, trackWidth: travelWidth)
            let isPastThreshold = progress >= VolunteerAvailabilitySlide.activationFraction

            // 开启态从右往左滑，所以进度、滑块、文字留白全部靠右对齐。
            ZStack(alignment: isAvailable ? .trailing : .leading) {
                // 高对比度主色底。Uber 原文："Distinguish the swipe affordance from the
                // surrounding UI by using a primary, high-contrast background."
                //
                // 🔴 **两个都不是 `AppColors.primary` / `AppColors.success`。** 前者的暗色取值
                // `#0A84FF` 压白字只有 3.65:1、后者 `#30D158` 只有 2.02:1，而轨道上那行字是
                // 17pt semibold —— 够不上 WCAG large text 的豁免，要 4.5:1。仓库里已有两个
                // 为「白字压色底」压暗过的版本，直接复用，不新造第三个。检查在
                // `LowVisionChannelTests` 的 `testVoiceStageSurfaceKeepsWhiteTextReadable`
                // 与 `testAvailabilityOnSurfaceKeepsWhiteTextReadable`。
                Capsule().fill(isAvailable ? AppColors.availabilityOnSurface : AppColors.voiceStageSurface)

                // 已滑过的轨道变亮，给连续的进度反馈。
                Capsule()
                    .fill(Color.white.opacity(0.16))
                    .frame(width: travel + knobSize + Self.knobInset * 2)

                Text(trackTitle(isPastThreshold: isPastThreshold))
                    .font(AppFonts.body().weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.62)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    // 给滑块让出它那一侧的位置，另一侧只留常规内边距。
                    .padding(isAvailable ? .trailing : .leading, knobSize)
                    .padding(isAvailable ? .leading : .trailing, 12)

                // 单个箭头。Uber 原文："The component does not support any other icons."
                // 箭头方向就是该往哪滑 —— 开启态指左。
                Circle()
                    .fill(Color.white)
                    .frame(width: knobSize, height: knobSize)
                    .overlay {
                        Image(systemName: isAvailable ? "arrow.left" : "arrow.right")
                            .font(.body.weight(.bold))
                            .foregroundColor(AppColors.primary)
                    }
                    .shadow(color: .black.opacity(0.22), radius: 3, x: 0, y: 2)
                    .padding(isAvailable ? .trailing : .leading, Self.knobInset)
                    .offset(x: isAvailable ? -travel : travel)
            }
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard isEnabled, !isUpdating else { return }
                        dragX = normalizedTravel(value.translation.width)
                    }
                    .onEnded { value in
                        guard isEnabled, !isUpdating else { return }
                        let activates = VolunteerAvailabilitySlide.activates(
                            dragX: normalizedTravel(value.translation.width),
                            trackWidth: travelWidth
                        )
                        // 回弹是位移类动效，必须让「减弱动态效果」关掉它（守卫 `motion-not-gated`）。
                        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.82)) {
                            dragX = 0
                        }
                        if activates { toggle() }
                    }
            )
        }
        .frame(height: trackHeight)
        // ponytail: 更新中只降透明度，不再叠一枚 `ProgressView`。
        // `setAvailability` 是乐观更新（`VolunteerHomeView.swift:768`，失败才回滚），
        // 轨道此刻已经翻成目标态了 —— 在一个「看起来已经开了」的控件上转圈只会让人以为没开。
        .opacity(isEnabled && !isUpdating ? 1 : 0.5)
        // 🔴 **辅助技术两态都拿到一枚普通按钮。**
        //
        // VoiceOver / Switch Control / Voice Control 会彻底改变用户的物理交互方式，
        // 很多人根本不触碰屏幕（Apple Developer Forums 线程 729098）—— 只有裸拖拽手势的话，
        // 这一屏**唯一**的主操作对他们等于不存在。开启态同理：左滑对他们也是做不到的动作。
        //
        // 用 `accessibilityRepresentation` 而不是把整个控件做成 `Button`：前者只换掉
        // 无障碍树，指针路径仍然只有滑动（不会被误点开），两边各自拿到对的那一套。
        //
        // label 放**动作名**而不是状态，是为了 Voice Control：那类用户得能把控件名念出来
        // （「点击 今天先不跑了」）。状态走 `accessibilityValue`，VoiceOver 会接在 label
        // 后面念，两件事都不丢。
        .accessibilityRepresentation {
            Button(isAvailable
                   ? VolunteerAvailabilityCopy.closeTitle
                   : VolunteerAvailabilityCopy.slideToOpenTitle) { toggle() }
                .disabled(!isEnabled || isUpdating)
                .accessibilityValue(isAvailable
                                    ? "\(VolunteerAvailabilityCopy.availableStatusTitle)，\(statusText)"
                                    : statusText)
                .accessibilityHint(isAvailable
                                   ? VolunteerAvailabilityCopy.closeHint
                                   : VolunteerAvailabilityCopy.slideHint)
        }
        // 🚩 **两态共用一个 identifier，状态由上面那枚按钮的 label 区分。**
        //
        // `scripts/hooks/guard.mjs` 的 identifier 漂移检测只认**字面量**
        // （`ACCESSIBILITY_IDENTIFIER` 正则），写成 `isAvailable ? "a" : "b"` 会让它
        // 两个都认不出来，于是 UI 测试引用的那个反被判成 stale —— 守卫从保护变成噪音。
        .accessibilityIdentifier("volunteerAvailabilitySlider")
    }

    /// 轨道上那行字。静止时说现在是什么状态 / 该做什么，拖过阈值时说松手会发生什么。
    private func trackTitle(isPastThreshold: Bool) -> String {
        if isAvailable {
            return isPastThreshold
                ? VolunteerAvailabilityCopy.slideReleaseToCloseTitle
                : "\(VolunteerAvailabilityCopy.availableStatusTitle) · \(statusText)"
        }
        return isPastThreshold
            ? VolunteerAvailabilityCopy.slideReleaseToOpenTitle
            : VolunteerAvailabilityCopy.slideToOpenTitle
    }

    /// 把手指位移折算成「朝生效方向走了多远」，**恒以正数表示前进**。
    ///
    /// 开启态要往左滑，`translation.width` 是负数，取反之后 `VolunteerAvailabilitySlide`
    /// 那三个纯函数原样可用 —— 包括 `travel(dragX: -80) == 0` 那条「不许拖出轨道」的钳位，
    /// 于是「反向乱拖」在两个方向上都是同一个行为，不必写第二遍。
    private func normalizedTravel(_ translationWidth: CGFloat) -> CGFloat {
        isAvailable ? -translationWidth : translationWidth
    }

    private func toggle() {
        guard isEnabled, !isUpdating else { return }
        // ponytail: 复用既有的 `HapticFeedback.play(.success)`，不为这一处新加一种 impact 波形。
        // 语义也对得上 —— 那条注释写的是「事情按预期推进了」，关闭同样是按预期推进。
        //
        // 🚩 关闭那一侧**新增**了触感（改版前是普通按钮，没有）。这不是顺手加的：
        // 点按能靠手指感觉到自己按下去了，而「拖过阈值了没有」纯靠猜 —— 阈值类手势必须
        // 有一次确认反馈，否则只能盯着屏幕看结果，而这一屏的用户不一定看得清。
        HapticFeedback.play(.success)
        onChange(!isAvailable)
    }
}
