import Combine
import SwiftUI

// MARK: - Blind Runner Profile ViewModel

@MainActor
final class BlindRunnerProfileViewModel: ObservableObject {
    @Published var name = ""
    @Published var emergencyContactName = ""
    @Published var emergencyContactPhone = "" {
        didSet {
            if emergencyContactPhone == originalEmergencyContactPhone,
               Self.isMaskedPhone(originalEmergencyContactPhone) {
                return
            }
            let normalized = Self.normalizedPhoneInput(emergencyContactPhone)
            if normalized != emergencyContactPhone {
                emergencyContactPhone = normalized
            }
        }
    }
    @Published var defaultPace: PacePreference = .noPreference
    @Published var specialNeeds = ""
    @Published var isLoading = false
    @Published var errorMessage: String?

    private weak var appState: AppState?
    private var speechService: SpeechService?
    private var originalEmergencyContactName = ""
    private var originalEmergencyContactPhone = ""

    var isEditing: Bool {
        appState?.blindProfile != nil
    }

    var isPhoneValid: Bool {
        isUsingUnchangedMaskedPhone || AppState.isValidMainlandPhone(emergencyContactPhone)
    }

    var emergencyContactPhoneForRequest: String? {
        isUsingUnchangedMaskedPhone ? nil : emergencyContactPhone
    }

    private var isUsingUnchangedMaskedPhone: Bool {
        emergencyContactPhone == originalEmergencyContactPhone &&
        Self.isMaskedPhone(originalEmergencyContactPhone)
    }

    var canSubmit: Bool {
        !name.trimmed.isEmpty &&
        !emergencyContactName.trimmed.isEmpty &&
        isPhoneValid &&
        !isLoading
    }

    func configure(with appState: AppState, speechService: SpeechService) {
        self.appState = appState
        self.speechService = speechService

        if let profile = appState.blindProfile {
            name = profile.name ?? ""
            defaultPace = profile.defaultPace ?? .noPreference
            specialNeeds = profile.specialNeeds ?? ""
        }

        if let contact = appState.emergencyContacts.first {
            originalEmergencyContactName = contact.name ?? ""
            originalEmergencyContactPhone = contact.phone ?? ""
            emergencyContactName = originalEmergencyContactName
            emergencyContactPhone = originalEmergencyContactPhone
        }
    }

    #if DEBUG
    func applyUITestProfilePrefillIfNeeded() {
        let environment = ProcessInfo.processInfo.environment
        guard environment["AIDRUN_UI_TEST_PREFILL_PROFILE_FORM"] == "1",
              appState?.blindProfile == nil else {
            return
        }

        name = environment["AIDRUN_UI_TEST_PROFILE_NICKNAME"] ?? "UITestBlind"
        emergencyContactName = environment["AIDRUN_UI_TEST_PROFILE_CONTACT_NAME"] ?? "UITestContact"
        emergencyContactPhone = environment["AIDRUN_UI_TEST_PROFILE_CONTACT_PHONE"] ?? "13800001111"
    }
    #endif

    func sanitizePhoneInput(_ value: String) {
        if value == originalEmergencyContactPhone, Self.isMaskedPhone(value) {
            emergencyContactPhone = value
            return
        }
        emergencyContactPhone = Self.normalizedPhoneInput(value)
    }

