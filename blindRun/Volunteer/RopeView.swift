import SwiftUI

// MARK: - 引导绳 = 进度绳（两端订单页头卡）
//
// 交付包 `03-motion-and-haptics.md` §一、§二、§三；精确取值对照 `reference/artboards/Rope.dc.html`。
// 语义（交付包 D2 / D3）：虚线 = 还没约好；实线 = 已约好。
//
// 🔄 2026-10-13 定稿 v6（`docs/ui/mockups/intro-call-20261013/`，负责人批准，issue #397）：
// 进度与引导绳合成一根。绳上四个**等距**刻度，第四格就是对方的头像；**「我」永远在左**，
// 每进一个阶段沿绳子挪一格。汇合那一格不画刻度，换成完成页的并肩插图（`RopeTogetherIllustration`）。
// 改版前盲人端是陪跑员在左往右走向「我」、陪跑员端出发中按 `eta.progress` 连续移动 —— 两条都改了。
//
// 几何是纯数据（`RopeGeometry`），视图只负责把数字画出来 —— 这样几何能在单测里验，
// 不用渲染。坐标系 342×96（并肩态 342×56），按容器宽度等比缩放。

enum RopeState: Equatable {
    case invited
    case agreed
    /// `progress` 是后端 `eta.progress`。2026-10-13 起刻度态**不再用它定位**（「我」停在「出发」刻度上），
    /// 保留关联值是为了不动调用点的数据流；还有几分钟到由头卡大数字与读屏标签说。
    case departed(progress: Double)
    case arrived
    /// 跑步中衔接（跑者端跑步卡里的并肩金绳）。
    case together
    /// 跑者取消。头像停在取消前的位置。
    indirect case cancelled(after: RopeState)

    /// 在四格里的哪一格（0…3）。
    var step: Int {
        switch self {
        case .invited: return 0
        case .agreed: return 1
        case .departed: return 2
        case .arrived, .together: return 3
        case .cancelled(let previous): return previous.step
        }
    }

    /// 刻度文字。第 1 格两端叫法不同：跑者那头是「匹配」（`BlindOrderFlowStep.matching`），
    /// 陪跑员那头是「邀请」。
    static func stepTitles(perspective: RopePerspective) -> [String] {
        [perspective == .runner ? "匹配" : "邀请", "约好", "出发", "汇合"]
    }

    /// 读屏标签。交付包 03：「第 N 步，共 4 步，{状态}」，出发中再加「还有 N 分钟到」；
    /// 2026-10-13 起再补「接下来：…」—— 负责人要的是「做过哪些、还有哪些」，而头卡里那行可见的
    /// 「第 N 步」去掉了（读屏念两遍），还剩哪几步只剩这里能说。第 4 步与取消不补。
    ///
    /// 跑者视角（盲人端订单页，#349）换一套说法：同一根绳子，陪跑员那头是「正在赶去」，
    /// 跑者这头是「陪跑员正在赶来」。照搬陪跑员口吻会让盲人听成是自己在赶路。
    func accessibilityLabel(remainingMinutes: Int? = nil, perspective: RopePerspective = .volunteer) -> String {
        let base = perspective == .runner ? runnerAccessibilityLabel : volunteerAccessibilityLabel(remainingMinutes: remainingMinutes)
        return base + nextStepsSuffix(perspective: perspective)
    }

    private func volunteerAccessibilityLabel(remainingMinutes: Int?) -> String {
        switch self {
        case .invited: return "第 1 步，共 4 步，邀请，还没约好"
        case .agreed: return "第 2 步，共 4 步，已约好"
        case .departed:
            let base = "第 3 步，共 4 步，正在赶去"
            guard let remainingMinutes else { return base }
            return "\(base)，还有 \(remainingMinutes) 分钟到"
        case .arrived: return "第 4 步，共 4 步，已到集合点"
        case .together: return "第 4 步，共 4 步，已汇合"
        case .cancelled: return "这次陪跑已取消"
        }
    }

