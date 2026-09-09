import Foundation

// MARK: - 志愿者线上培训（后端迁移 0043）

/// Mock 侧的一门课 + 它的题目 + 正确答案。
///
/// 🚨 **正确答案只存在这里，判卷也只在这里** —— 与后端同构。
/// `MockAPIClient` 组装 `TrainingCourseDetail` 时必须剥掉 `correctOption`，
/// 否则 Mock 的行为与真实后端不一致，而 UI 是照着 Mock 调的。
struct MockTrainingCourse: Sendable {
    let id: Int64
    let code: String
    let title: String
    let summary: String
    let content: String
    let isRequired: Bool
    let estimatedMinutes: Int
    let rewardPoints: Int
    let questions: [MockTrainingQuestion]
}

struct MockTrainingQuestion: Sendable {
    let id: Int64
    let stem: String
    let options: [(id: String, text: String)]
    let correctOption: String
    let explanation: String
}

/// 一个人在一门课上的进度（Mock 侧）。
struct MockTrainingProgress: Sendable {
    var studiedSeconds: Int = 0
    var attemptCount: Int = 0
    var completedAt: Date?
    var certificateNo: String?

    var isCompleted: Bool { completedAt != nil }
}

extension MockAPIClient {

    /// Mock 课程表。
    ///
    /// ⚠️ **内容与后端迁移 `0043` 的种子数据同源但不必逐字相同** —— Mock 的职责是
    /// 「像后端那样表现」，不是复刻文案。**结构必须一致**：两门必修 + 一门选修，
    /// 选修有奖励分，必修恒 0。
    ///
    /// 🚩 必修 2 刻意给了 **4 道题**：只有多于 4 道题时「错 1 题」才不到 80%，
    /// 「全对才过」这条规则在 Mock 上才演得出与百分比及格线的区别。
    static var mockTrainingCourses: [MockTrainingCourse] {
        [
            MockTrainingCourse(
                id: 4001,
                code: "GUIDE_BASICS",
                title: "陪跑基础",
                summary: "牵引绳怎么用、路面怎么提醒",
                content: """
                ## 牵引绳：方向靠手上的动作

                要往左，把绳往左轻拉一下；要往右，用手臂轻顶一下他的手臂。
                动作要小而清楚 —— 拉扯幅度大反而会让人失去平衡。

                **绳突然绷紧，说明步调不一致了。** 要调整的是你的节奏，不是让他跟上你。

                ## 路面：先说话，再动作

                遇到石子、减速带、破损路面，先用一句话说清楚，给他调整步幅的时间。
                """,
                isRequired: true,
                estimatedMinutes: 8,
                rewardPoints: 0,
                questions: [
                    MockTrainingQuestion(
                        id: 41_001,
                        stem: "陪跑中牵引绳突然绷得很紧，说明什么？",
                        options: [
                            ("A", "跑者体力下降了，鼓励他跟上你的节奏"),
                            ("B", "你们步调不一致了，把节奏调整到他那一侧"),
                            ("C", "绳太短，边跑边放长一些"),
                            ("D", "正常现象，不用管")
                        ],
                        correctOption: "B",
                        explanation: "绷紧的绳会同时影响两个人的重心。要调整的是你的节奏。"
                    ),
                    MockTrainingQuestion(
                        id: 41_002,
                        stem: "前方路面有一段碎石，你首先应该做什么？",
                        options: [
                            ("A", "先用一句话说清前面路况"),
                            ("B", "用绳把他往旁边带，绕开这一段"),
                            ("C", "加快通过，减少在这段路上的时间"),
                            ("D", "什么都不说，靠绳的动作提示就够了")
                        ],
                        correctOption: "A",
                        explanation: "他看不到你规避的路线。先给信息再给动作。"
                    )
                ]
            ),
            MockTrainingCourse(
                id: 4002,
                code: "EMERGENCY_HANDLING",
                title: "突发情况处置",
                summary: "人流、身体不适、走散该怎么反应",
                content: """
                ## 总原则：先停，再判断

                陪跑里绝大多数意外的正确第一反应都是**停下来**，而不是加速通过或绕开。

                ## 人流：等，不挤

                前方有人流对冲时，停下来，等人流走完再通行。人流里你护不住他，
                而他连「有人朝我过来」这个信息都没有。
                """,
                isRequired: true,
                estimatedMinutes: 10,
                rewardPoints: 0,
                questions: [
                    MockTrainingQuestion(
                        id: 42_001,
                        stem: "前方是一处无障碍设施，此刻有一股人流正对着你们过来。你应该？",
                        options: [
                            ("A", "加快速度，趁人流散开之前先过去"),
                            ("B", "停下来，等人流走完再通行"),
                            ("C", "松开牵引绳，让他跟着你的脚步声走"),
                            ("D", "拉着他从人流侧面挤过去")
                        ],
                        correctOption: "B",
                        explanation: "人流里你护不住他，而他连「有人朝我过来」这个信息都没有。"
                    ),
                    MockTrainingQuestion(
                        id: 42_002,
                        stem: "跑者说「我有点不舒服，想停一下」，第一反应应该是？",
                        options: [
                            ("A", "立刻停下，停稳之后再问情况"),
                            ("B", "先问哪里不舒服，判断之后再决定停不停"),
                            ("C", "鼓励他再坚持到前面路口"),
                            ("D", "放慢速度改成走，先不完全停下")
                        ],
                        correctOption: "A",
                        explanation: "他说停就停，不要先问原因、不要鼓励再坚持。"
                    ),
                    MockTrainingQuestion(
                        id: 42_003,
                        stem: "通过一段只能单列走的窄路，正确做法是？",
                        options: [
                            ("A", "直接拉紧绳把他带到你身后"),
                            ("B", "提前说明，让他靠近并扶住你的手臂，绳先放松"),
                            ("C", "松开绳，让他自己贴着墙走"),
                            ("D", "绳不变，加快通过")
                        ],
                        correctOption: "B",
                        explanation: "切换引导方式要先说一句话，不打招呼就去拉他会破坏他的平衡。"
                    ),
                    MockTrainingQuestion(
                        id: 42_004,
                        stem: "在人多的路段走散了，一时看不到他。你应该？",
                        options: [
                            ("A", "原地停留并出声呼叫他"),
                            ("B", "立刻沿原路往回找"),
                            ("C", "先到前方开阔处等"),
                            ("D", "先打电话给客服，等指示再行动")
                        ],
                        correctOption: "A",
                        explanation: "你一移动，他就失去了唯一的声音参照。先站住、先出声。"
                    )
                ]
            ),
            MockTrainingCourse(
                id: 4003,
                code: "PRE_RUN_COMMUNICATION",
                title: "赛前沟通与配合",
                summary: "第一次搭档要聊哪些、口令怎么统一（选修）",
                content: """
                ## 第一次搭档，先把口令说定

                至少约定四个：向左、向右、减速、立刻停。
                **重点是每次都用同一个词** —— 口令的价值来自固定。
                """,
                isRequired: false,
                estimatedMinutes: 6,
                rewardPoints: 20,
                questions: [
                    MockTrainingQuestion(
                        id: 43_001,
                        stem: "关于需要他贴紧你的口令，最重要的是什么？",
                        options: [
                            ("A", "每次都用同一个词，一说就懂"),
                            ("B", "用词尽量正式，避免歧义"),
                            ("C", "每次都完整说明要做什么动作"),
                            ("D", "用英文口令，更简短")
                        ],
                        correctOption: "A",
                        explanation: "换着说法讲同一件事，等于每次都要重新理解一遍。"
                    )
                ]
            )
        ]
    }