    nonisolated static func isMaskedPhone(_ value: String) -> Bool {
        value.range(of: #"^\d{3}\*{4}\d{4}$"#, options: .regularExpression) != nil
    }

    nonisolated static func normalizedPhoneInput(_ value: String) -> String {
        String(value.filter(\.isNumber).prefix(11))
    }

    func submit() {
        guard canSubmit, let appState else {
            let message = emergencyContactPhone.isEmpty || isPhoneValid ? "请填写必填信息" : "请输入正确的手机号"
            errorMessage = message
            speechService?.speakError(message)
            return
        }

        Task {
            await saveProfile(appState: appState)
        }
    }

    private func saveProfile(appState: AppState) async {
        isLoading = true
        errorMessage = nil

        let profileRequest = BlindProfileUpdateRequest(
            name: name.trimmed,
            runningPace: nil,
            specialNeeds: specialNeeds.nilIfBlank,
            visionLevel: nil,
            hasGuideDog: nil,
            tetherPreference: nil,
            chatPreference: nil,
            defaultPace: defaultPace == .noPreference ? nil : defaultPace
        )

        do {
            let profile: BlindProfileResponse = try await appState.apiClient.put(
                "/api/blind/profile",
                body: profileRequest
            )
            appState.updateBlindProfile(profile)

            // Save emergency contact
            let contactRequest = EmergencyContactRequest(
                name: emergencyContactName.trimmed,
                phone: emergencyContactPhoneForRequest,
                relationship: nil,
                isPrimary: true
            )
            guard let userId = appState.userId else {
                throw APIError.serverError(ErrorResponse(code: "VALIDATION_FAILED", message: "用户未登录"))
            }
            let contact = try await saveEmergencyContact(
                request: contactRequest,
                userId: userId,
                appState: appState
            )
            appState.updateEmergencyContacts([contact])

            isLoading = false
        } catch let error as APIError {
            isLoading = false
            if appState.handleAuthenticatedAPIError(error) {
                return
            }
            errorMessage = error.localizedMessage
            speechService?.speakError(error.localizedMessage)
        } catch {
            isLoading = false
            errorMessage = "保存失败，请重试"
            speechService?.speakError("保存失败，请重试")
        }
    }

    private func saveEmergencyContact(
        request: EmergencyContactRequest,
        userId: Int64,
        appState: AppState
    ) async throws -> EmergencyContactResponse {
        let existingContacts: [EmergencyContactResponse] = (try? await appState.apiClient.get(
            "/api/users/\(userId)/emergency-contacts"
        )) ?? []

        if let existingContact = existingContacts.first {
            if request.phone == nil,
               emergencyContactName.trimmed == originalEmergencyContactName.trimmed {
                return existingContact
            }
            return try await appState.apiClient.put(
                "/api/users/\(userId)/emergency-contacts/\(existingContact.id)",
                body: request
            )
        }

        do {
            return try await appState.apiClient.post(
                "/api/users/\(userId)/emergency-contacts",
                body: request
            )
        } catch {
            let fallbackContacts: [EmergencyContactResponse] = (try? await appState.apiClient.get(
                "/api/users/\(userId)/emergency-contacts"
            )) ?? []
            if let fallbackContact = fallbackContacts.first {
                return fallbackContact
            }
            throw error
        }
    }
}

// MARK: - Blind Runner Profile View

struct BlindRunnerProfileView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @StateObject private var viewModel = BlindRunnerProfileViewModel()
    @State private var showLogoutConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header

                    requiredSection

                    optionalSection

