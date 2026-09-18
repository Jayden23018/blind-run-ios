import SwiftUI

// MARK: - 阈值

/// 滑动开启 / 停止「可服务」的判定。
///
/// 抽成纯函数而不是写在手势回调里：这是整个控件**唯一一处会悄悄坏掉**的地方 ——
/// 阈值改错了控件照常能用，只是变难（或变得一碰就开/一碰就关），没有任何运行时信号。
///
/// 依据是 Uber Base Design System 的 Sliding button 规格（原文见
/// `docs/research/volunteer-profile-first-screen-20260914.md` §3）：
///
/// | Threshold | Value |
/// |---|---|
/// | Low (Easy) | "Complete more than 20%" |
/// | High (Hard) | "Complete more than 80%" |
///
/// 🔴 **开启侧取 Low (Easy)。** 同页的无障碍告警逐字写着：要求高交互精度的动作
/// "proves difficult to users with physical and motor disabilities, as well as seniors"。
/// 我们的志愿者里有大量中老年人，High 那一档是在给他们设障。
enum VolunteerAvailabilitySlide {
    /// 向右滑过轨道的这个比例即开启。**不要往上调** —— 理由见类型注释。
    static let activationFraction: CGFloat = 0.2

    /// 向左滑过这个比例即停止接单。
    ///
    /// 🔴 **刻意比开启高**（0.35 vs 0.20），理由不是「关闭要加摩擦」，而是**方向本身**：
    /// 向左滑是 iOS 边缘返回手势的方向，两侧阈值取同一个数会让一次边缘误触直接把接单关掉，
    /// 而志愿者当时正看着首页、屏幕上没有任何确认框拦他。
    ///
    /// ⚠️ 2026-09-17 产品拍板改成双向滑块之前，这里的既定做法是「关闭是普通点按，
    /// 摩擦力只加在答应那一侧」（依据是 Uber 司机下线挽留被 NYT 点名的 dark pattern）。
    /// 那条不再成立，但它防的东西仍然成立：**关闭路径上不许出现挽留** ——
    /// 不弹「你今天已经跑了 2 单，再坚持一下？」，不把「保持接单」做成主按钮。
    /// 抬高左滑阈值是防误触，不是劝退。
    static let deactivationFraction: CGFloat = 0.35

    /// 向右的实际位移，钳在 `0...trackWidth`。
    ///
    /// 非有限值（布局还没算出来时 `GeometryReader` 会给 NaN）一律当 0，
    /// 与 `VolunteerHomeTopLayout` 那批 `isFinite` 守卫同一个理由：
    /// 一个 NaN 会把滑块画到屏幕外，而屏幕上看起来只是「滑块不见了」。
    static func travel(dragX: CGFloat, trackWidth: CGFloat) -> CGFloat {
        guard dragX.isFinite, trackWidth.isFinite, trackWidth > 0 else { return 0 }
        return min(max(dragX, 0), trackWidth)
    }

    /// 向左的实际位移（正数），钳在 `0...trackWidth`。与 `travel` 完全镜像。
    static func leftTravel(dragX: CGFloat, trackWidth: CGFloat) -> CGFloat {
        travel(dragX: -dragX, trackWidth: trackWidth)
    }

    /// 松手时该不该真的开启。
    static func activates(dragX: CGFloat, trackWidth: CGFloat) -> Bool {
        guard trackWidth > 0 else { return false }
        return travel(dragX: dragX, trackWidth: trackWidth) / trackWidth >= activationFraction
    }

    /// 松手时该不该真的停止接单。
    static func deactivates(dragX: CGFloat, trackWidth: CGFloat) -> Bool {
        guard trackWidth > 0 else { return false }
        return leftTravel(dragX: dragX, trackWidth: trackWidth) / trackWidth >= deactivationFraction
    }

    /// 已滑过的比例，给轨道高亮用（0...1）。
    static func progress(dragX: CGFloat, trackWidth: CGFloat) -> CGFloat {
        guard trackWidth > 0 else { return 0 }
        return travel(dragX: dragX, trackWidth: trackWidth) / trackWidth
    }

