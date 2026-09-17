import Combine
import SwiftUI

// MARK: - 事后工单

@MainActor
final class SupportTicketViewModel: ObservableObject {
    @Published var content = ""
    @Published private(set) var isSubmitting = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var didSubmit = false

    var remainingCharacters: Int {
        SupportTicketRequest.maxContentLength - content.count
    }

    /// 返回是否提交成功。**失败一律留在这一屏** —— 关掉页面等于把用户刚写的那段字扔了。
    @discardableResult
    func submit(orderID: Int64?, appState: AppState) async -> Bool {
        guard !isSubmitting else { return false }
        // 校验走 `SupportTicketRequest` 的可失败构造，**不在这里重写一遍条件**：
        // 两处各判一次，改一处漏一处的表现是「按钮亮着、点了没反应」。
        guard let request = SupportTicketRequest(
            category: .orderService,
            content: content,
            orderId: orderID
        ) else {
            errorMessage = content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? SupportTicketCopy.emptyContent
                : SupportTicketCopy.tooLong(limit: SupportTicketRequest.maxContentLength)
            return false
        }

        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            try await appState.safety.submitSupportTicket(request)
            didSubmit = true
            return true
        } catch let error as APIError {
            if !appState.handleAuthenticatedAPIError(error) {
                errorMessage = SupportTicketCopy.failed
            }
            return false
        } catch {
            errorMessage = SupportTicketCopy.failed
            return false
        }
    }
}

/// 「上报问题」那一屏。盲人端与陪跑员端**共用**（契约刻意不限角色：
/// 只让盲人提，等于让志愿者的问题永远没有出口），所以放在 `Shared/`。
///
/// 🚨 **不是紧急求助入口。** `SupportTicketCopy.notice` 在写字之前就把时效说清楚，
/// 并把真正紧急时该做的事（拨 120 / 110）直接写出来 —— 契约对这条端点的 description
/// 逐字要求「客户端文案不得把用户从 SOS 引到这里」。
///
/// **分类固定 `ORDER_SERVICE`**，不给选择题：这一屏唯一的入口是订单页上的「上报问题」，
/// 分类是给客服分流用的，多一个选项读屏用户就多听一句。
struct SupportTicketView: View {
    let orderID: Int64?
    /// 显式传进来而不是 `@EnvironmentObject`：这一屏是从 `.sheet` 弹出来的，
    /// 依赖显式传递就不必赌环境有没有传下去。
    let appState: AppState
    let speak: (String) -> Void
    let speakError: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = SupportTicketViewModel()
    @FocusState private var isEditorFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(SupportTicketCopy.notice)
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    TextEditor(text: $viewModel.content)
                        .font(AppFonts.body())
                        .frame(minHeight: 160)
                        .padding(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(AppColors.Flow.ghostStroke, lineWidth: 1)
                        )
                        .focused($isEditorFocused)
                        .accessibilityLabel(SupportTicketCopy.prompt)
                        .accessibilityIdentifier("supportTicketEditor")

                    // 剩余字数**只在快写满时出现**：一个一直在变的数字挂在那里，
                    // 读屏用户每次经过都要听一遍，而绝大多数反馈只有两三行。
                    if viewModel.remainingCharacters <= 100 {
                        Text(SupportTicketCopy.remaining(max(viewModel.remainingCharacters, 0)))
                            .font(AppFonts.caption())
                            .foregroundColor(
                                viewModel.remainingCharacters < 0
                                    ? AppColors.destructive
                                    : AppColors.textSecondary
                            )
                            .accessibilityIdentifier("supportTicketRemaining")
                    }

                    // 失败与成功都**留在正文里**，不只靠一句 TTS ——
                    // 不开读屏的低视力用户屏幕上必须也有东西变（记忆
                    // `claimed-fallback-may-not-exist-in-release`）。
                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(AppFonts.body())
                            .foregroundColor(AppColors.destructive)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("supportTicketError")
                    }
                    if viewModel.didSubmit {
                        Label(SupportTicketCopy.submitted, systemImage: "checkmark.circle.fill")
                            .font(AppFonts.body())
                            .foregroundColor(AppColors.success)
                            .accessibilityIdentifier("supportTicketSubmitted")
                    }

                    PrimaryButton(SupportTicketCopy.submit, isLoading: viewModel.isSubmitting) {
                        Task {
                            isEditorFocused = false
                            if await viewModel.submit(orderID: orderID, appState: appState) {
                                speak(SupportTicketCopy.submitted)
                                dismiss()
                            } else if let message = viewModel.errorMessage {
                                speakError(message)
                            }
                        }
                    }
                    .accessibilityIdentifier("supportTicketSubmit")
                }
                .padding(20)
                .readableContentColumn()
            }
            .navigationTitle(SupportTicketCopy.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}
