import Foundation

// MARK: - 订单页 v7 的五步竖线（#917，定稿 `docs/ui/mockups/blind-order-tracking-20261109/` 第 5、11 条）
//
// 这一个文件是给两处用的：①–④ 的白底抽屉（#917）与 ⑤–⑧ 地图下面的抽屉（#918）。
// 所以它**只吃纯数据**（当前步 + 每步副标题 + 两个开关），不认识任何 ViewModel。
// 「哪些行要折」是纯函数 `BlindOrderTimelineLayout.rows`，视图只照它画；单测在 `BlindOrderTimelineTests`。

/// 竖线上的五步。名字在所有屏里相同（稿 v7：「匹配陪跑员 → 商量见面安排 → 等出发 → 在南门汇合 → 开跑」）。
///
/// ⚠️ 第四步稿里写「在南门汇合」，这里写「在集合点汇合」：「南门」是地址的短名，
/// 而地址是自由文本（`startAddress`），拆不出短名。完整地址在抽屉顶上那一行。
enum BlindOrderTimelineStep: Int, CaseIterable, Equatable, Hashable {
    case matchVolunteer = 0
    case arrangeMeetup
    case awaitDeparture
    case meetUp
    case startRun

    var title: String {
        switch self {
        case .matchVolunteer: return "匹配陪跑员"
        case .arrangeMeetup: return "商量见面安排"
        case .awaitDeparture: return "等出发"
        case .meetUp: return "在集合点汇合"
        case .startRun: return "开跑"
        }
    }

    /// 打勾之后那一行写什么。稿里只有第一步换了说法（「已匹配陪跑员」），其余照旧。
    var doneTitle: String {
        self == .matchVolunteer ? "已匹配陪跑员" : title
    }

    /// 已完成那一行的读屏。第一步的 `doneTitle` 自己就说了「已」，不再重复。
    var doneSpokenTitle: String {
        self == .matchVolunteer ? doneTitle : "\(title)，已完成"
    }
}

/// 竖线走到哪儿了：某一步正在进行，或五步都完成了（已完成页）。
enum BlindOrderTimelinePosition: Equatable {
    case current(BlindOrderTimelineStep)
    case allDone

    /// 当前步的下标；全部完成时等于步数（也就是「没有当前步」）。
    var currentIndex: Int {
        switch self {
        case .current(let step): return step.rawValue
        case .allDone: return BlindOrderTimelineStep.allCases.count
        }
    }
}

extension RunOrderStatus {
    /// 这一态落在竖线的哪一步。`nil` = 这一态不画竖线（已取消、暂无陪跑员、未知状态）。
    ///
    /// 穷举 switch，不写集合字面量：后端加状态时编译器会逼一次决策（同 `blindOrderFlowStep`）。
    /// 🔴 `.unknown` 不许落到「匹配陪跑员」：「我不认识这个状态」和「正在找人」是两件事。
    var blindOrderTimelinePosition: BlindOrderTimelinePosition? {
        switch self {
        case .pendingMatch, .rematching:
            return .current(.matchVolunteer)
        // 通话与确认安排单是同一步（v7 第 11 条 B）。
        case .pendingIntroCall:
            return .current(.arrangeMeetup)
        // 约好与陪跑员临期确认都还在「等出发」：对盲人这两态的事实都是「人定了，还没动身」。
        case .scheduledConfirmed, .pendingAccept:
            return .current(.awaitDeparture)
        // 陪跑员动身了，盲人这一步要做的是去集合点等；到了之后仍在这一步，直到按下开始。
        case .driverEnRoute, .driverArrived:
            return .current(.meetUp)
        case .inProgress:
            return .current(.startRun)
        case .completed:
            return .allDone
        case .cancelled, .noVolunteer, .unknown:
            return nil
        }
    }
}

/// 竖线的全部输入。**纯数据**，两个抽屉各自拼。
struct BlindOrderTimelineInput: Equatable {
    var position: BlindOrderTimelinePosition
    /// 每一步下面那行小字（「已等 3 分钟」「开跑前 1 小时会提醒你出门」）。没有就不画。
    var details: [BlindOrderTimelineStep: String] = [:]
    /// 当前步之后那一步要不要单独露一行「下一步 …」。③ 确认安排单那屏为 `false`
    /// （稿 v7 第 11 条 D：安排单五项首屏要完整可见，后面三步直接收成「还有 3 步」）。
    var showsNextStep = true
    /// `false` = 五步全部平铺不折叠（#918 抽屉拉到顶时用）。
    var folds = true
}

