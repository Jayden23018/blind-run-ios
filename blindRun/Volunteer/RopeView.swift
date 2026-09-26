import SwiftUI

// MARK: - 引导绳（陪跑员订单页 v2）
//
// 交付包 `03-motion-and-haptics.md` §一、§二、§三；精确取值对照 `reference/artboards/Rope.dc.html`。
// 语义（交付包 D2 / D3）：两个头像之间的距离 = 还要走多远；虚线 = 还没约好；实线 = 已约好；
// **不画走过的路**。步骤只给读屏。
//
// 几何是纯数据（`RopeGeometry`），视图只负责把数字画出来 —— 这样几何能在单测里验，
// 不用渲染。坐标系固定 342×56，按容器宽度等比缩放。

enum RopeState: Equatable {
    case invited
    case agreed
    /// `progress` 来自后端 `eta.progress`，绘制前再夹到 [0.1, 0.85]。
    case departed(progress: Double)
    case arrived
    /// 跑步中衔接与完成页。
    case together
    /// 跑者取消。头像停在取消前的位置。
    indirect case cancelled(after: RopeState)

    /// 读屏标签。交付包 03：「第 N 步，共 4 步，{状态}」，出发中再加「还有 N 分钟到」。
    func accessibilityLabel(remainingMinutes: Int? = nil) -> String {
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
}

/// 一个状态下引导绳的全部几何与样式。单位是 342×56 坐标系里的 pt。
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

    enum RunnerStyle: Equatable {
        /// 空心 + 虚线描边 [3, 3]，姓氏为装饰灰（还没约好）。
        case hollow
        case solid
        /// 去饱和变灰（跑者取消）。
        case greyed
    }

    static let width: CGFloat = 342
    static let height: CGFloat = 56
    static let avatarRadius: CGFloat = 22
    static let clampedProgress: ClosedRange<Double> = 0.1...0.85

    var volunteerX: CGFloat
    var runnerX: CGFloat
    var ropeStartX: CGFloat
    var ropeEndX: CGFloat
    /// 绳子两端的 y。只有并肩态不是 28（绳子挂在两个头像下方）。
    var ropeY: CGFloat = 28
    /// 二次曲线控制点相对 `ropeY` 的下垂量。
    var sag: CGFloat
    var ropeStyle: RopeStyle
    var runnerStyle: RunnerStyle = .solid
    /// x=8 处的出发地小圈。
    var showsOrigin = false
    /// 出发中陪跑员外圈的呼吸光晕。
    var showsVolunteerHalo = false
    /// 已到达时跑者外圈的金色光环。
    var showsRunnerRing = false

    static func make(for state: RopeState) -> RopeGeometry {
        switch state {
        case .invited:
            return RopeGeometry(
                volunteerX: 24, runnerX: 318, ropeStartX: 50, ropeEndX: 292,
                sag: 16, ropeStyle: .dashed, runnerStyle: .hollow
            )
        case .agreed:
            return RopeGeometry(volunteerX: 24, runnerX: 318, ropeStartX: 50, ropeEndX: 292, sag: 18, ropeStyle: .solid)
        case .departed(let progress):
            let p = min(max(progress, clampedProgress.lowerBound), clampedProgress.upperBound)
            let volunteerX = 24 + 244 * CGFloat(p)
            let start = volunteerX + 24
            let length = 292 - start
            // 交付包 03：下垂量 max(2, 18·长度/242)。画板示意（10）与公式不一致，按文档。
            return RopeGeometry(
                volunteerX: volunteerX, runnerX: 318, ropeStartX: start, ropeEndX: 292,
                sag: max(2, 18 * length / 242), ropeStyle: .solid,
                showsOrigin: true, showsVolunteerHalo: true
            )
        case .arrived:
            return RopeGeometry(
                volunteerX: 268, runnerX: 318, ropeStartX: 290, ropeEndX: 296,
                sag: 0, ropeStyle: .solid, showsOrigin: true, showsRunnerRing: true
            )
        case .together:
            return RopeGeometry(
                volunteerX: 150, runnerX: 194, ropeStartX: 146, ropeEndX: 196,
                ropeY: 49, sag: 8, ropeStyle: .gold
            )
        case .cancelled(let previous):
            var geometry = make(for: previous)
            geometry.ropeStyle = .broken
            geometry.runnerStyle = .greyed
            geometry.showsVolunteerHalo = false
            geometry.showsRunnerRing = false
            return geometry
        }
    }

