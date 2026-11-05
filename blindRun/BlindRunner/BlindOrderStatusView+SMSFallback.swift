import SwiftUI

extension BlindOrderStatusView {
    // MARK: - SMS fallback

    /// 把行程要素交给系统短信，发给紧急联系人。**不发任何网络请求** ——
    /// 行程来自本页已持有的 `OrderDetailResponse`，收件人来自 `AppState.emergencyContacts`。
    ///
    /// 三道门，顺序不能换：**先问设备能不能发**，再问有没有收件人。
    /// 反过来的话，一台不能发短信的设备会先把用户支去添加紧急联系人，
    /// 加完回来发现还是发不出去 —— 那是一趟白跑的路，而这条路对盲人格外贵。
    func shareRunPlanBySMS(_ order: OrderDetailResponse) {
        guard MessageComposeSheet.canSendText else {
            shareViewModel.note(RunPlanShareCopy.unavailable, isProblem: true)
            return
        }
        guard appState.primaryEmergencyContact?.phone?.nilIfBlank != nil else {
            shareViewModel.note(RunPlanShareCopy.noContact, isProblem: true)
            return
        }
        // 第三道门与前两道一样要出声。`compose` 只在 `status.offersRunPlanShare == false` 时返回 nil，
        // 也就是 5 秒轮询把订单推到终态、而按钮还留在屏幕上的那一瞬 —— 静默 return 的表现是
        // 「点了没反应」，对盲人端就是事故（`AGENTS.md` §1 那条枚举红线的同类）。
        guard RunPlanShareMessage.compose(order: order) != nil else {
            shareViewModel.note(RunPlanShareCopy.notShareable, isProblem: true)
            return
        }
        shareViewModel.clearNotice()
        showRunPlanShare = true
    }
}