    /// 当前上线的必修课门数 —— 门槛的分母，与后端同口径。
    private var mockRequiredCourseCount: Int {
        Self.mockTrainingCourses.filter(\.isRequired).count
    }

    /// 必修是否全过。
    ///
    /// 🚩 **Mock 必须自己算这个**，不能恒返 true：
    /// `handleGetVolunteerDispatchSummary` 要靠它产出 `TRAINING_INCOMPLETE`，
    /// 而那条原因是「志愿者上线了却收不到派单」在界面上唯一的解释。
    /// Mock 少造一个真实存在的原因，那条分支在开发期就永远跑不到 ——
    /// `NOT_VERIFIED` 的解码 bug 当年就是这么活到真机联调的。
    var mockTrainingRequiredCompleted: Bool {
        let passed = Self.mockTrainingCourses
            .filter { $0.isRequired && (trainingProgress[$0.id]?.isCompleted ?? false) }
            .count
        return passed >= mockRequiredCourseCount
    }

    /// 路径里的 courseId。
    ///
    /// `suffix` 为 nil 时只匹配 `/courses/{id}`（详情）；给了就匹配 `/courses/{id}/{suffix}`。
    /// ⚠️ 必须区分开：不区分的话 `/courses/1/quiz` 会先被详情那条路由吃掉。
    func extractTrainingCourseId(from path: String, suffix: String?) -> Int64? {
        let prefix = "/api/volunteer/training/courses/"
        guard path.hasPrefix(prefix) else { return nil }
        let rest = String(path.dropFirst(prefix.count))
        let parts = rest.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        if let suffix {
            guard parts.count == 2, parts[1] == suffix else { return nil }
            return Int64(parts[0])
        }
        guard parts.count == 1 else { return nil }
        return Int64(parts[0])
    }

