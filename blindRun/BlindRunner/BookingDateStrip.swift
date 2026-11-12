import SwiftUI

/// 约跑页的「哪天跑」（#821，v5 第三稿甲，负责人 2026-11-07 定）。
///
/// v4 只有一排 7 个日期圆，月份那一排是装饰、点不了（负责人：「仿照了界面，没有仿照逻辑」）。
/// 第三稿照参考图的样子、补上它的逻辑：
/// - 一整排日期圆从今天排到可约的最后一天（天数读后端 `maxLeadDays`），一直能横滑，不按周分页；
/// - 月份写在当月第一个日子正上方，跟日期一起滑（负责人选「甲」：月份与下面的日期一一对齐）；
///   选中的日子在哪个月，那个月加粗；
/// - 星期写在每个圆下面，今天写「今天」。
///
/// 读屏：整排日期合成**一个可调整元素**，上下轻扫换一天，只在能约的日子里走
/// （Apple 无障碍示例对横滑列表的做法，调研 `docs/research/booking-date-picker-20261107.md`）。
/// 辅助功能大字档一排圆放不下，改成一行一天的列表，先列 7 天，可展开全部。
struct BookingDateStrip: View {
    let now: Date
    let rules: BookingRules
    let selectedDay: Date?
    let onSelect: (Date) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsAllDaysInList = false

    /// 看得见的日期圆（参考图 48，留出描边与间距用 44）。可点区是整列、≥64 高。
    private static let dayCircleDiameter: CGFloat = 44
    private static let columnWidth: CGFloat = 48
    private static let columnSpacing: CGFloat = 10
    private static let minimumHitHeight: CGFloat = AppTouchTarget.blindPrimary
    /// 大字档列表先列几天。
    private static let collapsedListCount = 7

    private var calendar: Calendar { .aidRunBackend }
    private var days: [Date] { BookingSlotPlanner.days(now: now, rules: rules) }
    private var usesList: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if usesList {
                dayList
            } else {
                strip
            }
            Text(BookingCalendar.rangeFootnote(now: now, rules: rules) + (usesList ? "" : " · 左右滑看更多"))
                .font(AppFonts.caption())
                .foregroundColor(AppColors.Flow.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .accessibilityIdentifier("bookingDateRangeFootnote")
        }
        .padding(.vertical, 16)
    }

    // MARK: 一整排

    private var strip: some View {
        let days = days
        return ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Self.columnSpacing) {
                    ForEach(days, id: \.self) { day in
                        VStack(spacing: 8) {
                            monthLabel(for: day, in: days)
                            dayCell(day)
                        }
                        .frame(width: Self.columnWidth)
                        .id(day)
                    }
                }
                .padding(.horizontal, 16)
            }
            .onAppear { scroll(proxy, to: selectedDay, animated: false) }
            .onChange(of: selectedDay) { scroll(proxy, to: $0, animated: true) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("日期")
        .accessibilityValue(spokenSelection)
        .accessibilityHint("上下轻扫换一天")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: stepSelection(by: 1)
            case .decrement: stepSelection(by: -1)
            @unknown default: break
            }
        }
        .accessibilityIdentifier("bookingDateStrip")
    }

    /// 月份字：只写在当月第一个日子上方，其余列留同样高的空白，让下面的圆对齐。
    /// 不做成按钮：它就在那个月第一天正上方，点那一天即可；字高不到 64pt，做成按钮就是盲人端够不着的小目标。
    private func monthLabel(for day: Date, in days: [Date]) -> some View {
        let text = BookingCalendar.monthLabel(for: day, in: days)
        let isCurrent = selectedDay.map { calendar.isDate($0, equalTo: day, toGranularity: .month) } ?? false
        return Text(text ?? " ")
            .font(.subheadline.weight(isCurrent ? .bold : .regular))
            .foregroundColor(isCurrent ? AppColors.Flow.primaryText : AppColors.Flow.secondaryText)
            .lineLimit(1)
            .fixedSize()
            .frame(width: Self.columnWidth, alignment: .center)
    }

    private func dayCell(_ day: Date) -> some View {
        let isAvailable = BookingCalendar.state(of: day, now: now, rules: rules) == .available
        let isSelected = selectedDay == day
        let isToday = calendar.isDate(day, inSameDayAs: now)
        return Button {
            onSelect(day)
        } label: {
            VStack(spacing: 6) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.title3.weight(isSelected ? .bold : .regular))
                    .foregroundColor(dayNumberColor(isAvailable: isAvailable, isSelected: isSelected))
                    .frame(width: Self.dayCircleDiameter, height: Self.dayCircleDiameter) // guard:allow small-touch-target 只是圆，可点区是整列、64 高
                    .background(Circle().fill(dayFill(isAvailable: isAvailable, isSelected: isSelected)))
                    .overlay(dayBorder(isAvailable: isAvailable, isSelected: isSelected))
                Text(isToday ? "今天" : BookingSlotText.weekdayName(day))
                    .font(AppFonts.caption().weight(isSelected || isToday ? .semibold : .regular))
                    .foregroundColor(isSelected || isToday ? AppColors.Flow.navy : AppColors.Flow.secondaryText)
                    .lineLimit(1)
                    .fixedSize()
            }
            .frame(width: Self.columnWidth)
            .frame(minHeight: Self.minimumHitHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
    }

    private func dayNumberColor(isAvailable: Bool, isSelected: Bool) -> Color {
        guard isAvailable else { return AppColors.Flow.secondaryText }
        return isSelected ? .white : AppColors.Flow.primaryText
    }

    /// 选中：藏青实心 + 白字（#971，负责人 2026-11-12 批准；原是白底 + 蓝描边）；能约：浅蓝底；不能约：不填色。
    private func dayFill(isAvailable: Bool, isSelected: Bool) -> Color {
        if isSelected { return AppColors.Flow.navy }
        return isAvailable ? AppColors.Flow.blueTint : .clear
    }

    @ViewBuilder
    private func dayBorder(isAvailable: Bool, isSelected: Bool) -> some View {
        if isSelected {
            Circle().strokeBorder(AppColors.Flow.navy, lineWidth: 1.5)
        } else if isAvailable {
            // 浅蓝填充压白卡对比度不够，低视力看不出能点：加灰描边过 3:1（与 v4 同一条有意偏离，负责人 11-06 定）。
            Circle().strokeBorder(AppColors.ButtonPalette.neutralStroke, lineWidth: 1)
        } else {
            Circle().strokeBorder(AppColors.ButtonPalette.neutralStroke, style: StrokeStyle(lineWidth: 1, dash: [3]))
        }
    }

    // MARK: 大字档：一行一天

    private var dayList: some View {
        let days = days
        let shown = showsAllDaysInList ? days : Array(days.prefix(Self.collapsedListCount))
        return VStack(spacing: 8) {
            ForEach(shown, id: \.self) { day in
                let isAvailable = BookingCalendar.state(of: day, now: now, rules: rules) == .available
                BookingChoicePill(
                    title: BookingSlotText.spokenDay(day, now: now),
                    subtitle: isAvailable ? nil : "这天没有能约的时段",
                    isSelected: selectedDay == day,
                    height: Self.minimumHitHeight,
                    isEnabled: isAvailable,
                    fillsWidth: true
                ) { onSelect(day) }
            }
            if days.count > Self.collapsedListCount {
                BookingChoicePill(
                    title: showsAllDaysInList ? "收起" : "显示全部 \(days.count) 天",
                    isSelected: false,
                    height: Self.minimumHitHeight,
                    fillsWidth: true
                ) { showsAllDaysInList.toggle() }
                .accessibilityIdentifier("bookingDateListToggle")
            }
        }
        .padding(.horizontal, 16)
    }

    // MARK: 行为

    private func scroll(_ proxy: ScrollViewProxy, to day: Date?, animated: Bool) {
        guard let day else { return }
        if animated {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { proxy.scrollTo(day, anchor: .center) }
        } else {
            proxy.scrollTo(day, anchor: .center)
        }
    }

    /// 读屏上下轻扫：在能约的日子里前后走一天。还没选时从第一个能约的日子开始。
    private func stepSelection(by step: Int) {
        let days = BookingCalendar.availableDays(now: now, rules: rules)
        if let next = BookingCalendar.step(from: selectedDay, by: step, in: days) { onSelect(next) }
    }

    private var spokenSelection: String {
        guard let selectedDay else { return "还没选" }
        return BookingSlotText.spokenDay(selectedDay, now: now)
    }
}

