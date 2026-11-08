// `import Combine` 只为 `@Published` / `ObservableObject` 的合成 —— 
// 本文件**不订阅任何 publisher**，也没有 `AnyCancellable`。
// AGENTS.md 的并发硬约束是「同一条数据流不许既订阅 Combine 又 await」，
// 这里的数据流全走 async/await。
import Combine
import SwiftUI

// MARK: - 文案

/// 培训模块的全部用户可见文案，集中一处。
///
/// 🚩 **不要在这里写「预计 X 个工作日」之类的承诺**：后端没有任何 SLA 字段，
/// 编一个出来就是对用户撒谎（同 `PrivacyConsent` 那条不编 SLA 的口径）。
enum VolunteerTrainingCopy {
    static let navigationTitle = "陪跑培训"

    /// 未完成必修时首屏最上方那条。
    ///
    /// 🚩 **必须说清因果**：「没学完 → 接不到单」。只说「请完成培训」的话，
    /// 志愿者不会知道这是他收不到派单的原因，而那个状态在别处没有任何解释。
    static let blockedBanner = "必修培训还没完成，暂时无法接单。"

    static let allDoneBanner = "必修培训已全部完成。"
    static func certificateLine(_ no: String) -> String { "培训合格证编号 \(no)" }

    static let loadFailure = "培训课程加载失败。"
    static let retry = "重新加载"
    static let emptyCourses = "暂无课程。"

    static let startLearning = "开始学习"
    static let continueLearning = "继续学习"
    static let review = "复习"
    static let startQuiz = "开始答题"
    static let submitQuiz = "提交答案"
    static let finishQuiz = "完成"
    /// 结果页唯一的按钮。2026-11-04 负责人定稿：结果页不再放「回到课程正文」（原话「很突兀，看着很丑」），
    /// 想回正文点左上 ✕。
    static func retryQuiz(wrongCount: Int) -> String { "重答这 \(wrongCount) 题" }
    static let retryAll = "重新作答"

    // 列表页（2026-11-04 定稿 `docs/ui/mockups/volunteer-training-20261104/`）
    static let requiredSection = "必修"
    static let electiveSection = "选修"
    /// 选修组下的灰字。后半句是合规口径：积分 ≠ 志愿服务时长（中央网信办 2026-06-19 通知）。
    static let electiveFooter = "选修课不影响接单。积分和志愿服务时长是两回事。"
    static func requiredProgress(done: Int, total: Int) -> String { "\(done) / \(total) 门" }
    /// 进度卡的说明。🚩 同 `blockedBanner`：要说清「没学完 → 接不到单」。
    /// 写法同结果页（`VolunteerTrainingQuizView`）。不用「」括课名：被压窄的「」，落在行尾，
    /// 真机审计判 `Text clipped`，而字是完整的（#698，默认字号与 AX5 都报）。
    static func remainingRequired(_ titles: [String]) -> String {
        "还差 \(titles.count) 门必修：\(titles.joined(separator: "、"))。学完才能接单。"
    }
    static let pillCompleted = "已完成"
    static let pillToLearn = "去学习"
    static func pillReward(_ points: Int) -> String { "+\(points) 积分" }
    static func courseMeta(minutes: Int?, questions: Int?) -> String {
        var parts: [String] = []
        if let minutes, minutes > 0 { parts.append("约 \(minutes) 分钟") }
        if let questions, questions > 0 { parts.append("\(questions) 道题") }
        return parts.joined(separator: " · ")
    }

    /// 答题前的提示。**如实说明及格线与可重考**，不要含糊 ——
    /// 用户知道「错一题就要重来但可以无限重来」之后，行为和心态都不一样。
    static let quizIntro = "下面每道题都只有一个正确答案。全部答对才算通过，答错可以修改后再次提交，次数不限。"

    /// 题目缺选项时的说明。
    /// 🚩 这条必须存在：静默渲染一道没有选项的题，用户点不下去也不知道为什么，
    /// 而「全对才过」意味着他永远交不了卷。
    static let brokenQuestion = "题目选项加载失败，请退出后重新进入课程。如果反复出现，请联系客服。"
}

// MARK: - 课程列表 ViewModel

/// 培训首页的 view model。
///
/// 并发只用 async/await：`.task` + `Task`，没有 `AnyCancellable`（AGENTS.md 硬约束）。
@MainActor
final class VolunteerTrainingViewModel: ObservableObject {
    /// 课程列表的远端状态（#866）。失败视图由 `RemoteContent` 画，会念出来。
    @Published private(set) var state: AsyncLoadState<TrainingCourseListResponse> = .idle

    private weak var appState: AppState?

    /// ⚠️ `appState` 是 `weak` —— 传临时对象等于传 nil（守卫规则 `weak-temporary`）。
    /// 调用方必须持有它。
    func configure(appState: AppState) {
        self.appState = appState
    }

    var response: TrainingCourseListResponse? { state.value }
    var hasLoadedOnce: Bool { state.value != nil }
    var courses: [TrainingCourseSummary] { response?.visibleCourses ?? [] }
    var requiredCompleted: Bool { response?.isRequiredCompleted ?? false }
    var certificateNo: String? { response?.certificateNo?.nilIfBlank }

