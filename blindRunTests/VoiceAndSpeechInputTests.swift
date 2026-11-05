import XCTest
import AMapSearchKit
import AVFAudio
import CoreLocation
import SwiftUI
@testable import blindRun

@MainActor
final class VoiceAndSpeechInputTests: XCTestCase, BlindRunTestSupport {
    func testSpeechInputStopReasonAnnouncements() {
        XCTAssertEqual(SpeechInputStopReason.manual.announcement, "语音输入已关闭。")
        XCTAssertEqual(
            SpeechInputStopReason.silenceTimeout(hadDetectedSound: false).announcement,
            "未检测到声音，已停止语音输入。"
        )
        XCTAssertEqual(
            SpeechInputStopReason.silenceTimeout(hadDetectedSound: true).announcement,
            "语音输入已停止。"
        )
        XCTAssertEqual(SpeechInputStopReason.maxDuration.announcement, "语音输入已达到最长时间，已停止。")
    }

    func testVoiceServiceExposesRequestedAPIAndCompatibilityAlias() {
        let service = VoiceService()
        let legacyService: SpeechService = service

        service.speak(text: " 当前状态 ")
        XCTAssertEqual(service.lastSpokenText, "当前状态")
        XCTAssertEqual(service.latestRepeatableText, "当前状态")
        XCTAssertEqual(service.lastVoiceOverAnnouncement, "当前状态")

        legacyService.repeatCurrentStatus()
        XCTAssertEqual(service.lastSpokenText, "当前状态")

        service.stop()
        XCTAssertFalse(service.isSpeaking)
    }

    /// `speak` 必须**同步**置上 `isSpeaking`，不能等 `didStart` 代理。
    ///
    /// `VoiceOrderWizard.listen` 紧接着 `speak` 就开始轮询这个标志来决定什么时候开麦。代理是
    /// `DispatchQueue.main.async` 派发的，等它的话第一次检查读到的还是 false，等待循环当场放行 ——
    /// 麦克风在一个字都没念出来时就打开，而开麦切换音频分类会把这句话掐断。
    func testSpeakMarksSpeakingSynchronouslySoTheWizardDoesNotOpenTheMicTooEarly() {
        let service = VoiceService()

        service.speak(text: "这次的预约是：从当前位置出发。")

        XCTAssertTrue(
            service.isSpeaking,
            "speak 返回时就必须是「在播」——等代理置位，向导会在第一次轮询时判定「没在播」并立刻开麦"
        )
    }

    /// 迟到的 `didCancel` **不得**把新一条播报的状态抹掉。
    ///
    /// `speak` 是「先 `stopSpeaking(.immediate)` 再播新的」，旧那条随后会回一次 `didCancel`。
    /// 不对身份就清标志的话，这次回调会让向导以为读回已经播完而提前开麦 —— 就是 2026-08-06
    /// 报障的那个截断现象，只不过变成偶发，比稳定复现更难查。
    func testStaleUtteranceCallbackDoesNotClearTheSpeakingFlag() {
        let service = VoiceService()
        service.speak(text: "这次的预约是：从当前位置出发，明天早上八点，跑一个小时。")

        // 不是当前那一条的回调（旧 utterance 迟到，或系统回了别的实例）
        service.speechSynthesizer(AVSpeechSynthesizer(), didCancel: AVSpeechUtterance(string: "上一句"))

        XCTAssertTrue(
            service.isSpeaking,
            "别人的结束回调把当前播报标成「播完了」，向导会当场开麦，读回被截断"
        )
    }

    /// 播报语速必须跟随用户的 VoiceOver 设置，不能写死默认值。
    ///
    /// 读屏用户日常把语速调到远高于系统默认，而 `prefersAssistiveTechnologySettings` 的**出厂值是
    /// `false`**（已实测，不是推测）—— 不显式打开，App 的每一句播报都会比用户习惯的慢一大截，
    /// 且和同一句话的 VoiceOver 通告快慢不一。这是**每次播报都在犯**的缺陷，不是边界情况。
    ///
    /// ⚠️ 这条**只能**断言开关本身。SDK 头文件写明 `querying the properties will not reflect the
    /// user's settings` —— `utterance.rate` 永远读回我们写进去的 0.5，真实语速在进程里测不出来。
    /// 听感必须真机开 VoiceOver 人耳验，见记忆 `audio-correctness-needs-real-ears-not-code-reading`。
    func testSpokenUtteranceFollowsTheUsersVoiceOverRateInsteadOfTheFixedDefault() {
        let utterance = VoiceService.makeUtterance("志愿者已到达，请等待志愿者开始服务。")

        XCTAssertTrue(
            utterance.prefersAssistiveTechnologySettings,
            "没开这个标志，播报就锁死在默认语速 —— 读屏用户把语速调快过的，全被拖回默认"
        )
        // VoiceOver 没开时（低视力用户、明眼陪同者）走的是这三个值，删掉会连中文音色一起丢。
        XCTAssertEqual(utterance.voice?.language, "zh-CN")
        XCTAssertEqual(utterance.rate, AVSpeechUtteranceDefaultSpeechRate)
        XCTAssertEqual(utterance.speechString, "志愿者已到达，请等待志愿者开始服务。")
    }