    /// 跑者视角。出发中**不念分钟数**：后端只给本单陪跑员下发 `eta`，盲人 token 恒为 null。
    private var runnerAccessibilityLabel: String {
        switch self {
        case .invited: return "第 1 步，共 4 步，匹配中，还没约好"
        case .agreed: return "第 2 步，共 4 步，已约好"
        case .departed: return "第 3 步，共 4 步，陪跑员正在赶来"
        case .arrived: return "第 4 步，共 4 步，陪跑员已到达"
        case .together: return "第 4 步，共 4 步，已汇合"
        case .cancelled: return "这次陪跑已取消"
        }
    }

    private func nextStepsSuffix(perspective: RopePerspective) -> String {
        switch self {
        case .invited, .agreed, .departed:
            let rest = Self.stepTitles(perspective: perspective).dropFirst(step + 1)
            return "。接下来：" + rest.joined(separator: "、")
        case .arrived, .together, .cancelled:
            return ""
        }
    }
}

/// 引导绳从谁的角度画。**「我」永远在左**，两个视角不同的只有：读屏说法、刻度第 1 格的叫法、
/// 右边那个头像里写谁的姓。
enum RopePerspective: Equatable {
    case volunteer
    case runner
}

/// 一个状态下引导绳的全部几何与样式。单位是 342×96（并肩态 342×56）坐标系里的 pt。
struct RopeGeometry: Equatable {
    enum RopeStyle: Equatable {
        /// 虚线 [2, 7]，线宽 2.5。
        case dashed
        /// 实线，线宽 3。
        case solid
        /// 金色实线（汇合后并肩）。
        case gold
        /// 断开后的装饰灰。
        case broken
    }

    /// 右边那个头像（对方）。
    enum OtherStyle: Equatable {
        /// 空心 + 虚线描边 [3, 3]（还没有对方 / 还没约好）。
        case hollow
        case solid
        /// 去饱和变灰（跑者取消）。
        case greyed
    }

    enum Layout: Equatable {
        /// 四个刻度 + 「我」停在 `step` 那一格。
        case ticks
        /// 汇合：不画刻度，画完成页那张并肩插图。
        case illustration
        /// 跑步中衔接的并肩金绳（改版前的几何，原样保留）。
        case together
    }

    static let width: CGFloat = 342
    /// 刻度态：头像（y=28，半径 22）+ 刻度文字（中心 y=78）。
    static let height: CGFloat = 96
    /// 并肩态沿用改版前的高度：它挂在跑步卡里，下面紧跟三个数字。
    static let togetherHeight: CGFloat = 56
    static let avatarRadius: CGFloat = 22
    static let avatarY: CGFloat = 28
    /// 四个刻度，等距（每段 98）。第四个就是对方头像的圆心。
    ///
    /// v3 初稿把「我」的停靠点 24/105/187/268 当刻度画、第四格却落在 318，肉眼间距 81/81/131 ——
    /// 负责人目视发现的。**刻度与「我」停在哪是两组数**，汇合那一格「我」不压在对方头像上。
    static let ticks: [CGFloat] = [24, 122, 220, 318]
    /// 整根绳从第一个刻度垂到对方头像，控制点比两端低这么多（中点实际下垂一半，12pt）。
    static let curveSag: CGFloat = 24
    /// 刻度文字的中心 y。
    static let labelCenterY: CGFloat = 78

    var layout: Layout = .ticks
    var step: Int
    var selfX: CGFloat
    var otherX: CGFloat = 318
    var ropeStyle: RopeStyle
    var otherStyle: OtherStyle = .solid
    /// 出发中「我」外圈的呼吸光晕。只在陪跑员视角画（他才是在路上的那个），见 `RopeView`。
    var showsDepartureHalo = false

    var aspectHeight: CGFloat { layout == .together ? Self.togetherHeight : Self.height }

    /// 曲线上 `x` 处的 y。二次贝塞尔的控制点在两端中点，所以 x 与参数 t 成线性。
    static func curveY(atX x: CGFloat) -> CGFloat {
        let t = (x - ticks[0]) / (ticks[3] - ticks[0])
        return avatarY + 2 * t * (1 - t) * curveSag
    }

