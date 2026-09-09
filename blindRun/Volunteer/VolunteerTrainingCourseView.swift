// `import Combine` 只为 `@Published` / `ObservableObject` 的合成 —— 
// 本文件**不订阅任何 publisher**，也没有 `AnyCancellable`。
// AGENTS.md 的并发硬约束是「同一条数据流不许既订阅 Combine 又 await」，
// 这里的数据流全走 async/await。
import Combine
import OSLog
import SwiftUI

// MARK: - 课程详情 ViewModel

/// 一门课的正文 + 答题。
///
/// 并发只用 async/await（AGENTS.md 硬约束）。
@MainActor
final class VolunteerTrainingCourseViewModel: ObservableObject {
    @Published private(set) var detail: TrainingCourseDetail?
    @Published private(set) var isLoading = false
    @Published private(set) var isSubmitting = false
    @Published var errorMessage: String?

    /// 已选答案：questionId → optionId。
    @Published var selections: [Int64: String] = [:]
    @Published private(set) var lastResult: TrainingQuizResult?
    /// 是否已经进入答题区（正文读完之后才展开，避免一屏塞两件事）。
    @Published var isQuizVisible = false

    private static let logger = Logger(subsystem: "com.jerry.aidrun", category: "training")

    private weak var appState: AppState?
    private let courseId: Int64

    /// 本次进入课程页累计的停留秒数。
    ///
    /// 🚩 政策要求记录「学习时长」（中央社会工作部 2025-06 培训指引）。
    /// 用「进入时刻 → 离开时刻」这一对时间戳算，**不用定时器**：定时器要处理
    /// 进后台、被电话打断、页面被 push 覆盖三种情况，而这里只需要一个近似值。
    private var enteredAt: Date?

    init(courseId: Int64) {
        self.courseId = courseId
    }

    /// ⚠️ `appState` 是 `weak`，传临时对象等于传 nil（守卫规则 `weak-temporary`）。
    func configure(appState: AppState) {
        self.appState = appState
    }

    var questions: [TrainingQuestion] { detail?.visibleQuestions ?? [] }

    /// 选项缺失、答不了的题。
    ///
    /// 🚩 有这种题时**不能允许提交** —— 「全对才过」意味着他永远交不了卷，
    /// 而界面上不会有任何东西说明为什么。见 `VolunteerTrainingCopy.brokenQuestion`。
    var unanswerableQuestionIds: [Int64] {
        questions.filter { $0.visibleOptions.isEmpty }.map(\.id)
    }

    var hasUnanswerableQuestion: Bool { !unanswerableQuestionIds.isEmpty }

    /// 全部题目都选了才允许提交。
    var isEveryQuestionAnswered: Bool {
        !questions.isEmpty && questions.allSatisfy { selections[$0.id] != nil }
    }

    var canSubmit: Bool {
        isEveryQuestionAnswered && !hasUnanswerableQuestion && !isSubmitting
    }

    func load() async {
        guard let appState else { return }
        isLoading = true
        errorMessage = nil
        do {
            detail = try await appState.training.courseDetail(courseId: courseId)
            if enteredAt == nil { enteredAt = Date() }
        } catch {
            errorMessage = (error as? APIError)?.localizedMessage ?? "暂时没能读到课程内容。"
        }
        isLoading = false
    }

    /// 离开页面时把停留时长报上去。
    ///
    /// ⚠️ **失败只记不吵**：学习时长是合规记录，不是用户此刻在等的结果。
    /// 为它弹一个错误框会打断人，而重试一次的价值远低于打扰的代价。
    /// 但也**不能静默 `try?`** —— 那样后端一直收不到时长时没人会发现，
    /// 所以把它写进 `errorMessage` 之外的日志通道。
    func reportStudyTimeOnExit() async {
        guard let appState, let enteredAt else { return }
        let seconds = Int(Date().timeIntervalSince(enteredAt).rounded())
        self.enteredAt = nil
        // 0 秒不上报：一次「点进去立刻退出」不构成学习，也没必要打一次网络
        guard seconds > 0 else { return }
        do {
            try await appState.training.reportProgress(courseId: courseId, studiedSeconds: seconds)
        } catch {
            // 用 Logger 而不是静默 try? —— 后端一直收不到时长时得有地方能查到
            let course = self.courseId
            Self.logger.warning("上报培训学习时长失败（课程 \(course, privacy: .public)，\(seconds, privacy: .public) 秒）：\(error.localizedDescription, privacy: .public)")
        }
    }

