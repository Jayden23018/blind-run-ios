import Foundation

// MARK: - 订单页 v7 ①–④ 的纯值内容（#917，定稿 `docs/ui/mockups/blind-order-tracking-20261109/`）
//
// ① 匹配中（含 REMATCHING）、②③ 商量见面安排（通话 / 确认安排单）、④ 已约好（含 PENDING_ACCEPT）。
// 这几屏用深色头 + 白底抽屉 + 五步竖线（`BlindOrderTimeline`），求助在右上角胶囊。
// ②③ 的头部与卡片内容由 `BlindIntroCallView` 按通话子状态算（数据在通话端点里），这里只管 ①④ 与共用部分。

/// 这一态用 v7 的哪一屏。`nil` = 不走这套版式（出发起由 #918 另做；终态、未知态各有落点）。
enum BlindOrderStage: Equatable {
    case matching
    case introCall
    case booked

    /// 穷举 switch：后端加状态时编译器会逼一次决策。
    static func resolve(_ status: RunOrderStatus) -> BlindOrderStage? {
        switch status {
        case .pendingMatch, .rematching: return .matching
        case .pendingIntroCall: return .introCall
        case .scheduledConfirmed, .pendingAccept: return .booked
        case .driverEnRoute, .driverArrived, .inProgress, .completed,
             .cancelled, .noVolunteer, .unknown:
            return nil
        }
    }
}

/// ①–④ 上的新句子。**既有的句子不在这里重写**，直接取原常量。
enum BlindOrderStageCopy {
    static let matchingEyebrow = "匹配中"
    static let matchingTitle = "正在为你找陪跑员"
    /// ① 深色卡（负责人 11-11 第 12 条改的文案）。「最晚开跑前半小时会有结果」等 backend#949，**不写**。
    static let matchingCardLead = "可以先离开这个页面"
    static let matchingCardBody = "找到后马上通知你"
    /// ① 当前步小字（#926，稿 `blind-matching-wait-20261111/` 第 3 条）：「已等 3 分钟」「已等 2 小时 15 分钟」。
    /// 「X 小时 Y 分钟」沿用仓库已有的格式器，不另写一份（稿 B 帧注释）。取 `VolunteerMeetupPlanCopy` 那份
    /// 是因为它不带 `@MainActor`（约跑页、跑步记录那两份都挂在 view model 上）；整小时写「2 小时」。
    static func matchingWaited(minutes: Int) -> String {
        "已等 \(VolunteerMeetupPlanCopy.durationText(minutes))"
    }
    /// 找到那一刻旧 ① 当前步的小字（稿 C 帧 0–0.3 秒）。
    static let matchFound = "刚刚找到"

    static let introCallEyebrow = "先通个电话"
    static let introCallCandidateLabel = "想陪你跑的陪跑员"
    static func introCallDetail(remaining: String?) -> String {
        ["先通电话，再确认安排", remaining].compactMap { $0 }.joined(separator: " · ")
    }
    static func planDetail(remaining: String?) -> String {
        ["电话已通，请确认安排", remaining].compactMap { $0 }.joined(separator: " · ")
    }

    static let bookedEyebrow = "已约好"
    static func bookedTitle(start: String) -> String { "\(start) 开跑" }
    /// ④ 深色卡。稿原是「陈预计出发 1:05–1:10」，盲人侧拿不到 `suggestedDepartAt`（backend#943），先这么写。
    static func bookedCardLead(name: String) -> String { "\(name)出发时" }
    static let bookedCardBody = "会通知你"
    static let bookedVolunteerLabel = "你的陪跑员"

    /// ④ 当前步小字。提前量取 `BlindRunStartReminder.leadTime`，不写死。
    static func departureReminder(leadTime: TimeInterval) -> String {
        let minutes = Int(leadTime / 60)
        let amount = minutes % 60 == 0 ? "\(minutes / 60) 小时" : "\(minutes) 分钟"
        return "开跑前 \(amount)会提醒你出门"
    }

    static let cancelMatching = "取消匹配"
    static let cancelBooking = "取消预约"
    static let runnerMessage = "给陪跑员留言"
}

/// ①④ 底部的按钮。②③ 的按钮在 `BlindIntroCallView`（拨号、确认安排单都走通话那一套）。
enum BlindOrderStageBottomAction: Equatable {
    /// REMATCHING 且还能延长：实心。
    case keepWaiting
    /// 取消匹配：描边。identifier 沿用旧的「最后一行」（`blindOrderFlowLastRowButton`）。
    case cancelMatching
    /// 打电话给陪跑员：实心。只在拼得出 `tel:` URL 时给。
    case callVolunteer(title: String)
}

