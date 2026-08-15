import Combine
import SwiftUI

// MARK: - View Model

/// 盲人端的历史订单。此前**整条路都不存在** —— `/api/orders/mine` 只被首页用来
/// 找当前进行中的那一单（`BlindRunnerHomeView.swift:165-169`），订单一旦完成就再也回不去，
/// 于是 `BlindOrderStatusView` 里那段已完成轨迹实际上只在「跑完那一刻恰好还停在该页」时露过面。
@MainActor
final class BlindRunHistoryViewModel: ObservableObject {
    @Published private(set) var records: [OrderDetailResponse] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private weak var appState: AppState?
    private var speechService: SpeechService?

    func configure(with appState: AppState, speechService: SpeechService) {
        self.appState = appState
        self.speechService = speechService
    }

    func load() async {
        guard let appState else { return }
        isLoading = records.isEmpty
        errorMessage = nil
        do {
            let paged: PagedOrderResponse = try await appState.apiClient.get("/api/orders/mine")
            // 留全部终态（已完成 / 已取消 / 暂无志愿者）：「上次那单为什么没跑成」和
            // 「上次是谁陪我跑的」是同一个用户的同一次回看，分成两处只会多一个入口。
            // 进行中的那单不进来 —— 首页已经在管它，列表里再出现一次是两个真相源。
            // 未知状态一并排除：后端新增状态时把它当成「已经结束了」是在替用户下结论。
            records = paged.content
                .filter { $0.status.isTerminal }
                .sorted { ($0.createdAt ?? $0.plannedStart ?? "") > ($1.createdAt ?? $1.plannedStart ?? "") }
            isLoading = false
        } catch let error as APIError {
            isLoading = false
            if appState.handleAuthenticatedAPIError(error) { return }
            errorMessage = error.localizedMessage
            speechService?.speakError(error.localizedMessage)
        } catch {
            isLoading = false
            let message = "加载失败，下拉重试"
            errorMessage = message
            speechService?.speakError(message)
        }
    }
}

// MARK: - List

struct BlindRunHistoryView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @StateObject private var viewModel = BlindRunHistoryViewModel()

    var body: some View {
        List {
            if viewModel.isLoading {
                ProgressView("正在加载历史订单...")
                    .accessibilityLabel("正在加载历史订单")
            } else if viewModel.records.isEmpty {
                EmptyStateView(title: "暂无历史订单", message: "结束一次预约后，这里会显示那一单的详情。")
            } else {
                ForEach(viewModel.records, id: \.orderId) { order in
                    NavigationLink {
                        // 落到订单详情而不是直接进轨迹回放：详情页在这一单是 `COMPLETED` 时
                        // 内嵌轨迹摘要（并自动播报里程/时长/配速）、给出「查看大图路线」链接，
                        // 而且是**补评价唯一的入口** —— 评价此前只在「跑完那一刻恰好还停在详情页」
                        // 时出现过一次，错过就再也交不上。
                        BlindOrderStatusView(orderId: order.orderId) { _ in }
                    } label: {
                        BlindRunHistoryRow(order: order)
                    }
                    .accessibilityHint(order.status == .completed
                        ? "查看这一单的详情、路线，也可以在这里补评价"
                        : "查看这一单的详情")
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundColor(AppColors.destructive)
                    .accessibilityLabel(errorMessage)
            }
        }
        .navigationTitle("我的历史订单")
        .accessibilityIdentifier("blindRunHistoryList")
        .task {
            viewModel.configure(with: appState, speechService: speechService)
            await viewModel.load()
        }
        .refreshable {
            await viewModel.load()
        }
    }
}

private struct BlindRunHistoryRow: View {
    let order: OrderDetailResponse

    private var dateText: String {
        (order.createdAt ?? order.plannedStart ?? "").displayDateTime
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 状态排在最前，视觉与朗读同序：列表混了已完成 / 已取消 / 暂无志愿者之后，
            // 读屏用户逐行划过时第一个词就得能判断「这单跑成没有」，否则要听完整行才知道。
            Text(order.status.displayName)
                .font(AppFonts.body().weight(.semibold))
                .foregroundColor(order.status == .completed ? AppColors.textPrimary : AppColors.textSecondary)
            Text(dateText)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textPrimary)
            Text(order.startAddress ?? "地点未记录")
                .font(AppFonts.caption())
                .foregroundColor(AppColors.textSecondary)
        }
        .padding(.vertical, 4)
        // 行里不放里程 —— 那要为每一行单独打一次 `/track`。
        // ponytail: 需要的话再让后端在列表响应里带上，不在客户端拿 N 个请求换一行小字。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(order.status.displayName)，\(dateText)，出发地 \(order.startAddress ?? "未记录")")
    }
}
