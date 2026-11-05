import Combine
import CoreLocation
import XCTest
@testable import blindRun

@MainActor
final class EmergencySOSTriggerTests: XCTestCase, EmergencySOSTestSupport {

    // MARK: - Trigger: eligibility

    func testTriggerIsRejectedOutsideInProgress() async {
        let coordinator = EmergencyCoordinator()
        let safety = FakeSafetyService()
        let outcome = await coordinator.trigger(
            order: Self.makeOrder(status: .driverArrived),
            role: .blind,
            userID: 7,
            safety: safety,
            locate: { Self.coordinate() }
        )
        XCTAssertTrue(outcome.isFailure)
        XCTAssertTrue(safety.calls.isEmpty, "no request may be sent outside IN_PROGRESS")
        XCTAssertNil(coordinator.activeEvent)
    }

    /// 2026-08-01 起志愿者可以代盲人发起求助。
    ///
    /// 这条用例原先断言的是「志愿者角色一律拒绝」—— 那是后端把事件挂在**触发者**身上时的止血：
    /// 志愿者按下去，告警回推给他自己、盲人收不到、升级的是志愿者的紧急联系人。后端已改成按订单
    /// 参与方归属事件（handoff 2026-07-31），门槛随之放开，断言跟着改成「服务进行中放行、其余拒绝」。
    /// 留这段说明是因为下一个读到它的人会问「为什么曾经写死拒绝」。
    func testVolunteerMayTriggerDuringServiceButNotOutsideIt() async {
        let coordinator = EmergencyCoordinator()
        let safety = FakeSafetyService()
        safety.triggerEmergencyResult = .success(EmergencyTriggerResponse(success: true, eventId: 77, status: "CONTACT_NOTIFIED"))

        let allowed = await coordinator.trigger(
            order: Self.makeOrder(status: .inProgress),
            role: .volunteer,
            userID: 7,
            safety: safety,
            locate: { Self.coordinate() }
        )
        XCTAssertFalse(allowed.isFailure)
        XCTAssertEqual(safety.calls.count, 1, "服务进行中，志愿者代触发必须真的发出去")
        XCTAssertEqual(coordinator.activeEvent?.eventID, 77)

        // 服务之外仍然不放行：与盲人侧同一个 IN_PROGRESS 门槛，不因为角色不同而放宽。
        let blocked = await EmergencyCoordinator().trigger(
            order: Self.makeOrder(status: .driverArrived),
            role: .volunteer,
            userID: 7,
            safety: safety,
            locate: { Self.coordinate() }
        )
        XCTAssertTrue(blocked.isFailure)
        XCTAssertEqual(safety.calls.count, 1, "非服务中状态不得再发一次请求")
    }

    // MARK: - Trigger: GPS gate

    func testStrictGpsGateSendsNothingWithoutACoordinate() async {
        XCTAssertFalse(
            EmergencyCoordinator.allowsSubmissionWithoutLocation,
            "the strict gate is the shipped default until product/safety approve degradation"
        )
        let coordinator = EmergencyCoordinator()
        let safety = FakeSafetyService()
        let outcome = await coordinator.trigger(
            order: Self.makeOrder(status: .inProgress),
            role: .blind,
            userID: 7,
            safety: safety,
            locate: { nil },
            locationFailureReason: { .permissionDenied }
        )
        XCTAssertEqual(coordinator.state, .unsentNoLocation(.permissionDenied))
        XCTAssertTrue(outcome.isFailure)
        XCTAssertTrue(safety.calls.isEmpty)
        XCTAssertTrue(outcome.message.contains("设置"), "must guide the user to Settings")
    }

