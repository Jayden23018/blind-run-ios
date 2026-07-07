import Combine
import PhotosUI
import SwiftUI
import UIKit

// MARK: - Registration Step

enum RegistrationStep: Int, CaseIterable {
    case basicInfo = 1
    case idCard = 2
    case faceVerify = 3
    case training = 4

    var title: String {
        switch self {
        case .basicInfo: return "基本信息"
        case .idCard: return "身份核验"
        case .faceVerify: return "人脸核验"
        case .training: return "培训学习"
        }
    }
}

// MARK: - Registration ViewModel

@MainActor
final class VolunteerRegistrationViewModel: ObservableObject {
    @Published var currentStep: RegistrationStep = .basicInfo
    @Published var isLoading = false
    @Published var errorMessage: String?

    // Step 1: Basic Info
    @Published var name = ""
    @Published var phone = "" {
        didSet {
            let normalized = Self.normalizedPhoneNumber(phone)
            if normalized != phone {
                phone = normalized
            }
        }
    }
    @Published var runningExperience = ""
    @Published var hasGuidedBefore = false
    @Published var emergencyExperience = ""

    // Step 2: ID Card
    @Published var idCardName = ""
    @Published var idCardNumber = "" {
        didSet {
            let normalized = Self.normalizedIdCardNumber(idCardNumber)
            if normalized != idCardNumber {
                idCardNumber = normalized
            }
        }
    }
    @Published var frontImageData: Data?
    @Published var backImageData: Data?

    // Step 3: Face
    @Published var faceImageData: Data?

    // Step 4: Training
    @Published var courses: [TrainingCourseResponse] = []
    @Published var currentCourseQuestions: [QuizQuestionResponse] = []
    @Published var selectedCourseId: Int64?
    @Published var quizSelections: [Int64: Set<String>] = [:]
    @Published var quizResultMessage: String?
    @Published var trainingCompleted = false

    // Status
    @Published var registrationStatus: VolunteerRegistrationStatus?

    private weak var appState: AppState?
    private var speechService: SpeechService?
    private let apiClientOverride: (any APIClientProtocol)?
    private var courseProgressById: [Int64: Int] = [:]

    static let maxUploadImageBytes = 5 * 1024 * 1024
    static let idCardNumberRegex = #"^\d{17}[\dXx]$"#

    static func normalizedPhoneNumber(_ value: String) -> String {
        String(value.filter(\.isNumber).prefix(11))
    }

    static func normalizedIdCardNumber(_ value: String) -> String {
        String(value.filter { $0.isNumber || $0 == "X" || $0 == "x" }.prefix(18))
    }

    init(apiClient: (any APIClientProtocol)? = nil) {
        self.apiClientOverride = apiClient
    }

    var canSubmitBasicInfo: Bool {
        basicInfoValidationMessage == nil
    }

    var basicInfoValidationMessage: String? {
        if name.trimmed.isEmpty {
            return "请填写姓名"
        }
        if !AppState.isValidMainlandPhone(phone.trimmed) {
            return "请输入 11 位中国大陆手机号"
        }
        return nil
    }

    var idCardValidationMessage: String? {
        if idCardName.trimmed.isEmpty {
            return "请填写身份证姓名"
        }
        if idCardNumber.trimmed.range(of: Self.idCardNumberRegex, options: .regularExpression) == nil {
            return "请输入18位有效身份证号码"
        }
        if frontImageData == nil || backImageData == nil {
            return "请上传身份证正反面照片"
        }
        if let frontImageData, let message = imageValidationMessage(frontImageData) {
            return "身份证正面照片\(message)"
        }
        if let backImageData, let message = imageValidationMessage(backImageData) {
            return "身份证背面照片\(message)"
        }
        return nil
    }

    var canSubmitIdCard: Bool {
        !isIdReviewPending && idCardValidationMessage == nil && !isLoading
    }

    var idCardSubmitButtonTitle: String {
        if isIdReviewPending {
            return "身份审核中"
        }
        return isIdReviewRejected ? "重新提交身份核验" : "提交身份核验"
    }

    var canSubmitFace: Bool {
        currentStep == .faceVerify && faceImageData != nil && faceSubmitBlockingMessage == nil && !isLoading
    }

    var idVerifyStatusText: String {
        statusDisplayName(idVerifyStatus)
    }

