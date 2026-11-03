import XCTest
@testable import blindRun

/// 检查的编排（#526）：失败不拦、结果不缓存、关闭只记这个版本、只有版本过低时才查订单。
@MainActor
final class AppUpdateGateTests: XCTestCase {
    private struct Boom: Error {}

    private final class FakeSource: AppUpdateSource {
        var requirements: Result<AppVersionResponse, Error>
        var presence: AppUpdateOrderPresence = .none
        private(set) var presenceCalls = 0

        init(_ requirements: Result<AppVersionResponse, Error>) {
            self.requirements = requirements
        }

        func appVersionRequirements() async throws -> AppVersionResponse {
            try requirements.get()
        }

        func appUpdateOrderPresence() async -> AppUpdateOrderPresence {
            presenceCalls += 1
            return presence
        }
    }

    private static func response(min: String? = nil, latest: String? = nil) -> AppVersionResponse {
        AppVersionResponse(iosMinSupportedVersion: min, iosLatestVersion: latest, iosUpdateUrl: "https://apps.apple.com/cn/app/aidrun")
    }

    private func makeGate(
        currentVersion: String = "1.0",
        persistence: AppStatePersistence? = nil
    ) -> AppUpdateGate {
        AppUpdateGate(currentVersion: currentVersion, persistence: persistence ?? AppStatePersistenceFactory.makeIsolatedTest())
    }

    private static func isRequiredGate(_ presentation: AppUpdatePresentation) -> Bool {
        if case .requiredGate = presentation { return true }
        return false
    }

    private static func isOptionalPrompt(_ presentation: AppUpdatePresentation) -> Bool {
        if case .optionalPrompt = presentation { return true }
        return false
    }

    func testBelowMinimumWithNoOrderShowsTheGate() async {
        let gate = makeGate()
        await gate.refresh(from: FakeSource(.success(Self.response(min: "2.0"))))
        XCTAssertTrue(Self.isRequiredGate(gate.presentation))
    }

    /// 线上后端未部署时这个接口返回 401，走的就是这条。
    func testUnauthorizedResponseNeverBlocks() async {
        let gate = makeGate()
        await gate.refresh(from: FakeSource(.failure(APIError.unauthorized)))
        XCTAssertEqual(gate.presentation, .none)
    }

    func testRateLimitedOrFailedRequestNeverBlocks() async {
        let gate = makeGate()
        await gate.refresh(from: FakeSource(.failure(Boom())))
        XCTAssertEqual(gate.presentation, .none)
    }

    /// 结果不缓存：错配置修好之前断网时，人不能继续被挡在外面。
    func testALaterFailureLiftsTheGate() async {
        let gate = makeGate()
        let source = FakeSource(.success(Self.response(min: "2.0")))
        await gate.refresh(from: source)
        XCTAssertTrue(Self.isRequiredGate(gate.presentation))

        source.requirements = .failure(Boom())
        await gate.refresh(from: source)
        XCTAssertEqual(gate.presentation, .none)
    }

    func testAnActiveOrderHoldsTheGateBackUntilItEnds() async {
        let gate = makeGate()
        let source = FakeSource(.success(Self.response(min: "2.0")))
        source.presence = .active
        await gate.refresh(from: source)
        XCTAssertEqual(gate.presentation, .none)

        source.presence = .none
        await gate.refresh(from: source)
        XCTAssertTrue(Self.isRequiredGate(gate.presentation))
    }

    func testUpToDateDoesNotLookUpOrders() async {
        let source = FakeSource(.success(Self.response(min: "1.0", latest: "1.0.0")))
        await makeGate().refresh(from: source)
        XCTAssertEqual(source.presenceCalls, 0)
    }

    func testClosedPromptStaysClosedForTheSameVersion() async {
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        defer { persistence.reset() }
        let source = FakeSource(.success(Self.response(latest: "1.2.0")))
        let gate = makeGate(persistence: persistence)
        await gate.refresh(from: source)
        XCTAssertTrue(Self.isOptionalPrompt(gate.presentation))

        gate.dismissOptionalPrompt()
        XCTAssertEqual(gate.presentation, .none)

        await gate.refresh(from: source)
        XCTAssertEqual(gate.presentation, .none, "回到前台不再弹")

        let relaunched = makeGate(persistence: persistence)
        await relaunched.refresh(from: source)
        XCTAssertEqual(relaunched.presentation, .none, "重启也不再弹")
    }

