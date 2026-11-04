import SwiftUI

// MARK: - 答题页（整页弹出）

/// 课后答题与结果。照健康 App 心理健康问卷：**一页列出全部题**，每题一张白卡
/// （题号 + 题干 → 通栏分隔线 → 选项行，文字在左、圆圈在右），底部固定通栏胶囊「提交答案」。
///
/// 整页弹出盖住标签栏，左上返回正文、右上 ✕。结果页只有 ✕ 和一颗按钮：
/// 没全对 =「重答这 N 题」，全对 =「完成」。**不放「回到课程正文」**（负责人 2026-11-04 否决）。
///
/// 选择、交卷、只清错题的重答、学习时长都在 `VolunteerTrainingCourseViewModel` 里，这里只管画。
struct VolunteerTrainingQuizView: View {
    @ObservedObject var viewModel: VolunteerTrainingCourseViewModel
    let remainingRequiredTitles: [String]
    let onPassed: () -> Void
    let onFinish: () -> Void

    @Environment(\.dismiss) private var dismiss
    @AccessibilityFocusState private var focusesResultHeading: Bool

    private var courseTitle: String { viewModel.detail?.displayTitle ?? VolunteerTrainingCopy.navigationTitle }

    var body: some View {
        NavigationStack {
            Group {
                if let result = viewModel.lastResult {
                    resultContent(result)
                } else {
                    quizContent
                }
            }
            .background(TrainingSurface.page.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if viewModel.lastResult == nil {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button { dismiss() } label: { Image(systemName: "chevron.left") }
                            .accessibilityLabel("返回课程正文")
                            .accessibilityHint("已选的答案会保留")
                            .accessibilityIdentifier("volunteerTrainingQuizBackButton")
                    }
                    ToolbarItem(placement: .navigationBarTrailing) { closeButton }
                } else {
                    ToolbarItem(placement: .navigationBarLeading) { closeButton }
                }
            }
        }
        .onChange(of: viewModel.lastResult != nil) { hasResult in
            // 交卷后把读屏焦点挪到结果标题上：页面整个换了内容，不挪的话焦点留在已经消失的按钮上
            // 回到答题时先复位：标志一直停在 true 的话，下一次答错再赋 true 不会触发焦点移动
            guard hasResult else { focusesResultHeading = false; return }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                focusesResultHeading = true
            }
        }
        .onChange(of: viewModel.errorMessage) { message in
            // 交卷失败的红字在底栏里，读屏焦点不一定在那儿：念一遍，不然只是「按了没反应」
            guard let message else { return }
            UIAccessibility.post(notification: .announcement, argument: message)
        }
    }

    private var closeButton: some View {
        Button { dismiss() } label: { Image(systemName: "xmark") }
            .accessibilityLabel("关闭答题")
            .accessibilityHint(viewModel.lastResult == nil ? "回到课程正文，已选的答案会保留" : "回到课程正文")
            .accessibilityIdentifier("volunteerTrainingQuizCloseButton")
    }

    // MARK: 答题

    private var quizContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("\(courseTitle) · 课后答题")
                        .font(.title.bold())
                        .foregroundColor(AppColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(VolunteerTrainingCopy.quizIntro)
                        .font(.subheadline)
                        .foregroundColor(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if viewModel.hasUnanswerableQuestion {
                        // 🚩 选项加载不出来时明确说出来并挡住提交 —— 见 view model 的 unanswerableQuestionIds
                        Text(VolunteerTrainingCopy.brokenQuestion)
                            .font(AppFonts.body().weight(.semibold))
                            .foregroundColor(AppColors.destructive)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("volunteerTrainingBrokenQuestionNotice")
                    }

                    ForEach(Array(viewModel.questions.enumerated()), id: \.element.id) { index, question in
                        questionCard(index: index, question: question)
                            .id(question.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .readableContentColumn()
            }
            .safeAreaInset(edge: .bottom) { submitBar }
            .onAppear {
                // 重答回来时直接滚到第一道空着的题；全新开始时它就是第 1 题，不动
                guard !viewModel.selections.isEmpty, let first = firstUnansweredQuestionId else { return }
                proxy.scrollTo(first, anchor: .top)
            }
        }
    }

    private var firstUnansweredQuestionId: Int64? {
        viewModel.questions.first { viewModel.selections[$0.id] == nil }?.id
    }

    private func questionCard(index: Int, question: TrainingQuestion) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            questionHeader(number: index + 1, stem: question.displayStem)
            // 题干与选项之间一条通栏灰线，左右顶到卡边（负责人 2026-11-04 指出 v1 漏了这条）
            Divider()
            let options = question.visibleOptions
            ForEach(Array(options.enumerated()), id: \.element.id) { optionIndex, option in
                let isSelected = viewModel.selections[question.id] == option.id
                Button {
                    viewModel.selections[question.id] = option.id
                } label: {
                    TrainingOptionRow(text: option.displayText, mark: isSelected ? .selected : .empty)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.displayText)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                .accessibilityIdentifier("volunteerTrainingOption_\(question.id)_\(option.id)")
                if optionIndex < options.count - 1 {
                    // 选项之间的分隔线左侧留空，与题干下那条通栏线区分开
                    Divider().padding(.leading, 16)
                }
            }
        }
        .background(TrainingSurface.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        // ⚠️ 用 .contain 而不是 .combine：里面的选项是要能被逐个点到的按钮，
        // .combine 会把它们吃成一个不可操作的整体（记忆
        // `accessibility-identifier-overwrites-children` 的同类陷阱）
        .accessibilityElement(children: .contain)
    }

    private func questionHeader(number: Int, stem: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("第 \(number) 题，共 \(viewModel.questions.count) 题")
                .font(.footnote)
                .foregroundColor(AppColors.textSecondary)
            Text(stem)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        // 标题属性：读屏用「标题」转子能逐题跳，不用一个个选项划过去
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("volunteerTrainingQuestionHeader_\(number)")
    }

    private var submitBar: some View {
        TrainingBottomBar {
            // 交卷失败的原因挨着按钮放：放在题目列表末尾的话，人在上面改答案时根本看不见
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.subheadline)
                    .foregroundColor(AppColors.destructive)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("volunteerTrainingQuizError")
            }
            Button {
                Task {
                    if let result = await viewModel.submit(), result.isPassed {
                        onPassed()
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isSubmitting { ProgressView().tint(.white) }
                    Text(VolunteerTrainingCopy.submitQuiz)
                }
            }
            .buttonStyle(TrainingCapsuleButtonStyle(isLoading: viewModel.isSubmitting))
            .disabled(!viewModel.canSubmit)
            .accessibilityIdentifier("volunteerTrainingSubmitButton")

            // 🚩 按钮禁用时必须说明原因，而且原因和按钮在同一处 —— 只把按钮变灰的话，用户不知道少答了哪题
            if let hint = unansweredHint {
                Text(hint)
                    .font(.footnote)
                    .foregroundColor(AppColors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier("volunteerTrainingUnansweredHint")
            }
        }
    }

    /// 「还差第 2、3 题」。有答不了的题时不说（上面那条红字已经说了原因）。
    private var unansweredHint: String? {
        guard !viewModel.isEveryQuestionAnswered, !viewModel.hasUnanswerableQuestion else { return nil }
        let numbers = viewModel.questions.enumerated()
            .filter { viewModel.selections[$0.element.id] == nil }
            .map { String($0.offset + 1) }
        guard !numbers.isEmpty else { return nil }
        return "还差第 \(numbers.joined(separator: "、")) 题"
    }
}

