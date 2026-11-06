import SwiftUI

/// 改昵称页的文案（#750）。#812 起「给陪跑员的话」「特殊需求」改成核对清单里的常用说法，
/// 这一页只剩昵称。
enum BlindProfileNicknameCopy {
    static let title = BlindProfileCopy.nickname
    static let placeholder = "请输入昵称"
    /// 读屏标签沿用改版前表单输入框的说法（UI 用例与读屏用户都认这句）。
    static let accessibilityLabel = "昵称，必填"
    static let accessibilityHint = "请输入你的昵称"

    static var footnote: String {
        let range = BlindRunnerProfileViewModel.nicknameLengthRange
        return "必填，\(range.lowerBound) 到 \(range.upperBound) 个字。"
    }
}

/// 改昵称页（#750）：一个输入框，底部「保存」。
///
/// 输入框改的是页内草稿；按「保存」才写进资料并整份提交。存上了回查看页，没存上留在本页、草稿不丢，
/// 资料里那一项由 `saveChange` 改回原值。
struct BlindProfileTextEditPage: View {
    @EnvironmentObject private var speechService: SpeechService
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: BlindRunnerProfileViewModel
    @Binding var text: String
    @State private var draft: String
    @FocusState private var isFocused: Bool

    init(viewModel: BlindRunnerProfileViewModel, text: Binding<String>) {
        self.viewModel = viewModel
        _text = text
        _draft = State(initialValue: text.wrappedValue)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                GroupedCard {
                    inputField
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.textPrimary)
                        .focused($isFocused)
                        .padding(.horizontal, GroupedCardMetrics.rowHorizontalPadding)
                        .padding(.vertical, 16)
                        .frame(maxWidth: .infinity, minHeight: AppTouchTarget.blindPrimary, alignment: .topLeading)
                        .accessibilityLabel(BlindProfileNicknameCopy.accessibilityLabel)
                        .accessibilityHint(BlindProfileNicknameCopy.accessibilityHint)
                        .accessibilityIdentifier("blindProfileTextEditField")
                }

                if let error = viewModel.errorMessage {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.destructive)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, GroupedCardMetrics.rowHorizontalPadding)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(error)
                        .accessibilityIdentifier("blindProfileSaveError")
                }

                GroupedCardFootnote(text: BlindProfileNicknameCopy.footnote)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 24)
            .readableContentColumn()
        }
        .scrollDismissesKeyboard(.interactively)
        .background(AppColors.Flow.page)
        .safeAreaInset(edge: .bottom) {
            saveBar
        }
        .navigationTitle(BlindProfileNicknameCopy.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            viewModel.clearTransientNotices()
            speechService.speak("\(BlindProfileNicknameCopy.title)。改完按页面底部的保存。")
        }
    }

    private var inputField: some View {
        TextField(BlindProfileNicknameCopy.placeholder, text: $draft)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .onSubmit(save)
    }

    private var saveBar: some View {
        PrimaryButton("保存", isLoading: viewModel.isLoading) {
            save()
        }
        .disabled(viewModel.isLoading)
        .accessibilityLabel("保存\(BlindProfileNicknameCopy.title)")
        .accessibilityHint("保存后回到个人资料")
        .accessibilityIdentifier("blindProfileTextEditSave")
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppColors.Flow.page)
        // 先 `.contain` 再挂 id，否则会盖掉按钮的 id（记忆 `accessibility-identifier-overwrites-children`）。
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("blindProfileEditSaveBar")
    }

    private func save() {
        guard !viewModel.isLoading else { return }
        isFocused = false
        let previous = text
        text = draft
        Task {
            let saved = await viewModel.saveChange(savedLabel: BlindProfileNicknameCopy.title, requiresNickname: true) {
                text = previous
            }
            if saved {
                dismiss()
            }
        }
    }
}
