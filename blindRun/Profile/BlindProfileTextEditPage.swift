import SwiftUI

/// 个人资料里可以改字的三项（#750）。
enum BlindProfileTextField {
    case nickname
    case guideNote
    case specialNeeds

    var title: String {
        switch self {
        case .nickname: return BlindProfileCopy.nickname
        case .guideNote: return BlindProfileCopy.guideNote
        case .specialNeeds: return BlindProfileCopy.specialNeeds
        }
    }

    var placeholder: String {
        switch self {
        case .nickname: return "请输入昵称"
        case .guideNote: return "例如：我习惯你在我左边，转弯前提前说一声"
        case .specialNeeds: return "例如：需要语言引导"
        }
    }

    var isMultiline: Bool { self != .nickname }

    /// 读屏标签沿用改版前表单输入框的说法（UI 用例与读屏用户都认这几句）。
    var accessibilityLabel: String {
        switch self {
        case .nickname: return "昵称，必填"
        case .guideNote: return "给陪跑员的引导偏好，选填"
        case .specialNeeds: return "特殊需求，选填"
        }
    }

    var accessibilityHint: String {
        switch self {
        case .nickname: return "请输入你的昵称"
        case .guideNote:
            return "用你自己的话写，最多 \(BlindProfileUpdateRequest.guidePreferenceMaxLength) 个字。陪跑员接单后才看得到"
        case .specialNeeds: return "如有特殊需求请填写"
        }
    }

    /// 输入框下面那行灰字。给陪跑员的话带剩余字数，按 UTF-16 数，与 `guidePreferenceLengthError`、后端 `@Size` 同口径。
    func footnote(for draft: String) -> String {
        switch self {
        case .nickname:
            let range = BlindRunnerProfileViewModel.nicknameLengthRange
            return "必填，\(range.lowerBound) 到 \(range.upperBound) 个字。"
        case .guideNote:
            let limit = BlindProfileUpdateRequest.guidePreferenceMaxLength
            let remaining = limit - draft.trimmed.utf16.count
            let count = remaining >= 0 ? "还能写 \(remaining) 个字" : "已经超出 \(-remaining) 个字"
            return "最多 \(limit) 个字，\(count)。陪跑员接单后才看得到，接单前不会给任何人看。"
        case .specialNeeds:
            return "陪跑员接单后才看得到，接单前不会给任何人看。"
        }
    }
}

/// 个人资料的文字编辑页（#750）：一个输入框，底部「保存」。
///
/// 输入框改的是页内草稿；按「保存」才写进资料并整份提交。存上了回查看页，没存上留在本页、草稿不丢，
/// 资料里那一项由 `saveChange` 改回原值。
struct BlindProfileTextEditPage: View {
    @EnvironmentObject private var speechService: SpeechService
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: BlindRunnerProfileViewModel
    let field: BlindProfileTextField
    @Binding var text: String
    @State private var draft: String
    @FocusState private var isFocused: Bool

    init(viewModel: BlindRunnerProfileViewModel, field: BlindProfileTextField, text: Binding<String>) {
        self.viewModel = viewModel
        self.field = field
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
                        .accessibilityLabel(field.accessibilityLabel)
                        .accessibilityHint(field.accessibilityHint)
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

                GroupedCardFootnote(text: field.footnote(for: draft))
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
        .navigationTitle(field.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            viewModel.clearTransientNotices()
            speechService.speak("\(field.title)。改完按页面底部的保存。")
        }
    }

    @ViewBuilder
    private var inputField: some View {
        if field.isMultiline {
            TextField(field.placeholder, text: $draft, axis: .vertical)
                .lineLimit(4...10)
        } else {
            TextField(field.placeholder, text: $draft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit(save)
        }
    }

    private var saveBar: some View {
        PrimaryButton("保存", isLoading: viewModel.isLoading) {
            save()
        }
        .disabled(viewModel.isLoading)
        .accessibilityLabel("保存\(field.title)")
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
            let saved = await viewModel.saveChange(savedLabel: field.title, requiresNickname: field == .nickname) {
                text = previous
            }
            if saved {
                dismiss()
            }
        }
    }
}
