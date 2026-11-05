import Combine
import CoreLocation
import XCTest
@testable import blindRun

@MainActor
final class EmergencySOSReconciliationTests: XCTestCase, EmergencySOSTestSupport {

    // MARK: - 发送失败后的对账（阶段 4）

    /// 🔴 **一个会说谎的失败**：请求在服务端处理完了、响应在回程丢了（弱网、切基站、
    /// 后台挂起），客户端只看见 `网络异常`。那一刻屏幕上写着「求助未发出」，
    /// 而家属的短信其实已经在路上 —— 盲人会据此以为没人知道他出事了。
    ///
    /// 修法是**去问一句**，不是重发：`GET /api/emergency/active` 按契约原文是
    /// 「事件 id 与当前状态的唯一权威来源」，而且是只读的。
    @MainActor
    func testFailedSendAsksTheBackendWhetherItActuallyLanded() async {
        let safety = FakeSafetyService()
        safety.triggerEmergencyResult = .failure(URLError(.networkConnectionLost))
        // 后端其实收到了：事件真的存在。
        safety.activeEmergencyResult = .success(Self.openEventEnvelope(id: 808))
        let coordinator = Self.makeRecoverableCoordinator(safety: safety)

        let outcome = await coordinator.trigger(
            order: Self.makeOrder(status: .inProgress),
            role: .blind,
            userID: 7,
            safety: safety,
            locate: { Self.coordinate(latitude: 39.915, longitude: 116.404) }
        )

        XCTAssertEqual(coordinator.activeEvent?.eventID, 808)
        XCTAssertFalse(outcome.isFailure, "求助其实已经生效，界面却还在说「未发出」")
        XCTAssertFalse(outcome.message.contains("未发出"))
    }

    /// 429 冷却是**最强的一条「刚才那条真的发出去了」的证据**：后端按触发者 SETNX 占位，
    /// 命中它几乎只可能是我们自己刚刚那一条占的。
    ///
    /// 不对账的话用户听到的是「刚刚已经发送过求助，请 42 秒后再试」——
    /// 那句话听起来像被拒绝，而实际上求助正在生效。
    @MainActor
    func testCooldownIsReconciledIntoAnActiveEmergencyNotARejection() async {
        let safety = FakeSafetyService()
        safety.triggerEmergencyResult = .failure(
            APIError.rateLimited(RateLimitInfo(message: "刚刚已经发送过求助", retryAfterSeconds: 42))
        )
        safety.activeEmergencyResult = .success(Self.openEventEnvelope(id: 809))
        let coordinator = Self.makeRecoverableCoordinator(safety: safety)

        let outcome = await coordinator.trigger(
            order: Self.makeOrder(status: .inProgress),
            role: .blind,
            userID: 7,
            safety: safety,
            locate: { Self.coordinate(latitude: 39.915, longitude: 116.404) }
        )

        XCTAssertEqual(coordinator.activeEvent?.eventID, 809)
        XCTAssertFalse(outcome.isFailure)
        XCTAssertFalse(outcome.message.contains("秒后再试"))
    }

    /// 反向锁：**对账不许制造救援状态**。
    ///
    /// 后端说没有未结束的事件（或这一侧压根没有查询权限，比如志愿者），
    /// 失败就还是失败 —— 屏幕上必须留着「未发出」和那个拨 120 的入口。
    /// 这条比上面两条更要紧：上面两条错了是少说一句，这条错了是**把没发出的求助说成发出了**。
    @MainActor
    func testReconciliationNeverInventsRescueStateWhenNothingIsOpen() async {
        for activeResult in [
            Result<EmergencyActiveEnvelope, Error>.success(
                EmergencyActiveEnvelope(success: true, data: nil)
            ),
            // 查询本身也失败（断网时这才是最常见的情形）。
            .failure(URLError(.notConnectedToInternet)),
        ] {
            let safety = FakeSafetyService()
            safety.triggerEmergencyResult = .failure(URLError(.networkConnectionLost))
            safety.activeEmergencyResult = activeResult
            let coordinator = Self.makeRecoverableCoordinator(safety: safety)

            let outcome = await coordinator.trigger(
                order: Self.makeOrder(status: .inProgress),
                role: .blind,
                userID: 7,
                safety: safety,
                locate: { Self.coordinate(latitude: 39.915, longitude: 116.404) }
            )

            XCTAssertNil(coordinator.activeEvent, "后端没有未结束的事件，却造出了一个")
            XCTAssertTrue(outcome.isFailure, "求助没发出去，界面却不再说「未发出」")
            XCTAssertTrue(coordinator.state.isFailure, "失败态没保住，拨 120 的入口会跟着消失")
        }
    }

