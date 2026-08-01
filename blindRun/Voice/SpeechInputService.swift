import AVFoundation
import Combine
import Foundation
import OSLog
import Speech

// MARK: - Speech Audio Session

@MainActor
protocol SpeechAudioSessionManaging: AnyObject {
    var isInputAvailable: Bool { get }
    var inputNumberOfChannels: Int { get }
    var sampleRate: Double { get }

    func requestRecordPermission(_ response: @escaping (Bool) -> Void)
    func configureRecordingCategory() throws
    func activateRecording() throws
    func deactivateRecording() throws
    func configurePlaybackCategory() throws
    func activatePlayback() throws
}

@MainActor
final class SystemSpeechAudioSession: SpeechAudioSessionManaging {
    private let session: AVAudioSession

    init(session: AVAudioSession = .sharedInstance()) {
        self.session = session
    }

    var isInputAvailable: Bool { session.isInputAvailable }
    var inputNumberOfChannels: Int { session.inputNumberOfChannels }
    var sampleRate: Double { session.sampleRate }

    func requestRecordPermission(_ response: @escaping (Bool) -> Void) {
        session.requestRecordPermission(response)
    }

    func configureRecordingCategory() throws {
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
    }

    func activateRecording() throws {
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    func deactivateRecording() throws {
        try session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    func configurePlaybackCategory() throws {
        try session.setCategory(.playback, mode: .spokenAudio, options: [])
    }

    func activatePlayback() throws {
        try session.setActive(true)
    }
}

// MARK: - Speech Input Field

enum SpeechInputField: String, CaseIterable, Identifiable {
    case startPlaceSearch
    case startLocationDescription
    case destinationRoute
    case remark
    case ratingFeedback
    case volunteerServiceSummary
    // 语音下单向导的三个槽位。与上面的字段听写共用同一套授权/静音超时/最长时长，
    // 区别只在识别结果不回填输入框，而是交给后端解析端点。
    case voiceOrderStartPlace
    case voiceOrderStartTime
    case voiceOrderDuration

    var id: String { rawValue }

    static func isAllowlisted(_ fieldId: String) -> Bool {
        Self(rawValue: fieldId) != nil
    }
}

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

    var shouldTriggerSearchWithRecognizedText: Bool {
        switch self {
        case .manual, .finalResult, .silenceTimeout(hadDetectedSound: true), .maxDuration:
            return true
        case .silenceTimeout(hadDetectedSound: false), .error:
            return false
        }
    }
}

struct SpeechInputCompletion: Equatable {
    let field: SpeechInputField
    let recognizedText: String
    let reason: SpeechInputStopReason
}

// MARK: - Speech Input Service

/// iOS Speech framework wrapper for text-field dictation only.
/// It is intentionally not used for time parsing or global assistant behavior.
@MainActor
final class SpeechInputService: ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var activeField: SpeechInputField?
    @Published private(set) var lastStopReason: SpeechInputStopReason?
    @Published var errorMessage: String?
    @Published private(set) var audioSessionDiagnosticMessage: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "zh-CN"))
    private let audioEngine = AVAudioEngine()
    private let audioSession: any SpeechAudioSessionManaging
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "AidRun", category: "SpeechInput")
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionStartTask: Task<Void, Never>?
    private var recognitionSessionID = UUID()
    private var silenceMonitorTask: Task<Void, Never>?
    private var maxDurationTask: Task<Void, Never>?
    private var announcementHandler: ((String) -> Void)?
    private var completionHandler: ((SpeechInputCompletion) -> Void)?
    private var didInstallTap = false
    private var recognitionStartedAt: Date?
    private var lastSoundAt: Date?
    private var hasDetectedSound = false
    private var currentRecognizedText = ""

    static let initialSilenceTimeout: TimeInterval = 8
    static let trailingSilenceTimeout: TimeInterval = 3
    static let maximumRecognitionDuration: TimeInterval = 60
    static let speechPowerThreshold: Float = 0.012
    static let keyboardFallbackErrorMessage = "语音识别失败，请使用键盘输入。"

    init(audioSession: (any SpeechAudioSessionManaging)? = nil) {
        self.audioSession = audioSession ?? SystemSpeechAudioSession()
    }

    var activeFieldId: String? {
        activeField?.rawValue
    }

    /// Returns whether the given field is currently being listened to.
    func isListening(for field: SpeechInputField) -> Bool {
        isListening && activeField == field
    }

    /// Returns whether the given field owns the current recognition session,
    /// including the pending authorization window before recording starts.
    func hasRecognitionSession(for field: SpeechInputField) -> Bool {
        activeField == field
    }

    func startRecognition(
        field: SpeechInputField,
        onTextChanged: @escaping (String) -> Void,
        onAnnouncement: ((String) -> Void)? = nil,
        onCompletion: ((SpeechInputCompletion) -> Void)? = nil
    ) {
        if stopActiveRecognitionIfNeeded(beforeStarting: field) {
            return
        }

        announcementHandler = onAnnouncement
        completionHandler = onCompletion

        recognitionStartTask?.cancel()
        let sessionID = UUID()
        recognitionSessionID = sessionID
        activeField = field
        errorMessage = nil
        lastStopReason = nil
        currentRecognizedText = ""
        recognitionStartTask = Task { [weak self] in
            guard let self else { return }
            let speechAuthorized = await requestSpeechAuthorization()
            guard isCurrentRecognitionSession(sessionID, field: field) else { return }
            guard speechAuthorized else {
                errorMessage = "语音识别不可用，请使用键盘输入。"
                announce(errorMessage)
                clearRecognitionStartState(marking: .error)
                lastStopReason = .error
                return
            }

            let microphoneAuthorized = await requestMicrophoneAuthorization()
            guard isCurrentRecognitionSession(sessionID, field: field) else { return }
            guard microphoneAuthorized else {
                errorMessage = "麦克风不可用，请使用键盘输入。"
                announce(errorMessage)
                clearRecognitionStartState(marking: .error)
                lastStopReason = .error
                return
            }

            guard isCurrentRecognitionSession(sessionID, field: field) else { return }
            beginRecognition(onTextChanged: onTextChanged)
            if recognitionStartTask != nil, recognitionSessionID == sessionID {
                recognitionStartTask = nil
            }
        }
    }

    func stopRecognition() {
        stopAudioRecognition(reason: .manual, clearActiveField: true, announce: true, notifyCompletion: true, clearHandlers: true, invalidateSession: true)
    }

    func cancelRecognitionForLifecycle() {
        stopAudioRecognition(reason: .manual, clearActiveField: true, announce: false, notifyCompletion: false, clearHandlers: true, invalidateSession: true)
    }

    @discardableResult
    private func stopActiveRecognitionIfNeeded(beforeStarting field: SpeechInputField) -> Bool {
        if isListening && activeField == field {
            stopAudioRecognition(reason: .manual, clearActiveField: true, announce: true, notifyCompletion: true, clearHandlers: true)
            return true
        }

        if isListening {
            stopAudioRecognition(reason: .manual, clearActiveField: true, announce: true, notifyCompletion: true, clearHandlers: true)
        }

        return false
    }

    private func stopAudioRecognition(
        reason: SpeechInputStopReason,
        clearActiveField: Bool,
        announce: Bool,
        notifyCompletion: Bool,
        clearHandlers: Bool,
        invalidateSession: Bool = true,
        announcementAfterRestoration: String? = nil
    ) {
        let wasListening = isListening
        let hadAudioRecognitionSession = wasListening
            || audioEngine.isRunning
            || didInstallTap
            || recognitionRequest != nil
            || recognitionTask != nil
        let completedField = activeField
        let completedText = currentRecognizedText
        let completedHandler = completionHandler
        cancelStopTimers()
        if invalidateSession {
            recognitionSessionID = UUID()
            recognitionStartTask?.cancel()
            recognitionStartTask = nil
        }

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
        if wasListening || reason == .error || (invalidateSession && completedField != nil) {
            lastStopReason = reason
        }
        recognitionStartedAt = nil
        lastSoundAt = nil
        hasDetectedSound = false
        currentRecognizedText = ""
        if clearActiveField {
            activeField = nil
        }

        if hadAudioRecognitionSession {
            restorePlaybackAudioSession()
        }

        self.announce(announcementAfterRestoration)

        if announce && wasListening {
            self.announce(reason.announcement)
        }

        if notifyCompletion, (wasListening || reason == .error), let completedField {
            completedHandler?(SpeechInputCompletion(
                field: completedField,
                recognizedText: completedText,
                reason: reason
            ))
        }

        if clearHandlers {
            announcementHandler = nil
            completionHandler = nil
        }
    }

    private func isCurrentRecognitionSession(_ sessionID: UUID, field: SpeechInputField) -> Bool {
        recognitionSessionID == sessionID && activeField == field && !Task.isCancelled
    }

    private func clearRecognitionStartState(marking reason: SpeechInputStopReason) {
        recognitionSessionID = UUID()
        recognitionStartTask = nil
        activeField = nil
        lastStopReason = reason
        announcementHandler = nil
        completionHandler = nil
    }

    private func beginRecognition(onTextChanged: @escaping (String) -> Void) {
        guard recognizer?.isAvailable == true else {
            errorMessage = "语音识别暂不可用，请使用键盘输入。"
            announce(errorMessage)
            clearRecognitionStartState(marking: .error)
            return
        }

        stopAudioRecognition(reason: .manual, clearActiveField: false, announce: false, notifyCompletion: false, clearHandlers: false, invalidateSession: false)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        do {
            audioSessionDiagnosticMessage = nil
            try audioSession.configureRecordingCategory()
            try audioSession.activateRecording()
        } catch {
            handleRecognitionStartupFailure("语音输入启动失败，请使用键盘输入。")
            return
        }

        guard audioSession.isInputAvailable,
              audioSession.inputNumberOfChannels > 0,
              audioSession.sampleRate > 0 else {
            handleRecognitionStartupFailure("当前运行环境没有可用的麦克风输入，请使用键盘输入。")
            return
        }

        let inputNode = audioEngine.inputNode
        guard let recordingFormat = validRecordingFormat(from: inputNode) else {
            handleRecognitionStartupFailure("当前运行环境没有可用的麦克风输入，请使用键盘输入。")
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
            handleRecognitionStartupFailure("语音输入启动失败，请使用键盘输入。")
            return
        }

        isListening = true
        lastStopReason = nil
        recognitionStartedAt = Date()
        lastSoundAt = nil
        hasDetectedSound = false
        currentRecognizedText = ""
        startStopTimers()
        announce("语音输入已开启，请说话。")
        recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    let recognizedText = result.bestTranscription.formattedString
                    self.currentRecognizedText = recognizedText
                    onTextChanged(recognizedText)
                    if !recognizedText.trimmed.isEmpty {
                        self.markSoundDetected()
                    }
                    if result.isFinal {
                        self.stopAudioRecognition(reason: .finalResult, clearActiveField: true, announce: true, notifyCompletion: true, clearHandlers: true)
                    }
                }
                if error != nil, self.isListening {
                    self.errorMessage = SpeechInputStopReason.error.announcement
                    self.stopAudioRecognition(reason: .error, clearActiveField: true, announce: true, notifyCompletion: true, clearHandlers: true)
                }
            }
        }
    }

    private func handleRecognitionStartupFailure(_ message: String) {
        errorMessage = message
        stopAudioRecognition(
            reason: .error,
            clearActiveField: true,
            announce: false,
            notifyCompletion: true,
            clearHandlers: true,
            announcementAfterRestoration: message
        )
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
                self.stopAudioRecognition(reason: .maxDuration, clearActiveField: true, announce: true, notifyCompletion: true, clearHandlers: true)
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
                announce: true,
                notifyCompletion: true,
                clearHandlers: true
            )
            return
        }
        if hasDetectedSound,
           let lastSoundAt,
           now.timeIntervalSince(lastSoundAt) >= Self.trailingSilenceTimeout {
            stopAudioRecognition(
                reason: .silenceTimeout(hadDetectedSound: true),
                clearActiveField: true,
                announce: true,
                notifyCompletion: true,
                clearHandlers: true
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
            audioSession.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func restorePlaybackAudioSession() {
        var recoveryFailures: [String] = []

        do {
            try audioSession.deactivateRecording()
        } catch {
            recoveryFailures.append("deactivate: \(error.localizedDescription)")
        }

        do {
            try audioSession.configurePlaybackCategory()
        } catch {
            recoveryFailures.append("category: \(error.localizedDescription)")
        }

        do {
            try audioSession.activatePlayback()
        } catch {
            recoveryFailures.append("activate: \(error.localizedDescription)")
        }

        guard !recoveryFailures.isEmpty else {
            audioSessionDiagnosticMessage = nil
            return
        }

        let message = "语音输入结束后恢复播放音频会话失败：\(recoveryFailures.joined(separator: "; "))"
        audioSessionDiagnosticMessage = message
        logger.error("\(message, privacy: .public)")
    }

    #if DEBUG
    func startRecognitionForTesting(fieldId: String) {
        guard let field = SpeechInputField(rawValue: fieldId) else {
            errorMessage = Self.keyboardFallbackErrorMessage
            activeField = nil
            isListening = false
            lastStopReason = .error
            return
        }
        startRecognitionForTesting(field: field)
    }

    func startRecognitionForTesting(
        field: SpeechInputField,
        onAnnouncement: ((String) -> Void)? = nil,
        onCompletion: ((SpeechInputCompletion) -> Void)? = nil
    ) {
        if stopActiveRecognitionIfNeeded(beforeStarting: field) {
            return
        }

        recognitionSessionID = UUID()
        activeField = field
        isListening = true
        recognitionStartedAt = Date()
        lastStopReason = nil
        currentRecognizedText = ""
        announcementHandler = onAnnouncement
        completionHandler = onCompletion
    }

    func failRecognitionStartupForTesting(_ message: String) {
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        handleRecognitionStartupFailure(message)
    }

    @discardableResult
    func startPendingAuthorizationForTesting(
        field: SpeechInputField,
        onCompletion: ((SpeechInputCompletion) -> Void)? = nil
    ) -> UUID {
        if stopActiveRecognitionIfNeeded(beforeStarting: field) {
            recognitionSessionID = UUID()
        }
        let sessionID = UUID()
        recognitionSessionID = sessionID
        activeField = field
        isListening = false
        recognitionStartedAt = nil
        lastStopReason = nil
        currentRecognizedText = ""
        completionHandler = onCompletion
        return sessionID
    }

    func simulateAuthorizationCompletionForTesting(
        sessionID: UUID,
        field: SpeechInputField
    ) {
        guard isCurrentRecognitionSession(sessionID, field: field) else { return }
        isListening = true
        recognitionStartedAt = Date()
    }

    func finishRecognitionForTesting(
        text: String,
        reason: SpeechInputStopReason = .finalResult
    ) {
        currentRecognizedText = text
        stopAudioRecognition(reason: reason, clearActiveField: true, announce: false, notifyCompletion: true, clearHandlers: true)
    }

    func simulateRecognitionFailureForTesting(field: SpeechInputField) {
        activeField = field
        isListening = true
        errorMessage = Self.keyboardFallbackErrorMessage
        stopAudioRecognition(reason: .error, clearActiveField: true, announce: false, notifyCompletion: true, clearHandlers: true)
    }

    func triggerSilenceTimeoutForTesting(hadDetectedSound: Bool) {
        hasDetectedSound = hadDetectedSound
        stopAudioRecognition(
            reason: .silenceTimeout(hadDetectedSound: hadDetectedSound),
            clearActiveField: true,
            announce: false,
            notifyCompletion: true,
            clearHandlers: true
        )
    }
    #endif
}

private extension AVAudioFormat {
    var hasValidSampleRateAndChannels: Bool {
        sampleRate > 0 && channelCount > 0
    }
}
