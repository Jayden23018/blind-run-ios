//
//  ContentView.swift
//  blindRun
//
//  Created by Jerry on 5/18/26.
//

import Combine
import CoreLocation
import SwiftUI

/// 根路由视图，根据 AppState 的登录状态和活跃角色决定显示内容。
/// 路由由 @Published 属性驱动，登录或角色切换后自动更新。
struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var locationService: LocationService
    @State private var showRestorationLocalSignOutConfirmation = false
    @EnvironmentObject private var speechService: SpeechService
    @State private var showLogoutConfirmation = false
    private let locationReportTimer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()
    private var profileRefreshKey: String {
        "\(appState.accessToken ?? "anonymous")-\(appState.activeRole?.rawValue ?? "no-role")-\(appState.userId ?? -1)"
    }

    var body: some View {
        Group {
            if appState.sessionRestorationState == .restoring {
                VStack(spacing: 16) {
                    ProgressView()
                    Text("正在验证登录状态")
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("正在验证登录状态，请稍候")
            } else if case .validationFailed(let message) = appState.sessionRestorationState {
                VStack(spacing: 20) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 40))
                        .accessibilityHidden(true)
                    Text("暂时无法验证登录状态")
                        .font(.headline)
                    Text(message)
                        .multilineTextAlignment(.center)
                    Button("重试验证") {
                        Task { await appState.restoreSession() }
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityHint("重新连接服务端验证当前登录状态")
                    Button("仅退出本机", role: .destructive) {
                        showRestorationLocalSignOutConfirmation = true
                    }
                    .accessibilityHint("服务端令牌可能仍然有效，需要再次确认")
                }
                .padding(24)
                .accessibilityElement(children: .contain)
            } else if !appState.isLoggedIn {
                LoginView()
                    .transition(.opacity)
            } else if appState.activeRole == nil || appState.activeRole == .unset {
                RoleSelectionView()
                    .transition(.opacity)
            } else if appState.activeRole == .blind {
                if appState.isBlindProfileComplete {
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
                    NavigationStack {
                        VolunteerProfileView()
                    }
                    .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: appState.isLoggedIn)
        .animation(.easeInOut(duration: 0.3), value: appState.activeRole)
        .animation(.easeInOut(duration: 0.3), value: appState.isBlindProfileComplete)
        .animation(.easeInOut(duration: 0.3), value: appState.isVolunteerProfileApproved)
        .onReceive(locationService.$currentLocation) { _ in
            reportWebSocketLocationIfNeeded()
        }
        .onReceive(locationReportTimer) { _ in
            reportWebSocketLocationIfNeeded()
        }
        .onChange(of: appState.activeRole) { _ in
            if appState.isLoggedIn, appState.currentEnvironment != .mock {
                locationService.startUpdating()
            }
            reportWebSocketLocationIfNeeded()
        }
        .task(id: profileRefreshKey) {
            await refreshActiveProfileIfNeeded()
        }
        .modifier(SessionLifecycleStatusModifier())
        .overlay(alignment: .top) {
            if let notification = appState.realtimeCoordinator.currentNotification {
                RealtimeForegroundNotificationBanner(
                    notification: notification,
                    onDismiss: { appState.realtimeCoordinator.dismissCurrentNotification() }
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(100)
            }
        }
        .onReceive(appState.realtimeCoordinator.$currentNotification.compactMap { $0 }) { notification in
            speechService.speak(notification.speechText)
        }
        .alert("确认仅退出本机", isPresented: $showRestorationLocalSignOutConfirmation) {
            Button("仅退出本机", role: .destructive) { appState.clearSession() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("当前无法确认服务端 Token 已撤销。仅退出本机会清除本机登录信息，但远端 Token 可能继续有效。")
        }
    }

    private func reportWebSocketLocationIfNeeded() {
        guard appState.isLoggedIn,
              appState.activeRole != nil,
              appState.currentEnvironment != .mock,
              locationService.isAuthorized else {
            return
        }

        locationService.startUpdating()
        let coordinate = locationService.effectiveLocation
        appState.webSocketService?.sendLocationUpdate(
            lat: coordinate.latitude,
            lng: coordinate.longitude
        )
    }

    private func refreshActiveProfileIfNeeded() async {
        guard appState.isLoggedIn,
              appState.currentEnvironment != .mock,
              let role = appState.activeRole else {
            return
        }

        do {
            switch role {
            case .blind:
                let profile: BlindProfileResponse = try await appState.apiClient.get("/api/blind/profile")
                appState.updateBlindProfile(profile)
                if let userId = appState.userId {
                    let contacts: [EmergencyContactResponse] = try await appState.apiClient.get("/api/users/\(userId)/emergency-contacts")
                    appState.updateEmergencyContacts(contacts)
                }
            case .volunteer:
                let profile: VolunteerProfileResponse = try await appState.apiClient.get("/api/volunteer/profile")
                appState.updateVolunteerProfile(profile)
            case .unset:
                break
            }
        } catch let error as APIError {
            if appState.handleAuthenticatedAPIError(error) {
                return
            }
            // Keep the existing profile setup routes visible when the cloud has no profile yet.
        } catch {
            // Keep the existing profile setup routes visible when the cloud has no profile yet.
        }
    }
}

private struct SessionLifecycleStatusModifier: ViewModifier {
    @EnvironmentObject private var appState: AppState

    private var logoutFailure: Binding<Bool> {
        Binding(
            get: { if case .revocationFailed = appState.logoutState { return true }; return false },
            set: { if !$0 { appState.dismissLogoutFailure() } }
        )
    }

    private var deletionFailure: Binding<Bool> {
        Binding(
            get: { if case .revocationFailed = appState.accountDeletionState { return true }; return false },
            set: { if !$0 { appState.dismissAccountDeletionFailure() } }
        )
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                if appState.logoutState == .inProgress || appState.accountDeletionState == .inProgress {
                    ZStack {
                        Color.black.opacity(0.25).ignoresSafeArea()
                        ProgressView("正在处理，请稍候")
                            .padding(24)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                            .accessibilityLabel("请求正在处理中，请稍候")
                    }
                }
            }
            .alert("服务端退出失败", isPresented: logoutFailure) {
                Button("重试") { Task { await appState.logout() } }
                Button("仅退出本机", role: .destructive) { appState.confirmLocalOnlySignOut() }
                Button("取消", role: .cancel) { appState.dismissLogoutFailure() }
            } message: {
                let message: String = {
                    if case .revocationFailed(let value) = appState.logoutState { return value }
                    return "未能确认服务端 Token 已撤销。"
                }()
                Text("\(message) 仅退出本机可能使远端 Token 继续有效。")
            }
            .alert("删除账户失败", isPresented: deletionFailure) {
                Button("重试") { Task { await appState.deleteCurrentAccount() } }
                Button("取消", role: .cancel) { appState.dismissAccountDeletionFailure() }
            } message: {
                if case .revocationFailed(let message) = appState.accountDeletionState {
                    Text(message)
                }
            }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
        .environmentObject(LocationService())
        .environmentObject(SpeechService())
}
