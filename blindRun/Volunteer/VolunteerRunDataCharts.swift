import Charts
import SwiftUI

// 跑步数据页（#710）的图。数字一律来自 `VolunteerRunDataSummary`，这里只画。
//
// 🚩 每张图对读屏是**一个**元素，摘要句由调用方挂在外层（`VolunteerRunDataCopy.*Spoken`）；
// 这里的图本身一律 `accessibilityHidden`，免得读屏逐根柱子念「柱 1，柱 2」。

// MARK: - 柱图

/// 一组竖柱 + 可选的平均虚线（照定稿 `bars()`：最后一根不透明、其余 0.85）。
struct VolunteerRunDataBarChart: View {
    let values: [Double]
    let tint: Color
    /// 只给「平均」档画虚线；总计档不画。
    var average: Double?
    /// 横轴上要写字的位置（下标 → 文字）。没写的下标不出刻度。
    var axisLabels: [Int: String] = [:]
    var height: CGFloat = 130
    var highlightsLast = true

    var body: some View {
        VStack(spacing: 6) {
            chart
            VolunteerRunDataAxisLabels(count: values.count, labels: axisLabels)
                .accessibilityHidden(true)
        }
    }

    private var chart: some View {
        let top = max(values.max() ?? 0, average ?? 0, 0.1) * 1.12
        return Chart {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                BarMark(
                    x: .value("段", "\(index)"),
                    y: .value("值", value),
                    width: .ratio(0.62)
                )
                .cornerRadius(3)
                .foregroundStyle(tint.opacity(highlightsLast && index == values.count - 1 ? 1 : 0.85))
            }
            if let average, average > 0 {
                RuleMark(y: .value("平均", average))
                    .foregroundStyle(tint.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
            }
        }
        .chartYScale(domain: 0...top)
        .chartYAxis {
            AxisMarks(values: [0, top / 2, top]) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 3]))
            }
        }
        // 横轴文字自己画：Charts 把分类轴的标签宽度限在一根柱的宽度里，半年档 26 根柱时
        // 两端的「5月」「11月」被压成「…」（2026-11-05 真机审计报 Text clipped）。
        .chartXAxis(.hidden)
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// 柱图下面那行刻度文字：每个标签对准它那根柱的中心，靠边的改成向内对齐，不截断。
struct VolunteerRunDataAxisLabels: View {
    let count: Int
    let labels: [Int: String]

    var body: some View {
        // 先用一行看不见的字撑出高度（跟字号走），再按柱的位置摆每个标签。
        Text("1月")
            .font(.caption)
            .hidden()
            .frame(maxWidth: .infinity)
            .overlay {
                GeometryReader { proxy in
                    let band = proxy.size.width / CGFloat(max(1, count))
                    ForEach(labels.keys.sorted(), id: \.self) { index in
                        let centre = band * (CGFloat(index) + 0.5)
                        let alignment: Alignment = centre < band * 2 ? .leading : (centre > proxy.size.width - band * 2 ? .trailing : .center)
                        Text(labels[index] ?? "")
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary)
                            .fixedSize()
                            .frame(width: Self.slot, alignment: alignment)
                            .position(x: Self.slotCentre(centre, alignment: alignment, band: band), y: proxy.size.height / 2)
                    }
                }
            }
    }

    private static let slot: CGFloat = 64

    /// 靠左的标签左沿对准柱左沿，靠右的右沿对准柱右沿，其余居中。
    private static func slotCentre(_ centre: CGFloat, alignment: Alignment, band: CGFloat) -> CGFloat {
        switch alignment {
        case .leading: return centre - band / 2 + slot / 2
        case .trailing: return centre + band / 2 - slot / 2
        default: return centre
        }
    }
}

// MARK: - 横条对比