    /// F12：定位失败的两种成因，下一步动作完全不同。把「室内没信号」说成「去开权限」，
    /// 是让一个正处在紧急状态的盲人去翻一个根本没关的开关。
    func testNoLocationCopySplitsPermissionFromSignalLoss() async {
        let denied = EmergencySafetyCopy.locationUnavailable(.permissionDenied)
        XCTAssertTrue(denied.contains("定位权限"))
        XCTAssertTrue(denied.contains("设置"))

        for reason: LocationError? in [.locationUnavailable, .timeout, nil] {
            let signalLost = EmergencySafetyCopy.locationUnavailable(reason)
            XCTAssertFalse(
                signalLost.contains("设置"),
                "权限没问题时不该把人支去翻设置（reason=\(String(describing: reason))）"
            )
            XCTAssertTrue(signalLost.contains("开阔处"))
            XCTAssertTrue(signalLost.hasPrefix("求助未发出"))
            XCTAssertTrue(signalLost.contains("110"))
        }

        // 默认不传 reason 时走通用支，不许退回原来那句「请在设置中允许定位」。
        let coordinator = EmergencyCoordinator()
        let safety = FakeSafetyService()
        let outcome = await coordinator.trigger(
            order: Self.makeOrder(status: .inProgress),
            role: .blind,
            userID: 7,
            safety: safety,
            locate: { nil }
        )
        XCTAssertEqual(coordinator.state, .unsentNoLocation(nil))
        XCTAssertFalse(outcome.message.contains("设置"))
    }

    /// A device WGS-84 sample must never be uploaded raw; only the value already normalized at the
    /// single backend boundary is accepted.
    func testUnconvertedDeviceCoordinateIsTreatedAsNoLocation() async {
        let coordinator = EmergencyCoordinator()
        let safety = FakeSafetyService()
        let raw = LocatedCoordinate(
            coordinate: CLLocationCoordinate2D(latitude: 39.9, longitude: 116.4),
            system: .wgs84Device,
            capturedAt: Date(), source: .device
        )
        _ = await coordinator.trigger(
            order: Self.makeOrder(status: .inProgress),
            role: .blind,
            userID: 7,
            safety: safety,
            locate: { raw }
        )
        XCTAssertEqual(coordinator.state, .unsentNoLocation(nil))
        XCTAssertTrue(safety.calls.isEmpty)
    }

    func testSuccessfulTriggerSendsOrderAndGcj02Coordinate() async {
        let coordinator = EmergencyCoordinator()
        let safety = FakeSafetyService()
        safety.triggerEmergencyResult = .success(EmergencyTriggerResponse(success: true, eventId: 512, status: "VOLUNTEER_NOTIFIED"))

        let outcome = await coordinator.trigger(
            order: Self.makeOrder(status: .inProgress),
            role: .blind,
            userID: 7,
            safety: safety,
            locate: { Self.coordinate(latitude: 39.915, longitude: 116.404) }
        )

        // 打的是不是 `POST /api/emergency/trigger` 由
        // `SafetyServiceTests.testTriggerEmergencyPostsTheRequestBody` 守，这里只管
        // 「coordinator 有没有把订单和那份 GCJ-02 坐标原样交下去」。
        XCTAssertEqual(safety.calls.count, 1)
        XCTAssertEqual(safety.lastTriggerRequest?.orderId, 4242)
        XCTAssertEqual(safety.lastTriggerRequest?.gpsLat ?? 0, 39.915, accuracy: 0.000001)
        XCTAssertEqual(safety.lastTriggerRequest?.gpsLng ?? 0, 116.404, accuracy: 0.000001)

        XCTAssertEqual(coordinator.state, .acknowledged(.volunteerNotified))
        XCTAssertEqual(coordinator.activeEvent?.eventID, 512)
        XCTAssertEqual(coordinator.activeEvent?.orderID, 4242)
        XCTAssertEqual(coordinator.activeEvent?.userID, 7)
        XCTAssertFalse(outcome.isFailure)
        XCTAssertFalse(outcome.message.contains("短信"))
    }

    // MARK: - Trigger: result gating

    /// HTTP 200 alone is not an acknowledgement — `success: false` is a failure.
    func testUnsuccessfulStructuredBodyIsAFailure() async {
        let coordinator = EmergencyCoordinator()
        let safety = FakeSafetyService()
        safety.triggerEmergencyResult = .success(EmergencyTriggerResponse(success: false, eventId: 1, status: "PENDING"))
        let outcome = await coordinator.trigger(
            order: Self.makeOrder(status: .inProgress),
            role: .blind,
            userID: 7,
            safety: safety,
            locate: { Self.coordinate() }
        )
        XCTAssertTrue(outcome.isFailure)
        XCTAssertNil(coordinator.activeEvent)
    }

