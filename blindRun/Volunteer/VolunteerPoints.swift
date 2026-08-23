import Foundation

// MARK: - Contract

/// `GET /api/volunteer/points` 的响应（SPEC-E 第 1 步）。
///
/// 全部字段可选，与 `VolunteerAchievementsResponse` 同一套解码习惯：缺一个字段该少显示一行，
/// 而不是整页空白。
///
/// 🔴 **积分与「志愿服务时长」是两套完全独立的数**（时长在 `GET /api/volunteer/achievements`
/// 的 `totalServiceMinutes`）。文案里不得互相换算、不得写成「攒积分可折算志愿服务时长」——
/// 依据是中央网信办 2026-06-19《关于开展网络平台涉志愿服务违规信息专项整治的通知》第 2 条，
/// 它点名整治「宣传可以获得志愿服务时长」。这不是措辞偏好，是合规红线。
///
/// 两个数刻意分两屏（积分页 / 服务成就页），而不是并排放在一屏上 ——
/// 信息架构层就隔开，比靠文案自律可靠。
struct VolunteerPointsResponse: Decodable, Sendable, Equatable {
    let balance: Int64?
    let transactions: [PointTransactionResponse]?
    let page: Int?
    let size: Int?
    let totalElements: Int64?
    let totalPages: Int?

    var resolvedBalance: Int64 { balance ?? 0 }

    /// 🔴 **不做任何过滤。** 尤其不能按 `delta != 0` 过滤 —— 见 `PointTransactionResponse.delta`。
    var resolvedTransactions: [PointTransactionResponse] { transactions ?? [] }

    var hasMorePages: Bool {
        guard let page, let totalPages else { return false }
        return page + 1 < totalPages
    }
}

/// 一条积分流水。
struct PointTransactionResponse: Decodable, Sendable, Equatable {
    let id: Int64?

    /// 可正可负。
    ///
    /// 🔴 **`0` 是合法值，绝不能当脏数据过滤掉。** 它表示「这一单撞了防刷上限、没有加分」，
    /// `note` 里写着人话原因（例：「已达同一对每周上限 30 分，本单不加分」）。
    /// 过滤掉它，用户看到的就是「跑完了、订单也完成了、积分没动、界面上什么都没有」——
    /// 而那正是这套设计从头到尾要避免的静默错误。
    let delta: Int?

    /// 🔴 **开放枚举，收成 `String` 而不是 Swift `enum`。**
    ///
    /// 契约里是 `anyOf: [{enum: [...]}, {type: string}]`，那个 `- type: string` 分支是逃生口。
    /// 产成封闭枚举的话，后端下次加一个取值会让**整条响应**解不出来 ——
    /// 对盲人端就是一整页空白（AGENTS.md 硬约束，见 commit `4793805`）。
    /// 本轮后端已经加过一次（`INVITE_REWARD`），下次还会加。
    let reason: String?

    let orderId: Int64?

    /// 人读的原因。正常发分时为 `nil`；撞上限或冲正时有值。
    /// 契约 description 逐字：「可直接展示给用户」——不需要我们再组织文案。
    let note: String?

    let createdAt: String?

    var resolvedDelta: Int { delta ?? 0 }
}

// MARK: - 展示

extension PointTransactionResponse {
    /// `+10 分` / `0 分` / `-10 分`。
    ///
    /// 0 不写成 `+0`：那读起来像加了分。也不写成 `--`：屏幕上的占位符号从来不是给耳朵用的
    /// （本仓库栽过一次，评分为空时读屏念出「评分：破折号破折号」）。
    var deltaText: String {
        let value = resolvedDelta
        if value > 0 { return "+\(value) 分" }
        return "\(value) 分"
    }

    /// 加分 / 未加分 / 扣分。**图标与文字共同区分，颜色不是唯一指示**（WCAG 1.4.1）。
    enum Kind {
        case credited
        case noChange
        case deducted
    }

    var kind: Kind {
        let value = resolvedDelta
        if value > 0 { return .credited }
        if value < 0 { return .deducted }
        return .noChange
    }

    /// 未知 `reason` 落到「其他」，**不是**报错、也不是显示原始英文枚举值。
    var reasonText: String {
        switch reason {
        case "ORDER_COMPLETED": return "完成陪跑服务"
        case "ORDER_AUTO_COMPLETED": return "服务超时自动完成"
        case "INVITE_REWARD": return "邀请奖励"
        case "REVERSAL": return "人工冲正"
        default: return "其他"
        }
    }

