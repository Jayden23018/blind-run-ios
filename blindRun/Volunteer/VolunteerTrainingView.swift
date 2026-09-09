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
    static let blockedBannerHint = "完成下面标记为「必修」的课程后，就可以开始接单了。"

    static let allDoneBanner = "必修培训已全部完成。"
    static func certificateLine(_ no: String) -> String { "培训合格证编号 \(no)" }

    static let loadFailure = "暂时没能读到培训课程。"
    static let retry = "重新加载"
    static let emptyCourses = "当前没有可学习的课程，请稍后再来看看。"

    static let startLearning = "开始学习"
    static let continueLearning = "继续学习"
    static let review = "复习"
    static let startQuiz = "开始答题"
    static let submitQuiz = "提交答案"
    static let retryQuiz = "再答一次"
    static let backToCourse = "回到课程内容"

    /// 答题前的提示。**如实说明及格线与可重考**，不要含糊 ——
    /// 用户知道「错一题就要重来但可以无限重来」之后，行为和心态都不一样。
    static let quizIntro = "下面每道题都只有一个正确答案。全部答对才算通过，答错可以修改后再次提交，次数不限。"

    static let unansweredWarning = "还有题目没有作答，请全部选择后再提交。"

    /// 题目缺选项时的说明。
    /// 🚩 这条必须存在：静默渲染一道没有选项的题，用户点不下去也不知道为什么，
    /// 而「全对才过」意味着他永远交不了卷。
    static let brokenQuestion = "这道题的选项没能加载出来，请退出后重新进入课程。如果反复出现，请联系客服。"
}

// MARK: - 课程列表 ViewModel

/// 培训首页的 view model。
///
/// 并发只用 async/await：`.task` + `Task`，没有 `AnyCancellable`（AGENTS.md 硬约束）。
@MainActor
final class VolunteerTrainingViewModel: ObservableObject {
    @Published private(set) var response: TrainingCourseListResponse?
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoadedOnce = false
    @Published var errorMessage: String?

    private weak var appState: AppState?

    /// ⚠️ `appState` 是 `weak` —— 传临时对象等于传 nil（守卫规则 `weak-temporary`）。
    /// 调用方必须持有它。
    func configure(appState: AppState) {
        self.appState = appState
    }

    var courses: [TrainingCourseSummary] { response?.visibleCourses ?? [] }
    var requiredCompleted: Bool { response?.isRequiredCompleted ?? false }
    var certificateNo: String? { response?.certificateNo?.nilIfBlank }

    func load() async {
        guard let appState else { return }
        isLoading = true
        errorMessage = nil
        do {
            response = try await appState.training.courses()
            hasLoadedOnce = true
        } catch {
            // 不吞错误：失败时页面要给出可点的重试，而不是一个空列表。
            errorMessage = (error as? APIError)?.localizedMessage ?? VolunteerTrainingCopy.loadFailure
        }
        isLoading = false
    }
}

// MARK: - 培训首页（排法 C：任务清单）

