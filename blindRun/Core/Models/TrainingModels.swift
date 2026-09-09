import Foundation

// MARK: - 课程列表

/// `GET /api/volunteer/training/courses` 的响应。
///
/// 🚩 **`requiredCompleted` 读后端的，客户端不许自己数 `courses`。**
/// 分母是「当前上线的必修课数」，会随课程上下线变化；自己算会在「后端新增一门必修课」
/// 的那一刻与派单侧分叉 —— 表现是培训页显示已完成、却收不到任何派单，
/// 而这个矛盾在客户端日志里没有任何痕迹。
///
/// ⚠️ 它与「能不能接单」**不是同一件事**：还要过资质审核、开着可服务开关、在线。
/// 接单资格的权威来源是 `GET /api/volunteer/dispatch-summary` 的 `notAvailableReasons`
/// （见 `VolunteerDispatchNotAvailableReason.trainingIncomplete`）。
struct TrainingCourseListResponse: Decodable, Sendable {
    let requiredCompleted: Bool?
    /// 培训证书编号；必修未全过时为 nil。
    let certificateNo: String?
    let certifiedAt: String?
    let courses: [TrainingCourseSummary]?

    init(
        requiredCompleted: Bool? = nil,
        certificateNo: String? = nil,
        certifiedAt: String? = nil,
        courses: [TrainingCourseSummary]? = nil
    ) {
        self.requiredCompleted = requiredCompleted
        self.certificateNo = certificateNo
        self.certifiedAt = certifiedAt
        self.courses = courses
    }

    /// 旧服务端 / 字段缺失时按「未完成」处理。
    ///
    /// ⚠️ 这个默认值方向是**故意保守**的：培训页多显示一句「还差必修课」最坏是让人白点一下，
    /// 而反过来（默认 true）会让真的没学完的人以为自己达标了，然后困惑为什么收不到单。
    var isRequiredCompleted: Bool { requiredCompleted ?? false }

    var visibleCourses: [TrainingCourseSummary] { courses ?? [] }

    /// 必修里还没通过的那些 —— 首页「还差几门」和排序都用它。
    var pendingRequiredCourses: [TrainingCourseSummary] {
        visibleCourses.filter { $0.isRequired && !$0.isCompleted }
    }
}

/// 列表里的一门课。**不含正文** —— 正文只在详情接口给。
struct TrainingCourseSummary: Decodable, Sendable, Identifiable {
    let id: Int64
    /// 稳定业务标识。⚠️ **开放枚举**（后端是 String），不要产成封闭 enum。
    let code: String?
    let title: String?
    let summary: String?
    let required: Bool?
    let estimatedMinutes: Int?
    let questionCount: Int?
    let rewardPoints: Int?
    /// `NOT_STARTED` / `IN_PROGRESS` / `COMPLETED`。
    ///
    /// 🚩 **是 `String?` 而不是封闭 enum**：后端这一列是 VARCHAR，将来加值不需要迁移，
    /// 所以客户端必须能安全吃下未知值。产成封闭 enum 会让整条响应解不出来
    /// —— 对盲人端就是一整页空白（AGENTS.md 的红线）。归一化走 `progressState`。
    let status: String?
    let studiedSeconds: Int?
    let attemptCount: Int?
    let completedAt: String?

    init(
        id: Int64,
        code: String? = nil,
        title: String? = nil,
        summary: String? = nil,
        required: Bool? = nil,
        estimatedMinutes: Int? = nil,
        questionCount: Int? = nil,
        rewardPoints: Int? = nil,
        status: String? = nil,
        studiedSeconds: Int? = nil,
        attemptCount: Int? = nil,
        completedAt: String? = nil
    ) {
        self.id = id
        self.code = code
        self.title = title
        self.summary = summary
        self.required = required
        self.estimatedMinutes = estimatedMinutes
        self.questionCount = questionCount
        self.rewardPoints = rewardPoints
        self.status = status
        self.studiedSeconds = studiedSeconds
        self.attemptCount = attemptCount
        self.completedAt = completedAt
    }