    func submit() async -> TrainingQuizResult? {
        guard let appState, canSubmit else { return nil }
        isSubmitting = true
        errorMessage = nil
        let payload = TrainingQuizSubmitRequest(
            answers: questions.compactMap { question in
                guard let optionId = selections[question.id] else { return nil }
                return TrainingQuizSubmitRequest.Answer(questionId: question.id, optionId: optionId)
            }
        )
        defer { isSubmitting = false }
        do {
            let result = try await appState.training.submitQuiz(courseId: courseId, request: payload)
            lastResult = result
            // 交卷这一刻把在这门课上的停留时长一并结清，避免「答完就退出」丢掉这段时间
            await reportStudyTimeOnExit()
            enteredAt = Date()
            return result
        } catch {
            errorMessage = (error as? APIError)?.localizedMessage ?? "提交失败，请稍后重试。"
            return nil
        }
    }

    /// 重答：只清掉答错的那几题的选择，答对的保留。
    ///
    /// 🚩 清空全部会让用户把已经答对的题再选一遍 —— 在「全对才过」下这是纯粹的惩罚，
    /// 而且会让他把注意力从「哪里想错了」挪到「重新点一遍」。
    func prepareRetry() {
        guard let result = lastResult else { return }
        for wrong in result.visibleWrongQuestions {
            selections.removeValue(forKey: wrong.questionId)
        }
        lastResult = nil
    }
}

// MARK: - 课程详情视图