/// 约跑页的选项胶囊：白底灰描边；选中换藏青实心 + 白字（#971，负责人 2026-11-12 批准；v4 原是只换蓝描边）。
/// 未选中描边用灰按钮描边色（负责人 11-06 定，过 3:1）。可点区撑到 64pt 高。
/// v5（#821）加可选的第二行小字：时段的时间范围、或不能选的原因。
struct BookingChoicePill: View {
    let title: String
    var subtitle: String?
    let isSelected: Bool
    let height: CGFloat
    var isEnabled = true
    var fillsWidth = false
    /// 钟点、月份这类短词：不许折行，放不下先缩到 0.8（「10:30」折成两行会被读错）。
    var singleLine = false
    let action: () -> Void

    /// 盲人端可点下限（AGENTS.md §8）。看得见的胶囊更矮，可点区撑到这个高。
    private static let minimumHitHeight: CGFloat = AppTouchTarget.blindPrimary

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .foregroundColor(textColor)
                    .lineLimit(singleLine ? 1 : nil)
                    .minimumScaleFactor(singleLine ? 0.8 : 1)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundColor(isSelected && isEnabled ? AppColors.Flow.onNavySecondary : AppColors.Flow.secondaryText)
                }
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, fillsWidth ? 4 : 15)
            .padding(.vertical, subtitle == nil ? 0 : 6)
            .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: height) // guard:allow small-touch-target 看得见的胶囊，可点区见下方 64
            .background(Capsule().fill(fillColor))
            .overlay(
                Capsule().strokeBorder(
                    isSelected ? AppColors.Flow.navy : AppColors.ButtonPalette.neutralStroke,
                    style: StrokeStyle(lineWidth: isSelected ? 1.5 : 1, dash: isEnabled ? [] : [3])
                )
            )
            .frame(minHeight: Self.minimumHitHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var textColor: Color {
        guard isEnabled else { return AppColors.Flow.secondaryText }
        return isSelected ? .white : AppColors.Flow.primaryText
    }

    private var fillColor: Color {
        guard isEnabled else { return AppColors.Flow.page }
        return isSelected ? AppColors.Flow.navy : AppColors.Flow.surface
    }
}
