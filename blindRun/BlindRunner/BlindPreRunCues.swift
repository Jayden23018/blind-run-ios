import SwiftUI
import UIKit

// MARK: - 订单页上的两句定时提示（#660 B-26、F-16）
//
// 都是「状态没变、但该出声」的场合，所以不挂在状态推进的播报上，单独由这个修饰符按时间触发。
// 只挂在订单页（`BlindOrderStatusView`），App 不在前台时不出声：后台念出来的话用户多半听不见，
// 回到前台又会和回前台那一轮刷新抢话（记忆 `later-speak-silently-cuts-the-earlier-one`）。

/// 等待匹配时定时念的那一句（B-26）。
///
/// 匹配页没有主操作（`BlindOrderFlowStep` 末尾那段：摆一个按钮会让人以为等待期有件必须做的事），
/// 而「已等待 N 分钟」此前只写在屏幕标签里。第一次用的全盲用户听不到任何声音，分不清系统在找人还是卡住了。
enum MatchingWaitCue {
    /// 两次之间隔多久。3 分钟：审计场景是「等了 20 分钟一点声音都没有」，3 分钟内就能听到系统还活着；
    /// 再短就成了催促，盖过用户自己在读屏上的操作。
    static let interval: TimeInterval = 3 * 60

    /// 同一次停留最多念几次（30 分钟）。再往后这句话不再带来新信息，用户可以随时按「重复当前状态」。
    static let maximumPerVisit = 10

    /// 播报档：最低档。它不打断任何一句（状态推进、错误、用户按的「重复当前状态」都比它高），
    /// 被压着排队超过 10 秒就丢弃（`AnnouncementQueue.perKilometerMaxQueueAge`）——
    /// 一句过期的「还在找」没有补念的价值。与每公里播报同档，因为两者同性质：定时、可丢的背景信息。
    static let priority: AnnouncementPriority = .perKilometer

    /// `nil` = 这一态不念（已经有人了，或订单已结束）。
    static func text(for order: OrderDetailResponse, now: Date = Date()) -> String? {
        guard order.status.offersWaitedDuration else { return nil }
        // 「已等待」的口径与屏幕上那一格同源，不另算（锚点、上限见 `blindRunnerWaitedText`）。
        let waited = order.blindRunnerWaitedText(now: now).map { "，\($0)" } ?? ""
        return "系统还在为你找陪跑员\(waited)。有人接单会马上告诉你。"
    }
}

/// 盲人本机低电量（F-16）。
///
/// 电量此前只经 `LOCATION_UPDATE` 推给陪跑员（`LiveEscortSessionCoordinator`），盲人自己听不到。
/// 而盲人的手机是他唯一的求助和定位工具，关机后两边都断。
enum LowBatteryCue {
    /// 不高于这个电量就提醒。20% 是 iOS 自己弹「电池电量不足」的那一档，用户对这个数有概念。
    static let threshold: Float = 0.20

    /// 计划开始前多久起算「快出发了」。2 小时：够充上一截电，或找出充电宝；再早提醒，到出发时电量早就变了。
    static let departureWindow: TimeInterval = 2 * 60 * 60

    /// 播报档：按需档。低于状态推进（不切断「陪跑员已到达」这类句子），高于每公里播报。
    static let priority: AnnouncementPriority = .onDemand

    /// - Parameter level: `UIDevice.batteryLevel`，未开监测或拿不到时是 -1。
    /// - Returns: `nil` = 不提醒。
    static func warning(
        level: Float,
        state: UIDevice.BatteryState,
        order: OrderDetailResponse,
        now: Date = Date()
    ) -> String? {
        guard level >= 0, level <= threshold else { return nil }
        // 正在充：提醒他「去充电」是废话。`.unknown` 照常提醒（监测刚打开时会短暂是它）。
        guard state != .charging, state != .full else { return nil }
        guard order.status.isActiveForBlindRunner, isNearOrUnderway(order, now: now) else { return nil }
        let percent = Int((level * 100).rounded())
        return "手机电量只剩百分之\(percent)。陪跑时要靠这台手机求助和定位，请尽快充电，或带上充电宝。"
    }

