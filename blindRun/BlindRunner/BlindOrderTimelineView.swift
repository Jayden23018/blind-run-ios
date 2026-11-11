import SwiftUI

// MARK: - 视图

/// 五步竖线。当前步下面插调用方给的那张卡（`current`）。
///
/// 折叠行点一下就地展开，展开状态是这个视图自己的 `@State`；订单换到下一步时复位。
struct BlindOrderTimelineView<Current: View>: View {
    let input: BlindOrderTimelineInput
    @ViewBuilder let current: (BlindOrderTimelineStep) -> Current

    @State private var pastExpanded = false
    @State private var futureExpanded = false
    /// 刚从 ① 揭开到这一屏（#926）。为真时当前行从下方 8pt 淡入，见 `BlindOrderStageArrivalReveal`。
    @Environment(\.blindOrderStageArrival) private var arrival

    init(input: BlindOrderTimelineInput, @ViewBuilder current: @escaping (BlindOrderTimelineStep) -> Current) {
        self.input = input
        self.current = current
    }

    private var rows: [BlindOrderTimelineRow] {
        BlindOrderTimelineLayout.rows(input, pastExpanded: pastExpanded, futureExpanded: futureExpanded)
    }

    var body: some View {
        let rows = rows
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                rowView(row)
                    .background(alignment: .topLeading) {
                        if index < rows.count - 1 {
                            // 找到那一刻（#926）：连到当前步的那段走过的竖线从上往下长出来。
                            BlindOrderTimelineConnector(
                                isPast: row.isPast,
                                growsIn: arrival && row.isPast && rows[index + 1].isCurrent
                            )
                        }
                    }
            }
        }
        .onChange(of: input.position) { _ in
            pastExpanded = false
            futureExpanded = false
        }
    }

    @ViewBuilder
    private func rowView(_ row: BlindOrderTimelineRow) -> some View {
        switch row {
        case .current(let step, _):
            HStack(alignment: .top, spacing: BlindOrderTimelineMetrics.gap) {
                BlindOrderTimelineDot(kind: .current, currentDot: input.currentDot)
                VStack(alignment: .leading, spacing: 0) {
                    titleBlock(row)
                    current(step)
                        .padding(.top, 10)
                        .modifier(BlindOrderTimelineCardFadeOut(isActive: input.currentDot == .justFound))
                }
                .modifier(BlindOrderStageArrivalReveal(isActive: arrival))
            }
            .padding(.bottom, BlindOrderTimelineMetrics.rowSpacing)
        case .doneFold, .todoFold:
            foldRow(row)
        case .stopped:
            // 中断那一步（#946）：空心圆 + ✕，下面不接卡片（负责人 11-11 去掉了说明卡）。
            HStack(alignment: .top, spacing: BlindOrderTimelineMetrics.gap) {
                BlindOrderTimelineDot(kind: .stopped)
                titleBlock(row)
            }
            .padding(.bottom, BlindOrderTimelineMetrics.rowSpacing)
            .accessibilityIdentifier("blindOrderTimelineStoppedStep")
        default:
            HStack(alignment: .top, spacing: BlindOrderTimelineMetrics.gap) {
                BlindOrderTimelineDot(kind: row.isPast ? .done : .todo)
                titleBlock(row)
            }
            .padding(.bottom, BlindOrderTimelineMetrics.rowSpacing)
        }
    }

    /// 一行的字：标题 + 可选的小字。合成一个读屏元素。
    private func titleBlock(_ row: BlindOrderTimelineRow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if case .next = row {
                    Text("下一步")
                        .flowFont(FlowV2Fonts.tag())
                        .foregroundColor(AppColors.Flow.secondaryText)
                }
                Text(visibleTitle(row))
                    .flowFont(titleFont(row))
                    .foregroundColor(titleColor(row))
            }
            .fixedSize(horizontal: false, vertical: true)
            if let detail = detail(row) {
                Text(detail)
                    .flowFont(FlowV2Fonts.subhead())
                    .foregroundColor(AppColors.Flow.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(BlindOrderTimelineLayout.accessibilityLabel(for: row))
    }

    /// 「✓ 已完成 N 步 ›」「还有 N 步 ›」。整行可点，至少 64pt 高。
    private func foldRow(_ row: BlindOrderTimelineRow) -> some View {
        Button {
            if case .doneFold = row { pastExpanded = true } else { futureExpanded = true }
        } label: {
            HStack(alignment: .center, spacing: BlindOrderTimelineMetrics.gap) {
                BlindOrderTimelineDot(kind: row.isPast ? .done : .fold)
                HStack(spacing: 4) {
                    Text(BlindOrderTimelineLayout.foldTitle(for: row) ?? "")
                        .flowFont(FlowV2Fonts.callout(bold: true))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .accessibilityHidden(true)
                }
                .foregroundColor(row.isPast ? AppColors.Flow.secondaryText : AppColors.Flow.accent)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: AppTouchTarget.blindPrimary, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(BlindOrderTimelineLayout.accessibilityLabel(for: row))
        .accessibilityHint(BlindOrderTimelineLayout.foldAccessibilityHint)
        .modifier(BlindOrderTimelineFoldIdentifier(isPast: row.isPast))
    }

    private func visibleTitle(_ row: BlindOrderTimelineRow) -> String {
        switch row {
        case .done(let step, _): return step.doneTitle
        case .current(let step, _), .stopped(let step, _), .next(let step), .todo(let step): return step.title
        case .doneFold, .todoFold: return BlindOrderTimelineLayout.foldTitle(for: row) ?? ""
        }
    }

    private func detail(_ row: BlindOrderTimelineRow) -> String? {
        switch row {
        case .done(_, let detail), .current(_, let detail), .stopped(_, let detail): return detail?.nilIfBlank
        default: return nil
        }
    }

    private func titleFont(_ row: BlindOrderTimelineRow) -> (CGFloat, Font.Weight, Font.TextStyle) {
        switch row {
        case .current, .stopped: return (17, .bold, .body)
        case .done: return (17, .semibold, .body)
        default: return (17, .medium, .body)
        }
    }

    /// 未到的步用 `secondaryText`，不用稿里的浅灰：浅灰压白底不到 4.5:1（稿 ④ 差异 3）。
    private func titleColor(_ row: BlindOrderTimelineRow) -> Color {
        switch row {
        case .current, .done, .stopped: return AppColors.Flow.primaryText
        default: return AppColors.Flow.secondaryText
        }
    }
}

// MARK: - 竖线的零件

enum BlindOrderTimelineMetrics {
    static let dotDiameter: CGFloat = 23
    static let lineWidth: CGFloat = 3
    static let gap: CGFloat = 14
    static let rowSpacing: CGFloat = 13
}

/// 圆点。纯装饰，对读屏隐藏（状态已在行的读屏标签里）。
struct BlindOrderTimelineDot: View {
    /// `stopped` = 订单在这一步中断（#946）：空心圆 + ✕。
    enum Kind { case done, current, todo, fold, stopped }
    let kind: Kind
    /// 只对 `.current` 有意义。
    var currentDot: BlindOrderTimelineCurrentDot = .still

    /// 找到那一刻的打勾放大（稿 C 帧：1.3 倍再弹回）。
    @State private var popScale: CGFloat = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var showsCheck: Bool {
        kind == .done || (kind == .current && currentDot == .justFound)
    }

    var body: some View {
        ZStack {
            Circle().fill(fill)
            if kind == .fold {
                Circle().strokeBorder(AppColors.Flow.nodeStroke, lineWidth: 2.5)
            }
            if kind == .stopped {
                // 描边与 ✕ 用 `secondaryText`：控件边界压白底要 ≥ 3:1，`nodeStroke` 那种浅灰不够。
                Circle().strokeBorder(AppColors.Flow.secondaryText, lineWidth: 2.5)
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(AppColors.Flow.secondaryText)
            }
            if showsCheck {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .scaleEffect(popScale)
        // 当前步：圆点外再画一圈浅色圈（稿 v7 第 11 条 C，取代「现在：」前缀）。
        .background {
            if kind == .current {
                BlindOrderTimelineHalo(style: currentDot)
            }
        }
        .frame(width: BlindOrderTimelineMetrics.dotDiameter, height: BlindOrderTimelineMetrics.dotDiameter)
        .accessibilityHidden(true)
        .task(id: kind == .current && currentDot == .justFound) {
            guard kind == .current, currentDot == .justFound, !reduceMotion else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: BlindMatchFoundTiming.popUp)) { popScale = BlindMatchFoundTiming.popScale }
            try? await Task.sleep(nanoseconds: UInt64(BlindMatchFoundTiming.popUp * 1_000_000_000))
            withAnimation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.55)) { popScale = 1 }
        }
    }

    private var fill: Color {
        switch kind {
        case .done, .current: return AppColors.Flow.navy
        case .todo: return AppColors.Flow.nodeStroke
        case .fold, .stopped: return AppColors.Flow.surface
        }
    }
}

