import SwiftUI

// 远端内容（#857 候选 2，#863）：全仓「加载中 / 失败 / 已加载」只用这一套。
// 状态是 `AsyncLoadState`，视图是 `RemoteContent`。失败一律走 `IncentiveFailureSection`，会念出来 ——
// 盲人端「屏幕上多了一行字」等于什么都没发生（#527）。
//
// 页面规则留在 ViewModel，不进这里：例如下拉刷新失败时保留已显示的内容，就让状态保持 `.loaded`，
// 不改成 `.failed`（`MySupportTicketsViewModel.markFailedUnlessAlreadyShowing`）。

// MARK: - State

/// A single-request UI state. The request identifier prevents a late response
/// from replacing a newer refresh.
enum AsyncLoadState<Value> {
    case idle
    case loading(requestID: UUID)
    case loaded(Value)
    case failed(message: String)

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    /// The loaded value, or nil in any other state.
    var value: Value? {
        if case .loaded(let value) = self { return value }
        return nil
    }
}

extension AsyncLoadState: Equatable where Value: Equatable {}

// MARK: - View

/// 按 `AsyncLoadState` 画三种样子：加载占位、失败（会念）、内容。
///
/// 只管这一块内容本身，不加页边距：放进列表 / 卡片里的和占满整页的都用它，边距由页面定。
struct RemoteContent<Value, Content: View>: View {
    private let state: AsyncLoadState<Value>
    private let loadingLabel: String
    private let failureIdentifier: String
    private let retryTitle: String
    private let retry: @MainActor () -> Void
    private let content: @MainActor (Value) -> Content

    /// 用户点了几次重试。同一句失败文案、重试又失败时靠它再念一遍（#573）。
    @State private var attempt = 0

    init(_ state: AsyncLoadState<Value>,
         loadingLabel: String,
         failureIdentifier: String,
         retryTitle: String = "重试",
         retry: @escaping @MainActor () -> Void,
         @ViewBuilder content: @escaping @MainActor (Value) -> Content) {
        self.state = state
        self.loadingLabel = loadingLabel
        self.failureIdentifier = failureIdentifier
        self.retryTitle = retryTitle
        self.retry = retry
        self.content = content
    }

    var body: some View {
        switch state {
        case .idle, .loading:
            loadingPlaceholder
        case .failed(let message):
            IncentiveFailureSection(
                message: message,
                retryTitle: retryTitle,
                identifier: failureIdentifier,
                attempt: attempt
            ) {
                attempt += 1
                retry()
            }
        case .loaded(let value):
            content(value)
        }
    }

    /// 读屏只读一句 `loadingLabel`。
    private var loadingPlaceholder: some View {
        HStack(spacing: 8) {
            ProgressView()
            Text(loadingLabel)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: FlowMetrics.actionButtonMinHeight, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(loadingLabel)
    }
}
