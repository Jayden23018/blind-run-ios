import Foundation
import UserNotifications

// MARK: - 约好后的本机开跑提醒（#660 B-18）
//
// 跑者的行前提醒此前只靠后端推送：通知被关、推送没到、三天前约好当天没开 App，都会忘了这一单，
// 陪跑员白跑一趟。这里在约成（有人接下了）时排一条本机通知，与推送互为兜底。
//
// 🔴 不为这件事弹通知权限：权限只在第一次下单时问（`asksBlindForPushPermissionOnFirstOrder`）。
// 用户拒绝过就排不进去，`UNUserNotificationCenter.add` 会报错，这里吞掉 —— 那时「加入日历」是另一条路。

extension RunOrderStatus {
    /// 这一态值不值得排开跑提醒：人已经定下来、还没出发。
    ///
    /// 穷举 switch：后端加状态时编译器逼一次决策（同 `isActiveForBlindRunner` 一族的写法）。
    var remindsBlindRunnerBeforeStart: Bool {
        switch self {
        case .scheduledConfirmed, .pendingAccept:
            return true
        // 还在找人：可能落到「暂无陪跑员」，提前提醒「有一次陪跑」是一句可能落空的话。
        case .pendingMatch, .pendingIntroCall, .rematching:
            return false
        // 已经动身或在跑：提醒的时刻已经过了，或者人就在现场。
        case .driverEnRoute, .driverArrived, .inProgress:
            return false
        case .completed, .cancelled, .noVolunteer, .unknown:
            return false
        }
    }
}

/// 要排的一条提醒。纯值，单测直接比。
struct BlindRunStartReminder: Equatable {
    let orderId: Int64
    let fireDate: Date
    let body: String

    static let title = "助盲跑开跑提醒"

    /// 提前多久提醒。1 小时：够换衣服、找陪跑绳、出门；再早，到了出发时又忘了。
    static let leadTime: TimeInterval = 60 * 60

    static let identifierPrefix = "blindRunStartReminder-"

    var identifier: String { Self.identifierPrefix + String(orderId) }

    /// 从订单列表算出此刻应该排着的全部提醒。不在里面的，调用方会撤掉。
    ///
    /// 🔴 正文**不写出发地点**：锁屏上谁都看得见，而盲人的出发点常常就是家门口（F-14 同一条顾虑）。
    static func reminders(from orders: [OrderDetailResponse], now: Date = Date()) -> [BlindRunStartReminder] {
        orders.compactMap { order in
            guard order.status.remindsBlindRunnerBeforeStart,
                  let start = order.plannedStart?.backendTimestamp else { return nil }
            let fireDate = start.addingTimeInterval(-leadTime)
            guard fireDate > now else { return nil }
            let time = DateFormatter.aidRunDisplayDateTime.string(from: start)
            return BlindRunStartReminder(
                orderId: order.orderId,
                fireDate: fireDate,
                body: "\(Int(leadTime / 3600)) 小时后有一次陪跑，\(time) 开始。打开助盲跑可以查看出发地点和陪跑员。"
            )
        }
    }
}

/// 协议只为单测：单测里真排系统通知是系统级副作用（记忆 `hooks-on-shared-coordinators-fire-during-unit-tests`）。
protocol BlindRunStartReminderScheduling: AnyObject {
    /// 把本 App 排着的开跑提醒整体换成 `reminders`：多的撤掉，缺的补上，已有的按新时间重排。
    func replaceAll(with reminders: [BlindRunStartReminder]) async
}

final class BlindRunStartReminderCenter: BlindRunStartReminderScheduling {
    static let shared = BlindRunStartReminderCenter()

    private var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func replaceAll(with reminders: [BlindRunStartReminder]) async {
        guard !isRunningUnitTests else { return }
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let stale = pending.map(\.identifier).filter { $0.hasPrefix(BlindRunStartReminder.identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: stale)
        for reminder in reminders {
            let content = UNMutableNotificationContent()
            content.title = BlindRunStartReminder.title
            content.body = reminder.body
            content.sound = .default
            // 前台收到时 `PushNotificationsManager.willPresent` 念 `ttsText`。
            content.userInfo = ["ttsText": reminder.body]
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.fireDate)
            let request = UNNotificationRequest(
                identifier: reminder.identifier,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            )
            do {
                try await center.add(request)
            } catch {
                // 没授权通知时会走到这里。不重试、不弹权限（见文件头）。
                ClientFlowDiagnostics.record(event: "failed", operation: "blind-run-start-reminder")
                return
            }
        }
    }
}

enum BlindRunStartReminderSync {
    /// 拉一次 `GET /api/orders/mine`，按结果重排。首页的活跃订单一变就调（`BlindRunnerHomeViewModel.syncRunStartRemindersIfNeeded`）。
    ///
    /// 拉失败就什么都不动：撤掉的话，网络一抖就把用户已有的提醒全删了。返回这次有没有真的重排。
    @discardableResult
    static func refresh(
        using orders: any OrderServing,
        scheduler: any BlindRunStartReminderScheduling = BlindRunStartReminderCenter.shared,
        now: Date = Date()
    ) async -> Bool {
        guard let list = try? await orders.myOrders().content else { return false }
        await scheduler.replaceAll(with: BlindRunStartReminder.reminders(from: list, now: now))
        return true
    }
}
