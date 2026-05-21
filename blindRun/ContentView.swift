//
//  ContentView.swift
//  blindRun
//
//  Created by Jerry on 5/18/26.
//

import SwiftUI

/// 根路由视图，根据登录状态和角色决定显示内容。
/// 后续 PR 将替换为完整的导航路由。
struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // App 标题
                HighContrastText("助盲跑", style: .title)

                // 环境状态信息
                VStack(spacing: 8) {
                    HighContrastText("当前环境: \(appState.currentEnvironment.displayName)", style: .body)
                    HighContrastText("登录状态: \(appState.isLoggedIn ? "已登录" : "未登录")", style: .body)
                    if let role = appState.activeRole {
                        HighContrastText("当前角色: \(role.displayName)", style: .status)
                    }
                }

                Spacer()

                // 环境切换（仅 Debug 用）
                #if DEBUG
                VStack(spacing: 12) {
                    HighContrastText("环境切换", style: .caption)
                    ForEach(APIEnvironment.allCases, id: \.self) { env in
                        Button {
                            appState.currentEnvironment = env
                        } label: {
                            Text(env.displayName)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(appState.currentEnvironment == env ? AppColors.primary.opacity(0.2) : Color.clear)
                                .cornerRadius(8)
                        }
                        .accessibilityLabel("切换到\(env.displayName)")
                        .accessibilityHint("当前\(appState.currentEnvironment == env ? "已选中" : "未选中")")
                    }
                }
                #endif

                // 占位：后续替换为登录/角色选择/主页路由
                PrimaryButton("开始使用（待实现）") {
                    // 后续 PR 实现登录流程
                }
            }
            .padding()
            .navigationTitle("助盲跑")
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
        .environmentObject(SpeechService())
}
