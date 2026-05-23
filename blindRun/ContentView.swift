//
//  ContentView.swift
//  blindRun
//
//  Created by Jerry on 5/18/26.
//

import SwiftUI

/// 根路由视图，根据 AppState 的登录状态和活跃角色决定显示内容。
/// 路由由 @Published 属性驱动，登录或角色切换后自动更新。
struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @State private var restoreErrorMessage: String?
    @State private var showLogoutConfirmation = false

    var body: some View {
        Group {
            if !appState.isLoggedIn {
                LoginView()
                    .transition(.opacity)
            } else if appState.currentUser == nil && restoreErrorMessage == nil {
                restoreView
                    .transition(.opacity)
            } else if let restoreErrorMessage, appState.currentUser == nil {
                restoreErrorView(restoreErrorMessage)
                    .transition(.opacity)
            } else if appState.activeRole == nil {
                RoleSelectionView()
                    .transition(.opacity)
            } else if appState.activeRole == .blindRunner {
                if appState.isBlindRunnerProfileComplete {
                    BlindRunnerHomeView()
                        .transition(.opacity)
                } else {
                    BlindRunnerProfileView()
                        .transition(.opacity)
                }
            } else if appState.activeRole == .volunteer {
                if appState.isVolunteerProfileApproved {
                    VolunteerHomeView()
                        .transition(.opacity)
                } else {
                    VolunteerProfileView()
                        .transition(.opacity)
                }
            }
        }
        .task(id: appState.accessToken) {
            await refreshCurrentUserIfNeeded()
        }
        .animation(.easeInOut(duration: 0.3), value: appState.isLoggedIn)
        .animation(.easeInOut(duration: 0.3), value: appState.activeRole)
        .animation(.easeInOut(duration: 0.3), value: appState.isBlindRunnerProfileComplete)
        .animation(.easeInOut(duration: 0.3), value: appState.isVolunteerProfileApproved)
    }

    private var restoreView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("正在恢复登录状态...")
                .font(AppFonts.body())
                .foregroundColor(AppColors.textSecondary)
                .accessibilityLabel("正在恢复登录状态，请稍候")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
    }

    private func restoreErrorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Text(message)
                .font(AppFonts.body())
                .foregroundColor(AppColors.destructive)
                .multilineTextAlignment(.center)
                .accessibilityLabel(message)

            PrimaryButton("重新登录") {
                showLogoutConfirmation = true
            }
            .padding(.horizontal, 32)
            .accessibilityLabel("重新登录")
            .accessibilityHint("清除本地登录状态并返回登录页")
            .alert("确认退出", isPresented: $showLogoutConfirmation) {
                Button("确认退出", role: .destructive) {
                    appState.clearSession()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("确认后将清除当前登录状态，返回登录页。")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
    }

    private func refreshCurrentUserIfNeeded() async {
        guard appState.isLoggedIn, appState.currentUser == nil else { return }

        restoreErrorMessage = nil

        do {
            let response: UserMeResponse = try await appState.apiClient.get("/api/users/me")
            appState.updateUserMe(response)
        } catch let error as APIError {
            restoreErrorMessage = error.localizedMessage
            speechService.speakError(error.localizedMessage)
        } catch {
            restoreErrorMessage = "登录状态恢复失败，请重新登录。"
            speechService.speakError("登录状态恢复失败，请重新登录。")
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
        .environmentObject(SpeechService())
}
