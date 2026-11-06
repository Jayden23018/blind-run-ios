import SwiftUI

/// 核对清单一张卡的弹层（#812）：一题一屏，最后一题点「完成」整张卡一起保存。
///
/// 答案只存在本页的 `draft` 里；关掉弹层就丢掉，资料不变。没存上时留在最后一题，答案都在。
/// 视力卡没取得单独同意时，第一屏是同意页（文案全部取自 `PrivacyConsentPurpose.blindVisionProfile`，
/// 那是被单测钉住的合规文本，**不许在这里另写一份**）。
struct BlindProfileQuestionFlow: View {
    let card: BlindProfileCard
    @ObservedObject var viewModel: BlindRunnerProfileViewModel
    /// 存上了（或视力卡拒绝并存上了）。调用方据此关弹层、把读屏焦点放到这张卡上。
    let onFinished: () -> Void

    @EnvironmentObject private var speechService: SpeechService
    @EnvironmentObject private var speechInputService: SpeechInputService
    @Environment(\.dismiss) private var dismiss

    private let initialDraft: BlindProfileCardDraft
    @State private var draft: BlindProfileCardDraft
    @State private var showsConsent: Bool
    @State private var index = 0
    @State private var errorText: String?
    @State private var confirmsDiscard = false
    @AccessibilityFocusState private var isTitleFocused: Bool

    private static let consentPurpose = PrivacyConsentPurpose.blindVisionProfile
    /// 顶栏圆钮看得见的直径（照参考图）。可点区另由 `AppTouchTarget.blindPrimary` 撑到 64pt。
    private static let circleDiameter: CGFloat = 44
    /// 换屏后等这么久再放读屏焦点：同一帧里新视图还没进无障碍树，焦点会落空。
    private static let focusDelayNanoseconds: UInt64 = 350_000_000

    init(
        card: BlindProfileCard,
        viewModel: BlindRunnerProfileViewModel,
        initialDraft: BlindProfileCardDraft,
        startsWithConsent: Bool,
        onFinished: @escaping () -> Void
    ) {
        self.card = card
        self.viewModel = viewModel
        self.onFinished = onFinished
        self.initialDraft = initialDraft
        _draft = State(initialValue: initialDraft)
        _showsConsent = State(initialValue: startsWithConsent)
    }

    private var questions: [BlindProfileQuestion] { card.questions }
    private var question: BlindProfileQuestion { questions[min(index, questions.count - 1)] }
    private var isLast: Bool { index >= questions.count - 1 }
    private var isDirty: Bool { draft != initialDraft }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                Group {
                    if showsConsent {
                        consentContent
                    } else {
                        questionContent
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .readableContentColumn()
            }
            footer
        }
        .background(AppColors.background)
        // 改过答案就不许下滑关掉：一碰就丢，盲人用户不知道刚才选的没了。
        .interactiveDismissDisabled(isDirty || viewModel.isLoading)
        .alert("放弃本次修改？", isPresented: $confirmsDiscard) {
            Button("放弃", role: .destructive) { close() }
            Button("继续填写", role: .cancel) {}
        } message: {
            Text("已选内容不会保存，资料保持原样。")
        }
        .onAppear {
            viewModel.clearTransientNotices()
            if showsConsent {
                speechService.speak(text: Self.consentPurpose.spokenScript)
            }
            focusTitle()
        }
        .onChange(of: index) { _ in
            errorText = nil
            focusTitle()
        }
        .onDisappear {
            VoiceDictationButton.stopRecording(.profileSupplement, on: speechInputService)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("blindProfileFlow_\(card.rawValue)")
    }

    // MARK: - 顶栏：左上返回上一题、右上关闭

