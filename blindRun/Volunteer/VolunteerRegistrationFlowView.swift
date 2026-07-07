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
    @Published var phone = ""
    @Published var runningExperience = ""
    @Published var hasGuidedBefore = false
    @Published var emergencyExperience = ""

    // Step 2: ID Card
    @Published var idCardName = ""
    @Published var idCardNumber = ""
    @Published var frontImageData: Data?
    @Published var backImageData: Data?

    // Step 3: Face
    @Published var faceImageData: Data?
    @Published var faceIdentityReviewMessage: String?

    // Step 4: Training
    @Published var courses: [TrainingCourseResponse] = []
    @Published var currentCourseQuestions: [QuizQuestionResponse] = []
    @Published var trainingCompleted = false

    // Status
    @Published var registrationStatus: VolunteerRegistrationStatus?

    private weak var appState: AppState?
    private var speechService: SpeechService?
    private let apiClientOverride: (any APIClientProtocol)?

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

    var canSubmitIdCard: Bool {
        !idCardName.trimmed.isEmpty &&
        idCardNumber.count == 18 &&
        frontImageData != nil &&
        backImageData != nil
    }

    var canSubmitFace: Bool {
        faceImageData != nil && faceSubmitBlockingMessage == nil
    }

    var faceSubmitBlockingMessage: String? {
        if let faceIdentityReviewMessage {
            return faceIdentityReviewMessage
        }
        guard currentStep == .faceVerify,
              let status = registrationStatus?.idVerifyStatus?.uppercased(),
              status != "APPROVED" else {
            return nil
        }
        return identityReviewMessage(for: status)
    }

    func configure(appState: AppState, speechService: SpeechService) {
        self.appState = appState
        self.speechService = speechService
        phone = "" // user fills in
    }

    // MARK: - Load Registration Status

    func loadStatus() async {
        guard let appState else { return }
        isLoading = true
        do {
            let status: VolunteerRegistrationStatus = try await activeAPIClient(appState: appState).get("/api/volunteer/registration/status")
            applyRegistrationStatus(status)
            isLoading = false
        } catch let error as APIError {
            isLoading = false
            if appState.handleAuthenticatedAPIError(error) {
                return
            }
            // Default to step 1 if status fetch fails
            currentStep = .basicInfo
        } catch {
            isLoading = false
            // Default to step 1 if status fetch fails
            currentStep = .basicInfo
        }
    }

    // MARK: - Step 1: Submit Basic Info

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
            let _: EmptyResponse = try await appState.apiClient.post("/api/volunteer/registration/step1", body: request)
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

    func applyRegistrationStatus(_ status: VolunteerRegistrationStatus) {
        registrationStatus = status
        currentStep = resolvedRegistrationStep(from: status)
        trainingCompleted = status.trainingCompleted ?? trainingCompleted
        faceIdentityReviewMessage = resolvedFaceIdentityReviewMessage(from: status)
    }

    private func resolvedRegistrationStep(from status: VolunteerRegistrationStatus) -> RegistrationStep {
        if let stepCode = (status.registrationStep ?? status.currentStepCode)?.uppercased() {
            switch stepCode {
            case "STEP_1_BASIC_INFO":
                return .basicInfo
            case "STEP_2_ID_UPLOAD":
                return .idCard
            case "STEP_3_FACE_VERIFY":
                return .faceVerify
            case "STEP_4_TRAINING", "STEP_4_COMPLETED":
                return .training
            default:
                break
            }
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
        if status.step2Completed == true {
            return .faceVerify
        }
        if status.step1Completed == true {
            return .idCard
        }
        return .basicInfo
    }

    private func handleBasicInfoSubmissionError(_ error: APIError) async {
        let previousStep = currentStep
        let localizedMessage = error.localizedMessage
        if shouldRefreshRegistrationStatus(after: error), let appState {
            do {
                let status: VolunteerRegistrationStatus = try await appState.apiClient.get("/api/volunteer/registration/status")
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

    private func resolvedFaceIdentityReviewMessage(from status: VolunteerRegistrationStatus) -> String? {
        guard resolvedRegistrationStep(from: status) == .faceVerify,
              let idVerifyStatus = status.idVerifyStatus?.uppercased(),
              idVerifyStatus != "APPROVED" else {
            return nil
        }
        return identityReviewMessage(for: idVerifyStatus)
    }

    private func identityReviewMessage(for status: String) -> String {
        switch status {
        case "PENDING":
            return "请先完成身份审核，审核通过后再提交人脸核验"
        case "REJECTED":
            return "请先完成身份审核，当前身份证资料未通过，请重新提交"
        default:
            return "请先完成身份审核"
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

    private func activeAPIClient(appState: AppState) -> any APIClientProtocol {
        apiClientOverride ?? appState.apiClient
    }

    // MARK: - Step 2: Upload ID Card

    func submitIdCard() async {
        guard canSubmitIdCard, let appState else { return }

        isLoading = true
        errorMessage = nil

        guard let frontImageData, let backImageData else {
            isLoading = false
            errorMessage = "请上传身份证正反面照片"
            speechService?.speakError("请上传身份证正反面照片")
            return
        }

        do {
            let _: EmptyResponse = try await appState.apiClient.upload(
                "/api/volunteer/registration/step2/id-card",
                query: [
                    "idCardName": idCardName.trimmed,
                    "idCardNumber": idCardNumber.trimmed
                ],
                files: [
                    MultipartFile(fieldName: "frontFile", fileName: "id-card-front.jpg", mimeType: "image/jpeg", data: frontImageData),
                    MultipartFile(fieldName: "backFile", fileName: "id-card-back.jpg", mimeType: "image/jpeg", data: backImageData)
                ]
            )
            isLoading = false
            currentStep = .faceVerify
            faceIdentityReviewMessage = "请先完成身份审核"
            speechService?.speak("身份证资料提交成功，请等待身份审核通过")
        } catch let error as APIError {
            isLoading = false
            if appState.handleAuthenticatedAPIError(error) {
                return
            }
            errorMessage = error.localizedMessage
            speechService?.speakError(error.localizedMessage)
        } catch {
            isLoading = false
            errorMessage = "身份证资料提交失败，请重试"
            speechService?.speakError("身份证资料提交失败，请重试")
        }
    }

    // MARK: - Step 3: Face Verify

    func submitFaceVerify() async {
        if let message = faceSubmitBlockingMessage {
            errorMessage = message
            speechService?.speakError(message)
            return
        }
        guard canSubmitFace, let appState else { return }

        isLoading = true
        errorMessage = nil

        guard let faceImageData else {
            isLoading = false
            errorMessage = "请上传自拍照片"
            speechService?.speakError("请上传自拍照片")
            return
        }

        do {
            let _: EmptyResponse = try await appState.apiClient.upload(
                "/api/volunteer/registration/step3/face-verify",
                files: [
                    MultipartFile(fieldName: "facePhoto", fileName: "face-photo.jpg", mimeType: "image/jpeg", data: faceImageData)
                ]
            )
            isLoading = false
            currentStep = .training
            speechService?.speak("人脸核验资料提交成功，请完成培训课程")
        } catch let error as APIError {
            isLoading = false
            if appState.handleAuthenticatedAPIError(error) {
                return
            }
            if isIdentityReviewRequiredError(error) {
                let message = "请先完成身份审核"
                faceIdentityReviewMessage = message
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

    // MARK: - Step 4: Training

    func loadCourses() async {
        guard let appState else { return }
        do {
            let courseList: [TrainingCourseResponse] = try await appState.apiClient.get("/api/volunteer/registration/training/courses")
            courses = courseList
        } catch {
            courses = []
        }
    }

    func loadQuiz(courseId: Int64) async {
        guard let appState else { return }
        do {
            let questions: [QuizQuestionResponse] = try await appState.apiClient.get("/api/volunteer/registration/training/quiz/\(courseId)")
            currentCourseQuestions = questions
        } catch {
            currentCourseQuestions = []
        }
    }

    func submitTrainingProgress(courseId: Int64, progressPercent: Int, lastPositionSeconds: Int, timeSpentSeconds: Int) async {
        guard let appState else { return }
        let request = TrainingProgressRequest(
            courseId: courseId,
            progressPercent: progressPercent,
            lastPositionSeconds: lastPositionSeconds,
            timeSpentSeconds: timeSpentSeconds
        )
        do {
            let _: OrderResponse = try await appState.apiClient.post("/api/volunteer/registration/training/progress", body: request)
            if progressPercent >= 100 {
                speechService?.speak("课程学习完成")
            }
        } catch {
            // Silent failure for progress tracking
        }
    }

    func submitQuizAnswer(courseId: Int64, questionId: Int64, answers: [String], timeSpentSeconds: Int) async -> Bool {
        guard let appState else { return false }
        let request = QuizAnswerRequest(
            courseId: courseId,
            questionId: questionId,
            answers: answers,
            timeSpentSeconds: timeSpentSeconds
        )
        do {
            let result: QuizAnswerResponse = try await appState.apiClient.post("/api/volunteer/registration/training/quiz/answer", body: request)
            return result.correct ?? false
        } catch {
            return false
        }
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
    @State private var facePhotoItem: PhotosPickerItem?
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
                viewModel.faceImageData = image.normalizedJPEGData()
                speechService.speak("已拍摄自拍照片")
            }
            .ignoresSafeArea()
        }
        .task {
            viewModel.configure(appState: appState, speechService: speechService)
            await viewModel.loadStatus()
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

    // MARK: - Step 1: Basic Info

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

    // MARK: - Step 2: ID Card

    private var idCardStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("身份证上传")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)

            Text("请上传身份证正反面照片，系统将提交至后端进行身份核验。")
                .font(AppFonts.body())
                .foregroundColor(AppColors.textSecondary)

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

            PrimaryButton("提交身份核验", isLoading: viewModel.isLoading) {
                Task { await viewModel.submitIdCard() }
            }
            .disabled(!viewModel.canSubmitIdCard)
            .opacity(viewModel.canSubmitIdCard ? 1 : 0.45)
            .accessibilityLabel("提交身份核验")
        }
    }

    // MARK: - Step 3: Face Verify

    private var faceVerifyStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("人脸核验")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)

            Text("请上传清晰自拍照片，系统将提交至后端进行人脸核验。")
                .font(AppFonts.body())
                .foregroundColor(AppColors.textSecondary)

            if let blockingMessage = viewModel.faceSubmitBlockingMessage {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(AppColors.warning)
                            .accessibilityHidden(true)
                        Text(blockingMessage)
                            .font(AppFonts.body())
                            .foregroundColor(AppColors.destructive)
                    }

                    Button {
                        viewModel.currentStep = .idCard
                        viewModel.errorMessage = nil
                        speechService.speak("已返回身份核验，请重新提交真实身份证资料")
                    } label: {
                        Label("返回身份核验", systemImage: "person.text.rectangle")
                            .font(AppFonts.body().weight(.semibold))
                            .foregroundColor(AppColors.primary)
                    }
                    .accessibilityLabel("返回身份核验")
                    .accessibilityHint("返回上一步重新提交身份证姓名、号码和照片")
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(AppColors.secondaryBackground)
                .cornerRadius(12)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(blockingMessage)，可以返回身份核验重新提交资料")
            }

            Button {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    isShowingFaceCamera = true
                } else {
                    viewModel.errorMessage = "当前设备不可用相机，请从相册选择自拍照片"
                    speechService.speakError("当前设备不可用相机，请从相册选择自拍照片")
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

            photoPicker(
                title: "从相册选择自拍照片",
                selection: $facePhotoItem,
                hasData: viewModel.faceImageData != nil
            ) { data in
                viewModel.faceImageData = data
            }

            PrimaryButton("提交人脸核验", isLoading: viewModel.isLoading) {
                Task { await viewModel.submitFaceVerify() }
            }
            .disabled(!viewModel.canSubmitFace || viewModel.isLoading)
            .opacity(viewModel.canSubmitFace && !viewModel.isLoading ? 1 : 0.45)
            .accessibilityLabel("提交人脸核验")
            .accessibilityHint(viewModel.faceSubmitBlockingMessage ?? "提交自拍照片进行人脸核验")
        }
    }

    // MARK: - Step 4: Training

    private var trainingStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("培训学习")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)

            Text("请完成以下培训课程和测验")
                .font(AppFonts.body())
                .foregroundColor(AppColors.textSecondary)

            if viewModel.courses.isEmpty {
                ProgressView("加载课程中...")
                    .task { await viewModel.loadCourses() }
            } else {
                ForEach(viewModel.courses) { course in
                    trainingCourseCard(course)
                }
            }

            if viewModel.trainingCompleted {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(AppColors.success)
                    Text("注册完成！请等待审核")
                        .font(.title3.bold())
                        .foregroundColor(AppColors.textPrimary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .accessibilityLabel("注册完成，请等待审核")

                PrimaryButton("返回") {
                    dismiss()
                }
            }
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
            RoundedRectangle(cornerRadius: 12)
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
            let data = try await item.loadTransferable(type: Data.self)
            onDataLoaded(data)
        } catch {
            viewModel.errorMessage = "照片读取失败，请重新选择"
            speechService.speakError("照片读取失败，请重新选择")
        }
    }

    private func trainingCourseCard(_ course: TrainingCourseResponse) -> some View {
        VStack(alignment: .leading, spacing: 8) {
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
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.secondaryBackground)
        .cornerRadius(12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("课程：\(course.title ?? "未命名")")
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
