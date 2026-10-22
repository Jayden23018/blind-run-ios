import Foundation

/// 退出登录 / 删除账户请求的进行状态（`AppState.logoutState` / `accountDeletionState`）。
enum SessionOperationState: Equatable {
    case idle
    case inProgress
    case revocationFailed(message: String)
    /// 只用于删除账户：后端 409 拦下（`ErrorCode.blocksAccountDeletion`），弹窗不给「重试」。
    case deletionBlocked(message: String)

    /// 删除账户请求失败后该进哪个状态。
    static func accountDeletionFailure(for error: APIError) -> SessionOperationState {
        if error.errorCode?.blocksAccountDeletion == true {
            return .deletionBlocked(message: error.localizedMessage)
        }
        return .revocationFailed(message: error.localizedMessage)
    }

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

/// 删除账户失败弹窗（`AccountDeletionFailureAlertModifier` 渲染）。
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

/// 删除账户被后端 409 拦下时的本地文案（`ErrorCode.localizedMessage` 取用）。
enum AccountDeletionBlockCopy {
    static let activeOrder = "当前存在进行中的服务，请处理完成后再删除账户。"
    /// 后端 #844 的原话说「注销」，而两端设置页按钮叫「删除账户」，这里统一一个名字。
    /// 不写「倒计时内可以自己撤销」：陪跑员没有撤销权（AGENTS.md §6），两端共用这一句。
    static let activeEmergency = "当前有未结束的紧急求助，请等待客服处理完毕后再删除账户。"

    static func message(for code: ErrorCode) -> String {
        code == .activeEmergencyAccountDeletionBlocked ? activeEmergency : activeOrder
    }
}

extension ErrorCode {
    /// 删除账户被后端拦下（409），条件变了才能再删：立刻重试只会再被拒一次。
    var blocksAccountDeletion: Bool {
        self == .activeOrderAccountDeletionBlocked || self == .activeEmergencyAccountDeletionBlocked
    }
}
