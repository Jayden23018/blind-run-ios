import Combine
import Foundation
import SafariServices
import SwiftUI
#if canImport(AliyunFaceAuthFacade)
import AliyunFaceAuthFacade
#endif

// MARK: - Registration Step

enum RegistrationStep: Int, CaseIterable {
    case basicInfo = 1
    case faceVerify = 3
    case training = 4

    var title: String {
        switch self {
        case .basicInfo: return "基本信息与身份核验"
        case .faceVerify: return "活体认证"
        case .training: return "培训学习"
        }
    }

    var displayIndex: Int {
        switch self {
        case .basicInfo: return 1
        case .faceVerify: return 2
        case .training: return 3
        }
    }
}

// MARK: - CloudAuth MetaInfo

protocol CloudAuthMetaInfoProviding: Sendable {
    func collectMetaInfo(environment: APIEnvironment) async throws -> String
}

enum CloudAuthMetaInfoError: LocalizedError, Sendable {
    case sdkNotConfigured
    case sdkMetaInfoUnavailable
    case sdkMetaInfoSerializationFailed

    var errorDescription: String? {
        switch self {
        case .sdkNotConfigured:
            return "活体认证 SDK 未配置，请更新客户端后重试"
        case .sdkMetaInfoUnavailable, .sdkMetaInfoSerializationFailed:
            return "活体认证 SDK 初始化失败，请重试"
        }
    }
}

struct DefaultCloudAuthMetaInfoProvider: CloudAuthMetaInfoProviding {
    func collectMetaInfo(environment: APIEnvironment) async throws -> String {
        if environment.isMock {
            return #"{"platform":"ios","mock":true,"sdk":"cloud-auth-placeholder"}"#
        }
        #if canImport(AliyunFaceAuthFacade)
        AliyunFaceAuthFacade.initSDK()
        let metaInfo = AliyunFaceAuthFacade.getMetaInfo()
        return try Self.serializedMetaInfo(from: metaInfo)
        #else
        throw CloudAuthMetaInfoError.sdkNotConfigured
        #endif
    }

    nonisolated static func serializedMetaInfo(from dictionary: [AnyHashable: Any]) throws -> String {
        guard !dictionary.isEmpty else {
            throw CloudAuthMetaInfoError.sdkMetaInfoUnavailable
        }
        let jsonObject = normalizedJSONObject(from: dictionary)
        guard JSONSerialization.isValidJSONObject(jsonObject) else {
            throw CloudAuthMetaInfoError.sdkMetaInfoSerializationFailed
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: jsonObject, options: [.sortedKeys])
            guard let jsonString = String(data: data, encoding: .utf8), !jsonString.isEmpty else {
                throw CloudAuthMetaInfoError.sdkMetaInfoSerializationFailed
            }
            return jsonString
        } catch let error as CloudAuthMetaInfoError {
            throw error
        } catch {
            throw CloudAuthMetaInfoError.sdkMetaInfoSerializationFailed
        }
    }

    nonisolated private static func normalizedJSONObject(from dictionary: [AnyHashable: Any]) -> [String: Any] {
        var object: [String: Any] = [:]
        for (key, value) in dictionary {
            object[String(describing: key.base)] = normalizedJSONValue(value)
        }
        return object
    }

    nonisolated private static func normalizedJSONValue(_ value: Any) -> Any {
        if let dictionary = value as? [AnyHashable: Any] {
            return normalizedJSONObject(from: dictionary)
        }
        if let dictionary = value as? NSDictionary {
            var normalized: [String: Any] = [:]
            for (key, value) in dictionary {
                normalized[String(describing: key)] = normalizedJSONValue(value)
            }
            return normalized
        }
        if let array = value as? [Any] {
            return array.map(normalizedJSONValue)
        }
        if let array = value as? NSArray {
            return array.map(normalizedJSONValue)
        }
        return value
    }
}

struct FixedCloudAuthMetaInfoProvider: CloudAuthMetaInfoProviding {
    let metaInfo: String

    func collectMetaInfo(environment: APIEnvironment) async throws -> String {
        metaInfo
    }
}

struct CloudAuthSession: Identifiable, Sendable {
    let id = UUID()
    let certifyId: String
    let url: URL
}

// MARK: - Registration ViewModel

@MainActor
final class VolunteerRegistrationViewModel: ObservableObject {
    @Published var currentStep: RegistrationStep = .basicInfo
    @Published var isLoading = false
    @Published var errorMessage: String?

    // Step 1
    @Published var name = ""
    @Published var phone = "" {
        didSet {
            let normalized = Self.normalizedPhoneNumber(phone)
            if normalized != phone {
                phone = normalized
            }
        }
    }
    @Published var idCardName = ""
    @Published var idCardNumber = "" {
        didSet {
            let normalized = Self.normalizedIdCardNumber(idCardNumber)
            if normalized != idCardNumber {
                idCardNumber = normalized
            }
        }
    }
    @Published var runningExperience = ""
    @Published var hasGuidedBefore = false
    @Published var emergencyExperience = ""

