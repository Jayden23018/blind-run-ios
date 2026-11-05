import Foundation
import Speech

// 放在单独文件里是为了不让 `SpeechInputService.swift` 继续变长（SwiftLint 棘轮：文件与类体都已超上限）。
// 因此 `isApplicationActive`、`isCurrentRecognitionSession`、`markRecognitionStarted` 从 private 放宽成了模块内可见。
extension SpeechInputService {
    /// 授权拿到之后，最多等多久让 App 回到前台再开麦。超时照常开麦，与改动前的行为一致。
    static let foregroundWaitTimeout: TimeInterval = 2
    static let foregroundPollIntervalNanoseconds: UInt64 = 50_000_000

    func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    /// 两次授权都拿到之后，**等 App 回到前台再开麦**。
    ///
    /// 第一次用语音时会弹系统授权框。用户点「允许」时，授权回调常常比 App 回到前台更早到。
    /// 以前回调一到就开麦：这时 App 还是 `.inactive`，授权框还在收起，
    /// 在这个状态下打开录音会话与音频引擎，录音一开就断（2026-11-05 负责人真机报：
    /// 第一次点必失败，再点一次才行）。第二次点没有弹窗，App 全程在前台，所以正常。
    /// 等到前台再开麦，就让第一次和第二次走同一个状态。
    ///
    /// 同时也避开了 `RecognitionLifecyclePolicy` 的一个窗口：它在「`.inactive` 且正在听」时会停麦。
    /// 只要开麦落在前台之后，弹窗收起前后的 `.inactive` 就碰不到一个正在听的会话。
    ///
    /// 等待期间会话被作废（真进后台、用户换了输入框）就不开麦。超时照常开麦，不比改动前更糟。
    func startRecordingWhenApplicationIsActive(
        sessionID: UUID,
        field: SpeechInputField,
        start: () -> Void
    ) async {
        let deadline = Date().addingTimeInterval(Self.foregroundWaitTimeout)
        while !isApplicationActive(), Date() < deadline {
            try? await Task.sleep(nanoseconds: Self.foregroundPollIntervalNanoseconds)
            guard isCurrentRecognitionSession(sessionID, field: field) else { return }
        }
        guard isCurrentRecognitionSession(sessionID, field: field) else { return }
        start()
    }

    #if DEBUG
    /// 与生产路径共用 `startRecordingWhenApplicationIsActive`，只把真开麦换成 `markRecognitionStarted`。
    func simulateAuthorizationGrantedForTesting(sessionID: UUID, field: SpeechInputField) async {
        await startRecordingWhenApplicationIsActive(sessionID: sessionID, field: field) {
            self.markRecognitionStarted()
        }
    }
    #endif
}
