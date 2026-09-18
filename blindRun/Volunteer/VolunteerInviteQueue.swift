import Foundation

// MARK: - 一条待回复的邀请

/// 设计交付文档 v3 §4.4.2 / §4.4.3 的那张卡背后的状态。
///
/// 🚩 **它不是 `RealtimeDispatchPrompt` 的副本**，多出来的是「这一条已经有结果了」：
/// §4.4.3 要求结果**原地**变化（接下成功 / 已失效），不关掉再弹一个新弹层。
/// 所以回复成功之后这条邀请不能直接从队列里删掉 —— 删了卡片就跟着消失，
/// 而那正是设计稿点名不要的那种「弹层套弹层」。
struct VolunteerInviteState: Identifiable {
    enum Outcome {
        /// 已接下（`ACCEPT` 成功）。卡片原地变「已约好」。
        case accepted
        /// 回复期限已过。卡片原地变「这个邀请已失效」。
        case expired
    }

    let order: WSNewOrder
    let receivedAt: Date
    let expiresAt: Date
    /// 每秒由 view model 的 ticker 刷新。
    var remainingSeconds: Int
    /// `nil` = 还等着回复。
    var outcome: Outcome?

    /// 派单载荷给不了、要另外去 `GET /api/orders/available` 取的那三项。
    ///
    /// `nil` = 还没拉到 / 拉到了但这一单不在列表里 ⇒ **跑者那一行整行不渲染**。
    /// 不占位、不编 —— 给还没见面的陪跑员印一个猜的视力程度，见面第一下就会抓错人。
    ///
    /// 声明成带默认值的 `var`，好让 memberwise init 的既有构造点不必各补一行
    /// （同 `OrderDetailResponse.volunteerId` 那条）。
    var supplement: VolunteerInviteSupplement?

    /// 这一条是在他**正陪着人跑**的时候到的（设计交付 v3 §4.4.1 最后一行）。
    ///
    /// 只影响接单主页那张卡的标题（「陪跑时收到 N 个新邀请」而不是「N 个新邀请」）——
    /// 那句话在解释「为什么我当时一点感觉都没有」，没有它，静默暂存看起来就像丢了邀请。
    ///
    /// 声明成带默认值的 `var`，理由同 `supplement`：memberwise init 的既有构造点不必各补一行。
    var arrivedDuringEscort = false

    var id: Int64 { order.orderId }
    var isAwaitingReply: Bool { outcome == nil }

    /// 进度条的分母。**取 `expiresAt - receivedAt` 而不是 `dispatchTimeoutSeconds`**：
    /// 后端把窗口算在**发出**那一刻（`timestamp`），推送在路上耗掉的时间是真的少掉了，
    /// 拿标称值当分母会让进度条一上来就跳一段。
    var totalSeconds: Int {
        max(1, Int(ceil(expiresAt.timeIntervalSince(receivedAt))))
    }

    /// 剩余占比，0…1。
    var remainingFraction: Double {
        min(1, max(0, Double(remainingSeconds) / Double(totalSeconds)))
    }

    /// 进度条与剩余时间文字转「深黄」的那一刻（设计交付 v3 §4.4.2 第 3 项）。
    ///
    /// ⚠️ 设计稿的判据是「剩余 < 15 **分钟**」，那是按 §10「回复期限 1 小时 / 15 分钟」写的。
    /// 后端目前只有 `app.dispatch.per-volunteer-timeout-seconds=30`，一整个窗口才 30 秒 ——
    /// 照 15 分钟写等于**从第一帧就是深黄**，那条视觉提示就没有了。
    /// 所以沿用弹窗原有的 10 秒阈值（`VolunteerOrderFlowCopy.urgentCountdownSeconds`），
    /// 与「查看详情」那一页说同一句话。预约单的分钟级回复期限已投 handoff。
    var isUrgent: Bool {
        remainingSeconds <= VolunteerOrderFlowCopy.urgentCountdownSeconds
    }
}

// MARK: - 派单载荷之外的那三项

/// 设计交付 v3 §4.4.2 第 7 项的跑者行（视力 + 引导方式），以及项目负责人点名要的「跑多久」。
///
/// 🔴 **三项都不在 `NEW_ORDER` 推送里**，只能另外去 `GET /api/orders/available` 取
/// （见 `AvailableOrderResponse` 对「为什么正在等我回复的那一单也在那个列表里」的说明）。
///
/// 两个枚举字段存 `rawValue` 而不是枚举：后端往枚举加值时不许整条崩（AGENTS.md 硬约束），
/// 认不出的取值落 `EscortNeed.confirmInPerson`，而不是丢掉这一行 ——
/// 丢掉等于告诉陪跑员「跑者没有偏好」，而真实情况是「跑者填了，只是这个版本不认识」。
struct VolunteerInviteSupplement: Equatable, Sendable {
    let visionLevel: String?
    let tetherPreference: String?
    let expectedDurationMinutes: Int?