    /// 「我」的圆心 y：刻度态落在曲线上，并肩态在头像那一行。
    var selfY: CGFloat { layout == .ticks ? Self.curveY(atX: selfX) : Self.avatarY }

    /// 「我」与对方之间那段绳子（两端各让出一个头像半径 + 2）。
    var ropeStartX: CGFloat { selfX + Self.avatarRadius + 2 }
    var ropeEndX: CGFloat { otherX - Self.avatarRadius - 2 }

    static func make(for state: RopeState) -> RopeGeometry {
        switch state {
        case .invited:
            return RopeGeometry(step: 0, selfX: ticks[0], ropeStyle: .dashed, otherStyle: .hollow)
        case .agreed:
            return RopeGeometry(step: 1, selfX: ticks[1], ropeStyle: .solid)
        case .departed:
            return RopeGeometry(step: 2, selfX: ticks[2], ropeStyle: .solid, showsDepartureHalo: true)
        case .arrived:
            // 插图态不用 selfX 画东西；给「贴到对方身边」的值，让「减弱动态效果」关着时的过渡方向是对的。
            return RopeGeometry(layout: .illustration, step: 3, selfX: 268, ropeStyle: .solid)
        case .together:
            return RopeGeometry(layout: .together, step: 3, selfX: 150, otherX: 194, ropeStyle: .gold)
        case .cancelled(let previous):
            var geometry = make(for: previous)
            geometry.ropeStyle = .broken
            geometry.otherStyle = .greyed
            geometry.showsDepartureHalo = false
            return geometry
        }
    }

    /// 断开时每一段向两端各回缩的长度（交付包 03：各缩短 12）。
    static let breakRetraction: CGFloat = 12
}

// MARK: 绳子

/// 一段绳子：整根二次曲线（`curveStartX`…`curveEndX`，控制点在中点、低 `sag`）上
/// 从 `fromX` 到 `toX` 的那一截，可以在中点断开。
///
/// 截取用二次贝塞尔的分段公式**精确**算出子曲线，而不是按弧长 `trimmedPath`：
/// 刻度圆点是按 `RopeGeometry.curveY` 摆的，两边差一点点，圆点就会浮在绳子外面。
struct RopeShape: Shape {
    var curveStartX: CGFloat
    var curveEndX: CGFloat
    var y: CGFloat
    var sag: CGFloat
    var fromX: CGFloat
    var toX: CGFloat
    /// 断口两侧各回缩多少 pt（0 = 不断）。
    var gap: CGFloat = 0
    /// 画出的比例（0…1），「绳子接上」时从左往右画出。
    var drawn: CGFloat = 1

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { .init(.init(fromX, toX), .init(gap, drawn)) }
        set {
            fromX = newValue.first.first
            toX = newValue.first.second
            gap = newValue.second.first
            drawn = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let s = rect.width / RopeGeometry.width
        let span = max(curveEndX - curveStartX, 1)
        let t0 = min(max((fromX - curveStartX) / span, 0), 1)
        let t1 = min(max((toX - curveStartX) / span, 0), 1)
        let p0 = CGPoint(x: curveStartX, y: y)
        let c = CGPoint(x: (curveStartX + curveEndX) / 2, y: y + sag)
        let p2 = CGPoint(x: curveEndX, y: y)
        func point(_ t: CGFloat) -> CGPoint {
            let a = (1 - t) * (1 - t), b = 2 * t * (1 - t), d = t * t
            return CGPoint(x: (a * p0.x + b * c.x + d * p2.x) * s, y: (a * p0.y + b * c.y + d * p2.y) * s)
        }
        // 子曲线的控制点 = 二次曲线在 (t0, t1) 处的「开花」值。
        let w0 = (1 - t0) * (1 - t1), w1 = (1 - t0) * t1 + t0 * (1 - t1), w2 = t0 * t1
        let control = CGPoint(x: (w0 * p0.x + w1 * c.x + w2 * p2.x) * s, y: (w0 * p0.y + w1 * c.y + w2 * p2.y) * s)

        var full = Path()
        full.move(to: point(t0))
        full.addQuadCurve(to: point(t1), control: control)

        let length = max(toX - fromX, 1)
        let gapFraction = min(gap / length, 0.5)
        guard gapFraction > 0 else { return full.trimmedPath(from: 0, to: drawn) }
        var broken = full.trimmedPath(from: 0, to: 0.5 - gapFraction)
        broken.addPath(full.trimmedPath(from: 0.5 + gapFraction, to: 1))
        return broken
    }
}

