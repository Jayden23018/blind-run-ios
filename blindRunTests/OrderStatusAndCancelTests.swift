import XCTest
import AMapSearchKit
import AVFAudio
import CoreLocation
import SwiftUI
@testable import blindRun

@MainActor
final class OrderStatusAndCancelTests: XCTestCase, BlindRunTestSupport {
    func testBlindRunnerEmergencyIsAvailableOnlyInProgress() {
        for status in RunOrderStatus.allCases {
            XCTAssertEqual(
                status.canTriggerEmergency(as: .blind),
                status == .inProgress,
                "blind SOS eligibility is wrong for \(status.rawValue)"
            )
        }
    }

    // 已删除 `testVolunteerEmergencyStaysHiddenInEveryStatus`：它断言志愿者 SOS 入口在**所有**状态下都关闭，
    // 而 2026-07-31 后端改为按订单参与方归属事件后该入口已在 `IN_PROGRESS` 打开（commit ecea28b），
    // 这条断言从那时起就是红的。现行门槛由
    // `EmergencySOSTruthfulnessTests.testVolunteerEmergencyEntryIsEnabledOnlyDuringService` 覆盖。

    func testUnsetRoleCannotTriggerEmergency() {
        XCTAssertFalse(RunOrderStatus.inProgress.canTriggerEmergency(as: .unset))
    }

    func testEmergencyConfirmationCopyIsFixed() {
        XCTAssertEqual(
            EmergencySafetyCopy.confirmationMessage,
            "是否确认进入求助状态？确认后，本次服务将标记为异常，系统会记录当前订单状态。"
        )
    }

    func testBlindOrderPollingUsesFiveSecondsAndStopsOnTerminalStates() {
        XCTAssertEqual(AppConstants.Timing.orderPollingInterval, 5.0)
        XCTAssertTrue(RunOrderStatus.pendingMatch.shouldPoll)
        XCTAssertTrue(RunOrderStatus.pendingAccept.shouldPoll)
        XCTAssertTrue(RunOrderStatus.driverEnRoute.shouldPoll)
        XCTAssertTrue(RunOrderStatus.driverArrived.shouldPoll)
        XCTAssertTrue(RunOrderStatus.inProgress.shouldPoll)
        XCTAssertTrue(RunOrderStatus.rematching.shouldPoll)
        XCTAssertFalse(RunOrderStatus.completed.shouldPoll)
        XCTAssertFalse(RunOrderStatus.cancelled.shouldPoll)
        XCTAssertFalse(RunOrderStatus.noVolunteer.shouldPoll)
    }

    func testRematchingCopyKeepsBlindRunnerInStableWaitingState() {
        XCTAssertEqual(
            RunOrderStatus.rematching.blindRunnerDescription,
            "正在确认陪跑员状态，请稍候。"
        )
        XCTAssertEqual(RunOrderStatus.rematching.blindRunnerAnnouncement, "正在确认陪跑员状态，请稍候。")
        XCTAssertEqual(VoiceService.statusAnnouncement(for: .rematching), "正在确认陪跑员状态，请稍候。")
    }

    /// `NO_VOLUNTEER` 是**终态** —— 后端派单彻底失败时订单已经是
    /// `NO_VOLUNTEER` + `cancelledBy=SYSTEM`，这一单结束了。三处盲人侧文案都必须说出这件事
    /// 并给出出路，且不得再出现「稍后再试」这类暗示还能等的话。
    /// 对看不见屏幕的人，「被告知继续等一件已经结束的事」是事故，不是措辞问题。
    ///
    /// ⚠️ **后端的正确文案救不了这里。** 后端 2026-08-19 已把终态通知换成
    /// `ORDER_AUTO_CANCELLED`（「暂未匹配到志愿者，订单已取消，您可以稍后重新发起」），
    /// 但 `AppRealtimeCoordinator.shouldSuppressLifecycleNotification` 在有活跃订单时
    /// 把所有能映射到订单状态的模板通知整条抑制，而派单失败时盲人**必然**有活跃订单 ——
    /// 用户实际听到的只会是下面这三句。详见后端 handoff 2026-08-19 的 N98。
    ///
    /// 断言的是不变式而不是字面量：换个说法不该让这条红，退回「还能等」才该红。
    func testNoVolunteerCopySaysTheOrderEndedInsteadOfAskingToKeepWaiting() {
        let copies = [
            "blindRunnerDescription": RunOrderStatus.noVolunteer.blindRunnerDescription,
            "blindRunnerAnnouncement": RunOrderStatus.noVolunteer.blindRunnerAnnouncement,
            "statusAnnouncement": VoiceService.statusAnnouncement(for: .noVolunteer)
        ]

        for (name, copy) in copies {
            XCTAssertTrue(copy.contains("已取消"), "\(name) 没说出此订单已经结束：\(copy)")
            // 出路也要给：终态只说「结束了」而不说能怎么办，等于把人留在原地。
            XCTAssertTrue(copy.contains("重新发起"), "\(name) 没给出「可以重新发起」这条出路：\(copy)")
            for misleading in ["稍后再试", "稍后重试", "请稍候", "暂时"] {
                XCTAssertFalse(
                    copy.contains(misleading),
                    "\(name) 仍在暗示此订单还能等（「\(misleading)」）：\(copy)"
                )
            }
        }
    }