    /// 一行流水念出来的完整句子：日期 + 加了多少 + 为什么。
    ///
    /// `note` 非空时**用 `note` 取代** `reasonText`，不是拼在后面 —— 撞上限那条
    /// `note` 已经把话说全了（「已达同一对每周上限 30 分，本单不加分」），
    /// 再念一遍「完成陪跑服务」是自相矛盾。
    var accessibilityLabel: String {
        let day = createdAt?.nilIfBlank?.displayDateTime ?? "时间未知"
        let spokenDelta = resolvedDelta > 0
            ? "加 \(resolvedDelta) 分"
            : (resolvedDelta < 0 ? "扣 \(-resolvedDelta) 分" : "加 0 分")
        return "\(day)，\(spokenDelta)，\(note?.nilIfBlank ?? reasonText)"
    }
}

// MARK: - 按日期分组

/// 积分明细按天分组展示（抄各家积分明细页的通行做法：同一天的流水收在一个日期小标题下）。
///
/// 分组只是**视觉分节**，不改变顺序也不合并条目 —— 后端按 `createdAt` 倒序返回，
/// 这里保持原序，只在「天」变化处插一个标题。读屏因此听到的是
/// 「8 月 22 日，标题」→ 当天各条，与视觉顺序一致。
struct PointTransactionDay: Equatable {
    let title: String
    let transactions: [PointTransactionResponse]
}

enum PointTransactionGrouping {
    /// ⚠️ 时间解析不出来时归到「更早」而不是丢弃 —— 丢一条流水就是丢一次解释。
    static let unknownDayTitle = "更早"

    static func group(_ transactions: [PointTransactionResponse]) -> [PointTransactionDay] {
        var days: [PointTransactionDay] = []
        for transaction in transactions {
            let title = dayTitle(for: transaction)
            if let last = days.last, last.title == title {
                days[days.count - 1] = PointTransactionDay(
                    title: title,
                    transactions: last.transactions + [transaction]
                )
            } else {
                days.append(PointTransactionDay(title: title, transactions: [transaction]))
            }
        }
        return days
    }

    private static func dayTitle(for transaction: PointTransactionResponse) -> String {
        guard let date = transaction.createdAt?.nilIfBlank?.backendTimestamp else {
            return unknownDayTitle
        }
        return DateFormatter.aidRunDisplayDay.string(from: date)
    }
}

// MARK: - 文案

/// 积分页文案。
///
/// 🔴 三条合规红线逐字锁在这里，改动前先读 `docs/research/incentive-ui-blind-first-20260823.md`：
///
/// 1. **不得把积分与志愿服务时长混着说**，不得互相换算。
/// 2. **不得出现「可兑换」「转赠」「提现」「兑换现金」的暗示。** 目前只累计不消耗。
/// 3. **不得使用「最美志愿者」及同类官方评选称号**（中宣部/民政部/团中央「四个 100」）。
///
/// 第 2 条同时受守卫 `placeholder-promise` 约束（拦「敬请期待 / 即将上线」这类会兑现的暗示），
/// 所以这里写的是「开发中」而不是「敬请期待」。
enum VolunteerPointsCopy {
    static let navigationTitle = "我的积分"

    static let balanceCaption = "当前积分"

    /// 抄蚂蚁森林《用户使用须知》的做法：把「不可转让」写进用户看得见的文案，
    /// 而不是只留在法务文档里（「森林中的绿色能量无法转让或继承」）。
    static let disclaimer = "积分不能提现、不能转让、不能兑换现金。积分商城开发中。"

    /// 🔴 这一句是把两套数隔开的那道栏杆，不要删、也不要改成「积分可折算时长」。
    static let separateFromServiceHours = "积分和志愿服务时长是两回事。累计服务时长在「服务成就」页查看。"

    static let ledgerSectionTitle = "积分明细"

    static let empty = "还没有积分记录。完成一次陪跑服务后，这里会显示每一笔的加分和原因。"

    /// ⚠️ **不是**「功能未开启」。后端 `PointService` 只有数值参数、没有 enabled 开关，
    /// 积分从第一天就在记（SPEC-E §1 决策 1）。带开关的是火花 / 派单优先轮 / 邀请奖励三个。
    static let loadFailure = "暂时没能读到积分，请稍后重试。"

    static let retry = "重新加载"

    static func balanceAccessibilityLabel(_ balance: Int64) -> String {
        "\(balanceCaption) \(balance) 分"
    }
}