// MARK: 视图

struct RopeView: View {
    enum Theme {
        /// 彩色头卡（交付包 v2 C03）。关联值是当前头卡的状态色 —— 「我」头像里的字、打勾刻度里的勾用它。
        case onHero(Color)
    }

    let state: RopeState
    var theme: Theme = .onHero(AppColors.Flow.stateAgreed)
    /// 陪跑员的姓氏。陪跑员视角是「我」自己（默认写「我」）；跑者视角是右边那个头像。
    var volunteerInitial: String = "我"
    /// 跑者姓名（掩码），取首字。只在陪跑员视角用（右边那个头像）。
    var runnerName: String?
    /// 出发中追加到读屏标签里的「还有 N 分钟到」。
    var remainingMinutes: Int?
    /// 盲人端订单页传 `.runner`：左边写「我」、右边写 `volunteerInitial`。
    var perspective: RopePerspective = .volunteer

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 「邀请 → 约好」时实线从左往右画出（交付包 03 §二第一行，easeInOut 0.6 秒）。
    @State private var drawn: CGFloat = 1
    @State private var lastState: RopeState?

    private var geometry: RopeGeometry { .make(for: state) }

    /// 左边：永远是「我」。
    private var selfInitial: String {
        perspective == .runner ? "我" : volunteerInitial
    }

    /// 右边：对方。
    private var otherInitial: String {
        if perspective == .runner { return volunteerInitial }
        return runnerName?.unmaskedForSpeech.first.map(String.init) ?? "跑"
    }

    private var stateColor: Color {
        switch theme {
        case .onHero(let color): return color
        }
    }

    /// 交付包 03 §二：默认 spring；「减弱动态效果」下只做 0.2 秒淡入淡出、直接跳到终态（§四）。
    ///
    /// 2026-10-07 阻尼 0.85 → 0.6（负责人：绳子要「有点弹性和重力效果」，OpenSpec
    /// `redesign-blind-runner-screens-a`）：状态切换时位置会过冲一点再落定，像真的绳子被拉了一下。
    /// 两端共用这一处。**只在状态切换时晃**，静止时不摆动 —— 盲人端禁止非用户触发的常驻动效
    /// （`design-direction.md` §7）。
    static let springDamping: Double = 0.6

    private var animation: Animation {
        if reduceMotion { return .easeInOut(duration: 0.2) }
        return .spring(response: 0.5, dampingFraction: Self.springDamping)
    }

