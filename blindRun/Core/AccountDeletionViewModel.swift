import Combine
import Foundation
import SwiftUI

@MainActor
final class AccountDeletionViewModel: ObservableObject {
    @Published var showFinalConfirmation = false
    @Published var preflightMessage: String?

    /// 预检拦截的弹窗开关。
    ///
    /// 拦截**必须自己弹出来**。它此前唯一的展示面是设置页 `List` 末尾的一行文字，而 `089960e`（#76）
    /// 往两端设置页各加了三、四个入口之后，那一行落到了第二屏 —— SwiftUI 的 `List` 压根不渲染
    /// 屏幕外的行，于是用户点完「继续删除账户」屏幕上什么都不变，只有 `speakError` 那一声。
    /// 明眼志愿者与低视力用户拿不到任何反馈，看起来就是「点了没反应」。
    /// `testAuthLifecycleVolunteerDeletionRouteAndActiveOrderBlock` 从那天起一直红着，
    /// 红的正是这件事，只是被当成了用例陈旧。
    var isShowingPreflightBlock: Bool {
        get { preflightMessage != nil }
        set { if !newValue { preflightMessage = nil } }
    }

    /// 预检拦截的状态集。**口径是后端的「非终态」**（`OrderStatus.activeStatuses()`）——
    /// 这道预检不做自己的判断，它存在的唯一价值是**在服务端拒绝之前先出声告诉用户**。
    /// 漏一个状态的症状是：预检放行、不播任何提示，然后服务端按 `activeStatuses()` 拒 ⇒
    /// 那一声提前的反馈就没了，而它正是为盲人加的。
    ///
    /// `.scheduledConfirmed` 在列：后端 `occupiesVolunteer()` 上逐字写着「必须拦住他带着
    /// 这张单注销」，否则盲人的预约单会指向一个已注销的志愿者且不报任何错。
    /// `.pendingIntroCall` 一并补上（它从加进枚举那天起就漏在这里）。
    private static let blockingStatuses: Set<RunOrderStatus> = [
        .pendingMatch, .pendingIntroCall, .scheduledConfirmed, .pendingAccept,
        .driverEnRoute, .driverArrived, .inProgress, .rematching
    ]

    func preflight(appState: AppState, speechService: SpeechService) async {
        preflightMessage = nil
        do {
            let orders = try await appState.auth.accountDeletionOrderPreflight()
            if orders.content.contains(where: { Self.blockingStatuses.contains($0.status) }) {
                let message = "当前存在进行中的服务，请处理完成后再删除账户。"
                preflightMessage = message
                speechService.speakError(message)
                return
            }
        } catch APIError.unauthorized {
            // 会话已由 `apiClient` 外面那层统一处理（跑步中暂缓，否则登出，#872）。这里只停下：不弹删除确认。
            return
        } catch {
            // 预检只提供及时提示；最终权限与订单状态始终由删除接口裁决。
        }
        showFinalConfirmation = true
    }

    /// 最终确认弹窗正文。逐条对着后端 `UserService.deleteAccount` 的真实行为写：
    /// 用户行软删除 + 手机号改写释放，PII 级联硬删（盲人是实名资料 / 紧急联系人 / 常用地址，
    /// 志愿者是证件照 OSS / 资料 / 可服务时间，两端都删轨迹点 / 工单 / APNs token），
    /// 而**订单、评价、求助事件刻意保留** —— 后端注释写明它们不存姓名手机号，留作纠纷复核审计。
    ///
    /// 两端说各自删的那份：文案里出现用户根本没有的东西（对盲人说「证件照」）会让他怀疑自己填过什么。
    /// 保留项必须说 —— PIPL 第 47 条下用户对「删了什么、留了什么」有知情权，
    /// 而「此操作不可撤销」配上只字不提的保留项，很容易被理解成订单记录也一并没了。
    static func finalConfirmationMessage(for role: UserRole) -> String {
        let deleted: String
        switch role {
        case .blind:
            deleted = "你的实名信息、紧急联系人、常用地址和跑步轨迹"
        case .volunteer:
            deleted = "你的资质证件照、志愿者资料、可服务时间和服务轨迹"
        case .unset:
            // 角色还没定的账号只有登录信息，没有上面任何一份资料。
            deleted = "你的账户资料"
        }
        return """
        将删除\(deleted)。历史订单与评价会保留用于纠纷复核，其中不含你的姓名和手机号。\
        所有登录令牌立即失效，手机号可以重新注册。此操作不可撤销。
        """
    }
}
