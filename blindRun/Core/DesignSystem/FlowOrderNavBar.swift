import SwiftUI

// 从 `FlowV2Components.swift` 拆出（文件超长，SwiftLint 棘轮）。
// MARK: 导航栏

/// 订单页导航栏：左返回、中标题、右求助。左右各一个固定宽度的槽，
/// 这样标题始终居中、求助胶囊在任何状态下都在同一个位置。
///
/// 放大字号后两侧槽只增不减（`minWidth`），标题换行而不是把胶囊挤出屏幕。
struct FlowOrderNavBar: View {
    let title: String
    /// `nil` = 不放返回按钮（完成页）。
    var onBack: (() -> Void)?
    let onHelp: () -> Void
    /// 见 `FlowHelpPill`。
    var helpIsCloud = false
    var helpIsBusy = false
    /// 非 `nil` = 求助胶囊左边放「···」，里面是举报 / 不再匹配此人（2026-11-11 从页面底部收进来，`CounterpartSafetyMenu`）。
    var counterpartSafety: CounterpartBlockViewModel?

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let onBack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(AppColors.Flow.primaryText)
                            .frame(
                                width: FlowMetrics.v2TextButtonMinHeight,
                                height: FlowMetrics.v2TextButtonMinHeight,
                                alignment: .leading
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("返回")
                } else {
                    Color.clear.frame(width: 1, height: 1).accessibilityHidden(true)
                }
            }
            // 右槽多了「···」时左槽同步加宽，标题仍在正中。
            .frame(minWidth: FlowMetrics.v2NavSlotWidth + moreSlotWidth, alignment: .leading)

            Text(title)
                .flowFont((16, .bold, .headline))
                .foregroundColor(AppColors.Flow.primaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.isHeader)

            HStack(spacing: 8) {
                if let counterpartSafety {
                    FlowOrderNavMoreMenu(viewModel: counterpartSafety)
                }
                FlowHelpPill(isCloud: helpIsCloud, isBusy: helpIsBusy, action: onHelp)
            }
            .frame(minWidth: FlowMetrics.v2NavSlotWidth + moreSlotWidth, alignment: .trailing)
        }
        .frame(minHeight: FlowMetrics.v2NavHeight)
    }

    private var moreSlotWidth: CGFloat {
        counterpartSafety == nil ? 0 : FlowMetrics.v2TextButtonMinHeight + 8
    }
}

/// 陪跑员订单页顶栏的「···」。陪跑员端是明眼人，图标与返回键同尺寸（`v2TextButtonMinHeight`）。
private struct FlowOrderNavMoreMenu: View {
    @ObservedObject var viewModel: CounterpartBlockViewModel

    var body: some View {
        Menu {
            CounterpartSafetyMenuItems(viewModel: viewModel)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(AppColors.Flow.primaryText)
                .frame(width: FlowMetrics.v2TextButtonMinHeight, height: FlowMetrics.v2TextButtonMinHeight)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("更多操作")
        .accessibilityHint(CounterpartSafetyMenu.titles(viewModel: viewModel).joined(separator: "、"))
        .accessibilityIdentifier("volunteerOrderNavMoreMenu")
    }
}
