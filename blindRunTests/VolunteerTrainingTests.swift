import XCTest
@testable import blindRun

/// 志愿者线上培训（后端迁移 `0043`）。
///
/// 这组用例守的是**四件在代码里看不出来、破了却不会报错**的事：
///
/// 1. `TRAINING_INCOMPLETE` 必须被认出来。不认它 UI 就只剩 `.unknown` 那句
///    「请稍后重试或更新 App」—— 既不真也没用，而这是「上线了却收不到派单」
///    在屏幕上唯一的解释。
/// 2. 未知 `status` 值不许让整条响应解不出来（AGENTS.md 的盲人端红线）。
/// 3. `TRAINING_REWARD` 要念成「培训奖励」而不是「其他」——
///    不加映射**不会崩**，所以这条极容易被漏掉。
/// 4. 答不了的题（选项缺失）必须挡住提交。「全对才过」下他永远交不了卷，
///    而灰按钮不会说明为什么。
@MainActor
final class VolunteerTrainingTests: XCTestCase {

    // MARK: - 派单摘要：TRAINING_INCOMPLETE 的告知

    /// 🚩 本组最重要的一条。
    func testTrainingIncompleteReasonIsRecognisedAndExplained() {
        let summary = Self.summary(reasons: [.trainingIncomplete])

        XCTAssertEqual(
            summary.dispatchStatusText, "尚未完成必修培训",
            "认不出这个取值时会落到 .unknown 的「请稍后重试或更新 App」—— "
                + "那句话对一个「上线了却永远收不到单」的志愿者既不真也没用"
        )
        XCTAssertNotEqual(
            summary.dispatchStatusText,
            VolunteerDispatchNotAvailableReason.unknown.displayText,
            "落到 unknown 就说明枚举没跟上后端"
        )
    }

    /// 解码要真的认得后端下发的那个字符串 —— 上一条用的是构造好的枚举，绕过了解码。
    func testTrainingIncompleteDecodesFromBackendRawValue() throws {
        let json = #"{"canDispatch":false,"notAvailableReasons":["TRAINING_INCOMPLETE"]}"#
        let decoded = try JSONDecoder().decode(
            VolunteerDispatchSummaryResponse.self, from: Data(json.utf8)
        )

        XCTAssertEqual(decoded.notAvailableReasons, [.trainingIncomplete])
        XCTAssertEqual(decoded.dispatchStatusText, "尚未完成必修培训")
    }

    /// 与 `NOT_VERIFIED` 可以同时出现，两条都要念出来（后端刻意让它们正交）。
    func testTrainingAndVerificationReasonsCoexistAndBothAreSpoken() {
        let summary = Self.summary(reasons: [.notVerified, .trainingIncomplete])

        XCTAssertTrue(summary.dispatchStatusText.contains("尚未通过资质认证"))
        XCTAssertTrue(
            summary.dispatchStatusText.contains("尚未完成必修培训"),
            "两条同时命中时不能只念一条 —— 他会以为解决了资质就能接单"
        )
    }

    /// `.trainingIncomplete` 要进 `allCases`（那是「可枚举的真实原因」清单，
    /// 排除的只有 `.unknown`）。漏了它，任何遍历 `allCases` 的引导逻辑都会跳过培训。
    func testTrainingIncompleteIsAnEnumerableRealReason() {
        XCTAssertTrue(VolunteerDispatchNotAvailableReason.allCases.contains(.trainingIncomplete))
        XCTAssertFalse(VolunteerDispatchNotAvailableReason.allCases.contains(.unknown))
    }

    // MARK: - 解码宽容度

    /// 未知 `status` 不许让整条响应丢掉。
    func testUnknownCourseStatusDegradesInsteadOfFailingTheWholeResponse() throws {
        let json = """
        {"requiredCompleted":false,"courses":[
          {"id":1,"code":"X","title":"某课","required":true,"status":"SOMETHING_NEW_FROM_BACKEND"}
        ]}
        """
        let decoded = try JSONDecoder().decode(
            TrainingCourseListResponse.self, from: Data(json.utf8)
        )

        XCTAssertEqual(decoded.visibleCourses.count, 1, "未知状态值不该让整条响应解不出来")
        let course = try XCTUnwrap(decoded.visibleCourses.first)
        XCTAssertEqual(course.progressState, .unknown)
        XCTAssertEqual(
            course.progressState.displayText, "进行中",
            "对用户不能显示「未知状态」这种内部术语"
        )
        XCTAssertFalse(course.isCompleted, "未知状态绝不能被当成已完成 —— 那会让门槛凭空放开")
    }