    /// 这一刻的手势该不该被接受。
    ///
    /// 🔴 **停止接单不看 `isEnabled`（= 资质审核是否通过），这是刻意的不对称。**
    ///
    /// 「开始接单」有后果 —— 没通过审核的人不该进候选池，所以那一侧必须看 `isEnabled`。
    /// 「停止接单」没有后果，**任何时候都必须能退出**。资质在接单期间被撤销（后台审核状态
    /// 变化 + 回前台重新拉取），人却停不下来，是把用户锁在一个他已经不该待的状态里。
    ///
    /// 双向滑块改版前这里是两个控件、两套闸，所以不会撞上：那时关闭侧只有 `guard !isUpdating`。
    /// 合并成一条轨道之后两个方向共用同一批 `guard`，`isEnabled` 就顺势把关闭也堵上了 ——
    /// 三条路一起堵死（拖拽 `onEnded`、无障碍动作所在按钮的 `.disabled`、以及 `close()` 自己）。
    ///
    /// 抽成纯函数而不是写成散在视图里的三元表达式，与本类型其余部分同一个理由：
    /// 这种闸改错了屏幕上没有任何信号 —— 控件照常渲染，只是某个状态下按不动。
    static func acceptsGesture(isAvailable: Bool, isEnabled: Bool, isUpdating: Bool) -> Bool {
        guard !isUpdating else { return false }
        return isAvailable || isEnabled
    }
}

// MARK: - 文案

/// 滑动 CTA 的文案挂在 `VolunteerAvailabilityCopy` 上（`VolunteerHomeView.swift:15`），
/// 不另起一个 enum —— 那个类型存在的全部理由就是「这个开关在全 App 只有一个名字」。
extension VolunteerAvailabilityCopy {
    /// 未开启时的静止态。是**邀请**不是指令 —— 志愿者是无偿的，命令句式属于 controlling 型激励
    /// （Motivation Crowding，`docs/research/volunteer-home-incentive-layer-20260914.md` §3.2）。
    static let slideToOpenTitle = "向右滑动，开始接单"

    /// 向右拖过阈值之后。
    static let slideReleaseToOpenTitle = "松手即开启"

    /// 已开启时轨道上的主文案。
    static let availableStatusTitle = "接单中"

    /// 已开启时的副文案。**两件事都要说出来**：轨道此刻既是进入接单页的入口，也是关闭开关的地方。
    /// 只说一半的后果是另一半对不看提示的人等于不存在。
    static let availableActionHint = "点这里进入接单，向左滑动停止"

    /// 向左拖过阈值之后。
    static let slideReleaseToCloseTitle = "松手即停止接单"

    static let slideHint = "向右滑动开启，开启后才会收到系统派单，并进入接单页。开启不影响你当前的订单"
    static let enterHubTitle = "进入接单"
    static let enterHubHint = "查看下一次陪跑、待回复的邀请，也可以在那里暂停接单"
    static let closeTitle = "停止接单"
    static let closeHint = "停止后不会收到新的系统派单，但不影响当前订单"
}

// MARK: - 控件