    func testOrderStatusTerminalStates() {
        XCTAssertTrue(RunOrderStatus.completed.isTerminal)
        XCTAssertTrue(RunOrderStatus.cancelled.isTerminal)
        XCTAssertTrue(RunOrderStatus.noVolunteer.isTerminal)
        XCTAssertFalse(RunOrderStatus.pendingMatch.isTerminal)
        XCTAssertFalse(RunOrderStatus.inProgress.isTerminal)
    }

    func testOrderStatusCancelability() {
        XCTAssertEqual(RunOrderStatus.pendingAccept.displayName, "待出发")

        XCTAssertTrue(RunOrderStatus.pendingMatch.canCancel)
        XCTAssertTrue(RunOrderStatus.pendingAccept.canCancel)
        XCTAssertTrue(RunOrderStatus.rematching.canCancel)
        XCTAssertFalse(RunOrderStatus.inProgress.canCancel)
        XCTAssertFalse(RunOrderStatus.completed.canCancel)
        XCTAssertFalse(RunOrderStatus.cancelled.canCancel)

        XCTAssertTrue(RunOrderStatus.pendingMatch.canBlindRunnerCancel)
        XCTAssertTrue(RunOrderStatus.pendingAccept.canBlindRunnerCancel)
        XCTAssertTrue(RunOrderStatus.rematching.canBlindRunnerCancel)
        XCTAssertFalse(RunOrderStatus.driverEnRoute.canBlindRunnerCancel)
        XCTAssertFalse(RunOrderStatus.driverArrived.canBlindRunnerCancel)
        XCTAssertFalse(RunOrderStatus.inProgress.canBlindRunnerCancel)

        XCTAssertTrue(RunOrderStatus.pendingAccept.canVolunteerCancel)
        XCTAssertTrue(RunOrderStatus.driverEnRoute.canVolunteerCancel)
        XCTAssertTrue(RunOrderStatus.driverArrived.canVolunteerCancel)
        XCTAssertTrue(RunOrderStatus.inProgress.canVolunteerCancel)
        XCTAssertFalse(RunOrderStatus.pendingMatch.canVolunteerCancel)
        XCTAssertFalse(RunOrderStatus.rematching.canVolunteerCancel)
        XCTAssertFalse(RunOrderStatus.completed.canVolunteerCancel)
        XCTAssertFalse(RunOrderStatus.cancelled.canVolunteerCancel)
        XCTAssertFalse(RunOrderStatus.noVolunteer.canVolunteerCancel)

        XCTAssertTrue(RunOrderStatus.pendingAccept.canCancel(as: .blind))
        XCTAssertTrue(RunOrderStatus.pendingAccept.canCancel(as: .volunteer))
        XCTAssertTrue(RunOrderStatus.rematching.canCancel(as: .blind))
        XCTAssertFalse(RunOrderStatus.rematching.canCancel(as: .volunteer))
        XCTAssertFalse(RunOrderStatus.inProgress.canCancel(as: .blind))
        XCTAssertTrue(RunOrderStatus.inProgress.canCancel(as: .volunteer))
        XCTAssertFalse(RunOrderStatus.pendingAccept.canCancel(as: .unset))
    }

    func testMockCancelUsesRoleSpecificBackendContract() async throws {
        do {
            let appState = AppState()
            appState.currentEnvironment = .mock
            let client = appState.apiClient
            let _: EmptyResponse = try await client.post(
                "/api/orders/1/respond",
                body: OrderRespondRequest(action: .accept)
            )
            try await setMockRole(.blind, appState: appState)

            let _: EmptyResponse = try await client.post("/api/orders/1/cancel")
            let detail: OrderDetailResponse = try await client.get("/api/orders/1")

            XCTAssertEqual(detail.status, .cancelled)
        }

        do {
            let appState = AppState()
            appState.currentEnvironment = .mock
            let client = appState.apiClient
            let _: EmptyResponse = try await client.post(
                "/api/orders/1/respond",
                body: OrderRespondRequest(action: .accept)
            )
            try await setMockRole(.volunteer, appState: appState)

            let _: EmptyResponse = try await client.post("/api/orders/1/cancel")
            let rematchingDetail: OrderDetailResponse = try await client.get("/api/orders/1")
            XCTAssertEqual(rematchingDetail.status, .rematching)

            try await setMockRole(.blind, appState: appState)
            let _: EmptyResponse = try await client.post("/api/orders/1/cancel")
            let cancelledDetail: OrderDetailResponse = try await client.get("/api/orders/1")
            XCTAssertEqual(cancelledDetail.status, .cancelled)
        }
    }

