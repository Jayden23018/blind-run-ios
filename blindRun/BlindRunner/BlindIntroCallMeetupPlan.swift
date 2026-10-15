import CoreLocation
import Foundation
import UserNotifications

// MARK: - 盲人端「先通个电话」B1–B3 的纯逻辑（#434，OpenSpec `add-intro-call-meetup-plan` 第 4 组）
//
// 两端共用的部分（安排单、子状态、朗读文本、回前台判据、倒计时节点）在
// `Core/Models/IntroCallMeetupPlan.swift`（#436 / #432）。这里只放**盲人端自己**才有的：
// B3 每一行画什么、`notify-incoming` 节流、10 分钟未确认提醒、两句结局播报。
// 文案与读屏原话逐字取视觉稿 v2 `docs/ui/mockups/intro-call-meetup-plan-20261015/index.html`。

// MARK: - B3 的行

/// B3 安排单的一行。**一行 = 一个读屏元素**，`speech` 就是它的读屏标签。
struct BlindMeetupPlanRow: Equatable, Identifiable {
    enum Kind: String, Equatable {
        case time
        case place
        case meetSpot
        case colors
        case greeting
    }

    let kind: Kind
    /// 「开跑时间」。固定句那一行没有标题。
    let title: String?
    /// 标题旁的「已变更」小标签。**不用删除线** —— 读屏念不出删除线（视觉稿决定 4）。
    let isChanged: Bool
    /// 主值，每个元素一行（上衣颜色是两行）。
    let values: [String]
    /// 「原定 7:00 – 8:00」。只有已变更的项有。
    let original: String?
    /// 读屏标签。取自 `IntroCallMeetupCopy.planSpeech`，**不在这里另写一套**。
    let speech: String

    var id: Kind { kind }
}

/// 把一张安排单排成 B3 的五种行，顺序固定：开跑时间 → 集合地点 → 具体见面位置 → 上衣颜色 → 固定句。
///
/// 🚩 读屏标签**只来自** `IntroCallMeetupCopy.planSpeech`。这里按开头的固定字样把那几句认领到行上，
/// 不自己再判一遍「这一项念不念」—— 两边各判一次，迟早一边多一行、一边少一句。
/// 认领不到的句子（将来朗读加了第六种）也照样出一行，只是没有视觉值，**宁可多念不许漏念**。
enum BlindMeetupPlanLayout {

