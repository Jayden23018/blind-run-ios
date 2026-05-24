import Combine
import SwiftUI

// MARK: - Volunteer Action Guard

enum VolunteerOrderActionGuard {
    static func acceptBlockMessage(profile: VolunteerProfileDto?) -> String? {
        guard let profile,
              !profile.nickname.trimmed.isEmpty,
              AppState.isValidMainlandPhone(profile.phoneNumber) else {
            return "请先完善志愿者资料"
        }

        guard profile.verificationStatus == .approved,
              profile.adminReviewStatus == .approved else {
            return "请先完成志愿者认证"
        }

        guard profile.isAvailable else {
            return "请先开启可服务状态"
        }

        return nil
    }
}

// MARK: - Volunteer Profile ViewModel

@MainActor
final class VolunteerProfileViewModel: ObservableObject {
    @Published var nickname = ""
    @Published var phoneNumber = ""
    @Published var verificationStatus: VerificationStatus = .notSubmitted
    @Published var adminReviewStatus: AdminReviewStatus = .notSubmitted
    @Published var isLoading = false
    @Published var isCertificationRunning = false
    @Published var errorMessage: String?

    private weak var appState: AppState?
    private var speechService: SpeechService?

    var canSubmit: Bool {
        !nickname.trimmed.isEmpty &&
        !isLoading &&
        !isCertificationRunning
    }

    var certificationButtonTitle: String {
        if isCertificationRunning {
            return "认证中"
        }
        if verificationStatus == .approved && adminReviewStatus == .approved {
            return "模拟认证已完成"
        }
        return "开始模拟认证"
    }

    var certificationAccessibilityHint: String {
        if verificationStatus == .approved && adminReviewStatus == .approved {
            return "模拟认证已完成"
        }
        if appState?.isVolunteerProfileComplete != true {
            return "请先填写昵称并提交志愿者资料"
        }
        return "点击后开始 Demo 模拟认证"
    }

    func configure(with appState: AppState, speechService: SpeechService) {
        self.appState = appState
        self.speechService = speechService

        phoneNumber = appState.currentUser?.phoneNumber ?? appState.volunteerProfile?.phoneNumber ?? ""
        guard let profile = appState.volunteerProfile else { return }
        nickname = profile.nickname
        phoneNumber = profile.phoneNumber
        verificationStatus = profile.verificationStatus
        adminReviewStatus = profile.adminReviewStatus
    }

    func startMockCertification() {
        guard !isCertificationRunning, let appState else { return }
        guard appState.isVolunteerProfileComplete else {
            let message = "请先提交志愿者资料"
            errorMessage = message
            speechService?.speakError(message)
            return
        }

        Task {
            await runMockCertification(appState: appState)
        }
    }

    func submit() {
        guard canSubmit, let appState else {
            let message = nickname.trimmed.isEmpty ? "请填写昵称" : "请稍候"
            errorMessage = message
            speechService?.speakError(message)
            return
        }

        Task {
            await saveProfile(appState: appState)
        }
    }

    private func runMockCertification(appState: AppState) async {
        isCertificationRunning = true
        errorMessage = nil
        verificationStatus = .pending
        adminReviewStatus = .pending

        do {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            let profile: VolunteerProfileDto = try await appState.apiClient.post(
                "/api/volunteer/mock-verification/approve"
            )
            appState.updateVolunteerProfile(profile)
            phoneNumber = profile.phoneNumber
            verificationStatus = profile.verificationStatus
            adminReviewStatus = profile.adminReviewStatus
            isCertificationRunning = false
        } catch let error as APIError {
            isCertificationRunning = false
            verificationStatus = .notSubmitted
            adminReviewStatus = .notSubmitted
            errorMessage = error.localizedMessage
            speechService?.speakError(error.localizedMessage)
        } catch {
            isCertificationRunning = false
            verificationStatus = .notSubmitted
            adminReviewStatus = .notSubmitted
            errorMessage = "认证失败，请重试"
            speechService?.speakError("认证失败，请重试")
        }
    }

