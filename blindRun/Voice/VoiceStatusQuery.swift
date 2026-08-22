import CoreLocation
import Foundation

// MARK: - Voice Status Intent

/// 盲人端「问一句」能问的四件事，外加两个必须与它们分开的结果。
///
/// 意图判定**全部在本地做**，不发任何网络请求。四个意图就是四张关键词表，本地表在这件事上
/// 不比大模型差，还多三个性质：断网可用、零延迟、不新增契约。
///
/// ⚠️ **2026-08-18 更正：原来这里写着「后端 `/api/orders/voice/parse` 在生产上恒 404」，
/// 那条已经不成立了，别再拿它当「本地判定」的依据。** 生产实测：`GET /v3/api-docs`（经 80 端口
/// Nginx，200）里列着 `POST /api/orders/voice/parse`，且对该路径发无鉴权请求收到的是
/// **后端自己的** `{"code":401,"message":"未认证","success":false}` —— 说明请求确实被代理到了
/// Spring Boot 并由它处理，不是 404。（注意 401 这一条本身区分不了路径存不存在：
/// Security 过滤器排在 handler mapping 之前，随便编一个路径也返同样的 401。定论靠的是 api-docs。）
///
/// 本地判定这个选择**依然是对的**，只是理由要换成上面那三条（断网可用、零延迟、不新增契约），
/// 而不是「后端那条路根本不通」。
enum VoiceStatusIntent: Equatable {
    /// 志愿者离出发地点还有多远。只念直线距离，**不做 ETA / 路线规划**。
    case distance
    /// 订单当前在哪一步。
    case status
    /// 什么时候、在哪儿。
    case schedule
    /// 打电话给志愿者。必须复述号码 + 等一次语音确认才拨。
    case callVolunteer
    /// 识别到破坏性词汇（取消 / 退单），必须显式拒绝而不是落进 `unrecognized` 的整段兜底。
    ///
    /// ASR 会把「不取消」听成「取消」，而订单取消不可逆 —— 所以语音路径一条都不代做，
    /// 一律指回屏幕上的按钮。
    case blockedDestructive
    case unrecognized
}

// MARK: - Voice Status Answer

struct VoiceStatusAnswer: Equatable {
    let speech: String
    /// 非 nil 时表示这次回答后还要做一件事（本期只有拨号，且必须先确认）。
    let pendingAction: PendingAction?

    enum PendingAction: Equatable {
        case confirmDialVolunteer(phone: String)
    }
}

// MARK: - Voice Status Query

/// 「问一句」的纯逻辑：一句原话进来，一段要念的话出去。
///
/// 刻意不依赖 UIKit / SwiftUI / 网络：本仓库的 XCTest 只能真机跑，把判定写进 view model
/// 就得先构造 `AppState` + 硬件服务才能测一句关键词匹配。录音、播报、拨号在
/// `VoiceStatusQuerySession` 里。
enum VoiceStatusQuery {

    /// 兜底时追加的那句。单独暴露，测试里对得上字面量。
    static let askableHint = "你还可以问：志愿者还有多远、几点开始、打电话给志愿者。"

    /// 复述号码后用户没确认时念的那句。**必须说出「没有拨号」这件事** ——
    /// 静默返回等于让盲人不知道刚才那一轮到底发生了什么。
    static let dialCancelledSpeech = "已取消拨号。"

    // MARK: Classification

    /// 判定顺序有意义，别调换：
    /// 1. 破坏性词汇先判 —— 「打电话取消订单」必须落到拒绝，不能落到拨号。
    /// 2. 拨号次之 —— 它是唯一会产生外部动作的意图，宁可多问一次确认。
    /// 3. `status` 排在 `distance` 前面 —— 「到哪一步」比「到哪」更具体，反过来会被吃掉。
    /// 4. `schedule` 垫底 —— 它的词最泛（「什么时候」「在哪」），放前面会抢走「什么时候到」。
    static func classify(_ transcript: String) -> VoiceStatusIntent {
        let normalized = VoiceOrderWizard.normalizedCommand(transcript)
        guard !normalized.isEmpty else { return .unrecognized }
        if destructiveWords.contains(where: normalized.contains) { return .blockedDestructive }
        if callWords.contains(where: normalized.contains) { return .callVolunteer }
        if statusWords.contains(where: normalized.contains) { return .status }
        if distanceWords.contains(where: normalized.contains) { return .distance }
        if scheduleWords.contains(where: normalized.contains) { return .schedule }
        return .unrecognized
    }

    /// 判定用户是否用语音确认了拨号。
    ///
    /// 复用 `VoiceOrderWizard.isAffirmative` 的同一套整串白名单，**不另写一套「是 / 对 / 好」的表**：
    /// 那几个字是中文日常应答里频率最高的，而陪跑场景里志愿者可能就站在旁边说话。
    /// 复述那句教用户说的也是「确认」，白名单必须和系统教的话一致。
    static func isDialConfirmed(_ transcript: String) -> Bool {
        VoiceOrderWizard.isAffirmative(transcript)
    }