    init(visionLevel: String?, tetherPreference: String?, expectedDurationMinutes: Int?) {
        self.visionLevel = visionLevel
        self.tetherPreference = tetherPreference
        self.expectedDurationMinutes = expectedDurationMinutes
    }

    init(_ order: AvailableOrderResponse) {
        self.init(
            visionLevel: order.visionLevel,
            tetherPreference: order.tetherPreference,
            expectedDurationMinutes: order.expectedDurationMinutes
        )
    }

    /// 「视力情况 / 引导方式」两行，**空数组 = 那一行不渲染**。
    ///
    /// 与 `OrderDetailResponse.escortNeeds` 共用 `EscortNeed` 的形状与兜底文案，
    /// 但**刻意不带那条「跑者没有填写」的兜底行**：接单后那一屏是志愿者出发前的清单，
    /// 少一条要提醒他去问；邀请卡是一次 30 秒的打断，多一行「没填」只是噪音。
    /// 导盲犬那一行也不在这里 —— 它的源是 `WSNewOrder.hasGuideDog`，另一个数据源。
    var escortNeeds: [EscortNeed] {
        var needs: [EscortNeed] = []
        if let raw = visionLevel?.nilIfBlank {
            needs.append(EscortNeed(
                kind: .vision,
                symbolName: "eye.slash",
                title: "视力情况",
                value: VisionLevel(rawValue: raw)?.displayName ?? EscortNeed.confirmInPerson
            ))
        }
        if let raw = tetherPreference?.nilIfBlank {
            needs.append(EscortNeed(
                kind: .tether,
                symbolName: "link",
                title: "引导方式",
                value: TetherPreference(rawValue: raw)?.displayName ?? EscortNeed.confirmInPerson
            ))
        }
        return needs
    }

    /// 邀请卡跑者行那句小字（「全盲，牵引绳」）。`nil` = 整行不渲染。
    ///
    /// ⚠️ 措辞取 `VisionLevel` / `TetherPreference` 的 `displayName`（盲人端也在用的单一源），
    /// **不照设计稿写「用引导绳」** —— 为一处措辞抄第二份必然漂移，而「引导方式说法不一致」
    /// 不会有任何东西报警。
    var runnerSummary: String? {
        escortNeeds.map(\.value).joined(separator: "，").nilIfBlank
    }

    /// 「跑多久」那一行的值。`nil` = 后端没这个数，那一行不渲染。
    /// 写法与订单详情页既有的「预计时长」一致（`VolunteerOrderFlowViews.swift` 与
    /// `BlindOrderStatusView.swift` 都是 `"\(minutes) 分钟"`）。
    var durationText: String? {
        guard let minutes = expectedDurationMinutes, minutes > 0 else { return nil }
        return "\(minutes) 分钟"
    }
}

extension VolunteerInviteState {
    /// 把一次 `GET /api/orders/available` 的结果按 `orderId` 灌进队列。
    ///
    /// 🔴 **必须按 id 匹配，不许「取第一条」。** 那个列表是「附近可接的单」，
    /// 按距离升序、最多 20 条，正在等我回复的那一单可能排在任何位置 ——
    /// 取第一条的表现是把别人那一单的视力情况印在这张卡上，而屏幕上完全看不出来。
    ///
    /// 已经有 supplement 的不覆盖：这条路径会被每一条新邀请触发一次，
    /// 而列表可能在两次之间少掉已被别人接走的单。
    static func merge(
        _ orders: [AvailableOrderResponse],
        into invites: [VolunteerInviteState]
    ) -> [VolunteerInviteState] {
        guard !orders.isEmpty else { return invites }
        let byID = Dictionary(orders.map { ($0.orderId, $0) }, uniquingKeysWith: { first, _ in first })
        return invites.map { invite in
            guard invite.supplement == nil, let match = byID[invite.id] else { return invite }
            var updated = invite
            updated.supplement = VolunteerInviteSupplement(match)
            return updated
        }
    }
}

// MARK: - 连续「去不了」的本地计数

