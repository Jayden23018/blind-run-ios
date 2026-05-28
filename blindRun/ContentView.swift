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
    @State private var showLogoutConfirmation = false

    var body: some View {
        Group {
            if !appState.isLoggedIn {
                LoginView()
                    .transition(.opacity)
            } else if appState.activeRole == nil {
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
                    VolunteerProfileView()
                        .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: appState.isLoggedIn)
        .animation(.easeInOut(duration: 0.3), value: appState.activeRole)
        .animation(.easeInOut(duration: 0.3), value: appState.isBlindProfileComplete)
        .animation(.easeInOut(duration: 0.3), value: appState.isVolunteerProfileApproved)
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
        .environmentObject(SpeechService())
}
