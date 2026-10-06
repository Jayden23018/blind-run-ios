import Foundation

// MARK: - 盲人端订单页 v2 的头卡（#349）

/// 盲人端订单页跑步前四屏 + 倒计时那一张头卡要画的全部东西。视图只按它渲染。
///
/// 2026-10-06 项目负责人要求盲人端订单页改用陪跑员 v2 的版式（`VolunteerOrderFlowPage`）。
/// 与陪跑员端 `VolunteerOrderHero` 对称，但**不新造判定**：标题、副标题、警示全部取自
/// `BlindOrderFlowPresentation`（那边的每条文案都记着不许说的东西，50 多条用例钉着），
/// 这里只决定「哪句放在小标题、哪句放大字、绳子画到哪一格」。
///
/// 两条刻意的不同：
/// - **浅色头卡**（负责人 10-06）。陪跑员端的彩色状态底不搬过来。
/// - **出发屏没有「N 分钟后到」**：后端只给本单陪跑员下发 `eta`
///   （`OrderDetailAssembler.java:317-318`，`isEscortedBy(order, viewerId)`），盲人 token 恒为 null。
struct BlindOrderHero: Equatable {
    /// 小标题。「已约好 · 明天早上」「今天早上 6:35 开跑」。
    var eyebrow: String
    /// 大字数字。「6:35」，倒计时那三秒是「3」「2」「1」。`nil` = 用 `headline` 当主角。
    var number: String?
    /// 数字后的单位「开跑」。
    var unit: String?
    var headline: String?
    /// 副文，每行一句。来自 `presentation.subtitle` 按换行切开。
    var lines: [String] = []
    /// 红字警示（定位信号弱等）。只在异常时有。
    var warning: String?
    var rope: RopeState
    /// 倒计时那一拍。非 nil 时视图给大数字加回弹，读屏标签**不念这个数** ——
    /// 三个数字走 announcement 通道播报（`BlindOrderStatusViewModel.startRunCountdown`），
    /// 再进标签就是每秒换一次焦点元素的内容。
    var countdownBeat: Int?

    /// 头卡正文合成一个读屏元素（绳子另算一个）。
    var accessibilityLabel: String {
        // 小标题里的「 · 」只给眼睛看，读屏换成停顿（同 `FlowRunnerCard` 的 detail）。
        var parts = [eyebrow.replacingOccurrences(of: " · ", with: "，")]
        if countdownBeat == nil, let number { parts.append([number, unit].compactMap { $0 }.joined()) }
        if let headline { parts.append(headline) }
        parts.append(contentsOf: lines)
        if let warning { parts.append(warning) }
        return parts.filter { !$0.isEmpty }.joined(separator: "，")
    }

    /// `nil` = 这一幕不画头卡（跑步中 / 已完成：那两幕是原地变形后的三个数字）。
    static func make(
        presentation: BlindOrderFlowPresentation,
        order: OrderDetailResponse,
        now: Date = Date()
    ) -> Self? {
        let lines = presentation.subtitle
            .split(separator: "\n")
            .map { String($0) }
            .filter { !$0.isEmpty }
        let start = order.plannedStart?.backendTimestamp

        switch presentation.phase {
        case .running, .finished:
            return nil
        case .countdown(let beat):
            return Self(
                eyebrow: startEyebrow(start, now: now) ?? "已汇合",
                number: "\(beat)",
                headline: presentation.title,
                lines: lines,
                warning: presentation.warning,
                rope: .arrived,
                countdownBeat: beat
            )
        case .beforeRun:
            break
        }

        switch presentation.step {
        case .booked:
            // 与陪跑员端「约好」同一个样子：开跑时刻当主角数字。
            // 拿不到时间就退回 presentation 的标题（状态名），**不摆占位时间**。
            guard let start else {
                return Self(eyebrow: "已约好", headline: presentation.title, lines: lines,
                            warning: presentation.warning, rope: .agreed)
            }
            return Self(
                eyebrow: "已约好 · " + VolunteerOrderTimeCopy.dayPart(start, now: now),
                number: VolunteerOrderTimeCopy.clock(start),
                unit: "开跑",
                lines: lines,
                warning: presentation.warning,
                rope: .agreed
            )
        case .matching:
            return Self(eyebrow: startEyebrow(start, now: now) ?? "匹配中", headline: presentation.title,
                        lines: lines, warning: presentation.warning, rope: .invited)
        case .departed:
            // 进度固定一段，**不是算出来的**：盲人 token 拿不到 `eta.progress`。
            // 与 v1 那道固定 0.35 的进度环同一个意思 —— 表达「在路上」，不表达「走了多少」。
            return Self(eyebrow: startEyebrow(start, now: now) ?? "正在赶来", headline: presentation.title,
                        lines: lines, warning: presentation.warning, rope: .departed(progress: departedRopeProgress))
        case .metUp:
            return Self(eyebrow: startEyebrow(start, now: now) ?? "已汇合", headline: presentation.title,
                        lines: lines, warning: presentation.warning, rope: .arrived)
        }
    }

    /// 出发态绳子上陪跑员头像停的位置。见 `make` 里出发那一支。
    static let departedRopeProgress = 0.35

    /// 「今天早上 6:35 开跑」。除「约好」外的三格都用它当小标题：
    /// 大字已经在说「正在匹配 / 正在赶来 / 已到达」，几点开跑是这一屏唯一还没上头卡的事实。
    private static func startEyebrow(_ start: Date?, now: Date) -> String? {
        guard let start else { return nil }
        return "\(VolunteerOrderTimeCopy.dayPart(start, now: now)) \(VolunteerOrderTimeCopy.clock(start)) 开跑"
    }
}