/// ①④ 一屏的全部内容。**文案一律取既有常量或 `BlindOrderStageCopy`**，视图里不写中文字面量。
struct BlindOrderStagePresentation: Equatable {
    let stage: BlindOrderStage
    let eyebrow: String
    let title: String
    /// 抽屉顶上那行粗字（集合地点）。拿不到不画。
    let place: String?
    /// 地点下面那行小字（时间，或时段单的时段说明）。
    let when: String?
    let timeline: BlindOrderTimelineInput
    /// 当前步卡片上半截深色块的两行。
    let cardLead: String
    let cardBody: String
    /// 当前步卡片下半截的陪跑员行（④）。`nil` = 只有深色块（①）。
    let volunteer: Volunteer?
    let bottom: [BlindOrderStageBottomAction]
    let menu: [BlindOrderMenuItem.Kind]

    struct Volunteer: Equatable {
        /// 头像里那个字。
        let initial: String
        let label: String
        /// 屏幕上那行：「陈* · 蓝色上衣 · 陪跑 32 次」（姓名保留掩码）。
        let line: String
        /// 读屏那句：去星号。
        let spoken: String
    }

    /// 头部合成一个读屏元素念的那句。
    var headerAccessibilityLabel: String {
        "\(eyebrow)。\(title)"
    }

    /// `nil` = 这一态不是 ① 或 ④。
    static func make(
        order: OrderDetailResponse,
        canKeepWaiting: Bool,
        now: Date = Date()
    ) -> BlindOrderStagePresentation? {
        guard let stage = BlindOrderStage.resolve(order.status),
              let position = order.status.blindOrderTimelinePosition else { return nil }
        switch stage {
        case .matching:
            return matching(order: order, position: position, canKeepWaiting: canKeepWaiting, now: now)
        case .booked:
            return booked(order: order, position: position, now: now)
        case .introCall:
            return nil
        }
    }

    /// 找到那一刻前 0.3 秒的旧 ①：当前点打勾、小字换「刚刚找到」（稿 C 帧第一格）。不是 ① 时原样返回。
    func markingMatchFound() -> BlindOrderStagePresentation {
        guard stage == .matching else { return self }
        var timeline = timeline
        timeline.currentDot = .justFound
        timeline.details[.matchVolunteer] = BlindOrderStageCopy.matchFound
        return BlindOrderStagePresentation(
            stage: stage, eyebrow: eyebrow, title: title, place: place, when: when, timeline: timeline,
            cardLead: cardLead, cardBody: cardBody, volunteer: volunteer, bottom: bottom, menu: menu
        )
    }

    /// 地点行。④ 把陪跑员写的具体见面位置接在后面（同 ③「朝阳公园南门 · 南门保安亭左边」）。
    static func placeLine(order: OrderDetailResponse, includesMeetSpot: Bool) -> String? {
        guard let address = order.startAddress?.nilIfBlank else { return nil }
        guard includesMeetSpot, let spot = order.meetSpotNote?.nilIfBlank else { return address }
        return "\(address) · \(spot)"
    }

    private static func matching(
        order: OrderDetailResponse,
        position: BlindOrderTimelinePosition,
        canKeepWaiting: Bool,
        now: Date
    ) -> BlindOrderStagePresentation {
        var details: [BlindOrderTimelineStep: String] = [:]
        if let minutes = order.blindRunnerWaitedMinutes(now: now) {
            details[.matchVolunteer] = BlindOrderStageCopy.matchingWaited(minutes: minutes)
        }
        var bottom: [BlindOrderStageBottomAction] = []
        // 判据与改版前同一个（`offersBlindRunnerKeepWaitingControl`）：只有 REMATCHING 是真延长。
        if order.status.offersBlindRunnerKeepWaitingControl, canKeepWaiting {
            bottom.append(.keepWaiting)
        }
        if order.status.canBlindRunnerCancel {
            bottom.append(.cancelMatching)
        }
        return BlindOrderStagePresentation(
            stage: .matching,
            eyebrow: BlindOrderStageCopy.matchingEyebrow,
            title: order.status == .rematching ? order.blindRunnerRematchingTitle : BlindOrderStageCopy.matchingTitle,
            place: placeLine(order: order, includesMeetSpot: false),
            when: order.flexibleMatchingDescription ?? order.blindRunnerShortStartText(now: now),
            // 只有 ① 呼吸：匹配是长等待，等待指示要一直在动（稿第 3 条）。
            timeline: BlindOrderTimelineInput(position: position, details: details, currentDot: .breathing),
            cardLead: BlindOrderStageCopy.matchingCardLead,
            cardBody: BlindOrderStageCopy.matchingCardBody,
            volunteer: nil,
            bottom: bottom,
            menu: []
        )
    }

