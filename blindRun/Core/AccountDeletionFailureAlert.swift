import Foundation

/// 删除账户失败弹窗（`ContentView` 的 `SessionLifecycleStatusModifier` 渲染）。
struct AccountDeletionFailureAlert: Equatable {
    static let failedTitle = "删除账户失败"

    let title: String
    let message: String
    let offersRetry: Bool
}

extension SessionOperationState {
    /// 删除账户失败弹窗的内容；不在失败态时为 nil。
    var accountDeletionFailureAlert: AccountDeletionFailureAlert? {
        switch self {
        case .revocationFailed(let message):
            return AccountDeletionFailureAlert(
                title: AccountDeletionFailureAlert.failedTitle,
                message: message,
                offersRetry: true
            )
        case .idle, .inProgress:
            return nil
        }
    }
}
