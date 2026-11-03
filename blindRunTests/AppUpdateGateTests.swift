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

    private static func isOptionalPrompt(_ presentation: AppUpdatePresentation) -> Bool {
        if case .optionalPrompt = presentation { return true }
        return false
    }

    func testBelowMinimumWithNoEscortPrompts() async {
        let gate = makeGate()
        await gate.refresh(from: FakeSource(.success(Self.response(min: "2.0"))))
        XCTAssertTrue(gate.presentation.isRequired)
    }

    /// 线上后端未部署时这个接口返回 401，走的就是这条。
    func testUnauthorizedResponseNeverPrompts() async {
        let gate = makeGate()
        await gate.refresh(from: FakeSource(.failure(APIError.unauthorized)))
        XCTAssertEqual(gate.presentation, .none)
    }

    func testRateLimitedOrFailedRequestNeverPrompts() async {
        let gate = makeGate()
        await gate.refresh(from: FakeSource(.failure(Boom())))
        XCTAssertEqual(gate.presentation, .none)
    }

    /// 结果不缓存：错配置修好之前断网时，人不能继续被弹窗挡着。
    func testALaterFailureClearsThePrompt() async {
        let gate = makeGate()
        let source = FakeSource(.success(Self.response(min: "2.0")))
        await gate.refresh(from: source)
        XCTAssertTrue(gate.presentation.isRequired)

        source.requirements = .failure(Boom())
        await gate.refresh(from: source)
        XCTAssertEqual(gate.presentation, .none)
    }

    func testNoPromptDuringAnEscortThenPromptsOnceItEnds() async {
        let gate = makeGate()
        let source = FakeSource(.success(Self.response(min: "2.0")))
        source.presence = .underway
        await gate.refresh(from: source)
        XCTAssertEqual(gate.presentation, .none)

        source.presence = .none
        await gate.refresh(from: source)
        XCTAssertTrue(gate.presentation.isRequired)
    }

    /// 系统弹窗按下按钮就收起。回到 App 时版本仍然过低，必须再弹。
    func testRequiredPromptComesBackOnReturnWhileStillBelowMinimum() async {
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        defer { persistence.reset() }
        let source = FakeSource(.success(Self.response(min: "2.0")))
        let gate = makeGate(persistence: persistence)
        await gate.refresh(from: source)

        gate.promptDidClose()
        XCTAssertEqual(gate.presentation, .none)

        await gate.refresh(from: source)
        XCTAssertTrue(gate.presentation.isRequired, "回到 App 必须再弹")
    }

    func testRequiredPromptStopsOnceUpdated() async {
        let source = FakeSource(.success(Self.response(min: "2.0")))
        let gate = makeGate(currentVersion: "2.0")
        await gate.refresh(from: source)
        XCTAssertEqual(gate.presentation, .none)
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

        gate.promptDidClose()
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
        gate.promptDidClose()

        source.requirements = .success(Self.response(latest: "1.3.0"))
        await gate.refresh(from: source)
        XCTAssertTrue(Self.isOptionalPrompt(gate.presentation))
    }

    /// 退出登录跑 `reset()`。关闭记录不进 `all`，否则换账号就重弹一次。
    func testClosedPromptSurvivesAccountReset() {
        XCTAssertFalse(AppStatePersistenceKeys.all.contains(AppStatePersistenceKeys.dismissedAppUpdateVersion))
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

    /// 只有这三态推迟。这条同时钉住 `isEscortUnderway` 与负责人定的三态是同一个集合。
    func testOnlyTheThreeEscortStatusesDeferThePrompt() {
        for status: RunOrderStatus in [.driverEnRoute, .driverArrived, .inProgress] {
            XCTAssertEqual(AppState.orderPresence(statuses: [status]), .underway, "\(status)")
        }
        for status: RunOrderStatus in [.pendingMatch, .pendingIntroCall, .scheduledConfirmed, .pendingAccept, .rematching, .completed, .cancelled, .noVolunteer] {
            XCTAssertEqual(AppState.orderPresence(statuses: [status]), .none, "\(status)")
        }
        XCTAssertEqual(AppState.orderPresence(statuses: []), .none)
    }

    func testStatusUnknownToThisClientIsNotTreatedAsFree() {
        XCTAssertEqual(AppState.orderPresence(statuses: [.unknown]), .unknown)
        XCTAssertEqual(AppState.orderPresence(statuses: [.unknown, .inProgress]), .underway)
    }
}
