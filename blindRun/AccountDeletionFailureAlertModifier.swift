import SwiftUI

/// 删除账户失败弹窗。内容由 `SessionOperationState.accountDeletionFailureAlert` 决定：
/// 后端 409 拦下只给「知道了」，其余失败给「重试 / 取消」。
struct AccountDeletionFailureAlertModifier: ViewModifier {
    @EnvironmentObject private var appState: AppState

    private var failureAlert: AccountDeletionFailureAlert? {
        appState.accountDeletionState.accountDeletionFailureAlert
    }

    private var isPresented: Binding<Bool> {
        Binding(
            get: { failureAlert != nil },
            set: { if !$0 { appState.dismissAccountDeletionFailure() } }
        )
    }

    func body(content: Content) -> some View {
        content
            .alert(failureAlert?.title ?? AccountDeletionFailureAlert.failedTitle, isPresented: isPresented) {
                if failureAlert?.offersRetry == false {
                    Button("知道了", role: .cancel) { appState.dismissAccountDeletionFailure() }
                } else {
                    Button("重试") { Task { await appState.deleteCurrentAccount() } }
                    Button("取消", role: .cancel) { appState.dismissAccountDeletionFailure() }
                }
            } message: {
                if let message = failureAlert?.message {
                    Text(message)
                }
            }
    }
}
