import Combine
import Foundation
import SwiftUI

extension AppState {
    // MARK: - 重连补读

    /// WS 重连后补读断线期间遗漏的通知（`GET /api/notifications/since`）。
    ///
    /// `after` 优先用本次会话实时见到的最新 timestamp，其次读持久化游标；
    /// 两者都是 ISO-8601（无时区），与后端 `notification_logs.sent_at` 同格式 ——
    /// 传 epoch 毫秒会被后端判 400 `INVALID_TIMESTAMP`。
    /// 首次安装且从未收到过通知时游标为空，此时不补读（后端窗口只有 24h/50 条，全量拉没有意义）。
    ///
    /// 一次补读可能跨多页：后端每页最多 50 条，`hasMore = true` 表示窗口里还有没返回完的，
    /// 要拿本页最后一条的 `sentAt` 当新的 `after` 再拉（契约 `api_spec.yaml:3329`）。
    /// 只拉第一页的后果是离线越久漏得越多，而那批恰恰是最该被听见的。
    ///
    /// ponytail: 上限 10 页 ≈ 500 条，远超后端 24h 窗口的现实量。后端要是坏成恒回
    /// `hasMore = true`，宁可少补几条也不能让盲人的手机在这里空转。
    static let catchUpPageLimit = 10

    func catchUpMissedNotifications() async {
        guard isLoggedIn else { return }
        // 断线期间可能整条求助都发生完了（志愿者代触发、家属短信回执、客服解除），而通知信封不带
        // eventId，补读文本无法还原事件状态。恢复只能问 `GET /api/emergency/active`，且必须先于补读，
        // 免得补读把已解除的旧文案念成当前状态。
        await recoverActiveEmergency()
        let after = realtimeCoordinator.lastObservedNotificationTimestamp
            ?? persistence.string(forKey: AppConstants.UserDefaultsKeys.lastSeenNotificationTimestamp)
        guard let after, !after.isEmpty else { return }
        var cursor = after
        do {
            for _ in 0..<Self.catchUpPageLimit {
                let page = try await auth.missedNotifications(after: cursor)
                realtimeCoordinator.ingestCatchUp(page.notifications)
                // 逐页落盘：中途失败时已经补到的那几页不必下次重拉。
                if let latest = realtimeCoordinator.lastObservedNotificationTimestamp {
                    persistence.set(latest, forKey: AppConstants.UserDefaultsKeys.lastSeenNotificationTimestamp)
                }
                // 取本页最大的 `sentAt`，不是 `lastObservedNotificationTimestamp` —— 后者会被
                // 循环期间到达的实时通知推到更靠后的时刻，拿它当 `after` 会跳过中间那一段。
                // 契约说的「最后一条」在正序下就是最大值，用 max 是为了后端乱序时游标也只前进：
                // 退回去会把同一页反复拉到上限为止。
                guard page.hasMore == true,
                      let next = page.notifications.compactMap(\.sentAt).max(),
                      next > cursor else { break }
                cursor = next
            }
        } catch {
            // 补读是 best-effort：失败不阻断实时链路，下次重连自然重试。
            ClientFlowDiagnostics.record(event: "failed", operation: "notification-catch-up")
        }
    }

    /// 向 `GET /api/emergency/active` 要回当前未结束的求助。两个角色都调，但问的不是一件事：
    /// 盲人拿自己的事件（屏 3b），志愿者拿他正在陪的那位盲人的事件（强提醒，后端 #387 ②，
    /// 2026-09-15 起对志愿者开放）。
    func recoverActiveEmergency() async {
        switch activeRole {
        case .blind:
            await emergencyCoordinator.refreshActiveEvent(userID: userId)
        case .volunteer:
            await emergencyCoordinator.refreshVolunteerAlert(safety: safety)
        case .unset, nil:
            return
        }
    }
}
