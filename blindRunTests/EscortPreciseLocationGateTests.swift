import CoreLocation
import XCTest
@testable import blindRun

/// 陪跑同行会话里的「精确位置」关闭：盲人端 #373 起亮横幅、申请临时精确位置；#407 起两端都不上报同行位置、都亮横幅、都申请。
/// OpenSpec `gate-escort-sharing-on-precise-accuracy`。从 `PreciseLocationGateTests` 拆出（那个文件超了 SwiftLint 棘轮）。
@MainActor
final class EscortPreciseLocationGateTests: XCTestCase {

    /// 盲人端：出发阶段申请一次，进 `IN_PROGRESS` 再申请一次，同一阶段不重复；健康提示落到精确位置那一档。
    func testBlindEscortRequestsPreciseLocationPerPhaseAndShowsTheHealthBanner() async {
        let location = Self.locationService(accuracy: 5000)
        location.simulatePreciseLocationOffForTesting()
        let (coordinator, service) = Self.makeEscortCoordinator(role: .blind, location: location)

        coordinator.updateOwnedOrder(orderID: 79, status: .driverEnRoute)
        let showedBanner = await Self.waitUntil { coordinator.healthState == .preciseLocationOff(.blind) }
        XCTAssertTrue(showedBanner, "健康提示：\(coordinator.healthState)")
        XCTAssertEqual(location.temporaryPreciseLocationRequestsForTesting, [.escortRun])
        XCTAssertTrue(coordinator.healthState.userMessage?.contains("求助") == true, "要说清求助会发不出去")
        XCTAssertTrue(coordinator.healthState.userMessage?.contains("暂停同行位置共享") == true, "要说清已经不发了（#407）")

        coordinator.updateOwnedOrder(orderID: 79, status: .driverArrived)
        _ = await Self.waitUntil { false }
        XCTAssertEqual(location.temporaryPreciseLocationRequestsForTesting.count, 1, "出发阶段内不重复弹")

        coordinator.updateOwnedOrder(orderID: 79, status: .inProgress)
        let requestedAgain = await Self.waitUntil { location.temporaryPreciseLocationRequestsForTesting.count == 2 }
        XCTAssertTrue(requestedAgain, "进跑步阶段仍关着就再申请一次")

        // 用户允许了：下一轮刷新回到正常档位。
        location.simulatePreciseLocationOffForTesting(false)
        let recovered = await Self.waitUntil { coordinator.healthState == .active(background: true) }
        XCTAssertTrue(recovered, "允许之后应恢复：\(coordinator.healthState)")
        coordinator.reset()
        withExtendedLifetime(service) {}
    }

    /// 网络断开时同行位置整个停了，比「位置不准」更要紧：横幅先说断网。
    func testNetworkDisconnectOutranksThePreciseLocationBanner() async {
        let location = Self.locationService(accuracy: 5000)
        location.simulatePreciseLocationOffForTesting()
        let (coordinator, service) = Self.makeEscortCoordinator(role: .blind, location: location, connected: false)

        coordinator.updateOwnedOrder(orderID: 81, status: .inProgress)
        let settled = await Self.waitUntil { coordinator.healthState == .networkDisconnected }

        XCTAssertTrue(settled, "健康提示：\(coordinator.healthState)")
        coordinator.reset()
        withExtendedLifetime(service) {}
    }

    /// 陪跑员端也进这一档、也申请临时精确位置（#407 定为两端都拦），用陪跑员自己的用途说明；文案不提求助。
    func testVolunteerEscortRequestsPreciseLocationPerPhaseAndShowsItsOwnBanner() async {
        let location = Self.locationService(accuracy: 5000)
        location.simulatePreciseLocationOffForTesting()
        let (coordinator, service) = Self.makeEscortCoordinator(role: .volunteer, location: location)

        coordinator.updateOwnedOrder(orderID: 80, status: .driverEnRoute)
        let showedBanner = await Self.waitUntil { coordinator.healthState == .preciseLocationOff(.volunteer) }
        XCTAssertTrue(showedBanner, "健康提示：\(coordinator.healthState)")
        XCTAssertEqual(location.temporaryPreciseLocationRequestsForTesting, [.escortVolunteer], "不借用盲人那条用途说明")
        let message = coordinator.healthState.userMessage ?? ""
        XCTAssertTrue(message.contains("暂停同行位置共享") && message.contains("精确位置"), message)
        XCTAssertFalse(message.contains("求助"), "陪跑员端的求助不受这个开关影响，不许说发不出去")

        coordinator.updateOwnedOrder(orderID: 80, status: .driverArrived)
        _ = await Self.waitUntil { false }
        XCTAssertEqual(location.temporaryPreciseLocationRequestsForTesting.count, 1, "出发阶段内不重复弹")
        coordinator.updateOwnedOrder(orderID: 80, status: .inProgress)
        let requestedAgain = await Self.waitUntil { location.temporaryPreciseLocationRequestsForTesting.count == 2 }
        XCTAssertTrue(requestedAgain, "进跑步阶段仍关着就再申请一次")
        coordinator.reset()
        withExtendedLifetime(service) {}
    }

