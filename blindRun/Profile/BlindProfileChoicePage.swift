import SwiftUI

/// 个人资料的选择页（#750）：照设置 App 的选择页，每项一行 64pt，选中打对勾，点了当场整份保存。
///
/// 不在页内另存一份值，直接绑资料的那个字段：查看页那一行和这里的对勾永远说同一个值。
/// 没存上时 `saveChange` 把字段改回去，对勾跟着回到原值。
struct BlindProfileChoicePage<Value: Hashable>: View {
    @EnvironmentObject private var speechService: SpeechService
    @ObservedObject var viewModel: BlindRunnerProfileViewModel
    let title: String
    let choices: [BlindProfileChoice<Value>]
    @Binding var selection: Value
    let footnote: String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                GroupedCard {
                    ForEach(Array(choices.enumerated()), id: \.element.id) { index, choice in
                        if index > 0 {
                            GroupedCardDivider()
                        }
                        choiceRow(choice)
                    }
                }

                // 保存结果紧跟在列表下面：屏幕上能看见，读屏也念过一遍（`saveProfile` 里）。
                if let saved = viewModel.savedNotice {
                    Label(saved, systemImage: "checkmark.circle.fill")
                        .font(AppFonts.body().weight(.semibold))
                        .foregroundColor(AppColors.success)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, GroupedCardMetrics.rowHorizontalPadding)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(saved)
                        .accessibilityIdentifier("blindProfileSavedNotice")
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

                GroupedCardFootnote(text: footnote)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 32)
            .readableContentColumn()
        }
        .background(AppColors.Flow.page)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            viewModel.clearTransientNotices()
            speechService.speak("\(title)。现在是：\(currentTitle)。点一项就当场保存。")
        }
    }

    private var currentTitle: String {
        choices.first { $0.value == selection }?.title ?? BlindProfileCopy.unfilled
    }

    private func choiceRow(_ choice: BlindProfileChoice<Value>) -> some View {
        let isSelected = choice.value == selection
        return Button {
            choose(choice)
        } label: {
            HStack(spacing: 8) {
                Text(choice.title)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(AppFonts.body().weight(.semibold))
                        .foregroundColor(AppColors.primary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, GroupedCardMetrics.rowHorizontalPadding)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: AppTouchTarget.blindPrimary, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // 保存中不收第二次点击：两次请求谁先回来就决定最终值，不可控。
        .disabled(viewModel.isLoading)
        .accessibilityLabel(choice.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func choose(_ choice: BlindProfileChoice<Value>) {
        guard !viewModel.isLoading else { return }
        guard choice.value != selection else {
            // 点已选中的那项也给一声，免得盲人用户以为没点到。
            speechService.speak("现在就是：\(choice.title)")
            return
        }
        let previous = selection
        selection = choice.value
        Task {
            await viewModel.saveChange(savedLabel: choice.title) {
                selection = previous
            }
        }
    }
}
