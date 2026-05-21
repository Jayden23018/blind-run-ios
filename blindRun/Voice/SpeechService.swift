import AVFoundation
import Combine
import SwiftUI

// MARK: - Speech Service

/// 集中式 TTS 服务，使用 AVSpeechSynthesizer 播报状态变化和错误提示。
/// 通过记录上次播报状态，避免轮询时重复播报。
final class SpeechService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {

    private nonisolated(unsafe) let synthesizer = AVSpeechSynthesizer()
    @Published private(set) var isSpeaking = false
    private var lastSpokenStatus: RunOrderStatus?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Public API

    /// 播报文本
    func speak(_ text: String) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        synthesizer.speak(utterance)
    }

    /// 播报订单状态变化（防重复）
    /// 只在状态真正变化时播报，避免轮询时反复播报同一状态。
    func speakStatusChange(_ status: RunOrderStatus) {
        guard status != lastSpokenStatus else { return }
        lastSpokenStatus = status
        speak(statusAnnouncement(for: status))
    }

    /// 重复播报当前状态（"重复当前状态"按钮调用）
    func repeatCurrentStatus() {
        guard let status = lastSpokenStatus else {
            speak("当前没有进行中的订单。")
            return
        }
        speak(statusAnnouncement(for: status))
    }

    /// 播报错误信息
    func speakError(_ message: String) {
        speak(message)
    }

    /// 停止播报
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    /// 重置最后播报状态（切换订单时调用）
    func resetLastStatus() {
        lastSpokenStatus = nil
    }

    // MARK: - Status Copy Mapping (docs/09 section 7)

    private func statusAnnouncement(for status: RunOrderStatus) -> String {
        switch status {
        case .matching:
            return "预约已提交，正在等待志愿者接单。"
        case .accepted:
            return "志愿者已接单，请等待志愿者到达。"
        case .arrived:
            return "志愿者已到达，请确认开始服务。"
        case .inProgress:
            return "服务已开始，请注意安全。"
        case .completed:
            return "服务已完成，感谢使用助盲跑。"
        case .cancelled:
            return "本次预约已取消。"
        case .emergency:
            return "已进入求助状态，系统已记录本次异常。"
        }
    }

    // MARK: - AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = true
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = false
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = false
        }
    }
}