    /// 🔴 #407 第 2 项：精确位置关着时两端都不上报同行位置（此前只拦了盲人端的求助与下单，同行位置每 5 秒照发模糊点）。
    /// 对照在同一条里：允许精确位置、来了新样本之后恢复上报 —— 只断「不发」的话，一个永远不发的实现也会绿。
    func testEscortSendsNoLocationWhilePreciseLocationIsOffOnEitherSide() async {
        for role in [UserRole.blind, .volunteer] {
            let location = Self.locationService(accuracy: 5000)
            location.simulatePreciseLocationOffForTesting()
            var sent = 0
            let (coordinator, service) = Self.makeEscortCoordinator(role: role, location: location) { sent += 1 }

            coordinator.updateOwnedOrder(orderID: 90, status: .inProgress)
            _ = await Self.waitUntil { coordinator.healthState == .preciseLocationOff(role) }
            _ = await Self.waitUntil(timeout: 0.3) { false }
            XCTAssertEqual(sent, 0, "\(role) 端：精确位置关着时一个点都不许发")

            location.simulatePreciseLocationOffForTesting(false)
            location.simulateDeviceLocationForTesting(
                CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737),
                capturedAt: Date(),
                horizontalAccuracy: 8
            )
            let resumed = await Self.waitUntil { sent > 0 }
            XCTAssertTrue(resumed, "\(role) 端：允许精确位置后应自动恢复上报")
            coordinator.reset()
            withExtendedLifetime(service) {}
        }
    }

    /// 用途键必须在 `Info.plist` 的 `NSLocationTemporaryUsageDescriptionDictionary` 里，否则系统不弹（SDK 原文）。
    /// 新加用途只改枚举、忘了 plist 的话，申请会静默什么都不发生。
    func testEveryPreciseLocationPurposeHasAnInfoPlistDescription() {
        let descriptions = Bundle.main.object(forInfoDictionaryKey: "NSLocationTemporaryUsageDescriptionDictionary") as? [String: String]
        for purpose in [PreciseLocationPurpose.bookingStartPoint, .escortRun, .escortVolunteer] {
            XCTAssertFalse(descriptions?[purpose.rawValue]?.isEmpty ?? true, "缺 \(purpose.rawValue) 的用途说明")
        }
    }

    // MARK: - Helpers

    private static func locationService(accuracy: Double?) -> LocationService {
        let location = LocationService()
        location.simulateDeviceLocationForTesting(
            CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737),
            capturedAt: Date(),
            horizontalAccuracy: accuracy
        )
        return location
    }

    /// 返回的 `WebSocketService` **必须由调用方攥着**：协调器对它是 `weak`，不攥着出函数即释放，
    /// 健康状态恒为 `networkDisconnected`、断网那条用例也会假绿（记忆 `location-service-test-seam-and-weak-viewmodel-deps`）。
    private static func makeEscortCoordinator(
        role: UserRole,
        location: LocationService,
        connected: Bool = true,
        onSend: @escaping @MainActor () -> Void = {}
    ) -> (LiveEscortSessionCoordinator, WebSocketService) {
        let coordinator = LiveEscortSessionCoordinator(
            realtimeCoordinator: AppRealtimeCoordinator(),
            reportInterval: 0.05,
            sendLocation: { _, _, _ in await onSend() }
        )
        let service = WebSocketService()
        service.simulateConnectionStateForTesting(connected ? .connected : .disconnected)
        coordinator.configure(identityKey: "account:\(role):token", role: role, webSocketService: service)
        coordinator.attachLocationService(location)
        return (coordinator, service)
    }

    /// 轮询到条件成立或超时。`{ false }` 当作「等一小段」用。
    private static func waitUntil(timeout: TimeInterval = 1, _ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return condition()
    }
}