    /// 首次进入、点重试、从课程详情返回时都走这里。
    ///
    /// 页面规则：已经读到过列表时，刷新不切回加载占位，刷新失败也保留已显示的列表（状态停在 `.loaded`）。
    func load() async {
        guard let appState else { return }
        if state.value == nil { state = .loading(requestID: UUID()) }
        do {
            state = .loaded(try await appState.training.courses())
        } catch {
            guard state.value == nil else { return }
            // 不吞错误：失败时页面要给出可点的重试，而不是一个空列表。
            state = .failed(message: (error as? APIError)?.localizedMessage ?? VolunteerTrainingCopy.loadFailure)
        }
    }
}

// MARK: - 培训首页（2026-11-04 定稿：进度卡 + 必修 / 选修两组）

/// 志愿者培训首页。
///
/// **2026-11-04 负责人定稿**（照健康 App 同功能页的版式，`docs/ui/mockups/volunteer-training-20261104/`）：
/// 顶部一张进度卡（圆环 +「1 / 2 门」+ 还差哪门），下面「必修」「选修」两组，
/// 每行右侧的状态胶囊说下一步该做什么。
///
/// 进度卡仍然**永远在第一屏**、说清「没学完 → 接不到单」—— 排法 C 留下的理由没变：
/// 失败/阻断说明排在列表末尾时，最长列表 + 最大字号下根本不在第一屏
/// （记忆 `claimed-fallback-may-not-exist-in-release`）。
///
/// 触达高度：志愿者端**不受 64pt 线约束**（`guard.mjs` 的 `small-touch-target`
/// 显式排除 `/blindRun/Volunteer/`），但仍按系统 44pt 下限走，且每个控件都有
/// `accessibilityLabel`。
struct VolunteerTrainingView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = VolunteerTrainingViewModel()
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                RemoteContent(
                    viewModel.state,
                    loadingLabel: "正在加载培训课程",
                    failureIdentifier: "volunteerTrainingRetryButton",
                    retryTitle: VolunteerTrainingCopy.retry,
                    retry: { Task { await viewModel.load() } }
                ) { _ in
                    progressCard
                    courseGroups
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .readableContentColumn()
        }
        .background(TrainingSurface.page.ignoresSafeArea())
        .navigationTitle(VolunteerTrainingCopy.navigationTitle)
        .navigationBarTitleDisplayMode(.large)
        // 二级页藏标签栏：悬浮胶囊会盖掉最后一行（记忆 `tab-bar-clips-the-last-line-of-secondary-pages`），
        // 加 padding 救不回来。返回箭头一直在，不缺出口。
        .toolbar(.hidden, for: .tabBar)
        .task {
            viewModel.configure(appState: appState)
            // 只在首次进入时拉；从课程详情返回时由 courseRow 的回调刷新
            if !viewModel.hasLoadedOnce { await viewModel.load() }
        }
    }

    // MARK: 进度卡

    private var requiredCourses: [TrainingCourseSummary] { viewModel.courses.filter(\.isRequired) }
    private var electiveCourses: [TrainingCourseSummary] { viewModel.courses.filter { !$0.isRequired } }

    /// 门槛卡 —— 永远在第一屏，见类注释。
    ///
    /// 🚩 「学完没有」**读后端的 `requiredCompleted`**，不拿下面数出来的门数判（`TrainingCourseListResponse` 的注释）。
    /// 门数只用来画圆环和「1 / 2 门」这一行。
    @ViewBuilder
    private var progressCard: some View {
        let total = requiredCourses.count
        let done = requiredCourses.filter(\.isCompleted).count
        let isDone = viewModel.requiredCompleted
        HStack(alignment: .center, spacing: 16) {
            TrainingProgressRing(fraction: isDone ? 1 : (total > 0 ? Double(done) / Double(total) : 0))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(VolunteerTrainingCopy.requiredSection)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(AppColors.textSecondary)
                if total > 0 {
                    Text(VolunteerTrainingCopy.requiredProgress(done: done, total: total))
                        .font(.title.bold())
                        .foregroundColor(AppColors.textPrimary)
                }
                Text(progressLine(isDone: isDone))
                    .font(.subheadline)
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if isDone, let certificateNo = viewModel.certificateNo {
                    Text(VolunteerTrainingCopy.certificateLine(certificateNo))
                        .font(.footnote)
                        .foregroundColor(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background(TrainingSurface.card)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        // 整张卡读成一句：门数 + 原因（+ 证书编号逐字念）。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(progressAccessibilityLabel(isDone: isDone, done: done, total: total))
        .accessibilityIdentifier(isDone ? "volunteerTrainingDoneBanner" : "volunteerTrainingBlockedBanner")
    }

    private func progressLine(isDone: Bool) -> String {
        if isDone { return VolunteerTrainingCopy.allDoneBanner }
        let pending = viewModel.response?.pendingRequiredCourses.map(\.displayTitle) ?? []
        // 后端说没学完、而列表里的必修都已完成（课程刚上下线的那一刻）：退回通用说法，不编课名
        return pending.isEmpty ? VolunteerTrainingCopy.blockedBanner : VolunteerTrainingCopy.remainingRequired(pending)
    }

    private func progressAccessibilityLabel(isDone: Bool, done: Int, total: Int) -> String {
        var parts = ["必修培训"]
        if total > 0 { parts.append("已完成 \(done) 门，共 \(total) 门") }
        parts.append(progressLine(isDone: isDone))
        if isDone, let certificateNo = viewModel.certificateNo {
            // 证书编号要能被逐字念清 —— 它会被口头转述、被抄下来
            parts.append("培训合格证编号，\(certificateNo.map { String($0) }.joined(separator: "、"))")
        }
        return parts.joined(separator: "，")
    }

    // MARK: 课程分组

    @ViewBuilder
    private var courseGroups: some View {
        if viewModel.courses.isEmpty {
            Text(VolunteerTrainingCopy.emptyCourses)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textSecondary)
                .accessibilityIdentifier("volunteerTrainingEmpty")
        } else {
            if !requiredCourses.isEmpty {
                courseGroup(title: VolunteerTrainingCopy.requiredSection, courses: requiredCourses, footer: nil)
            }
            if !electiveCourses.isEmpty {
                courseGroup(
                    title: VolunteerTrainingCopy.electiveSection,
                    courses: electiveCourses,
                    footer: VolunteerTrainingCopy.electiveFooter
                )
            }
        }
    }

    private func courseGroup(title: String, courses: [TrainingCourseSummary], footer: String?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(AppColors.textSecondary)
                .padding(.horizontal, 16)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                ForEach(courses) { course in
                    courseRow(course)
                    if course.id != courses.last?.id {
                        Divider().padding(.leading, 60)
                    }
                }
            }
            .background(TrainingSurface.card)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            if let footer {
                Text(footer)
                    .font(.footnote)
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
            }
        }
    }

    private func courseRow(_ course: TrainingCourseSummary) -> some View {
        NavigationLink {
            VolunteerTrainingCourseView(
                courseId: course.id,
                remainingRequiredTitles: (viewModel.response?.pendingRequiredCourses ?? [])
                    .filter { $0.id != course.id }
                    .map(\.displayTitle)
            ) {
                // 从详情返回后刷新：可能刚刚通过了一门课，进度卡与状态胶囊都要跟着变
                Task { await viewModel.load() }
            }
        } label: {
            HStack(spacing: 12) {
                TrainingCourseIcon(course: course)
                    .accessibilityHidden(true)
                // 辅助功能字号下胶囊换到标题下面：并排时标题列会被挤成一两个字一行
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                    : AnyLayout(HStackLayout(spacing: 12))
                layout {
                VStack(alignment: .leading, spacing: 2) {
                    Text(course.displayTitle)
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.textPrimary)
                        .multilineTextAlignment(.leading)
                    let meta = VolunteerTrainingCopy.courseMeta(minutes: course.estimatedMinutes, questions: course.questionCount)
                    if !meta.isEmpty {
                        Text(meta)
                            .font(.footnote)
                            .foregroundColor(AppColors.textSecondary)
                    }
                }
                // 唯一的弹性子视图：标题列吃掉剩余宽度，胶囊和箭头贴右（记忆 `flexible-spacer-steals-half-the-row`）
                .frame(maxWidth: .infinity, alignment: .leading)
                TrainingStatusPill(status: pillStatus(course))
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(AppColors.textSecondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // 整行合成一个可点元素，label 把「标题 + 必修/选修 + 状态」一次念全
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(course.displayTitle)，\(course.isRequired ? "必修" : "选修")，\(statusLine(course))")
        .accessibilityHint("打开课程内容与考核")
        .accessibilityIdentifier("volunteerTrainingCourseRow_\(course.id)")
    }

    private func pillStatus(_ course: TrainingCourseSummary) -> TrainingStatusPill.Status {
        if course.isCompleted { return .completed }
        if !course.isRequired && course.rewardPointsValue > 0 { return .reward(course.rewardPointsValue) }
        return .toLearn
    }

    /// 读屏念的「学到哪了」。界面上只给胶囊；学习时长与答题次数只进读屏（定稿行里放不下第三行）。
    ///
    /// 学习时长只在 > 0 时出现 —— 「已学 0 分钟」比不说更糟。
    private func statusLine(_ course: TrainingCourseSummary) -> String {
        var parts: [String] = [pillStatus(course).text]
        let meta = VolunteerTrainingCopy.courseMeta(minutes: course.estimatedMinutes, questions: course.questionCount)
        if !meta.isEmpty { parts.append(meta) }
        let minutes = (course.studiedSeconds ?? 0) / 60
        if minutes > 0 { parts.append("已学 \(minutes) 分钟") }
        if course.attemptCountValue > 0 && !course.isCompleted {
            parts.append("已答 \(course.attemptCountValue) 次")
        }
        return parts.joined(separator: "，")
    }
}