/// 「10 月 ▇▇▇▇ 50.1」那种一行一根的横条：提要里程对比与「一起跑的人」。
/// 数字是真文本，条只是视觉辅助。
struct VolunteerRunDataHorizontalBar: View {
    let label: String
    let value: String
    let fraction: Double
    let tint: Color
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            // 大字号下三样排不下一行：标签和数值一行，条另起一行。
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(label)
                    Spacer(minLength: 8)
                    Text(value).fontWeight(.semibold)
                }
                bar
            }
            .font(.subheadline)
        } else {
            HStack(spacing: 10) {
                Text(label)
                    .frame(minWidth: 44, alignment: .leading)
                    .foregroundColor(AppColors.textSecondary)
                bar
                Text(value)
                    .fontWeight(.semibold)
                    .frame(minWidth: 52, alignment: .trailing)
            }
            .font(.subheadline)
        }
    }

    private var bar: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(tint)
                .frame(width: max(6, proxy.size.width * min(1, max(0, fraction))))
        }
        .frame(height: 18)
        .accessibilityHidden(true)
    }
}

// MARK: - 陪跑日历

/// 26 周 × 7 天的格子，一个 `Canvas` 画完（不建 182 个视图）。上面写月份，左边写「一 三 五 日」。
struct VolunteerRunDataCalendarGrid: View {
    let weeks: [VolunteerRunDataSummary.CalendarWeek]
    let calendar: Calendar
    @Environment(\.colorScheme) private var colorScheme

    private let labelColumn: CGFloat = 18
    private let monthRow: CGFloat = 14
    private let gap: CGFloat = 1.5

    var body: some View {
        GeometryReader { proxy in
            let cell = cellSide(width: proxy.size.width)
            Canvas { context, _ in
                draw(in: &context, cell: cell)
            }
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private var columns: CGFloat { CGFloat(max(1, weeks.count)) }

    /// 宽高比随格数定，`GeometryReader` 才拿得到确定的高度。
    private var aspectRatio: CGFloat {
        // 以 11pt 一格估：宽 = 标签列 + 26 格，高 = 月份行 + 7 格。
        let width = labelColumn + columns * (11 + gap)
        let height = monthRow + 7 * (11 + gap)
        return width / height
    }

    private func cellSide(width: CGFloat) -> CGFloat {
        max(4, (width - labelColumn) / columns - gap)
    }

    private func draw(in context: inout GraphicsContext, cell: CGFloat) {
        let tones = AppColors.VolunteerHome.calendarLevelTones
        let isDark = colorScheme == .dark
        let todayStroke = Color(uiColor: UIColor(rgb: isDark ? tones[4].dark : tones[4].light))
        let labelColor = AppColors.textSecondary
        var lastMonth = -1
        for (column, week) in weeks.enumerated() {
            let x = labelColumn + CGFloat(column) * (cell + gap)
            let month = calendar.component(.month, from: week.monday)
            // 最后两列放不下「11月」三个字，到那里才换月的不写（会被右边截掉半个字）。
            if month != lastMonth, column <= weeks.count - 3 {
                lastMonth = month
                context.draw(
                    Text("\(month)月").font(.system(size: 10)).foregroundColor(labelColor),
                    at: CGPoint(x: x, y: 0),
                    anchor: .topLeading
                )
            }
            for (row, mark) in week.days.enumerated() {
                let level: Int
                switch mark {
                case .future: continue
                case .none: level = 0
                case .ran(let value): level = min(4, max(1, value))
                }
                let rect = CGRect(x: x, y: monthRow + CGFloat(row) * (cell + gap), width: cell, height: cell)
                let tone = tones[level]
                let path = Path(roundedRect: rect, cornerRadius: min(2.5, cell / 4))
                context.fill(path, with: .color(Color(uiColor: UIColor(rgb: isDark ? tone.dark : tone.light))))
                if isLastDrawnDay(column: column, row: row) {
                    context.stroke(path, with: .color(todayStroke), lineWidth: 1.2)
                }
            }
        }
        for (row, name) in [(0, "一"), (2, "三"), (4, "五"), (6, "日")] {
            context.draw(
                Text(name).font(.system(size: 9.5)).foregroundColor(labelColor),
                at: CGPoint(x: 0, y: monthRow + CGFloat(row) * (cell + gap) + cell / 2),
                anchor: .leading
            )
        }
    }

    /// 今天 = 最后一列里最后一个不是 `.future` 的格子，描一圈边。
    private func isLastDrawnDay(column: Int, row: Int) -> Bool {
        guard column == weeks.count - 1 else { return false }
        let lastDrawn = weeks[column].days.lastIndex { $0 != .future }
        return lastDrawn == row
    }
}

/// 日历下面的「少 ■■■■■ 多（按当天公里）」。
struct VolunteerRunDataCalendarLegend: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 4) {
            Spacer(minLength: 0)
            Text(VolunteerRunDataCopy.legendLess)
            ForEach(Array(AppColors.VolunteerHome.calendarLevelTones.enumerated()), id: \.offset) { _, tone in
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(Color(uiColor: UIColor(rgb: colorScheme == .dark ? tone.dark : tone.light)))
                    .frame(width: 11, height: 11)
            }
            Text(VolunteerRunDataCopy.legendMore)
        }
        .font(.caption)
        .foregroundColor(AppColors.textSecondary)
        .accessibilityHidden(true)
    }
}