// MARK: - 结果页

extension VolunteerTrainingQuizView {
    private func resultContent(_ result: TrainingQuizResult) -> some View {
        let wrongCount = result.visibleWrongQuestions.count
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    // 图形与颜色只是加强：感叹号 / 对勾的形状不同，结论在标题文字里
                    Image(systemName: result.isPassed ? "checkmark" : "exclamationmark")
                        .font(.title2.weight(.bold))
                        .foregroundColor(.white)
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(result.isPassed ? AppColors.success : AppColors.warning))
                        .accessibilityHidden(true)
                    Text(resultHeadline(result))
                        .font(.title.bold())
                        .foregroundColor(AppColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityFocused($focusesResultHeading)
                        .accessibilityIdentifier("volunteerTrainingQuizResult")
                    Text(resultDetail(result))
                        .font(.subheadline)
                        .foregroundColor(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 4)

                // 🚩 逐题解释必须给。可无限重考 + 全对才过的组合下，
                //    只说「答错了」会让用户唯一的策略变成改选项猜到过。
                ForEach(result.visibleWrongQuestions) { wrong in
                    wrongCard(wrong)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .readableContentColumn()
        }
        .safeAreaInset(edge: .bottom) {
            TrainingBottomBar {
                if result.isPassed {
                    Button(VolunteerTrainingCopy.finishQuiz) { onFinish() }
                        .buttonStyle(TrainingCapsuleButtonStyle())
                        .accessibilityHint("回到培训课程列表")
                        .accessibilityIdentifier("volunteerTrainingFinishButton")
                } else {
                    Button(wrongCount > 0 ? VolunteerTrainingCopy.retryQuiz(wrongCount: wrongCount) : VolunteerTrainingCopy.retryAll) {
                        viewModel.prepareRetry()
                    }
                    .buttonStyle(TrainingCapsuleButtonStyle())
                    .accessibilityHint("答对的题会保留，只需重新选答错的题")
                    .accessibilityIdentifier("volunteerTrainingRetryQuizButton")
                }
            }
        }
    }