    /// 验红用的对照：**没经过 `makeUtterance` 的裸 utterance 必须是关着的**。
    ///
    /// 上面那条断言 `true`，而 `AVSpeechUtterance` 要是哪天把出厂值改成 `true`，那条会在
    /// `makeUtterance` 被误删的情况下照样绿。这条钉住「绿是因为我们设了，不是因为系统白送」。
    func testRawUtteranceDoesNotFollowAssistiveSettingsByDefault() {
        XCTAssertFalse(
            AVSpeechUtterance(string: "志愿者已到达，请等待志愿者开始服务。")
                .prefersAssistiveTechnologySettings,
            "出厂值若变成 true，上面那条用例就不再能证明 makeUtterance 真的设了这个标志"
        )
    }

    func testVoiceServiceCanPostVoiceOverOnlyAnnouncement() {
        let service = VoiceService()

        service.announce(" 已找到 2 个地点 ")

        XCTAssertNil(service.lastSpokenText)
        XCTAssertEqual(service.lastVoiceOverAnnouncement, "已找到 2 个地点")
    }

    func testVoiceServiceStatusAnnouncementsMatchAccessibilityGuidelinesAndDeduplicate() {
        let service = VoiceService()

        XCTAssertEqual(
            VoiceService.statusAnnouncement(for: .pendingMatch),
            "订单提交成功，系统正在为你派单。"
        )
        XCTAssertEqual(
            VoiceService.statusAnnouncement(for: .driverArrived),
            RunOrderStatus.blindRunnerArrivedCopy
        )
        XCTAssertEqual(
            VoiceService.statusAnnouncement(for: .pendingAccept),
            "陪跑员已接单，请前往或等待在预约出发地点。"
        )
        XCTAssertEqual(
            VoiceService.statusAnnouncement(for: .driverEnRoute),
            "陪跑员已出发，正在前往出发地点。"
        )
        XCTAssertEqual(
            VoiceService.statusAnnouncement(for: .completed),
            "陪跑已完成，感谢使用助盲跑。"
        )

        XCTAssertTrue(service.speakStatusChange(.pendingMatch))
        XCTAssertFalse(service.speakStatusChange(.pendingMatch))
        XCTAssertTrue(service.speakStatusChange(.pendingAccept))
        XCTAssertEqual(service.lastSpokenStatus, .pendingAccept)

        service.stop()
    }

    func testSpeechInputFieldsAreTextOnlyAllowlist() {
        XCTAssertTrue(SpeechInputField.isAllowlisted(SpeechInputField.startPlaceSearch.rawValue))
        XCTAssertTrue(SpeechInputField.isAllowlisted(SpeechInputField.startLocationDescription.rawValue))
        XCTAssertTrue(SpeechInputField.isAllowlisted(SpeechInputField.destinationRoute.rawValue))
        XCTAssertTrue(SpeechInputField.isAllowlisted(SpeechInputField.remark.rawValue))
        XCTAssertTrue(SpeechInputField.isAllowlisted(SpeechInputField.ratingFeedback.rawValue))
        XCTAssertTrue(SpeechInputField.isAllowlisted(SpeechInputField.volunteerServiceSummary.rawValue))

        XCTAssertFalse(SpeechInputField.isAllowlisted("appointmentTime"))
        XCTAssertFalse(SpeechInputField.isAllowlisted("estimatedDistance"))
        XCTAssertFalse(SpeechInputField.isAllowlisted("pacePreference"))
    }

    func testSpeechInputRejectsNonAllowlistedFieldAndKeepsKeyboardFallback() {
        let service = SpeechInputService()

        service.startRecognitionForTesting(fieldId: "appointmentTime")

        XCTAssertFalse(service.isListening)
        XCTAssertNil(service.activeFieldId)
        XCTAssertEqual(service.lastStopReason, .error)
        XCTAssertEqual(service.errorMessage, SpeechInputService.keyboardFallbackErrorMessage)
    }

