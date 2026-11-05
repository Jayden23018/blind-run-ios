import CoreLocation
import Foundation

extension VoiceOrderWizard {
    // MARK: Networking

    /// 整句解析。
    ///
    /// - Parameter current: 上一轮的槽位快照。整句轮传 nil（还没有「上一轮」），
    ///   确认轮传 `lastParsed?.slotSnapshot` —— 后端据此做「新抽到的覆盖、没抽到的继承」，
    ///   用户只说「时间改成九点」也能保住其余槽位。
    func parseOrderResponse(
        _ transcript: String,
        current: VoiceSlotSnapshot? = nil
    ) async throws -> ParseVoiceOrderResponse {
        guard let voiceOrderService else { throw WizardError.notConfigured }
        let body = parseRequest(transcript: transcript, current: current)
        return try await withParseTimeout {
            try await voiceOrderService.parseOrder(body)
        }
    }

    /// 带上当前坐标让后端走周边搜索做就近消歧。**拿不到真实定位就不带** —— 宁可退回正向编码，
    /// 也不能拿演示坐标去消歧，那会把人约到另一座城市。
    ///
    /// 两轮共用这一份：这条红线只该有一个出处，复制第二遍迟早有一边忘了判 `system`。
    private func parseRequest(
        transcript: String,
        current: VoiceSlotSnapshot?
    ) -> ParseVoiceOrderRequest {
        let sample = currentCoordinate?()
        let coordinate = sample?.system == .gcj02Backend ? sample?.coordinate : nil
        return ParseVoiceOrderRequest(
            transcript: transcript,
            latitude: coordinate?.latitude,
            longitude: coordinate?.longitude,
            current: current
        )
    }

    /// 给一次解析请求加超时。后端的模型兜底自己有 3 秒降级，这层防的是网络卡死 ——
    /// 没有它，向导会静默地永远停在「正在识别」，而盲人听不到任何提示。
    private func withParseTimeout<T: Sendable>(
        _ operation: @escaping @concurrent @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(Self.parseTimeout * 1_000_000_000))
                throw WizardError.parseTimedOut
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw WizardError.parseTimedOut }
            return result
        }
    }
}
