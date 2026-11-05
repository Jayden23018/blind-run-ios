import XCTest
import AMapSearchKit
import AVFAudio
import CoreLocation
import SwiftUI
@testable import blindRun

@MainActor
final class SpeechInputLifecycleTests: XCTestCase {
    /// 授权被拒是**启动阶段**失败，走的是 `clearRecognitionStartState` 而不是 `stopAudioRecognition`。
    /// 调用方（语音下单向导）只能靠这一次完成回调发现语音这条路断了：看不见屏幕的人没有别的方式
    /// 察觉向导已经停住，漏掉这次回调等于让向导无限静默等待。
    func testAuthorizationDenialDeliversATerminalCompletion() {
        let service = SpeechInputService()
        var completions: [SpeechInputCompletion] = []

        service.startPendingAuthorizationForTesting(field: .voiceOrderStartPlace) {
            completions.append($0)
        }
        service.denyAuthorizationForTesting()

        XCTAssertEqual(completions.count, 1, "启动阶段失败必须送出一次终局完成，否则调用方永远等不到结果")
        XCTAssertEqual(completions.first?.field, .voiceOrderStartPlace)
        XCTAssertEqual(completions.first?.reason, .error)
        XCTAssertEqual(completions.first?.recognizedText, "")
        XCTAssertEqual(service.lastStopReason, .error)
        XCTAssertNil(service.activeFieldId)
    }

    func testAuthorizationDenialCompletionIsDeliveredOnlyOnce() {
        let service = SpeechInputService()
        var completions: [SpeechInputCompletion] = []

        service.startPendingAuthorizationForTesting(field: .voiceOrderStartPlace) {
            completions.append($0)
        }
        service.denyAuthorizationForTesting()
        service.denyAuthorizationForTesting()

        XCTAssertEqual(completions.count, 1, "重复清理不得再送一次完成或再播报一次")
    }

    func testSpeechInputLifecycleCancelClearsStateWithoutCompletion() {
        let service = SpeechInputService()
        var completion: SpeechInputCompletion?

        service.startRecognitionForTesting(field: .startPlaceSearch) {
            completion = $0
        }
        service.cancelRecognitionForLifecycle()

        XCTAssertFalse(service.isListening)
        XCTAssertNil(service.activeFieldId)
        XCTAssertEqual(service.lastStopReason, .manual)
        XCTAssertNil(completion)

        service.startRecognitionForTesting(field: .startPlaceSearch) {
            completion = $0
        }
        service.finishRecognitionForTesting(text: "大观楼")

        XCTAssertEqual(completion?.field, .startPlaceSearch)
        XCTAssertEqual(completion?.recognizedText, "大观楼")
        XCTAssertEqual(completion?.reason, .finalResult)
    }

    func testSpeechInputLifecycleCancelInvalidatesPendingAuthorizationSession() {
        let service = SpeechInputService()
        var completion: SpeechInputCompletion?

        let staleSession = service.startPendingAuthorizationForTesting(field: .startPlaceSearch) {
            completion = $0
        }
        service.cancelRecognitionForLifecycle()
        service.simulateAuthorizationCompletionForTesting(sessionID: staleSession, field: .startPlaceSearch)

        XCTAssertFalse(service.isListening)
        XCTAssertNil(service.activeFieldId)
        XCTAssertEqual(service.lastStopReason, .manual)
        XCTAssertNil(completion)

        service.startRecognitionForTesting(field: .startPlaceSearch) {
            completion = $0
        }
        service.finishRecognitionForTesting(text: "大观楼")

        XCTAssertEqual(completion?.field, .startPlaceSearch)
        XCTAssertEqual(completion?.recognizedText, "大观楼")
        XCTAssertEqual(completion?.reason, .finalResult)
    }

    /// 系统权限弹窗会让 `scenePhase` 短暂走一趟 `.inactive`。在那一刻作废掉待授权的识别会话，
    /// 用户点完「允许」之后授权回调恢复时 `isCurrentRecognitionSession` 必然判 false，
    /// 于是**静默 return**：没有播报、没有 errorMessage、没有完成回调，麦克风从未启动。
    /// 再点说话按钮命中 `VoiceOrderWizard.finishSpeakingOrSkipPrompt` 那个没有 `else` 的
    /// `if/else if`，是彻底的空操作 —— 2026-09-07 真机报的「点了没反应，要退出重进两次」。
    ///
    /// 下面这两行刻意照抄 `blindRunApp.swift` 的 `onChange(of: scenePhase)` 体，
    /// 这样判定改错时这条会红，而不是只有那个纯函数的断言会红。
    func testTransientInactivePhaseKeepsThePendingAuthorizationAlive() {
        let service = SpeechInputService()
        let session = service.startPendingAuthorizationForTesting(field: .startPlaceSearch)

        if RecognitionLifecyclePolicy.cancelsRecognition(on: .inactive, isListening: service.isListening) {
            service.cancelRecognitionForLifecycle()
        }
        service.simulateAuthorizationCompletionForTesting(sessionID: session, field: .startPlaceSearch)

        XCTAssertTrue(
            service.isListening,
            "权限弹窗让 scenePhase 走了一趟 .inactive，待授权的识别会话就被作废了 —— "
                + "用户点「允许」之后麦克风不会打开，而且一个字都不会播"
        )
    }