    /// 这一轮的识别结果该不该拿去回答。
    ///
    /// **空识别不回答。** 那一轮用户根本没说话（没听见起音提示、还在想、提示音被静音拨杆关掉），
    /// 把它当成「没听懂」去念整段状态，等于拿一段 15~25 秒的播报回答一次没说出口的提问 ——
    /// 而且会盖掉 `SpeechInputService` 自己那句「未检测到声音，已停止语音输入」，
    /// 那是用户判断「麦克风到底开没开」的唯一线索。
    static func shouldAnswer(_ completion: SpeechInputCompletion) -> Bool {
        completion.reason.shouldTriggerSearchWithRecognizedText
            && !completion.recognizedText.trimmed.isEmpty
    }

    // MARK: Answering

    /// - Parameter volunteerCoordinate: **已判过新鲜度**的志愿者坐标；过期或没有一律传 nil。
    ///   这里不判新鲜度是因为两个调用页拿坐标的路子不同（状态页有过期清理任务，首页只有缓存），
    ///   而念一个几分钟前的距离对听不见屏幕的人就是假数据。
    /// - Parameter fallbackAnnouncement: 兜底整段，调用方传 `order.blindRunnerAnnouncement(distanceText:)`。
    static func answer(
        intent: VoiceStatusIntent,
        order: OrderDetailResponse?,
        volunteerCoordinate: CLLocationCoordinate2D?,
        fallbackAnnouncement: String
    ) -> VoiceStatusAnswer {
        // 没有进行中的订单时，四个意图一个都答不了。**统一回同一句 + 可问清单**，
        // 而不是各编一句「暂时没有这个信息」—— 用户要能分清「没订单」和「功能坏了」。
        guard let order else {
            return VoiceStatusAnswer(
                speech: join("当前没有进行中的预约。", askableHint),
                pendingAction: nil
            )
        }

        switch intent {
        case .blockedDestructive:
            return VoiceStatusAnswer(
                speech: "取消需要在屏幕上确认，请找取消订单按钮。",
                pendingAction: nil
            )

        case .distance:
            return VoiceStatusAnswer(
                speech: distanceSpeech(order: order, volunteerCoordinate: volunteerCoordinate),
                pendingAction: nil
            )

        case .status:
            return VoiceStatusAnswer(
                speech: "\(order.status.displayName)。\(order.status.blindRunnerDescription)",
                pendingAction: nil
            )

        case .schedule:
            let time = order.plannedStartForAnnouncement.map { "预约时间：\($0)。" }
                ?? "预约时间还没有记录。"
            return VoiceStatusAnswer(
                speech: "\(time)出发地点：\(order.startAddressForAnnouncement)。",
                pendingAction: nil
            )

        case .callVolunteer:
            return callAnswer(order: order)

        case .unrecognized:
            return VoiceStatusAnswer(
                speech: join(fallbackAnnouncement, askableHint),
                pendingAction: nil
            )
        }
    }

    // MARK: Distance

    private static func distanceSpeech(
        order: OrderDetailResponse,
        volunteerCoordinate: CLLocationCoordinate2D?
    ) -> String {
        guard order.status.offersVolunteerDistanceToStart else {
            return "\(noDistanceReason(for: order.status))当前是\(order.status.displayName)。"
        }
        guard let distanceText = order.volunteerDistanceToStartText(from: volunteerCoordinate) else {
            // 坐标过期、没收到过、或订单没有起点坐标。三者对用户的下一步是同一件事：
            // 现在这个数字不存在，别等它。
            return "暂时收不到志愿者位置，所以算不出距离。当前是\(order.status.displayName)。"
        }
        return "志愿者\(distanceText)。"
    }

    /// 「为什么没有这个数据」比「暂时没有这个信息」多的那半句，就是盲人分辨
    /// 「功能坏了」和「现在就没有」的全部依据。
    private static func noDistanceReason(for status: RunOrderStatus) -> String {
        switch status {
        case .pendingMatch, .noVolunteer:
            return "还没有志愿者接单，所以暂时算不出距离。"
        // 通话磨合期后端不下发候选人位置（他还没接单），不是「收不到」而是「本来就没有」。
        case .pendingIntroCall:
            return "还在通话确认阶段，还没有志愿者接单，所以暂时算不出距离。"
        case .rematching:
            return "正在重新匹配志愿者，暂时算不出距离。"
        case .inProgress:
            return "你和志愿者已经在一起了，不需要距离。"
        case .completed, .cancelled:
            return "本次预约已经结束，没有志愿者位置。"
        case .unknown:
            return "订单状态有更新，暂时算不出距离。"
        case .pendingAccept, .driverEnRoute, .driverArrived:
            // `offersVolunteerDistanceToStart` 已经把这三态挡在上面，走不到这里。
            return "暂时收不到志愿者位置，所以算不出距离。"
        }
    }

