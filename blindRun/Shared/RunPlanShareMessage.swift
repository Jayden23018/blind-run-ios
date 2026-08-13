import Foundation

// MARK: - Copy

/// 「把这次行程告诉家人」的全部对外文案。集中一处与 `KeepWaitingCopy` 同一个理由：
/// 这里每一句的措辞都有硬约束，散在 view 和 delegate 回调里就只能靠人记。
///
/// **最硬的那条约束**：`MFMessageComposeViewController` 的 `.sent` 结果
/// **不保证消息真的到达收件人**（Apple 文档），用户还可以在系统界面里改掉收件人和正文。
/// 所以下面任何一句都不许出现「已通知」「已收到」「已送达」「家人已知悉」。
/// 这与 `AGENTS.md` §6 那条「App 永远不得宣称短信已发出、已送达」同源，
/// 由 `RunPlanShareMessageTests` 逐条断言。
enum RunPlanShareCopy {
    static let buttonTitle = "把这次行程告诉家人"

    /// hint 必须说清「需要你自己点发送」—— 盲人按下按钮后弹出的是系统短信界面，
    /// 如果以为按一下就发出去了，他会直接退出，而短信还躺在草稿里。
    static let accessibilityHint = "打开短信，内容已经填好，需要你自己点发送"

    /// 进行时，不是完成时。见本枚举顶部的约束说明。
    static let sent = "短信已交给系统，请在短信里确认已发出。"
    static let cancelled = "已取消，没有发送。"
    static let failed = "短信没能发出，请稍后再试，或者直接打电话。"

    /// 设备根本不能发短信（iPad 无蜂窝、运营商未配置等）。不静默失败：
    /// 系统 composer 没有存草稿这一步，`canSendText` 为 false 时呈现它只会得到一个空壳。
    static let unavailable = "这台设备不能发短信，请直接打电话告诉家人。"

    /// 没有紧急联系人时不隐藏按钮 —— 隐藏了盲人就不知道有这个功能。
    static let noContact = "还没有设置紧急联系人，先去添加一个。"

    /// 短信正文最后一句。家属需要知道这是一次性的告知，不是持续监控，
    /// 否则「我收到过一条短信」会被误当成「我一直看得到他在哪」。
    static let disclaimer = "（这条短信由本人发送，App 不会自动通知任何人。）"
}

// MARK: - Message

/// 发给紧急联系人的行程告知短信正文。**纯函数，不 import UIKit，可单测。**
///
/// 这是 `docs/research/live-trip-sharing-and-volunteer-incentives-20260813.md` §1 里
/// 那套架构的最后一环：Strava Beacon 与 Uber 都是「服务端发 token + 免登录只读页，
/// 客户端把链接塞进预填短信由用户手动发」，服务端那两截我们还没有，
/// 于是这一版把链接换成静态行程要素。后端契约到位后，只需在正文里多加一行 URL。
enum RunPlanShareMessage {
    static func compose(order: OrderDetailResponse) -> String? {
        guard order.status.offersRunPlanShare else { return nil }

        var lines = ["我正在使用助盲跑陪跑服务。"]

        if let start = order.plannedStartForAnnouncement {
            lines.append("出发时间：\(start)")
        }
        if let address = order.startAddress?.nilIfBlank {
            lines.append("出发地点：\(address)")
        }
        // 终点用 `endAddress` 而**不是** `endAddressForDisplay`：后者会给查不到坐标的地址
        // 追加「（未定位到）」，那是给志愿者看的（改变他要不要导航），对家属只是噪音，
        // 还顺带暴露了我们内部的定位状态。
        //
        // `nil` 时**一个字都不提终点**：`endAddress == nil` 的语义是「用户没说终点」，
        // 不是「原路返回起点」。摆一行出来，家属就会去等一个盲人从没说过的地点
        // （同 `endAddressForDisplay` 的注释与后端 `websocket-protocol.md:429` 一条口径）。
        if let endAddress = order.endAddress?.nilIfBlank {
            lines.append("结束地点：\(endAddress)")
        }
        // 预计结束时间取 `plannedEnd`，**不用** `plannedStart + expectedDurationMinutes` 自己推 ——
        // 两者是后端各自算的，口径不保证一致，推出来的数字与订单详情页显示的对不上时，
        // 家属手里的时间和盲人手里的时间就差一截。
        if let end = order.plannedEnd?.nilIfBlank?.displayDateTime {
            lines.append("预计结束：\(end)")
        }
        lines.append("订单号：\(order.orderId)")
        lines.append(RunPlanShareCopy.disclaimer)

        return lines.joined(separator: "\n")
    }
}
