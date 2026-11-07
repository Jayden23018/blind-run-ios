import SwiftUI

// MARK: - Voice Dictation Button

/// 给已有的文字框挂一枚「语音输入」按钮（#795）：留言、评价、举报、工单。
///
/// 和 `VoiceTextField` 的分工：
/// - **不画输入框。** 各页面的输入框保持原样（工单页是 #755 定稿的白卡），按钮默认放在框下面整行铺满，
///   盲人端次级操作一律整行竖排（`docs/ui/design-direction.md`）。例外：传 `besideField` 时
///   输入框在左、只有图标的按钮在右同一行（#831 评语框，负责人 11-07 定）。
/// - **接在后面，不覆盖。** 识别结果接在开录那一刻已有的文字后面。`VoiceTextField` 是整框替换，
///   放在这几处会把用户先打好的一段话冲掉，而读屏用户不一定发现。
/// - **识别完念一遍。** 盲人用语音写字，大部分时间花在检查识别结果上
///   （`docs/research/blind-input-reduction-20261106.md`），先念给他听，省一次逐字读框。
///
/// 识别走苹果 `SFSpeechRecognizer`（`SpeechInputService`），不送后端大模型（负责人 2026-11-06 定）。
struct VoiceDictationButton: View {
    /// 读屏标签里用：「语音输入给陪跑员的留言」。
    let fieldTitle: String
    @Binding var text: String
    @ObservedObject var speechInputService: SpeechInputService
    @ObservedObject var speechService: SpeechService
    let speechField: SpeechInputField
    /// 传了就把输入框画在左边、按钮缩成只有图标的方块放右边同一行（#831 评语框，负责人 11-07 定）。
    /// 可点区仍是 64pt，读屏标签与整行样式完全相同；「正在聆听」与失败原因照旧在这一行下面整行显示。
    var besideField: AnyView?

    /// 只有图标的那一档的边长 = 盲人端最小可点区。
    static let compactSide = AppTouchTarget.blindPrimary

    /// 只显示这一枚按钮自己引起的错误。`SpeechInputService` 全 App 共用一个，
    /// 它的 `errorMessage` 可能是别的页面上一次留下的。别的字段开录时复位。
    @State private var didStartHere = false
    /// 这一次录音写进框里的最后一版。框里的字和它对不上 = 用户录音中自己改过字。
    /// 用类而不是 `@State` 值：识别回调是开录时捕获的闭包，要读到最新值。
    @State private var session = DictationSession()

