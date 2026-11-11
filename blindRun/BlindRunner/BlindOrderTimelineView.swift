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
                            BlindOrderTimelineConnector(isPast: row.isPast)
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
                BlindOrderTimelineDot(kind: .current)
                VStack(alignment: .leading, spacing: 0) {
                    titleBlock(row)
                    current(step)
                        .padding(.top, 10)
                }
            }
            .padding(.bottom, BlindOrderTimelineMetrics.rowSpacing)
        case .doneFold, .todoFold:
            foldRow(row)
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
        case .current(let step, _), .next(let step), .todo(let step): return step.title
        case .doneFold, .todoFold: return BlindOrderTimelineLayout.foldTitle(for: row) ?? ""
        }
    }

    private func detail(_ row: BlindOrderTimelineRow) -> String? {
        switch row {
        case .done(_, let detail), .current(_, let detail): return detail?.nilIfBlank
        default: return nil
        }
    }

    private func titleFont(_ row: BlindOrderTimelineRow) -> (CGFloat, Font.Weight, Font.TextStyle) {
        switch row {
        case .current: return (17, .bold, .body)
        case .done: return (17, .semibold, .body)
        default: return (17, .medium, .body)
        }
    }

    /// 未到的步用 `secondaryText`，不用稿里的浅灰：浅灰压白底不到 4.5:1（稿 ④ 差异 3）。
    private func titleColor(_ row: BlindOrderTimelineRow) -> Color {
        switch row {
        case .current, .done: return AppColors.Flow.primaryText
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
    enum Kind { case done, current, todo, fold }
    let kind: Kind

    var body: some View {
        ZStack {
            Circle().fill(fill)
            if kind == .fold {
                Circle().strokeBorder(AppColors.Flow.nodeStroke, lineWidth: 2.5)
            }
            if kind == .done {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        // 当前步：圆点外再画一圈浅色圈（稿 v7 第 11 条 C，取代「现在：」前缀）。
        .background(
            Circle()
                .fill(AppColors.Flow.navy.opacity(kind == .current ? 0.16 : 0))
                .padding(-4)
        )
        .frame(width: BlindOrderTimelineMetrics.dotDiameter, height: BlindOrderTimelineMetrics.dotDiameter)
        .accessibilityHidden(true)
    }

    private var fill: Color {
        switch kind {
        case .done, .current: return AppColors.Flow.navy
        case .todo: return AppColors.Flow.nodeStroke
        case .fold: return AppColors.Flow.surface
        }
    }
}

/// 圆点下面连到下一行的那段竖线。
private struct BlindOrderTimelineConnector: View {
    let isPast: Bool

    var body: some View {
        Rectangle()
            .fill(isPast ? AppColors.Flow.navy : AppColors.Flow.nodeStroke)
            .frame(width: BlindOrderTimelineMetrics.lineWidth)
            .padding(.top, BlindOrderTimelineMetrics.dotDiameter)
            .padding(.leading, (BlindOrderTimelineMetrics.dotDiameter - BlindOrderTimelineMetrics.lineWidth) / 2)
            .accessibilityHidden(true)
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
