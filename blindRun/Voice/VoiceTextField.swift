import SwiftUI

// MARK: - Voice Text Field

/// Text input with an optional Speech framework microphone action.
/// Use only for allowlisted text fields; time remains DatePicker-only.
struct VoiceTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var isMultiline = false
    @ObservedObject var speechInputService: SpeechInputService
    @ObservedObject var speechService: SpeechService
    let speechField: SpeechInputField
    let accessibilityLabel: String
    let accessibilityHint: String
    var onRecognitionCompleted: ((SpeechInputCompletion) -> Void)? = nil

    var body: some View {
        let isListening = speechInputService.isListening(for: speechField)

        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(AppColors.textPrimary)

            HStack(alignment: .top, spacing: 8) {
                Group {
                    if isMultiline {
                        TextEditor(text: $text)
                            .frame(minHeight: 96)
                    } else {
                        TextField(placeholder, text: $text)
                    }
                }
                .font(AppFonts.body())
                .padding()
                .background(AppColors.secondaryBackground)
                .cornerRadius(8)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityHint(accessibilityHint)

                Button {
                    speechInputService.startRecognition(field: speechField, onTextChanged: { recognizedText in
                        text = recognizedText
                    }, onAnnouncement: { message in
                        // 走通告而不是合成器，和 `VoiceOrderWizard` 保持一致。
                        //
                        // 这些通告（「语音输入已开启，请说话。」等）是在**麦克风已经打开之后**发出的。
                        // 用合成器念，声音会被自己的麦克风录进去、进而被识别成用户说的话。
                        // 以前侥幸没出事，是因为录音分类 `.record` 根本不开输出通道，这一句被系统吞掉了；
                        // 2026-08-06 为了让起音提示能被听见改成 `.playAndRecord` 之后，它会真的响。
                        //
                        // 「麦克风开了」由 `RecordingCue` 的提示音加震动承担 —— 那本来就是它的职责。
                        speechService.announce(message)
                    }, onCompletion: { completion in
                        onRecognitionCompleted?(completion)
                    })
                } label: {
                    Image(systemName: isListening ? "mic.fill" : "mic")
                        .font(.title2)
                        .frame(width: 52, height: 52)
                        .background(isListening ? AppColors.warning : AppColors.primary)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .accessibilityHidden(true)
                }
                .accessibilityLabel(isListening ? "停止语音输入\(title)" : "语音输入\(title)")
                .accessibilityHint(isListening ? "点击后停止录音" : "点击后开始语音输入")
            }

            if isListening {
                HStack(spacing: 6) {
                    Image(systemName: "waveform")
                        .accessibilityHidden(true)
                    Text("正在聆听...")
                }
                .font(AppFonts.caption())
                .foregroundColor(AppColors.textSecondary)
                .accessibilityLabel("\(title)正在聆听")
            }

            if let errorMessage = speechInputService.errorMessage {
                Text(errorMessage)
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.destructive)
                    .accessibilityLabel(errorMessage)
            }
        }
        .onDisappear {
            if speechInputService.hasRecognitionSession(for: speechField) {
                speechInputService.cancelRecognitionForLifecycle()
            }
        }
    }
}
