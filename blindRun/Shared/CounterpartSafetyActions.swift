import Combine
import SwiftUI

// MARK: - 不再匹配此人

@MainActor
final class CounterpartBlockViewModel: ObservableObject {
    @Published private(set) var isBlocking = false
    @Published private(set) var didBlock = false
    @Published private(set) var errorMessage: String?

    /// 返回是否成功。立即生效、幂等，所以成功后这一页收起入口即可，不做别的。
    @discardableResult
    func block(userId: Int64, appState: AppState) async -> Bool {
        guard !isBlocking else { return false }
        isBlocking = true
        errorMessage = nil
        defer { isBlocking = false }
        do {
            try await appState.safety.blockUser(userId: userId)
            didBlock = true
            return true
        } catch let error as APIError {
            if !appState.handleAuthenticatedAPIError(error) {
                errorMessage = UserSafetyCopy.failureMessage(for: error, fallback: UserSafetyCopy.blockFailed)
            }
            return false
        } catch {
            errorMessage = UserSafetyCopy.blockFailed
            return false
        }
    }
}

// MARK: - 入口

/// 「举报」+「不再匹配此人」。入口在哪一页都是这一份，确认和文案不分叉。
///
/// 目标由 `CounterpartSafetyGate` 给出，视图外判完条件才放这个组件。
/// 这里不提示「对方已拉黑你」一类的话：这一层只知道自己的操作，对方的界面没有任何变化。
struct CounterpartSafetyActions: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService

    let target: CounterpartSafetyTarget
    var blockContext: UserSafetyCopy.BlockContext = .standard
    /// 一页有多个人时传（固定搭档页），读屏和确认框要说清是谁。传不带星号的念法。
    var spokenName: String?
    /// 固定搭档页要在成功后重拉列表：对方会从列表里消失。
    var onBlocked: (@MainActor () async -> Void)?

    @StateObject private var viewModel = CounterpartBlockViewModel()
    @State private var showsReport = false
    @State private var showsBlockConfirm = false

    var body: some View {
        VStack(spacing: FlowMetrics.actionButtonSpacing) {
            FlowActionButton(
                UserSafetyCopy.reportTitle,
                style: .ghost,
                accessibilityLabel: spokenName.map { UserSafetyCopy.reportTitle + $0 },
                accessibilityHint: UserSafetyCopy.reportHint
            ) {
                showsReport = true
            }
            .accessibilityIdentifier("counterpartReportButton")

            if !viewModel.didBlock {
                FlowActionButton(
                    UserSafetyCopy.blockTitle,
                    style: .ghost,
                    isLoading: viewModel.isBlocking,
                    accessibilityLabel: spokenName.map(UserSafetyCopy.blockLabel),
                    accessibilityHint: UserSafetyCopy.blockHint
                ) {
                    showsBlockConfirm = true
                }
                .accessibilityIdentifier("counterpartBlockButton")
            }

            // 结果留在正文里，读屏另有播报：低视力用户走的是视觉那条通道。
            if viewModel.didBlock {
                outcome(UserSafetyCopy.blockSucceeded, color: AppColors.success, identifier: "counterpartBlockSucceeded")
            }
            if let errorMessage = viewModel.errorMessage {
                outcome(errorMessage, color: AppColors.destructive, identifier: "counterpartBlockError")
            }
        }
        .frame(maxWidth: .infinity)
        .sheet(isPresented: $showsReport) {
            UserReportView(
                target: target,
                appState: appState,
                speak: { speechService.speak($0) },
                speakError: { speechService.speakError($0) }
            )
        }
        .alert(spokenName.map(UserSafetyCopy.blockConfirmTitle) ?? UserSafetyCopy.blockConfirmTitle, isPresented: $showsBlockConfirm) {
            Button(UserSafetyCopy.blockConfirmAction, role: .destructive) {
                Task { await block() }
            }
            Button(UserSafetyCopy.cancel, role: .cancel) {}
        } message: {
            Text(blockContext.confirmMessage)
        }
    }

    private func block() async {
        if await viewModel.block(userId: target.userId, appState: appState) {
            speechService.speak(UserSafetyCopy.blockSucceeded)
            await onBlocked?()
        } else if let message = viewModel.errorMessage {
            speechService.speakError(message)
        }
    }

    private func outcome(_ text: String, color: Color, identifier: String) -> some View {
        Text(text)
            .font(AppFonts.body())
            .foregroundColor(color)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier(identifier)
    }
}

/// 订单页的入口。判定全在 `CounterpartSafetyGate`。
struct OrderCounterpartSafetySection: View {
    let order: OrderDetailResponse

    var body: some View {
        if let target = CounterpartSafetyGate.orderPageTarget(order) {
            CounterpartSafetyActions(target: target)
        }
    }
}

/// 留言旁的「举报这条留言」。留言不放「不再匹配此人」：那是对人的动作，页面底部已经有。
struct MessageReportButton: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService

    let target: CounterpartSafetyTarget

    @State private var showsReport = false

    var body: some View {
        FlowActionButton(
            UserSafetyCopy.reportMessageTitle,
            style: .ghost,
            accessibilityHint: UserSafetyCopy.reportMessageHint
        ) {
            showsReport = true
        }
        .accessibilityIdentifier("messageReportButton")
        .sheet(isPresented: $showsReport) {
            UserReportView(
                target: target,
                appState: appState,
                speak: { speechService.speak($0) },
                speakError: { speechService.speakError($0) }
            )
        }
    }
}
