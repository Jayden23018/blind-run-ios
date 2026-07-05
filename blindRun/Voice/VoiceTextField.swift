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
                        speechService.speak(text: message)
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
    }
}
