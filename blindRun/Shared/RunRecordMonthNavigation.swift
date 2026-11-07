import SwiftUI

// 「记录」列表顶上的月份栏与月份模型（#829，照负责人参考图）。从 `RunRecordHistoryView.swift` 拆出来，
// 因为那边已超过文件长度上限（SwiftLint 棘轮只许变小）。

// MARK: - Month

/// 列表从选中的月份开始按月分节，往下滑接着加载更早的月份（负责人 2026-11-07 参考图，#829；
/// 取代 2026-09-24「一次一个月、不往下追加」）。顶上月份栏切的是「从哪个月开始」。
nonisolated struct RunRecordMonth: Equatable, Comparable, Sendable {
    let year: Int
    let month: Int

    init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    init(containing date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month], from: date)
        self.init(year: parts.year ?? 2026, month: parts.month ?? 1)
    }

    var previous: RunRecordMonth {
        month == 1 ? RunRecordMonth(year: year - 1, month: 12) : RunRecordMonth(year: year, month: month - 1)
    }

    var next: RunRecordMonth {
        month == 12 ? RunRecordMonth(year: year + 1, month: 1) : RunRecordMonth(year: year, month: month + 1)
    }

    /// 同一年只说「9月」；跨年才带年份，不然 1 月往回翻到的「12月」会被听成今年的 12 月。
    func title(relativeTo current: RunRecordMonth) -> String {
        year == current.year ? "\(month)月" : "\(year)年\(month)月"
    }

    /// 月份栏总带年份（「2026年11月」）。
    var fullTitle: String { "\(year)年\(month)月" }

    static func < (lhs: RunRecordMonth, rhs: RunRecordMonth) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }
}

/// 列表里的一节：一个月和它的记录。没有记录的月份不成节。
struct RunRecordMonthSection: Equatable, Identifiable {
    let month: RunRecordMonth
    let items: [RunHistoryItem]
    var id: RunRecordMonth { month }
}

// MARK: - Month Bar

/// 「‹ 2026年11月 ⌄ ›」：点箭头或在栏上左右滑切月，点中间弹出月份列表直接跳。
/// 当月不给「下个月」，留同宽空位让标题保持居中。读屏是三个元素：上个月、选择月份菜单、下个月。
struct RunRecordMonthBar: View {
    @ObservedObject var viewModel: RunRecordHistoryViewModel

    /// 横向滑过这么远、且明显比竖向多，才算切月，免得竖着滚列表时误切。
    private static let swipeThreshold: CGFloat = 50
    private static let side = FlowMetrics.actionButtonMinHeight

    var body: some View {
        HStack(spacing: 0) {
            arrow(
                systemName: "chevron.left",
                label: "上个月",
                target: viewModel.month.previous,
                identifier: "runRecordHistoryPreviousMonth"
            ) { await viewModel.showPreviousMonth() }
            picker
            if viewModel.canShowNextMonth {
                arrow(
                    systemName: "chevron.right",
                    label: "下个月",
                    target: viewModel.month.next,
                    identifier: "runRecordHistoryNextMonth"
                ) { await viewModel.showNextMonth() }
            } else {
                Color.clear
                    .frame(width: Self.side, height: Self.side)
                    .accessibilityHidden(true)
            }
        }
        .background(AppColors.Flow.surface)
        .clipShape(RoundedRectangle(cornerRadius: Self.side / 2, style: .continuous))
        .simultaneousGesture(
            DragGesture(minimumDistance: 20).onEnded { value in
                let dx = value.translation.width
                guard abs(dx) > Self.swipeThreshold, abs(dx) > abs(value.translation.height) * 2,
                      !viewModel.isLoading else { return }
                // 往左滑看后一个月，往右滑看前一个月（和翻页方向一致）。
                Task { dx < 0 ? await viewModel.showNextMonth() : await viewModel.showPreviousMonth() }
            }
        )
    }

    private var picker: some View {
        Menu {
            ForEach(viewModel.pickerMonths, id: \.self) { month in
                Button {
                    Task { await viewModel.jump(to: month) }
                } label: {
                    if month == viewModel.month {
                        Label(month.fullTitle, systemImage: "checkmark")
                    } else {
                        Text(month.fullTitle)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(viewModel.monthBarTitle)
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Image(systemName: "chevron.down")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundColor(AppColors.textPrimary)
            .frame(maxWidth: .infinity, minHeight: Self.side)
            .contentShape(Rectangle())
        }
        .disabled(viewModel.isLoading)
        .accessibilityLabel("选择月份，当前 \(viewModel.monthBarTitle)")
        .accessibilityIdentifier("runRecordHistoryMonthPicker")
    }

    private func arrow(
        systemName: String,
        label: String,
        target: RunRecordMonth,
        identifier: String,
        action: @escaping @MainActor () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            Image(systemName: systemName)
                .font(.title3.weight(.semibold))
                .foregroundColor(AppColors.textPrimary)
                .frame(width: Self.side, height: Self.side)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isLoading)
        .accessibilityLabel(label)
        .accessibilityHint("切到 \(target.fullTitle)")
        .accessibilityIdentifier(identifier)
    }
}