    /// 断开时每一段向两端各回缩的长度（交付包 03：各缩短 12）。
    static let breakRetraction: CGFloat = 12
}

// MARK: 绳子

/// 一条二次曲线，可以在中点断开。所有几何量都进 `animatableData`，状态切换时由 SwiftUI 插值。
struct RopeShape: Shape {
    var startX: CGFloat
    var endX: CGFloat
    var y: CGFloat
    var sag: CGFloat
    /// 断口两侧各回缩多少 pt（0 = 不断）。
    var gap: CGFloat
    /// 画出的比例（0…1），「绳子接上」时从左往右画出。
    var drawn: CGFloat = 1

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>>> {
        get { .init(.init(startX, endX), .init(.init(y, sag), .init(gap, drawn))) }
        set {
            startX = newValue.first.first
            endX = newValue.first.second
            y = newValue.second.first.first
            sag = newValue.second.first.second
            gap = newValue.second.second.first
            drawn = newValue.second.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let s = rect.width / RopeGeometry.width
        let a = CGPoint(x: startX * s, y: y * s)
        let b = CGPoint(x: endX * s, y: y * s)
        let c = CGPoint(x: (startX + endX) / 2 * s, y: (y + sag) * s)
        var full = Path()
        full.move(to: a)
        full.addQuadCurve(to: b, control: c)

        let length = max(endX - startX, 1)
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
        /// 藏青头卡、锁屏。
        case dark
        /// 白色头卡（仅邀请）。
        case light
    }

    let state: RopeState
    var theme: Theme = .dark
    /// 陪跑员自己的姓氏（本机知道）。
    var volunteerInitial: String = "我"
    /// 跑者姓名（掩码），取首字。
    var runnerName: String?
    /// 出发中追加到读屏标签里的「还有 N 分钟到」。
    var remainingMinutes: Int?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 「邀请 → 约好」时实线从左往右画出（交付包 03 §二第一行，easeInOut 0.6 秒）。
    @State private var drawn: CGFloat = 1
    @State private var lastState: RopeState?

    private var geometry: RopeGeometry { .make(for: state) }

    private var runnerInitial: String {
        runnerName?.unmaskedForSpeech.first.map(String.init) ?? "跑"
    }

    /// 交付包 03 §二：默认 spring；「减弱动态效果」下只做 0.2 秒淡入淡出、直接跳到终态（§四）。
    private var animation: Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.5, dampingFraction: 0.85)
    }

    var body: some View {
        GeometryReader { proxy in
            let s = proxy.size.width / RopeGeometry.width
            content(scale: s)
                // 减弱动态效果：不插值位置，整幅换成新状态并交叉淡入。
                .id(reduceMotion ? AnyHashable(geometry.animationKey) : AnyHashable(0))
                .transition(.opacity)
        }
        .aspectRatio(RopeGeometry.width / RopeGeometry.height, contentMode: .fit)
        .animation(animation, value: geometry)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.accessibilityLabel(remainingMinutes: remainingMinutes))
        .accessibilityIdentifier("volunteerOrderRope")
        .onAppear { lastState = state }
        .onChange(of: state) { newState in
            defer { lastState = newState }
            guard lastState == .invited, newState == .agreed, !reduceMotion else { return }
            var reset = Transaction()
            reset.disablesAnimations = true
            withTransaction(reset) { drawn = 0 }
            // 下一轮再起动画：同一轮里先置 0 再置 1 会被合并成「没变」。
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.6)) { drawn = 1 }
            }
        }
    }

    @ViewBuilder
    private func content(scale s: CGFloat) -> some View {
        let g = geometry
        let r = RopeGeometry.avatarRadius * s
        ZStack(alignment: .topLeading) {
            if g.showsOrigin {
                Circle()
                    .stroke(colors.mutedStroke, lineWidth: 2 * s)
                    .frame(width: 8 * s, height: 8 * s)
                    .position(x: 8 * s, y: 28 * s)
                    .transition(.opacity)
            }

            RopeShape(
                startX: g.ropeStartX, endX: g.ropeEndX, y: g.ropeY, sag: g.sag,
                gap: g.ropeStyle == .broken ? RopeGeometry.breakRetraction : 0,
                drawn: g.ropeStyle == .solid ? drawn : 1
            )
            .stroke(ropeColor(g.ropeStyle), style: ropeStroke(g.ropeStyle, scale: s))

            if g.showsRunnerRing {
                Circle()
                    .stroke(AppColors.Flow.gold, lineWidth: 2.5 * s)
                    .frame(width: 54 * s, height: 54 * s)
                    .position(x: g.runnerX * s, y: 28 * s)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.8).combined(with: .opacity))
            }

            runnerAvatar(style: g.runnerStyle, radius: r, scale: s)
                .position(x: g.runnerX * s, y: 28 * s)

            if g.showsVolunteerHalo {
                Circle()
                    .fill(colors.volunteer)
                    .frame(width: 56 * s, height: 56 * s)
                    // 半径 22→28 × 透明度 22%→0，2.0 秒循环（交付包 03 §三）。
                    .flowLoopingPulse(period: 2.0, from: 0.22, to: 0, scaleFrom: 22 / 28, scaleTo: 1)
                    .position(x: g.volunteerX * s, y: 28 * s)
            }
            avatar(initial: volunteerInitial, fill: colors.volunteer, text: .white, radius: r, scale: s)
                .position(x: g.volunteerX * s, y: 28 * s)
        }
    }

    @ViewBuilder
    private func runnerAvatar(style: RopeGeometry.RunnerStyle, radius r: CGFloat, scale s: CGFloat) -> some View {
        switch style {
        case .hollow:
            Text(runnerInitial)
                .font(.system(size: 17 * s, weight: .bold))
                .foregroundColor(colors.hollowInitial)
                .frame(width: 2 * r - 2 * s, height: 2 * r - 2 * s)
                .background(Circle().fill(colors.hollowFill))
                .overlay(
                    Circle().strokeBorder(colors.hollowStroke, style: StrokeStyle(lineWidth: 2 * s, dash: [3 * s, 3 * s]))
                )
        case .solid:
            avatar(initial: runnerInitial, fill: colors.runner, text: .white, radius: r, scale: s)
        case .greyed:
            avatar(initial: runnerInitial, fill: colors.runner, text: .white, radius: r, scale: s)
                .saturation(0)
                .opacity(0.6)
        }
    }

    private func avatar(initial: String, fill: Color, text: Color, radius r: CGFloat, scale s: CGFloat) -> some View {
        Text(initial)
            .font(.system(size: 17 * s, weight: .bold))
            .foregroundColor(text)
            .frame(width: 2 * r, height: 2 * r)
            .background(Circle().fill(fill))
    }

    private func ropeColor(_ style: RopeGeometry.RopeStyle) -> Color {
        switch style {
        case .dashed: return colors.dashedRope
        case .solid: return colors.rope
        case .gold: return AppColors.Flow.gold
        case .broken: return colors.dashedRope
        }
    }

    private func ropeStroke(_ style: RopeGeometry.RopeStyle, scale s: CGFloat) -> StrokeStyle {
        switch style {
        case .dashed: return StrokeStyle(lineWidth: 2.5 * s, lineCap: .round, dash: [2 * s, 7 * s])
        case .solid, .gold, .broken: return StrokeStyle(lineWidth: 3 * s, lineCap: .round)
        }
    }

    private var colors: RopeColors { theme == .dark ? .dark : .light }
}

