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
    /// 外观。确认框、文案、读屏标签两种外观完全相同，只有画法不同。
    var presentation: Presentation = .buttons
    /// `.groupedRows` 每行的最小高度。陪跑员端 56（明眼人）；盲人端搭档详情页传 64（#752）。
    var groupedRowMinHeight: CGFloat = 56

    enum Presentation {
        /// 两枚整宽描边按钮（订单页、通话页）。
        case buttons
        /// 一张白卡里的两行蓝字（两端搭档详情页，照健康 App「共享」的人页，#697 / #752）。
        case groupedRows
    }

    @StateObject private var viewModel = CounterpartBlockViewModel()
    @State private var showsReport = false
    @State private var showsBlockConfirm = false

    var body: some View {
        actions
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

    @MainActor @ViewBuilder
    private var actions: some View {
        switch presentation {
        case .buttons:
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
        case .groupedRows:
            groupedRows
        }
    }

    /// 白卡里两行蓝字，行间一条细线。结果（已拉黑 / 失败）留在卡片下面，同按钮外观。
    @MainActor
    private var groupedRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(spacing: 0) {
                rowButton(
                    UserSafetyCopy.reportTitle,
                    accessibilityLabel: spokenName.map { UserSafetyCopy.reportTitle + $0 },
                    hint: UserSafetyCopy.reportHint,
                    identifier: "counterpartReportButton"
                ) {
                    showsReport = true
                }
                if !viewModel.didBlock {
                    Divider().padding(.leading, 16)
                    rowButton(
                        UserSafetyCopy.blockTitle,
                        accessibilityLabel: spokenName.map(UserSafetyCopy.blockLabel),
                        hint: UserSafetyCopy.blockHint,
                        identifier: "counterpartBlockButton"
                    ) {
                        showsBlockConfirm = true
                    }
                    .disabled(viewModel.isBlocking)
                }
            }
            .background(AppColors.Flow.surface)
            .clipShape(RoundedRectangle(cornerRadius: VolunteerSecondaryMetrics.cardRadius, style: .continuous))

            if viewModel.didBlock {
                outcome(UserSafetyCopy.blockSucceeded, color: AppColors.success, identifier: "counterpartBlockSucceeded")
            }
            if let errorMessage = viewModel.errorMessage {
                outcome(errorMessage, color: AppColors.destructive, identifier: "counterpartBlockError")
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func rowButton(
        _ title: String,
        accessibilityLabel: String?,
        hint: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(AppFonts.body())
                .foregroundColor(AppColors.primary)
                // 默认 56 给陪跑员搭档详情页（明眼人，Apple 44pt 线）；盲人端调用方传 64。
                .frame(maxWidth: .infinity, minHeight: groupedRowMinHeight, alignment: .leading) // guard:allow small-touch-target
                .padding(.horizontal, 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel ?? title)
        .accessibilityHint(hint)
        .accessibilityIdentifier(identifier)
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
