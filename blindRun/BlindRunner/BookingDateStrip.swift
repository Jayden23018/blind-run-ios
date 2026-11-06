import SwiftUI

/// 约跑页（#806）的「哪天跑」：月份带 + 一排可横向滑的日期圆。尺寸取参考图实测（模拟图 v4）。
/// 从 `BlindMatchFirstBookingView` 拆出来，理由是那个视图超过了 SwiftLint 的类型长度上限。
struct BookingDateStrip: View {
    let now: Date
    let selectedDay: Date?
    let onSelect: (Date) -> Void

    private static let horizontalPadding: CGFloat = 18.5
    private static let minimumHitHeight: CGFloat = 64
    /// 日期圆的直径（参考图实测 48）。只是看得见的圆，可点区是整列 60 宽、≥64 高。
    private static let dayCircleDiameter: CGFloat = 48


    var body: some View {
        let days = BookingSlotPlanner.days(now: now)
        return VStack(alignment: .leading, spacing: 14) {
            monthRow(days: days)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(days.enumerated()), id: \.element) { index, day in
                        dayButton(day, index: index, total: days.count)
                    }
                }
                .padding(.horizontal, Self.horizontalPadding)
            }
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.Flow.page)
    }

    /// 参考图的月份带：当前月加粗，前后渐淡。只是装饰，日期本身会念出几月几日，所以不进读屏。
    private func monthRow(days: [Date]) -> some View {
        let month = Calendar.aidRunBackend.component(.month, from: selectedDay ?? days.first ?? now)
        return HStack(spacing: 18) {
            ForEach([-2, -1, 0, 1, 2], id: \.self) { offset in
                monthLabel(month: month, offset: offset)
            }
        }
        .padding(.horizontal, Self.horizontalPadding)
        .accessibilityHidden(true)
    }

    private func monthLabel(month: Int, offset: Int) -> some View {
        let value: Int = ((month - 1 + offset) % 12 + 12) % 12 + 1
        let isCurrent = offset == 0
        let fade: Double = abs(offset) == 1 ? 0.8 : 0.55
        let color: Color = isCurrent ? AppColors.Flow.primaryText : AppColors.Flow.secondaryText.opacity(fade)
        return Text("\(value)月")
            .font(.footnote.weight(isCurrent ? .semibold : .regular))
            .foregroundColor(color)
    }

    private func dayButton(_ day: Date, index: Int, total: Int) -> some View {
        let isAvailable = BookingSlotPlanner.isDayAvailable(day, now: now)
        let isSelected = selectedDay == day
        let number = Calendar.aidRunBackend.component(.day, from: day)
        return Button {
            onSelect(day)
        } label: {
            VStack(spacing: 8) {
                Text("\(number)")
                    .font(.title3.weight(isSelected ? .semibold : .regular))
                    .foregroundColor(dayNumberColor(isAvailable: isAvailable, isSelected: isSelected))
                    .frame(width: Self.dayCircleDiameter, height: Self.dayCircleDiameter) // guard:allow small-touch-target 只是圆，可点区见下方整列 60×64
                    .background(Circle().fill(dayFill(isAvailable: isAvailable, isSelected: isSelected)))
                    .overlay(dayBorder(isAvailable: isAvailable, isSelected: isSelected))
                Text(BookingSlotText.weekdayName(day))
                    .font(AppFonts.caption())
                    .foregroundColor(isSelected ? AppColors.Flow.navy : AppColors.Flow.secondaryText)
            }
            .frame(width: 60)
            .frame(minHeight: Self.minimumHitHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(BookingSlotText.spokenDay(day, now: now) + (isAvailable ? "" : "，今天的时段都已过"))
        .accessibilityValue("第 \(index + 1) 项，共 \(total) 项")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func dayNumberColor(isAvailable: Bool, isSelected: Bool) -> Color {
        guard isAvailable else { return AppColors.Flow.secondaryText }
        return isSelected ? AppColors.Flow.navy : AppColors.Flow.primaryText
    }

    private func dayFill(isAvailable: Bool, isSelected: Bool) -> Color {
        if isSelected { return AppColors.Flow.surface }
        return isAvailable ? AppColors.Flow.blueTint : AppColors.Flow.page
    }

    @ViewBuilder
    private func dayBorder(isAvailable: Bool, isSelected: Bool) -> some View {
        if isSelected {
            Circle().strokeBorder(AppColors.ButtonPalette.primaryFill, lineWidth: 1.5)
        } else if !isAvailable {
            Circle().strokeBorder(AppColors.ButtonPalette.neutralStroke, style: StrokeStyle(lineWidth: 1, dash: [3]))
        }
    }
}

/// 约跑页（#806）的选项胶囊：白底、选中只换 1.5pt 蓝描边（不加粗、不填色，照参考图）。
/// 未选中描边用灰按钮描边色（负责人 11-06 定，过 3:1）。可点区撑到 64pt 高。
struct BookingChoicePill: View {
    let title: String
    let isSelected: Bool
    let height: CGFloat
    var isEnabled = true
    var fillsWidth = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(textColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, fillsWidth ? 4 : 15)
                .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: height)
                .background(Capsule().fill(isEnabled ? AppColors.Flow.surface : AppColors.Flow.page))
                .overlay(
                    Capsule().strokeBorder(
                        isSelected ? AppColors.ButtonPalette.primaryFill : AppColors.ButtonPalette.neutralStroke,
                        lineWidth: isSelected ? 1.5 : 1
                    )
                )
                .frame(minHeight: 64)
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