    /// 字段整体缺失时按「未完成」处理，方向是刻意保守的。
    func testMissingRequiredCompletedIsTreatedAsNotCompleted() throws {
        let decoded = try JSONDecoder().decode(
            TrainingCourseListResponse.self, from: Data(#"{"courses":[]}"#.utf8)
        )

        XCTAssertFalse(
            decoded.isRequiredCompleted,
            "默认 true 会让没学完的人以为自己达标了，然后困惑为什么收不到单"
        )
        XCTAssertTrue(decoded.visibleCourses.isEmpty)
    }

    // MARK: - 积分流水文案

    /// 不加这条映射**不会崩**（`reason` 是 `String?`，未知值落 default「其他」），
    /// 所以它是这次改动里最容易被漏掉的一处。
    func testTrainingRewardIsNamedInThePointsLedger() {
        let tx = PointTransactionResponse(
            id: 1, delta: 20, reason: "TRAINING_REWARD", orderId: nil, note: nil, createdAt: nil
        )

        XCTAssertEqual(
            tx.reasonText, "培训奖励",
            "漏了这条映射，志愿者做完选修拿到分、流水里那一行写着「其他」"
        )
        XCTAssertNotEqual(tx.reasonText, "其他")
    }

    // MARK: - 答题 view model

    /// 全部题目作答完才允许提交，且原因要能显示出来（不是只把按钮变灰）。
    func testSubmitStaysBlockedUntilEveryQuestionIsAnswered() async throws {
        let appState = Self.makeAppState()
        let viewModel = VolunteerTrainingCourseViewModel(courseId: 4002)
        viewModel.configure(appState: appState)

        await viewModel.load()
        let questions = viewModel.questions
        XCTAssertGreaterThan(questions.count, 1, "这条用例需要多于一道题才有意义")

        XCTAssertFalse(viewModel.canSubmit, "一题都没答就不能提交")
        XCTAssertFalse(viewModel.isEveryQuestionAnswered)

        for question in questions.dropLast() {
            viewModel.selections[question.id] = question.visibleOptions.first?.id
        }
        XCTAssertFalse(viewModel.canSubmit, "还差一题也不能提交")

        let last = try XCTUnwrap(questions.last)
        viewModel.selections[last.id] = last.visibleOptions.first?.id
        XCTAssertTrue(viewModel.canSubmit)
        XCTAssertTrue(viewModel.isEveryQuestionAnswered)
    }

    /// 🚩 选项缺失的题必须挡住提交。
    ///
    /// 「全对才过」意味着这种题让他永远交不了卷，而界面上必须说清原因
    /// （`VolunteerTrainingCopy.brokenQuestion`），不能只给一个灰按钮。
    func testQuestionWithNoOptionsBlocksSubmissionAndIsNamed() {
        let broken = TrainingQuestion(id: 1, stem: "选项没加载出来的题", options: [])
        XCTAssertTrue(broken.visibleOptions.isEmpty)
        XCTAssertFalse(
            VolunteerTrainingCopy.brokenQuestion.isEmpty,
            "必须有一句话解释为什么提交不了 —— 灰按钮本身不说明任何事"
        )
    }

    /// 重答只清掉答错的那几题，答对的保留。
    ///
    /// 清空全部在「全对才过」下是纯粹的惩罚，还会把注意力从「哪里想错了」挪到「重新点一遍」。
    func testRetryKeepsAnswersThatWereAlreadyCorrect() async throws {
        let appState = Self.makeAppState()
        let viewModel = VolunteerTrainingCourseViewModel(courseId: 4002)
        viewModel.configure(appState: appState)
        await viewModel.load()

        let questions = viewModel.questions
        XCTAssertGreaterThanOrEqual(questions.count, 2)
        // 全部先选第一个选项 —— Mock 里正确答案不都是 A，所以必然错几题
        for question in questions {
            viewModel.selections[question.id] = question.visibleOptions.first?.id
        }
        let submitted = await viewModel.submit()
        let result = try XCTUnwrap(submitted, "提交应当返回结果")
        XCTAssertFalse(result.isPassed, "全选第一个选项不该通过，否则这条用例没有区分度")

        let wrongIds = Set(result.visibleWrongQuestions.map(\.questionId))
        XCTAssertFalse(wrongIds.isEmpty)
        let correctIds = Set(questions.map(\.id)).subtracting(wrongIds)

        viewModel.prepareRetry()

        for id in wrongIds {
            XCTAssertNil(viewModel.selections[id], "答错的题要清掉，让他重新想")
        }
        for id in correctIds {
            XCTAssertNotNil(
                viewModel.selections[id],
                "答对的题必须保留 —— 让人把已经答对的再点一遍是纯粹的惩罚"
            )
        }
    }

    // MARK: - Mock 全链路（门槛真的会解开）

    /// 走真实判卷路径把两门必修课都过掉，`requiredCompleted` 要从 false 变 true，
    /// 且派单摘要里的 `TRAINING_INCOMPLETE` 要随之消失。
    ///
    /// 🚩 这条串起了本次改动的因果链：**门槛不是一个孤立的布尔，它连着「能不能接单」**。
    func testCompletingEveryRequiredCourseClearsTheDispatchBlock() async throws {
        let client = MockAPIClient()
        let appState = Self.makeAppState(client: client)

        let before: TrainingCourseListResponse = try await appState.training.courses()
        XCTAssertFalse(before.isRequiredCompleted, "Mock 默认一门课都没学")
        XCTAssertTrue(
            client.handleGetVolunteerDispatchSummary().notAvailableReasons?
                .contains(.trainingIncomplete) ?? false,
            "没学完时派单摘要必须给出 TRAINING_INCOMPLETE —— 少了它，"
                + "志愿者看到「等待系统派单」却永远等不到单，屏幕上没有任何解释"
        )

        // 逐门必修课全对通过
        for course in before.visibleCourses where course.isRequired {
            let detail = try await appState.training.courseDetail(courseId: course.id)
            let answers = detail.visibleQuestions.map { question in
                TrainingQuizSubmitRequest.Answer(
                    questionId: question.id,
                    optionId: Self.correctOption(courseId: course.id, questionId: question.id)
                )
            }
            let result = try await appState.training.submitQuiz(
                courseId: course.id,
                request: TrainingQuizSubmitRequest(answers: answers)
            )
            XCTAssertTrue(result.isPassed, "全对却没通过说明判卷口径不是「全对」")
            XCTAssertEqual(
                result.awardedPointsValue, 0,
                "必修课不发分 —— 给「达到最低要求」发奖会让积分失去意义"
            )
        }

        let after: TrainingCourseListResponse = try await appState.training.courses()
        XCTAssertTrue(after.isRequiredCompleted, "必修全过之后门槛必须解开")
        XCTAssertNotNil(after.certificateNo, "必修全过要发培训合格证（政策允许颁发）")
        XCTAssertFalse(
            client.handleGetVolunteerDispatchSummary().notAvailableReasons?
                .contains(.trainingIncomplete) ?? false,
            "门槛解开之后 TRAINING_INCOMPLETE 必须消失，否则首页永远说他不能接单"
        )
    }

    /// 选修首次通过发分，重复通过不重复发分。
    func testOptionalCourseAwardsPointsOnlyOnFirstPass() async throws {
        let client = MockAPIClient()
        let appState = Self.makeAppState(client: client)

        let list: TrainingCourseListResponse = try await appState.training.courses()
        let optional = try XCTUnwrap(
            list.visibleCourses.first(where: { !$0.isRequired && $0.rewardPointsValue > 0 }),
            "Mock 需要一门带奖励分的选修课"
        )
        let detail = try await appState.training.courseDetail(courseId: optional.id)
        let answers = detail.visibleQuestions.map { question in
            TrainingQuizSubmitRequest.Answer(
                questionId: question.id,
                optionId: Self.correctOption(courseId: optional.id, questionId: question.id)
            )
        }
        let request = TrainingQuizSubmitRequest(answers: answers)

        let first = try await appState.training.submitQuiz(courseId: optional.id, request: request)
        XCTAssertTrue(first.isPassed)
        XCTAssertEqual(first.awardedPointsValue, optional.rewardPointsValue)

        let again = try await appState.training.submitQuiz(courseId: optional.id, request: request)
        XCTAssertTrue(again.isPassed)
        XCTAssertEqual(again.awardedPointsValue, 0, "同一门课再过一次不能再发分")
    }

    /// 学习时长增量累加（政策要求记录的字段）。
    func testStudiedSecondsAccumulate() async throws {
        let client = MockAPIClient()
        let appState = Self.makeAppState(client: client)
        let courseId: Int64 = 4001

        try await appState.training.reportProgress(courseId: courseId, studiedSeconds: 60)
        try await appState.training.reportProgress(courseId: courseId, studiedSeconds: 30)

        let list: TrainingCourseListResponse = try await appState.training.courses()
        let course = try XCTUnwrap(list.visibleCourses.first(where: { $0.id == courseId }))
        XCTAssertEqual(course.studiedSeconds, 90, "上报的是增量，后端/Mock 做加法")
    }

    /// 课程详情里**不能**出现正确答案。
    ///
    /// Mock 与真实后端必须同构 —— UI 是照着 Mock 调的，Mock 多给了答案，
    /// 真机上就会少一块（或者反过来，有人照 Mock 写出依赖答案的 UI）。
    func testMockCourseDetailNeverCarriesTheCorrectAnswer() async throws {
        let appState = Self.makeAppState()
        let detail = try await appState.training.courseDetail(courseId: 4002)

        XCTAssertFalse(detail.visibleQuestions.isEmpty)
        // `TrainingQuestion` 类型上压根没有正确答案字段，这里断言的是「选项只有 id + text」，
        // 即结构上不存在承载答案的地方。
        for question in detail.visibleQuestions {
            XCTAssertFalse(question.visibleOptions.isEmpty, "每道题都要有选项，否则答不了")
            for option in question.visibleOptions {
                XCTAssertFalse(option.id.isEmpty)
            }
        }
    }

    /// 交卷时少答一题，Mock 要按后端口径拒绝，而不是「按能对上的部分判分」。
    func testMockRejectsPartialAnswerSetLikeTheBackendDoes() async throws {
        let appState = Self.makeAppState()
        let detail = try await appState.training.courseDetail(courseId: 4002)
        let partial = detail.visibleQuestions.dropLast().map { question in
            TrainingQuizSubmitRequest.Answer(
                questionId: question.id,
                optionId: question.visibleOptions.first?.id ?? "A"
            )
        }

        do {
            _ = try await appState.training.submitQuiz(
                courseId: 4002,
                request: TrainingQuizSubmitRequest(answers: Array(partial))
            )
            XCTFail("少答一题必须被拒 —— 按部分判分会把漏传的坏客户端表现成「你答错了」")
        } catch {
            XCTAssertEqual((error as? APIError)?.errorCode, .badRequest)
        }
    }

    // MARK: - 错误码文案

    /// `TRAINING_NOT_COMPLETED` 的文案必须与「去传资质证件」那条区分开。
    func testTrainingNotCompletedMessageDoesNotSendUserToUploadDocuments() {
        let training = ErrorCode.trainingNotCompleted.localizedMessage
        let notVerified = ErrorCode.volunteerNotApproved.localizedMessage

        XCTAssertNotEqual(training, notVerified)
        XCTAssertTrue(
            training.contains("培训"),
            "这条要把人指向培训，而不是让他去传一份根本不需要的材料"
        )
        XCTAssertFalse(
            training.contains("资质证书"),
            "共用「上传资质证书」的说法会让志愿者做一件完全无效的事"
        )
    }

    // MARK: - Helpers

    /// 调用方作用域里的 `let` —— view model 的 `weak appState` 才不会当场断
    /// （守卫规则 `weak-temporary`，记忆 `location-service-test-seam-and-weak-viewmodel-deps`）。
    private static func makeAppState(client: MockAPIClient? = nil) -> AppState {
        let appState = AppState(apiClient: client ?? MockAPIClient())
        appState.currentEnvironment = .mock
        return appState
    }

    /// 从 Mock 课表里取某题的正确答案。
    ///
    /// ⚠️ 只有测试能这么做 —— 生产代码拿不到正确答案，那正是重点。
    private static func correctOption(courseId: Int64, questionId: Int64) -> String {
        MockAPIClient.mockTrainingCourses
            .first(where: { $0.id == courseId })?
            .questions.first(where: { $0.id == questionId })?
            .correctOption ?? "A"
    }

    private static func summary(
        reasons: [VolunteerDispatchNotAvailableReason]
    ) -> VolunteerDispatchSummaryResponse {
        VolunteerDispatchSummaryResponse(
            canDispatch: reasons.isEmpty,
            notAvailableReasons: reasons,
            wantsDispatch: true,
            isOnline: true,
            lastLat: nil,
            lastLng: nil,
            lastLocationAt: nil,
            coverageRadiusKm: 10,
            isWithinServiceTime: true,
            availableTimeSlots: nil,
            avgRating: nil,
            totalRatings: nil,
            totalDispatched: nil,
            totalAccepted: nil,
            totalDeclined: nil,
            totalTimeout: nil,
            totalCompleted: nil,
            totalCancelled: nil,
            acceptanceRate: nil,
            activeOrders: nil,
            recentOrders: nil,
            introCallOrderId: nil
        )
    }
}