// MARK: - 本周七天

/// 结论卡下面那排圆：跑过的那天实心带对勾（不只靠颜色），今天还没跑画虚线圈。
struct VolunteerRunDataWeekDots: View {
    let dots: [VolunteerRunDataSummary.WeekDot]
    @ScaledMetric(relativeTo: .body) private var side: CGFloat = 28

    var body: some View {
        HStack(spacing: 0) {
            ForEach(dots, id: \.weekday) { dot in
                VStack(spacing: 4) {
                    circle(dot)
                        .frame(width: side, height: side)
                    Text(VolunteerRunDataCopy.weekdayNames[dot.weekday])
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(VolunteerRunDataCopy.weekDotsSpoken(dots))
        .accessibilityIdentifier("volunteerRunData.weekDots")
    }

    @ViewBuilder
    private func circle(_ dot: VolunteerRunDataSummary.WeekDot) -> some View {
        if dot.ran {
            ZStack {
                Circle().fill(AppColors.VolunteerHome.streakOrange)
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundColor(.white)
            }
        } else if dot.isToday {
            Circle().strokeBorder(AppColors.VolunteerHome.streakOrange, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
        } else {
            Circle().strokeBorder(AppColors.textSecondary.opacity(dot.isFuture ? 0.35 : 0.6), lineWidth: 1.5)
        }
    }
}

// MARK: - 周 / 月 / 半年 / 年

/// 分段切换。不用系统 `Picker(.segmented)`：它固定 32pt 高，压不到可点区下限；
/// 这里每段至少 44pt 高、整段可点。
struct VolunteerRunDataRangePicker: View {
    @Binding var selection: VolunteerRunDataSummary.MileageRange
    @Environment(\.colorScheme) private var colorScheme

    /// 选中那一段的底色。暗色下卡片底（`Flow.surface` `#1C1C1E`）和轨道一样深，选中看不出来
    ///（2026-11-05 真机暗色截图），换成更亮一档的 `Flow.progressTrack`（`#3A3A3C`）。
    private var selectedFill: Color {
        colorScheme == .dark ? AppColors.Flow.progressTrack : AppColors.Flow.surface
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(VolunteerRunDataSummary.MileageRange.allCases) { range in
                let isSelected = range == selection
                Button {
                    selection = range
                } label: {
                    Text(VolunteerRunDataCopy.rangeTitle(range))
                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                        .foregroundColor(AppColors.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(isSelected ? selectedFill : Color.clear)
                                .shadow(color: .black.opacity(isSelected ? 0.08 : 0), radius: 2, y: 1)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(VolunteerRunDataCopy.mileageSection)，\(VolunteerRunDataCopy.rangeTitle(range))")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityIdentifier("volunteerRunDataRange.\(range.rawValue)")
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(AppColors.secondaryBackground)
        )
    }
}