    private func saveProfile(appState: AppState) async {
        isLoading = true
        errorMessage = nil

        do {
            let profile: VolunteerProfileDto = try await appState.apiClient.put(
                "/api/profiles/volunteer",
                body: VolunteerProfileUpsertRequest(nickname: nickname.trimmed)
            )
            appState.updateVolunteerProfile(profile)
            apply(profile: profile)
            isLoading = false
        } catch let error as APIError {
            isLoading = false
            errorMessage = error.localizedMessage
            speechService?.speakError(error.localizedMessage)
        } catch {
            isLoading = false
            errorMessage = "提交失败，请重试"
            speechService?.speakError("提交失败，请重试")
        }
    }

    private func apply(profile: VolunteerProfileDto) {
        nickname = profile.nickname
        phoneNumber = profile.phoneNumber
        verificationStatus = profile.verificationStatus
        adminReviewStatus = profile.adminReviewStatus
    }
}

// MARK: - Volunteer Profile View

struct VolunteerProfileView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @StateObject private var viewModel = VolunteerProfileViewModel()

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    formSection
                    certificationSection

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
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HighContrastText("志愿者认证", style: .title)
                .accessibilityAddTraits(.isHeader)
            Text("填写昵称并完成 Demo 模拟认证。")
                .font(AppFonts.body())
                .foregroundColor(AppColors.textSecondary)
                .accessibilityLabel("填写昵称并完成 Demo 模拟认证")
                .accessibilityHint("认证为模拟流程，不会进行真实实名认证")
        }
    }

    private var formSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VolunteerTextField(
                title: "昵称",
                placeholder: "请输入昵称",
                text: $viewModel.nickname,
                errorMessage: viewModel.nickname.trimmed.isEmpty ? "请填写昵称" : nil,
                accessibilityLabel: "请输入昵称",
                accessibilityHint: "昵称为必填项"
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("手机号")
                    .font(.headline)
                    .foregroundColor(AppColors.textPrimary)
                    .accessibilityLabel("手机号")
                    .accessibilityHint("自动填充登录手机号，只读")

                Text(viewModel.phoneNumber.isEmpty ? "未获取手机号" : viewModel.phoneNumber)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(AppColors.secondaryBackground)
                    .cornerRadius(8)
                    .accessibilityLabel("手机号 \(viewModel.phoneNumber.isEmpty ? "未获取" : viewModel.phoneNumber)")
                    .accessibilityHint("只读字段，来自登录手机号")
            }
        }
    }

    private var certificationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("请完成以下认证步骤（Demo 版为模拟认证）")
                .font(AppFonts.body())
                .foregroundColor(AppColors.textPrimary)
                .accessibilityLabel("请完成以下认证步骤，Demo 版为模拟认证")
                .accessibilityHint("点击开始模拟认证后会自动通过")

            Button {
                viewModel.startMockCertification()
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isCertificationRunning {
                        ProgressView()
                    }
                    Text(viewModel.certificationButtonTitle)
                        .font(AppFonts.primaryButton())
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 64)
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isCertificationRunning || viewModel.verificationStatus == .approved)
            .accessibilityLabel("开始模拟认证")
            .accessibilityHint(viewModel.certificationAccessibilityHint)

            statusRow(title: "verificationStatus", value: viewModel.verificationStatus.rawValue)
            statusRow(title: "adminReviewStatus", value: viewModel.adminReviewStatus.rawValue)
        }
        .padding()
        .background(AppColors.secondaryBackground)
        .cornerRadius(8)
    }

    private func statusRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textSecondary)
            Spacer()
            Text(value)
                .font(AppFonts.body().weight(.semibold))
                .foregroundColor(value == "approved" ? AppColors.success : AppColors.textPrimary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) 状态 \(value)")
        .accessibilityHint("认证状态展示")
    }

    private var submitButton: some View {
        VStack(spacing: 8) {
            PrimaryButton("提交", isLoading: viewModel.isLoading) {
                viewModel.submit()
            }
            .disabled(!viewModel.canSubmit)
            .opacity(viewModel.canSubmit ? 1 : 0.45)
            .accessibilityLabel("提交")
            .accessibilityHint(viewModel.canSubmit ? "点击后提交志愿者资料" : "请先填写昵称")
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(.regularMaterial)
    }
}

// MARK: - Volunteer Text Field

private struct VolunteerTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let errorMessage: String?
    let accessibilityLabel: String
    let accessibilityHint: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(AppColors.textPrimary)

            TextField(placeholder, text: $text)
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

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#if DEBUG
#Preview {
    VolunteerProfileView()
        .environmentObject(AppState())
        .environmentObject(SpeechService())
}
#endif