    // MARK: Call

    /// 语音拨号复用**与屏幕按钮完全相同的三个条件**（`BlindOrderStatusView.volunteerCallSection`）：
    /// 状态允许 + 有号码 + 号码拼得出 `tel:` URL。绕过其中任何一个，就等于在不该打电话的状态下
    /// 让盲人拨出去一通电话。
    private static func callAnswer(order: OrderDetailResponse) -> VoiceStatusAnswer {
        // 通话磨合期**确实有一通该打的电话**，只是号码走专用接口（`IntroCallEndpoint.view`）、
        // 不在 `volunteerPhone` 上，所以 `offersVolunteerCall` 判 false。
        // 落到下面那句通用的「现在还不能打电话给志愿者」是错的 —— 能打，只是语音这条路暂时不接。
        // 对看不见屏幕的人，说「不能打」而不说去哪打就是死路，所以在通用分支之前单独答。
        if order.status == .pendingIntroCall {
            return VoiceStatusAnswer(
                // 结尾照样带上 `displayName`：这一族答句的共同不变式是「答完必须让用户知道
                // 现在是什么状态」，只有开头那句「现在还不能打电话给志愿者」是这一态的例外。
                speech: "这一单还在通话确认阶段，语音暂时不能替你拨号。"
                    + "打电话给这位志愿者的按钮就在订单状态页上。当前是\(order.status.displayName)。",
                pendingAction: nil
            )
        }
        guard order.status.offersVolunteerCall else {
            return VoiceStatusAnswer(
                speech: "现在还不能打电话给志愿者，\(noCallReason(for: order.status))当前是\(order.status.displayName)。",
                pendingAction: nil
            )
        }
        guard let phone = order.volunteerPhone?.nilIfBlank,
              EmergencyDialer.telURL(for: phone) != nil else {
            return VoiceStatusAnswer(
                speech: "还没有拿到志愿者的电话号码，暂时不能拨号。当前是\(order.status.displayName)。",
                pendingAction: nil
            )
        }
        // 逐位念。合成器会把 13800138000 念成一个天文数字，那串音记不住也对不上。
        // 只念数字位，与 `EmergencyDialer.telURL` 实际拨出去的完全一致。
        let spoken = phone.filter(\.isNumber).map(String.init).joined(separator: " ")
        return VoiceStatusAnswer(
            speech: "志愿者电话是 \(spoken)。要拨打请说确认，不打就说不用了。",
            pendingAction: .confirmDialVolunteer(phone: phone)
        )
    }

    private static func noCallReason(for status: RunOrderStatus) -> String {
        switch status {
        case .pendingMatch, .noVolunteer:
            return "还没有志愿者接单。"
        case .rematching:
            return "原来的志愿者已经不在这一单里，正在重新匹配。"
        case .completed, .cancelled:
            return "本次预约已经结束。"
        case .unknown:
            return "订单状态有更新，请先刷新页面。"
        case .pendingAccept, .driverEnRoute, .driverArrived, .inProgress:
            // `offersVolunteerCall` 已经放行这四态，走不到这里。
            return "当前状态不支持拨号。"
        case .pendingIntroCall:
            // `callAnswer` 在通用分支之前就把这一态单独答掉了，走不到这里。
            return "当前状态不支持拨号。"
        }
    }

    // MARK: Keyword tables

    /// 破坏性动作。**一条都不代做**，只指回屏幕。
    ///
    /// 词表里不带句尾语气词：`normalizedCommand` 会把「我不跑了」剥成「我不跑」，
    /// 写成「不跑了」就一条都不中（这一脚已经踩在用例 `testCancellationWordsAreBlocked...` 上）。
    private static let destructiveWords = ["取消", "退单", "退掉", "撤销", "不跑", "不去"]

    private static let callWords = [
        "打电话", "电话", "拨号", "拨打", "打给", "联系志愿者", "联系他", "通话"
    ]

    private static let statusWords = [
        "什么状态", "订单状态", "状态", "到哪一步", "哪一步", "接单", "怎么样", "什么情况", "进展"
    ]

    private static let distanceWords = [
        "多远", "到哪", "什么时候到", "快到", "还有多久", "还要多久", "多久到", "距离", "远不远"
    ]

    private static let scheduleWords = [
        "几点", "时间", "什么时候", "在哪", "从哪", "出发地点", "地点", "地址", "集合"
    ]

    // MARK: Helpers

    private static func join(_ head: String, _ tail: String) -> String {
        let trimmedHead = head.trimmed
        guard !trimmedHead.isEmpty else { return tail }
        return "\(trimmedHead) \(tail)"
    }
}
