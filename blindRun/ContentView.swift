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
    @EnvironmentObject private var speechService: SpeechService
    @State private var showLogoutConfirmation = false
    private let locationReportTimer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()
    private var profileRefreshKey: String {
        "\(appState.accessToken ?? "anonymous")-\(appState.activeRole?.rawValue ?? "no-role")-\(appState.userId ?? -1)"
    }

    var body: some View {
        Group {
            if !appState.isLoggedIn {
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

#Preview {
    ContentView()
        .environmentObject(AppState())
        .environmentObject(LocationService())
        .environmentObject(SpeechService())
}