    var body: some View {
        let isListening = speechInputService.isListening(for: speechField)

        VStack(alignment: .leading, spacing: 8) {
            if let besideField {
                HStack(alignment: .top, spacing: 8) {
                    besideField
                    button(isListening: isListening)
                }
            } else {
                button(isListening: isListening)
            }

            if isListening {
                HStack(spacing: 6) {
                    Image(systemName: "waveform")
                        .accessibilityHidden(true)
                    Text(VoiceDictationCopy.listening)
                }
                .font(AppFonts.caption())
                .foregroundColor(AppColors.textSecondary)
                .accessibilityElement(children: .combine)
            }

            // 失败要留在屏幕上，不只靠一句播报：不开读屏的低视力用户屏幕上也要有东西变。
            if didStartHere, let errorMessage = speechInputService.errorMessage {
                Text(errorMessage)
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onChange(of: speechInputService.activeField) { field in
            if let field, field != speechField { didStartHere = false }
        }
        .onDisappear {
            if speechInputService.hasRecognitionSession(for: speechField) {
                speechInputService.cancelRecognitionForLifecycle()
            }
        }
    }

    private func button(isListening: Bool) -> some View {
        Button {
            toggleRecognition(isListening: isListening)
        } label: {
            if besideField == nil {
                Label(
                    isListening ? VoiceDictationCopy.stop : VoiceDictationCopy.start,
                    systemImage: isListening ? "stop.circle" : "mic"
                )
            } else {
                Image(systemName: isListening ? "stop.circle" : "mic")
                    .font(.title2.weight(.semibold))
                    .frame(width: Self.compactSide, height: Self.compactSide)
                    .contentShape(Rectangle())
            }
        }
        .buttonStyle(OutlineSecondaryButtonStyle(fillsWidth: besideField == nil))
        .accessibilityLabel(isListening ? "停止语音输入\(fieldTitle)" : "语音输入\(fieldTitle)")
        .accessibilityHint(isListening ? VoiceDictationCopy.stopHint : VoiceDictationCopy.startHint)
        .accessibilityIdentifier("\(speechField.rawValue)DictationButton")
    }

    /// 提交、保存之前调用：先停掉这个字段的录音再提交。
    /// 不停的话，提交出去的是当时的半句话，麦克风还开着，还会继续往已提交的框里写。
    static func stopRecording(_ field: SpeechInputField, on service: SpeechInputService) {
        if service.hasRecognitionSession(for: field) {
            service.stopRecognition()
        }
    }

    private func toggleRecognition(isListening: Bool) {
        if !isListening {
            // 收起键盘：键盘开着时用户可能边录边打字，系统键盘自己的听写也会和这里抢麦克风。
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            didStartHere = true
        }
        // 正在录这一个字段时，`startRecognition` 就是「停止」。
        let base = text
        let session = session
        session.lastWritten = text
        session.userEdited = false
        speechInputService.startRecognition(field: speechField, onTextChanged: { recognized in
            guard let next = Self.nextText(
                current: text, lastWritten: session.lastWritten, base: base, recognized: recognized
            ) else {
                // 用户录音中改了字：停下，不拿识别结果盖掉他刚改的。
                session.userEdited = true
                speechInputService.stopRecognition()
                return
            }
            text = next
            session.lastWritten = next
        }, onAnnouncement: { message in
            // 走通告不走合成器，原因同 `VoiceTextField`：麦克风可能还开着，合成器的声音会被录进去。
            speechService.announce(message)
        }, onCompletion: { completion in
            // 用户自己改过字时，识别结果没有写进框里，不能说「已填入」。
            guard !session.userEdited else { return }
            // 紧跟在「语音输入已停止」之后发，会把那一句顶掉：「已填入」本身就说明停了。
            if let readBack = Self.readBack(for: completion) {
                speechService.announce(readBack)
            }
        })
    }

    /// 开录前框里的字 + 这一次识别到的字。识别结果在录音过程中会不断改写，所以每次都从 `base` 重拼。
    nonisolated static func merged(base: String, recognized: String) -> String {
        base + recognized
    }

    /// 收到一版识别结果后框里该是什么。返回 `nil` = 框里的字已不是上次写进去的那一版（用户改过），
    /// 这时不能写：`base + recognized` 会把用户刚改的字整框冲掉，而读屏用户不一定发现。
    nonisolated static func nextText(current: String, lastWritten: String, base: String, recognized: String) -> String? {
        guard current == lastWritten else { return nil }
        return merged(base: base, recognized: recognized)
    }

    /// 识别结束后念的那一句。没识别到字、或识别失败时返回 `nil`：
    /// 那两种情况 `SpeechInputService` 已经念过原因（「未检测到声音」「语音识别失败」），不能被顶掉。
    nonisolated static func readBack(for completion: SpeechInputCompletion) -> String? {
        guard completion.reason.shouldTriggerSearchWithRecognizedText else { return nil }
        let recognized = completion.recognizedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !recognized.isEmpty else { return nil }
        return VoiceDictationCopy.filled(recognized)
    }
}

/// 一次录音的可变状态。识别回调是开录时捕获的闭包，值类型的 `@State` 在里面读不到新值。
@MainActor
final class DictationSession {
    var lastWritten = ""
    var userEdited = false
}

enum VoiceDictationCopy {
    static let start = "语音输入"
    static let stop = "停止语音输入"
    static let startHint = "说完会念出填进去的文字"
    static let stopHint = "点击后停止录音"
    static let listening = "正在聆听"

    static func filled(_ text: String) -> String { "已填入：\(text)" }
}