    private func resultHeadline(_ result: TrainingQuizResult) -> String {
        let total = result.totalCount ?? viewModel.questions.count
        if result.isPassed { return "\(total) 题全对" }
        // 后端缺 correctCount 时按错题数推，别读成「答对 0 题」
        let correct = result.correctCount ?? max(0, total - result.visibleWrongQuestions.count)
        return "答对 \(correct) 题，共 \(total) 题"
    }

    private func resultDetail(_ result: TrainingQuizResult) -> String {
        guard result.isPassed else {
            let wrongCount = result.visibleWrongQuestions.count
            // 没全对却没给错题（不该发生）：不编题数，prepareRetry 此时什么都不清
            guard wrongCount > 0 else { return "全部答对才算学完。请检查答案后重新提交。" }
            return "全部答对才算学完。答对的会保留，只需重答 \(wrongCount) 题。"
        }
        var line = "「\(courseTitle)」已学完。"
        if result.requiredCompleted == true {
            line += VolunteerTrainingCopy.allDoneBanner
        } else if viewModel.detail?.isRequired == true, !remainingRequiredTitles.isEmpty {
            line += "还差 \(remainingRequiredTitles.count) 门必修：\(remainingRequiredTitles.joined(separator: "、"))。"
        }
        if result.awardedPointsValue > 0 {
            line += "获得 \(result.awardedPointsValue) 积分。"
        }
        if let certificateNo = result.certificateNo?.nilIfBlank {
            line += VolunteerTrainingCopy.certificateLine(certificateNo) + "。"
        }
        return line
    }

    /// 错题卡：与答题卡同一个样式，选错的那项右侧红色叉，下面灰字解析。
    private func wrongCard(_ wrong: TrainingQuizResult.WrongQuestion) -> some View {
        let index = viewModel.questions.firstIndex { $0.id == wrong.questionId }
        let question = index.map { viewModel.questions[$0] }
        let picked = viewModel.selections[wrong.questionId].flatMap { optionId in
            question?.visibleOptions.first { $0.id == optionId }
        }
        return VStack(alignment: .leading, spacing: 0) {
            if let index {
                questionHeader(number: index + 1, stem: question?.displayStem ?? wrong.stem?.nilIfBlank ?? "这道题答错了")
            } else {
                // 结果里的题不在本页题目里（不该发生）：至少把题干给出来
                Text(wrong.stem?.nilIfBlank ?? "这道题答错了")
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(16)
            }
            Divider()
            if let picked {
                TrainingOptionRow(text: picked.displayText, mark: .wrong)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("你选的是：\(picked.displayText)，答错了")
            }
            // explanation 可能为 nil（题目没填）—— 那就整段不显示，不显示 "nil"
            if let explanation = wrong.explanation?.nilIfBlank {
                Text(explanation)
                    .font(.subheadline)
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, picked == nil ? 12 : 0)
                    .padding(.bottom, 14)
                    // 不加前缀的话，读屏听起来像题干的延续
                    .accessibilityLabel("解析：\(explanation)")
            }
        }
        .background(TrainingSurface.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("volunteerTrainingWrongQuestion_\(wrong.questionId)")
    }
}