    var body: some View {
        let g = geometry
        GeometryReader { proxy in
            let s = proxy.size.width / RopeGeometry.width
            content(g, scale: s)
                // 减弱动态效果：不插值位置，整幅换成新状态并交叉淡入。
                .id(reduceMotion ? AnyHashable(g.animationKey) : AnyHashable(g.layout))
                .transition(.opacity)
        }
        .aspectRatio(RopeGeometry.width / g.aspectHeight, contentMode: .fit)
        .animation(animation, value: geometry)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.accessibilityLabel(remainingMinutes: remainingMinutes, perspective: perspective))
        .modifier(RopeIdentifier(perspective: perspective))
        .onAppear { lastState = state }
        .onChange(of: state) { newState in
            defer { lastState = newState }
            // 从第 1 格（邀请，或先通个电话）进约好都画：盲人订单页走的是「先通个电话 → 约好」。
            guard lastState?.step == 0, newState == .agreed, !reduceMotion else { return }
            var reset = Transaction()
            reset.disablesAnimations = true
            withTransaction(reset) { drawn = 0 }
            // 下一轮再起动画：同一轮里先置 0 再置 1 会被合并成「没变」。
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.6)) { drawn = 1 } // guard:allow motion-not-gated（上面 guard 已排除 reduceMotion）
            }
        }
    }

    @ViewBuilder
    private func content(_ g: RopeGeometry, scale s: CGFloat) -> some View {
        switch g.layout {
        case .ticks:
            ticksContent(g, scale: s)
        case .illustration:
            RopeTogetherIllustration(tint: stateColor, leftInitial: selfInitial, rightInitial: otherInitial)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .together:
            togetherContent(g, scale: s)
        }
    }

    // MARK: 刻度态

    private func ticksContent(_ g: RopeGeometry, scale s: CGFloat) -> some View {
        let r = RopeGeometry.avatarRadius * s
        let ticks = RopeGeometry.ticks
        let titles = RopeState.stepTitles(perspective: perspective)
        return ZStack(alignment: .topLeading) {
            // 走过的那段：一条细淡线，只为把打过勾的刻度串起来。
            if g.step > 0 {
                RopeShape(
                    curveStartX: ticks[0], curveEndX: ticks[3], y: RopeGeometry.avatarY, sag: RopeGeometry.curveSag,
                    fromX: ticks[0], toX: g.selfX
                )
                .stroke(AppColors.Flow.ropeMuted, style: StrokeStyle(lineWidth: 2 * s, lineCap: .round))
            }

            // 还要走的那段 = 引导绳本身。
            RopeShape(
                curveStartX: ticks[0], curveEndX: ticks[3], y: RopeGeometry.avatarY, sag: RopeGeometry.curveSag,
                fromX: g.ropeStartX, toX: g.ropeEndX,
                gap: g.ropeStyle == .broken ? RopeGeometry.breakRetraction : 0,
                drawn: g.ropeStyle == .solid ? drawn : 1
            )
            .stroke(ropeColor(g.ropeStyle), style: ropeStroke(g.ropeStyle, scale: s))

            // 前三个刻度（第四个是对方头像）。「我」所在那一格不画。
            ForEach(0..<3, id: \.self) { index in
                if index != g.step {
                    tickMark(done: index < g.step, scale: s)
                        .position(x: ticks[index] * s, y: RopeGeometry.curveY(atX: ticks[index]) * s)
                }
            }

            ForEach(0..<4, id: \.self) { index in
                stepLabel(titles[index], isCurrent: index == g.step, scale: s)
                    .position(x: ticks[index] * s, y: RopeGeometry.labelCenterY * s)
            }

            otherAvatar(style: g.otherStyle, radius: r, scale: s)
                .position(x: g.otherX * s, y: RopeGeometry.avatarY * s)

            if g.showsDepartureHalo && perspective == .volunteer {
                Circle()
                    .fill(Color.white)
                    .frame(width: 56 * s, height: 56 * s)
                    // 半径 22→28 × 透明度 22%→0，2.0 秒循环（交付包 03 §三）。
                    .flowLoopingPulse(period: 2.0, from: 0.22, to: 0, scaleFrom: 22 / 28, scaleTo: 1)
                    .position(x: g.selfX * s, y: g.selfY * s)
            }

            selfAvatar(radius: r, scale: s)
                .position(x: g.selfX * s, y: g.selfY * s)
        }
    }

    /// 走过的刻度：白色实心 + 头卡色的勾；没到的：白描边空心圈。
    @ViewBuilder
    private func tickMark(done: Bool, scale s: CGFloat) -> some View {
        if done {
            Image(systemName: "checkmark")
                .font(.system(size: 10 * s, weight: .heavy))
                .foregroundColor(stateColor)
                .frame(width: 18 * s, height: 18 * s)
                .background(Circle().fill(Color.white))
        } else {
            Circle()
                .strokeBorder(AppColors.Flow.ropeLine, lineWidth: 2 * s)
                .frame(width: 14 * s, height: 14 * s)
        }
    }

    /// 刻度文字。整根绳是**一个**读屏元素（`children: .ignore`），这些字只给眼睛看。
    /// 当前格白色加粗；其余用小标题那一档半透明白（压每种状态色都 ≥4.5，`FlowDesignSystemTests`）——
    /// 做过 / 没到由刻度形状区分，不靠把字压淡。
    private func stepLabel(_ title: String, isCurrent: Bool, scale s: CGFloat) -> some View {
        Text(title)
            // 跟随 Dynamic Type（理由同头像里的字），宽高由绳子几何定死，大字号下靠 `minimumScaleFactor` 缩回。
            .flowFont(size: 15 * s, weight: isCurrent ? .heavy : .semibold, relativeTo: .footnote)
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .foregroundColor(isCurrent ? AppColors.Flow.onHeroStrong : AppColors.Flow.onHeroEyebrow)
            .frame(width: 92 * s, height: 26 * s)
    }

    // MARK: 并肩态（跑步中衔接）

    private func togetherContent(_ g: RopeGeometry, scale s: CGFloat) -> some View {
        let r = RopeGeometry.avatarRadius * s
        return ZStack(alignment: .topLeading) {
            RopeShape(curveStartX: 146, curveEndX: 196, y: 49, sag: 8, fromX: 146, toX: 196)
                .stroke(AppColors.Flow.gold, style: StrokeStyle(lineWidth: 3 * s, lineCap: .round))
            otherAvatar(style: .solid, radius: r, scale: s)
                .position(x: g.otherX * s, y: RopeGeometry.avatarY * s)
            selfAvatar(radius: r, scale: s)
                .position(x: g.selfX * s, y: RopeGeometry.avatarY * s)
        }
    }

    // MARK: 头像

    /// 「我」：白色实心，字用头卡色。
    private func selfAvatar(radius r: CGFloat, scale s: CGFloat) -> some View {
        avatar(initial: selfInitial, fill: .white, text: stateColor, radius: r, scale: s)
    }

    @ViewBuilder
    private func otherAvatar(style: RopeGeometry.OtherStyle, radius r: CGFloat, scale s: CGFloat) -> some View {
        switch style {
        case .hollow:
            Text(otherInitial)
                .flowFont(size: 17 * s, weight: .bold, relativeTo: .footnote)
                .minimumScaleFactor(0.4)
                .lineLimit(1)
                .foregroundColor(AppColors.Flow.onHeroEyebrow)
                .frame(width: 2 * r - 2 * s, height: 2 * r - 2 * s)
                .overlay(
                    Circle().strokeBorder(AppColors.Flow.ropeMuted, style: StrokeStyle(lineWidth: 2 * s, dash: [3 * s, 3 * s]))
                )
        case .solid:
            avatar(initial: otherInitial, fill: AppColors.Flow.runnerFill, text: .white, stroke: .white, radius: r, scale: s)
        case .greyed:
            avatar(initial: otherInitial, fill: AppColors.Flow.runnerFill, text: .white, stroke: .white, radius: r, scale: s)
                .saturation(0)
                .opacity(0.6)
        }
    }

    private func avatar(
        initial: String, fill: Color, text: Color, stroke: Color? = nil, radius r: CGFloat, scale s: CGFloat
    ) -> some View {
        Text(initial)
            // 跟随 Dynamic Type（同 `FlowAvatar`）；圆的直径由绳子几何定死，大字号下靠
            // `minimumScaleFactor` 缩回圆里。写死 `.system(size:)` 会被无障碍审计判「改不了字号」——
            // 读屏隐藏的字照样被审计（2026-10-06 盲人订单页横屏审计红出来的）。
            .flowFont(size: 17 * s, weight: .bold, relativeTo: .footnote)
            .minimumScaleFactor(0.4)
            .lineLimit(1)
            .foregroundColor(text)
            .frame(width: 2 * r, height: 2 * r)
            .background(Circle().fill(fill))
            .overlay(Circle().strokeBorder(stroke ?? .clear, lineWidth: 2 * s))
    }

    private func ropeColor(_ style: RopeGeometry.RopeStyle) -> Color {
        switch style {
        case .dashed, .broken: return AppColors.Flow.ropeMuted
        case .solid: return AppColors.Flow.ropeLine
        case .gold: return AppColors.Flow.gold
        }
    }

    private func ropeStroke(_ style: RopeGeometry.RopeStyle, scale s: CGFloat) -> StrokeStyle {
        switch style {
        case .dashed: return StrokeStyle(lineWidth: 2.5 * s, lineCap: .round, dash: [2 * s, 7 * s])
        case .solid, .gold, .broken: return StrokeStyle(lineWidth: 3 * s, lineCap: .round)
        }
    }
}

