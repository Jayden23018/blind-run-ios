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

    /// 向右的实际位移，钳在 `0...trackWidth`。
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


// MARK: - 控件

/// 首页底部白色底座里的那一枚胶囊（陪跑员首页 v3，负责人 2026-11-04 定稿，#694）。
///
/// 两种形态：
/// - **没在接单**：浅灰轨道 + 蓝色圆形滑块。向右滑 = 开启接单并进入接单页。
///   Uber Base 同页的 Caution 逐字写着 "If the action is not critical, a sliding button may be
///   unnecessary" —— 滑动只有绑在一个**真有后果**的动作上才立得住，「从这一刻起开始收派单」正是那种动作。
/// - **在接单**：没有滑块，整枚胶囊是一个入口，点按进入接单页。接单中是浅绿底深绿字「接单中 · 进入接单」。
///
/// 🔴 **v3 去掉了向左滑动停止接单**（2026-09-17 的双向滑块）。停止走接单页的「暂停接单」，
/// 那里有一次确认、说清已约好的单不受影响。读屏的「停止接单」自定义动作保留：
/// 读屏用户少走一页，且它不会被误触。
struct VolunteerAvailabilitySlider: View {
    /// 滑块与轨道之间的留白。滑块直径 = 轨道高 − 2×这个数。
    private static let knobInset: CGFloat = 5

    /// 文字与胶囊两端的距离。大字号下 12 会贴到圆角上（模拟器 AX3 截图）。
    private static let textInset: CGFloat = 20

    /// 轨道高度的上限。
    ///
    /// 🔴 **`@ScaledMetric` 必须封顶，否则 AX5 下这条入口会吃掉半屏。**
    /// `.body` 在 AX5 约是默认的 3.12 倍（`docs/research/dynamic-type-scale-20260812.md`），
    /// 不封顶算出来约 180pt，滑块跟着变成一个 170pt 的圆；横屏视口只有约 393pt。
    /// 封的是**容器**不是文字：轨道里的字仍是 `AppFonts.body()`，两行 + `minimumScaleFactor` 兜底。
    private static let maximumTrackHeight: CGFloat = 96

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 样例 58pt。跟字号长，但封顶（见 `maximumTrackHeight`）。
    @ScaledMetric(relativeTo: .body) private var scaledTrackHeight: CGFloat = 58

    private var trackHeight: CGFloat {
        min(scaledTrackHeight, Self.maximumTrackHeight)
    }

    let isAvailable: Bool
    /// 能不能滑开。滑动解决不了的原因（资质、培训）已经算在里面。
    let isEnabled: Bool
    let isUpdating: Bool
    /// 🔴 「接单中」只认这一项，不认 `isAvailable`：开关开着不等于后端会派单（审计 V-6）。
    let status: VolunteerAvailabilityStatus
    /// `status` 要解释的那句话。nil = 没有要解释的事。
    let notice: VolunteerAvailabilityNotice?
    /// 已开启时读屏值后面那半句（「正在等待系统派单」），来自 `VolunteerHomeViewModel.statusText`。
    let statusText: String
    let onChange: (Bool) -> Void
    /// 进入接单主页。开启那一下与已开启时点按胶囊，走的都是它。
    let onEnterHub: () -> Void
    /// 打开接单前进度。被资质或培训挡住时，点按轨道走它。
    let onShowProgress: () -> Void

    @State private var dragX: CGFloat = 0