/// 竖线上的一行。
enum BlindOrderTimelineRow: Equatable, Identifiable {
    case done(BlindOrderTimelineStep, detail: String?)
    /// 「✓ 已完成 N 步 ›」。
    case doneFold([BlindOrderTimelineStep])
    case current(BlindOrderTimelineStep, detail: String?)
    /// 「下一步 …」。
    case next(BlindOrderTimelineStep)
    case todo(BlindOrderTimelineStep)
    /// 「还有 N 步 ›」。
    case todoFold([BlindOrderTimelineStep])

    var id: String {
        switch self {
        case .done(let step, _): return "done-\(step.rawValue)"
        case .doneFold: return "doneFold"
        case .current(let step, _): return "current-\(step.rawValue)"
        case .next(let step): return "next-\(step.rawValue)"
        case .todo(let step): return "todo-\(step.rawValue)"
        case .todoFold: return "todoFold"
        }
    }

    /// 这一行下面那段竖线是不是走过的颜色（深色）。只有已完成的行下面是深色。
    var isPast: Bool {
        switch self {
        case .done, .doneFold: return true
        default: return false
        }
    }
}

/// 折叠规则（稿 v7 第 11 条 A）。**只在这里写一次**，视图与单测都读它。
enum BlindOrderTimelineLayout {
    /// 几步起收成一行。1 步不收：收成「还有 1 步」比直接写出那一步还长。
    static let minimumFoldCount = 2

    static func rows(
        _ input: BlindOrderTimelineInput,
        pastExpanded: Bool = false,
        futureExpanded: Bool = false
    ) -> [BlindOrderTimelineRow] {
        let steps = BlindOrderTimelineStep.allCases
        let currentIndex = input.position.currentIndex
        var rows: [BlindOrderTimelineRow] = []

        let past = Array(steps.prefix(currentIndex))
        if input.folds, !pastExpanded, past.count >= minimumFoldCount {
            rows.append(.doneFold(past))
        } else {
            rows += past.map { .done($0, detail: input.details[$0]) }
        }

        guard case .current(let current) = input.position else { return rows }
        rows.append(.current(current, detail: input.details[current]))

        var future = Array(steps.dropFirst(currentIndex + 1))
        // 拉到顶（不折叠）时稿里不写「下一步」前缀（v7 C 帧），全部按未到的样子画。
        guard input.folds else {
            return rows + future.map { .todo($0) }
        }
        if input.showsNextStep, !future.isEmpty {
            rows.append(.next(future.removeFirst()))
        }
        if !futureExpanded, future.count >= minimumFoldCount {
            rows.append(.todoFold(future))
        } else {
            rows += future.map { .todo($0) }
        }
        return rows
    }

    /// 每一行的读屏。折叠行念出被收起来的每一步（稿原话「后面还有 3 步：等出发、在南门汇合、开跑」）。
    static func accessibilityLabel(for row: BlindOrderTimelineRow) -> String {
        switch row {
        case .done(let step, let detail):
            return [step.doneSpokenTitle, detail].compactMap { $0?.nilIfBlank }.joined(separator: "，")
        case .doneFold(let steps):
            return "已完成 \(steps.count) 步：\(steps.map(\.title).joined(separator: "、"))"
        case .current(let step, let detail):
            return ["\(step.title)，当前这一步", detail].compactMap { $0?.nilIfBlank }.joined(separator: "。")
        case .next(let step):
            return "下一步，\(step.title)"
        case .todo(let step):
            return "\(step.title)，还没到"
        case .todoFold(let steps):
            return "后面还有 \(steps.count) 步：\(steps.map(\.title).joined(separator: "、"))"
        }
    }

    /// 折叠行的可见文字。
    static func foldTitle(for row: BlindOrderTimelineRow) -> String? {
        switch row {
        case .doneFold(let steps): return "已完成 \(steps.count) 步"
        case .todoFold(let steps): return "还有 \(steps.count) 步"
        default: return nil
        }
    }

    static let foldAccessibilityHint = "点两下展开"
}
