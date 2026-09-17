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

    /// 已开启的状态条。这一刻起才会收到派单推送，所以说的是「等待」而不是「已完成」。
    static let availableStatusTitle = "已开启"

    /// 🔴 关闭是**普通点按**，且**不得弹任何激励挽留**。
    ///
    /// Uber 在司机点下线时弹当日收入目标劝其继续，被 NYT 点名、在 gig 平台设计分类法里
    /// 归入 dark pattern。摩擦力只加在「答应」这一侧 —— 这条已经以注释钉在
    /// `VolunteerHomeIncentive.swift:99-107`，改 UI 时别把它绕过去。
    static let closeTitle = "今天先不跑了"

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
    /// 已开启时状态条上那半句（「正在等待系统派单」），来自 `VolunteerHomeViewModel.statusText`。
    let statusText: String
    let onChange: (Bool) -> Void

    @State private var dragX: CGFloat = 0

    var body: some View {
        VStack(spacing: 10) {
            if isAvailable {
                availableStatusBar
                closeButton
            } else {
                slideTrack
            }
        }
    }

    // MARK: 开启侧（有摩擦力）

    private var slideTrack: some View {
        GeometryReader { proxy in
            let knobSize = max(28, trackHeight - Self.knobInset * 2)
            // 滑块能走的距离 = 轨道宽 − 滑块直径 − 两侧留白。
            let travelWidth = max(0, proxy.size.width - knobSize - Self.knobInset * 2)
            let travel = VolunteerAvailabilitySlide.travel(dragX: dragX, trackWidth: travelWidth)
            let progress = VolunteerAvailabilitySlide.progress(dragX: dragX, trackWidth: travelWidth)
            let isPastThreshold = progress >= VolunteerAvailabilitySlide.activationFraction

            ZStack(alignment: .leading) {
                // 高对比度主色底。Uber 原文："Distinguish the swipe affordance from the
                // surrounding UI by using a primary, high-contrast background."
                //
                // 🔴 **不是 `AppColors.primary`。** 它的暗色取值 `#0A84FF` 压白字只有 3.65:1，
                // 而轨道上那行字是 17pt semibold —— 够不上 WCAG large text 的豁免，要 4.5:1。
                // 仓库里已经有一个为「白字压蓝底」而压暗的版本（`voiceStageSurfaceTone`，
                // 暗色 `#0B4DA2` 白字 8.08:1），直接复用它，不新造第三个蓝。
                // 检查在 `LowVisionChannelTests.testVoiceStageSurfaceKeepsWhiteTextReadable`。
                Capsule().fill(AppColors.voiceStageSurface)

                // 已滑过的轨道变亮，给连续的进度反馈。
                Capsule()
                    .fill(Color.white.opacity(0.16))
                    .frame(width: travel + knobSize + Self.knobInset * 2)

                Text(isPastThreshold
                     ? VolunteerAvailabilityCopy.slideReleaseToOpenTitle
                     : VolunteerAvailabilityCopy.slideToOpenTitle)
                    .font(AppFonts.body().weight(.semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.62)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.leading, knobSize)
                    .padding(.trailing, 12)

                // 单个箭头。Uber 原文："The component does not support any other icons."
                Circle()
                    .fill(Color.white)
                    .frame(width: knobSize, height: knobSize)
                    .overlay {
                        Image(systemName: "arrow.right")
                            .font(.body.weight(.bold))
                            .foregroundColor(AppColors.primary)
                    }
                    .shadow(color: .black.opacity(0.22), radius: 3, x: 0, y: 2)
                    .padding(.leading, Self.knobInset)
                    .offset(x: travel)
            }
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard isEnabled, !isUpdating else { return }
                        dragX = value.translation.width
                    }
                    .onEnded { value in
                        guard isEnabled, !isUpdating else { return }
                        let activates = VolunteerAvailabilitySlide.activates(
                            dragX: value.translation.width,
                            trackWidth: travelWidth
                        )
                        // 回弹是位移类动效，必须让「减弱动态效果」关掉它（守卫 `motion-not-gated`）。
                        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.82)) {
                            dragX = 0
                        }
                        if activates { activate() }
                    }
            )
        }
        .frame(height: trackHeight)
        .opacity(isEnabled && !isUpdating ? 1 : 0.5)
        // 🔴 **辅助技术拿到的是一枚普通按钮。**
        //
        // VoiceOver / Switch Control / Voice Control 会彻底改变用户的物理交互方式，
        // 很多人根本不触碰屏幕（Apple Developer Forums 线程 729098）—— 只有裸拖拽手势的话，
        // 这一屏**唯一**的主操作对他们等于不存在。
        //
        // 用 `accessibilityRepresentation` 而不是把整个控件做成 `Button`：前者只换掉
        // 无障碍树，指针路径仍然只有滑动（不会被误点开），两边各自拿到对的那一套。
        .accessibilityRepresentation {
            Button(VolunteerAvailabilityCopy.slideToOpenTitle) { activate() }
                .disabled(!isEnabled || isUpdating)
                .accessibilityHint(VolunteerAvailabilityCopy.slideHint)
        }
        .accessibilityIdentifier("volunteerAvailabilitySlider")
    }

    private func activate() {
        guard isEnabled, !isUpdating else { return }
        // ponytail: 复用既有的 `HapticFeedback.play(.success)`，不为这一处新加一种 impact 波形。
        // 语义也对得上 —— 那条注释写的是「事情按预期推进了」。
        HapticFeedback.play(.success)
        onChange(true)
    }

    // MARK: 关闭侧（无摩擦力）

    private var availableStatusBar: some View {
        HStack(spacing: 8) {
            if isUpdating {
                ProgressView()
                    .tint(.white)
                    .accessibilityHidden(true)
            }
            Text("\(VolunteerAvailabilityCopy.availableStatusTitle) · \(statusText)")
                .font(AppFonts.body().weight(.semibold))
                .foregroundColor(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.62)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .frame(minHeight: trackHeight)
        // 🔴 **不是 `AppColors.success`。** 那个色的暗色取值 `#30D158` 压白字只有 2.02:1，
        // 而这是首屏底部唯一的常驻控件。理由与取值见 `AppColors.availabilityOnSurfaceTone`，
        // 检查在 `LowVisionChannelTests.testAvailabilityOnSurfaceKeepsWhiteTextReadable`。
        .background(AppColors.availabilityOnSurface)
        .clipShape(Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(VolunteerAvailabilityCopy.toggleTitle)\(VolunteerAvailabilityCopy.availableStatusTitle)，\(statusText)")
        .accessibilityIdentifier("volunteerAvailabilityStatusBar")
    }

    /// 🔴 普通点按，**没有二次确认、没有挽留**。
    ///
    /// 关掉开关不影响当前订单（后端行为），所以它不是不可逆动作 —— 给它加确认，
    /// 或者顺势弹一句「你今天已经跑了 2 单，再坚持一下？」，就是 Uber 那条被点名的
    /// 下线挽留。摩擦力只加在「答应」这一侧。
    private var closeButton: some View {
        Button {
            guard !isUpdating else { return }
            onChange(false)
        } label: {
            Text(VolunteerAvailabilityCopy.closeTitle)
                .font(AppFonts.body().weight(.semibold))
                .foregroundColor(AppColors.primary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)  // guard:allow small-touch-target
                .background(AppColors.secondaryBackground)
                .clipShape(Capsule())
        }
        .disabled(isUpdating)
        .accessibilityLabel(VolunteerAvailabilityCopy.closeTitle)
        .accessibilityHint(VolunteerAvailabilityCopy.closeHint)
        .accessibilityIdentifier("volunteerAvailabilityCloseButton")
    }
}