/// 两套主题的配色（交付包 03「配色」+ `Rope.dc.html`）。
private struct RopeColors {
    let volunteer: Color
    let runner: Color
    let rope: Color
    let dashedRope: Color
    let mutedStroke: Color
    let hollowFill: Color
    let hollowStroke: Color
    let hollowInitial: Color

    static let dark = RopeColors(
        volunteer: AppColors.Flow.volunteerDot,
        runner: AppColors.Flow.runnerDot,
        rope: AppColors.Flow.ropeOnNavy,
        dashedRope: AppColors.Flow.mutedOnNavy,
        mutedStroke: AppColors.Flow.mutedStrokeOnNavy,
        hollowFill: AppColors.Flow.navy,
        hollowStroke: AppColors.Flow.mutedStrokeOnNavy,
        hollowInitial: AppColors.Flow.onNavyEyebrow
    )

    static let light = RopeColors(
        volunteer: AppColors.Flow.accent,
        runner: AppColors.Flow.navy,
        rope: AppColors.Flow.accent,
        dashedRope: AppColors.Flow.decorMuted,
        mutedStroke: AppColors.Flow.decorMuted,
        hollowFill: AppColors.Flow.surface,
        hollowStroke: AppColors.Flow.decorMuted,
        hollowInitial: AppColors.Flow.decorMutedInk
    )
}

