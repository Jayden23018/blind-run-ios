import Combine
import SwiftUI

// MARK: - Volunteer Action Guard

enum VolunteerOrderActionGuard {
    static func acceptBlockMessage(profile: VolunteerProfileResponse?) -> String? {
        guard let profile, profile.isProfileCompleteForDispatch else {
            return "请先完善志愿者资料"
        }

        guard profile.isCertificationApproved else {
            return "请先完成志愿者认证"
        }

        guard profile.isAdminReviewApprovedWhenAvailable else {
            return "请等待管理员审核通过"
        }

        guard profile.hasManualDispatchOptIn else {
            return "请先开启可服务状态"
        }

        return nil
    }
}

// MARK: - Volunteer Profile ViewModel

@MainActor
final class VolunteerProfileViewModel: ObservableObject {
    @Published var name = ""
    @Published var verificationStatus = "not_submitted"
    @Published var adminReviewStatus: String?
    @Published var isLoading = false
    @Published var isCertificationRunning = false
    @Published var errorMessage: String?

    private weak var appState: AppState?
    private var speechService: SpeechService?

    var canSubmit: Bool {
        !name.trimmed.isEmpty &&
        !isLoading &&
        !isCertificationRunning
    }

    var isApproved: Bool {
        verificationStatus.lowercased() == "approved" &&
            ((adminReviewStatus?.lowercased() ?? "approved") == "approved")
    }

    var isPendingReview: Bool {
        verificationStatus.lowercased() == "pending"
    }

    var isRegistrationInProgress: Bool {
        verificationStatus.lowercased() == "in_progress"
    }

    var isRejected: Bool {
        verificationStatus.lowercased() == "rejected"
    }

    var certificationButtonTitle: String {
        if isCertificationRunning {
            return "认证中"
        }
        if isApproved {
            return "认证已完成"
        }
        if isPendingReview {
            return "审核中"
        }
        if isRegistrationInProgress {
            return "继续认证"
        }
        if isRejected {
            return "重新认证"
        }
        return "开始认证"
    }

    var certificationAccessibilityHint: String {
        if isApproved {
            return "认证已完成"
        }
        if isPendingReview {
            return "认证资料已提交，请等待审核"
        }
        if isRegistrationInProgress {
            return "点击后继续志愿者注册认证流程"
        }
        if appState?.isVolunteerProfileComplete != true {
            return "请先填写昵称并提交志愿者资料"
        }
        return "点击后进入志愿者注册认证流程"
    }

    /// 是否需要显示真实注册流程（非 mock 环境）
    var shouldShowRealRegistration: Bool {
        appState?.currentEnvironment != .mock
    }

    func configure(with appState: AppState, speechService: SpeechService) {
        self.appState = appState
        self.speechService = speechService

        guard let profile = appState.volunteerProfile else { return }
        name = profile.name ?? ""
        verificationStatus = profile.verificationStatus?.lowercased() ?? "not_submitted"
        adminReviewStatus = profile.adminReviewStatus?.lowercased()
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
            let message = name.trimmed.isEmpty ? "请填写昵称" : "请稍候"
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
        verificationStatus = "pending"

        do {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            let profile: VolunteerProfileResponse = try await appState.apiClient.post(
                "/api/volunteer/mock-verification/approve"
            )
            appState.updateVolunteerProfile(profile)
            verificationStatus = profile.verificationStatus?.lowercased() ?? "not_submitted"
            adminReviewStatus = profile.adminReviewStatus?.lowercased()
            isCertificationRunning = false
        } catch let error as APIError {
            isCertificationRunning = false
            verificationStatus = "not_submitted"
            errorMessage = error.localizedMessage
            speechService?.speakError(error.localizedMessage)
        } catch {
            isCertificationRunning = false
            verificationStatus = "not_submitted"
            errorMessage = "认证失败，请重试"
            speechService?.speakError("认证失败，请重试")
        }
    }

    private func saveProfile(appState: AppState) async {
        isLoading = true
        errorMessage = nil

        do {
            let request = VolunteerProfileUpdateRequest(name: name.trimmed)
            let profile: VolunteerProfileResponse = try await appState.apiClient.put(
                "/api/volunteer/profile",
                body: request
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

    private func apply(profile: VolunteerProfileResponse) {
        name = profile.name ?? ""
        verificationStatus = profile.verificationStatus?.lowercased() ?? "not_submitted"
        adminReviewStatus = profile.adminReviewStatus?.lowercased()
    }
}

// MARK: - Volunteer Profile View

struct VolunteerProfileView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @StateObject private var viewModel = VolunteerProfileViewModel()
    @State private var showLogoutConfirm = false

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
                HighContrastText("志愿者认证", style: .title)
                    .accessibilityAddTraits(.isHeader)
                Text(viewModel.shouldShowRealRegistration ? "填写昵称并完成志愿者认证。" : "填写昵称并完成 Demo 模拟认证。")
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textSecondary)
                    .accessibilityLabel(viewModel.shouldShowRealRegistration ? "填写昵称并完成志愿者认证" : "填写昵称并完成 Demo 模拟认证")
            }

            Spacer()

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

    private var formSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VolunteerTextField(
                title: "昵称",
                placeholder: "请输入昵称",
                text: $viewModel.name,
                errorMessage: viewModel.name.trimmed.isEmpty ? "请填写昵称" : nil,
                accessibilityLabel: "请输入昵称",
                accessibilityHint: "昵称为必填项"
            )
        }
    }

    private var certificationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if viewModel.shouldShowRealRegistration {
                Text("请完成以下认证步骤")
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textPrimary)
                    .accessibilityLabel("请完成以下认证步骤")

                NavigationLink {
                    VolunteerRegistrationFlowView()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "person.badge.shield.checkmark")
                        Text(viewModel.certificationButtonTitle)
                            .font(AppFonts.primaryButton())
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 64)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isApproved || viewModel.isPendingReview)
                .accessibilityLabel("开始认证")
                .accessibilityHint(viewModel.certificationAccessibilityHint)
            } else {
                Text("请完成以下认证步骤（Demo 版为模拟认证）")
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textPrimary)
                    .accessibilityLabel("请完成以下认证步骤，Demo 版为模拟认证")

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
                .disabled(viewModel.isCertificationRunning || viewModel.isApproved)
                .accessibilityLabel("开始模拟认证")
                .accessibilityHint(viewModel.certificationAccessibilityHint)
            }

            statusRow(title: "认证状态", value: viewModel.verificationStatus)
            if let adminReviewStatus = viewModel.adminReviewStatus {
                statusRow(title: "管理员审核", value: adminReviewStatus)
            }
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
            Text(statusDisplayName(value))
                .font(AppFonts.body().weight(.semibold))
                .foregroundColor(value.lowercased() == "approved" ? AppColors.success : AppColors.textPrimary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) 状态 \(statusDisplayName(value))")
        .accessibilityHint("认证状态展示")
    }

    private func statusDisplayName(_ value: String) -> String {
        switch value.lowercased() {
        case "approved": return "已通过"
        case "pending": return "审核中"
        case "in_progress": return "认证中"
        case "rejected": return "未通过"
        case "not_submitted", "none": return "未提交"
        default: return value
        }
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

#if DEBUG
#Preview {
    VolunteerProfileView()
        .environmentObject(AppState())
        .environmentObject(SpeechService())
}
#endif