    // Step 3
    @Published var cloudAuthSession: CloudAuthSession?
    @Published var activeCertifyId: String?
    @Published var faceVerifyMessage: String?
    @Published var isPollingFaceResult = false
    @Published var canReturnToBasicInfoForIdentityEdit = false

    // Step 4
    @Published var courses: [TrainingCourseResponse] = []
    @Published var currentCourseQuestions: [QuizQuestionResponse] = []
    @Published var selectedCourseId: Int64?
    @Published var quizSelections: [Int64: Set<String>] = [:]
    @Published var quizResultMessage: String?
    @Published var trainingCompleted = false

    @Published var registrationStatus: VolunteerRegistrationStatus?

    private weak var appState: AppState?
    private var speechService: SpeechService?
    private let apiClientOverride: (any APIClientProtocol)?
    private let metaInfoProvider: any CloudAuthMetaInfoProviding
    private var courseProgressById: [Int64: Int] = [:]

    static let idCardNumberRegex = #"^\d{17}[\dXx]$"#
    static let faceResultPollingIntervalNanoseconds: UInt64 = 3_000_000_000
    nonisolated static let maxFaceResultPollingAttempts = 240

    static func normalizedPhoneNumber(_ value: String) -> String {
        String(value.filter(\.isNumber).prefix(11))
    }

    static func normalizedIdCardNumber(_ value: String) -> String {
        String(value.filter { $0.isNumber || $0 == "X" || $0 == "x" }.prefix(18))
    }

    init(
        apiClient: (any APIClientProtocol)? = nil,
        metaInfoProvider: (any CloudAuthMetaInfoProviding)? = nil
    ) {
        self.apiClientOverride = apiClient
        self.metaInfoProvider = metaInfoProvider ?? DefaultCloudAuthMetaInfoProvider()
    }

    var canSubmitBasicInfo: Bool {
        basicInfoValidationMessage == nil && !isLoading
    }

    var basicInfoValidationMessage: String? {
        if name.trimmed.isEmpty {
            return "请填写姓名"
        }
        if !AppState.isValidMainlandPhone(phone.trimmed) {
            return "请输入 11 位中国大陆手机号"
        }
        return identityInfoValidationMessage
    }

    var identityInfoValidationMessage: String? {
        if idCardNumber.trimmed.range(of: Self.idCardNumberRegex, options: .regularExpression) == nil {
            return "请输入18位有效身份证号码"
        }
        return nil
    }

    var canStartFaceVerify: Bool {
        currentStep == .faceVerify && !isLoading && !isPollingFaceResult
    }

    var faceVerifyButtonTitle: String {
        activeCertifyId == nil ? "开始活体认证" : "重新开始活体认证"
    }

    var shouldPollRegistrationStatus: Bool {
        currentStep == .training && !trainingCompleted
    }

    var selectedCourse: TrainingCourseResponse? {
        guard let selectedCourseId else { return nil }
        return courses.first { $0.id == selectedCourseId }
    }

    func configure(appState: AppState, speechService: SpeechService) {
        self.appState = appState
        self.speechService = speechService
        phone = ""
    }

    // MARK: - Load Registration Status

    func loadStatus(showLoading: Bool = true) async {
        guard let appState else { return }
        if showLoading {
            isLoading = true
        }
        do {
            let status: VolunteerRegistrationStatus = try await activeAPIClient(appState: appState).get("/api/volunteer/registration/status")
            applyRegistrationStatus(status)
            isLoading = false
        } catch let error as APIError {
            isLoading = false
            if appState.handleAuthenticatedAPIError(error) {
                return
            }
            if showLoading {
                currentStep = .basicInfo
            }
        } catch {
            isLoading = false
            if showLoading {
                currentStep = .basicInfo
            }
        }
    }