struct VolunteerTrainingCourseView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel: VolunteerTrainingCourseViewModel
    /// 通过之后通知列表页刷新（门槛横幅与状态都要跟着变）。
    private let onCompletionChanged: () -> Void

    init(courseId: Int64, onCompletionChanged: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: VolunteerTrainingCourseViewModel(courseId: courseId))
        self.onCompletionChanged = onCompletionChanged
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let detail = viewModel.detail {
                    contentSection(detail)
                    if viewModel.isQuizVisible {
                        quizSection
                    } else if !viewModel.questions.isEmpty {
                        PrimaryButton(VolunteerTrainingCopy.startQuiz) {
                            viewModel.isQuizVisible = true
                        }
                        .accessibilityIdentifier("volunteerTrainingStartQuizButton")
                    }
                } else if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("正在加载课程内容")
                } else {
                    IncentiveFailureSection(
                        message: viewModel.errorMessage ?? "暂时没能读到课程内容。",
                        retryTitle: VolunteerTrainingCopy.retry,
                        identifier: "volunteerTrainingCourseRetryButton"
                    ) {
                        Task { await viewModel.load() }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .readableContentColumn()
        }
        .background(AppColors.background)
        .navigationTitle(viewModel.detail?.displayTitle ?? VolunteerTrainingCopy.navigationTitle)
        .task {
            viewModel.configure(appState: appState)
            if viewModel.detail == nil { await viewModel.load() }
        }
        .onDisappear {
            // 学习时长在离开时结清。⚠️ 这里刻意不用 scenePhase ——
            // 进后台不代表离开这门课，回来还在同一页（记忆 `permission-alert-makes-scenephase-inactive`
            // 的同类教训：把生命周期事件当成「用户走了」会算错）。
            Task { await viewModel.reportStudyTimeOnExit() }
        }
    }

    // MARK: 正文

    private func contentSection(_ detail: TrainingCourseDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if detail.isRequired {
                Text("必修")
                    .font(AppFonts.caption().weight(.semibold))
                    .foregroundColor(AppColors.primary)
            }
            // Markdown 原生渲染：`LocalizedStringKey` 会解析 **粗体** / ## 标题 之外的
            // 基础语法。⚠️ 不用 WebView —— 那里 Dynamic Type 与 VoiceOver 都不按系统设置走。
            ForEach(Array(markdownBlocks(detail.content).enumerated()), id: \.offset) { _, block in
                Text(block.attributed)
                    .font(block.isHeading ? AppFonts.title() : AppFonts.body())
                    .foregroundColor(AppColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityIdentifier("volunteerTrainingCourseContent")
    }

    /// 把 Markdown 正文切成段，标题段单独放大。
    ///
    /// ponytail: 只处理「`##` 标题 + 段落」两种，不引第三方 Markdown 渲染器。
    /// 种子课程的正文就是这两种结构；真需要表格/图片时再换渲染器。
    private func markdownBlocks(_ content: String?) -> [(attributed: AttributedString, isHeading: Bool)] {
        let raw = content?.nilIfBlank ?? "（本课程暂无正文）"
        return raw
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { paragraph in
                let isHeading = paragraph.hasPrefix("#")
                let body = paragraph
                    .replacingOccurrences(of: "^#{1,6}\\s*", with: "", options: .regularExpression)
                // Markdown 解析失败时退回纯文本，绝不让一段正文整体消失
                let attributed = (try? AttributedString(
                    markdown: body,
                    options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
                )) ?? AttributedString(body)
                return (attributed, isHeading)
            }
    }

    // MARK: 答题

    @ViewBuilder
    private var quizSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Divider()

            Text(VolunteerTrainingCopy.quizIntro)
                .font(AppFonts.caption())
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
                questionBlock(index: index, question: question)
            }

            if let result = viewModel.lastResult {
                resultBlock(result)
            } else {
                submitButton
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.destructive)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("volunteerTrainingQuizError")
            }
        }
    }

    private func questionBlock(index: Int, question: TrainingQuestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("第 \(index + 1) 题　\(question.displayStem)")
                .font(AppFonts.body().weight(.semibold))
                .foregroundColor(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(question.visibleOptions) { option in
                let isSelected = viewModel.selections[question.id] == option.id
                Button {
                    viewModel.selections[question.id] = option.id
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        // 选中状态同时用图形和「已选择」文字表达，不只靠颜色
                        Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                            .foregroundColor(isSelected ? AppColors.primary : AppColors.textSecondary)
                            .accessibilityHidden(true)
                        Text(option.displayText)
                            .font(AppFonts.body())
                            .foregroundColor(AppColors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 6)
                }
                .accessibilityLabel(option.displayText)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                .accessibilityIdentifier("volunteerTrainingOption_\(question.id)_\(option.id)")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        // ⚠️ 用 .contain 而不是 .combine：里面的选项是要能被逐个点到的按钮，
        // .combine 会把它们吃成一个不可操作的整体（记忆
        // `accessibility-identifier-overwrites-children` 的同类陷阱）
        .accessibilityElement(children: .contain)
    }

    private var submitButton: some View {
        VStack(alignment: .leading, spacing: 6) {
            PrimaryButton(
                VolunteerTrainingCopy.submitQuiz,
                isLoading: viewModel.isSubmitting
            ) {
                Task {
                    if let result = await viewModel.submit(), result.isPassed {
                        onCompletionChanged()
                    }
                }
            }
            .disabled(!viewModel.canSubmit)
            .accessibilityIdentifier("volunteerTrainingSubmitButton")

            // 🚩 按钮禁用时必须说明原因。只把按钮变灰的话，用户不知道少答了题 ——
            //    这正是「失败只多一行字」那类缺陷的反面：原因和控件在同一处。
            if !viewModel.isEveryQuestionAnswered && !viewModel.hasUnanswerableQuestion {
                Text(VolunteerTrainingCopy.unansweredWarning)
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.textSecondary)
                    .accessibilityIdentifier("volunteerTrainingUnansweredHint")
            }
        }
    }

    private func resultBlock(_ result: TrainingQuizResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(result.summaryText)
                .font(AppFonts.body().weight(.semibold))
                .foregroundColor(result.isPassed ? AppColors.success : AppColors.destructive)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("volunteerTrainingQuizResult")

            // 🚩 逐题解释必须给。可无限重考 + 全对才过的组合下，
            //    只说「答错了」会让用户唯一的策略变成改选项猜到过。
            ForEach(result.visibleWrongQuestions) { wrong in
                VStack(alignment: .leading, spacing: 4) {
                    Text(wrong.stem?.nilIfBlank ?? "这道题答错了")
                        .font(AppFonts.caption().weight(.semibold))
                        .foregroundColor(AppColors.textPrimary)
                    // explanation 可能为 nil（题目没填）—— 那就整段不显示，不显示 "nil"
                    if let explanation = wrong.explanation?.nilIfBlank {
                        Text(explanation)
                            .font(AppFonts.caption())
                            .foregroundColor(AppColors.textSecondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !result.isPassed {
                PrimaryButton(VolunteerTrainingCopy.retryQuiz) {
                    viewModel.prepareRetry()
                }
                .accessibilityIdentifier("volunteerTrainingRetryQuizButton")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}
