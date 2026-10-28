import CoreLocation
import XCTest
@testable import blindRun

/// #500：UI 测试定位接缝与 Mock 的「合并进未结案事件」。
///
/// 接缝让 UI 用例走得到屏 3b；这里守的是它**不会**变成「演示坐标上传」的口子（`AGENTS.md` §6）：
/// 测试来源的样本只许发给 Mock，任何别的客户端一律一个字节都不发。
@MainActor
final class EmergencyUITestLocationSeamTests: XCTestCase {
    private static let orderId: Int64 = 4_500

    // MARK: - 接缝本身

    #if DEBUG
    /// 两个开关缺一个都不出样本：UI 测试没要这条路时，求助照旧只认设备采样。
    func testSeamProducesASampleOnlyWhenBothSwitchesAreOn() {
        let key = EmergencyCoordinator.uiTestEmergencyLocationKey
        XCTAssertNil(EmergencyCoordinator.uiTestEmergencySample(environment: [:]))
        XCTAssertNil(EmergencyCoordinator.uiTestEmergencySample(environment: [key: "1"]), "没选 Mock 环境也出了样本")
        XCTAssertNil(EmergencyCoordinator.uiTestEmergencySample(environment: ["AIDRUN_UI_TEST_API_ENV": "mock"]))
        XCTAssertNil(EmergencyCoordinator.uiTestEmergencySample(environment: [key: "1", "AIDRUN_UI_TEST_API_ENV": "demo"]))

        let sample = EmergencyCoordinator.uiTestEmergencySample(environment: [key: "1", "AIDRUN_UI_TEST_API_ENV": "mock"])
        XCTAssertEqual(sample?.source, .uiTestSeam, "接缝产出的样本必须带测试来源标记")
        XCTAssertEqual(sample?.system, .gcj02Backend)
    }
    #endif

    // MARK: - 硬拒绝：测试来源 × 非 Mock

    /// 单测替身不是 Mock：判错的代价不对称，宁可按真实后端算。
    func testTestSourcedSampleIsNeverSentThroughANonMockService() async {
        let (coordinator, safety) = EmergencySOSTests.makeCountdownFixture()
        defer { EmergencySOSTests.teardownAlarmObservers() }
        safety.triggerEmergencyResult = .success(EmergencyTriggerResponse(success: true, eventId: 1, status: "PENDING"))

        let outcome = await trigger(coordinator, safety: safety, sample: Self.sample(.uiTestSeam))

        XCTAssertTrue(safety.calls.isEmpty, "测试来源的坐标发出去了：\(safety.calls)")
        XCTAssertEqual(outcome.state, .unsentNoLocation(nil))
        XCTAssertTrue(outcome.isFailure, "没发出去就必须按失败说")
        XCTAssertNil(coordinator.activeEvent)
    }

    /// 真实的 `SafetyService`，只是底下不是 `MockAPIClient`（线上就是这个形状）：同样一个请求都不许出门。
    func testTestSourcedSampleIsNeverSentThroughARealTransport() async {
        let coordinator = EmergencyCoordinator()
        let transport = NonMockSafetyTransport()

        let outcome = await trigger(coordinator, safety: SafetyService(transport: transport), sample: Self.sample(.uiTestSeam))

        XCTAssertEqual(transport.paths, [], "测试来源的坐标打到了真实后端")
        XCTAssertEqual(outcome.state, .unsentNoLocation(nil))
    }

    /// 反向哨兵：设备采样照常发。没有这一条，上面两条在「一律不发」的实现下也是绿的。
    func testDeviceSampleIsStillSentThroughANonMockService() async {
        let (coordinator, safety) = EmergencySOSTests.makeCountdownFixture()
        defer { EmergencySOSTests.teardownAlarmObservers() }
        safety.triggerEmergencyResult = .success(EmergencyTriggerResponse(success: true, eventId: 77, status: "CONTACT_NOTIFIED"))

        let outcome = await trigger(coordinator, safety: safety, sample: Self.sample(.device))

        XCTAssertEqual(safety.calls, ["triggerEmergency(_:)"])
        XCTAssertEqual(outcome.state, .acknowledged(.contactNotified))
    }

    /// 坐标系转换不许把标记洗掉：洗掉了，测试样本就变成了「设备采样」，闸形同虚设。
    func testNormalizerKeepsTheSourceMarker() {
        let wgs = LocatedCoordinate(
            coordinate: CLLocationCoordinate2D(latitude: 39.9, longitude: 116.4),
            system: .wgs84Device,
            source: .uiTestSeam
        )
        let normalized = BackendCoordinateNormalizer.normalize(wgs)
        XCTAssertEqual(normalized?.system, .gcj02Backend, "前提：确实走了转换那一支")
        XCTAssertEqual(normalized?.source, .uiTestSeam)
    }

    // MARK: - Mock：测试来源能发，再按一次被并进同一条（后端 #841）

