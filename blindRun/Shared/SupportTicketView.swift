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
        // 与校验闸同一个计数口径（UTF-16），否则会出现「提示还剩 3 个字、提交却被拦」。
        SupportTicketRequest.maxContentLength - SupportTicketRequest.length(of: content)
    }

    /// 返回是否提交成功。**失败一律留在这一屏** —— 关掉页面等于把用户刚写的那段字扔了。
    @discardableResult
    func submit(orderID: Int64?, category: SupportTicketCategory = .orderService, appState: AppState) async -> Bool {
        guard !isSubmitting else { return false }
        // 校验走 `SupportTicketRequest` 的可失败构造，**不在这里重写一遍条件**：
        // 两处各判一次，改一处漏一处的表现是「按钮亮着、点了没反应」。
        guard let request = SupportTicketRequest(
            category: category,
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
                errorMessage = error.errorCode == .supportTicketLimitExceeded
                    ? error.localizedMessage
                    : SupportTicketCopy.failed
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
/// **分类由入口决定**，不给选择题：订单页是 `ORDER_SERVICE`，「我的」页是 `ACCOUNT`。
/// 分类是给客服分流用的，多一个选项读屏用户就多听一句。
struct SupportTicketView: View {
    let orderID: Int64?
    var category: SupportTicketCategory = .orderService
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
                VStack(alignment: .leading, spacing: 8) {
                    // 定稿 #755：输入框白卡在上，说明挪到下面当组说明。
                    TextEditor(text: $viewModel.content)
                        .font(AppFonts.body())
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 160)
                        .padding(8)
                        .background(AppColors.Flow.surface)
                        .clipShape(RoundedRectangle(cornerRadius: GroupedCardMetrics.cardRadius, style: .continuous))
                        .overlay(alignment: .topLeading) {
                            // 占位字只给看的人；读屏已经从 `accessibilityLabel` 听到同一句。
                            if viewModel.content.isEmpty {
                                Text(SupportTicketCopy.prompt)
                                    .font(AppFonts.body())
                                    .foregroundColor(AppColors.textSecondary)
                                    .padding(.horizontal, 13)
                                    .padding(.vertical, 16)
                                    .allowsHitTesting(false)
                                    .accessibilityHidden(true)
                            }
                        }
                        .focused($isEditorFocused)
                        .accessibilityLabel(SupportTicketCopy.prompt)
                        .accessibilityIdentifier("supportTicketEditor")

                    noticeText
                        .font(.footnote)
                        .foregroundColor(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, GroupedCardMetrics.rowHorizontalPadding)

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
                            .padding(.horizontal, GroupedCardMetrics.rowHorizontalPadding)
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
                            .padding(.horizontal, GroupedCardMetrics.rowHorizontalPadding)
                            .accessibilityIdentifier("supportTicketError")
                    }
                    if viewModel.didSubmit {
                        Label(SupportTicketCopy.submitted, systemImage: "checkmark.circle.fill")
                            .font(AppFonts.body())
                            .foregroundColor(AppColors.success)
                            .padding(.horizontal, GroupedCardMetrics.rowHorizontalPadding)
                            .accessibilityIdentifier("supportTicketSubmitted")
                    }

                    PrimaryButton(SupportTicketCopy.submit, isLoading: viewModel.isSubmitting) {
                        Task {
                            isEditorFocused = false
                            if await viewModel.submit(orderID: orderID, category: category, appState: appState) {
                                speak(SupportTicketCopy.submitted)
                                dismiss()
                            } else if let message = viewModel.errorMessage {
                                speakError(message)
                            }
                        }
                    }
                    .padding(.top, 16)
                    .accessibilityIdentifier("supportTicketSubmit")

                    // 不放工具栏：系统会把工具栏文字按钮包成字号固定的玻璃按钮，审计判对比度与字号都不过，
                    // 也够不到 64pt（记忆 sheet-toolbar-text-button-fails-audit，举报页 #524 同样处理）。
                    // 定稿 #755：降成一行蓝字，可点区仍是整行 64pt（写在 `TextButtonStyle` 里）。
                    Button(UserSafetyCopy.close) { dismiss() }
                        .buttonStyle(TextButtonStyle(alignment: .center))
                        .accessibilityIdentifier("supportTicketClose")
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
                .readableContentColumn()
            }
            .background(AppColors.Flow.page)
            .navigationTitle(SupportTicketCopy.title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    /// 说明里「有危险就打 120 / 110」那句加粗。文案仍是 `SupportTicketCopy.notice` 一个常量，
    /// 这里只按句子拆开上样式；哪天那句改了对不上，就整段照常显示，不丢字。
    private var noticeText: Text {
        let notice = SupportTicketCopy.notice
        guard let range = notice.range(of: Self.dangerSentence) else { return Text(notice) }
        return Text(notice[..<range.lowerBound])
            + Text(notice[range]).bold()
            + Text(notice[range.upperBound...])
    }

    static let dangerSentence = "如果现在有危险，请直接拨打 120 或 110。"
}
