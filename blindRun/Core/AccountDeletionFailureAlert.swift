import Foundation

/// 删除账户失败弹窗（`ContentView` 的 `SessionLifecycleStatusModifier` 渲染）。
///
/// 两类失败给不同的出路：网络断开、5xx 这类给「重试」；后端 409 拦下的
/// （有进行中的订单 / 未结束的紧急求助）只给「知道了」—— 立刻重试只会再被拒一次。
struct AccountDeletionFailureAlert: Equatable {
    static let failedTitle = "删除账户失败"
    static let blockedTitle = "暂时不能删除账户"

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
        case .deletionBlocked(let message):
            return AccountDeletionFailureAlert(
                title: AccountDeletionFailureAlert.blockedTitle,
                message: message,
                offersRetry: false
            )
        case .idle, .inProgress:
            return nil
        }
    }
}
