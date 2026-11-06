import SwiftUI

/// 约跑页的「大概什么时候？」卡（#821，从 `BlindMatchFirstBookingView` 拆出来，那个视图超了 SwiftLint 的类型长度上限）。
///
/// 三个时段胶囊下面写实际能约的时间范围，不能选时写原因（已过 / 不在值守时间 / 超出可约范围）；
/// 有值守时段限制时顶上原样显示后端那句提示。再下面是可不选的具体时刻。
struct BookingSlotSection: View {
    let now: Date
    let rules: BookingRules
    let selectedDay: Date?
    let selectedSlot: BookingDaySlot?
    let preferredStart: Date?
    /// 后端拼好的值守时段提示。`nil` = 没有限制，不显示。
    let dutyHoursHint: String?
    let onSelectSlot: (BookingDaySlot) -> Void
    let onTogglePreferredStart: (Date) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let hint = dutyHoursHint {
                Label {
                    Text(hint).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "clock").accessibilityHidden(true)
                }
                .font(.footnote)
                .foregroundColor(AppColors.Flow.secondaryText)
                .padding(.bottom, 8)
                .accessibilityIdentifier("matchFirstDutyHoursHint")
            }
            HStack(spacing: 10) {
                ForEach(BookingDaySlot.allCases) { slot in slotPill(slot) }
            }
            Rectangle()
                .fill(AppColors.Flow.separator)
                .frame(height: 1)
                .padding(.vertical, 8)
                .accessibilityHidden(true)
            startTimeSection
        }
        .padding(16)
    }

    private func slotPill(_ slot: BookingDaySlot) -> some View {
        let range = selectedDay.flatMap { BookingSlotPlanner.window(day: $0, slot: slot, now: now, rules: rules) }
        let reason = selectedDay.flatMap { BookingSlotPlanner.unavailableReason(day: $0, slot: slot, now: now, rules: rules) }
        let rangeText = range.map { "\(BookingSlotText.clock($0.start))–\(BookingSlotText.clock($0.end))" }
        return BookingChoicePill(
            title: slot.title,
            subtitle: rangeText ?? reason?.text,
            isSelected: selectedSlot == slot,
            height: 52,
            isEnabled: range != nil,
            fillsWidth: true
        ) { onSelectSlot(slot) }
        .accessibilityLabel(
            range.map { "\(slot.title)，\(BookingSlotText.clock($0.start))到\(BookingSlotText.clock($0.end))之间" }
                ?? "\(slot.title)，\(reason?.text ?? BookingSlotUnavailableReason.passed.text)"
        )
        .accessibilityIdentifier("matchFirstSlot_\(slot.rawValue)")
    }

    // MARK: 想几点开始（可不选）

    private var startTimeSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(startTimeHint)
                .font(AppFonts.caption())
                .foregroundColor(AppColors.Flow.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
                alignment: .leading,
                spacing: 0
            ) {
                ForEach(startTimes, id: \.self) { time in
                    BookingChoicePill(
                        title: BookingSlotText.clock(time), isSelected: preferredStart == time, height: 44, fillsWidth: true,
                        singleLine: true
                    ) {
                        onTogglePreferredStart(time)
                    }
                    .accessibilityHint("可以不选，电话里再定")
                }
            }
        }
    }

    private var startTimes: [Date] {
        guard let selectedDay, let selectedSlot else { return [] }
        return BookingSlotPlanner.startTimes(day: selectedDay, slot: selectedSlot, now: now, rules: rules)
    }

    private var startTimeHint: String {
        guard let selectedDay, let selectedSlot,
              BookingSlotPlanner.window(day: selectedDay, slot: selectedSlot, now: now, rules: rules) != nil else {
            return "先选一个时段"
        }
        return "具体几点可以不选，电话里再定"
    }
}