                    if let errorMessage = viewModel.errorMessage {
                        Text(errorMessage)
                            .font(AppFonts.body())
                            .foregroundColor(AppColors.destructive)
                            .accessibilityLabel(errorMessage)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 32)
                .padding(.bottom, 120)
            }
        }
        .background(AppColors.background)
        .safeAreaInset(edge: .bottom) {
            submitButton
        }
        .onAppear {
            viewModel.configure(with: appState, speechService: speechService)
            #if DEBUG
            viewModel.applyUITestProfilePrefillIfNeeded()
            #endif
            speechService.speak("请填写个人资料。昵称、紧急联系人姓名、紧急联系人电话为必填项。")
        }
        .alert("确认退出", isPresented: $showLogoutConfirm) {
            Button("确认退出", role: .destructive) {
                appState.clearSession()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("确认后将清除当前登录状态，返回登录页。")
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                HighContrastText(viewModel.isEditing ? "编辑资料" : "完善信息", style: .title)
                    .accessibilityAddTraits(.isHeader)

                Text("昵称、紧急联系人姓名、紧急联系人电话为必填项。")
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textSecondary)
                    .accessibilityLabel("昵称、紧急联系人姓名、紧急联系人电话为必填项")
            }

            Spacer()

            if !viewModel.isEditing {
                Button {
                    showLogoutConfirm = true
                } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 18))
                        .foregroundColor(AppColors.destructive)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("退出登录")
                .accessibilityHint("退出后需要重新登录，需要二次确认")
            }
        }
    }

    private var requiredSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            ProfileTextField(
                title: "昵称",
                placeholder: "请输入昵称",
                text: $viewModel.name,
                isRequired: true,
                errorMessage: viewModel.name.trimmed.isEmpty ? "请填写必填信息" : nil,
                accessibilityLabel: "昵称，必填",
                accessibilityHint: "请输入您的昵称"
            )

            ProfileTextField(
                title: "紧急联系人姓名",
                placeholder: "请输入紧急联系人姓名",
                text: $viewModel.emergencyContactName,
                isRequired: true,
                errorMessage: viewModel.emergencyContactName.trimmed.isEmpty ? "请填写必填信息" : nil,
                accessibilityLabel: "紧急联系人姓名，必填",
                accessibilityHint: "请输入紧急联系人姓名"
            )

            ProfileTextField(
                title: "紧急联系人电话",
                placeholder: "请输入11位手机号",
                text: $viewModel.emergencyContactPhone,
                isRequired: true,
                keyboardType: .numberPad,
                errorMessage: phoneErrorMessage,
                accessibilityLabel: "紧急联系人电话，必填，11位手机号",
                accessibilityHint: "请输入紧急联系人手机号，只能输入数字"
            )
            .onChange(of: viewModel.emergencyContactPhone) { newValue in
                viewModel.sanitizePhoneInput(newValue)
            }
        }
    }

    private var optionalSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("默认配速偏好")
                    .font(.headline)
                    .foregroundColor(AppColors.textPrimary)

                Picker("默认配速偏好", selection: $viewModel.defaultPace) {
                    ForEach(PacePreference.allCases, id: \.self) { pace in
                        Text(pace.displayName).tag(pace)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("默认配速偏好，选填")
                .accessibilityHint("选择跑步配速偏好")
            }

            ProfileTextField(
                title: "特殊需求",
                placeholder: "例如：需要语言引导",
                text: $viewModel.specialNeeds,
                isRequired: false,
                errorMessage: nil,
                accessibilityLabel: "特殊需求，选填",
                accessibilityHint: "如有特殊需求请填写"
            )
        }
    }

    private var submitButton: some View {
        VStack(spacing: 8) {
            PrimaryButton(
                viewModel.isEditing ? "保存" : "完成",
                isLoading: viewModel.isLoading
            ) {
                viewModel.submit()
            }
            .disabled(!viewModel.canSubmit)
            .opacity(viewModel.canSubmit ? 1 : 0.45)
            .accessibilityLabel(viewModel.isEditing ? "保存，保存资料" : "完成，保存资料")
            .accessibilityHint(viewModel.canSubmit ? "点击后保存资料" : "请先填写必填资料")
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(.regularMaterial)
    }

    private var phoneErrorMessage: String? {
        if viewModel.emergencyContactPhone.isEmpty {
            return "请填写必填信息"
        }
        if !viewModel.isPhoneValid {
            return "请输入正确的手机号"
        }
        return nil
    }
}

// MARK: - Profile Text Field

private struct ProfileTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let isRequired: Bool
    var keyboardType: UIKeyboardType = .default
    let errorMessage: String?
    let accessibilityLabel: String
    let accessibilityHint: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(AppColors.textPrimary)
                if isRequired {
                    Text("*")
                        .font(.headline)
                        .foregroundColor(AppColors.destructive)
                        .accessibilityHidden(true)
                }
            }

            TextField(placeholder, text: $text)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(AppFonts.body())
                .padding()
                .background(AppColors.secondaryBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(errorMessage == nil ? Color.clear : AppColors.destructive, lineWidth: 1)
                )
                .cornerRadius(8)
                .accessibilityLabel(accessibilityLabel)
                .accessibilityHint(accessibilityHint)

            if let errorMessage {
                Text(errorMessage)
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.destructive)
                    .accessibilityLabel(errorMessage)
            }
        }
    }
}

#if DEBUG
#Preview {
    BlindRunnerProfileView()
        .environmentObject(AppState())
        .environmentObject(SpeechService())
}
#endif
