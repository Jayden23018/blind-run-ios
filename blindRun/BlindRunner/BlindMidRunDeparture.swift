import Foundation

// 陪跑员在同行三态（出发 / 汇合 / 跑步中）退出后，跑者这一侧说什么（#653）。

/// 这一刻跑者身边很可能已经没有人了，所以三句都先说事实和该做的事。
///
/// 🚨 **不说「正在确认陪跑员状态」**：陪跑员已经退出，没有什么可确认的，这句话会让人继续等他回来。
/// 也不说原因：转到这一态的可能是陪跑员自己取消，也可能是后端判他失联（`ORDER_VOLUNTEER_LOST`）。
enum BlindMidRunDepartureCopy {
    static let title = "陪跑员已退出"
    static let description = "现在只有你一个人。请先停下来，走到安全的地方等候。系统正在重新匹配陪跑员。"
    static let announcement = "\(title)。\(description)"
}

/// 这台手机上，最近一张进过同行三态的订单。
///
/// **客户端只能自己记**：契约里 `REMATCHING` 的订单详情分不出陪跑员是出发前还是出发后退出的
/// （`run` 只在 `IN_PROGRESS` 非空，模板通知也不一定带 `orderId`）。
/// 存盘是因为 App 被杀后重新打开时，内存里已经没有上一个状态了。只存订单号，不存任何个人信息。
///
/// 陪跑员端也走同一个入口写，但只有跑者页面读，所以不分角色。
///
/// ponytail: 客户端记的事实会过期，两个方向都可能错。① 漏报：手机从没见过同行态，退回通用句。
/// ② 误报：手机在后台时错过了换人，新陪跑员又在出发前退出，而普通 `REMATCHING` 通知也没收到，
/// 跑者会听到一次「只有你一个人」。两者都要后端在订单详情里给这个事实才能根除。
final class BlindMidRunDepartureRecord {
    static let defaultsKey = "blindRun.midRunDeparture.accompaniedOrderID"

    /// 单测进程里 `defaults` 为 `nil`，什么都不记：跑者订单页的用例不该往真实偏好里写订单号，
    /// 也不该让上一条用例的订单号改变下一条用例的文案。要测的用例自己换掉这个实例。
    nonisolated(unsafe) static var shared = BlindMidRunDepartureRecord(
        defaults: ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil ? .standard : nil
    )

    private let defaults: UserDefaults?
    /// 收到过 `REMATCHING_MID_RUN`、而页面还没念状态句的单。只放内存：它只管这一次别念重。
    private var alertedOrderIDs: Set<Int64> = []

    init(defaults: UserDefaults?) {
        self.defaults = defaults
    }

    private var accompaniedOrderID: Int64? {
        (defaults?.object(forKey: Self.defaultsKey) as? NSNumber)?.int64Value
    }

    /// 每次拿到订单的新状态都调一次。离开重新匹配（又接上了人）或订单结束时清掉：
    /// 下一次从 `PENDING_ACCEPT` 退回 `REMATCHING` 时跑者还没出门，不算半路退出。
    ///
    /// 🚨 `PENDING_INTRO_CALL` 也清，刻意的：通话没聊成回到 `REMATCHING` 时若显示「陪跑员已退出」，
    /// 跑者会以为是刚通话的候选人拒绝了他，而「无声拒绝」要求他无从得知这件事。
    func observe(orderID: Int64, status: RunOrderStatus) {
        if status != .rematching { alertedOrderIDs.remove(orderID) }
        if status.runsLiveEscortSession {
            recordDeparture(orderID: orderID)
        } else if status != .rematching, status != .unknown {
            clearDeparture(orderID: orderID)
        }
    }

    /// 收到通知时调，`orderID` 认不出是哪一单时传 `nil`。
    ///
    /// - `REMATCHING_MID_RUN`：手机可能在后台时错过了同行三态，所以这里也记下订单号。
    /// - `REMATCHING`：后端只在陪跑员**出发前**退出时发它，收到就说明这次不算半路退出。
    func note(eventType: String, orderID: Int64?) {
        guard let orderID else { return }
        switch eventType {
        case "REMATCHING_MID_RUN":
            recordDeparture(orderID: orderID)
            alertedOrderIDs.insert(orderID)
        case "REMATCHING":
            clearDeparture(orderID: orderID)
        default:
            break
        }
    }

    /// 这一单的半路退出警示是否已经交给横幅播报。只回答一次：陪跑员换人后再次退出时，
    /// 这里若还留着旧记录，而那次警示又没送达，页面就会误判「已经念过」而保持沉默。
    func consumeAlert(orderID: Int64) -> Bool {
        alertedOrderIDs.remove(orderID) != nil
    }

    private func recordDeparture(orderID: Int64) {
        defaults?.set(NSNumber(value: orderID), forKey: Self.defaultsKey)
    }

    private func clearDeparture(orderID: Int64) {
        guard accompaniedOrderID == orderID else { return }
        defaults?.removeObject(forKey: Self.defaultsKey)
    }

    func volunteerLeftMidRun(orderID: Int64, status: RunOrderStatus) -> Bool {
        status == .rematching && accompaniedOrderID == orderID
    }
}

extension OrderDetailResponse {
    /// 这一单正在重新匹配，而且陪跑员是在同行三态里退出的。
    var blindRunnerLeftAloneMidRun: Bool {
        BlindMidRunDepartureRecord.shared.volunteerLeftMidRun(orderID: orderId, status: status)
    }

    // 以下几条是跑者各处文案的唯一分支点（#653）：状态变化、「重复当前状态」都走 `blindRunnerAnnouncement`。

    var blindRunnerAnnouncementUnlessLeftAlone: String {
        blindRunnerLeftAloneMidRun ? BlindMidRunDepartureCopy.announcement : status.blindRunnerAnnouncement
    }

    var blindRunnerDescriptionUnlessLeftAlone: String {
        blindRunnerLeftAloneMidRun ? BlindMidRunDepartureCopy.description : status.blindRunnerDescription
    }

    var blindRunnerRematchingTitle: String {
        blindRunnerLeftAloneMidRun ? BlindMidRunDepartureCopy.title : "正在重新匹配陪跑员"
    }

    /// 语音问「现在什么状态」的答句。
    var blindRunnerStatusAnswer: String {
        blindRunnerLeftAloneMidRun
            ? BlindMidRunDepartureCopy.announcement
            : "\(status.displayName)。\(status.blindRunnerDescription)"
    }
}

extension VoiceService {
    /// 跑者两个页面的状态播报入口。半路退出走警示档，其余与 `speakStatusChange` 相同。
    ///
    /// 后端先发 `REMATCHING_MID_RUN`、再发状态变化（`OrderLifecycleService` 里的先后），所以常见路径上
    /// 这一刻横幅那条警示正在念。已经收到过那条就只记去重键，否则同一件事会连念两遍。
    /// **没收到时必须自己念**：WebSocket 断着时，轮询是唯一知道这件事的通道。
    @discardableResult
    func speakBlindRunnerStatusChange(_ order: OrderDetailResponse, text: String) -> Bool {
        guard order.blindRunnerLeftAloneMidRun else {
            return speakStatusChange(order.status, text: text)
        }
        guard order.status != lastSpokenStatus else { return false }
        if BlindMidRunDepartureRecord.shared.consumeAlert(orderID: order.orderId) {
            markStatusAnnounced(order.status)
            return false
        }
        return speakStatusChange(order.status, text: text, priority: .alert)
    }
}
