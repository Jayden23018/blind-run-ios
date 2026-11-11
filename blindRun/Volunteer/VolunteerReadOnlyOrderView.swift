import SwiftUI

struct VolunteerReadOnlyOrderView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @StateObject private var trackViewModel = CompletedTrackSummaryViewModel()
    /// 举报 / 不再匹配此人：2026-11-11 起收进导航栏「···」，正文只留结果一行（`CounterpartSafetyMenu`）。
    @StateObject private var counterpartSafety = CounterpartBlockViewModel()
    let order: OrderDetailResponse

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VolunteerStatusBanner(status: order.status)
                // 只读回看也保留：导盲犬那一行原本在订单信息里，从那儿移走之后
                // 这个页面不补上就成了净丢失。
                VolunteerRunnerNeedsBanner(order: order)
                VolunteerBlindRunnerInfoCard(order: order, showPhone: order.status != .pendingMatch && order.blindPhone?.trimmed.isEmpty == false)
                VolunteerOrderInfoSection(order: order, distanceText: nil)
                if order.status == .completed, let track = trackViewModel.track {
                    CompletedTrackSummaryView(track: track, recordOrderId: order.orderId, role: .volunteer) {
                        speechService.speak(track.spokenSummary)
                    }
                } else if trackViewModel.isLoading {
                    ProgressView("正在加载本次路线")
                } else if let error = trackViewModel.errorMessage {
                    Text(error).foregroundColor(AppColors.textSecondary)
                }
                CounterpartBlockOutcome(viewModel: counterpartSafety)
            }
            .padding(20)
            .readableContentColumn()
        }
        .navigationTitle("订单详情")
        .toolbar {
            if CounterpartSafetyGate.orderPageTarget(order) != nil {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        CounterpartSafetyMenuItems(viewModel: counterpartSafety)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("更多操作")
                    .accessibilityHint(CounterpartSafetyMenu.titles(viewModel: counterpartSafety).joined(separator: "、"))
                    .accessibilityIdentifier("volunteerOrderNavMoreMenu")
                }
            }
        }
        .counterpartSafetyPrompts(viewModel: counterpartSafety, target: CounterpartSafetyGate.orderPageTarget(order))
        .task {
            guard order.status == .completed else { return }
            await trackViewModel.load(orderID: order.orderId, appState: appState)
        }
    }
}
