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
/// 只用系统定义的 `UINotificationFeedbackGenerator` 三种语义，不自造波形：Apple 明确要求
/// 保持系统一致性，自造的模式对用户是需要重新学习的噪音。
enum HapticFeedback {
    enum Kind {
        /// 事情按预期推进了：接单、到达、服务开始、订单完成、求助已受理。
        case success
        /// 需要注意但不是失败：订单被取消、暂无志愿者、重新匹配中。
        case warning
        /// 明确的坏消息：求助**未发出**。
        case error
    }

    /// 真机以外（模拟器、单测）静默无副作用，所以不需要测试替身。
    ///
    /// 主线程派发的理由与 `VoiceService.markSpeaking` 一致：调用点分布在轮询回调、
    /// WebSocket 回调和 `didSet` 里，线程不确定，而 `UIFeedbackGenerator` 要求主线程。
    static func play(_ kind: Kind) {
        let type: UINotificationFeedbackGenerator.FeedbackType = {
            switch kind {
            case .success: return .success
            case .warning: return .warning
            case .error: return .error
            }
        }()
        let fire = { UINotificationFeedbackGenerator().notificationOccurred(type) }
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
        case .pendingIntroCall, .scheduledConfirmed, .pendingAccept, .driverEnRoute, .driverArrived, .inProgress, .completed:
            return .success
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