    func pollStatusWhileNeeded() async {
        while shouldPollRegistrationStatus && !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            await loadStatus(showLoading: false)
        }
    }

    func applyRegistrationStatus(_ status: VolunteerRegistrationStatus) {
        registrationStatus = status
        appState?.updateVolunteerRegistrationStatus(status)
        currentStep = resolvedRegistrationStep(from: status)
        if currentStep != .faceVerify {
            canReturnToBasicInfoForIdentityEdit = false
        }
        trainingCompleted = status.isRegistrationComplete || (status.trainingCompleted ?? trainingCompleted)
        if trainingCompleted {
            quizResultMessage = "注册流程已完成，现在可以接单"
        }
    }

    private func resolvedRegistrationStep(from status: VolunteerRegistrationStatus) -> RegistrationStep {
        let stepCode = (status.registrationStep ?? status.currentStepCode)?.uppercased()
        switch stepCode {
        case "STEP_1_BASIC_INFO", "STEP_2_ID_UPLOAD":
            return .basicInfo
        case "STEP_3_FACE_VERIFY":
            return .faceVerify
        case "STEP_4_TRAINING", "STEP_4_COMPLETED":
            return .training
        default:
            break
        }

        if let currentStep = status.currentStep {
            switch currentStep {
            case 1, 2:
                return .basicInfo
            case 3:
                return .faceVerify
            case 4:
                return .training
            default:
                break
            }
        }

        let faceStatus = (status.faceVerifyStatus ?? status.stepDetails?.faceVerifyStatus ?? "").uppercased()
        let idStatus = (status.idVerifyStatus ?? status.stepDetails?.idVerifyStatus ?? "").uppercased()
        if status.step3Completed == true || faceStatus == "APPROVED" || faceStatus == "PASSED" {
            return .training
        }
        if status.step1Completed == true || idStatus == "APPROVED" {
            return .faceVerify
        }
        return .basicInfo
    }

    // MARK: - Step 1

    func submitBasicInfo() async {
        if let message = basicInfoValidationMessage {
            errorMessage = message
            speechService?.speakError(message)
            return
        }
        guard let appState else { return }
        isLoading = true
        errorMessage = nil

        let request = BasicInfoRequest(
            name: name.trimmed,
            phone: phone.trimmed,
            idCardName: name.trimmed,
            idCardNumber: idCardNumber.trimmed,
            runningExperience: runningExperience.trimmed.isEmpty ? nil : runningExperience.trimmed,
            hasGuidedBefore: hasGuidedBefore,
            emergencyExperience: emergencyExperience.trimmed.isEmpty ? nil : emergencyExperience.trimmed
        )

        do {
            let _: EmptyResponse = try await activeAPIClient(appState: appState).post("/api/volunteer/registration/step1", body: request)
            await syncStatusAfterBasicInfoSuccess(appState: appState)
        } catch let error as APIError {
            if appState.handleAuthenticatedAPIError(error) {
                isLoading = false
                return
            }
            await handleBasicInfoSubmissionError(error)
        } catch {
            isLoading = false
            errorMessage = "提交失败，请重试"
            speechService?.speakError("提交失败，请重试")
        }
    }

    private func syncStatusAfterBasicInfoSuccess(appState: AppState) async {
        do {
            let status: VolunteerRegistrationStatus = try await activeAPIClient(appState: appState).get("/api/volunteer/registration/status")
            applyRegistrationStatus(status)
        } catch {
            currentStep = .faceVerify
        }
        isLoading = false
        switch currentStep {
        case .basicInfo:
            speechService?.speak("身份信息已提交，请等待状态同步")
        case .faceVerify:
            faceVerifyMessage = "身份核验通过，请开始活体认证"
            speechService?.speak("身份核验通过，请开始活体认证")
        case .training:
            speechService?.speak("身份与活体认证已完成，请继续培训学习")
        }
    }

    private func handleBasicInfoSubmissionError(_ error: APIError) async {
        let previousStep = currentStep
        let localizedMessage = error.localizedMessage
        if shouldRefreshRegistrationStatus(after: error), let appState {
            do {
                let status: VolunteerRegistrationStatus = try await activeAPIClient(appState: appState).get("/api/volunteer/registration/status")
                applyRegistrationStatus(status)
                isLoading = false
                if currentStep != previousStep {
                    let message = "已同步注册进度，请继续完成\(currentStep.title)"
                    errorMessage = message
                    speechService?.speak(message)
                    return
                }
            } catch {
                // Fall through to the original backend error.
            }
        }

        isLoading = false
        errorMessage = localizedMessage
        speechService?.speakError(localizedMessage)
    }

    private func shouldRefreshRegistrationStatus(after error: APIError) -> Bool {
        guard case .serverError(let response) = error else {
            return false
        }
        let normalizedMessage = response.message.uppercased()
        return normalizedMessage.contains("CURRENT STEP") ||
            normalizedMessage.contains("当前步骤") ||
            normalizedMessage.contains("STEP_")
    }

    func refreshStatus() {
        Task { await loadStatus(showLoading: false) }
    }

    // MARK: - Step 3

    func startFaceVerify() async {
        guard canStartFaceVerify, let appState else { return }
        isLoading = true
        errorMessage = nil
        faceVerifyMessage = nil
        canReturnToBasicInfoForIdentityEdit = false

        do {
            let metaInfo = try await metaInfoProvider.collectMetaInfo(environment: appState.currentEnvironment)
            let request = FaceVerifyInitRequest(metaInfo: metaInfo)
            let response: FaceVerifyInitResponse = try await activeAPIClient(appState: appState).post(
                "/api/volunteer/registration/step3/face-verify/init",
                body: request
            )
            isLoading = false
            await handleFaceVerifyInitResponse(response)
        } catch let error as CloudAuthMetaInfoError {
            isLoading = false
            let message = error.localizedDescription
            errorMessage = message
            speechService?.speakError(message)
        } catch let error as APIError {
            isLoading = false
            if appState.handleAuthenticatedAPIError(error) {
                return
            }
            if isIdentityInfoError(error) {
                await handleFaceVerifyIdentityInfoError(error.localizedMessage)
                return
            }
            errorMessage = error.localizedMessage
            speechService?.speakError(error.localizedMessage)
        } catch {
            isLoading = false
            errorMessage = "活体认证发起失败，请重试"
            speechService?.speakError("活体认证发起失败，请重试")
        }
    }

    private func handleFaceVerifyInitResponse(_ response: FaceVerifyInitResponse) async {
        if response.isError {
            let message = response.message ?? "活体认证发起失败，请重试"
            if isIdentityInfoMessage(message) {
                await handleFaceVerifyIdentityInfoError(message)
                return
            }
            errorMessage = message
            speechService?.speakError(message)
            return
        }
        guard let certifyId = response.certifyId,
              !certifyId.trimmed.isEmpty,
              let urlString = response.certifyUrl,
              let url = URL(string: urlString) else {
            let message = response.message ?? "活体认证地址无效，请重试"
            errorMessage = message
            speechService?.speakError(message)
            return
        }
        activeCertifyId = certifyId
        cloudAuthSession = CloudAuthSession(certifyId: certifyId, url: url)
        canReturnToBasicInfoForIdentityEdit = false
        faceVerifyMessage = response.message ?? "活体认证已发起，请在打开的页面完成眨眼或点头动作"
        speechService?.speak(faceVerifyMessage ?? "活体认证已发起")
    }

    private func handleFaceVerifyIdentityInfoError(_ message: String) async {
        activeCertifyId = nil
        cloudAuthSession = nil
        faceVerifyMessage = nil

        if let appState {
            do {
                let status: VolunteerRegistrationStatus = try await activeAPIClient(appState: appState).get("/api/volunteer/registration/status")
                applyRegistrationStatus(status)
            } catch {
                // Keep the user on the current screen and expose the manual edit path.
            }
        }

        if currentStep == .faceVerify {
            canReturnToBasicInfoForIdentityEdit = true
            errorMessage = message
            speechService?.speakError(message)
        } else {
            canReturnToBasicInfoForIdentityEdit = false
            errorMessage = "请修改身份信息后重新提交"
            speechService?.speakError("请修改身份信息后重新提交")
        }
    }

    private func isIdentityInfoError(_ error: APIError) -> Bool {
        guard case .serverError(let response) = error else {
            return false
        }
        return isIdentityInfoMessage("\(response.code) \(response.message)")
    }

    private func isIdentityInfoMessage(_ message: String) -> Bool {
        let normalizedMessage = message.uppercased()
        return normalizedMessage.contains("身份信息") ||
            normalizedMessage.contains("身份证") ||
            normalizedMessage.contains("IDCARD") ||
            normalizedMessage.contains("ID_CARD") ||
            normalizedMessage.contains("ID_INFO") ||
            normalizedMessage.contains("IDENTITY")
    }

    func returnToBasicInfoForIdentityEdit() {
        currentStep = .basicInfo
        activeCertifyId = nil
        cloudAuthSession = nil
        faceVerifyMessage = nil
        errorMessage = nil
        canReturnToBasicInfoForIdentityEdit = false
        speechService?.speak("请修改姓名和身份证号码后重新提交")
    }

    func pollFaceVerifyResultAfterReturn() {
        guard activeCertifyId != nil else { return }
        Task { await pollFaceVerifyResultUntilFinished() }
    }

    func pollFaceVerifyResultUntilFinished(maxAttempts: Int = maxFaceResultPollingAttempts) async {
        guard activeCertifyId != nil, !isPollingFaceResult else { return }
        isPollingFaceResult = true
        defer { isPollingFaceResult = false }

        for attempt in 0..<maxAttempts {
            guard !Task.isCancelled else { return }
            let finished = await pollFaceVerifyResultOnce()
            if finished {
                return
            }
            if attempt < maxAttempts - 1 {
                try? await Task.sleep(nanoseconds: Self.faceResultPollingIntervalNanoseconds)
            }
        }
        activeCertifyId = nil
        errorMessage = "活体认证结果查询超时，请重新发起认证"
        speechService?.speakError("活体认证结果查询超时，请重新发起认证")
    }

    @discardableResult
    func pollFaceVerifyResultOnce() async -> Bool {
        guard let appState, let certifyId = activeCertifyId else { return true }
        do {
            let request = FaceVerifyResultRequest(certifyId: certifyId)
            let response: FaceVerifyResponse = try await activeAPIClient(appState: appState).post(
                "/api/volunteer/registration/step3/face-verify/result",
                body: request
            )
            return await handleFaceVerifyResult(response)
        } catch let error as APIError {
            if appState.handleAuthenticatedAPIError(error) {
                return true
            }
            errorMessage = error.localizedMessage
            speechService?.speakError(error.localizedMessage)
            return true
        } catch {
            errorMessage = "活体认证结果查询失败，请重试"
            speechService?.speakError("活体认证结果查询失败，请重试")
            return true
        }
    }

    private func handleFaceVerifyResult(_ response: FaceVerifyResponse) async -> Bool {
        if response.isPassed {
            activeCertifyId = nil
            cloudAuthSession = nil
            faceVerifyMessage = response.message ?? "活体认证通过，请完成培训课程"
            currentStep = .training
            speechService?.speak(faceVerifyMessage ?? "活体认证通过")
            await loadCourses()
            await loadStatus(showLoading: false)
            return true
        }
        if response.isPending {
            faceVerifyMessage = response.message ?? "活体认证结果处理中，请稍候"
            return false
        }
        if response.isRejected {
            activeCertifyId = nil
            faceVerifyMessage = nil
            let message = response.message ?? "活体认证未通过，请重新发起认证"
            errorMessage = message
            speechService?.speakError(message)
            return true
        }
        if response.isError {
            activeCertifyId = nil
            faceVerifyMessage = nil
            let message = response.message ?? "活体认证结果异常，请重新发起认证"
            errorMessage = message
            speechService?.speakError(message)
            return true
        }

        activeCertifyId = nil
        let message = response.message ?? "活体认证未通过，请重新发起认证"
        errorMessage = message
        speechService?.speakError(message)
        return true
    }

    // MARK: - Step 4

    func loadCourses() async {
        guard let appState else { return }
        do {
            let courseList: [TrainingCourseResponse] = try await activeAPIClient(appState: appState).get("/api/volunteer/registration/training/courses")
            courses = courseList.sorted { ($0.orderIndex ?? 0) < ($1.orderIndex ?? 0) }
        } catch let error as APIError {
            if appState.handleAuthenticatedAPIError(error) {
                return
            }
            courses = []
            errorMessage = error.localizedMessage
        } catch {
            courses = []
            errorMessage = "培训课程加载失败，请重试"
        }
    }

    func progressPercent(for course: TrainingCourseResponse) -> Int {
        guard let id = course.id else {
            return course.progressPercent ?? 0
        }
        return courseProgressById[id] ?? course.progressPercent ?? (course.status?.uppercased() == "COMPLETED" ? 100 : 0)
    }

    func canLoadQuiz(for course: TrainingCourseResponse) -> Bool {
        progressPercent(for: course) >= 95
    }

    func reportNextTrainingProgress(for course: TrainingCourseResponse) async {
        guard let courseId = course.id, let appState else { return }
        let current = progressPercent(for: course)
        let next = min(current + 10, 100)
        guard next > current else {
            speechService?.speak("课程学习进度已完成")
            return
        }

        let increased = next - current
        let timeSpentSeconds = max(60, increased * 6)
        let durationSeconds = max((course.durationMinutes ?? 1) * 60, 60)
        let lastPositionSeconds = max(0, min(durationSeconds, durationSeconds * next / 100))
        let request = TrainingProgressRequest(
            courseId: courseId,
            progressPercent: next,
            lastPositionSeconds: lastPositionSeconds,
            timeSpentSeconds: timeSpentSeconds
        )

        do {
            let _: EmptyResponse = try await activeAPIClient(appState: appState).post("/api/volunteer/registration/training/progress", body: request)
            courseProgressById[courseId] = next
            speechService?.speak(next >= 95 ? "课程测验已解锁" : "学习进度已更新到\(next)%")
            await loadStatus(showLoading: false)
        } catch let error as APIError {
            if appState.handleAuthenticatedAPIError(error) {
                return
            }
            errorMessage = error.localizedMessage
            speechService?.speakError(error.localizedMessage)
        } catch {
            errorMessage = "学习进度上报失败，请稍后重试"
            speechService?.speakError("学习进度上报失败，请稍后重试")
        }
    }

    func loadQuiz(courseId: Int64) async {
        guard let appState else { return }
        quizResultMessage = nil
        do {
            let questions: [QuizQuestionResponse] = try await activeAPIClient(appState: appState).get("/api/volunteer/registration/training/quiz/\(courseId)")
            selectedCourseId = courseId
            currentCourseQuestions = questions.sorted { ($0.orderIndex ?? 0) < ($1.orderIndex ?? 0) }
            quizSelections = [:]
        } catch let error as APIError {
            if appState.handleAuthenticatedAPIError(error) {
                return
            }
            currentCourseQuestions = []
            errorMessage = error.localizedMessage
        } catch {
            currentCourseQuestions = []
            errorMessage = "测验题目加载失败，请重试"
        }
    }

    func toggleQuizAnswer(question: QuizQuestionResponse, option: String) {
        guard let questionId = question.id else { return }
        let answer = answerValue(from: option)
        if question.questionType?.uppercased().contains("MULTIPLE") == true {
            var values = quizSelections[questionId] ?? []
            if values.contains(answer) {
                values.remove(answer)
            } else {
                values.insert(answer)
            }
            quizSelections[questionId] = values
        } else {
            quizSelections[questionId] = [answer]
        }
    }

    func isOptionSelected(question: QuizQuestionResponse, option: String) -> Bool {
        guard let questionId = question.id else { return false }
        return quizSelections[questionId]?.contains(answerValue(from: option)) == true
    }

    func submitCurrentQuiz() async {
        guard let appState, let courseId = selectedCourseId else { return }
        guard !currentCourseQuestions.isEmpty else {
            errorMessage = "请先加载测验题目"
            return
        }

        let unanswered = currentCourseQuestions.contains { question in
            guard let questionId = question.id else { return true }
            return quizSelections[questionId]?.isEmpty != false
        }
        guard !unanswered else {
            errorMessage = "请完成所有题目后再提交"
            speechService?.speakError("请完成所有题目后再提交")
            return
        }

        isLoading = true
        errorMessage = nil
        var latestResult: QuizAnswerResponse?

        do {
            for question in currentCourseQuestions {
                guard let questionId = question.id else { continue }
                let answers = Array(quizSelections[questionId] ?? []).sorted()
                let request = QuizAnswerRequest(courseId: courseId, questionId: questionId, answers: answers, timeSpentSeconds: 8)
                latestResult = try await activeAPIClient(appState: appState).post("/api/volunteer/registration/training/quiz/answer", body: request)
            }
            isLoading = false
            if latestResult?.passed == true {
                quizResultMessage = "测验通过，正在同步注册状态"
                speechService?.speak("测验通过，正在同步注册状态")
            } else if let score = latestResult?.scorePercent {
                quizResultMessage = "测验得分 \(score)%，未通过可继续重考"
                speechService?.speakError("测验未通过，可继续重考")
            } else {
                quizResultMessage = "测验已提交，请查看结果"
            }
            await loadCourses()
            await loadStatus(showLoading: false)
        } catch let error as APIError {
            isLoading = false
            if appState.handleAuthenticatedAPIError(error) {
                return
            }
            errorMessage = error.localizedMessage
            speechService?.speakError(error.localizedMessage)
        } catch {
            isLoading = false
            errorMessage = "测验提交失败，请重试"
            speechService?.speakError("测验提交失败，请重试")
        }
    }

    private func answerValue(from option: String) -> String {
        let trimmed = option.trimmed
        if let first = trimmed.first, first.isLetter {
            return String(first).uppercased()
        }
        return trimmed
    }

    private func activeAPIClient(appState: AppState) -> any APIClientProtocol {
        apiClientOverride ?? appState.apiClient
    }
}