    static func rows(
        plan: IntroCallMeetupPlan,
        original: IntroCallOriginalArrangement,
        volunteerName: String,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> (titleSpeech: String, changeCount: Int, rows: [BlindMeetupPlanRow]) {
        let speech = IntroCallMeetupCopy.planSpeech(
            plan: plan, original: original, volunteerName: volunteerName, now: now, calendar: calendar
        )
        let changes = plan.changes(from: original)
        let rows = speech.items.map { item -> BlindMeetupPlanRow in
            if item.hasPrefix("开跑时间") {
                return timeRow(plan: plan, original: original, changes: changes, speech: item, now: now, calendar: calendar)
            }
            if item.hasPrefix("集合地点") {
                return placeRow(plan: plan, original: original, changes: changes, speech: item)
            }
            if item.hasPrefix("具体见面位置") {
                return BlindMeetupPlanRow(
                    kind: .meetSpot, title: "具体见面位置", isChanged: false,
                    values: [plan.meetSpotNote?.nilIfBlank ?? ""], original: nil, speech: item
                )
            }
            if item == IntroCallMeetupCopy.fixedGreetingLine {
                return BlindMeetupPlanRow(
                    kind: .greeting, title: nil, isChanged: false, values: [item], original: nil, speech: item
                )
            }
            return colorRow(plan: plan, speech: item)
        }
        return (speech.title, changes.count, rows)
    }

    /// 「明天 7:30 – 8:30」。
    static func timeRange(start: Date, end: Date?, now: Date, calendar: Calendar) -> String {
        let day = IntroCallMeetupCopy.spokenDay(start, now: now, calendar: calendar)
        let clock = { (date: Date) in VolunteerOrderTimeCopy.clock(date) }
        guard let end else { return "\(day) \(clock(start))" }
        return "\(day) \(clock(start)) – \(clock(end))"
    }

    private static func timeRow(
        plan: IntroCallMeetupPlan,
        original: IntroCallOriginalArrangement,
        changes: IntroCallMeetupChanges,
        speech: String,
        now: Date,
        calendar: Calendar
    ) -> BlindMeetupPlanRow {
        let start = plan.plannedStartTime ?? original.plannedStartTime
        let end = plan.plannedEndTime ?? original.plannedEndTime
        let value = start.map { timeRange(start: $0, end: end, now: now, calendar: calendar) } ?? ""
        // 「原定」只写钟点不写日：同一张单上「明天」念两遍是噪音；改到别的日子时主值那行已经写了新日子。
        let originalText: String? = changes.timeChanged ? original.plannedStartTime.map { originalStart in
            let clock = VolunteerOrderTimeCopy.clock(originalStart)
            let endClock = original.plannedEndTime.map { " – " + VolunteerOrderTimeCopy.clock($0) } ?? ""
            let sameDay = start.map { calendar.isDate($0, inSameDayAs: originalStart) } ?? true
            let day = sameDay ? "" : IntroCallMeetupCopy.spokenDay(originalStart, now: now, calendar: calendar) + " "
            return "原定 \(day)\(clock)\(endClock)"
        } : nil
        return BlindMeetupPlanRow(
            kind: .time, title: "开跑时间", isChanged: changes.timeChanged,
            values: [value], original: originalText, speech: speech
        )
    }

    private static func placeRow(
        plan: IntroCallMeetupPlan,
        original: IntroCallOriginalArrangement,
        changes: IntroCallMeetupChanges,
        speech: String
    ) -> BlindMeetupPlanRow {
        let address = plan.startAddress?.nilIfBlank ?? original.startAddress?.nilIfBlank ?? ""
        var originalText: String?
        if changes.placeChanged {
            // 原地名写全，不截前缀（理由同 `IntroCallMeetupCopy.placeItem`：集合点是可能是威胁来源的一方改的）。
            let from = original.startAddress?.nilIfBlank.map { "原定 \($0)" }
            let distance = changes.distanceFromOriginalMeters
                .flatMap { $0 >= IntroCallMeetupCopy.minimumSpokenDistanceMeters ? $0 : nil }
                .map { "距原地点约 \(DistanceCalculator.formattedDistance($0))" }
            let parts = [from, distance].compactMap { $0 }
            originalText = parts.isEmpty ? nil : parts.joined(separator: "，")
        }
        return BlindMeetupPlanRow(
            kind: .place, title: "集合地点", isChanged: changes.placeChanged,
            values: [address], original: originalText, speech: speech
        )
    }

    /// 「陪跑员：红色」「你：蓝色（通话中确认）」。只出现颜色名，不画色块（视觉稿决定 5）。
    private static func colorRow(plan: IntroCallMeetupPlan, speech: String) -> BlindMeetupPlanRow {
        var values: [String] = []
        if let volunteer = plan.volunteerTopColor?.spokenName { values.append("陪跑员：\(volunteer)") }
        if let runner = plan.runnerTopColor?.spokenName { values.append("你：\(runner)（通话中确认）") }
        return BlindMeetupPlanRow(
            kind: .colors, title: "上衣颜色", isChanged: false, values: values, original: nil, speech: speech
        )
    }
}

// MARK: - notify-incoming 节流

/// `POST /intro-call/notify-incoming` 的客户端节流：**60 秒内最多发一次**（设计文档 §4，修审查 #10）。
///
/// 每次「再次致电」都会让陪跑员手机响一条 HIGH 通知「跑者正在给你打电话」。盲人连按几次拨号
/// （确认框点了取消、又点一次）时，对方会被同一句话连轰。节流只管通知，**拨号本身从不拦**。
struct IntroCallIncomingNotifyThrottle: Equatable {
    static let interval: TimeInterval = 60

    private(set) var lastSentAt: Date?

    /// 返回 true = 这一次该发；同时记下发送时刻。
    mutating func shouldNotify(now: Date) -> Bool {
        if let lastSentAt, now.timeIntervalSince(lastSentAt) < Self.interval { return false }
        lastSentAt = now
        return true
    }
}

// MARK: - 10 分钟未确认提醒

/// 安排单发来 10 分钟仍未确认、窗口还没到期时**提醒一次**（设计文档 §4，视觉稿 ④「临期提醒」）。
///
/// - 起点取这一版的 `submittedAt`（服务端时刻）；拿不到就取客户端**第一次看到这一版**的时刻。
///   陪跑员改了一版，起点跟着换 —— 新内容要重听，10 分钟从新的一版算。
/// - 「一次」是**这一轮**一次：响过之后陪跑员再改也不再响（`IntroCallMeetupCopy.planChangedRelisten` 已经会说）。
/// - 到点时窗口已过不响：超时由服务端宣布，客户端不抢。
/// - App 在前台时由调用方播报；不在前台时由调用方排一条本地通知，`markDeliveredWhileAway` 记账，
///   回到前台不再补播 —— 同一件事说两遍就不是「一次」了。
struct IntroCallPlanReminder: Equatable {
    static let delay: TimeInterval = 10 * 60

    private(set) var hasReminded = false
    private(set) var dueAt: Date?
    private var trackedVersion: Int?
    private var firstSeenAt: Date?

    /// 每次拉到通话数据喂一次。`isAwaitingConfirmation == false`（没有安排单 / 已确认）时清掉到期时刻。
    mutating func observe(
        planVersion: Int?,
        submittedAt: Date?,
        isAwaitingConfirmation: Bool,
        windowEndsAt: Date?,
        now: Date
    ) {
        guard let planVersion, isAwaitingConfirmation, !hasReminded else {
            dueAt = nil
            return
        }
        if trackedVersion != planVersion {
            trackedVersion = planVersion
            firstSeenAt = now
        }
        guard let start = submittedAt ?? firstSeenAt else {
            dueAt = nil
            return
        }
        let due = start.addingTimeInterval(Self.delay)
        if let windowEndsAt, due >= windowEndsAt {
            dueAt = nil
            return
        }
        dueAt = due
    }