/// 当前步圆点外那一圈（#926，稿 `blind-matching-wait-20261111/draft.html` 色板）。
///
/// 圈的**布局尺寸固定**为最大那一档，只动 `scaleEffect` 与透明度：`repeatForever` 若改的是 frame / padding，
/// 在 `ScrollView` 里会把整行的位置也带着动。`.animation(_:value:)` 只挂在这一个视图上，同理。
private struct BlindOrderTimelineHalo: View {
    let style: BlindOrderTimelineCurrentDot

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false

    private static let dot = BlindOrderTimelineMetrics.dotDiameter
    private static let maxRing: CGFloat = 11
    private static var maxDiameter: CGFloat { dot + 2 * maxRing }

    /// 外圈宽度与透明度。`still` 沿用 #923 的 4pt / 0.16。
    private var ring: (width: CGFloat, opacity: Double) {
        switch style {
        case .still, .justFound:
            return (4, 0.16)
        case .breathing:
            if reduceMotion { return (6, 0.14) }
            return expanded ? (11, 0.12) : (3, 0.16)
        }
    }

    var body: some View {
        let ring = ring
        Circle()
            .fill(AppColors.Flow.navy.opacity(ring.opacity))
            .frame(width: Self.maxDiameter, height: Self.maxDiameter)
            .scaleEffect((Self.dot + 2 * ring.width) / Self.maxDiameter)
            .animation(breathingAnimation, value: expanded)
            .frame(width: Self.dot, height: Self.dot)
            .onAppear { startBreathingIfNeeded() }
            .onChange(of: reduceMotion) { _ in
                // 中途关掉「减弱动态效果」要重新起；打开时 `ring` 直接落 6pt，不必停动画。
                expanded = false
                startBreathingIfNeeded()
            }
    }