    var isRequired: Bool { required ?? false }
    var displayTitle: String { title?.nilIfBlank ?? "未命名课程" }
    var progressState: TrainingProgressState { TrainingProgressState(rawStatus: status) }
    var isCompleted: Bool { progressState == .completed }
    var rewardPointsValue: Int { rewardPoints ?? 0 }
    var attemptCountValue: Int { attemptCount ?? 0 }

    /// 列表行的副标题：把「必修/选修 · 时长 · 题数 · 奖励」压成一行。
    /// 每一段都在缺值时整段省略，不显示「0 分钟」这种更糟的占位。
    var metaLine: String {
        var parts: [String] = [isRequired ? "必修" : "选修"]
        if let estimatedMinutes, estimatedMinutes > 0 { parts.append("约 \(estimatedMinutes) 分钟") }
        if let questionCount, questionCount > 0 { parts.append("\(questionCount) 道题") }
        if rewardPointsValue > 0 { parts.append("完成得 \(rewardPointsValue) 积分") }
        return parts.joined(separator: " · ")
    }
}

/// 单门课的学习状态。
///
/// **未知值落 `.unknown` 而不是解码失败** —— 这是本仓库对枚举的一贯口径。
enum TrainingProgressState: Equatable, Sendable {
    case notStarted
    case inProgress
    case completed
    /// 后端加了新状态而客户端还没跟上。**不是错误**，按「进行中」那一档展示。
    case unknown

    init(rawStatus: String?) {
        switch rawStatus?.uppercased() {
        case "NOT_STARTED", .none: self = .notStarted
        case "IN_PROGRESS": self = .inProgress
        case "COMPLETED": self = .completed
        default: self = .unknown
        }
    }

    var displayText: String {
        switch self {
        case .notStarted: return "未开始"
        case .inProgress: return "进行中"
        case .completed: return "已完成"
        // 不写「未知状态」这种内部术语 —— 用户看不懂，也不需要懂
        case .unknown: return "进行中"
        }
    }
}

// MARK: - 课程详情

/// `GET /api/volunteer/training/courses/{courseId}` 的响应。
///
/// 🚨 **契约里没有正确答案，客户端也不该有任何地方期待它。** 判卷在后端。
struct TrainingCourseDetail: Decodable, Sendable {
    let id: Int64
    let code: String?
    let title: String?
    let summary: String?
    let required: Bool?
    let estimatedMinutes: Int?
    /// 正文，Markdown。**原生渲染，不进 WebView** —— WebView 里 Dynamic Type
    /// 与 VoiceOver 都不按系统设置走。
    let content: String?
    let status: String?
    let studiedSeconds: Int?
    let attemptCount: Int?
    let completedAt: String?
    let questions: [TrainingQuestion]?

    init(
        id: Int64,
        code: String? = nil,
        title: String? = nil,
        summary: String? = nil,
        required: Bool? = nil,
        estimatedMinutes: Int? = nil,
        content: String? = nil,
        status: String? = nil,
        studiedSeconds: Int? = nil,
        attemptCount: Int? = nil,
        completedAt: String? = nil,
        questions: [TrainingQuestion]? = nil
    ) {
        self.id = id
        self.code = code
        self.title = title
        self.summary = summary
        self.required = required
        self.estimatedMinutes = estimatedMinutes
        self.content = content
        self.status = status
        self.studiedSeconds = studiedSeconds
        self.attemptCount = attemptCount
        self.completedAt = completedAt
        self.questions = questions
    }

    var displayTitle: String { title?.nilIfBlank ?? "培训课程" }
    var visibleQuestions: [TrainingQuestion] { questions ?? [] }
    var progressState: TrainingProgressState { TrainingProgressState(rawStatus: status) }
    var isRequired: Bool { required ?? false }
}

struct TrainingQuestion: Decodable, Sendable, Identifiable {
    let id: Int64
    let stem: String?
    let options: [TrainingOption]?

    init(id: Int64, stem: String? = nil, options: [TrainingOption]? = nil) {
        self.id = id
        self.stem = stem
        self.options = options
    }

    var displayStem: String { stem?.nilIfBlank ?? "（题干缺失）" }

