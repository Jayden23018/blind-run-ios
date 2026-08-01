import Combine
import SwiftUI

// MARK: - Blind Runner Profile ViewModel

@MainActor
final class BlindRunnerProfileViewModel: ObservableObject {
    @Published var name = ""
    @Published var defaultPace: PacePreference = .noPreference
    @Published var specialNeeds = ""
    @Published var isLoading = false
    @Published var errorMessage: String?

    private weak var appState: AppState?
    private var speechService: SpeechService?

    var isEditing: Bool {
        appState?.blindProfile != nil
    }

    var canSubmit: Bool {
        !name.trimmed.isEmpty && !isLoading
    }

    func configure(with appState: AppState, speechService: SpeechService) {
        self.appState = appState
        self.speechService = speechService

        if let profile = appState.blindProfile {
            name = profile.name ?? ""
            defaultPace = profile.defaultPace?.selectable ?? .noPreference
            specialNeeds = profile.specialNeeds ?? ""
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
    }
    #endif

    func submit() {
        guard canSubmit, let appState else {
            let message = "请填写必填信息"
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

                    emergencyContactSection

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
            speechService.speak("请填写个人资料。昵称为必填项。紧急联系人在下方单独管理，至少需要 1 位。")
        }
        .alert("确认退出", isPresented: $showLogoutConfirm) {
            Button("确认退出", role: .destructive) {
                Task { await appState.logout() }
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

                Text("昵称为必填项。紧急联系人在下方单独管理。")
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textSecondary)
                    .accessibilityLabel("昵称为必填项。紧急联系人在下方单独管理")
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
        }
    }

    /// 资料页只展示主联系人摘要 + 管理入口；增删改和主联系人切换都在 `EmergencyContactsView`。
    private var emergencyContactSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("紧急联系人")
                .font(.headline)
                .foregroundColor(AppColors.textPrimary)
                .accessibilityAddTraits(.isHeader)

            Text(emergencyContactSummary)
                .font(AppFonts.body())
                .foregroundColor(
                    appState.hasExactlyOnePrimaryEmergencyContact
                        ? AppColors.textSecondary
                        : AppColors.destructive
                )
                .accessibilityLabel(emergencyContactSummary)

            NavigationLink {
                EmergencyContactsView()
            } label: {
                Text("管理紧急联系人")
                    .font(AppFonts.primaryButton())
                    .foregroundColor(AppColors.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 64)
                    .background(AppColors.secondaryBackground)
                    .cornerRadius(12)
            }
            .accessibilityLabel("管理紧急联系人")
            .accessibilityHint("添加、编辑、删除紧急联系人，或切换主联系人")
        }
    }

    private var emergencyContactSummary: String {
        guard appState.emergencyContactCount > 0 else {
            return "还没有紧急联系人。下单前至少需要 1 位，最多 \(EmergencyContactRules.maxCount) 位。"
        }
        guard let primary = appState.primaryEmergencyContact else {
            return "共 \(appState.emergencyContactCount) 位紧急联系人，但还没有唯一的主联系人，请进入管理页设置。"
        }
        let relationshipText = primary.relationship?.nilIfBlank.map { "，关系\($0)" } ?? ""
        return "共 \(appState.emergencyContactCount) 位紧急联系人。主联系人：\(primary.name?.nilIfBlank ?? "未命名")，\(primary.maskedPhone ?? "未填写手机号")\(relationshipText)。"
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
    NavigationStack {
        BlindRunnerProfileView()
            .environmentObject(AppState())
            .environmentObject(SpeechService())
    }
}
#endif
