import Foundation
import CoreLocation
import SwiftUI

// MARK: - Order Display Helpers

/// 以下每个 `case .unknown` 都对应「后端新增了本客户端不认识的订单状态」。
/// 一律走中性、只读、不下结论的分支：让订单继续留在列表里可被刷新，
/// 好过把它当成已结束而从界面上抹掉。
extension RunOrderStatus {
    var isActiveForBlindRunner: Bool {
        switch self {
        case .pendingMatch, .pendingAccept, .inProgress, .driverEnRoute, .driverArrived, .rematching:
            return true
        case .completed, .cancelled, .noVolunteer:
            return false
        case .unknown:
            return true
        }
    }

    var isActiveForVolunteer: Bool {
        switch self {
        case .pendingAccept, .driverEnRoute, .driverArrived, .inProgress:
            return true
        case .pendingMatch, .completed, .cancelled, .rematching, .noVolunteer:
            return false
        case .unknown:
            return true
        }
    }

    /// 志愿者能否看到盲人填的**自由文本**（`specialNotes` 特殊说明 / `routeNotes` 路线备注）。
    ///
    /// `AGENTS.md §8`：**接单前隐藏盲人的敏感健康信息。** 自由文本取值空间开放、敏感度无法预判，
    /// 语音下单落地后它装的就是用户原话（「我有低血糖，如果我说头晕请马上停下来」）。
    /// 派单是串行的，接单前展示等于把它交给这一单碰到过的每一个志愿者，包括最后拒单的那些。
    ///
    /// `routeNotes` 2026-08-07 一并收进来（后端已拍板同口径并在适配）。它的产品用途看着无害
    /// （「沿湖边跑道」），但字段类型决定风险、用途不决定：同一个输入框里写「我住院刚出来，
    /// 只能走平路」是完全自然的事，而客户端无法在展示前判断用户写了哪一种。
    ///
    /// 刻意写成穷举 switch 而不是 `!= .pendingMatch`，为的是两件事：
    /// - `.rematching` —— 原志愿者取消后订单回到重新派单，**那个人已经不是参与者了**，
    ///   简写的 `!=` 会把他判成可见。
    /// - `.unknown` —— 后端新增状态时必须**默认不公开**。这一族的其他 helper 对未知值取
    ///   「保守地当作进行中」，那是为了不让订单从界面上消失；隐私边界的保守方向相反，是关。
    ///
    /// `.pendingAccept` 判为可见，因为它已经在接单**之后**：盲人端该状态的文案是
    /// 「志愿者已接单」，且志愿者此时才拥有取消权（`AGENTS.md §5`）。
    /// 派单弹窗那一刻订单还是 `PENDING_MATCH`。
    ///
    /// 结构化条件（配速 / 路线偏好 / 导盲犬）**不走这条闸**：取值空间封闭（枚举 / 布尔），
    /// 且它们是志愿者判断「我接不接得下来」的依据，藏起来只会让人盲接、接了再取消。
    var disclosesBlindRunnerNotesToVolunteer: Bool {
        switch self {
        case .pendingAccept, .driverEnRoute, .driverArrived, .inProgress, .completed, .cancelled:
            return true
        case .pendingMatch, .rematching, .noVolunteer:
            return false
        case .unknown:
            return false
        }
    }

    /// 盲人端订单页该不该给出「打电话给志愿者」的主按钮。
    ///
    /// 陪跑没有车牌 / 车型 / 颜色，视障者确认「眼前这个人是不是我的志愿者」的唯一手段就是这通电话
    /// （依据见 `docs/research/blind-ui-visual-benchmark-20260808.md` §3.2）。所以凡是需要**当面汇合**
    /// 的状态都要给，且要给成主按钮而不是一行文字。
    ///
    /// 终态一律不给：订单结束后 `volunteerPhone` 可能还在响应里，但那时候摆一个占半屏的拨号按钮
    /// 是在诱导盲人打一通没有理由的电话。
    ///
    /// 写成穷举 switch 而不是集合字面量：后端往枚举加值时编译器会在这里逼一次决策，
    /// 而集合字面量会默默把新状态判成 false。
    var offersVolunteerCall: Bool {
        switch self {
        case .pendingAccept, .driverEnRoute, .driverArrived, .inProgress:
            return true
        // 还没有志愿者，或那个志愿者已经不是本单参与者（`REMATCHING` 是他取消后进入的状态）。
        case .pendingMatch, .rematching, .noVolunteer:
            return false
        case .completed, .cancelled:
            return false
        // 状态未知时落到只读跟踪页，不提供任何会产生外呼的动作。
        case .unknown:
            return false
        }
    }