private extension RopeGeometry {
    /// 「减弱动态效果」时用它当 `.id`：几何变了就整幅交叉淡入，而不是插值位置。
    var animationKey: String {
        "\(volunteerX)-\(runnerX)-\(ropeStyle)-\(runnerStyle)"
    }
}

// MARK: - Previews

#Preview("引导绳 · 六个状态") {
    RopeGallery()
}

#Preview("引导绳 · 深色外观") {
    RopeGallery().preferredColorScheme(.dark)
}

#Preview("引导绳 · 动画演示") {
    RopeAnimationDemo()
}

private struct RopeGallery: View {
    private let states: [(String, RopeState)] = [
        ("邀请", .invited),
        ("约好", .agreed),
        ("出发 p=0.68", .departed(progress: 0.68)),
        ("出发 p=0.02（夹到 0.1）", .departed(progress: 0.02)),
        ("汇合", .arrived),
        ("并肩", .together),
        ("跑者取消（出发中）", .cancelled(after: .departed(progress: 0.5))),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                FlowHeroCard(style: .light) {
                    Text("邀请 · 浅色主题").flowFont(FlowV2Fonts.subhead(bold: true))
                    RopeView(state: .invited, theme: .light, volunteerInitial: "张", runnerName: "李*")
                }
                ForEach(states, id: \.0) { title, state in
                    FlowHeroCard(style: .navy) {
                        Text(title)
                            .flowFont(FlowV2Fonts.subhead(bold: true))
                            .foregroundColor(AppColors.Flow.onNavyEyebrow)
                        RopeView(state: state, volunteerInitial: "张", runnerName: "李*", remainingMinutes: 8)
                    }
                }
            }
            .padding(FlowMetrics.v2ScreenPadding)
        }
        .background(AppColors.Flow.page)
    }
}

/// 按按钮循环切换状态，看 03 §二的状态切换动画。
private struct RopeAnimationDemo: View {
    private let sequence: [RopeState] = [
        .invited, .agreed, .departed(progress: 0.2), .departed(progress: 0.6),
        .arrived, .together, .cancelled(after: .departed(progress: 0.6)),
    ]
    @State private var index = 0

    var body: some View {
        VStack(spacing: 16) {
            FlowHeroCard(style: .navy) {
                RopeView(state: sequence[index], volunteerInitial: "张", runnerName: "李*", remainingMinutes: 8)
            }
            Text(sequence[index].accessibilityLabel(remainingMinutes: 8))
                .flowFont(FlowV2Fonts.callout())
            FlowActionButton("下一个状态", style: .raisedPrimary) {
                index = (index + 1) % sequence.count
            }
        }
        .padding(FlowMetrics.v2ScreenPadding)
        .background(AppColors.Flow.page)
    }
}
