import XCTest
@testable import blindRun

/// 「有人查看了你的行程分享」（后端 SPEC-D D4，新 eventType `SHARE_LINK_VIEWED`）。
///
/// **这一条在 iOS 侧不需要新代码 —— 但正因为不需要，它才必须有测试。**
///
/// `WSAppNotification.eventType` 是 `String` 而不是闭合枚举，未知取值既不会解码失败，
/// 也不会被 `shouldSuppressLifecycleNotification` 抑制（`lifecycleStatus` 返回 `nil` ⇒ 不抑制），
/// 于是它自然走到横幅 + 播报。这套「默认放行」的设计是有意的，但它没有任何东西钉着 ——
/// 哪天有人把 `eventType` 收成闭合枚举、或者把未知类型的默认方向改成抑制，
/// 盲人这一侧就静默地不再被告知有人在看他的位置，而**没有任何测试会红**。
///
/// 这条通知的价值恰恰在于它是**播报**：盲人看不见横幅，但能被告知「有人在看着你」
/// （Lyft 官方原文：`You'll receive a notification when someone clicks the link to follow your ride.`）。
/// 做成一条静默的横幅等于没做。
///
/// ⚠️ **边界**：真正调 `speechService.speak` 的是 `ContentView.swift:365`
/// （`.onReceive(...$currentNotification)`）。这里能钉到的是「`currentNotification` 被填上
/// 且 `speechText` 非空」——播报链路的最后一跳在视图层，由 UI 测试与真机验证覆盖。
@MainActor
final class ShareLinkViewedNotificationTests: XCTestCase {

    /// 回归门：未知 eventType 不许被抑制，必须成为当前通知并带上可播报文本。
    func testShareLinkViewedReachesTheSpokenNotificationChannel() async {
        let coordinator = AppRealtimeCoordinator(notificationDuration: 60)
        let service = WebSocketService()
        coordinator.attach(to: service, role: .blind)

        service.simulateIncomingEventForTesting(.notification(makeShareLinkViewed()))
        await Task.yield()

        XCTAssertEqual(coordinator.currentNotification?.displayText, "有人查看了你的行程分享")
        XCTAssertEqual(
            coordinator.currentNotification?.speechText,
            "有人查看了你的行程分享",
            "speechText 为空 = 盲人这一侧只剩一条看不见的横幅"
        )
    }

    /// 没有 `ttsText` 时必须回落到 `body`，而不是留空。
    /// 后端模板不一定填 `ttsText`，而这条通知的全部价值就在播报上。
    func testMissingTtsTextFallsBackToBodySoItIsStillSpoken() async {
        let coordinator = AppRealtimeCoordinator(notificationDuration: 60)
        let service = WebSocketService()
        coordinator.attach(to: service, role: .blind)

        service.simulateIncomingEventForTesting(.notification(makeShareLinkViewed(ttsText: nil)))
        await Task.yield()

        XCTAssertEqual(coordinator.currentNotification?.speechText, "有人查看了你的行程分享")
    }

    /// 它是**信息性**通知，不是安全事件：不得进求助那条链路。
    /// 进了的话界面会当成安全事件渲染（`isSafetyEvent` 影响队列裁剪与展示），
    /// 而「有人点开了链接」既不改订单状态，也不证明出了任何事。
    func testShareLinkViewedIsNotTreatedAsASafetyEvent() async {
        let coordinator = AppRealtimeCoordinator(notificationDuration: 60)
        let service = WebSocketService()
        coordinator.attach(to: service, role: .blind)

        service.simulateIncomingEventForTesting(.notification(makeShareLinkViewed()))
        await Task.yield()

        XCTAssertEqual(coordinator.currentNotification?.isSafetyEvent, false)
        XCTAssertNil(AppRealtimeCoordinator.emergencyKind(forEventType: "SHARE_LINK_VIEWED"))
    }

    /// 未知 eventType 一律不抑制 —— 这是 `shouldSuppressLifecycleNotification` 有意的默认方向。
    /// 直接钉住判定函数，而不只是钉住上面那条端到端用例：默认方向被反过来时，
    /// 挂掉的会是这一条，错误信息也指得更准。
    func testUnknownEventTypeIsNotALifecycleTemplate() {
        XCTAssertNil(AppRealtimeCoordinator.lifecycleStatus(forEventType: "SHARE_LINK_VIEWED"))
    }

    /// 后端每个令牌只推首次（SPEC-D §D4.3），所以客户端不需要自己去重。
    /// 但客户端的去重窗口不能把它**额外**吃掉：真出现两条（令牌撤销后重新生成算新令牌），
    /// 那是两次不同的查看，都该播。这里钉住「不同 messageId 各播一次」。
    func testTwoDistinctTokensEachAnnounceOnce() async {
        let coordinator = AppRealtimeCoordinator(notificationDuration: 60)
        let service = WebSocketService()
        coordinator.attach(to: service, role: .blind)

        service.simulateIncomingEventForTesting(.notification(makeShareLinkViewed(messageID: "m-1")))
        await Task.yield()
        XCTAssertNotNil(coordinator.currentNotification)
        coordinator.dismissCurrentNotification()

        service.simulateIncomingEventForTesting(.notification(makeShareLinkViewed(messageID: "m-2")))
        await Task.yield()
        XCTAssertEqual(coordinator.currentNotification?.displayText, "有人查看了你的行程分享")
    }

    /// 文案**不能说是谁在看** —— 令牌不绑身份，后端也不知道（SPEC-D §D4.3）。
    /// 这条钉的是我们不去给它加工：客户端只能原样呈现后端 body，不许拼一个「你的家人」。
    func testCopyNeverNamesTheViewer() async {
        let coordinator = AppRealtimeCoordinator(notificationDuration: 60)
        let service = WebSocketService()
        coordinator.attach(to: service, role: .blind)

        service.simulateIncomingEventForTesting(.notification(makeShareLinkViewed()))
        await Task.yield()

        let spoken = coordinator.currentNotification?.speechText ?? ""
        for claim in ["家人", "家属", "紧急联系人", "已通知"] {
            XCTAssertFalse(spoken.contains(claim), "不得声称是谁在看：\(claim)")
        }
    }

    private func makeShareLinkViewed(
        messageID: String = "share-viewed-1",
        ttsText: String? = "有人查看了你的行程分享"
    ) -> WSAppNotification {
        WSAppNotification(
            type: WSMessageType.appNotification.rawValue,
            eventId: nil,
            messageId: messageID,
            eventType: "SHARE_LINK_VIEWED",
            title: "行程分享",
            body: "有人查看了你的行程分享",
            ttsText: ttsText,
            priority: "NORMAL",
            timestamp: "2026-08-13T12:00:00Z"
        )
    }
}