    /// 盲人端订单页该不该给出「把这次行程告诉家人」。
    ///
    /// United In Stride 把**开始时间 / 集合地点 / 路线 / 结束时间**列为陪跑出发前必须约定的
    /// 四要素（`docs/research/blind-app-feature-landscape-20260812.md` §2.2）。在这条动作
    /// 存在之前，家属唯一会被触达的时机是 SOS 之后 —— 也就是说，跑步正常进行的全程，
    /// 家里人根本不知道这件事在发生。
    ///
    /// `PENDING_MATCH` 不给：还没人接单，此时能告诉家人的只有「我打算跑」，而订单可能
    /// 被自动取消，家属拿到的是一条会失效的信息。终态不给：没有进行中的行程可告知。
    ///
    /// 状态集**目前**与 `offersVolunteerCall` 完全相同，但两者是各自独立的产品判断，
    /// 不是同一件事：那条是「要不要当面确认志愿者身份」，这条是「行程要素齐没齐」。
    /// 合并成一个属性会让将来任一侧改状态集时静默带偏另一侧。
    ///
    /// 同样写成穷举 switch：后端往枚举加值时编译器在这里逼一次决策。
    var offersRunPlanShare: Bool {
        switch self {
        case .pendingAccept, .driverEnRoute, .driverArrived, .inProgress:
            return true
        case .pendingMatch, .rematching, .noVolunteer:
            return false
        case .completed, .cancelled:
            return false
        case .unknown:
            return false
        }
    }

    /// 等待期延长窗口该打哪个端点；`nil` 表示本状态没有这个动作。
    ///
    /// 后端在订单长时间无人接单时推 `ORDER_CANCELLATION_WARNING`，正文逐字是
    /// 「您的订单即将因长时间无人接单被取消，**点击继续等待可延长**」。在这条动作存在之前，
    /// 盲人听到那句话、屏幕上没有对应的控件，能做的只有等订单被自动取消再重下一单。
    ///
    /// 两个端点的前置状态**互斥**（后端 `OrderLifecycleService.keepWaiting` 只收 `PENDING_MATCH`，
    /// `keepRematching` 只收 `REMATCHING`，其余一律 409 `ORDER_STATUS_NOT_ALLOWED`）。
    /// 所以这里返回的是「**该打哪一个**」而不是「能不能打」——
    /// 判定与选路合成一处，`offersKeepWaiting` 为真却没有端点这种状态在结构上就不存在。
    ///
    /// 同 `offersVolunteerCall` 写成穷举 switch：后端加状态时编译器逼一次决策，
    /// 集合字面量会把新状态默默判成「没有这个动作」——那正是「点了没反应」的来源。
    var keepWaitingEndpoint: KeepWaitingEndpoint? {
        switch self {
        case .pendingMatch:
            return .keepWaiting
        case .rematching:
            return .keepRematching
        // 已经有志愿者了，等待窗口不再是这一单的问题。
        case .pendingAccept, .driverEnRoute, .driverArrived, .inProgress:
            return nil
        // `NO_VOLUNTEER` 是**终态**（后端 `OrderStatus.java:46`「预留终态」、
        // `DispatchService.java:574`），两个端点都会拒。可恢复的窗口在走到它**之前**。
        case .completed, .cancelled, .noVolunteer:
            return nil
        case .unknown:
            return nil
        }
    }

