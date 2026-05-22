import Combine
import Foundation
import SwiftUI

// MARK: - Role Selection ViewModel

/// 角色选择页 ViewModel，管理角色切换 API 调用和活跃订单拦截处理。
/// 依赖 AppState 通过 ``configure(with:)`` 在 View.onAppear 中注入。
@MainActor
final class RoleSelectionViewModel: ObservableObject {

    // MARK: - Published State

    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var showBlockedAlert: Bool = false

    // MARK: - Dependencies

    private weak var appState: AppState?
    private var speechService: SpeechService?

    // MARK: - Init

    init() {}

    func configure(with appState: AppState, speechService: SpeechService) {
        self.appState = appState
        self.speechService = speechService
    }

    // MARK: - Actions

    /// 选择角色并调用后端 API 切换
    func selectRole(_ role: UserRole) {
        guard let appState = appState else {
            errorMessage = "应用未初始化，请重启"
            return
        }

        Task { await performRoleSwitch(role: role, appState: appState) }
    }

    // MARK: - Private

    private func performRoleSwitch(role: UserRole, appState: AppState) async {
        isLoading = true
        errorMessage = nil

        do {
            let switchRequest = SwitchRoleRequest(activeRole: role)
            let updatedUser: UserDto = try await appState.apiClient.request(
                method: .patch,
                path: "/api/users/me/active-role",
                query: nil,
                body: switchRequest,
                requiresAuth: true
            )
            appState.updateCurrentUser(updatedUser, fallbackActiveRole: role)
            isLoading = false
        } catch let error as APIError {
            isLoading = false
            handleSwitchError(error)
        } catch {
            isLoading = false
            errorMessage = "网络错误，请重试"
            speechService?.speakError("网络错误，请重试")
        }
    }

    private func handleSwitchError(_ error: APIError) {
        switch error {
        case .serverError(let response):
            if response.errorCode == .activeOrderRoleSwitchBlocked {
                errorMessage = response.message
                showBlockedAlert = true
            } else {
                errorMessage = response.message
            }
        case .networkError:
            errorMessage = "网络错误，请重试"
        case .unauthorized:
            errorMessage = "登录已过期，请重新登录。"
        case .decodingError, .invalidURL, .unknown:
            errorMessage = "角色设置失败，请重试。"
        }
        // TTS 播报错误信息，确保盲人用户能听到错误提示
        if let message = errorMessage {
            speechService?.speakError(message)
        }
    }
}