    var body: some View {
        Group {
            if isAvailable || status.blocksOpening {
                entryPill
            } else {
                slideTrack
            }
        }
        .frame(height: trackHeight)
        // 被挡住时轨道是一句要读清楚的话和一个入口，不是禁用态，不能压暗。
        .opacity(acceptsGesture || status.blocksOpening ? 1 : 0.5)
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
            if status.blocksOpening {
                Button(VolunteerReadinessCopy.progressButtonTitle) { onShowProgress() }
                    .disabled(isUpdating)
                    .accessibilityHint(VolunteerReadinessCopy.progressButtonHint)
                    .accessibilityValue(notice?.spoken ?? "")
                    .accessibilityActions {
                        // 已开着的人仍要能退出（见 `acceptsGesture`）；关着的人没有这个动作。
                        if isAvailable {
                            Button(VolunteerAvailabilityCopy.closeTitle) { close() }
                        }
                    }
            } else if isAvailable {
                Button(VolunteerAvailabilityCopy.enterHubTitle) { onEnterHub() }
                    // 🔴 不是 `!isEnabled || isUpdating` —— 停止接单那个 action 挂在这枚
                    // 按钮上，按 `isEnabled` 停用会把它一起掐掉（见 `acceptsGesture`）。
                    .disabled(!acceptsGesture)
                    .accessibilityHint(VolunteerAvailabilityCopy.enterHubHint)
                    .accessibilityValue(accessibilityStatus)
                    .accessibilityAction(named: VolunteerAvailabilityCopy.closeTitle) { close() }
            } else {
                // 读屏双击即开启（#694 必须保留）。
                Button(VolunteerAvailabilityCopy.slideToOpenTitle) { open() }
                    .disabled(!isEnabled || isUpdating)
                    .accessibilityHint(VolunteerAvailabilityCopy.slideHint)
            }
        }
        .accessibilityIdentifier("volunteerAvailabilitySlider")
    }

    // MARK: 没在接单：滑块

    private var slideTrack: some View {
        GeometryReader { proxy in
            let knobSize = max(28, trackHeight - Self.knobInset * 2)
            // 滑块能走的距离 = 轨道宽 − 滑块直径 − 两侧留白。
            let travelWidth = max(0, proxy.size.width - knobSize - Self.knobInset * 2)
            let travel = VolunteerAvailabilitySlide.travel(dragX: dragX, trackWidth: travelWidth)
            let willOpen = VolunteerAvailabilitySlide.activates(dragX: dragX, trackWidth: travelWidth)

            ZStack(alignment: .leading) {
                // 浅灰轨道压在白色底座上（样例 `#EEF1F6`；取页面底色，暗色是纯黑压 `#1C1C1E` 底座）。
                Capsule().fill(AppColors.Flow.page)

                // 已滑过的那一段变成浅蓝，给连续的进度反馈。只在拖动时出现。
                if travel > 0 {
                    Capsule()
                        .fill(AppColors.Flow.blueTint)
                        .frame(width: travel + knobSize + Self.knobInset * 2)
                }

                trackLabel(
                    title: willOpen ? VolunteerAvailabilityCopy.slideReleaseToOpenTitle : VolunteerAvailabilityCopy.slideToOpenTitle,
                    detail: nil,
                    color: AppColors.textPrimary
                )
                .padding(.leading, knobSize + Self.knobInset * 2)
                .padding(.trailing, Self.textInset)

                // 单个箭头。Uber 原文："The component does not support any other icons."
                // 🔴 不是 `voiceStageSurface`（暗色 `#0B4DA2` 压纯黑轨道只有 2.60:1，控件边界要 3:1）；
                // `primary` 暗色 `#0A84FF` 压纯黑 5.76:1，白箭头 3.65:1（图形对象 3:1 够）。
                Circle()
                    .fill(AppColors.primary)
                    .frame(width: knobSize, height: knobSize)
                    .overlay {
                        Image(systemName: "arrow.right")
                            .font(.body.weight(.bold))
                            .foregroundColor(.white)
                    }
                    .padding(.leading, Self.knobInset)
                    .offset(x: travel)
            }
            .contentShape(Capsule())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard acceptsGesture else { return }
                        dragX = value.translation.width
                    }
                    .onEnded { value in
                        guard acceptsGesture else { return }
                        let opens = VolunteerAvailabilitySlide.activates(
                            dragX: value.translation.width,
                            trackWidth: travelWidth
                        )
                        // 回弹是位移类动效，必须让「减弱动态效果」关掉它（守卫 `motion-not-gated`）。
                        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.82)) {
                            dragX = 0
                        }
                        if opens { open() }
                    }
            )
        }
    }

    // MARK: 在接单 / 被挡住：整枚胶囊是入口

    /// 接单中：浅绿底深绿字「● 接单中 · 进入接单 ›」（`AppColors.availabilityPill*`，6.79:1 / 7.63:1）。
    /// 开着却收不到单、或被资质 / 培训挡住时：浅灰底，说清原因，点按去接单页或接单前进度。
    private var entryPill: some View {
        let accepting = status.isAccepting
        let foreground = accepting ? AppColors.availabilityPillText : AppColors.textPrimary
        return ZStack {
            Capsule().fill(accepting ? AppColors.availabilityPillSurface : AppColors.Flow.page)
            HStack(spacing: 8) {
                if accepting {
                    // 状态点只是冗余线索：「接单中」三个字已经说了（WCAG 1.4.1）。
                    Circle()
                        .fill(foreground)
                        .frame(width: 10, height: 10)
                        .accessibilityHidden(true)
                }
                trackLabel(title: pillTitle, detail: pillDetail, color: foreground)
                    .layoutPriority(1)
                if isAvailable, !status.blocksOpening {
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.bold))
                        .foregroundColor(foreground)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, Self.textInset)
        }
        .contentShape(Capsule())
        // 被资质或培训挡住时点按去看进度；开着时点按进入接单页。
        .onTapGesture {
            guard !isUpdating else { return }
            if status.blocksOpening {
                onShowProgress()
            } else if isAvailable, isEnabled {
                onEnterHub()
            }
        }
    }

    private var pillTitle: String {
        if let notice { return notice.title }
        return "\(VolunteerAvailabilityCopy.availableStatusTitle) · \(VolunteerAvailabilityCopy.enterHubTitle)"
    }

    /// 第二行。接单中不需要：「接单中 · 进入接单」已经说完了；锁屏收不到邀请那句在接单页的状态卡上。
    private var pillDetail: String? {
        guard let notice else { return nil }
        guard isAvailable, !status.blocksOpening else { return notice.detail }
        // 开着却收不到单：原因 + 去处。
        return [notice.detail, VolunteerAvailabilityCopy.enterHubTitle].compactMap { $0 }.joined(separator: " · ")
    }

    private func trackLabel(title: String, detail: String?, color: Color) -> some View {
        VStack(spacing: 2) {
            if isUpdating {
                ProgressView()
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(AppFonts.body().weight(.semibold))
            if let detail {
                Text(detail)
                    .font(AppFonts.caption())
            }
        }
        .foregroundColor(color)
        .lineLimit(2)
        .minimumScaleFactor(0.62)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    private var accessibilityStatus: String {
        status.isAccepting
            ? "\(VolunteerAvailabilityCopy.availableStatusTitle)，\(statusText)"
            : notice?.spoken ?? statusText
    }

    /// 见 `VolunteerAvailabilitySlide.acceptsGesture` —— 停止接单那侧刻意不看 `isEnabled`。
    private var acceptsGesture: Bool {
        VolunteerAvailabilitySlide.acceptsGesture(
            isAvailable: isAvailable,
            isEnabled: isEnabled,
            isUpdating: isUpdating
        )
    }

    /// 开启并进入接单主页。
    ///
    /// **两件事一起做**是设计交付 v3 的流程（主页滑动 → 接单主页）：开启之后志愿者要看的
    /// 是「下一次陪跑 / 有没有待回复的邀请」，而那些都不在首页上。
    private func open() {
        guard isEnabled, !isUpdating else { return }
        // ponytail: 复用既有的 `HapticFeedback.play(.success)`，不为这一处新加一种 impact 波形。
        HapticFeedback.play(.success)
        onChange(true)
        onEnterHub()
    }

    /// 🔴 **关闭路径上不许有挽留。** 只剩读屏自定义动作这一条路（指针用户走接单页的「暂停接单」）。
    private func close() {
        guard acceptsGesture else { return }
        HapticFeedback.play(.success)
        onChange(false)
    }
}