    private static func booked(
        order: OrderDetailResponse,
        position: BlindOrderTimelinePosition,
        now: Date
    ) -> BlindOrderStagePresentation {
        let name = order.volunteerNameForSpeech
        let start = order.blindRunnerShortStartText(now: now)
        var bottom: [BlindOrderStageBottomAction] = []
        // 判据「拼不拼得出 tel: URL」：掩码串会被 `telURL` 拦掉（同 `BlindOrderFlowPresentation.primaryAction`）。
        if order.status.offersVolunteerCall,
           EmergencyDialer.telURL(for: order.volunteerPhone?.nilIfBlank) != nil {
            bottom.append(.callVolunteer(title: "打电话给\(name)"))
        }
        var menu: [BlindOrderMenuItem.Kind] = []
        if order.status.canBlindRunnerCancel { menu.append(.cancelBooking) }
        if order.status.offersRunPlanShare { menu.append(.shareRunPlan) }
        if order.status.acceptsRunnerMessage { menu.append(.runnerMessage) }
        return BlindOrderStagePresentation(
            stage: .booked,
            eyebrow: BlindOrderStageCopy.bookedEyebrow,
            title: start.map(BlindOrderStageCopy.bookedTitle(start:)) ?? order.status.displayName,
            place: placeLine(order: order, includesMeetSpot: true),
            when: start,
            timeline: BlindOrderTimelineInput(
                position: position,
                details: [.awaitDeparture: BlindOrderStageCopy.departureReminder(leadTime: BlindRunStartReminder.leadTime)]
            ),
            cardLead: BlindOrderStageCopy.bookedCardLead(name: name),
            cardBody: BlindOrderStageCopy.bookedCardBody,
            volunteer: bookedVolunteer(order: order, name: name),
            bottom: bottom,
            menu: menu
        )
    }

    /// 稿 ④「陈* · 陪跑 32 次」+ 上衣颜色（同 ⑤「蓝色上衣 · 陪跑 32 次」）。只写后端真发了的项。
    private static func bookedVolunteer(order: OrderDetailResponse, name: String) -> Volunteer? {
        guard let masked = order.volunteerName?.nilIfBlank else { return nil }
        let color = order.volunteerTopColor?.spokenName.map { "\($0)上衣" }
        let parts = [masked, color, order.volunteerExperienceText].compactMap { $0 }
        let spokenParts = [name, color, order.volunteerExperienceText].compactMap { $0 }
        return Volunteer(
            initial: name.first.map(String.init) ?? "陪",
            label: BlindOrderStageCopy.bookedVolunteerLabel,
            line: parts.joined(separator: " · "),
            spoken: "\(BlindOrderStageCopy.bookedVolunteerLabel)，\(spokenParts.joined(separator: "，"))"
        )
    }
}

// MARK: - 匹配中的等待与「找到了」那一刻（#926，稿 `docs/ui/mockups/blind-matching-wait-20261111/`）

enum BlindMatchingWaitTiming {
    /// 呼吸半程：3 秒一个来回（稿第 3 条）。
    static let breathHalfCycle: TimeInterval = 1.5
}

/// 找到那一刻约 1 秒的时间点（稿 C 帧：0–0.3 打勾、0.3–0.8 竖线长与标题换字、1 秒定格）。
enum BlindMatchFoundTiming {
    /// 打勾那一格多长；之后揭开新屏。
    static let checkPhase: TimeInterval = 0.3
    /// 打勾放大到多大、放大用多久（之后弹簧弹回）。
    static let popScale: CGFloat = 1.3
    static let popUp: TimeInterval = 0.12
    /// 新旧两屏交叉淡入多久；减弱动态效果时整段就是这一下（稿「0.25 秒淡入淡出」）。
    static let crossfade: TimeInterval = 0.25
    /// 竖线往下长、新卡片上浮淡入多久。
    static let lineGrow: TimeInterval = 0.5
    /// 新卡片和主按钮从下方多远淡入。
    static let riseOffset: CGFloat = 8
    /// 从开始到定格（之后读屏焦点才挪到新标题）。
    static let total: TimeInterval = 1.0
}

/// 一次「找到陪跑员」过渡。由 `apply` 在换订单的同一刻置上，订单页演完后清掉。
struct BlindMatchFoundTransition: Equatable {
    let id = UUID()
    /// 换之前那一单（`PENDING_MATCH` / `REMATCHING`）。前 0.3 秒照它画旧 ①。
    let previousOrder: OrderDetailResponse
    /// 已经揭开到新屏（前 0.3 秒为 `false`）。
    var revealed = false

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id && lhs.revealed == rhs.revealed }

    /// 该不该放这段过渡。**只认「人一直看着 ① 等，然后它变成了 ② 或 ④」**（稿第 4、5 条）：
    /// - `previous == nil`：冷启动 / 点通知进来，人没看过等待那一屏，直接显示定格屏。
    /// - `watchedContinuously == false`：上一次刷新之后 App 进过后台，同理不补放。
    /// - 落点只认 v7 ②（通话）与 ④（已约好，`requiresIntroCall=false` 的单）；
    ///   取消、暂无陪跑员、同态刷新、匹配两态之间互转都不放。
    static func shouldPlay(from previous: RunOrderStatus?, to status: RunOrderStatus, watchedContinuously: Bool) -> Bool {
        guard watchedContinuously, let previous, BlindOrderStage.resolve(previous) == .matching else { return false }
        switch BlindOrderStage.resolve(status) {
        case .introCall, .booked: return true
        case .matching, nil: return false
        }
    }
}