    /// 真进后台要取消 —— 麦克风不能在用户切走之后继续开着。同样照抄 `onChange` 的函数体。
    func testBackgroundPhaseStillCancelsAnActiveRecognition() {
        let service = SpeechInputService()
        service.startRecognitionForTesting(field: .startPlaceSearch)
        XCTAssertTrue(service.isListening, "前提没成立：这条要验的是「正在听」的会话")

        if RecognitionLifecyclePolicy.cancelsRecognition(on: .background, isListening: service.isListening) {
            service.cancelRecognitionForLifecycle()
        }

        XCTAssertFalse(service.isListening, "App 进后台了，麦克风还开着")
    }

    /// 正在听的时候走 `.inactive` **仍然要停**：那是 iPad 分屏 / 来电横幅 / 控制中心，
    /// 用户已经在看别的东西了，麦克风不该开着。
    ///
    /// 这条是「只写 `.background` 才取消」会带来的 iPad 回归 —— 全仓
    /// `AVAudioSession.interruptionNotification` 零命中，scenePhase 这条线就是唯一的中断清理，
    /// 而静音超时最长会被旁边 App 的声音续命到 `maximumRecognitionDuration = 60` 秒。
    func testInactivePhaseStillCancelsWhileActuallyListening() {
        let service = SpeechInputService()
        service.startRecognitionForTesting(field: .startPlaceSearch)

        if RecognitionLifecyclePolicy.cancelsRecognition(on: .inactive, isListening: service.isListening) {
            service.cancelRecognitionForLifecycle()
        }

        XCTAssertFalse(
            service.isListening,
            "iPad 分屏切到旁边那个 App 之后麦克风还开着 —— 权限弹窗那一刻会话还没在听，"
                + "两种情况靠 isListening 区分，别退回成只看 phase"
        )
    }

    func testSpeechInputPendingAuthorizationOwnsRecognitionSessionBeforeListening() {
        let service = SpeechInputService()

        service.startPendingAuthorizationForTesting(field: .startPlaceSearch)

        XCTAssertFalse(service.isListening(for: .startPlaceSearch))
        XCTAssertTrue(service.hasRecognitionSession(for: .startPlaceSearch))
        XCTAssertFalse(service.hasRecognitionSession(for: .remark))

        service.cancelRecognitionForLifecycle()

        XCTAssertFalse(service.hasRecognitionSession(for: .startPlaceSearch))
    }

    func testSpeechInputCompletionIncludesFieldTextAndStopReason() {
        let service = SpeechInputService()
        var completion: SpeechInputCompletion?

        service.startRecognitionForTesting(field: .startPlaceSearch) {
            completion = $0
        }
        service.finishRecognitionForTesting(
            text: "大观",
            reason: .silenceTimeout(hadDetectedSound: true)
        )

        XCTAssertFalse(service.isListening)
        XCTAssertNil(service.activeFieldId)
        XCTAssertEqual(completion?.field, .startPlaceSearch)
        XCTAssertEqual(completion?.recognizedText, "大观")
        XCTAssertEqual(completion?.reason, .silenceTimeout(hadDetectedSound: true))
        XCTAssertTrue(completion?.reason.shouldTriggerSearchWithRecognizedText == true)
    }

    func testSpeechInputSwitchingFieldsCompletesPreviousFieldBeforeReplacingHandler() {
        let service = SpeechInputService()
        var startPlaceCompletion: SpeechInputCompletion?
        var notesCompletion: SpeechInputCompletion?

        service.startRecognitionForTesting(field: .startPlaceSearch) {
            startPlaceCompletion = $0
        }
        service.finishRecognitionForTesting(
            text: "大观",
            reason: .silenceTimeout(hadDetectedSound: true)
        )
        service.startRecognitionForTesting(field: .startPlaceSearch) {
            startPlaceCompletion = $0
        }
        service.startRecognitionForTesting(field: .startLocationDescription) {
            notesCompletion = $0
        }

        XCTAssertEqual(startPlaceCompletion?.field, .startPlaceSearch)
        XCTAssertEqual(startPlaceCompletion?.recognizedText, "")
        XCTAssertEqual(startPlaceCompletion?.reason, .manual)
        XCTAssertNil(notesCompletion)
        XCTAssertTrue(service.isListening(for: .startLocationDescription))
    }

    func testSpeechInputSilenceTimeoutClearsActiveField() {
        let service = SpeechInputService()

        service.startRecognitionForTesting(field: .startLocationDescription)
        service.triggerSilenceTimeoutForTesting(hadDetectedSound: false)

        XCTAssertFalse(service.isListening)
        XCTAssertNil(service.activeFieldId)
        XCTAssertEqual(service.lastStopReason, .silenceTimeout(hadDetectedSound: false))
    }
}