    /// 🔴 **手里还攥着一个旧事件、而新的这次发送失败了。**
    ///
    /// 这是本组里唯一一条真正会出事的路径，也是上面那条用例**盖不住**的：
    /// 对账发现后端其实已经没有未结束的事件（旧的被客服解除了），于是它会
    /// 顺手把本地那个陈旧事件清掉、状态归 `.idle` —— 而 `.idle` 的 `message` 是 `nil`。
    ///
    /// 如果这时候直接把「对账之后的状态」当成结果返回，用户按下求助之后
    /// **屏幕上什么都不会多出来、耳朵里也一个字都听不到**：既没有「未发出」，
    /// 也没有那个拨 120 的入口。对看不见屏幕的人，这与「按了没反应」不可区分。
    ///
    /// 2026-09-15 验红时发现：把 `reconcile` 里那道 `guard activeEvent != nil` 去掉，
    /// 上面那条用例照样绿 —— 它从一个干净的 coordinator 出发，走不到这条分支。
    /// 这条用例就是为补那个洞写的。
    @MainActor
    func testFailureIsStillAnnouncedEvenWhenReconciliationClearsAStaleEvent() async {
        let safety = FakeSafetyService()
        let coordinator = Self.makeRecoverableCoordinator(safety: safety)

        // 先制造一个「手里攥着旧事件」的现实状态：上一次求助成功过。
        safety.triggerEmergencyResult = .success(
            EmergencyTriggerResponse(success: true, eventId: 700, status: "CONTACT_NOTIFIED")
        )
        _ = await coordinator.trigger(
            order: Self.makeOrder(status: .inProgress),
            role: .blind,
            userID: 7,
            safety: safety,
            locate: { Self.coordinate(latitude: 39.915, longitude: 116.404) }
        )
        XCTAssertEqual(coordinator.activeEvent?.eventID, 700)

        // 现在：旧事件已被客服解除（后端说没有未结束的），而新的这次发送失败了。
        safety.triggerEmergencyResult = .failure(URLError(.networkConnectionLost))
        safety.activeEmergencyResult = .success(EmergencyActiveEnvelope(success: true, data: nil))

        let outcome = await coordinator.trigger(
            order: Self.makeOrder(status: .inProgress),
            role: .blind,
            userID: 7,
            safety: safety,
            locate: { Self.coordinate(latitude: 39.915, longitude: 116.404) }
        )

        XCTAssertNil(coordinator.activeEvent, "陈旧事件没被清掉，界面会顶着一个早就结束的求助")
        XCTAssertTrue(outcome.isFailure, "新的这次发送失败了，却没有作为失败播报出去")
        XCTAssertFalse(
            outcome.message.isEmpty,
            "按下求助之后一个字都没说 —— 对看不见屏幕的人，这与「按了没反应」不可区分"
        )
        XCTAssertTrue(outcome.message.contains("未发出"))
    }

    /// 对账**只在失败路径上发生**。成功那条不许多打一次查询 ——
    /// 触发响应里已经带了 `eventId` 和状态，再查一次是纯浪费，而这条链路上每一次
    /// 往返都发生在一个人正在出事的时候。
    @MainActor
    func testSuccessfulSendDoesNotPayForAnExtraQuery() async {
        let safety = FakeSafetyService()
        safety.triggerEmergencyResult = .success(
            EmergencyTriggerResponse(success: true, eventId: 810, status: "CONTACT_NOTIFIED")
        )
        let coordinator = Self.makeRecoverableCoordinator(safety: safety)

        _ = await coordinator.trigger(
            order: Self.makeOrder(status: .inProgress),
            role: .blind,
            userID: 7,
            safety: safety,
            locate: { Self.coordinate(latitude: 39.915, longitude: 116.404) }
        )

        XCTAssertEqual(safety.calls, ["triggerEmergency(_:)"])
    }


    /// 用**解码**造 fixture，不用逐字段构造。
    ///
    /// 这个类型的字段是后端契约的形状（`status` 还刻意是 `String` 而不是枚举，
    /// 见它自己的注释），逐字段写死会在后端加字段时全线红 ——
    /// 而那种红说明不了任何事，只会让下一个人把用例改成将就。
    private static func openEventEnvelope(id: Int64) -> EmergencyActiveEnvelope {
        let json = """
        {"success":true,"code":200,"data":{
          "id":\(id),"orderId":4242,"userId":7,
          "triggeredAt":"2026-09-15T14:30:00","triggerType":"BUTTON",
          "status":"CONTACT_NOTIFIED","hasGpsLocation":true}}
        """
        // swiftlint:disable:next force_try 桩数据解不出说明这条用例本身写坏了，该当场炸。
        return try! APIPayloadDecoder.decodePayload(
            EmergencyActiveEnvelope.self,
            from: Data(json.utf8),
            decoder: JSONDecoder()
        )
    }
}