// MARK: - Registration Flow View

struct VolunteerRegistrationFlowView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel = VolunteerRegistrationViewModel()

    var body: some View {
        VStack(spacing: 0) {
            stepIndicator

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    switch viewModel.currentStep {
                    case .basicInfo:
                        basicInfoStep
                    case .faceVerify:
                        faceVerifyStep
                    case .training:
                        trainingStep
                    }

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(AppFonts.body())
                            .foregroundColor(AppColors.destructive)
                            .accessibilityLabel(errorMessage)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 24)
            }
        }
        .background(AppColors.background)
        .navigationTitle("志愿者注册")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $viewModel.cloudAuthSession, onDismiss: {
            viewModel.pollFaceVerifyResultAfterReturn()
        }) { session in
            SafariView(url: session.url)
                .ignoresSafeArea()
        }
        .task {
            viewModel.configure(appState: appState, speechService: speechService)
            await viewModel.loadStatus()
        }
        .task(id: viewModel.shouldPollRegistrationStatus) {
            guard viewModel.shouldPollRegistrationStatus else { return }
            await viewModel.pollStatusWhileNeeded()
        }
        .onChange(of: scenePhase) { newPhase in
            guard newPhase == .active else { return }
            viewModel.pollFaceVerifyResultAfterReturn()
        }
    }

    // MARK: - Step Indicator

    private var stepIndicator: some View {
        HStack(spacing: 4) {
            ForEach(RegistrationStep.allCases, id: \.rawValue) { step in
                VStack(spacing: 4) {
                    Circle()
                        .fill(step.displayIndex <= viewModel.currentStep.displayIndex ? AppColors.primary : AppColors.textSecondary.opacity(0.3))
                        .frame(width: 28, height: 28)
                        .overlay {
                            Text("\(step.displayIndex)")
                                .font(.caption.bold())
                                .foregroundColor(.white)
                        }
                    Text(step.title)
                        .font(.caption2)
                        .foregroundColor(step == viewModel.currentStep ? AppColors.primary : AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("步骤\(step.displayIndex) \(step.title)")
                .accessibilityValue(step == viewModel.currentStep ? "当前步骤" : step.displayIndex < viewModel.currentStep.displayIndex ? "已完成" : "未完成")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppColors.secondaryBackground)
    }

    // MARK: - Step 1

    private var basicInfoStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("基本信息与身份核验")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)

            Text("请填写基本信息和身份证信息，姓名需与身份证一致。提交后系统会进行身份证二要素核验，通过后进入活体认证。")
                .font(AppFonts.body())
                .foregroundColor(AppColors.textSecondary)

            formField(title: "姓名", placeholder: "请输入真实姓名", text: $viewModel.name)
            formField(title: "手机号", placeholder: "请输入手机号", text: $viewModel.phone)
                .keyboardType(.phonePad)
            formField(title: "身份证号码", placeholder: "请输入18位身份证号码", text: $viewModel.idCardNumber)
                .keyboardType(.asciiCapable)
            formField(title: "跑步经验", placeholder: "描述您的跑步经验（选填）", text: $viewModel.runningExperience)

            Toggle("是否有陪跑经验", isOn: $viewModel.hasGuidedBefore)
                .font(AppFonts.body())
                .accessibilityLabel("是否有陪跑经验")

            formField(title: "急救经验", placeholder: "描述您的急救经验（选填）", text: $viewModel.emergencyExperience)

            if let validationMessage = viewModel.basicInfoValidationMessage {
                Text(validationMessage)
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.destructive)
                    .accessibilityLabel("无法提交身份信息：\(validationMessage)")
            }

            PrimaryButton("提交身份信息", isLoading: viewModel.isLoading) {
                Task { await viewModel.submitBasicInfo() }
            }
            .disabled(!viewModel.canSubmitBasicInfo)
            .opacity(viewModel.canSubmitBasicInfo ? 1 : 0.45)
            .accessibilityLabel("提交身份信息")
            .accessibilityHint(viewModel.basicInfoValidationMessage ?? "提交基本信息和身份证二要素核验")
        }
    }

    // MARK: - Step 3

    private var faceVerifyStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("活体认证")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)

            Text("请在阿里云实人认证页面中按提示完成眨眼或点头动作。完成后返回 App，系统会自动查询认证结果。")
                .font(AppFonts.body())
                .foregroundColor(AppColors.textSecondary)

            if let faceVerifyMessage = viewModel.faceVerifyMessage {
                Text(faceVerifyMessage)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textPrimary)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppColors.secondaryBackground)
                    .cornerRadius(8)
                    .accessibilityLabel(faceVerifyMessage)
            }

            PrimaryButton(viewModel.faceVerifyButtonTitle, isLoading: viewModel.isLoading) {
                Task { await viewModel.startFaceVerify() }
            }
            .disabled(!viewModel.canStartFaceVerify)
            .opacity(viewModel.canStartFaceVerify ? 1 : 0.45)
            .accessibilityLabel(viewModel.faceVerifyButtonTitle)
            .accessibilityHint("发起阿里云动作活体认证")

            if viewModel.canReturnToBasicInfoForIdentityEdit {
                Button("返回修改身份信息") {
                    viewModel.returnToBasicInfoForIdentityEdit()
                }
                .font(AppFonts.body().weight(.semibold))
                .foregroundColor(AppColors.primary)
                .accessibilityLabel("返回修改身份信息")
                .accessibilityHint("返回基本信息页面修改姓名和身份证号码")
            }

            if viewModel.activeCertifyId != nil {
                Button("查询活体认证结果") {
                    Task { await viewModel.pollFaceVerifyResultUntilFinished() }
                }
                .disabled(viewModel.isPollingFaceResult)
                .font(AppFonts.body().weight(.semibold))
                .foregroundColor(viewModel.isPollingFaceResult ? AppColors.textSecondary : AppColors.primary)
                .accessibilityLabel("查询活体认证结果")
            }

            if viewModel.isPollingFaceResult {
                ProgressView("正在查询活体认证结果...")
                    .accessibilityLabel("正在查询活体认证结果")
            }
        }
    }

    // MARK: - Step 4

    private var trainingStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("培训学习")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)

            Text("请完成必修课程学习进度和测验。测验会在课程进度达到95%后解锁。")
                .font(AppFonts.body())
                .foregroundColor(AppColors.textSecondary)

            Button("刷新注册状态") {
                viewModel.refreshStatus()
            }
            .font(AppFonts.body().weight(.semibold))
            .foregroundColor(AppColors.primary)
            .accessibilityLabel("刷新注册状态")

            if viewModel.courses.isEmpty {
                ProgressView("加载课程中...")
                    .task { await viewModel.loadCourses() }
            } else {
                ForEach(viewModel.courses) { course in
                    trainingCourseCard(course)
                }
            }

            if !viewModel.currentCourseQuestions.isEmpty {
                quizSection
            }

            if let quizResultMessage = viewModel.quizResultMessage {
                Text(quizResultMessage)
                    .font(AppFonts.body())
                    .foregroundColor(viewModel.trainingCompleted ? AppColors.success : AppColors.textPrimary)
                    .accessibilityLabel(quizResultMessage)
            }

            if viewModel.trainingCompleted {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(AppColors.success)
                    Text("注册完成，现在可以接单")
                        .font(.title3.bold())
                        .foregroundColor(AppColors.textPrimary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .accessibilityLabel("注册完成，现在可以接单")

                PrimaryButton("返回") {
                    dismiss()
                }
            }
        }
    }

    private func trainingCourseCard(_ course: TrainingCourseResponse) -> some View {
        let progress = viewModel.progressPercent(for: course)
        return VStack(alignment: .leading, spacing: 12) {
            Text(course.title ?? "课程")
                .font(.headline)
                .foregroundColor(AppColors.textPrimary)
            if let desc = course.description {
                Text(desc)
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(2)
            }
            if let duration = course.durationMinutes {
                Text("预计 \(duration) 分钟")
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.textSecondary)
            }

            ProgressView(value: Double(progress), total: 100)
                .accessibilityLabel("课程进度")
                .accessibilityValue("\(progress)%")
            Text("当前进度 \(progress)%")
                .font(AppFonts.caption())
                .foregroundColor(AppColors.textSecondary)

            HStack(spacing: 12) {
                Button {
                    Task { await viewModel.reportNextTrainingProgress(for: course) }
                } label: {
                    Label(progress >= 100 ? "进度已完成" : "上报学习进度", systemImage: "play.circle")
                }
                .disabled(progress >= 100)
                .font(AppFonts.body().weight(.semibold))
                .foregroundColor(progress >= 100 ? AppColors.textSecondary : AppColors.primary)
                .accessibilityLabel(progress >= 100 ? "课程进度已完成" : "上报学习进度")

                if let courseId = course.id {
                    Button {
                        Task { await viewModel.loadQuiz(courseId: courseId) }
                    } label: {
                        Label("加载测验", systemImage: "questionmark.circle")
                    }
                    .disabled(!viewModel.canLoadQuiz(for: course))
                    .font(AppFonts.body().weight(.semibold))
                    .foregroundColor(viewModel.canLoadQuiz(for: course) ? AppColors.primary : AppColors.textSecondary)
                    .accessibilityLabel("加载测验")
                    .accessibilityHint(viewModel.canLoadQuiz(for: course) ? "加载本课程测验题目" : "课程进度达到95%后解锁")
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.secondaryBackground)
        .cornerRadius(8)
        .accessibilityElement(children: .contain)
    }

    private var quizSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("课程测验")
                .font(.headline)
                .foregroundColor(AppColors.textPrimary)
                .accessibilityAddTraits(.isHeader)

            ForEach(viewModel.currentCourseQuestions) { question in
                VStack(alignment: .leading, spacing: 10) {
                    Text(question.questionText ?? "题目")
                        .font(AppFonts.body().weight(.semibold))
                        .foregroundColor(AppColors.textPrimary)
                    ForEach(question.options ?? [], id: \.self) { option in
                        Button {
                            viewModel.toggleQuizAnswer(question: question, option: option)
                        } label: {
                            HStack {
                                Image(systemName: viewModel.isOptionSelected(question: question, option: option) ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(viewModel.isOptionSelected(question: question, option: option) ? AppColors.primary : AppColors.textSecondary)
                                    .accessibilityHidden(true)
                                Text(option)
                                    .font(AppFonts.body())
                                    .foregroundColor(AppColors.textPrimary)
                                Spacer()
                            }
                            .padding(.vertical, 8)
                        }
                        .accessibilityLabel(option)
                        .accessibilityValue(viewModel.isOptionSelected(question: question, option: option) ? "已选择" : "未选择")
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppColors.secondaryBackground)
                .cornerRadius(8)
            }

            PrimaryButton("提交测验", isLoading: viewModel.isLoading) {
                Task { await viewModel.submitCurrentQuiz() }
            }
            .disabled(viewModel.isLoading)
            .accessibilityLabel("提交测验")
        }
    }

    // MARK: - Helpers

    private func formField(title: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(AppColors.textPrimary)
            TextField(placeholder, text: text)
                .font(AppFonts.body())
                .padding()
                .background(AppColors.secondaryBackground)
                .cornerRadius(8)
                .accessibilityLabel(title)
                .accessibilityHint(placeholder)
        }
    }
}

private struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

#if DEBUG
#Preview {
    NavigationStack {
        VolunteerRegistrationFlowView()
            .environmentObject(AppState())
            .environmentObject(SpeechService())
    }
}
#endif