/// 两端各一个 identifier。写成字面量分支而不是参数：`guard.mjs` 的 `stale-ui-test-identifier`
/// 只认字面量调用形式（理由同 `OrderFlowBottomActions.Owner`）。
private struct RopeIdentifier: ViewModifier {
    let perspective: RopePerspective

    func body(content: Content) -> some View {
        switch perspective {
        case .volunteer: content.accessibilityIdentifier("volunteerOrderRope")
        case .runner: content.accessibilityIdentifier("blindOrderFlowRope")
        }
    }
}

/// 「两人并肩」插图（`Done.dc.html`：200×84，头像半径 30、圆心相距 42 即重叠 18，下方一条金色弧线）。
/// 完成页用它（完成绿）；2026-10-13 起汇合也用它（汇合橙，负责人：两个头像贴在绳子末端难看）。
///
/// 配色（C10，按 C03 规则）：左边「我」白色实心、字用头卡色；右边对方 8% 白填充 + 2pt 白描边，
/// 外面再套一圈 2pt 头卡色做分隔 —— 它压在左边的白圆上，没有这圈底色，半透明填充会透出白色。
///
/// 进入动画（03 §二「进入完成页」①②）：插图从 0.9 倍放大并淡入，金色绳 0.8 秒画出。
/// 「减弱动态效果」下只淡入，绳子直接画满。
///
/// 不复用 `RopeView(.together)`：那是 `Rope.dc.html` 里 44pt 的「并肩」态，挂在跑步中衔接处；
/// 这是单独的一张大插图，照搬过去头像小一圈、也不重叠（4.10 对照时抓到的）。
/// 读屏隐藏 —— 头卡正文（「你和李明跑完了」「陈已到达」）已经说了同一件事。
struct RopeTogetherIllustration: View {
    /// 当前头卡色：完成绿、汇合橙。
    var tint: Color = AppColors.Flow.stateDone
    var leftInitial: String = "我"
    var rightInitial: String = "跑"

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    /// 陪跑员完成页：左边陪跑员自己，右边跑者姓氏（去掩码取首字）。
    init(tint: Color = AppColors.Flow.stateDone, leftInitial: String = "我", rightInitial: String = "跑") {
        self.tint = tint
        self.leftInitial = leftInitial
        self.rightInitial = rightInitial
    }