/// 志愿者培训首页。
///
/// **排法 C**：一屏看完全部进度，「为什么不能接单」摆在最上面。
/// 选它的理由是本仓库的前科 —— 失败/阻断说明如果排在列表末尾，
/// 在最长列表 + 最大字号下根本不在第一屏，等于没有反馈
/// （记忆 `claimed-fallback-may-not-exist-in-release`）。
///
/// 触达高度：志愿者端**不受 64pt 线约束**（`guard.mjs` 的 `small-touch-target`
/// 显式排除 `/blindRun/Volunteer/`），但仍按系统 44pt 下限走，且每个控件都有
/// `accessibilityLabel`。
struct VolunteerTrainingView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = VolunteerTrainingViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if viewModel.hasLoadedOnce {
                    gateBanner
                    courseList
                } else if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("正在加载培训课程")
                } else {
                    IncentiveFailureSection(
                        message: viewModel.errorMessage ?? VolunteerTrainingCopy.loadFailure,
                        retryTitle: VolunteerTrainingCopy.retry,
                        identifier: "volunteerTrainingRetryButton"
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
        .navigationTitle(VolunteerTrainingCopy.navigationTitle)
        .task {
            viewModel.configure(appState: appState)
            // 只在首次进入时拉；从课程详情返回时由 onAppear 那条刷新（见 courseRow）
            if !viewModel.hasLoadedOnce { await viewModel.load() }
        }
    }

    /// 门槛横幅 —— 永远在第一屏，见类注释。
    @ViewBuilder
    private var gateBanner: some View {
        if viewModel.requiredCompleted {
            VStack(alignment: .leading, spacing: 6) {
                Label(VolunteerTrainingCopy.allDoneBanner, systemImage: "checkmark.seal")
                    .font(AppFonts.body().weight(.semibold))
                    .foregroundColor(AppColors.success)
                if let certificateNo = viewModel.certificateNo {
                    Text(VolunteerTrainingCopy.certificateLine(certificateNo))
                        .font(AppFonts.caption())
                        .foregroundColor(AppColors.textSecondary)
                        // 证书编号要能被逐字念清 —— 它会被口头转述、被抄下来
                        .accessibilityLabel(
                            "培训合格证编号，\(certificateNo.map { String($0) }.joined(separator: "、"))"
                        )
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("volunteerTrainingDoneBanner")
        } else {
            VStack(alignment: .leading, spacing: 6) {
                // 图标只是装饰，对读屏隐藏；语义全在文字里（不靠颜色/图标传达状态）
                Label {
                    Text(VolunteerTrainingCopy.blockedBanner)
                        .font(AppFonts.body().weight(.semibold))
                        .foregroundColor(AppColors.textPrimary)
                } icon: {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(AppColors.warning)
                        .accessibilityHidden(true)
                }
                Text(VolunteerTrainingCopy.blockedBannerHint)
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.textSecondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("volunteerTrainingBlockedBanner")
        }
    }

    @ViewBuilder
    private var courseList: some View {
        if viewModel.courses.isEmpty {
            Text(VolunteerTrainingCopy.emptyCourses)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textSecondary)
                .accessibilityIdentifier("volunteerTrainingEmpty")
        } else {
            VStack(spacing: 0) {
                ForEach(viewModel.courses) { course in
                    courseRow(course)
                    if course.id != viewModel.courses.last?.id {
                        Divider()
                    }
                }
            }
            .background(AppColors.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func courseRow(_ course: TrainingCourseSummary) -> some View {
        NavigationLink {
            VolunteerTrainingCourseView(courseId: course.id) {
                // 从详情返回后刷新：可能刚刚通过了一门课，门槛横幅与状态都要跟着变
                Task { await viewModel.load() }
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: course.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(course.isCompleted ? AppColors.success : AppColors.textSecondary)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(course.displayTitle)
                        .font(AppFonts.body().weight(.semibold))
                        .foregroundColor(AppColors.textPrimary)
                    Text(course.metaLine)
                        .font(AppFonts.caption())
                        .foregroundColor(AppColors.textSecondary)
                    // 状态用文字给，不只靠上面那个图标的颜色
                    Text(statusLine(course))
                        .font(AppFonts.caption())
                        .foregroundColor(course.isCompleted ? AppColors.success : AppColors.primary)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // 整行合成一个可点元素，label 把「标题 + 必修/选修 + 状态」一次念全
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(course.displayTitle)，\(course.isRequired ? "必修" : "选修")，\(statusLine(course))")
        .accessibilityHint("打开课程内容与考核")
        .accessibilityIdentifier("volunteerTrainingCourseRow_\(course.id)")
    }

    /// 一行说清「学到哪了」。
    ///
    /// 学习时长只在 > 0 时出现 —— 「已学 0 分钟」比不显示更糟。
    private func statusLine(_ course: TrainingCourseSummary) -> String {
        var parts: [String] = [course.progressState.displayText]
        let minutes = (course.studiedSeconds ?? 0) / 60
        if minutes > 0 { parts.append("已学 \(minutes) 分钟") }
        if course.attemptCountValue > 0 && !course.isCompleted {
            parts.append("已答 \(course.attemptCountValue) 次")
        }
        return parts.joined(separator: " · ")
    }
}
