import SwiftUI

/// 退出登录的二次确认，全 App 只有这一份（#561）。
///
/// 退出登录是危险操作（skill `aidrun-a11y-voice`「危险操作必须二次确认」）：读屏用户滑过按钮时
/// 双击一下就会被踢回登录页、要重新收验证码。此前四个页面各抄一份同样的弹窗，启动恢复失败页漏抄了，
/// 按下就退。守卫 `logout-without-confirmation` 拦在本文件以外直接调 `appState.logout()`。
struct LogoutConfirmation: ViewModifier {
    @EnvironmentObject private var appState: AppState
    @Binding var isPresented: Bool

    func body(content: Content) -> some View {
        content.alert("确认退出", isPresented: $isPresented) {
            Button("确认退出", role: .destructive) {
                Task { await appState.logout() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("确认后将清除当前登录状态，返回登录页。")
        }
    }
}

extension View {
    /// 按钮只负责把 `isPresented` 置真；真正退出在弹窗的「确认退出」里。
    func logoutConfirmation(isPresented: Binding<Bool>) -> some View {
        modifier(LogoutConfirmation(isPresented: isPresented))
    }
}