    private var topBar: some View {
        HStack {
            if !showsConsent && index > 0 {
                circleButton(systemImage: "chevron.left", label: "上一题", identifier: "blindProfileFlowBack") {
                    index -= 1
                }
            }
            Spacer()
            circleButton(systemImage: "xmark", label: "关闭", identifier: "blindProfileFlowClose") {
                if isDirty { confirmsDiscard = true } else { close() }
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 6)
    }

    /// 看得见的 44pt 圆钮，可点区 64pt（盲人端下限）。
    private func circleButton(systemImage: String, label: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundColor(AppColors.textPrimary)
                .frame(width: Self.circleDiameter, height: Self.circleDiameter)
                .background(Circle().fill(AppColors.Flow.page))
                .frame(width: AppTouchTarget.blindPrimary, height: AppTouchTarget.blindPrimary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isLoading)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    // MARK: - 同意页（只有视力卡）

    private var consentContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: card.systemImage)
                .font(.system(size: 52))
                .foregroundColor(card.tint)
                .frame(width: 112, height: 112)
                .background(Circle().fill(AppColors.Flow.page))
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)

            Text(Self.consentPurpose.title)
                .font(.title2.weight(.bold))
                .foregroundColor(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($isTitleFocused)

            // 每条告知各自一个读屏焦点，不并成一段（同 `ConsentDisclosureView.disclosureList`）。
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Self.consentPurpose.disclosures, id: \.self) { text in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("·")
                            .font(AppFonts.body())
                            .foregroundColor(AppColors.textSecondary)
                            .accessibilityHidden(true)
                        Text(text)
                            .font(AppFonts.body())
                            .foregroundColor(AppColors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            errorLine
        }
    }

    // MARK: - 题目