    func handleGetTrainingCourses() -> TrainingCourseListResponse {
        let items = Self.mockTrainingCourses.map { course -> TrainingCourseSummary in
            let progress = trainingProgress[course.id]
            return TrainingCourseSummary(
                id: course.id,
                code: course.code,
                title: course.title,
                summary: course.summary,
                required: course.isRequired,
                estimatedMinutes: course.estimatedMinutes,
                questionCount: course.questions.count,
                rewardPoints: course.rewardPoints,
                status: mockTrainingStatus(progress),
                studiedSeconds: progress?.studiedSeconds ?? 0,
                attemptCount: progress?.attemptCount ?? 0,
                completedAt: progress?.completedAt.map(Self.mockIso)
            )
        }
        // 证书取最后通过的那门必修课，与后端 latestCompletedRequired 同口径
        let requiredCompleted = mockTrainingRequiredCompleted
        let certificateSource: MockTrainingProgress? = requiredCompleted
            ? Self.mockTrainingCourses
                .filter(\.isRequired)
                .compactMap { trainingProgress[$0.id] }
                .filter { $0.completedAt != nil }
                .max(by: { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) })
            : nil
        return TrainingCourseListResponse(
            requiredCompleted: requiredCompleted,
            certificateNo: certificateSource?.certificateNo,
            certifiedAt: certificateSource?.completedAt.map(Self.mockIso),
            courses: items
        )
    }

    func handleGetTrainingCourseDetail(courseId: Int64) throws -> TrainingCourseDetail {
        guard let course = Self.mockTrainingCourses.first(where: { $0.id == courseId }) else {
            throw APIError.serverError(ErrorResponse(code: "RESOURCE_NOT_FOUND", message: "培训课程不存在"))
        }
        let progress = trainingProgress[courseId]
        return TrainingCourseDetail(
            id: course.id,
            code: course.code,
            title: course.title,
            summary: course.summary,
            required: course.isRequired,
            estimatedMinutes: course.estimatedMinutes,
            content: course.content,
            status: mockTrainingStatus(progress),
            studiedSeconds: progress?.studiedSeconds ?? 0,
            attemptCount: progress?.attemptCount ?? 0,
            completedAt: progress?.completedAt.map(Self.mockIso),
            // 🚨 只带题干和选项，**不带 correctOption** —— 与后端契约逐字一致。
            //    带上去 Mock 就比真实后端多给了答案，而 UI 是照着 Mock 调的。
            questions: course.questions.map { question in
                TrainingQuestion(
                    id: question.id,
                    stem: question.stem,
                    options: question.options.map { TrainingOption(id: $0.id, text: $0.text) }
                )
            }
        )
    }

    func handleReportTrainingProgress(
        courseId: Int64,
        body: (any Encodable & Sendable)?
    ) throws -> EmptyResponse {
        guard Self.mockTrainingCourses.contains(where: { $0.id == courseId }) else {
            throw APIError.serverError(ErrorResponse(code: "RESOURCE_NOT_FOUND", message: "培训课程不存在"))
        }
        guard let request = body as? TrainingProgressRequest else {
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_ERROR", message: "缺少 studiedSeconds"))
        }
        // 与后端同样的上限校验：超限 400 而不是静默截断
        guard request.studiedSeconds >= 0, request.studiedSeconds <= 14400 else {
            throw APIError.serverError(ErrorResponse(
                code: "VALIDATION_ERROR",
                message: "单次上报的学习时长不能超过 4 小时"
            ))
        }
        var progress = trainingProgress[courseId] ?? MockTrainingProgress()
        // 增量累加，已通过的课照样累加（复习也是学习）—— 与后端一致
        progress.studiedSeconds += request.studiedSeconds
        trainingProgress[courseId] = progress
        return EmptyResponse()
    }

    func handleSubmitTrainingQuiz(
        courseId: Int64,
        body: (any Encodable & Sendable)?
    ) throws -> TrainingQuizResult {
        guard let course = Self.mockTrainingCourses.first(where: { $0.id == courseId }) else {
            throw APIError.serverError(ErrorResponse(code: "RESOURCE_NOT_FOUND", message: "培训课程不存在"))
        }
        guard let request = body as? TrainingQuizSubmitRequest else {
            throw APIError.serverError(ErrorResponse(code: "VALIDATION_ERROR", message: "缺少 answers"))
        }

        // 与后端同口径：必须一题不缺、也不能多，且不许同题多答
        var submitted: [Int64: String] = [:]
        for answer in request.answers {
            if submitted.updateValue(answer.optionId, forKey: answer.questionId) != nil {
                throw APIError.serverError(ErrorResponse(
                    code: "BAD_REQUEST", message: "同一道题提交了多个答案，请重新作答"
                ))
            }
        }
        guard Set(submitted.keys) == Set(course.questions.map(\.id)) else {
            throw APIError.serverError(ErrorResponse(
                code: "BAD_REQUEST", message: "答案与题目不匹配，请重新进入课程作答"
            ))
        }

        var correctCount = 0
        var wrong: [TrainingQuizResult.WrongQuestion] = []
        for question in course.questions {
            if submitted[question.id] == question.correctOption {
                correctCount += 1
            } else {
                wrong.append(TrainingQuizResult.WrongQuestion(
                    questionId: question.id,
                    stem: question.stem,
                    explanation: question.explanation
                ))
            }
        }
        // 及格线是**全对**，不是百分比 —— 与后端一致
        let passed = correctCount == course.questions.count

        var progress = trainingProgress[courseId] ?? MockTrainingProgress()
        progress.attemptCount += 1
        let firstPass = passed && progress.completedAt == nil
        if firstPass {
            progress.completedAt = Date()
            progress.certificateNo = "AIDRUN-T-MOCK-\(courseId)"
        }
        trainingProgress[courseId] = progress

        // 必修恒 0，只有选修首次通过才发分 —— 与后端一致
        let awarded = (firstPass && !course.isRequired) ? course.rewardPoints : 0
        return TrainingQuizResult(
            passed: passed,
            correctCount: correctCount,
            totalCount: course.questions.count,
            attemptNo: progress.attemptCount,
            wrongQuestions: wrong,
            awardedPoints: awarded,
            certificateNo: (firstPass && mockTrainingRequiredCompleted) ? progress.certificateNo : nil,
            requiredCompleted: mockTrainingRequiredCompleted
        )
    }

    /// 测试/演示用：把全部必修课直接标成已通过。
    ///
    /// 存在的理由是 Mock 默认「一门都没学」（见 `trainingProgress` 的注释）——
    /// 那个默认让培训主路径能被走到，但也意味着**任何与培训无关的志愿者用例**
    /// 都会被 `TRAINING_INCOMPLETE` 干扰。那些用例在 setUp 里调这个方法即可。
    ///
    /// ⚠️ 刻意**不走判卷路径**：它要的是「前提成立」，不是「验证判卷」。
    /// 判卷本身由 `VolunteerTrainingTests` 走真实路径验。
    func completeAllRequiredTrainingForTesting() {
        for course in Self.mockTrainingCourses where course.isRequired {
            var progress = trainingProgress[course.id] ?? MockTrainingProgress()
            progress.completedAt = Date()
            progress.certificateNo = "AIDRUN-T-MOCK-\(course.id)"
            trainingProgress[course.id] = progress
        }
    }

    private func mockTrainingStatus(_ progress: MockTrainingProgress?) -> String {
        guard let progress else { return "NOT_STARTED" }
        if progress.isCompleted { return "COMPLETED" }
        return "IN_PROGRESS"
    }

    private static func mockIso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
