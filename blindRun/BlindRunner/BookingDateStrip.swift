import SwiftUI

/// 约跑页的「哪天跑」（#821，v5）：真实年月标题 + 翻周箭头 + 月份胶囊 + 周一到周日一周一页。
///
/// v4 只有一排 7 个日期圆，月份那一排是装饰、点不了（负责人 2026-11-07：「仿照了界面，没有仿照逻辑」）。
/// 现在可约范围读后端 `maxLeadDays`，月份只列范围覆盖的月份，左右滑或点箭头一次翻一周。
///
/// 读屏：一周的格子合成**一个可调整元素**，上下轻扫换一天，只在能约的日子里走，跨周自动翻页
/// （Apple 无障碍示例对横滑列表的做法，调研 `docs/research/booking-date-picker-20261107.md`）。
/// 辅助功能大字档一周七格放不下，改成一行一天的列表（同「默认出发地点」页的做法）。
struct BookingDateStrip: View {
    let now: Date
    let rules: BookingRules
    let selectedDay: Date?
    let onSelect: (Date) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var weekIndex = 0
    @State private var pagesForward = true

    /// 看得见的日期圆。可点区是整列宽、64 高。
    private static let dayCircleDiameter: CGFloat = 40
    private static let minimumHitHeight: CGFloat = AppTouchTarget.blindPrimary
    /// 横滑超过这么远才翻周，免得竖着滚页面时误翻。
    private static let swipeThreshold: CGFloat = 40
    /// 小圆点最多画几个（30 天约 6 周）。
    private static let maximumPageDots = 8

    private var calendar: Calendar { .aidRunBackend }
    private var weeks: [BookingWeek] { BookingCalendar.weeks(now: now, rules: rules) }
    private var usesList: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        let weeks = weeks
        let index = min(weekIndex, max(weeks.count - 1, 0))
        return VStack(alignment: .leading, spacing: 12) {
            if let week = weeks[safe: index] {
                header(week: week, index: index, count: weeks.count)
                monthChips
                Group {
                    if usesList {
                        dayList(week)
                    } else {
                        dayGrid(week)
                    }
                }
                .id(week.id)
                .transition(pageTransition)
                // 后端天数配得很大时周数多，一排小圆点会挤出卡片：超过上限就不画（标题与箭头已经说清在哪一周）。
                if (2...Self.maximumPageDots).contains(weeks.count) { pageDots(index: index, count: weeks.count) }
            }
            Text(BookingCalendar.rangeFootnote(now: now, rules: rules))
                .font(AppFonts.caption())
                .foregroundColor(AppColors.Flow.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("bookingDateRangeFootnote")
        }
        .padding(16)
        .onAppear { syncWeek(to: selectedDay, animated: false) }
        .onChange(of: selectedDay) { syncWeek(to: $0, animated: true) }
    }

    // MARK: 标题与翻周

