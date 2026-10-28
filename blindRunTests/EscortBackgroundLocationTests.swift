import CoreLocation
import XCTest
@testable import blindRun

/// 同行会话的后台定位档位（#523，OpenSpec `share-escort-location-in-background-from-departure`）。
/// 从 `LiveEscortTrackTests` 拆出（那个文件超了 SwiftLint 棘轮）。
final class EscortBackgroundLocationTests: XCTestCase {

    /// #523：出发起就允许后台继续共享（陪跑员会切去外部导航），增强精度只在跑步中；终态与换身份立即关。
    @MainActor
    func testSessionLifecycleSharesInBackgroundFromDepartureAndClearsOnTerminalOrIdentityChange() async {
        let realtime = AppRealtimeCoordinator()
        let coordinator = LiveEscortSessionCoordinator(realtimeCoordinator: realtime)
        let service = WebSocketService()
        let location = LocationService()
        coordinator.configure(identityKey: "account-a:blind:token", role: .blind, webSocketService: service)
        coordinator.attachLocationService(location)
        coordinator.updateOwnedOrder(orderID: 8, status: .driverEnRoute)
        await Task.yield()
        XCTAssertTrue(coordinator.isSessionEligible)
        // 🔴 复现 #523：出发后切去外部导航，本 App 进后台 —— 此前这一态不允许后台，位置共享就停了。
        let didShareInBackground = await waitUntil { location.escortLocationMode == .sharing }
        XCTAssertTrue(didShareInBackground, "出发后就要允许后台继续共享：\(location.escortLocationMode)")

        coordinator.updateOwnedOrder(orderID: 8, status: .inProgress)
        // 正向条件：轮询等待增强档位真正开启，避免固定 sleep 在负载抖动时提前断言
        let didEnableBackground = await waitUntil { location.escortLocationMode == .running }
        XCTAssertTrue(didEnableBackground, "进入 IN_PROGRESS 后应切到跑步的增强定位")
        let didSettleHealthState = await waitUntil {
            coordinator.healthState == .permissionRequired || coordinator.healthState == .networkDisconnected
        }
        XCTAssertTrue(didSettleHealthState, "健康状态应落在 permissionRequired 或 networkDisconnected")

        coordinator.updateOwnedOrder(orderID: 8, status: .completed)
        await Task.yield()
        XCTAssertNil(coordinator.activeOrderID)
        XCTAssertFalse(location.isEscortBackgroundModeEnabled)

        coordinator.updateOwnedOrder(orderID: 9, status: .driverArrived)
        coordinator.configure(identityKey: "account-b:blind:new-token", role: .blind, webSocketService: service)
        await Task.yield()
        XCTAssertNil(coordinator.activeOrderID)
    }

    @MainActor
    private func waitUntil(timeout: TimeInterval = 2, _ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return condition()
    }
}
