import Foundation

// 从 `SafetyModule.swift` 原样搬来（#506）：那个文件已超 SwiftLint 长度上限，CI 棘轮不许再变长。

/// 本地拨号弹窗的两种语境。**只差第一句**，而那一句每次都得说对：
/// 它回答的是「我刚才那一下到底发生了什么」，说错会让盲人把「什么都没发生」当成「求助已发出」。
///
/// 做成枚举而不是让调用方各传一个字符串：两处都在安全路径上，谁漏了一句
/// 都不会有任何运行时症状 —— 弹窗照常弹，只是话说错了。
///
/// 2026-09-15 由三种减为两种：`inProgress`（陪跑中主动拨号）的调用点已并入求助中心
/// `blindActiveRunSafetyHubDialog`，它的第一句由 `hubDialogMessage` 承担。
enum EmergencyCallContext {
    /// 首页，当前没有进行中的陪跑。
    case homeIdle
    /// 云端求助刚刚失败（首页与订单状态页共用）。
    case cloudFailed
    /// 陪跑员订单页右上角「求助」，不在跑步中（邀请到完成 / 跑者取消，`VolunteerOrderSOSMode.localCall`，2026-09-26）。
    ///
    /// 不复用 `homeIdle`：那句「当前没有进行中的陪跑」对一个正骑车赶去集合点的陪跑员不成立。
    case volunteerBeforeRun
    /// 跑者端，跑步中登录已过期（#376，`BlindHomeSOSMode.localCallSessionExpired`）。
    case runnerSessionExpired
    /// 陪跑员跑步中求助面板，登录已过期（#381，`VolunteerRunEmergencyMode.localCallSessionExpired`）。
    ///
    /// 不复用 `volunteerBeforeRun`：「现在不在跑步中」此刻是假的。
    case volunteerSessionExpired
    /// 跑者端屏 3b：云端求助**已经发出**，用户还想自己打电话（#506 的「打 110 或紧急联系人」）。
    ///
    /// 不复用 `cloudFailed`：那句「求助没有发出去」此刻是假的，会让人以为求助白按了。
    case cloudSent

    /// 跑者端求助模式 → 拨号弹窗该用哪一句。**两个入口（「我的」tab 求助条、订单页求助中心）都走这里**，
    /// 此前各写一个三元表达式 `== .cloudTrigger ? .cloudFailed : .homeIdle` —— 加一档模式时
    /// 三元表达式不会报错，只会把新的一档静默归到「当前没有进行中的陪跑」。
    static func runner(for mode: BlindHomeSOSMode) -> EmergencyCallContext {
        switch mode {
        case .cloudTrigger: return .cloudFailed
        case .localCall: return .homeIdle
        case .localCallSessionExpired: return .runnerSessionExpired
        }
    }

    var dialogMessage: String {
        switch self {
        case .homeIdle: return EmergencySafetyCopy.homeCallDialogMessage
        case .cloudFailed: return EmergencySafetyCopy.cloudFailedCallDialogMessage
        case .volunteerBeforeRun: return EmergencySafetyCopy.volunteerBeforeRunCallDialogMessage
        // 这句不提联系人，两端都成立。
        case .runnerSessionExpired, .volunteerSessionExpired: return EmergencySafetyCopy.sessionExpiredCallDialogMessage
        case .cloudSent: return EmergencySafetyCopy.sentCallDialogMessage
        }
    }

    var accessibilityHint: String {
        switch self {
        case .homeIdle: return EmergencySafetyCopy.homeCallAccessibilityHint
        case .cloudFailed: return EmergencySafetyCopy.cloudFailedCallAccessibilityHint
        case .volunteerBeforeRun: return EmergencySafetyCopy.volunteerBeforeRunCallAccessibilityHint
        case .runnerSessionExpired: return EmergencySafetyCopy.sessionExpiredCallAccessibilityHint
        case .volunteerSessionExpired: return EmergencySafetyCopy.volunteerSessionExpiredCallAccessibilityHint
        case .cloudSent: return EmergencySafetyCopy.sentOtherCallsAccessibilityHint
        }
    }

    /// 「尚未设置唯一的主紧急联系人」那句只对跑者成立 —— 陪跑员这里本来就不列联系人。
    /// 穷举而不是 `!=`：再加一档陪跑员语境时，编译器会逼一次决策。
    var appendsNoContactHint: Bool {
        switch self {
        case .homeIdle, .cloudFailed, .runnerSessionExpired, .cloudSent: return true
        case .volunteerBeforeRun, .volunteerSessionExpired: return false
        }
    }
}