    private func header(week: BookingWeek, index: Int, count: Int) -> some View {
        HStack(spacing: 0) {
            Text(BookingCalendar.title(for: week))
                .font(.title3.weight(.semibold))
                .foregroundColor(AppColors.Flow.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            weekArrow(systemName: "chevron.left", target: index - 1, count: count, prefix: "上一周")
            weekArrow(systemName: "chevron.right", target: index + 1, count: count, prefix: "下一周")
        }
    }

    private func weekArrow(systemName: String, target: Int, count: Int, prefix: String) -> some View {
        let isEnabled = (0..<count).contains(target)
        return Button {
            goToWeek(target)
        } label: {
            Image(systemName: systemName)
                .font(.body.weight(.semibold))
                .foregroundColor(isEnabled ? AppColors.ButtonPalette.primaryFill : AppColors.Flow.secondaryText)
                .frame(width: 36, height: 36) // guard:allow small-touch-target 只是圆底，可点区见下一行 64×64
                .background(Circle().fill(isEnabled ? AppColors.Flow.blueTint : AppColors.Flow.page))
                .frame(width: Self.minimumHitHeight, height: Self.minimumHitHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(weeks[safe: target].map { "\(prefix)，\(BookingCalendar.spokenRange(of: $0))" } ?? prefix)
        .accessibilityIdentifier(target > weekIndex ? "bookingDateNextWeek" : "bookingDatePreviousWeek")
    }

    // MARK: 月份

    private var monthChips: some View {
        let months = BookingCalendar.months(now: now, rules: rules)
        return HStack(spacing: 10) {
            ForEach(months, id: \.self) { firstDay in
                let month = calendar.component(.month, from: firstDay)
                let isSelected = selectedDay.map { calendar.isDate($0, equalTo: firstDay, toGranularity: .month) } ?? false
                BookingChoicePill(title: "\(month)月", isSelected: isSelected, height: 36, singleLine: true) {
                    onSelect(firstDay)
                }
                .accessibilityLabel("\(month)月")
                .accessibilityHint("跳到\(month)月第一个能约的日子")
                .accessibilityIdentifier("bookingDateMonth_\(month)")
            }
        }
    }

    // MARK: 一周七格

    private func dayGrid(_ week: BookingWeek) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 0) {
                ForEach(week.days, id: \.self) { day in
                    Text(BookingSlotText.weekdayShortName(day))
                        .font(AppFonts.caption())
                        .foregroundColor(AppColors.Flow.secondaryText)
                        .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)
            HStack(spacing: 0) {
                ForEach(week.days, id: \.self) { day in
                    dayCell(day)
                }
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(swipeGesture)
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
        .accessibilityIdentifier("bookingDateWeek")
    }

    private func dayCell(_ day: Date) -> some View {
        let state = BookingCalendar.state(of: day, now: now, rules: rules)
        let isSelected = selectedDay == day
        let isToday = calendar.isDate(day, inSameDayAs: now)
        return Button {
            onSelect(day)
        } label: {
            VStack(spacing: 2) {
                Text("\(calendar.component(.day, from: day))")
                    .font(.body.weight(isSelected ? .semibold : .regular))
                    .foregroundColor(dayNumberColor(state: state, isSelected: isSelected))
                    .frame(width: Self.dayCircleDiameter, height: Self.dayCircleDiameter) // guard:allow small-touch-target 只是圆，可点区是整列宽、64 高
                    .background(Circle().fill(dayFill(state: state, isSelected: isSelected)))
                    .overlay(dayBorder(state: state, isSelected: isSelected))
                Text(isToday ? "今天" : " ")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(AppColors.ButtonPalette.primaryFill)
            }
            .frame(maxWidth: .infinity, minHeight: Self.minimumHitHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(state != .available)
    }

    private func dayNumberColor(state: BookingDayState, isSelected: Bool) -> Color {
        if isSelected { return .white }
        return state == .available ? AppColors.Flow.primaryText : AppColors.Flow.secondaryText
    }

    private func dayFill(state: BookingDayState, isSelected: Bool) -> Color {
        if isSelected { return AppColors.ButtonPalette.primaryFill }
        return state == .available ? AppColors.Flow.blueTint : .clear
    }

    @ViewBuilder
    private func dayBorder(state: BookingDayState, isSelected: Bool) -> some View {
        switch state {
        case .available where !isSelected:
            // 浅蓝填充压白卡对比度不够，低视力看不出能点：加灰描边过 3:1（与 v4 同一条有意偏离，负责人 11-06 定）。
            Circle().strokeBorder(AppColors.ButtonPalette.neutralStroke, lineWidth: 1)
        case .unavailable, .beyondRange:
            Circle().strokeBorder(AppColors.ButtonPalette.neutralStroke, style: StrokeStyle(lineWidth: 1, dash: [3]))
        default:
            EmptyView()
        }
    }

    // MARK: 大字档：一行一天

    private func dayList(_ week: BookingWeek) -> some View {
        VStack(spacing: 8) {
            ForEach(week.days.filter { $0 >= calendar.startOfDay(for: now) }, id: \.self) { day in
                let state = BookingCalendar.state(of: day, now: now, rules: rules)
                BookingChoicePill(
                    title: BookingSlotText.spokenDay(day, now: now),
                    subtitle: state == .available ? nil : dayStateText(state),
                    isSelected: selectedDay == day,
                    height: Self.minimumHitHeight,
                    isEnabled: state == .available,
                    fillsWidth: true
                ) { onSelect(day) }
            }
        }
        .simultaneousGesture(swipeGesture)
    }

    private func dayStateText(_ state: BookingDayState) -> String {
        switch state {
        case .available: return ""
        case .past: return "已过"
        case .unavailable: return "这天没有能约的时段"
        case .beyondRange: return "超出可约范围"
        }
    }

    // MARK: 第几周

    private func pageDots(index: Int, count: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { dot in
                Circle()
                    .fill(dot == index ? AppColors.ButtonPalette.primaryFill : AppColors.ButtonPalette.neutralStroke.opacity(0.45))
                    .frame(width: 6, height: 6)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    // MARK: 行为

    private var pageTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .move(edge: pagesForward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: pagesForward ? .leading : .trailing).combined(with: .opacity)
        )
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 24).onEnded { value in
            let width = value.translation.width
            guard abs(width) > Self.swipeThreshold, abs(width) > abs(value.translation.height) else { return }
            goToWeek(weekIndex + (width < 0 ? 1 : -1))
        }
    }

    private func goToWeek(_ target: Int) {
        guard weeks.indices.contains(target), target != weekIndex else { return }
        pagesForward = target > weekIndex
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { weekIndex = target }
    }

    private func syncWeek(to day: Date?, animated: Bool) {
        guard let day, let target = BookingCalendar.weekIndex(of: day, in: weeks), target != weekIndex else { return }
        if animated {
            goToWeek(target)
        } else {
            weekIndex = target
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

/// 约跑页的选项胶囊：白底、选中只换 1.5pt 蓝描边（照 v4 参考图）。
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
                        .foregroundColor(AppColors.Flow.secondaryText)
                }
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, fillsWidth ? 4 : 15)
            .padding(.vertical, subtitle == nil ? 0 : 6)
            .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: height) // guard:allow small-touch-target 看得见的胶囊，可点区见下方 64
            .background(Capsule().fill(isEnabled ? AppColors.Flow.surface : AppColors.Flow.page))
            .overlay(
                Capsule().strokeBorder(
                    isSelected ? AppColors.ButtonPalette.primaryFill : AppColors.ButtonPalette.neutralStroke,
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
        return isSelected ? AppColors.Flow.navy : AppColors.Flow.primaryText
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
