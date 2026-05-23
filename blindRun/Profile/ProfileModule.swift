import Combine
import SwiftUI

// MARK: - Running Experience

enum RunningExperience: String, CaseIterable, Identifiable, Sendable {
    case none
    case occasional
    case frequent

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none:
            return "无经验"
        case .occasional:
            return "偶尔跑"
        case .frequent:
            return "经常跑"
        }
    }
}

// MARK: - Blind Runner Profile ViewModel

@MainActor
final class BlindRunnerProfileViewModel: ObservableObject {
    @Published var nickname = ""
    @Published var emergencyContactName = ""
    @Published var emergencyContactPhone = ""
    @Published var runningExperience: RunningExperience = .none
    @Published var isLoading = false
    @Published var errorMessage: String?

    private weak var appState: AppState?
    private var speechService: SpeechService?

    var isEditing: Bool {
        appState?.blindRunnerProfile != nil
    }

    var isPhoneValid: Bool {
        AppState.isValidMainlandPhone(emergencyContactPhone)
    }

    var canSubmit: Bool {
        !nickname.trimmed.isEmpty &&
        !emergencyContactName.trimmed.isEmpty &&
        isPhoneValid &&
        !isLoading
    }

    func configure(with appState: AppState, speechService: SpeechService) {
        self.appState = appState
        self.speechService = speechService

        guard let profile = appState.blindRunnerProfile else { return }
        nickname = profile.nickname
        emergencyContactName = profile.emergencyContact?.name ?? ""
        emergencyContactPhone = profile.emergencyContact?.phoneNumber ?? ""
        if let rawValue = profile.runningExperience,
           let experience = RunningExperience(rawValue: rawValue) {
            runningExperience = experience
        }
    }

    func sanitizePhoneInput(_ value: String) {
        let digits = value.filter(\.isNumber)
        emergencyContactPhone = String(digits.prefix(11))
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

        let request = BlindRunnerProfileUpsertRequest(
            nickname: nickname.trimmed,
            runningExperience: runningExperience.rawValue,
            emergencyContact: EmergencyContactDto(
                name: emergencyContactName.trimmed,
                phoneNumber: emergencyContactPhone
            )
        )

        do {
            let profile: BlindRunnerProfileDto = try await appState.apiClient.put(
                "/api/profiles/blind-runner",
                body: request
            )
            appState.updateBlindRunnerProfile(profile)
            isLoading = false
        } catch let error as APIError {
            isLoading = false
            errorMessage = error.localizedMessage
            speechService?.speakError(error.localizedMessage)
        } catch {
            isLoading = false
            errorMessage = "保存失败，请重试"
            speechService?.speakError("保存失败，请重试")
        }
    }
}

// MARK: - Blind Runner Profile View

struct BlindRunnerProfileView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @StateObject private var viewModel = BlindRunnerProfileViewModel()

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
            speechService.speak("请填写个人资料。昵称、紧急联系人姓名、紧急联系人电话为必填项。")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HighContrastText(viewModel.isEditing ? "编辑资料" : "完善信息", style: .title)
                .accessibilityAddTraits(.isHeader)

            Text("昵称、紧急联系人姓名、紧急联系人电话为必填项。")
                .font(AppFonts.body())
                .foregroundColor(AppColors.textSecondary)
                .accessibilityLabel("昵称、紧急联系人姓名、紧急联系人电话为必填项")
        }
    }

    private var requiredSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            ProfileTextField(
                title: "昵称",
                placeholder: "请输入昵称",
                text: $viewModel.nickname,
                isRequired: true,
                errorMessage: viewModel.nickname.trimmed.isEmpty ? "请填写必填信息" : nil,
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
        VStack(alignment: .leading, spacing: 8) {
            Text("跑步经验")
                .font(.headline)
                .foregroundColor(AppColors.textPrimary)

            Picker("跑步经验", selection: $viewModel.runningExperience) {
                ForEach(RunningExperience.allCases) { experience in
                    Text(experience.displayName).tag(experience)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("跑步经验，选填")
            .accessibilityHint("点击选择跑步经验")
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