    /// 前台轮询时问一次。返回 true = 现在播，并记成已提醒。
    mutating func consumeIfDue(now: Date) -> Bool {
        guard !hasReminded, let dueAt, now >= dueAt else { return false }
        hasReminded = true
        self.dueAt = nil
        return true
    }

    /// 回到前台时调：离开期间到点的那条已经由本地通知送达过了。
    mutating func markDeliveredWhileAway(now: Date) {
        guard let dueAt, now >= dueAt else { return }
        hasReminded = true
        self.dueAt = nil
    }
}

/// 10 分钟提醒的本地通知。**协议只为单测**：单测里真排一条系统通知是系统级副作用
/// （记忆 `hooks-on-shared-coordinators-fire-during-unit-tests`）。
protocol IntroCallPlanReminderNotifying: AnyObject {
    func schedule(orderId: Int64, at dueAt: Date)
    func cancel(orderId: Int64)
}

/// 真实实现。前台收到时 `PushNotificationsManager.willPresent` 会念出来 —— 所以只在**进后台时**排、
/// 回前台立刻撤（`BlindOrderStatusViewModel.observeScenePhase`），前台那一次由 view model 自己播。
final class IntroCallPlanReminderNotifier: IntroCallPlanReminderNotifying {
    static let shared = IntroCallPlanReminderNotifier()

    private var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    static func identifier(orderId: Int64) -> String { "introCallPlanReminder-\(orderId)" }

    func schedule(orderId: Int64, at dueAt: Date) {
        guard !isRunningUnitTests else { return }
        let interval = dueAt.timeIntervalSinceNow
        guard interval > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = IntroCallCopy.blindPlanReminderTitle
        content.body = IntroCallCopy.blindPlanReminderBody
        content.sound = .default
        content.userInfo = ["ttsText": IntroCallCopy.blindPlanReminderSpeech]
        let request = UNNotificationRequest(
            identifier: Self.identifier(orderId: orderId),
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        )
        Task {
            do {
                try await UNUserNotificationCenter.current().add(request)
            } catch {
                // 没授权通知时会走到这里。不重试、不打扰：前台那一次播报不依赖它。
                ClientFlowDiagnostics.record(event: "failed", operation: "intro-call-plan-reminder")
            }
        }
    }

    func cancel(orderId: Int64) {
        guard !isRunningUnitTests else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [Self.identifier(orderId: orderId)]
        )
    }
}

// MARK: - 结局播报

enum BlindIntroCallOutcomeCopy {

    /// 本轮没约成时说的话。盲人**听过安排单**（`hadPlan`）就先说「本次见面安排未生效」——
    /// 免得以为刚听的安排已经定了（视觉稿 ④ 最后一块、时间线 8′）。后半句仍是中性的 `continuedSearch`。
    static func roundEnded(hadPlan: Bool) -> String {
        hadPlan ? IntroCallCopy.blindPlanNotTakenEffect + IntroCallCopy.continuedSearch : IntroCallCopy.continuedSearch
    }

    /// 约好那一刻（`PENDING_INTRO_CALL` → `PENDING_ACCEPT` / `SCHEDULED_CONFIRMED`）的整句。
    /// 视觉稿原话：「约定完成。明天 7 点 30 分，朝阳公园东门，东门保安亭左侧。陪跑员李*上衣为红色，见面时将主动上前并告知姓氏。」
    ///
    /// 取的是**订单**上的字段（安排单约成后已写进订单），不是通话页的旧数据。每段拿不到就省掉那段。
    static func agreed(order: OrderDetailResponse, now: Date = Date(), calendar: Calendar = .current) -> String {
        var place: [String] = []
        if let start = order.plannedStart?.nilIfBlank?.backendTimestamp {
            place.append("\(IntroCallMeetupCopy.spokenDay(start, now: now, calendar: calendar)) \(spokenClockWithUnit(start, calendar: calendar))")
        }
        if let address = order.startAddress?.nilIfBlank { place.append(address) }
        if let note = order.meetSpotNote?.nilIfBlank { place.append(note) }

        var text = "约定完成。"
        if !place.isEmpty { text += place.joined(separator: "，") + "。" }
        let name = order.volunteerName?.nilIfBlank?.unmaskedForSpeech
        let who = name.map { "陪跑员\($0)" } ?? "陪跑员"
        if let color = order.volunteerTopColor?.spokenName {
            text += "\(who)上衣为\(color)，见面时将主动上前并告知姓氏。"
        } else {
            text += "见面时\(who)将主动上前并告知姓氏。"
        }
        return text
    }

    /// 「7 点 30 分」「7 点」。整句播报里带「分」（视觉稿原话），B3 逐项朗读不带（`spokenClock`）。
    static func spokenClockWithUnit(_ date: Date, calendar: Calendar = .current) -> String {
        let minute = calendar.component(.minute, from: date)
        let clock = IntroCallMeetupCopy.spokenClock(date, calendar: calendar)
        return minute == 0 ? clock : "\(clock) 分"
    }
}
