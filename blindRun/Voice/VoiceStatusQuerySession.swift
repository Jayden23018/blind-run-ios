import CoreLocation
import Foundation
import UIKit

// MARK: - Voice Status Query Session

/// 「问一句」的一次问答：录一句 → 只答被问的那一项 → （问拨号时）再录一句确认 → 拨号。
///
/// 判定逻辑在 `VoiceStatusQuery`（纯函数、可单测）；这里只做硬件那一半：开麦、播报、拨号。
///
/// **两个页面共用一个实现，不各写一份。** 首页与订单状态页的差别只有「订单和志愿者坐标从哪来」，
/// 用 `context` 闭包收掉；拨号确认那一段是安全逻辑，抄两遍迟早漂移（`AGENTS.md` §1）。
@MainActor
final class VoiceStatusQuerySession {

    private weak var speechService: SpeechService?
    private weak var speechInputService: SpeechInputService?
    /// **每一轮现取一次**，不缓存：录音那几秒里轮询可能已经把订单刷新了，
    /// 用开麦那一刻的旧订单回答等于念过期数据。
    private var context: (() -> (order: OrderDetailResponse?, volunteerCoordinate: CLLocationCoordinate2D?))?

    /// 当前这一轮的身份。
    ///
    /// `SpeechInputService.startRecognition` 在开新会话前会**停掉旧会话并触发旧的完成回调**
    /// （`stopActiveRecognitionIfNeeded`）。没有这个 token 的话，用户在「说确认拨号吗」那一轮
    /// 按下「问一句」，被顶掉的确认回调会带着当时的识别文本跑完 —— 也就是可能直接拨出去。
    private var currentRound = UUID()
    /// 录音服务发来的提示（「未检测到声音」「麦克风不可用」）。**先存着，不立刻播** ——
    /// 正常问答里它会被紧接着的答案打断，只有「这一轮什么都没听到」时它才是用户唯一的信息。
    private var pendingAnnouncement: String?

    func configure(
        speechService: SpeechService?,
        speechInputService: SpeechInputService?,
        context: @escaping () -> (order: OrderDetailResponse?, volunteerCoordinate: CLLocationCoordinate2D?)
    ) {
        self.speechService = speechService
        self.speechInputService = speechInputService
        self.context = context
    }

    /// 按下「问一句」。
    func ask() {
        guard let speechInputService else { return }
        // 已经在听问题这一轮：这一按是「我说完了」，不是「重新问」。
        //
        // 必须保持**同一个 round**，否则完成回调会被下面的新 round 判成过期而丢掉 ——
        // 现象是用户说完按下停止，只听到停录提示音，然后一片沉默，问题白问了。
        // （`startRecognition` 对同一 field 本来就只停不起，见 `stopActiveRecognitionIfNeeded`。）
        if speechInputService.isListening(for: .voiceStatusQuery) {
            speechInputService.stopRecognition()
            return
        }
        // 正在念的那段立刻停：不停的话麦克风会把播报当成用户说话，识别必然跑偏。
        speechService?.stop()
        let round = UUID()
        currentRound = round
        pendingAnnouncement = nil
        listen(field: .voiceStatusQuery, round: round, service: speechInputService) { [weak self] transcript in
            self?.handleQuestion(transcript, round: round)
        }
    }

    // MARK: Rounds

    private func handleQuestion(_ transcript: String, round: UUID) {
        let (order, coordinate) = context?() ?? (nil, nil)
        let intent = VoiceStatusQuery.classify(transcript)
        let answer = VoiceStatusQuery.answer(
            intent: intent,
            order: order,
            volunteerCoordinate: coordinate,
            fallbackAnnouncement: fallbackAnnouncement(order: order, coordinate: coordinate)
        )
        speechService?.speak(answer.speech)

        guard case .confirmDialVolunteer(let phone) = answer.pendingAction else { return }
        Task { [weak self] in
            // 号码没念完就开麦，用户听到的是被自己截断的号码 —— 而他要靠这串数字判断拨给谁。
            await self?.waitForSpeechToSettle(characterCount: answer.speech.count)
            guard let self, let speechInputService, self.currentRound == round else { return }
            self.listen(field: .voiceStatusConfirmCall, round: round, service: speechInputService) { [weak self] reply in
                self?.handleDialConfirmation(reply, phone: phone)
            }
        }
    }

    private func handleDialConfirmation(_ transcript: String, phone: String) {
        guard VoiceStatusQuery.isDialConfirmed(transcript) else {
            speechService?.speak(VoiceStatusQuery.dialCancelledSpeech)
            return
        }
        // 复述号码到用户说完「确认」之间隔了好几秒，订单可能已经变了（志愿者取消 → REMATCHING）。
        // 屏幕上的拨号按钮会跟着状态消失，语音这条路也必须跟着走 —— 判据同一个
        // `offersVolunteerCall`，不许因为「刚才还能打」就放行。
        let (order, _) = context?() ?? (nil, nil)
        guard order?.status.offersVolunteerCall == true,
              let telURL = EmergencyDialer.telURL(for: phone) else {
            speechService?.speak("订单状态已经变了，现在不能打电话给志愿者。")
            return
        }
        speechService?.speak("正在拨号。")
        UIApplication.shared.open(telURL)
    }

    // MARK: Plumbing

    /// 起一轮录音。空识别不交给 `onTranscript`：那一轮用户根本没说话，
    /// 当成「没听懂」去念整段状态是在拿一段长播报回答一次没说出口的提问。
    private func listen(
        field: SpeechInputField,
        round: UUID,
        service: SpeechInputService,
        onTranscript: @escaping (String) -> Void
    ) {
        service.startRecognition(
            field: field,
            // 实时文本这一页不上屏：没有输入框可回填，念出来又会盖住用户自己的声音。
            onTextChanged: { _ in },
            onAnnouncement: { [weak self] message in
                guard let self, self.currentRound == round else { return }
                self.pendingAnnouncement = message
            },
            onCompletion: { [weak self] completion in
                guard let self, self.currentRound == round, completion.field == field else { return }
                let announcement = self.pendingAnnouncement
                self.pendingAnnouncement = nil
                guard VoiceStatusQuery.shouldAnswer(completion) else {
                    // 确认那一轮没听到声音 = 没确认。必须说出「没拨」，不能静默收场。
                    let tail = field == .voiceStatusConfirmCall ? VoiceStatusQuery.dialCancelledSpeech : nil
                    let spoken = [announcement, tail].compactMap { $0 }.joined(separator: " ")
                    if !spoken.isEmpty { self.speechService?.speak(spoken) }
                    return
                }
                onTranscript(completion.recognizedText.trimmed)
            }
        )
    }

    /// 与 `VoiceOrderWizard.waitForSpeechToSettle` 同一套：上限按字数走，播完就立刻放行。
    private func waitForSpeechToSettle(characterCount: Int) async {
        guard let speechService else { return }
        let deadline = Date().addingTimeInterval(
            VoiceOrderWizard.settleTimeout(forCharacterCount: characterCount)
        )
        while speechService.isSpeaking && Date() < deadline {
            try? await Task.sleep(nanoseconds: 150_000_000)
        }
    }

    private func fallbackAnnouncement(
        order: OrderDetailResponse?,
        coordinate: CLLocationCoordinate2D?
    ) -> String {
        guard let order else { return "" }
        let distanceText = order.status.offersVolunteerDistanceToStart
            ? order.volunteerDistanceToStartText(from: coordinate)
            : nil
        return order.blindRunnerAnnouncement(distanceText: distanceText)
    }
}