    /// 盲人端订单页该不该给出「继续等待」。派生自 `keepWaitingEndpoint`，不另写一遍 switch。
    var offersKeepWaiting: Bool {
        keepWaitingEndpoint != nil
    }
}

/// 两条延长端点。存在的理由是 `scripts/validate-spec-coverage.mjs`：
/// 它扫源码里的接口路径**字符串字面量**，逐条对撞后端契约。若把路径拼成
/// 「订单前缀 + 订单号 + **变量**后缀」，两段插值都会被归一成 `{param}`，
/// 得到一条契约里不存在的路径，于是这两个端点对门禁**彻底隐形** ——
/// 而门禁存在的全部意义就是拦住「前端在调后端没有的路径」。
///
/// 所以完整路径必须在这里写成字面量（连注释里也不能出现示例路径，同样会被扫到）。
/// 两个 case 的 switch 由编译器保证穷举，与上面那个按状态选路的 switch 不会各自漂移。
enum KeepWaitingEndpoint {
    case keepWaiting
    case keepRematching

    /// ⚠️ 这两条都是 `PUT`（`api_spec.yaml:236` / `:256`），
    /// 与其余走 `POST` 的订单状态流转端点不同族。
    func path(orderId: Int64) -> String {
        switch self {
        case .keepWaiting:
            return "/api/orders/\(orderId)/keep-waiting"
        case .keepRematching:
            return "/api/orders/\(orderId)/keep-rematching"
        }
    }
}

extension RunOrderStatus {

    /// 「志愿者离出发地点还有多远」这个数字对本状态有没有意义。
    ///
    /// 汇合前的三态才有：`IN_PROGRESS` 时两人已经在一起，念距离是噪音；派单中 / 重新匹配时
    /// 根本没有志愿者；终态更没有。语音查距离（`VoiceStatusQuery`）与状态页的距离刷新
    /// （`BlindOrderStatusViewModel.refreshVolunteerDistance`）共用这一处判定 ——
    /// 此前这个三元组在状态页里抄了两遍，再加语音入口就是第三遍。
    ///
    /// 同 `offersVolunteerCall` 写成穷举 switch：后端加状态时编译器逼一次决策。
    var offersVolunteerDistanceToStart: Bool {
        switch self {
        case .pendingAccept, .driverEnRoute, .driverArrived:
            return true
        case .pendingMatch, .rematching, .noVolunteer, .inProgress, .completed, .cancelled:
            return false
        case .unknown:
            return false
        }
    }

    var blindRunnerDescription: String {
        switch self {
        case .pendingMatch:
            return "系统正在派单，请稍候。"
        case .pendingAccept:
            return "志愿者已接单，请按预约时间前往或等待在出发地点。"
        case .inProgress:
            return "服务已开始，请注意安全。"
        case .driverEnRoute:
            return "志愿者已出发，正在前往出发地点。"
        case .driverArrived:
            return arrivedWaitingCopy
        case .completed:
            return "服务已完成，感谢使用助盲跑。"
        case .cancelled:
            return "本次预约已取消。"
        case .rematching:
            return "正在确认志愿者状态，请稍候；如需更换志愿者，系统会继续处理。"
        case .noVolunteer:
            return "暂时没有可用志愿者，请稍后重试。"
        case .unknown:
            return "订单状态有更新，请刷新页面或稍后重试。"
        }
    }

    var blindRunnerAnnouncement: String {
        switch self {
        case .pendingMatch:
            return "订单提交成功，系统正在为你派单。"
        case .pendingAccept:
            return "志愿者已接单，请前往或等待在预约出发地点。"
        case .inProgress:
            return "服务已开始，请注意安全。"
        case .driverEnRoute:
            return "志愿者已出发，正在前往出发地点。"
        case .driverArrived:
            return "志愿者已到达约定地点，等待志愿者开始服务。"
        case .completed:
            return "服务已完成，感谢使用助盲跑。"
        case .cancelled:
            return "本次预约已取消。"
        case .rematching:
            return "正在确认志愿者状态，请稍候。"
        case .noVolunteer:
            return "暂时没有可用志愿者。"
        case .unknown:
            return "订单状态有更新，请刷新页面或稍后重试。"
        }
    }

