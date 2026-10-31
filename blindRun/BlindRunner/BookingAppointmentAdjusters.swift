import SwiftUI

/// 预约时间下面的「日期」「时刻」两行可调节控件（#295 走查 C1）。
///
/// compact 样式的 `DatePicker` 点开是弹层，读屏下能不能用上下滑调节没有核实过。这两行保证一定有
/// 一条不开弹层的路：读屏把整行当**一个可调节元素**（上下滑一次一格），明眼人点两端的「−」「＋」。
///
/// 不用系统 `Stepper`：它的 +/- 按钮只有约 32pt 高，低于盲人端 64pt 触达下限，守卫看不见它。
struct BookingAppointmentAdjusters: View {
    @ObservedObject var viewModel: BlindBookingViewModel

    var body: some View {
        VStack(spacing: 8) {
            BookingAdjustRow(
                title: "日期",
                value: viewModel.appointmentTime.formatted(.dateTime.month().day().weekday()),
                stepName: "一天",
                identifier: "blindBookingDateAdjuster",
                decrement: { viewModel.shiftAppointment(byMinutes: -24 * 60) },
                increment: { viewModel.shiftAppointment(byMinutes: 24 * 60) }
            )
            BookingAdjustRow(
                title: "时刻",
                value: viewModel.appointmentTime.formatted(date: .omitted, time: .shortened),
                stepName: "十五分钟",
                identifier: "blindBookingTimeAdjuster",
                decrement: { viewModel.shiftAppointment(byMinutes: -15) },
                increment: { viewModel.shiftAppointment(byMinutes: 15) }
            )
        }
    }
}

private struct BookingAdjustRow: View {
    let title: String
    let value: String
    let stepName: String
    let identifier: String
    let decrement: () -> Void
    let increment: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            adjustButton(systemImage: "minus", action: decrement)
            Text("\(title)：\(value)")
                .font(AppFonts.body().weight(.semibold))
                .foregroundColor(AppColors.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
            adjustButton(systemImage: "plus", action: increment)
        }
        .background(AppColors.secondaryBackground)
        .cornerRadius(AppCornerRadius.medium)
        // 读屏只看到一个元素：两端按钮对读屏藏起来，调节走上下滑。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("预约\(title)")
        .accessibilityValue(value)
        .accessibilityHint("上下滑动，每次增减\(stepName)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: increment()
            case .decrement: decrement()
            @unknown default: break
            }
        }
        .accessibilityIdentifier(identifier)
    }

    private func adjustButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title2.weight(.semibold))
                .foregroundColor(AppColors.primary)
                .frame(width: AppTouchTarget.blindPrimary, height: AppTouchTarget.blindPrimary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
