import SwiftUI

struct VolunteerReadOnlyOrderView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @StateObject private var trackViewModel = CompletedTrackSummaryViewModel()
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
                OrderCounterpartSafetySection(order: order)
            }
            .padding(20)
            .readableContentColumn()
        }
        .navigationTitle("订单详情")
        .task {
            guard order.status == .completed else { return }
            await trackViewModel.load(orderID: order.orderId, appState: appState)
        }
    }
}