    func testSpeechInputFailureShowsKeyboardFallbackError() {
        let service = SpeechInputService()

        service.simulateRecognitionFailureForTesting(field: .remark)

        XCTAssertFalse(service.isListening)
        XCTAssertNil(service.activeFieldId)
        XCTAssertEqual(service.lastStopReason, .error)
        XCTAssertEqual(service.errorMessage, SpeechInputService.keyboardFallbackErrorMessage)
    }

    func testSpeechInputStopRecognitionClearsActiveField() {
        let service = SpeechInputService()

        service.startRecognitionForTesting(fieldId: "remark")
        XCTAssertTrue(service.isListening(for: .remark))

        service.stopRecognition()

        XCTAssertFalse(service.isListening)
        XCTAssertNil(service.activeFieldId)
        XCTAssertEqual(service.lastStopReason, .manual)
    }

    func testSpeechInputRestoresPlaybackBeforeCompletionForEveryStopReason() {
        let reasons: [SpeechInputStopReason] = [
            .manual,
            .finalResult,
            .silenceTimeout(hadDetectedSound: false),
            .silenceTimeout(hadDetectedSound: true),
            .maxDuration,
            .error
        ]

        for reason in reasons {
            let audioSession = MockSpeechAudioSession()
            let service = SpeechInputService(audioSession: audioSession)
            var completionOperations: [String] = []
            service.startRecognitionForTesting(field: .startPlaceSearch) { _ in
                completionOperations = audioSession.operations + ["completion"]
            }

            service.finishRecognitionForTesting(text: "大观楼", reason: reason)

            XCTAssertEqual(
                completionOperations,
                ["deactivateRecording", "configurePlayback", "activatePlayback", "completion"],
                "Unexpected audio restoration order for \(reason)"
            )
        }
    }

    func testSpeechInputLifecycleStopRestoresPlaybackWithoutCompleting() {
        let audioSession = MockSpeechAudioSession()
        let service = SpeechInputService(audioSession: audioSession)
        var didComplete = false
        service.startRecognitionForTesting(field: .remark) { _ in didComplete = true }

        service.cancelRecognitionForLifecycle()

        XCTAssertEqual(audioSession.operations, ["deactivateRecording", "configurePlayback", "activatePlayback"])
        XCTAssertFalse(didComplete)
    }

    func testSpeechInputRepeatedStopDoesNotRepeatAudioSessionCleanup() {
        let audioSession = MockSpeechAudioSession()
        let service = SpeechInputService(audioSession: audioSession)
        service.startRecognitionForTesting(field: .remark)

        service.stopRecognition()
        service.stopRecognition()

        XCTAssertEqual(audioSession.operations, ["deactivateRecording", "configurePlayback", "activatePlayback"])
    }

    func testSpeechInputPlaybackRecoveryFailureKeepsCompletionAndDiagnostics() {
        let failurePoints: [MockSpeechAudioSession.FailurePoint] = [
            .deactivate,
            .playbackCategory,
            .playbackActivation
        ]

        for failurePoint in failurePoints {
            let audioSession = MockSpeechAudioSession()
            audioSession.failurePoint = failurePoint
            let service = SpeechInputService(audioSession: audioSession)
            var completion: SpeechInputCompletion?
            service.startRecognitionForTesting(field: .startPlaceSearch) { completion = $0 }

            service.finishRecognitionForTesting(text: "大观楼")

            XCTAssertEqual(completion?.recognizedText, "大观楼")
            XCTAssertEqual(audioSession.operations, ["deactivateRecording", "configurePlayback", "activatePlayback"])
            XCTAssertNotNil(service.audioSessionDiagnosticMessage)
            XCTAssertNil(service.errorMessage)
        }
    }

    func testSpeechInputStartupFailureRestoresPlaybackBeforeErrorAnnouncement() {
        let audioSession = MockSpeechAudioSession()
        let service = SpeechInputService(audioSession: audioSession)
        var observedOperations: [String] = []
        service.startRecognitionForTesting(field: .remark, onAnnouncement: { message in
            observedOperations = audioSession.operations + ["announce:\(message)"]
        })

        service.failRecognitionStartupForTesting("语音输入启动失败，请使用键盘输入。")

        XCTAssertEqual(
            observedOperations,
            [
                "deactivateRecording",
                "configurePlayback",
                "activatePlayback",
                "announce:语音输入启动失败，请使用键盘输入。"
            ]
        )
        XCTAssertEqual(service.lastStopReason, .error)
    }
}