    func testDecodingFailureLeavesSosUnsent() async {
        let coordinator = EmergencyCoordinator()
        let safety = FakeSafetyService()
        safety.triggerEmergencyResult = .failure(APIError.decodingError(TriggerStubError.decoding))
        let outcome = await coordinator.trigger(
            order: Self.makeOrder(status: .inProgress),
            role: .blind,
            userID: 7,
            safety: safety,
            locate: { Self.coordinate() }
        )
        XCTAssertTrue(outcome.isFailure)
        XCTAssertTrue(outcome.message.hasPrefix("求助未发出"))
        XCTAssertNil(coordinator.activeEvent)
    }

    /// Backend cooldown is `RateLimitException(60)` → 429 `TOO_MANY_REQUESTS` with
    /// `retryAfterSeconds` + a `Retry-After` header (`GlobalExceptionHandler.java:218-231`).
    func testCooldownSurfacesTheRetryDelay() async {
        let coordinator = EmergencyCoordinator()
        let safety = FakeSafetyService()
        safety.triggerEmergencyResult = .failure(APIError.rateLimited(RateLimitInfo(message: "请求过于频繁", retryAfterSeconds: 47)))
        let outcome = await coordinator.trigger(
            order: Self.makeOrder(status: .inProgress),
            role: .blind,
            userID: 7,
            safety: safety,
            locate: { Self.coordinate() }
        )
        XCTAssertEqual(coordinator.state, .cooldown(retryAfterSeconds: 47))
        XCTAssertTrue(outcome.message.contains("47"))
        XCTAssertNil(coordinator.activeEvent)
    }

    func testConcurrentTapsSendOnlyOneRequest() async {
        let coordinator = EmergencyCoordinator()
        let safety = FakeSafetyService()
        safety.triggerEmergencyResult = .success(EmergencyTriggerResponse(success: true, eventId: 1, status: "PENDING"))
        safety.triggerDelayNanoseconds = 200_000_000

        let order = Self.makeOrder(status: .inProgress)
        // A slow fix acquisition is the realistic window for a second tap: the runner hears nothing
        // yet and presses again. The guard must already be armed during `.locating`, not only once
        // the request is in flight.
        async let first = coordinator.trigger(
            order: order,
            role: .blind,
            userID: 7,
            safety: safety,
            locate: {
                try? await Task.sleep(nanoseconds: 200_000_000)
                return Self.coordinate()
            }
        )
        // 这里原本是单次 `await Task.yield()` 然后立刻断言。**那是 flaky 的**：一次 yield 只保证
        // 当前任务让出一次，不保证 `trigger` 已经跑到 `state = .locating`。单跑本套件永远绿，
        // 和另外三套一起跑（77 条）时会间歇性红成 `("idle") is not equal to ("locating")` ——
        // 2026-08-12 实测同一份代码、同一条命令，一次 76/77、一次 77/77。
        //
        // 改成有界自旋。断言的意图一个字没变（「`.locating` 期间守卫就必须已经武装」），
        // 变的只是不再假设一次 yield 足够：真回归时状态永远不会变成 `.locating`，
        // 循环空转到超时，断言照样红。
        var spins = 0
        while coordinator.state != .locating && spins < 100 {
            await Task.yield()
            spins += 1
        }
        XCTAssertEqual(coordinator.state, .locating, "the button must show progress while locating")

        let second = await coordinator.trigger(
            order: order, role: .blind, userID: 7, safety: safety, locate: { Self.coordinate() }
        )
        _ = await first

        XCTAssertEqual(safety.calls.count, 1, "a double tap must not send two SOS requests")
        XCTAssertTrue(second.state.isBusy)
    }
}

// MARK: - Test Doubles
//
// 替身是 `FakeSafetyService`（`blindRunTests/FakeSafetyService.swift`）。原先这里那个
// `EmergencyAPIClientStub` 是个 `APIClientProtocol` 桩，按 path 分支决定返回什么 ——
// 于是「什么条件下才该发出请求」这个判定同时活在被测代码和替身里，而它正是 §6 的红线本身。

/// 只用来喂 `APIError.decodingError` 一个底层错误。
private enum TriggerStubError: Error { case decoding }