    private var breathingAnimation: Animation? {
        guard style == .breathing, !reduceMotion else { return nil }
        return .easeInOut(duration: BlindMatchingWaitTiming.breathHalfCycle).repeatForever(autoreverses: true)
    }

    private func startBreathingIfNeeded() {
        guard style == .breathing, !reduceMotion else { return }
        // 推到下一拍再改：同一拍里改的话首帧就在终值，看不到动画。
        Task { @MainActor in expanded = true }
    }
}

/// 圆点下面连到下一行的那段竖线。
private struct BlindOrderTimelineConnector: View {
    let isPast: Bool
    /// 找到那一刻：从上往下长出来（稿 C 帧 0.3–0.8 秒）。
    var growsIn = false

    @State private var grown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Rectangle()
            .fill(isPast ? AppColors.Flow.navy : AppColors.Flow.nodeStroke)
            .frame(width: BlindOrderTimelineMetrics.lineWidth)
            .scaleEffect(x: 1, y: growsIn && !grown ? 0 : 1, anchor: .top)
            .padding(.top, BlindOrderTimelineMetrics.dotDiameter)
            .padding(.leading, (BlindOrderTimelineMetrics.dotDiameter - BlindOrderTimelineMetrics.lineWidth) / 2)
            .accessibilityHidden(true)
            .onAppear {
                guard growsIn else { return }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: BlindMatchFoundTiming.lineGrow)) { grown = true }
            }
    }
}

/// 找到那一刻旧卡片淡出（稿 C 帧 0–0.3 秒「旧卡片淡出」）。
private struct BlindOrderTimelineCardFadeOut: ViewModifier {
    let isActive: Bool
    @State private var faded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(isActive && faded ? 0 : 1)
            .onAppear {
                guard isActive else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: BlindMatchFoundTiming.checkPhase)) { faded = true }
            }
    }
}

// MARK: - 找到那一刻的揭开（#926）

private struct BlindOrderStageArrivalKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// 这一屏是不是刚从 ① 匹配中揭开（找到陪跑员那一刻的后半段）。订单页在过渡期间置真。
    var blindOrderStageArrival: Bool {
        get { self[BlindOrderStageArrivalKey.self] }
        set { self[BlindOrderStageArrivalKey.self] = newValue }
    }
}

/// 揭开时从下方 8pt 淡入（稿 C 帧「新卡片和主按钮从下方 8pt 淡入」）。不在过渡里时什么都不做。
struct BlindOrderStageArrivalReveal: ViewModifier {
    let isActive: Bool
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let hidden = isActive && !shown
        content
            .opacity(hidden ? 0 : 1)
            .offset(y: hidden ? BlindMatchFoundTiming.riseOffset : 0)
            .onAppear {
                guard isActive else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: BlindMatchFoundTiming.lineGrow)) { shown = true }
            }
    }
}

/// 折叠行的 identifier。字面量分支的理由同 `OrderFlowBottomActions.Owner`（守卫只认字面量）。
private struct BlindOrderTimelineFoldIdentifier: ViewModifier {
    let isPast: Bool

    func body(content: Content) -> some View {
        if isPast {
            content.accessibilityIdentifier("blindOrderTimelineDoneFold")
        } else {
            content.accessibilityIdentifier("blindOrderTimelineTodoFold")
        }
    }
}