    init(tint: Color = AppColors.Flow.stateDone, runnerName: String?) {
        self.init(tint: tint, rightInitial: runnerName?.unmaskedForSpeech.first.map(String.init) ?? "跑")
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Path { path in
                path.move(to: CGPoint(x: 58, y: 60))
                path.addQuadCurve(to: CGPoint(x: 142, y: 60), control: CGPoint(x: 100, y: 90))
            }
            .trim(from: 0, to: appeared || reduceMotion ? 1 : 0)
            .stroke(AppColors.Flow.gold, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.8), value: appeared)
            // 跟随 Dynamic Type、圆的直径定死，大字号下靠 `minimumScaleFactor` 缩回圆里（同 `RopeView.avatar`）。
            // 写死 `.system(size:)` 会被无障碍审计判「改不了字号」—— 读屏隐藏的字照样被审计，
            // 而这张图 2026-10-13 起也画在盲人汇合页上（那一页在审计范围里）。
            Text(leftInitial)
                .flowFont(size: 22, weight: .bold, relativeTo: .title3)
                .minimumScaleFactor(0.4)
                .lineLimit(1)
                .foregroundColor(tint)
                .frame(width: 60, height: 60)
                .background(Circle().fill(Color.white))
                .position(x: 79, y: 38)
            Circle()
                .fill(tint)
                .frame(width: 64, height: 64)
                .position(x: 121, y: 38)
            Text(rightInitial)
                .flowFont(size: 22, weight: .bold, relativeTo: .title3)
                .minimumScaleFactor(0.4)
                .lineLimit(1)
                .foregroundColor(.white)
                .frame(width: 60, height: 60)
                .background(Circle().fill(AppColors.Flow.runnerFill))
                .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
                .position(x: 121, y: 38)
        }
        .frame(width: 200, height: 84)
        .scaleEffect(appeared || reduceMotion ? 1 : 0.9)
        .opacity(appeared ? 1 : 0)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.85), value: appeared)
        .onAppear { appeared = true }
        .accessibilityHidden(true)
    }
}