    func testANewerVersionPromptsAgain() async {
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        defer { persistence.reset() }
        let source = FakeSource(.success(Self.response(latest: "1.2.0")))
        let gate = makeGate(persistence: persistence)
        await gate.refresh(from: source)
        gate.dismissOptionalPrompt()

        source.requirements = .success(Self.response(latest: "1.3.0"))
        await gate.refresh(from: source)
        XCTAssertTrue(Self.isOptionalPrompt(gate.presentation))
    }

    /// 退出登录跑 `reset()`。关闭记录不进 `all`，否则换账号就重弹一次。
    func testClosedPromptSurvivesAccountReset() {
        XCTAssertFalse(AppStatePersistenceKeys.all.contains(AppStatePersistenceKeys.dismissedAppUpdateVersion))
    }

    func testRequiredGateCannotBeDismissed() async {
        let gate = makeGate()
        await gate.refresh(from: FakeSource(.success(Self.response(min: "2.0"))))
        gate.dismissOptionalPrompt()
        XCTAssertTrue(Self.isRequiredGate(gate.presentation))
    }

    // MARK: 订单判定

    private func makeAppState(orders: FakeOrderService = FakeOrderService()) -> AppState {
        AppState(orders: orders, persistence: AppStatePersistenceFactory.makeIsolatedTest())
    }

    /// 冷启动恢复完成之前不知道这个人有没有在跑，全屏页不能抢先盖上来。
    func testRestoringSessionIsUnknown() async {
        let presence = await makeAppState().appUpdateOrderPresence()
        XCTAssertEqual(presence, .unknown)
    }

    func testRunnerStatusesMapToPresence() {
        XCTAssertEqual(AppState.orderPresence(runnerStatus: nil), .none)
        XCTAssertEqual(AppState.orderPresence(runnerStatus: .completed), .none)
        XCTAssertEqual(AppState.orderPresence(runnerStatus: .cancelled), .none)
        XCTAssertEqual(AppState.orderPresence(runnerStatus: .noVolunteer), .none)
        for status: RunOrderStatus in [.pendingMatch, .pendingIntroCall, .scheduledConfirmed, .pendingAccept, .driverEnRoute, .driverArrived, .inProgress, .rematching, .unknown] {
            XCTAssertEqual(AppState.orderPresence(runnerStatus: status), .active, "\(status)")
        }
    }

    private func summary(_ fields: String) throws -> VolunteerDispatchSummaryResponse {
        try JSONDecoder().decode(VolunteerDispatchSummaryResponse.self, from: Data("{\(fields)}".utf8))
    }

    func testVolunteerSummaryCountsEveryOrderField() throws {
        XCTAssertEqual(AppState.orderPresence(volunteerSummary: try summary(#""activeOrders":[],"upcomingOrders":[]"#)), .none)
        XCTAssertEqual(AppState.orderPresence(volunteerSummary: try summary(#""introCallOrderId":9,"upcomingOrders":[]"#)), .active)
        XCTAssertEqual(AppState.orderPresence(volunteerSummary: try summary(#""activeOrders":[{"orderId":9,"status":"IN_PROGRESS"}],"upcomingOrders":[]"#)), .active)
        XCTAssertEqual(AppState.orderPresence(volunteerSummary: try summary(#""upcomingOrders":[{"orderId":9,"status":"IN_PROGRESS"}]"#)), .active)
    }

    /// 契约：`upcomingOrders` 为 null 表示这一块服务端没取到，当成空列表就会盖住他的预约单。
    func testVolunteerSummaryWithoutUpcomingBlockIsUnknown() throws {
        XCTAssertEqual(AppState.orderPresence(volunteerSummary: try summary(#""activeOrders":[]"#)), .unknown)
    }
}