    var faceVerifyStatusText: String {
        statusDisplayName(faceVerifyStatus)
    }

    var idVerifyRejectionReason: String? {
        registrationStatus?.stepDetails?.idVerifyRejectionReason
    }

    var faceVerifyRejectionReason: String? {
        registrationStatus?.stepDetails?.faceVerifyRejectionReason
    }

    var isIdReviewPending: Bool {
        idVerifyStatus == "PENDING"
    }

    var isIdReviewRejected: Bool {
        idVerifyStatus == "REJECTED"
    }

    var shouldPollRegistrationStatus: Bool {
        isIdReviewPending || (currentStep == .training && !trainingCompleted)
    }

    var faceSubmitBlockingMessage: String? {
        guard currentStep == .faceVerify, idVerifyStatus != "APPROVED" else {
            return nil
        }
        return identityReviewMessage(for: idVerifyStatus)
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
        trainingCompleted = status.isRegistrationComplete || (status.trainingCompleted ?? trainingCompleted)
        if trainingCompleted {
            quizResultMessage = "注册流程已完成，现在可以接单"
        }
    }

    private func resolvedRegistrationStep(from status: VolunteerRegistrationStatus) -> RegistrationStep {
        let stepCode = (status.registrationStep ?? status.currentStepCode)?.uppercased()
        if stepCode == "STEP_1_BASIC_INFO" {
            return .basicInfo
        }

        let idStatus = (status.idVerifyStatus ?? status.stepDetails?.idVerifyStatus ?? "").uppercased()
        if idStatus == "PENDING" || idStatus == "REJECTED" || stepCode == "STEP_2_ID_UPLOAD" {
            return .idCard
        }

        switch stepCode {
        case "STEP_3_FACE_VERIFY":
            return .faceVerify
        case "STEP_4_TRAINING", "STEP_4_COMPLETED":
            return .training
        default:
            break
        }

        if let currentStep = status.currentStep {
            switch currentStep {
            case 1:
                return .basicInfo
            case 2:
                return .idCard
            case 3:
                return .faceVerify
            case 4:
                return .training
            default:
                break
            }
        }

        if status.step3Completed == true {
            return .training
        }
        if status.step2Completed == true || idStatus == "APPROVED" {
            return .faceVerify
        }
        if status.step1Completed == true {
            return .idCard
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
            runningExperience: runningExperience.trimmed.isEmpty ? nil : runningExperience.trimmed,
            hasGuidedBefore: hasGuidedBefore,
            emergencyExperience: emergencyExperience.trimmed.isEmpty ? nil : emergencyExperience.trimmed
        )

        do {
            let _: EmptyResponse = try await activeAPIClient(appState: appState).post("/api/volunteer/registration/step1", body: request)
            isLoading = false
            currentStep = .idCard
            speechService?.speak("基本信息提交成功，请上传身份证")
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

    // MARK: - Step 2

    func submitIdCard() async {
        if isIdReviewPending {
            errorMessage = nil
            speechService?.speak("资料已提交，正在等待人工审核")
            return
        }
        if let message = idCardValidationMessage {
            errorMessage = message
            speechService?.speakError(message)
            return
        }
        guard let appState, let frontImageData, let backImageData else { return }

        isLoading = true
        errorMessage = nil

        do {
            let _: EmptyResponse = try await activeAPIClient(appState: appState).upload(
                "/api/volunteer/registration/step2/id-card",
                fields: [
                    "idCardName": idCardName.trimmed,
                    "idCardNumber": idCardNumber.trimmed
                ],
                files: [
                    MultipartFile(fieldName: "frontFile", fileName: "id-card-front.jpg", mimeType: "image/jpeg", data: frontImageData),
                    MultipartFile(fieldName: "backFile", fileName: "id-card-back.jpg", mimeType: "image/jpeg", data: backImageData)
                ]
            )
            isLoading = false
            currentStep = .idCard
            let pendingStatus = VolunteerRegistrationStatus(
                currentStepCode: "STEP_2_ID_UPLOAD",
                stepDetails: VolunteerRegistrationStepDetails(idVerifyStatus: "PENDING"),
                step1Completed: true,
                idVerifyStatus: "PENDING"
            )
            applyRegistrationStatus(pendingStatus)
            errorMessage = nil
            speechService?.speak("身份证资料提交成功，请等待身份审核通过")
        } catch let error as APIError {
            if appState.handleAuthenticatedAPIError(error) {
                isLoading = false
                return
            }
            if await reconcileStatusAfterIdCardSubmissionError(error) {
                return
            }
            isLoading = false
            errorMessage = error.localizedMessage
            speechService?.speakError(error.localizedMessage)
        } catch {
            isLoading = false
            errorMessage = "身份证资料提交失败，请重试"
            speechService?.speakError("身份证资料提交失败，请重试")
        }
    }

    private func reconcileStatusAfterIdCardSubmissionError(_ error: APIError) async -> Bool {
        guard shouldRefreshRegistrationStatus(afterIdCardError: error), let appState else {
            return false
        }
        do {
            let status: VolunteerRegistrationStatus = try await activeAPIClient(appState: appState).get("/api/volunteer/registration/status")
            applyRegistrationStatus(status)
            isLoading = false
            if isIdReviewPending {
                errorMessage = nil
                speechService?.speak("资料已提交，正在等待人工审核")
                return true
            }
            if currentStep == .basicInfo {
                let message = "请先完成基本信息填写"
                errorMessage = message
                speechService?.speakError(message)
                return true
            }
            return false
        } catch {
            return false
        }
    }

    private func shouldRefreshRegistrationStatus(afterIdCardError error: APIError) -> Bool {
        guard case .serverError(let response) = error else {
            return false
        }
        let normalized = "\(response.code) \(response.message)".uppercased()
        return normalized.contains("基本信息") ||
            normalized.contains("BASIC") ||
            normalized.contains("CURRENT STEP") ||
            normalized.contains("当前步骤") ||
            normalized.contains("STEP_")
    }

    func refreshStatus() {
        Task { await loadStatus(showLoading: false) }
    }

    // MARK: - Step 3

    func setFaceImageData(_ data: Data?) {
        guard let data else {
            faceImageData = nil
            return
        }
        if let message = imageValidationMessage(data) {
            faceImageData = nil
            errorMessage = "自拍照片\(message)"
            speechService?.speakError("自拍照片\(message)")
            return
        }
        faceImageData = data
        errorMessage = nil
    }

    func submitFaceVerify() async {
        if let message = faceSubmitBlockingMessage {
            errorMessage = message
            speechService?.speakError(message)
            return
        }
        guard canSubmitFace, let appState, let faceImageData else { return }

        if let message = imageValidationMessage(faceImageData) {
            errorMessage = "自拍照片\(message)"
            speechService?.speakError("自拍照片\(message)")
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let response: FaceVerifyResponse = try await activeAPIClient(appState: appState).upload(
                "/api/volunteer/registration/step3/face-verify",
                files: [
                    MultipartFile(fieldName: "facePhoto", fileName: "face-photo.jpg", mimeType: "image/jpeg", data: faceImageData)
                ]
            )
            isLoading = false
            if response.isPassed {
                currentStep = .training
                speechService?.speak(response.message ?? "人脸核验通过，请完成培训课程")
                await loadCourses()
                await loadStatus(showLoading: false)
            } else {
                let message = response.message ?? faceVerifyRejectionReason ?? "人脸核验未通过，请重新拍照"
                errorMessage = message
                speechService?.speakError(message)
            }
        } catch let error as APIError {
            isLoading = false
            if appState.handleAuthenticatedAPIError(error) {
                return
            }
            if isIdentityReviewRequiredError(error) {
                let message = "请先完成身份审核"
                errorMessage = message
                speechService?.speakError(message)
            } else {
                errorMessage = error.localizedMessage
                speechService?.speakError(error.localizedMessage)
            }
        } catch {
            isLoading = false
            errorMessage = "人脸核验提交失败，请重试"
            speechService?.speakError("人脸核验提交失败，请重试")
        }
    }

    private func isIdentityReviewRequiredError(_ error: APIError) -> Bool {
        guard case .serverError(let response) = error else {
            return false
        }
        return response.message.contains("身份") ||
            response.message.contains("身份证") ||
            response.message.uppercased().contains("ID")
    }

    private func identityReviewMessage(for status: String) -> String {
        switch status {
        case "PENDING":
            return "请等待身份审核通过后再提交人脸核验"
        case "REJECTED":
            return "身份证资料未通过，请重新提交"
        default:
            return "请先完成身份审核"
        }
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

    private var idVerifyStatus: String {
        (registrationStatus?.idVerifyStatus ?? registrationStatus?.stepDetails?.idVerifyStatus ?? "NONE").uppercased()
    }

    private var faceVerifyStatus: String {
        (registrationStatus?.faceVerifyStatus ?? registrationStatus?.stepDetails?.faceVerifyStatus ?? "NONE").uppercased()
    }

    private func statusDisplayName(_ value: String) -> String {
        switch value.uppercased() {
        case "NONE", "NOT_STARTED":
            return "未提交"
        case "PENDING":
            return "审核中"
        case "APPROVED", "PASSED":
            return "已通过"
        case "REJECTED":
            return "未通过"
        default:
            return value
        }
    }

    private func imageValidationMessage(_ data: Data) -> String? {
        if data.count > Self.maxUploadImageBytes {
            return "不能超过5MB"
        }
        guard Self.looksLikeImage(data) else {
            return "必须是图片文件"
        }
        return nil
    }

    private static func looksLikeImage(_ data: Data) -> Bool {
        guard data.count >= 4 else { return false }
        let bytes = [UInt8](data.prefix(12))
        if bytes.starts(with: [0xFF, 0xD8]) {
            return true
        }
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            return true
        }
        if bytes.starts(with: [0x47, 0x49, 0x46]) {
            return true
        }
        if bytes.count >= 12,
           bytes[4] == 0x66,
           bytes[5] == 0x74,
           bytes[6] == 0x79,
           bytes[7] == 0x70 {
            return true
        }
        return false
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
    @StateObject private var viewModel = VolunteerRegistrationViewModel()
    @State private var frontPhotoItem: PhotosPickerItem?
    @State private var backPhotoItem: PhotosPickerItem?
    @State private var isShowingFaceCamera = false

    var body: some View {
        VStack(spacing: 0) {
            stepIndicator

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    switch viewModel.currentStep {
                    case .basicInfo:
                        basicInfoStep
                    case .idCard:
                        idCardStep
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
        .fullScreenCover(isPresented: $isShowingFaceCamera) {
            CameraCaptureView { image in
                viewModel.setFaceImageData(image.normalizedJPEGData())
                speechService.speak("已拍摄自拍照片")
            }
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
    }

    // MARK: - Step Indicator

    private var stepIndicator: some View {
        HStack(spacing: 4) {
            ForEach(RegistrationStep.allCases, id: \.rawValue) { step in
                VStack(spacing: 4) {
                    Circle()
                        .fill(step.rawValue <= viewModel.currentStep.rawValue ? AppColors.primary : AppColors.textSecondary.opacity(0.3))
                        .frame(width: 28, height: 28)
                        .overlay {
                            Text("\(step.rawValue)")
                                .font(.caption.bold())
                                .foregroundColor(.white)
                        }
                    Text(step.title)
                        .font(.caption2)
                        .foregroundColor(step == viewModel.currentStep ? AppColors.primary : AppColors.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("步骤\(step.rawValue) \(step.title)")
                .accessibilityValue(step == viewModel.currentStep ? "当前步骤" : step.rawValue < viewModel.currentStep.rawValue ? "已完成" : "未完成")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppColors.secondaryBackground)
    }

    // MARK: - Step 1

    private var basicInfoStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("基本信息")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)

            formField(title: "姓名", placeholder: "请输入真实姓名", text: $viewModel.name)
            formField(title: "手机号", placeholder: "请输入手机号", text: $viewModel.phone)
                .keyboardType(.phonePad)
            formField(title: "跑步经验", placeholder: "描述您的跑步经验（选填）", text: $viewModel.runningExperience)

            Toggle("是否有陪跑经验", isOn: $viewModel.hasGuidedBefore)
                .font(AppFonts.body())
                .accessibilityLabel("是否有陪跑经验")

            formField(title: "急救经验", placeholder: "描述您的急救经验（选填）", text: $viewModel.emergencyExperience)

            if let validationMessage = viewModel.basicInfoValidationMessage {
                Text(validationMessage)
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.destructive)
                    .accessibilityLabel("无法提交基本信息：\(validationMessage)")
            }

            PrimaryButton("提交基本信息", isLoading: viewModel.isLoading) {
                Task { await viewModel.submitBasicInfo() }
            }
            .disabled(viewModel.isLoading || !viewModel.canSubmitBasicInfo)
            .opacity(viewModel.isLoading || !viewModel.canSubmitBasicInfo ? 0.45 : 1)
            .accessibilityLabel("提交基本信息")
            .accessibilityHint(viewModel.basicInfoValidationMessage ?? "点击提交")
        }
    }

    // MARK: - Step 2

    private var idCardStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("身份证上传")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)

            Text("请上传身份证正反面照片，系统将提交至后端进行身份核验。")
                .font(AppFonts.body())
                .foregroundColor(AppColors.textSecondary)

            identityReviewStatusPanel

            formField(title: "身份证姓名", placeholder: "请输入身份证上的姓名", text: $viewModel.idCardName)
            formField(title: "身份证号码", placeholder: "请输入18位身份证号码", text: $viewModel.idCardNumber)
                .keyboardType(.asciiCapable)

            photoPicker(
                title: "正面照片（人像面）",
                selection: $frontPhotoItem,
                hasData: viewModel.frontImageData != nil
            ) { data in
                viewModel.frontImageData = data
            }
            photoPicker(
                title: "背面照片（国徽面）",
                selection: $backPhotoItem,
                hasData: viewModel.backImageData != nil
            ) { data in
                viewModel.backImageData = data
            }

            if let validationMessage = viewModel.idCardValidationMessage {
                Text(validationMessage)
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.destructive)
                    .accessibilityLabel("无法提交身份核验：\(validationMessage)")
            }

            PrimaryButton(viewModel.idCardSubmitButtonTitle, isLoading: viewModel.isLoading) {
                Task { await viewModel.submitIdCard() }
            }
            .disabled(!viewModel.canSubmitIdCard)
            .opacity(viewModel.canSubmitIdCard ? 1 : 0.45)
            .accessibilityLabel(viewModel.idCardSubmitButtonTitle)
            .accessibilityHint(viewModel.isIdReviewPending ? "身份审核中，请等待或刷新状态" : viewModel.idCardValidationMessage ?? "提交身份证姓名、号码和正反面照片")
        }
    }

    private var identityReviewStatusPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: viewModel.isIdReviewRejected ? "xmark.circle.fill" : viewModel.isIdReviewPending ? "clock.fill" : "info.circle.fill")
                    .foregroundColor(viewModel.isIdReviewRejected ? AppColors.destructive : viewModel.isIdReviewPending ? AppColors.warning : AppColors.textSecondary)
                    .accessibilityHidden(true)
                Text("身份审核：\(viewModel.idVerifyStatusText)")
                    .font(AppFonts.body().weight(.semibold))
                    .foregroundColor(AppColors.textPrimary)
            }

            if viewModel.isIdReviewPending {
                Text("资料已提交，正在等待人工审核。测试时可由 CS admin 通过身份证审核。")
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.textSecondary)
                Button("刷新审核状态") {
                    viewModel.refreshStatus()
                }
                .font(AppFonts.body().weight(.semibold))
                .foregroundColor(AppColors.primary)
                .accessibilityLabel("刷新审核状态")
            } else if viewModel.isIdReviewRejected {
                Text(viewModel.idVerifyRejectionReason ?? "身份证资料未通过，请重新提交。")
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.destructive)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.secondaryBackground)
        .cornerRadius(8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("身份审核状态 \(viewModel.idVerifyStatusText)")
    }

    // MARK: - Step 3

    private var faceVerifyStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("人脸核验")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)

            Text("请使用本机前置相机拍摄清晰自拍照片，系统将实时提交人脸核验。")
                .font(AppFonts.body())
                .foregroundColor(AppColors.textSecondary)

            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundColor(AppColors.success)
                    .accessibilityHidden(true)
                Text("身份审核：\(viewModel.idVerifyStatusText)")
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textPrimary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("身份审核状态 \(viewModel.idVerifyStatusText)")

            if let blockingMessage = viewModel.faceSubmitBlockingMessage {
                Text(blockingMessage)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.destructive)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(AppColors.secondaryBackground)
                    .cornerRadius(8)
                    .accessibilityLabel(blockingMessage)
            }

            Button {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    isShowingFaceCamera = true
                } else {
                    let message = "需要使用真机相机完成自拍人脸核验"
                    viewModel.errorMessage = message
                    speechService.speakError(message)
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "camera.fill")
                        .accessibilityHidden(true)
                    Text(viewModel.faceImageData == nil ? "拍摄自拍照片" : "重新拍摄自拍照片")
                }
                .font(AppFonts.primaryButton())
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 64)
                .background(AppColors.primary)
                .cornerRadius(12)
            }
            .accessibilityLabel(viewModel.faceImageData == nil ? "拍摄自拍照片" : "重新拍摄自拍照片")
            .accessibilityHint("打开系统相机拍摄用于人脸核验的自拍照片")

            if viewModel.faceImageData != nil {
                Label("已拍摄自拍照片", systemImage: "checkmark.circle.fill")
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.success)
                    .accessibilityLabel("已拍摄自拍照片")
            }

            PrimaryButton("提交人脸核验", isLoading: viewModel.isLoading) {
                Task { await viewModel.submitFaceVerify() }
            }
            .disabled(!viewModel.canSubmitFace)
            .opacity(viewModel.canSubmitFace ? 1 : 0.45)
            .accessibilityLabel("提交人脸核验")
            .accessibilityHint(viewModel.faceSubmitBlockingMessage ?? "提交自拍照片进行人脸核验")
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

    private func photoPicker(
        title: String,
        selection: Binding<PhotosPickerItem?>,
        hasData: Bool,
        onDataLoaded: @escaping (Data?) -> Void
    ) -> some View {
        PhotosPicker(selection: selection, matching: .images) {
            photoPickerLabel(title: title, hasData: hasData)
        }
        .onChange(of: selection.wrappedValue) { newValue in
            Task { await loadPhotoData(from: newValue, onDataLoaded: onDataLoaded) }
        }
        .accessibilityLabel(title)
        .accessibilityValue(hasData ? "已选择照片" : "未选择照片")
        .accessibilityHint("点击选择照片")
    }

    private func photoPickerLabel(title: String, hasData: Bool) -> some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 8)
                .fill(AppColors.secondaryBackground)
                .frame(height: 120)
                .overlay {
                    VStack(spacing: 8) {
                        Image(systemName: hasData ? "checkmark.circle.fill" : "camera.fill")
                            .font(.title)
                            .foregroundColor(hasData ? AppColors.success : AppColors.textSecondary)
                        Text(hasData ? "已选择" : title)
                            .font(AppFonts.caption())
                            .foregroundColor(AppColors.textSecondary)
                    }
                }
        }
    }

    private func loadPhotoData(
        from item: PhotosPickerItem?,
        onDataLoaded: @escaping (Data?) -> Void
    ) async {
        guard let item else {
            onDataLoaded(nil)
            return
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data),
                  let normalized = image.normalizedJPEGData() else {
                viewModel.errorMessage = "照片读取失败，请重新选择图片"
                speechService.speakError("照片读取失败，请重新选择图片")
                onDataLoaded(nil)
                return
            }
            if normalized.count > VolunteerRegistrationViewModel.maxUploadImageBytes {
                viewModel.errorMessage = "照片不能超过5MB"
                speechService.speakError("照片不能超过5MB")
                onDataLoaded(nil)
                return
            }
            viewModel.errorMessage = nil
            onDataLoaded(normalized)
        } catch {
            viewModel.errorMessage = "照片读取失败，请重新选择"
            speechService.speakError("照片读取失败，请重新选择")
        }
    }
}

// MARK: - Camera Capture

private struct CameraCaptureView: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraDevice = .front
        picker.cameraCaptureMode = .photo
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, dismiss: dismiss)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let onCapture: (UIImage) -> Void
        private let dismiss: DismissAction

        init(onCapture: @escaping (UIImage) -> Void, dismiss: DismissAction) {
            self.onCapture = onCapture
            self.dismiss = dismiss
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onCapture(image)
            }
            dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }
    }
}

private extension UIImage {
    func normalizedJPEGData(maxDimension: CGFloat = 1600, compressionQuality: CGFloat = 0.82) -> Data? {
        let longestSide = max(size.width, size.height)
        let scale = longestSide > maxDimension ? maxDimension / longestSide : 1
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let normalizedImage = renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return normalizedImage.jpegData(compressionQuality: compressionQuality)
    }
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
