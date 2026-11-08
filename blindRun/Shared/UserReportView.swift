import Combine
import SwiftUI

// MARK: - 举报

@MainActor
final class UserReportViewModel: ObservableObject {
    @Published var reason: UserReportReason?
    @Published var detail = ""
    @Published private(set) var isSubmitting = false
    @Published private(set) var errorMessage: String?
    /// 非 `nil` = 已提交，内容是要显示并朗读的结果句。
    @Published private(set) var submittedMessage: String?

    var remainingCharacters: Int {
        let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        return UserReportRequest.maxDetailLength - UserReportRequest.length(of: trimmed)
    }

    /// 失败一律留在这一屏，已选的原因和已写的字都不丢。
    @discardableResult
    func submit(target: CounterpartSafetyTarget, appState: AppState) async -> Bool {
        guard !isSubmitting else { return false }
        guard let reason else {
            errorMessage = UserSafetyCopy.reasonRequired
            return false
        }
        guard let request = UserReportRequest(target: target, reason: reason, detail: detail) else {
            errorMessage = UserSafetyCopy.detailTooLong(limit: UserReportRequest.maxDetailLength)
            return false
        }

        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            let ticket = try await appState.safety.report(request)
            submittedMessage = UserSafetyCopy.reportSubmitted(ticketId: ticket.id)
            return true
        } catch let error as APIError {
            if !error.endsSession {
                errorMessage = UserSafetyCopy.failureMessage(for: error, fallback: UserSafetyCopy.reportFailed)
            }
            return false
        } catch {
            errorMessage = UserSafetyCopy.reportFailed
            return false
        }
    }
}

/// 举报那一屏，两端共用。从 `.sheet` 弹出，所以依赖显式传入，理由同 `SupportTicketView`。
///
/// 🚨 **不是紧急求助入口。** 这里不放任何求助按钮，`UserSafetyCopy.reportNotice` 只把时效说清楚。
struct UserReportView: View {
    let target: CounterpartSafetyTarget
    let appState: AppState
    let speak: (String) -> Void
    let speakError: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    /// 只给详情框的语音输入用（#795）。根视图注入，弹层继承。
    @EnvironmentObject private var speechInputService: SpeechInputService
    @EnvironmentObject private var speechService: SpeechService
    @StateObject private var viewModel = UserReportViewModel()
    @FocusState private var isEditorFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let message = viewModel.submittedMessage {
                        submitted(message)
                    } else {
                        form
                    }
                }
                .padding(20)
                .readableContentColumn()
            }
            .navigationTitle(target.messageId == nil ? UserSafetyCopy.reportTitle : UserSafetyCopy.reportMessageTitle)
            .navigationBarTitleDisplayMode(.inline)
        }
        .accessibilityIdentifier("userReportView")
    }

    @ViewBuilder
    private var form: some View {
        Text(UserSafetyCopy.reportNotice)
            .font(AppFonts.body())
            .foregroundColor(AppColors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

        if let quoted = target.quotedText {
            Text(UserSafetyCopy.quoted(quoted))
                .font(AppFonts.body())
                .foregroundColor(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AppColors.secondaryBackground))
                .accessibilityIdentifier("userReportQuotedMessage")
        }

        Text(UserSafetyCopy.reasonPrompt)
            .font(AppFonts.title())
            .foregroundColor(AppColors.textPrimary)
            .accessibilityAddTraits(.isHeader)

        ForEach(UserReportReason.allCases, id: \.self) { reason in
            reasonRow(reason)
        }

        // 读屏走输入框自己的标签，这一行只给看屏幕的人：空白方框说不清它是干什么的。
        Text(UserSafetyCopy.detailPrompt)
            .font(AppFonts.body())
            .foregroundColor(AppColors.textSecondary)
            .accessibilityHidden(true)

        TextEditor(text: $viewModel.detail)
            .font(AppFonts.body())
            .frame(minHeight: 120)
            .padding(8)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(AppColors.Flow.ghostStroke, lineWidth: 1)
            )
            .focused($isEditorFocused)
            .accessibilityLabel(UserSafetyCopy.detailPrompt)
            .accessibilityIdentifier("userReportDetail")

        VoiceDictationButton(
            fieldTitle: "补充说明",
            text: $viewModel.detail,
            speechInputService: speechInputService,
            speechService: speechService,
            speechField: .userReportDetail
        )
        .disabled(viewModel.isSubmitting)

        if viewModel.remainingCharacters <= 100 {
            Text(UserSafetyCopy.remaining(max(viewModel.remainingCharacters, 0)))
                .font(AppFonts.caption())
                .foregroundColor(viewModel.remainingCharacters < 0 ? AppColors.destructive : AppColors.textSecondary)
                .accessibilityIdentifier("userReportRemaining")
        }

        // 失败留在正文里，不只靠一句播报：不开读屏的低视力用户屏幕上也要有东西变。
        if let errorMessage = viewModel.errorMessage {
            Text(errorMessage)
                .font(AppFonts.body())
                .foregroundColor(AppColors.destructive)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("userReportError")
        }

        PrimaryButton(UserSafetyCopy.submitReport, isLoading: viewModel.isSubmitting) {
            Task {
                isEditorFocused = false
                VoiceDictationButton.stopRecording(.userReportDetail, on: speechInputService)
                if await viewModel.submit(target: target, appState: appState) {
                    if let message = viewModel.submittedMessage { speak(message) }
                } else if let message = viewModel.errorMessage {
                    speakError(message)
                }
            }
        }
        .accessibilityIdentifier("userReportSubmit")

        // 不放工具栏：系统会把工具栏按钮包成字号固定的玻璃按钮，审计判对比度与字号都不过，也够不到 64pt。
        // 灰按钮，与上面的实心主按钮同形状（#749）。原来的 `.ghost` 描边压白底只有 1.52:1。
        Button(UserSafetyCopy.close) { dismiss() }
            .buttonStyle(NeutralButtonStyle())
            .accessibilityIdentifier("userReportClose")
    }

    private func reasonRow(_ reason: UserReportReason) -> some View {
        let isSelected = viewModel.reason == reason
        return Button {
            viewModel.reason = reason
        } label: {
            HStack(spacing: 12) {
                // 选中靠图标形状和读屏特征表达，不只靠颜色。
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(isSelected ? AppColors.primary : AppColors.textSecondary)
                    .accessibilityHidden(true)
                Text(reason.displayName)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: FlowMetrics.actionButtonMinHeight, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AppColors.secondaryBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? AppColors.primary : AppColors.Flow.ghostStroke, lineWidth: isSelected ? 2 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(reason.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func submitted(_ message: String) -> some View {
        Label(message, systemImage: "checkmark.circle.fill")
            .font(AppFonts.body())
            .foregroundColor(AppColors.success)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("userReportSubmitted")

        PrimaryButton(UserSafetyCopy.done) { dismiss() }
            .accessibilityIdentifier("userReportDone")
    }
}
