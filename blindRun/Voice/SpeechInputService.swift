import AVFoundation
import Combine
import Foundation
import Speech

// MARK: - Speech Input Service

/// iOS Speech framework wrapper for text-field dictation only.
/// It is intentionally not used for time parsing or global assistant behavior.
@MainActor
final class SpeechInputService: ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var activeFieldId: String?
    @Published var errorMessage: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    /// Returns whether the given field is currently being listened to.
    func isListening(for fieldId: String) -> Bool {
        isListening && activeFieldId == fieldId
    }

    func startRecognition(fieldId: String, onTextChanged: @escaping (String) -> Void) {
        // Tapping the same field while listening → stop
        if isListening && activeFieldId == fieldId {
            stopRecognition()
            return
        }

        // Tapping a different field while listening → stop previous, then start new
        if isListening {
            stopRecognition()
        }

        activeFieldId = fieldId
        errorMessage = nil
        Task {
            let speechAuthorized = await requestSpeechAuthorization()
            guard speechAuthorized else {
                errorMessage = "语音识别不可用，请使用键盘输入。"
                activeFieldId = nil
                return
            }

            let microphoneAuthorized = await requestMicrophoneAuthorization()
            guard microphoneAuthorized else {
                errorMessage = "麦克风不可用，请使用键盘输入。"
                activeFieldId = nil
                return
            }

            beginRecognition(onTextChanged: onTextChanged)
        }
    }

    func stopRecognition() {
        stopAudioRecognition(clearActiveField: true)
    }

    private func stopAudioRecognition(clearActiveField: Bool) {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
        if clearActiveField {
            activeFieldId = nil
        }

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            // Deactivation is best-effort; keep keyboard fallback available.
        }
    }

    private func beginRecognition(onTextChanged: @escaping (String) -> Void) {
        guard recognizer?.isAvailable == true else {
            errorMessage = "语音识别暂不可用，请使用键盘输入。"
            activeFieldId = nil
            return
        }

        stopAudioRecognition(clearActiveField: false)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "语音输入启动失败，请使用键盘输入。"
            stopAudioRecognition(clearActiveField: true)
            return
        }

        guard audioSession.isInputAvailable,
              audioSession.inputNumberOfChannels > 0,
              audioSession.sampleRate > 0 else {
            errorMessage = "当前运行环境没有可用的麦克风输入，请使用键盘输入。"
            stopAudioRecognition(clearActiveField: true)
            return
        }

        let inputNode = audioEngine.inputNode
        guard let recordingFormat = validRecordingFormat(from: inputNode) else {
            errorMessage = "当前运行环境没有可用的麦克风输入，请使用键盘输入。"
            stopAudioRecognition(clearActiveField: true)
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak request] buffer, _ in
            request?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            errorMessage = "语音输入启动失败，请使用键盘输入。"
            stopRecognition()
            return
        }

        isListening = true
        recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    onTextChanged(result.bestTranscription.formattedString)
                    if result.isFinal {
                        self.stopRecognition()
                    }
                }
                if error != nil {
                    self.errorMessage = "语音识别失败，请使用键盘输入。"
                    self.stopRecognition()
                }
            }
        }
    }

    private func validRecordingFormat(from inputNode: AVAudioInputNode) -> AVAudioFormat? {
        let outputFormat = inputNode.outputFormat(forBus: 0)
        if outputFormat.hasValidSampleRateAndChannels {
            return outputFormat
        }

        let inputFormat = inputNode.inputFormat(forBus: 0)
        if inputFormat.hasValidSampleRateAndChannels {
            return inputFormat
        }

        return nil
    }

    private func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private func requestMicrophoneAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}

private extension AVAudioFormat {
    var hasValidSampleRateAndChannels: Bool {
        sampleRate > 0 && channelCount > 0
    }
}