    /// 选项为空时这道题**答不了**。
    ///
    /// 🚩 调用方必须处理这种情况（`TrainingQuizViewModel.unanswerableQuestionIds`）——
    /// 静默渲染一道没有选项的题，用户点不下去也不知道为什么，
    /// 而「全对才过」意味着他永远交不了卷。
    var visibleOptions: [TrainingOption] { options ?? [] }
}

struct TrainingOption: Decodable, Sendable, Identifiable {
    /// 选项标识（`"A"` / `"B"` / …），交卷时回传这个值。
    let id: String
    let text: String?

    init(id: String, text: String? = nil) {
        self.id = id
        self.text = text
    }

    var displayText: String { text?.nilIfBlank ?? id }
}

// MARK: - 上报学习时长

/// 政策要求记录「学习时长」（中央社会工作部 2025-06 培训指引）。
///
/// ⚠️ **是本次增量，不是累计值**，后端做加法。传累计值会让「换一台设备继续学」
/// 把时长覆盖成更小的数。
struct TrainingProgressRequest: Encodable, Sendable {
    let studiedSeconds: Int
}

// MARK: - 交卷

struct TrainingQuizSubmitRequest: Encodable, Sendable {
    let answers: [Answer]

    struct Answer: Encodable, Sendable {
        let questionId: Int64
        let optionId: String
    }
}

/// 交卷结果。及格线是**全对**。
struct TrainingQuizResult: Decodable, Sendable {
    let passed: Bool?
    let correctCount: Int?
    let totalCount: Int?
    let attemptNo: Int?
    let wrongQuestions: [WrongQuestion]?
    /// 本次实际发放的积分。0 = 没发（必修课，或这门课之前已通过）。
    /// ⚠️ **不要用它判断是否通过** —— 必修通过时它也是 0。
    let awardedPoints: Int?
    let certificateNo: String?
    /// 交卷之后必修是否已全部通过。由 false 变 true 意味着派单门槛刚解开，
    /// 调用方据此刷新首页派单摘要。
    let requiredCompleted: Bool?

    init(
        passed: Bool? = nil,
        correctCount: Int? = nil,
        totalCount: Int? = nil,
        attemptNo: Int? = nil,
        wrongQuestions: [WrongQuestion]? = nil,
        awardedPoints: Int? = nil,
        certificateNo: String? = nil,
        requiredCompleted: Bool? = nil
    ) {
        self.passed = passed
        self.correctCount = correctCount
        self.totalCount = totalCount
        self.attemptNo = attemptNo
        self.wrongQuestions = wrongQuestions
        self.awardedPoints = awardedPoints
        self.certificateNo = certificateNo
        self.requiredCompleted = requiredCompleted
    }

    var isPassed: Bool { passed ?? false }
    var visibleWrongQuestions: [WrongQuestion] { wrongQuestions ?? [] }
    var awardedPointsValue: Int { awardedPoints ?? 0 }

    struct WrongQuestion: Decodable, Sendable, Identifiable {
        let questionId: Int64
        let stem: String?
        /// 可能为 nil（题目没填解释）。调用方要处理 nil 而不是显示 "nil"。
        let explanation: String?

        var id: Int64 { questionId }

        init(questionId: Int64, stem: String? = nil, explanation: String? = nil) {
            self.questionId = questionId
            self.stem = stem
            self.explanation = explanation
        }
    }

    /// 结果页要念/要显示的一句话。
    ///
    /// 🚩 未通过时**必须说清错了几题**，而不是只说「未通过」——
    /// 可无限重考 + 全对才过的组合下，用户需要知道差多少。
    var summaryText: String {
        let correct = correctCount ?? 0
        let total = totalCount ?? 0
        if isPassed {
            if awardedPointsValue > 0 {
                return "考核通过，答对 \(correct) 题，获得 \(awardedPointsValue) 积分。"
            }
            return "考核通过，\(total) 题全部答对。"
        }
        let wrongCount = max(0, total - correct)
        return "本次未通过。\(total) 题中答错 \(wrongCount) 题，可以修改后再次提交。"
    }
}