    private var questionContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 题号写进题目的读屏标签：换题时焦点落在题目上，先听到进度再听到题目。
            Text("第 \(index + 1) 题，共 \(questions.count) 题")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(AppColors.textSecondary)
                .accessibilityHidden(true)
            Text(question.title)
                .font(.title2.weight(.bold))
                .foregroundColor(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("第 \(index + 1) 题，共 \(questions.count) 题，\(question.title)")
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($isTitleFocused)
                .accessibilityIdentifier("blindProfileFlowQuestionTitle")
            Text(question.note)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            switch question.kind {
            case .single, .multi:
                optionGroup
            case .supplement:
                supplementField
            }
            errorLine
        }
        .padding(.top, 4)
    }

    private var optionGroup: some View {
        VStack(spacing: 0) {
            ForEach(Array(question.options.enumerated()), id: \.element.id) { offset, option in
                if offset > 0 {
                    GroupedCardDivider()
                }
                optionRow(option, offset: offset)
            }
        }
        .background(AppColors.Flow.page)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.top, 8)
    }

    private func optionRow(_ option: BlindProfileOption, offset: Int) -> some View {
        let isMulti = question.kind == .multi
        let isSelected = isMulti
            ? draft.selectedSet(for: question).contains(option.id)
            : draft.selection(for: question) == option.id
        let mark = isMulti
            ? (isSelected ? "checkmark.square.fill" : "square")
            : (isSelected ? "checkmark.circle.fill" : "circle")
        return Button {
            draft = isMulti ? draft.toggling(option.id, for: question) : draft.choosing(option.id, for: question)
            errorText = nil
        } label: {
            HStack(spacing: 12) {
                Text(option.title)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                Image(systemName: mark)
                    .font(.title2)
                    .foregroundColor(isSelected ? AppColors.primary : AppColors.textSecondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, GroupedCardMetrics.rowHorizontalPadding)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: AppTouchTarget.blindPrimary, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isLoading)
        .accessibilityLabel(option.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("blindProfileOption_\(question.rawValue)_\(offset)")
    }

    private var supplementField: some View {
        let answer = draft.phraseAnswer(for: question) ?? .empty
        let set = question.phraseSet ?? .guideNote
        let remainingText = set.remainingText(for: answer)
        return VStack(alignment: .leading, spacing: 8) {
            VoiceTextField(
                title: "补充说明",
                placeholder: "例如：我习惯陪跑员在我左侧",
                text: Binding(
                    get: { draft.phraseAnswer(for: question)?.supplement ?? "" },
                    set: { draft = draft.withSupplement($0, for: question); errorText = nil }
                ),
                isMultiline: true,
                speechInputService: speechInputService,
                speechService: speechService,
                speechField: .profileSupplement,
                accessibilityLabel: "补充说明，选填",
                accessibilityHint: remainingText
            )
            Text(remainingText)
                .font(AppFonts.caption())
                .foregroundColor(set.remaining(for: answer) < 0 ? AppColors.destructive : AppColors.textSecondary)
                .accessibilityIdentifier("blindProfileFlowRemaining")
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var errorLine: some View {
        if let errorText {
            Label(errorText, systemImage: "exclamationmark.circle.fill")
                .font(AppFonts.body())
                .foregroundColor(AppColors.destructive)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(errorText)
                .accessibilityIdentifier("blindProfileSaveError")
        }
    }

    // MARK: - 底部按钮（一屏一个实心）

    private var footer: some View {
        VStack(spacing: 0) {
            if showsConsent {
                // 同意与拒绝一样宽、一样整行铺满（`PrivacyConsent.swift` `declineButtonTitle` 上那段）。
                Button(Self.consentPurpose.agreeButtonTitle, action: agree)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(viewModel.isLoading)
                    .accessibilityIdentifier("blindProfileVisionConsentAgree")
                Button(Self.consentPurpose.declineButtonTitle, action: decline)
                    .buttonStyle(NeutralButtonStyle())
                    .disabled(viewModel.isLoading)
                    .accessibilityIdentifier("blindProfileVisionConsentDecline")
            } else {
                advanceButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(AppColors.background)
    }

    private var advanceButton: some View {
        let canAdvance = draft.canAdvance(from: question)
        let title = isLast ? "完成" : "继续"
        return Button(action: advance) {
            HStack(spacing: AppSpacing.small) {
                if viewModel.isLoading {
                    ProgressView()
                        .tint(.white)
                }
                Text(title)
            }
        }
        .buttonStyle(PrimaryButtonStyle(isLoading: viewModel.isLoading))
        .disabled(!canAdvance || viewModel.isLoading)
        .accessibilityLabel(viewModel.isLoading ? "正在保存" : title)
        .accessibilityHint(canAdvance ? (isLast ? "保存\(card.title)" : "进入下一题") : "请先选择一项")
        .accessibilityIdentifier("blindProfileFlowContinue")
    }

    // MARK: - 动作

    private func advance() {
        guard draft.canAdvance(from: question), !viewModel.isLoading else { return }
        guard isLast else {
            index += 1
            return
        }
        if let lengthError = draft.lengthError(for: card) {
            errorText = lengthError
            speechService.speakError(lengthError)
            return
        }
        VoiceDictationButton.stopRecording(.profileSupplement, on: speechInputService)
        let answers = draft
        let card = card
        Task {
            let saved = await viewModel.saveCard(savedLabel: answers.savedLabel(for: card)) { viewModel in
                answers.apply(to: card, viewModel: viewModel)
            }
            if saved {
                onFinished()
            } else {
                errorText = viewModel.errorMessage
            }
        }
    }

    private func agree() {
        viewModel.acceptVisionConsent()
        showsConsent = false
        index = 0
        focusTitle()
    }

    private func decline() {
        Task {
            if await viewModel.declineVisionConsentAndSave() {
                onFinished()
            } else {
                errorText = viewModel.errorMessage
            }
        }
    }

    private func close() {
        VoiceDictationButton.stopRecording(.profileSupplement, on: speechInputService)
        dismiss()
    }

    /// 换屏后把读屏焦点放到题目上。等一拍再放：同一帧里新视图还没进无障碍树，焦点会落空。
    private func focusTitle() {
        isTitleFocused = false
        Task {
            try? await Task.sleep(nanoseconds: Self.focusDelayNanoseconds)
            isTitleFocused = true
        }
    }
}
