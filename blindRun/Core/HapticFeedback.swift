import UIKit

// MARK: - Haptic Feedback

/// 业务事件的触觉通道。
///
/// **为什么这个 App 特别需要它**：陪跑是「听觉通道最容易被占用」的场景 —— 户外噪音、
/// 耳机在放东西、正在跟志愿者说话。而在此之前全仓只有 2 处触觉，都在
/// `SpeechInputService` 的录音起停，业务事件（接单、到达、求助已发出、订单取消）**一次都没有**，
/// 也就是说最重要的三条状态全押在最容易被打翻的那条通道上。
/// Apple 的指引也是这一条：用户在**看不见屏幕时最依赖触觉**。
///
/// 触觉是**冗余通道，不是替代通道** —— 每一次触觉旁边都必须已经有一句话在播。
/// 单独的一下震动没有语义，用户分不出是「接单了」还是「取消了」。
/// 所以接线点选在播报的 funnel 里（`VoiceService.speakStatusChange`、
/// `EmergencyCoordinator.state` 的 `didSet`），而不是散落在各个业务分支上。
///
/// 只用系统定义的波形，不自造：Apple 明确要求保持系统一致性，自造的模式对用户是需要
/// 重新学习的噪音。三种**通知**语义走 `UINotificationFeedbackGenerator`，
/// 两种**撞击**走 `UIImpactFeedbackGenerator`（`.tick` 用 `.light`、`.strong` 用 `.heavy`）。
enum HapticFeedback {
    enum Kind {
        /// 事情按预期推进了：接单、到达、服务开始、订单完成、求助已受理。
        case success
        /// 需要注意但不是失败：订单被取消、暂无志愿者、重新匹配中。
        case warning
        /// 明确的坏消息：求助**未发出**。
        case error
        /// 一次**轻**节拍。目前只有开跑倒计时的三拍用它（设计稿逐字写的是「每拍轻震」）。
        ///
        /// 🚩 **它是上面「触觉必须伴随一句话」那条不变量的唯一破例，破得有理由：**
        /// 倒计时那三下不是三条独立消息，而是**同一个信息的三个节拍**，
        /// 而那条信息（还有几秒开跑）此刻正以 52pt 的数字显示在屏幕正中。
        /// 也就是说它旁边确实有别的通道在说同一件事，只不过是视觉不是听觉 ——
        /// 对不开读屏的低视力用户，这恰恰是唯一还能对上的两条通道。
        ///
        /// 🔴 **不能复用 `.success`。** 那是通知波形，接单 / 到达 / 服务开始 / 订单完成
        /// 用的都是它；倒数三下若也用它，一是跑者分不出这三下是什么意思，
        /// 二是紧接着 `speakStatusChange(.inProgress)` 也震一次 `.success`
        /// （`RunOrderStatus.haptic` 判 `.success`）—— 三秒里四次同样的波形，
        /// 等于把这条通道的语义洗掉。换成 impact 之后是「1 次通知 + 3 次轻拍」，可分辨。
        case tick
        /// 一次**强**撞击。设计稿里写作「强震一次」，目前只有「陪跑员结束了本次陪跑」用它
        /// （状态清单 §4）。
        ///
        /// 🔴 **不能用 `.warning` 顶替**：那是通知波形里的「双下」，而且语义是
        /// 「需要注意但不是失败」（订单被取消、暂无志愿者都在用它）——
        /// 把「跑完了」震成跟「订单被取消」同一个波形，是在告诉跑者出事了。
        /// 也不能用 `.success`：接单 / 到达 / 服务开始全是它，而这一下要表达的是
        /// 「整件事到此结束」，是这条链路上最后也最重的一下。
        case strong
    }

    /// 真机以外（模拟器、单测）静默无副作用，所以不需要测试替身。
    ///
    /// 主线程派发的理由与 `VoiceService.markSpeaking` 一致：调用点分布在轮询回调、
    /// WebSocket 回调和 `didSet` 里，线程不确定，而 `UIFeedbackGenerator` 要求主线程。
    static func play(_ kind: Kind) {
        let fire: () -> Void = {
            switch kind {
            case .tick:
                return { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
            case .strong:
                return { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }
            case .success, .warning, .error:
                let type: UINotificationFeedbackGenerator.FeedbackType = {
                    switch kind {
                    case .success: return .success
                    case .warning: return .warning
                    case .error: return .error
                    // 上面的外层 switch 已经把两种撞击分走了。
                    case .tick, .strong: return .success
                    }
                }()
                return { UINotificationFeedbackGenerator().notificationOccurred(type) }
            }
        }()
        if Thread.isMainThread {
            fire()
        } else {
            DispatchQueue.main.async(execute: fire)
        }
    }
}

extension RunOrderStatus {
    /// 状态变化时该给哪一种触觉。`nil` = 不震（本状态没有值得打断用户的信息）。
    ///
    /// 穷举 switch 而非集合字面量，理由同 `offersVolunteerCall`：后端加状态时编译器逼一次决策。
    /// 落到 `nil` 必须是**想清楚了**的结果，而不是新状态默认掉进去的坑。
    var haptic: HapticFeedback.Kind? {
        switch self {
        // 推进：每一步都是用户在等的那个消息。
        // `.pendingIntroCall` 在列：有人想陪你跑，而且**需要你去打一通电话** ——
        // 这一态既是好消息又带着一个待办，正是该打断用户的时刻。
        // `.scheduledConfirmed` 在列：「有人接了你那张跨天单」是纯好消息，与 `.pendingAccept` 同档。
        case .pendingIntroCall, .scheduledConfirmed, .pendingAccept, .driverEnRoute, .driverArrived, .inProgress:
            return .success
        // 🚩 `COMPLETED` 2026-09-17 从 `.success` 换成 `.strong`（设计稿 §4「+ 强震一次」）。
        // 它与上面那一串的区别是**这一下是最后一下**：前面每一次推进都在说「下一步来了」，
        // 而这一次说的是「结束了，你可以摘下引导绳」。同一个波形分不出这层差别，
        // 而对看不见屏幕的人，这恰恰是他唯一能立刻确认「跑完了」的通道。
        case .completed:
            return .strong
        // 需要注意：计划有变，用户多半要做点什么。
        case .cancelled, .noVolunteer, .rematching:
            return .warning
        // 下单成功由下单流程自己给反馈，这里再震一次是重复的。
        case .pendingMatch:
            return nil
        // 认不出的状态照样震一下：播报那边也是宁可说「请刷新」也不静默，两条通道口径一致。
        case .unknown:
            return .warning
        }
    }
}
