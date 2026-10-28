import Foundation

// 待回复邀请与服务端对账（后端 #366）。从 `AppState.swift` 挪出：那个文件与类体只许变短（SwiftLint 棘轮 #488）。
extension AppState {
    /// 待回复邀请与服务端对账（`GET /api/volunteer/pending-invites`，后端 #366）。只对陪跑员。
    ///
    /// 契约：「冷启动、从后台回前台、WS 重连成功后，各调一次」。撤回推送只走 WS、不能补读，
    /// 锁屏期间的新邀请也只有 APNs —— 不对账的话，离线期间被接走的卡会一直挂着，新来的卡永远看不到。
    ///
    /// 同一时刻只跑一次：回前台与首页加载常常同时触发，后到的一方等前一次的结果。
    ///
    /// 在跑的那一次如果是触发**之前**发出的（例如断线前发出、重连时还没回来），它的快照可能早于这次触发
    /// 想看到的变化 —— 所以并进来的调用会在它结束后**再补跑一次**，而不是直接拿它的结果。
    func restorePendingInvites() async {
        await pendingInvitesRestoreGate.run { [weak self] in
            await self?.performPendingInvitesRestore()
        }
    }

    private func performPendingInvitesRestore() async {
        guard isLoggedIn, activeRole == .volunteer else { return }
        let requestedAt = Date()
        let requestedFor = userId
        do {
            let response = try await orders.pendingInvites()
            // 请求在路上时可能登出、换了账号或换了角色：前一个会话的快照不许灌进这一个。
            guard isLoggedIn, activeRole == .volunteer, userId == requestedFor else { return }
            // 缺 `invites` 键 ≠「一张都没有」：照空列表对账会把手上所有邀请判成失效。
            guard let invites = response.invites else {
                ClientFlowDiagnostics.record(event: "failed", operation: "pending-invites-shape")
                return
            }
            realtimeCoordinator.reconcilePendingInvites(
                invites, requestedAt: requestedAt, consecutiveDeclineCount: response.consecutiveDeclineCount
            )
        } catch let error as APIError {
            if handleAuthenticatedAPIError(error) { return }
            // 失败静默：手上的卡照旧，下一次回前台 / 重连再对。对账失败不该打断陪跑员。
            ClientFlowDiagnostics.record(event: "failed", operation: "pending-invites")
        } catch {
            ClientFlowDiagnostics.record(event: "failed", operation: "pending-invites")
        }
    }
}

/// 同一时刻只跑一次；跑着的时候又被触发过，就在这一次结束后**再跑一次**，而不是让后到的调用直接拿这一次的结果。
///
/// 后到的调用等的是「它触发之后的那一次」跑完：在跑的那一次可能是触发之前发出的，结果早于它想看到的变化。
@MainActor
final class CoalescedRerun {
    private var inFlight: Task<Void, Never>?
    private var requestedAgain = false

    func run(_ work: @escaping @MainActor () async -> Void) async {
        if let inFlight {
            requestedAgain = true
            await inFlight.value
            return
        }
        let task = Task { @MainActor [weak self] in
            repeat {
                self?.requestedAgain = false
                await work()
            } while self?.requestedAgain == true
        }
        inFlight = task
        await task.value
        inFlight = nil
    }
}
