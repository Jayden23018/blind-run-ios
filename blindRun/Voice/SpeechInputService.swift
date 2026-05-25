import AVFoundation
import Combine
import Foundation
import Speech

// MARK: - Speech Input Stop Reason

enum SpeechInputStopReason: Equatable {
    case manual
    case finalResult
    case silenceTimeout(hadDetectedSound: Bool)
    case maxDuration
    case error

    var announcement: String {
        switch self {
        case .manual:
            return "语音输入已关闭。"
        case .finalResult:
            return "语音输入已停止。"
        case .silenceTimeout(let hadDetectedSound):
            return hadDetectedSound ? "语音输入已停止。" : "未检测到声音，已停止语音输入。"
        case .maxDuration:
            return "语音输入已达到最长时间，已停止。"
        case .error:
            return "语音识别失败，请使用键盘输入。"
        }
    }
}

// MARK: - Speech Input Service

/// iOS Speech framework wrapper for text-field dictation only.
/// It is intentionally not used for time parsing or global assistant behavior.
@MainActor
final class SpeechInputService: ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var activeFieldId: String?
    @Published private(set) var lastStopReason: SpeechInputStopReason?
    @Published var errorMessage: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var silenceMonitorTask: Task<Void, Never>?
    private var maxDurationTask: Task<Void, Never>?
    private var announcementHandler: ((String) -> Void)?
    private var didInstallTap = false
    private var recognitionStartedAt: Date?
    private var lastSoundAt: Date?
    private var hasDetectedSound = false

    static let initialSilenceTimeout: TimeInterval = 8
    static let trailingSilenceTimeout: TimeInterval = 3
    static let maximumRecognitionDuration: TimeInterval = 60
    static let speechPowerThreshold: Float = 0.012

    /// Returns whether the given field is currently being listened to.
    func isListening(for fieldId: String) -> Bool {
        isListening && activeFieldId == fieldId
    }

    func startRecognition(
        fieldId: String,
        onTextChanged: @escaping (String) -> Void,
        onAnnouncement: ((String) -> Void)? = nil
    ) {
        announcementHandler = onAnnouncement

        // Tapping the same field while listening → stop
        if isListening && activeFieldId == fieldId {
            stopAudioRecognition(reason: .manual, clearActiveField: true, announce: true)
            return
        }

        // Tapping a different field while listening → stop previous, then start new
        if isListening {
            stopAudioRecognition(reason: .manual, clearActiveField: true, announce: true)
        }

        activeFieldId = fieldId
        errorMessage = nil
        lastStopReason = nil
        Task {
            let speechAuthorized = await requestSpeechAuthorization()
            guard speechAuthorized else {
                errorMessage = "语音识别不可用，请使用键盘输入。"
                announce(errorMessage)
                activeFieldId = nil
                lastStopReason = .error
                return
            }

            let microphoneAuthorized = await requestMicrophoneAuthorization()
            guard microphoneAuthorized else {
                errorMessage = "麦克风不可用，请使用键盘输入。"
                announce(errorMessage)
                activeFieldId = nil
                lastStopReason = .error
                return
            }

            beginRecognition(onTextChanged: onTextChanged)
        }
    }

    func stopRecognition() {
        stopAudioRecognition(reason: .manual, clearActiveField: true, announce: true)
    }

    private func stopAudioRecognition(
        reason: SpeechInputStopReason,
        clearActiveField: Bool,
        announce: Bool
    ) {
        let wasListening = isListening
        cancelStopTimers()

        if audioEngine.isRunning {
            audioEngine.stop()
        }
        if didInstallTap {
            audioEngine.inputNode.removeTap(onBus: 0)
            didInstallTap = false
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
        if wasListening || reason == .error {
            lastStopReason = reason
        }
        recognitionStartedAt = nil
        lastSoundAt = nil
        hasDetectedSound = false
        if clearActiveField {
            activeFieldId = nil
        }

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            // Deactivation is best-effort; keep keyboard fallback available.
        }

        if announce && wasListening {
            self.announce(reason.announcement)
        }
    }

    private func beginRecognition(onTextChanged: @escaping (String) -> Void) {
        guard recognizer?.isAvailable == true else {
            errorMessage = "语音识别暂不可用，请使用键盘输入。"
            announce(errorMessage)
            activeFieldId = nil
            lastStopReason = .error
            return
        }

        stopAudioRecognition(reason: .manual, clearActiveField: false, announce: false)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "语音输入启动失败，请使用键盘输入。"
            announce(errorMessage)
            stopAudioRecognition(reason: .error, clearActiveField: true, announce: false)
            return
        }

        guard audioSession.isInputAvailable,
              audioSession.inputNumberOfChannels > 0,
              audioSession.sampleRate > 0 else {
            errorMessage = "当前运行环境没有可用的麦克风输入，请使用键盘输入。"
            announce(errorMessage)
            stopAudioRecognition(reason: .error, clearActiveField: true, announce: false)
            return
        }

        let inputNode = audioEngine.inputNode
        guard let recordingFormat = validRecordingFormat(from: inputNode) else {
            errorMessage = "当前运行环境没有可用的麦克风输入，请使用键盘输入。"
            announce(errorMessage)
            stopAudioRecognition(reason: .error, clearActiveField: true, announce: false)
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self, weak request] buffer, _ in
            if SpeechInputService.containsAudibleSpeech(in: buffer) {
                Task { @MainActor in
                    self?.markSoundDetected()
                }
            }
            request?.append(buffer)
        }
        didInstallTap = true

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            errorMessage = "语音输入启动失败，请使用键盘输入。"
            announce(errorMessage)
            stopAudioRecognition(reason: .error, clearActiveField: true, announce: false)
            return
        }

        isListening = true
        lastStopReason = nil
        recognitionStartedAt = Date()
        lastSoundAt = nil
        hasDetectedSound = false
        startStopTimers()
        announce("语音输入已开启，请说话。")
        recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    onTextChanged(result.bestTranscription.formattedString)
                    if !result.bestTranscription.formattedString.trimmed.isEmpty {
                        self.markSoundDetected()
                    }
                    if result.isFinal {
                        self.stopAudioRecognition(reason: .finalResult, clearActiveField: true, announce: true)
                    }
                }
                if error != nil, self.isListening {
                    self.errorMessage = SpeechInputStopReason.error.announcement
                    self.stopAudioRecognition(reason: .error, clearActiveField: true, announce: true)
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

    private func startStopTimers() {
        cancelStopTimers()

        silenceMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                await MainActor.run {
                    self?.stopIfSilent()
                }
            }
        }

        maxDurationTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.maximumRecognitionDuration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.isListening else { return }
                self.stopAudioRecognition(reason: .maxDuration, clearActiveField: true, announce: true)
            }
        }
    }

    private func cancelStopTimers() {
        silenceMonitorTask?.cancel()
        silenceMonitorTask = nil
        maxDurationTask?.cancel()
        maxDurationTask = nil
    }

    private func stopIfSilent() {
        guard isListening, let recognitionStartedAt else { return }
        let now = Date()
        if !hasDetectedSound, now.timeIntervalSince(recognitionStartedAt) >= Self.initialSilenceTimeout {
            stopAudioRecognition(
                reason: .silenceTimeout(hadDetectedSound: false),
                clearActiveField: true,
                announce: true
            )
            return
        }
        if hasDetectedSound,
           let lastSoundAt,
           now.timeIntervalSince(lastSoundAt) >= Self.trailingSilenceTimeout {
            stopAudioRecognition(
                reason: .silenceTimeout(hadDetectedSound: true),
                clearActiveField: true,
                announce: true
            )
        }
    }

    private func markSoundDetected() {
        hasDetectedSound = true
        lastSoundAt = Date()
    }

    private func announce(_ message: String?) {
        guard let message, !message.isEmpty else { return }
        announcementHandler?(message)
    }

    private static func containsAudibleSpeech(in buffer: AVAudioPCMBuffer) -> Bool {
        guard let channelData = buffer.floatChannelData, buffer.frameLength > 0 else {
            return false
        }
        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard channelCount > 0 else { return false }

        var sum: Float = 0
        for channelIndex in 0..<channelCount {
            let samples = channelData[channelIndex]
            for frameIndex in 0..<frameLength {
                let sample = samples[frameIndex]
                sum += sample * sample
            }
        }
        let meanSquare = sum / Float(frameLength * channelCount)
        return sqrt(meanSquare) >= speechPowerThreshold
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

    #if DEBUG
    func startRecognitionForTesting(fieldId: String) {
        activeFieldId = fieldId
        isListening = true
        recognitionStartedAt = Date()
        lastStopReason = nil
    }

    func triggerSilenceTimeoutForTesting(hadDetectedSound: Bool) {
        hasDetectedSound = hadDetectedSound
        stopAudioRecognition(
            reason: .silenceTimeout(hadDetectedSound: hadDetectedSound),
            clearActiveField: true,
            announce: false
        )
    }
    #endif
}

private extension AVAudioFormat {
    var hasValidSampleRateAndChannels: Bool {
        sampleRate > 0 && channelCount > 0
    }
}