/// 设计交付 v3 §4.4.3：「连续 3 次去不了后，下次打开接单主页询问『要不要调整空闲时间』，
/// **不做任何惩罚**」。
///
/// 🚩 **后端没有这个计数**（它自己那套「30 天内 3 次 → 暂停邀请 14 天」是另一回事，
/// 口径与触发后果都不同），所以只能本地计。
///
/// 重装 App 计数归零是**可接受**的：它触发的全部后果只有一句不带惩罚的询问，
/// 归零的代价是「少问一次」，不会误判任何人。反过来如果它带惩罚，本地存就不能用了。
struct VolunteerDeclineStreak {
    /// 设计交付 v3 §10「询问调整空闲时间 = 连续 3 次去不了」。
    static let threshold = 3
    private static let storageKey = "aidrun.volunteer.consecutiveDeclineCount"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var count: Int { defaults.integer(forKey: Self.storageKey) }

    var shouldAskAboutAvailability: Bool { count >= Self.threshold }

    /// **只在 `DECLINE` 真的发出去之后调**。5 秒撤销窗口内点了撤销的那次不算 ——
    /// 他并没有拒绝这一单。
    func recordDecline() {
        defaults.set(count + 1, forKey: Self.storageKey)
    }

    /// 接下任一单即清零；询问过一次也清零（问一次就够，反复问就成了惩罚）。
    func reset() {
        defaults.removeObject(forKey: Self.storageKey)
    }
}

// MARK: - 文案

/// 逐字取自《陪跑员端首页与接单 设计交付文档 v3》§4.4.2 / §4.4.3。
/// 与订单页共用的那几句（「接下这次陪跑」「这次去不了」「还剩 X 秒回复」）
/// **不在这里重写一遍**，直接用 `VolunteerOrderFlowCopy` —— 两份必然漂移。
enum VolunteerInviteCopy {
    /// 标题行**恒报数**，只有 1 条时也写「1 个新邀请」（项目负责人 2026-09-18 当面拍板）。
    ///
    /// HTML 稿单条那一屏写的是「新的陪跑邀请」，**不照它**：标题右边现在恒挂分页点，
    /// 一条时是一枚孤零零的长条，配「新的陪跑邀请」会让人以为还有别的没显示出来；
    /// 而「1 个新邀请」和那一枚点说的是同一件事。
    static func sheetTitle(count: Int) -> String {
        "\(max(1, count)) 个新邀请"
    }

    static let distanceToStartLabel = "离你"
    static let detail = "查看详情"

    // §4.4.3 「接下成功」
    static let acceptedTitle = "已约好"
    static let acceptedDetail = "跑者的全名和电话已放进订单"
    static let acceptedPrimary = "查看订单"
    static let acceptedSecondary = "回到接单"

    // §4.4.3 「接下失败：已过期」与「在卡片打开期间过期」是同一张卡
    static let expiredTitle = "这个邀请已失效"
    static let expiredDetail = "回复时间已过"
    static let expiredPrimary = "知道了"

    // §4.4.3 「这次去不了」的撤销 toast
    static let declineToastText = "已回复这次去不了"
    static let declineToastUndo = "撤销"

    // §4.4.3 连续 3 次去不了后的询问（接单主页）
    static let adjustAvailabilityTitle = "要不要调整空闲时间"
    static let adjustAvailabilitySubtitle = "最近几次邀请你都去不了。改一下空闲时间，可能更容易碰上合适的。"

    /// 接单主页上「收起之后回来」的那个入口。
    static func pendingInvitesTitle(count: Int) -> String {
        count > 1 ? "\(count) 个新邀请" : "1 个新邀请"
    }

    /// 同一个入口，但这几条是他陪跑期间静默攒下的（§4.4.1 最后一行逐字）。
    ///
    /// 换这句话的理由不是文风：静默暂存**在当时没有任何表现**（不推不震不弹），
    /// 所以回到接单主页看到几条邀请时，他唯一的解释只能是「我刚才漏了」。
    /// 这句话是那段静默的收据。
    static func pendingInvitesDuringRunTitle(count: Int) -> String {
        "陪跑时收到 \(max(1, count)) 个新邀请"
    }

    // §4.4.1「App 在前台，位于其他页面」那一行的顶部横幅
    static let bannerTitle = "新的陪跑邀请"
    static let bannerAction = "查看"
    /// 横幅停留时长（§10 规则参数表「横幅停留时间 4 秒」）。
    static let bannerDisplaySeconds: TimeInterval = 4
}