    var statusSymbolName: String {
        switch self {
        case .pendingMatch:
            return "clock.arrow.circlepath"
        case .pendingAccept:
            return "person.crop.circle.badge.questionmark"
        case .inProgress:
            return "checkmark.circle.fill"
        case .driverEnRoute:
            return "figure.walk.circle.fill"
        case .driverArrived:
            return "bell.circle.fill"
        case .completed:
            return "checkmark.seal.fill"
        case .cancelled:
            return "xmark.circle.fill"
        case .rematching:
            return "arrow.triangle.2.circlepath"
        case .noVolunteer:
            return "person.slash.fill"
        case .unknown:
            return "questionmark.circle"
        }
    }

    var statusColor: Color {
        switch self {
        case .pendingMatch, .pendingAccept, .rematching:
            return AppColors.warning
        case .inProgress, .driverEnRoute, .completed:
            return AppColors.success
        case .driverArrived:
            return AppColors.primary
        case .cancelled, .noVolunteer:
            return AppColors.textSecondary
        case .unknown:
            return AppColors.textSecondary
        }
    }
}

// MARK: - Keep Waiting Copy

/// 「继续等待」的全部对外文案。集中一处是为了让它们能被测试逐条钉住 ——
/// 这里每一句的措辞都有约束，散在 view 和 view model 里就只能靠人记。
enum KeepWaitingCopy {
    static let buttonTitle = "继续等待"
    static let accessibilityHint = "告诉系统你还想继续等，避免订单因为长时间没人接单被自动取消"

    /// 成功文案。两条硬约束：
    ///
    /// 1. **进行时，不是完成时。** 后端 200 只回 `{"success": true}`，订单状态不变
    ///    （`PENDING_MATCH` 还是 `PENDING_MATCH`），所以用户唯一的反馈就是这句话。
    /// 2. **不许出现具体时长。** 窗口长度是后端配置（`app.match.max-keep-waiting-count`
    ///    和对应的超时值），客户端读不到。写「已为你延长 10 分钟」就是编一个数字念给盲人听
    ///    —— 与 SOS 那条「不得宣称短信已送达」同一个道理。
    ///    `KeepWaitingCopyTests` 断言本串不含任何阿拉伯数字。
    static let success = "已经告诉系统继续等待，正在继续为你寻找志愿者。"

    /// 上限文案。后端在延长次数用尽后**不再推送** `ORDER_CANCELLATION_WARNING`
    /// （`websocket-protocol.md`：那时文案里的「点击继续等待可延长」已经不成立）。
    /// 客户端对齐同一口径：说清没得延长了，并说明**还能做什么** —— 只说「不能延长」
    /// 会把盲人留在一个没有下一步的地方。
    static let limitReached = "已经到了可以延长的次数上限，不能再延长了。系统还会继续为你匹配；如果不想再等，可以取消订单后重新预约。"

    /// 「重复当前状态」里附带的一句。看不见屏幕的人靠这句发现这个动作存在。
    static let repeatStatusSuffix = "如果还想继续等，可以点继续等待。"
}

// MARK: - Order Detail Helpers

extension OrderDetailResponse {
    var sortKey: String {
        createdAt ?? plannedStart ?? ""
    }

    var startCoordinate: CLLocationCoordinate2D? {
        guard let startLatitude, let startLongitude else { return nil }
        return CLLocationCoordinate2D(latitude: startLatitude, longitude: startLongitude)
    }

    var startAddressForAnnouncement: String {
        startAddress?.nilIfBlank ?? "预约出发地点"
    }