    func testMockCancelUsesAppStateRoleWithoutRoleEndpoint() async throws {
        do {
            let appState = AppState()
            appState.currentEnvironment = .mock
            appState.activeRole = .blind
            let client = appState.apiClient

            let _: EmptyResponse = try await client.post("/api/orders/1/cancel")
            let detail: OrderDetailResponse = try await client.get("/api/orders/1")

            XCTAssertEqual(detail.status, .cancelled)
        }

        do {
            let appState = AppState()
            appState.currentEnvironment = .mock
            appState.activeRole = .volunteer
            let client = appState.apiClient
            let _: EmptyResponse = try await client.post(
                "/api/orders/1/respond",
                body: OrderRespondRequest(action: .accept)
            )

            let _: EmptyResponse = try await client.post("/api/orders/1/cancel")
            let detail: OrderDetailResponse = try await client.get("/api/orders/1")

            XCTAssertEqual(detail.status, .rematching)
        }
    }

    func testMockVolunteerCancelMovesActiveServiceStatesToRematching() async throws {
        for status in [RunOrderStatus.driverEnRoute, .driverArrived, .inProgress] {
            let appState = AppState()
            appState.currentEnvironment = .mock
            let client = appState.apiClient
            try await setMockRole(.volunteer, appState: appState)
            let _: EmptyResponse = try await client.post(
                "/api/orders/1/respond",
                body: OrderRespondRequest(action: .accept)
            )
            if [.driverEnRoute, .driverArrived, .inProgress].contains(status) {
                let _: EmptyResponse = try await client.post("/api/orders/1/en-route")
            }
            if [.driverArrived, .inProgress].contains(status) {
                let _: EmptyResponse = try await client.post("/api/orders/1/arrived")
            }
            if status == .inProgress {
                let _: EmptyResponse = try await client.post("/api/orders/1/start-service")
            }

            let beforeCancel: OrderDetailResponse = try await client.get("/api/orders/1")
            XCTAssertEqual(beforeCancel.status, status)

            let _: EmptyResponse = try await client.post("/api/orders/1/cancel")
            let afterCancel: OrderDetailResponse = try await client.get("/api/orders/1")
            XCTAssertEqual(afterCancel.status, .rematching)
        }
    }

    func testPendingAcceptBlindCopyUsesDepartureLanguageAndOrderDetails() {
        let order = makeOrder(orderId: 1, status: .pendingAccept)
        let announcement = order.blindRunnerAnnouncement()

        XCTAssertEqual(RunOrderStatus.pendingAccept.blindRunnerDescription, "陪跑员已接单，请按预约时间前往或等待在出发地点。")
        XCTAssertTrue(announcement.contains("陪跑员已接单"))
        XCTAssertTrue(announcement.contains("朝阳公园南门"))
        XCTAssertTrue(announcement.contains("陪跑员出发后会继续通知你"))
        XCTAssertFalse(announcement.contains("待确认"))
    }

    func testDisplayDateTimeFormatsBackendLocalDateTimeForSpeech() {
        XCTAssertEqual("2026-07-05T15:18:10".displayDateTime, "2026年7月5日 15:18")
    }

    /// 后端 `LocalDateTime` 取自 `now()` 时带小数秒（handoff 2026-08-04 实测
    /// `2026-08-04T11:40:42.644571`），下单回执的 `createdAt` 必带。解不出时 `displayDateTime`
    /// 会原样返回，等于把一串 ISO 时间念给盲人听。
    func testDisplayDateTimeAcceptsFractionalSecondsFromBackendNow() {
        XCTAssertEqual("2026-08-04T11:40:42.644571".displayDateTime, "2026年8月4日 11:40")
        XCTAssertEqual("2026-08-04T11:40:42.6".displayDateTime, "2026年8月4日 11:40")
        XCTAssertEqual("2026-08-04T11:40:42".backendLocalDate, "2026-08-04T11:40:42.644571".backendLocalDate)
    }

    /// 截小数秒只对无时区串成立。带偏移的串必须落到 ISO8601 分支，否则会被当成本地时间、差好几个小时。
    func testFractionalSecondTruncationDoesNotSwallowTimeZoneOffsets() throws {
        XCTAssertNil("2026-08-04T11:40:42.644+08:00".backendLocalDate)
        XCTAssertNil("2026-08-04T11:40:42.644Z".backendLocalDate)

        let utc = try XCTUnwrap(ISO8601DateFormatter.aidRunFormatter.date(from: "2026-08-04T11:40:42.644Z"))
        XCTAssertEqual(
            "2026-08-04T11:40:42.644Z".displayDateTime,
            DateFormatter.aidRunDisplayDateTime.string(from: utc)
        )
    }
}