    func testMockAcceptsTheTestSampleAndMergesTheRetriggerIntoTheOpenEvent() async {
        let mock = Self.makeMock()
        let safety = SafetyService(transport: mock)
        let coordinator = EmergencyCoordinator()
        XCTAssertTrue(EmergencyCoordinator.isMockBacked(safety), "前提：这一份才算 Mock")

        let first = await trigger(coordinator, safety: safety, sample: Self.sample(.uiTestSeam))
        guard case .acknowledged = first.state else {
            return XCTFail("测试来源的样本发给 Mock 应当受理，实际 \(first.state)")
        }
        let eventID = coordinator.activeEvent?.eventID

        let second = await trigger(coordinator, safety: safety, sample: Self.sample(.uiTestSeam))

        XCTAssertNotNil(eventID)
        XCTAssertEqual(coordinator.activeEvent?.eventID, eventID, "Mock 又新建了一条，没照后端 #841 合并")
        guard case .mergedIntoOpenEvent = second.state else {
            return XCTFail("再按一次应当被并进未结案的那条，实际 \(second.state)")
        }
        XCTAssertEqual(coordinator.mergedRetriggerCount, 1, "屏 3b 靠它重新弹出")
        XCTAssertTrue(second.message.hasPrefix("这次没有新建求助"), second.message)
    }

    /// 按钮真正走的入口是 `beginCountdown`（长按 / 确认后都到这里）：被合并时**念**的必须是「这次没有新建求助」那句。
    /// 屏 3b 上的同一句由 UI 用例 `testBlindSOSSentScreenPopsUpAgainWhenTheRetriggerIsMerged` 守，UI 测试听不到声音。
    func testMergedRetriggerThroughTheCountdownEntryAnnouncesNoNewRequest() async {
        let mock = Self.makeMock()
        let safety = SafetyService(transport: mock)
        let coordinator = EmergencyCoordinator()
        _ = await trigger(coordinator, safety: safety, sample: Self.sample(.uiTestSeam))
        XCTAssertNotNil(coordinator.activeEvent, "前提：第一条已发出")

        let retrigger = Self.sample(.uiTestSeam)
        var spoken: [String] = []
        coordinator.beginCountdown(
            order: .preview(orderId: Self.orderId, status: .inProgress),
            role: .blind,
            userID: 7,
            safety: safety,
            locate: { retrigger },
            announce: { spoken.append($0) }
        )
        for _ in 0..<20 where spoken.isEmpty {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }

        XCTAssertEqual(spoken, [EmergencySafetyCopy.mergedIntoOpenEvent])
        XCTAssertEqual(coordinator.mergedRetriggerCount, 1)
    }

    /// 合并只发生在**未结案**时：撤销之后再按是一条新求助。
    func testMockOpensANewEventOnceTheOpenOneIsClosed() async throws {
        let mock = Self.makeMock()
        let safety = SafetyService(transport: mock)
        let coordinator = EmergencyCoordinator()

        _ = await trigger(coordinator, safety: safety, sample: Self.sample(.device))
        let firstID = try XCTUnwrap(coordinator.activeEvent?.eventID)
        let cancelled = await coordinator.cancelByOwner(safety: safety)
        XCTAssertEqual(cancelled.state, .cancelledByOwner, "前提：第一条已撤销")

        let again = await trigger(coordinator, safety: safety, sample: Self.sample(.device))

        guard case .acknowledged = again.state else {
            return XCTFail("撤销之后再按应当是一条新求助，实际 \(again.state)")
        }
        XCTAssertNotEqual(coordinator.activeEvent?.eventID, firstID)
        XCTAssertEqual(coordinator.mergedRetriggerCount, 0)
    }

    // MARK: - Fixture

    private func trigger(
        _ coordinator: EmergencyCoordinator,
        safety: any SafetyServing,
        sample: LocatedCoordinate
    ) async -> EmergencyCoordinator.TriggerOutcome {
        await coordinator.trigger(
            order: .preview(orderId: Self.orderId, status: .inProgress),
            role: .blind,
            userID: 7,
            safety: safety,
            locate: { sample }
        )
    }

    private static func sample(_ source: LocatedCoordinate.Source) -> LocatedCoordinate {
        LocatedCoordinate(
            coordinate: CLLocationCoordinate2D(latitude: 39.915, longitude: 116.404),
            system: .gcj02Backend,
            horizontalAccuracy: 10,
            source: source
        )
    }

    private static func makeMock() -> MockAPIClient {
        let mock = MockAPIClient()
        mock.orders = [.preview(orderId: orderId, status: .inProgress)]
        return mock
    }
}

/// 不是 Mock 的传输层：记下每一条打出去的路径，一律按网络不通失败。
private final class NonMockSafetyTransport: APIClientProtocol, @unchecked Sendable {
    private(set) var paths: [String] = []

    func request<T: Decodable>(
        method: HTTPMethod,
        path: String,
        query: [String: String]?,
        body: (any Encodable & Sendable)?,
        requiresAuth: Bool
    ) async throws -> T {
        paths.append(path)
        throw APIError.networkError(URLError(.notConnectedToInternet))
    }

    func upload<T: Decodable>(
        path: String,
        query: [String: String]?,
        fields: [String: String]?,
        files: [MultipartFile],
        requiresAuth: Bool
    ) async throws -> T {
        paths.append(path)
        throw APIError.networkError(URLError(.notConnectedToInternet))
    }
}
