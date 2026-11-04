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

    private static let logger = Logger(subsystem: "com.culiu-tech.blindrun", category: "training")

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
            errorMessage = (error as? APIError)?.localizedMessage ?? "课程内容加载失败。"
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

/// 一门课的正文页。答题弹整页（`VolunteerTrainingQuizView`），不再接在正文下面。
///
/// 2026-11-04 负责人定稿（`docs/ui/mockups/volunteer-training-20261104/`）：顶部「必修 · 约 N 分钟」小胶囊 +
/// 大标题 + 简介，正文放白卡，底部固定一颗通栏胶囊「开始答题」（负责人选 A 版）。
struct VolunteerTrainingCourseView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: VolunteerTrainingCourseViewModel
    /// 列表页带进来的「除这门以外还没学完的必修课」，只用于全对结果页那句「还差哪门」。
    private let remainingRequiredTitles: [String]
    /// 通过之后通知列表页刷新（进度卡与状态都要跟着变）。
    private let onCompletionChanged: () -> Void
    /// 全对页按「完成」后，答题页收起时顺带退回列表。
    @State private var leavesAfterQuiz = false

    init(
        courseId: Int64,
        remainingRequiredTitles: [String] = [],
        onCompletionChanged: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: VolunteerTrainingCourseViewModel(courseId: courseId))
        self.remainingRequiredTitles = remainingRequiredTitles
        self.onCompletionChanged = onCompletionChanged
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let detail = viewModel.detail {
                    header(detail)
                    contentSection(detail)
                } else if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("正在加载课程内容")
                } else {
                    IncentiveFailureSection(
                        message: viewModel.errorMessage ?? "课程内容加载失败。",
                        retryTitle: VolunteerTrainingCopy.retry,
                        identifier: "volunteerTrainingCourseRetryButton"
                    ) {
                        Task { await viewModel.load() }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .readableContentColumn()
        }
        .background(TrainingSurface.page.ignoresSafeArea())
        // 固定在底部：正文读到哪里都点得到。挂在这一页的 ScrollView 上，不挂 NavigationStack 外层。
        .safeAreaInset(edge: .bottom) {
            if viewModel.detail != nil && !viewModel.questions.isEmpty {
                TrainingBottomBar {
                    Button(VolunteerTrainingCopy.startQuiz) {
                        viewModel.isQuizVisible = true
                    }
                    .buttonStyle(TrainingCapsuleButtonStyle())
                    .accessibilityHint("打开课后答题")
                    .accessibilityIdentifier("volunteerTrainingStartQuizButton")
                }
            }
        }
        .navigationTitle(viewModel.detail?.displayTitle ?? VolunteerTrainingCopy.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .fullScreenCover(isPresented: $viewModel.isQuizVisible, onDismiss: {
            guard leavesAfterQuiz else { return }
            leavesAfterQuiz = false
            dismiss()
        }) {
            VolunteerTrainingQuizView(
                viewModel: viewModel,
                remainingRequiredTitles: remainingRequiredTitles,
                onPassed: { onCompletionChanged() },
                onFinish: {
                    leavesAfterQuiz = true
                    viewModel.isQuizVisible = false
                }
            )
        }
        .task {
            viewModel.configure(appState: appState)
            if viewModel.detail == nil { await viewModel.load() }
        }
        .onDisappear {
            // 学习时长在离开时结清。⚠️ 这里刻意不用 scenePhase ——
            // 进后台不代表离开这门课，回来还在同一页（记忆 `permission-alert-makes-scenephase-inactive`
            // 的同类教训：把生命周期事件当成「用户走了」会算错）。
            //
            // 弹出整页答题时这一页也会收到 onDisappear，那不是离开：答题也算在这门课上的时长，
            // 留到真正退回列表（或交卷）时一并结清。
            guard !viewModel.isQuizVisible else { return }
            Task { await viewModel.reportStudyTimeOnExit() }
        }
    }

    // MARK: 正文

    private func header(_ detail: TrainingCourseDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            let meta = [
                detail.isRequired ? VolunteerTrainingCopy.requiredSection : VolunteerTrainingCopy.electiveSection,
                detail.estimatedMinutes.flatMap { $0 > 0 ? "约 \($0) 分钟" : nil }
            ].compactMap { $0 }.joined(separator: " · ")
            Text(meta)
                .font(.footnote.weight(.semibold))
                .foregroundColor(AppColors.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color(uiColor: .systemGray5)))
            Text(detail.displayTitle)
                .font(.title.bold())
                .foregroundColor(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            if let summary = detail.summary?.nilIfBlank {
                Text(summary)
                    .font(.subheadline)
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 4)
    }

    private func contentSection(_ detail: TrainingCourseDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Markdown 原生渲染：`LocalizedStringKey` 会解析 **粗体** / ## 标题 之外的
            // 基础语法。⚠️ 不用 WebView —— 那里 Dynamic Type 与 VoiceOver 都不按系统设置走。
            ForEach(Array(markdownBlocks(detail.content).enumerated()), id: \.offset) { _, block in
                Text(block.attributed)
                    .font(block.isHeading ? .headline : AppFonts.body())
                    .foregroundColor(AppColors.textPrimary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, block.isHeading ? 4 : 0)
                    .accessibilityAddTraits(block.isHeading ? .isHeader : [])
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TrainingSurface.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
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
}

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
            guard hasResult else { return }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)
                focusesResultHeading = true
            }
        }
    }

    private var closeButton: some View {
        Button { dismiss() } label: { Image(systemName: "xmark") }
            .accessibilityLabel("关闭答题")
            .accessibilityHint("回到课程正文，已选的答案会保留")
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

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(AppFonts.body())
                            .foregroundColor(AppColors.destructive)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("volunteerTrainingQuizError")
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
    }

    private var submitBar: some View {
        TrainingBottomBar {
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

    // MARK: 结果

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
                    Button(VolunteerTrainingCopy.retryQuiz(wrongCount: max(wrongCount, 1))) {
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
        return "答对 \(result.correctCount ?? 0) 题，共 \(total) 题"
    }

    private func resultDetail(_ result: TrainingQuizResult) -> String {
        guard result.isPassed else {
            let wrongCount = max(result.visibleWrongQuestions.count, 1)
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
            }
        }
        .background(TrainingSurface.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("volunteerTrainingWrongQuestion_\(wrong.questionId)")
    }
}

// MARK: - 答题页小部件

/// 一个选项行：文字在左（多行时左对齐）、标记在右。
private struct TrainingOptionRow: View {
    enum Mark { case empty, selected, wrong }

    let text: String
    let mark: Mark
    @ScaledMetric(relativeTo: .body) private var markSide: CGFloat = 24

    var body: some View {
        HStack(spacing: 12) {
            Text(text)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textPrimary)
                // 按钮里的多行文字默认居中：旧版选项第二行错位就是这个（current/O-quiz-2.png）
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            markView
                .frame(width: markSide, height: markSide)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }

    /// 选中 = 实心圆 + 白对勾、答错 = 红底白叉：形状不同，不只靠颜色。
    @ViewBuilder
    private var markView: some View {
        switch mark {
        case .empty:
            Circle().strokeBorder(AppColors.textSecondary, lineWidth: 1.5)
        case .selected:
            Image(systemName: "checkmark")
                .font(.caption.weight(.bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Circle().fill(AppColors.primary))
        case .wrong:
            Image(systemName: "xmark")
                .font(.caption.weight(.bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Circle().fill(AppColors.destructive))
        }
    }
}

/// 贴底的按钮栏。不透明底色 + 固定 id：内容滚到它后面时，无障碍审计按几何放过被盖住的字
/// （记忆 `opaque-bottom-bar-fakes-contrast-failure`，id 已接进 `AccessibilityAuditTests.audit` 的列表）。
struct TrainingBottomBar<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 8) {
            content
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .readableContentColumn()
        .background(TrainingSurface.page.ignoresSafeArea(edges: .bottom))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("volunteerTrainingBottomBar")
    }
}

/// 通栏胶囊按钮（开始答题 / 提交答案 / 重答 / 完成）。负责人 2026-11-04 选 A 版。
///
/// 配色与字号同 `PrimaryButtonStyle`（白字压 `primary`：亮 6.53:1、暗 3.65:1，`title3.bold` 属大字门槛 3:1；
/// 不可用 = `textSecondary` 压 `systemGray5`），只把圆角矩形换成胶囊。高度不低于 64pt（交接书易错点 2）。
struct TrainingCapsuleButtonStyle: ButtonStyle {
    var isLoading = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let looksDisabled = !isEnabled && !isLoading
        let ink = looksDisabled ? AppColors.textSecondary : Color.white
        configuration.label
            .font(AppFonts.primaryButton())
            .foregroundColor(ink)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity)
            .frame(minHeight: AppTouchTarget.blindPrimary)
            .background(Capsule().fill(looksDisabled ? Color(uiColor: .systemGray5) : AppColors.primary))
            .contentShape(Capsule())
            // 换 `ButtonStyle` 会接管掉默认的按下反馈，不补这一行按下去屏幕上什么都不动。
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
