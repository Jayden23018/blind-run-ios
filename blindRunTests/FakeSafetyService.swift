import Foundation
@testable import blindRun

/// `SafetyServing` 的测试替身。规矩照抄 `FakeAuthService`：
///
/// 1. **不许含任何业务判定**（`if` / `switch` / 校验 / 状态机）。每个方法只做两件事：
///    记一笔调用、返回构造时注入的罐装值。
/// 2. **默认是失败而不是成功**：没打桩的方法抛 `NotStubbed`。
///
/// 这两条对求助这一片格外要紧：被替换掉的 `EmergencyAPIClientStub` 会按 path 分支决定返回什么，
/// 于是「这条链路在什么条件下才发请求」这个判定同时存在于被测代码和替身里 ——
/// 而它正是 `AGENTS.md` §6 那几条红线本身。
final class FakeSafetyService: SafetyServing, @unchecked Sendable {

    struct NotStubbed: Error, CustomStringConvertible {
        let method: String
        var description: String { "FakeSafetyService.\(method) 没有打桩" }
    }

    /// 调用顺序，元素是 `#function`（如 `"triggerEmergency(_:)"`）。
    /// 「一次双击只准发一条求助」这类断言读的就是它的长度。
    private(set) var calls: [String] = []

    var triggerEmergencyResult: Result<EmergencyTriggerResponse, Error> = .failure(NotStubbed(method: "triggerEmergency"))
    var activeEmergencyResult: Result<EmergencyActiveEnvelope, Error> = .failure(NotStubbed(method: "activeEmergency"))
    var cancelEmergencyResult: Result<EmergencyCancelResponse, Error> = .failure(NotStubbed(method: "cancelEmergencyByOwner"))
    var acknowledgeEmergencyResult: Result<VolunteerEmergencyAcknowledgement, Error> = .failure(NotStubbed(method: "acknowledgeEmergencyAsVolunteer"))
    var introCallResult: Result<IntroCallView, Error> = .failure(NotStubbed(method: "introCall"))
    var submitIntroCallDecisionResult: Result<Void, Error> = .success(())
    var reportIntroCallUnreachableResult: Result<Void, Error> = .success(())
    /// `.failure` = 订单详情读不到（通话磨合期后端对志愿者就是 403）。
    var matchedOrderResult: Result<OrderDetailResponse, Error> = .failure(NotStubbed(method: "matchedOrder"))
    var orderTrackResult: Result<OrderTrackResponse, Error> = .failure(NotStubbed(method: "orderTrack"))

    /// 每次 `triggerEmergency` 之前多睡这么久。制造「请求在飞、第二次点击进来了」的窗口用。
    var triggerDelayNanoseconds: UInt64 = 0

    /// 最后一次收到的参数。断言「传下去的是哪个值」用，不参与任何判定。
    private(set) var lastTriggerRequest: EmergencyTriggerRequest?
    private(set) var lastEventId: Int64?
    private(set) var lastOrderId: Int64?
    private(set) var lastIntroCallDecision: IntroCallDecision?
    /// 全部 orderId 的到达顺序，`introCall` / `matchedOrder` / `orderTrack` 共用。
    private(set) var orderIds: [Int64] = []

    private func record(_ method: String = #function) {
        calls.append(method)
    }

    func triggerEmergency(_ request: EmergencyTriggerRequest) async throws -> EmergencyTriggerResponse {
        record()
        lastTriggerRequest = request
        if triggerDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: triggerDelayNanoseconds)
        }
        return try triggerEmergencyResult.get()
    }

    func activeEmergency() async throws -> EmergencyActiveEnvelope {
        record()
        return try activeEmergencyResult.get()
    }

    func cancelEmergencyByOwner(eventId: Int64) async throws -> EmergencyCancelResponse {
        record()
        lastEventId = eventId
        return try cancelEmergencyResult.get()
    }

    func acknowledgeEmergencyAsVolunteer(eventId: Int64) async throws -> VolunteerEmergencyAcknowledgement {
        record()
        lastEventId = eventId
        return try acknowledgeEmergencyResult.get()
    }

    func introCall(orderId: Int64) async throws -> IntroCallView {
        record()
        lastOrderId = orderId
        orderIds.append(orderId)
        return try introCallResult.get()
    }

    func submitIntroCallDecision(orderId: Int64, decision: IntroCallDecision) async throws {
        record()
        lastOrderId = orderId
        lastIntroCallDecision = decision
        orderIds.append(orderId)
        return try submitIntroCallDecisionResult.get()
    }

    func reportIntroCallUnreachable(orderId: Int64) async throws {
        record()
        lastOrderId = orderId
        orderIds.append(orderId)
        return try reportIntroCallUnreachableResult.get()
    }

    func matchedOrder(orderId: Int64) async throws -> OrderDetailResponse {
        record()
        lastOrderId = orderId
        orderIds.append(orderId)
        return try matchedOrderResult.get()
    }

    func orderTrack(orderId: Int64) async throws -> OrderTrackResponse {
        record()
        lastOrderId = orderId
        orderIds.append(orderId)
        return try orderTrackResult.get()
    }
}