    /// 「结束地点」那一行要显示的文字；`nil` 表示**整行不渲染**。
    ///
    /// 没有终点时返回 `nil` 而不是「未指定」之类的占位：`endAddress == nil` 的语义是
    /// 「用户没说终点」，**不是**「原路返回起点」。摆一行出来，志愿者就会去跟盲人核对
    /// 一个对方从没说过的地点（后端 `websocket-protocol.md:429` 同一条口径）。
    ///
    /// 查不到坐标时把这件事说出来，是因为它改变志愿者的动作：没有坐标就没法导航，
    /// 只能当面问。不标注的话，那一行看起来和有坐标的完全一样。
    var endAddressForDisplay: String? {
        guard let address = endAddress?.nilIfBlank else { return nil }
        return endLatitude == nil ? "\(address)（未定位到）" : address
    }

    var plannedStartForAnnouncement: String? {
        plannedStart?.nilIfBlank?.displayDateTime
    }

    func volunteerDistanceToStartText(from volunteerCoordinate: CLLocationCoordinate2D?) -> String? {
        guard let volunteerCoordinate, let startCoordinate else { return nil }
        let meters = DistanceCalculator.distance(from: volunteerCoordinate, to: startCoordinate)
        return "距出发地点约 \(DistanceCalculator.formattedDistance(meters))"
    }

    func blindRunnerAnnouncement(distanceText: String? = nil) -> String {
        let distanceSentence = distanceText.map { "志愿者\($0)。" } ?? ""
        switch status {
        case .pendingAccept:
            if let plannedStartForAnnouncement {
                return "志愿者已接单。请在\(plannedStartForAnnouncement)前往或等待在出发地点：\(startAddressForAnnouncement)。\(distanceSentence)志愿者出发后会继续通知你。"
            }
            return "志愿者已接单。请前往或等待在出发地点：\(startAddressForAnnouncement)。\(distanceSentence)志愿者出发后会继续通知你。"
        case .driverEnRoute:
            if let distanceText {
                return "志愿者已出发，正在前往出发地点，\(distanceText)。"
            }
            return "志愿者已出发，正在前往出发地点。"
        case .driverArrived:
            return "\(status.blindRunnerAnnouncement)\(distanceSentence)"
        default:
            return status.blindRunnerAnnouncement
        }
    }
}

// MARK: - String Helpers

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var nilIfBlank: String? {
        let value = trimmed
        return value.isEmpty ? nil : value
    }

    /// 后端 `LocalDateTime` 的无时区时间串（`2026-08-04T11:40:42`），**可能带小数秒**
    /// （`2026-08-04T11:40:42.644571`）。凡是取自 `now()` 且没经过 DB round-trip 的字段都会带 ——
    /// 下单回执的 `createdAt` 一定带，`acceptedAt` / `recordedAt` / `triggeredAt` 同理
    /// （handoff 2026-08-04 后端实测）。
    ///
    /// 小数位数不固定（尾零被丢弃），所以不另配一个 `.SSSSSS` 格式器，直接截掉小数部分 ——
    /// 秒以下精度对展示和预约时间都没有意义。**但带时区偏移的串不能这么截**
    /// （`...42.644+08:00` 截完会差好几个小时），所以要求小数点后必须全是数字，
    /// 带偏移的交给调用方的 ISO8601 分支。
    var backendLocalDate: Date? {
        let formatter = DateFormatter.aidRunBackendLocalDateTime
        if let date = formatter.date(from: self) { return date }
        let parts = split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[1].isEmpty, parts[1].allSatisfy(\.isNumber) else { return nil }
        return formatter.date(from: String(parts[0]))
    }

    var displayDateTime: String {
        if let date = backendLocalDate {
            return DateFormatter.aidRunDisplayDateTime.string(from: date)
        }
        if let date = ISO8601DateFormatter.aidRunFormatter.date(from: self) {
            return DateFormatter.aidRunDisplayDateTime.string(from: date)
        }
        if let date = ISO8601DateFormatter().date(from: self) {
            return DateFormatter.aidRunDisplayDateTime.string(from: date)
        }
        return self
    }
}

extension ISO8601DateFormatter {
    static let aidRunFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

extension DateFormatter {
    static let aidRunBackendLocalDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()

    static let aidRunDisplayDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日 HH:mm"
        return formatter
    }()
}
