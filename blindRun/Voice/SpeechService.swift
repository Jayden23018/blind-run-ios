import AVFoundation
import Combine
import SwiftUI
import UIKit

// MARK: - Voice Service

/// 集中式 TTS 服务，使用 AVSpeechSynthesizer 播报状态变化和错误提示。
/// 通过记录上次播报状态，避免轮询时重复播报。
final class VoiceService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {

    private nonisolated(unsafe) let synthesizer = AVSpeechSynthesizer()
    @Published private(set) var isSpeaking = false
    @Published private(set) var lastSpokenText: String?
    @Published private(set) var latestRepeatableText: String?
    @Published private(set) var lastVoiceOverAnnouncement: String?
    private(set) var lastSpokenStatus: RunOrderStatus?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Public API

    /// 播报文本
    func speak(text: String) {
        let normalizedText = text.trimmed
        guard !normalizedText.isEmpty else { return }
        lastSpokenText = normalizedText
        latestRepeatableText = normalizedText
        // ⚠️ VoiceOver 开着时这一句会同时走无障碍通告和合成器，听感上可能是念两遍。
        // 2026-08-01 曾改成「VoiceOver 运行时只留合成器」，当天回退：
        // 两条通道各有不可替代的性质 —— 通告走 VoiceOver 自己的语速与队列（读屏用户常把语速调到
        // 14~16 字/秒，合成器这边是写死的默认语速），而合成器不会像通告那样在 VoiceOver 忙时被丢弃，
        // 这一点对 SOS 是硬要求。砍掉任何一条都有真实代价，而**双重播报本身还没在真机上确认过**。
        // 结论：不靠读代码拍板。真机听过之后再定，届时可能的方案是通告 + 按 VoiceOver 语速合成。
        postVoiceOverAnnouncement(normalizedText)
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: normalizedText)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        synthesizer.speak(utterance)
    }

    /// 兼容既有调用点的短方法名。
    func speak(_ text: String) {
        speak(text: text)
    }

    /// VoiceOver-only announcement for transient UI state such as search results.
    func announce(_ text: String) {
        postVoiceOverAnnouncement(text)
    }

    /// 播报订单状态变化（防重复）
    /// 只在状态真正变化时播报，避免轮询时反复播报同一状态。
    @discardableResult
    func speakStatusChange(_ status: RunOrderStatus) -> Bool {
        guard status != lastSpokenStatus else { return false }
        lastSpokenStatus = status
        speak(text: Self.statusAnnouncement(for: status))
        return true
    }

    @discardableResult
    func speakStatusChange(_ status: RunOrderStatus, text: String) -> Bool {
        guard status != lastSpokenStatus else { return false }
        lastSpokenStatus = status
        speak(text: text)
        return true
    }

    /// 重复播报当前状态（"重复当前状态"按钮调用）
    func repeatCurrentStatus() {
        speak(text: latestRepeatableText ?? "当前没有进行中的订单。")
    }

    /// 播报错误信息
    func speakError(_ message: String) {
        speak(text: message)
    }

    /// 停止播报
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    /// 重置最后播报状态（切换订单时调用）
    func resetLastStatus() {
        lastSpokenStatus = nil
        latestRepeatableText = nil
    }

    private func postVoiceOverAnnouncement(_ text: String) {
        let normalizedText = text.trimmed
        guard !normalizedText.isEmpty else { return }
        lastVoiceOverAnnouncement = normalizedText
        let post = {
            UIAccessibility.post(notification: .announcement, argument: normalizedText)
        }
        if Thread.isMainThread {
            post()
        } else {
            DispatchQueue.main.async(execute: post)
        }
    }

    // MARK: - Status Copy Mapping (docs/09 section 7)

    static func statusAnnouncement(for status: RunOrderStatus) -> String {
        switch status {
        case .pendingMatch:
            return "订单提交成功，系统正在为你派单。"
        case .pendingAccept:
            return "志愿者已接单，请前往或等待在预约出发地点。"
        case .driverEnRoute:
            return "志愿者已出发，正在前往出发地点。"
        case .driverArrived:
            return "志愿者已到达，请等待志愿者开始服务。"
        case .inProgress:
            return "服务已开始，请注意安全。"
        case .completed:
            return "服务已完成，感谢使用助盲跑。"
        case .cancelled:
            return "本次预约已取消。"
        case .rematching:
            return "正在确认志愿者状态，请稍候。"
        case .noVolunteer:
            return "暂无可用志愿者，请稍后再试。"
        // 后端新增了本客户端不认识的状态。宁可播一句「请刷新」，也不能因为编不出文案就静默 ——
        // 盲人用户没有别的渠道知道订单变了。
        case .unknown:
            return "订单状态有更新，请刷新页面或稍后重试。"
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

/// 兼容仓库中已按 docs/09 命名接入的调用点。
typealias SpeechService = VoiceService
