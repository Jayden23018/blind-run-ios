import Combine
import SwiftUI

// MARK: - Volunteer Home ViewModel

@MainActor
final class VolunteerHomeViewModel: ObservableObject {
    @Published var isAvailable = false
    @Published var verificationStatus: VerificationStatus = .notSubmitted
    @Published var adminReviewStatus: AdminReviewStatus = .notSubmitted
    @Published var nickname = ""
    @Published var errorMessage: String?
    @Published var isLoading = false
    @Published var isUpdatingAvailability = false

    private weak var appState: AppState?
    private var speechService: SpeechService?

    var statusText: String {
        isAvailable ? "可接单" : "已关闭接单"
    }

    var statusColor: Color {
        isAvailable ? AppColors.success : AppColors.textSecondary
    }

    var acceptBlockMessage: String? {
        VolunteerOrderActionGuard.acceptBlockMessage(profile: appState?.volunteerProfile)
    }

    func configure(with appState: AppState, speechService: SpeechService) {
        self.appState = appState
        self.speechService = speechService
        apply(profile: appState.volunteerProfile)

        if appState.volunteerProfile == nil {
            Task {
                await loadCurrentUser(appState: appState)
            }
        }
    }

    func setAvailability(_ value: Bool) {
        guard !isUpdatingAvailability, let appState else { return }

        let previousValue = isAvailable
        isAvailable = value
        Task {
            await updateAvailability(value, previousValue: previousValue, appState: appState)
        }
    }

    func acceptOrder(orderId: String) async -> RunOrderDto? {
        if let message = VolunteerOrderActionGuard.acceptBlockMessage(profile: appState?.volunteerProfile) {
            errorMessage = message
            speechService?.speakError(message)
            return nil
        }

        guard let appState else { return nil }

        do {
            let order: RunOrderDto = try await appState.apiClient.post("/api/orders/\(orderId)/accept")
            return order
        } catch let error as APIError {
            errorMessage = error.localizedMessage
            speechService?.speakError(error.localizedMessage)
            return nil
        } catch {
            errorMessage = "接单失败，请重试"
            speechService?.speakError("接单失败，请重试")
            return nil
        }
    }

    private func loadCurrentUser(appState: AppState) async {
        isLoading = true
        errorMessage = nil

        do {
            let response: UserMeResponse = try await appState.apiClient.get("/api/users/me")
            appState.updateUserMe(response)
            apply(profile: response.volunteerProfile)
            isLoading = false
        } catch let error as APIError {
            isLoading = false
            errorMessage = error.localizedMessage
            speechService?.speakError(error.localizedMessage)
        } catch {
            isLoading = false
            errorMessage = "资料加载失败，请重试"
            speechService?.speakError("资料加载失败，请重试")
        }
    }

    private func updateAvailability(_ value: Bool, previousValue: Bool, appState: AppState) async {
        isUpdatingAvailability = true
        errorMessage = nil

        do {
            let profile: VolunteerProfileDto = try await appState.apiClient.patch(
                "/api/volunteer/availability",
                body: AvailabilityRequest(isAvailable: value)
            )
            appState.updateVolunteerProfile(profile)
            apply(profile: profile)
            isUpdatingAvailability = false
        } catch let error as APIError {
            isAvailable = previousValue
            isUpdatingAvailability = false
            errorMessage = error.localizedMessage
            speechService?.speakError(error.localizedMessage)
        } catch {
            isAvailable = previousValue
            isUpdatingAvailability = false
            errorMessage = "可服务状态更新失败，请重试"
            speechService?.speakError("可服务状态更新失败，请重试")
        }
    }

    private func apply(profile: VolunteerProfileDto?) {
        guard let profile else { return }
        nickname = profile.nickname
        verificationStatus = profile.verificationStatus
        adminReviewStatus = profile.adminReviewStatus
        isAvailable = profile.isAvailable
    }
}

// MARK: - Volunteer Home View

/// 志愿者首页：展示认证状态与可服务开关。
struct VolunteerHomeView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @StateObject private var viewModel = VolunteerHomeViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                availabilitySection
                readinessSection

                #if DEBUG
                DebugTestingPanel()
                    .environmentObject(appState)
                #endif

                if viewModel.isLoading {
                    ProgressView("正在加载志愿者资料...")
                        .accessibilityLabel("正在加载志愿者资料，请稍候")
                        .accessibilityHint("加载完成后会显示可服务开关")
                }

                if let errorMessage = viewModel.errorMessage {
                    Text(errorMessage)
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.destructive)
                        .accessibilityLabel(errorMessage)
                }

                Spacer(minLength: 32)
            }
            .padding(.horizontal, 24)
            .padding(.top, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(AppColors.background)
        .onAppear {
            viewModel.configure(with: appState, speechService: speechService)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HighContrastText("志愿者首页", style: .title)
                .accessibilityAddTraits(.isHeader)

            Text(viewModel.nickname.isEmpty ? "完成认证后可开启接单。" : "\(viewModel.nickname)，完成认证后可开启接单。")
                .font(AppFonts.body())
                .foregroundColor(AppColors.textSecondary)
                .accessibilityLabel(viewModel.nickname.isEmpty ? "完成认证后可开启接单" : "\(viewModel.nickname)，完成认证后可开启接单")
                .accessibilityHint("这里显示当前志愿者资料状态")
        }
    }

    private var availabilitySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle(
                isOn: Binding(
                    get: { viewModel.isAvailable },
                    set: { viewModel.setAvailability($0) }
                )
            ) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("可服务开关")
                        .font(.headline)
                        .foregroundColor(AppColors.textPrimary)
                    Text("开启后才可以接受新订单。")
                        .font(AppFonts.caption())
                        .foregroundColor(AppColors.textSecondary)
                }
            }
            .disabled(!appState.isVolunteerProfileApproved || viewModel.isUpdatingAvailability)
            .accessibilityLabel("可服务开关")
            .accessibilityHint("关闭后其他用户看不到你的接单状态")

            HStack(spacing: 8) {
                Circle()
                    .fill(viewModel.statusColor)
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)
                Text(viewModel.statusText)
                    .font(AppFonts.body().weight(.semibold))
                    .foregroundColor(viewModel.statusColor)
                    .accessibilityLabel(viewModel.statusText)
                    .accessibilityHint("当前可服务状态")

                if viewModel.isUpdatingAvailability {
                    ProgressView()
                        .accessibilityLabel("正在更新可服务状态")
                        .accessibilityHint("请稍候")
                }
            }
        }
        .padding()
        .background(AppColors.secondaryBackground)
        .cornerRadius(8)
    }

    private var readinessSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusRow(title: "verificationStatus", value: viewModel.verificationStatus.rawValue)
            statusRow(title: "adminReviewStatus", value: viewModel.adminReviewStatus.rawValue)

            if let blockMessage = viewModel.acceptBlockMessage {
                Text(blockMessage)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.warning)
                    .accessibilityLabel(blockMessage)
                    .accessibilityHint("不满足接单条件时显示")
            } else {
                Text("当前满足接单条件")
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.success)
                    .accessibilityLabel("当前满足接单条件")
                    .accessibilityHint("可以接受新订单")
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
            Text(value)
                .font(AppFonts.body().weight(.semibold))
                .foregroundColor(value == "approved" ? AppColors.success : AppColors.textPrimary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) 状态 \(value)")
        .accessibilityHint("志愿者认证状态")
    }
}

#if DEBUG
#Preview {
    VolunteerHomeView()
        .environmentObject(AppState())
        .environmentObject(SpeechService())
}
#endif
