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

    var body: some View {
        Group {
            if !appState.isLoggedIn {
                LoginView()
                    .transition(.opacity)
            } else if appState.activeRole == nil {
                RoleSelectionView()
                    .transition(.opacity)
            } else if appState.activeRole == .blindRunner {
                BlindRunnerHomeView()
                    .transition(.opacity)
            } else if appState.activeRole == .volunteer {
                VolunteerHomeView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: appState.isLoggedIn)
        .animation(.easeInOut(duration: 0.3), value: appState.activeRole)
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
        .environmentObject(SpeechService())
}
