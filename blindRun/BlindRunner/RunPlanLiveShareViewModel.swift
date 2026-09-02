//
//  RunPlanLiveShareViewModel.swift
//  blindRun
//
//  「把这次行程告诉家人」这一块的状态与网络调用。
//

// `Combine` 只为 `ObservableObject` / `@Published` 引入 —— 这一层**不订阅任何 publisher**，
// 网络调用全走 async/await（AGENTS.md 的「并发模型只用一种」说的是数据流，不是 SwiftUI 的绑定机制）。
import Combine
import SwiftUI

/// 行程告知的结果提示。盲人靠 `speak` 听到，低视力用户靠这行字看到 ——
/// 两条通道都要有，`isProblem` 只决定颜色，不决定有没有。
struct RunPlanShareNotice: Equatable {
    let text: String
    let isProblem: Bool
}

/// 实时分享（起 / 停）与它的结果提示。
///
/// 从 `BlindOrderStatusView` 的 body 里提出来的：那两个网络调用原本住在 view 的
/// `@State` 之间，**失败分支因此没有任何测试面** —— 而这一块的失败分支恰恰是有内容的
/// （失败要露出短信降级入口、要出声、要留住「停止分享」按钮）。
///
/// 只用 async/await，不持有 `AnyCancellable`（AGENTS.md 硬约束）。
@MainActor
final class RunPlanLiveShareViewModel: ObservableObject {
    /// 当前是否在分享中。**来自本地记录而不是订单详情**：后端没有查询分享状态的端点，
    /// 理由与代价写在 `RunPlanLiveShareStore` 的注释里。
    @Published private(set) var isLiveSharing = false
    @Published private(set) var isWorking = false
    /// 短信入口是**降级路径**，不是常驻功能：实时分享失败时才露出来。
    /// 常驻会让读屏用户每次都多滑一个按钮，而它在实时分享可用时并不是用户想要的那条路。
    @Published private(set) var showSMSFallback = false
    @Published private(set) var notice: RunPlanShareNotice?
    @Published var payload: ShareLinkPayload?

    private weak var appState: AppState?
    private var speechService: SpeechService?
    private var orderId: Int64?

    /// ⚠️ `appState` 是 `weak`：传一个临时对象进来等于传 nil（见记忆
    /// `location-service-test-seam-and-weak-viewmodel-deps`）。用例要自己持有它。
    func configure(appState: AppState, speechService: SpeechService, orderId: Int64) {
        self.appState = appState
        self.speechService = speechService
        self.orderId = orderId
        isLiveSharing = RunPlanLiveShareStore(persistence: appState.persistence).isSharing(orderID: orderId)
    }

    /// 提示 + 播报一起给。**两条通道必须同时动** —— 只留一条就会让另一半用户什么都得不到。
    /// `spoken` 只在「屏幕上写的」与「念出来的」刻意不同时才传（起分享成功那一处）。
    func note(_ text: String, isProblem: Bool, spoken: String? = nil) {
        notice = RunPlanShareNotice(text: text, isProblem: isProblem)
        let announcement = spoken ?? text
        if isProblem {
            speechService?.speakError(announcement)
        } else {
            speechService?.speak(announcement)
        }
    }

    /// - Parameter hidingSMSFallback: 只在**重新发起实时分享**时传 true —— 那是一次全新的尝试，
    ///   上一次失败留下的降级入口该收走。打开短信面板时**不能**传 true：
    ///   面板还开着就把它背后的按钮撤掉，用户取消后就回不去了。
    func clearNotice(hidingSMSFallback: Bool = false) {
        notice = nil
        if hidingSMSFallback {
            showSMSFallback = false
        }
    }

    func startLiveShare() async {
        guard !isWorking, let appState, let orderId else { return }
        isWorking = true
        defer { isWorking = false }

        note(RunPlanLiveShareCopy.preparing, isProblem: false)
        do {
            let response = try await appState.orders.startLiveShare(orderId: orderId)
            RunPlanLiveShareStore(persistence: appState.persistence).markSharing(orderID: orderId)
            isLiveSharing = true
            note(RunPlanLiveShareCopy.sharing, isProblem: false, spoken: RunPlanLiveShareCopy.ready)
            payload = ShareLinkPayload(
                text: RunPlanLiveShareMessage.compose(shareUrl: response.shareUrl)
            )
        } catch {
            // 失败一律露出短信降级入口，包括 409（终态竞态）—— 那种情况下实时分享已经不可能，
            // 而「把这次行程告诉家人」这件事仍然做得到。
            let reason = (error as? APIError)?.localizedMessage ?? APIError.networkError(error).localizedMessage
            showSMSFallback = true
            note(
                RunPlanLiveShareCopy.failed(reason, offersSMSFallback: MessageComposeSheet.canSendText),
                isProblem: true
            )
        }
    }

    func stopLiveShare() async {
        guard !isWorking, let appState, let orderId else { return }
        isWorking = true
        defer { isWorking = false }

        note(RunPlanLiveShareCopy.stopping, isProblem: false)
        do {
            try await appState.orders.stopLiveShare(orderId: orderId)
            RunPlanLiveShareStore(persistence: appState.persistence).clear()
            isLiveSharing = false
            note(RunPlanLiveShareCopy.stopped, isProblem: false)
        } catch {
            // **失败时不清本地状态**：链接可能还有效，把「停止分享」入口一起收走，
            // 用户就再也停不掉了。宁可让他多按一次，也不要把入口弄丢。
            note(RunPlanLiveShareCopy.stopFailed, isProblem: true)
        }
    }
}