private extension RopeGeometry {
    /// 「减弱动态效果」时用它当 `.id`：几何变了就整幅交叉淡入，而不是插值位置。
    var animationKey: String {
        "\(layout)-\(step)-\(ropeStyle)-\(otherStyle)"
    }
}

// MARK: - Previews

#Preview("引导绳 · 各状态") {
    RopeGallery()
}

#Preview("引导绳 · 跑者视角") {
    RopeGallery(perspective: .runner)
}

#Preview("引导绳 · 深色外观") {
    RopeGallery().preferredColorScheme(.dark)
}

#Preview("引导绳 · 动画演示") {
    RopeAnimationDemo()
}

private struct RopeGallery: View {
    var perspective: RopePerspective = .volunteer

    private let states: [(String, RopeState, Color)] = [
        ("邀请 / 匹配", .invited, AppColors.Flow.stateMatching),
        ("约好", .agreed, AppColors.Flow.stateAgreed),
        ("出发", .departed(progress: 0.68), AppColors.Flow.stateDeparted),
        ("汇合", .arrived, AppColors.Flow.stateArrived),
        ("并肩", .together, AppColors.Flow.stateRunning),
        ("跑者取消（约好后）", .cancelled(after: .agreed), AppColors.Flow.stateAgreed),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(states, id: \.0) { title, state, color in
                    FlowHeroCard(style: .tinted(color)) {
                        Text(title)
                            .flowFont(FlowV2Fonts.subhead(bold: true))
                            .foregroundColor(AppColors.Flow.onHeroEyebrow)
                        RopeView(
                            state: state, theme: .onHero(color), volunteerInitial: perspective == .runner ? "张" : "我",
                            runnerName: "李*", remainingMinutes: 8, perspective: perspective
                        )
                    }
                }
                FlowHeroCard(style: .tinted(AppColors.Flow.stateDone)) {
                    RopeTogetherIllustration(runnerName: "李*")
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(FlowMetrics.v2ScreenPadding)
        }
        .background(AppColors.Flow.page)
    }
}

/// 按按钮循环切换状态，看 03 §二的状态切换动画。
private struct RopeAnimationDemo: View {
    private let sequence: [(RopeState, Color)] = [
        (.invited, AppColors.Flow.stateMatching),
        (.agreed, AppColors.Flow.stateAgreed),
        (.departed(progress: 0.2), AppColors.Flow.stateDeparted),
        (.arrived, AppColors.Flow.stateArrived),
        (.together, AppColors.Flow.stateRunning),
        (.cancelled(after: .agreed), AppColors.Flow.stateAgreed),
    ]
    @State private var index = 0

    var body: some View {
        let (state, color) = sequence[index]
        VStack(spacing: 16) {
            FlowHeroCard(style: .tinted(color)) {
                RopeView(state: state, theme: .onHero(color), runnerName: "李*", remainingMinutes: 8)
            }
            Text(state.accessibilityLabel(remainingMinutes: 8))
                .flowFont(FlowV2Fonts.callout())
            FlowActionButton("下一个状态", style: .raisedPrimary) {
                index = (index + 1) % sequence.count
            }
        }
        .padding(FlowMetrics.v2ScreenPadding)
        .background(AppColors.Flow.page)
    }
}