/// 首屏底部的「可服务」滑动 CTA。
///
/// 🚩 **双向**：向右滑 = 开启接单并进入接单页；向左滑 = 停止接单。
/// Uber Base 同页的 Caution 逐字写着 "If the action is not critical, a sliding button may be
/// unnecessary and may add unnecessary complexity to the interface" —— 滑动只有绑在一个
/// **真有后果**的动作上才立得住，而「从这一刻起开始（或不再）收派单」正是那种动作。
///
/// 已开启时**点按轨道**进入接单页：那一刻向右已经没有「开启」这件事可做了，
/// 而再给首页加第二个控件会让这一条底栏在 AX5 下吃掉更多屏幕。
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
    /// 已开启时副文案后面那半句（「正在等待系统派单」），来自 `VolunteerHomeViewModel.statusText`。
    let statusText: String
    let onChange: (Bool) -> Void
    /// 进入接单主页。开启那一下与已开启时点按轨道，走的都是它。
    let onEnterHub: () -> Void

    @State private var dragX: CGFloat = 0

    var body: some View {
        slideTrack
    }

    private var slideTrack: some View {
        GeometryReader { proxy in
            let knobSize = max(28, trackHeight - Self.knobInset * 2)
            // 滑块能走的距离 = 轨道宽 − 滑块直径 − 两侧留白。
            let travelWidth = max(0, proxy.size.width - knobSize - Self.knobInset * 2)
            let rightTravel = VolunteerAvailabilitySlide.travel(dragX: dragX, trackWidth: travelWidth)
            let leftTravel = VolunteerAvailabilitySlide.leftTravel(dragX: dragX, trackWidth: travelWidth)
            let willOpen = !isAvailable
                && VolunteerAvailabilitySlide.activates(dragX: dragX, trackWidth: travelWidth)
            let willClose = isAvailable
                && VolunteerAvailabilitySlide.deactivates(dragX: dragX, trackWidth: travelWidth)
            // 未开启时滑块停在最左，只往右走；已开启时停在最右，只往左走。
            let knobOffset = isAvailable ? travelWidth - leftTravel : rightTravel

            ZStack(alignment: .leading) {
                // 高对比度主色底。Uber 原文："Distinguish the swipe affordance from the
                // surrounding UI by using a primary, high-contrast background."
                //
                // 🔴 **不是 `AppColors.primary`。** 它的暗色取值 `#0A84FF` 压白字只有 3.65:1，
                // 而轨道上那行字是 17pt semibold —— 够不上 WCAG large text 的豁免，要 4.5:1。
                // 仓库里已经有一个为「白字压蓝底」而压暗的版本（`voiceStageSurfaceTone`，
                // 暗色 `#0B4DA2` 白字 8.08:1），直接复用它，不新造第三个蓝。
                // 检查在 `LowVisionChannelTests.testVoiceStageSurfaceKeepsWhiteTextReadable`。
                //
                // 已开启时换成同样验过对比度的绿（`availabilityOnSurface`）：轨道颜色是
                // 「我现在到底在不在接单」唯一的全局视觉线索，两态同色等于没有这条线索。
                Capsule().fill(isAvailable ? AppColors.availabilityOnSurface : AppColors.voiceStageSurface)

                // 已滑过的轨道变亮，给连续的进度反馈。
                Capsule()
                    .fill(Color.white.opacity(0.16))
                    .frame(width: knobOffset + knobSize + Self.knobInset * 2)

                trackLabel(willOpen: willOpen, willClose: willClose)
                    .padding(.leading, isAvailable ? 12 : knobSize)
                    .padding(.trailing, isAvailable ? knobSize : 12)

                // 单个箭头。Uber 原文："The component does not support any other icons."
                Circle()
                    .fill(Color.white)
                    .frame(width: knobSize, height: knobSize)
                    .overlay {
                        Image(systemName: isAvailable ? "arrow.left" : "arrow.right")
                            .font(.body.weight(.bold))
                            .foregroundColor(AppColors.primary)
                    }
                    .shadow(color: .black.opacity(0.22), radius: 3, x: 0, y: 2)
                    .padding(.leading, Self.knobInset)
                    .offset(x: knobOffset)
            }
            .contentShape(Capsule())
            // 已开启时点按轨道 = 进入接单主页。未开启时点按不做任何事 ——
            // 开启是有后果的动作，摩擦力（滑动）就是它的确认方式。
            .onTapGesture {
                guard isAvailable, isEnabled, !isUpdating else { return }
                onEnterHub()
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard acceptsGesture else { return }
                        dragX = value.translation.width
                    }
                    .onEnded { value in
                        guard acceptsGesture else { return }
                        let opens = !isAvailable && VolunteerAvailabilitySlide.activates(
                            dragX: value.translation.width,
                            trackWidth: travelWidth
                        )
                        let closes = isAvailable && VolunteerAvailabilitySlide.deactivates(
                            dragX: value.translation.width,
                            trackWidth: travelWidth
                        )
                        // 回弹是位移类动效，必须让「减弱动态效果」关掉它（守卫 `motion-not-gated`）。
                        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.82)) {
                            dragX = 0
                        }
                        if opens { open() }
                        if closes { close() }
                    }
            )
        }
        .frame(height: trackHeight)
        .opacity(acceptsGesture ? 1 : 0.5)
        // 🔴 **辅助技术拿到的是普通控件。**
        //
        // VoiceOver / Switch Control / Voice Control 会彻底改变用户的物理交互方式，
        // 很多人根本不触碰屏幕（Apple Developer Forums 线程 729098）—— 只有裸拖拽手势的话，
        // 这一屏**唯一**的主操作对他们等于不存在。
        //
        // 用 `accessibilityRepresentation` 而不是把整个控件做成 `Button`：前者只换掉
        // 无障碍树，指针路径仍然只有滑动 / 点按（不会被误点开），两边各自拿到对的那一套。
        //
        // ⚠️ 已开启时是「一枚按钮 + 一个自定义动作」，不是两枚按钮：两枚按钮会让读屏用户
        // 在底栏上划两次才走完，而其中一次念的是他八成不想要的那个（停止接单）。
        .accessibilityRepresentation {
            if isAvailable {
                Button(VolunteerAvailabilityCopy.enterHubTitle) { onEnterHub() }
                    // 🔴 不是 `!isEnabled || isUpdating` —— 停止接单那个 action 挂在这枚
                    // 按钮上，按 `isEnabled` 停用会把它一起掐掉（见 `acceptsGesture`）。
                    .disabled(!acceptsGesture)
                    .accessibilityHint(VolunteerAvailabilityCopy.enterHubHint)
                    .accessibilityValue("\(VolunteerAvailabilityCopy.availableStatusTitle)，\(statusText)")
                    .accessibilityAction(named: VolunteerAvailabilityCopy.closeTitle) { close() }
            } else {
                Button(VolunteerAvailabilityCopy.slideToOpenTitle) { open() }
                    .disabled(!isEnabled || isUpdating)
                    .accessibilityHint(VolunteerAvailabilityCopy.slideHint)
            }
        }
        .accessibilityIdentifier("volunteerAvailabilitySlider")
    }

    @ViewBuilder
    private func trackLabel(willOpen: Bool, willClose: Bool) -> some View {
        VStack(spacing: 2) {
            if isUpdating {
                ProgressView()
                    .tint(.white)
                    .accessibilityHidden(true)
            }
            Text(primaryTitle(willOpen: willOpen, willClose: willClose))
                .font(AppFonts.body().weight(.semibold))
            if isAvailable, !willClose {
                Text(VolunteerAvailabilityCopy.availableActionHint)
                    .font(AppFonts.caption())
                    .opacity(0.9)
            }
        }
        .foregroundColor(.white)
        .lineLimit(2)
        .minimumScaleFactor(0.62)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    private func primaryTitle(willOpen: Bool, willClose: Bool) -> String {
        if willClose { return VolunteerAvailabilityCopy.slideReleaseToCloseTitle }
        if willOpen { return VolunteerAvailabilityCopy.slideReleaseToOpenTitle }
        return isAvailable
            ? VolunteerAvailabilityCopy.availableStatusTitle
            : VolunteerAvailabilityCopy.slideToOpenTitle
    }

    /// 开启并进入接单主页。
    ///
    /// **两件事一起做**是设计交付 v3 的流程（主页滑动 → 接单主页）：开启之后志愿者要看的
    /// 是「下一次陪跑 / 有没有待回复的邀请」，而那些都不在首页上。
    /// 见 `VolunteerAvailabilitySlide.acceptsGesture` —— 停止接单那侧刻意不看 `isEnabled`。
    private var acceptsGesture: Bool {
        VolunteerAvailabilitySlide.acceptsGesture(
            isAvailable: isAvailable,
            isEnabled: isEnabled,
            isUpdating: isUpdating
        )
    }

    private func open() {
        guard isEnabled, !isUpdating else { return }
        // ponytail: 复用既有的 `HapticFeedback.play(.success)`，不为这一处新加一种 impact 波形。
        // 语义也对得上 —— 那条注释写的是「事情按预期推进了」。
        HapticFeedback.play(.success)
        onChange(true)
        onEnterHub()
    }

    /// 🔴 **关闭路径上不许有挽留。**
    ///
    /// 关掉开关不影响当前订单（后端行为），所以它不是不可逆动作 —— 给它顺势弹一句
    /// 「你今天已经跑了 2 单，再坚持一下？」，就是 Uber 那条被 NYT 点名的下线挽留。
    /// 双向滑块改的是**手势**，不是这条。
    private func close() {
        guard acceptsGesture else { return }
        HapticFeedback.play(.success)
        onChange(false)
    }
}