    private static func isNearOrUnderway(_ order: OrderDetailResponse, now: Date) -> Bool {
        if order.status.isUnderwayForBlindRunner { return true }
        guard let start = order.plannedStart?.backendTimestamp else { return false }
        return start.timeIntervalSince(now) <= departureWindow
    }
}

/// 每张单只提醒一次。进程内记账：首页与订单页都挂了这个提示，订单页压在首页上时两者都活着，
/// 靠同一本账保证只念一次。App 重启后会再提醒一次，可以接受。
@MainActor
final class LowBatteryCueLedger {
    static let shared = LowBatteryCueLedger()
    private var warnedOrderIDs: Set<Int64> = []

    /// 第一次为这张单要提醒时返回 `true`，之后都是 `false`。
    func claim(orderId: Int64) -> Bool {
        warnedOrderIDs.insert(orderId).inserted
    }
}

extension View {
    /// - Parameters:
    ///   - announcesMatchingWait: 只有订单页传 `true`。首页压在订单页底下时也活着，两处都念「还在找」会叠声。
    ///   - isFrontmost: 这一页是不是用户眼前那一页。上面压着别的页（语音下单、求助中心）时不出声：
    ///     语音下单正在听写时插一句，会被当成用户说的话。
    func blindRunnerPreRunCues(order: OrderDetailResponse?, announcesMatchingWait: Bool, isFrontmost: Bool) -> some View {
        modifier(BlindPreRunCuesModifier(order: order, announcesMatchingWait: announcesMatchingWait, isFrontmost: isFrontmost))
    }
}

private struct BlindPreRunCuesModifier: ViewModifier {
    let order: OrderDetailResponse?
    let announcesMatchingWait: Bool
    let isFrontmost: Bool
    @EnvironmentObject private var speechService: SpeechService
    @Environment(\.scenePhase) private var scenePhase

    /// 多久看一次电量。电量是慢变量，一分钟足够；也顺带覆盖「时间走进出发前 2 小时」。
    private static let batteryCheckInterval: TimeInterval = 60

    private var isActive: Bool { scenePhase == .active && isFrontmost }

    func body(content: Content) -> some View {
        content
            .task(id: "\(order?.orderId ?? 0)-\(order?.status.rawValue ?? "")-\(isActive)") {
                await runMatchingWaitCues()
            }
            .task(id: "\(order?.orderId ?? 0)-\(order?.status.rawValue ?? "")-\(isActive)-battery") {
                await runBatteryChecks()
            }
    }

    private func runMatchingWaitCues() async {
        guard announcesMatchingWait, isActive, let order, MatchingWaitCue.text(for: order) != nil else { return }
        for _ in 0..<MatchingWaitCue.maximumPerVisit {
            try? await Task.sleep(nanoseconds: UInt64(MatchingWaitCue.interval * 1_000_000_000))
            guard !Task.isCancelled, let text = MatchingWaitCue.text(for: order) else { return }
            speechService.speak(text, priority: MatchingWaitCue.priority)
        }
    }

    private func runBatteryChecks() async {
        guard isActive, let order, order.status.isActiveForBlindRunner else { return }
        // 只开不关：`LiveEscortSessionCoordinator` 也在读电量，这里关掉会让它上报 -1。
        UIDevice.current.isBatteryMonitoringEnabled = true
        while !Task.isCancelled {
            let device = UIDevice.current
            // 通话中这一档会被播报队列直接丢掉（只放行警示档），先别记账，挂断后下一轮再念。
            if let text = LowBatteryCue.warning(level: device.batteryLevel, state: device.batteryState, order: order),
               !speechService.isCallActive(),
               LowBatteryCueLedger.shared.claim(orderId: order.orderId) {
                speechService.speak(text, priority: LowBatteryCue.priority)
                return
            }
            try? await Task.sleep(nanoseconds: UInt64(Self.batteryCheckInterval * 1_000_000_000))
        }
    }
}
