import Foundation

// MARK: - 一条新邀请该怎么出现（设计交付 v3 §4.4.1）

/// 同一条邀请，按陪跑员**当下所处的状态**换一种呈现方式。
///
/// 🔴 **这一块坏了没有任何运行时信号。** 邀请照样到、倒计时照样走、接下照样成功 ——
/// 只是它没出现在该出现的地方：人正牵着引导绳跑着，屏幕上弹出一张压暗全屏的卡；
/// 或者反过来，他正坐在接单主页上等单，却只在顶上闪过一条 4 秒的横幅。
/// 两种都不会报错，也不会有任何用例在别处红掉，所以判定抽成纯函数逐档钉住。
///
/// **设计稿那张表一共 6 行，这里只判其中 3 行**，其余三行都不是客户端的判断：
/// - 「App 在后台或锁屏 → 系统推送」：那是 APNs 的活，而后端派单**根本不发 APNs**
///   （`NotificationService.sendDispatchNotification` 只 `sessionRegistry.sendToUser`），
///   已投 handoff。WebSocket 真在 `.inactive` 时送达一条，按他当下在哪一页处理即可。
/// - 「长按推送 → 两个操作」：没有推送就没有长按，同上。
/// - 「未开启接单 / 空闲时间以外 / 22:00–6:00 → 后端不发邀请」：判据全在后端，
///   客户端收到了就该呈现 —— 自己再判一遍只会制造「后端发了、客户端吞了」的静默分歧。
enum VolunteerInvitePresentation: Equatable {
    /// 底部邀请卡（sheet，背景压暗）+ 轻震一次 + 短提示音一次 + 播报。
    case inviteCard
    /// 顶部横幅停留 4 秒 + 首页标签数字角标 + 轻震一次。**无提示音**（设计稿逐字）。
    case banner
    /// 不推送、不横幅、不震动，只入队。陪跑结束回到接单主页后以
    /// 「陪跑时收到 N 个新邀请」卡片出现。
    case stashedDuringRun

    /// - Parameters:
    ///   - isEscortUnderway: 他正走在某一单里（`RunOrderStatus.isEscortUnderway`）。
    ///   - isOnDispatchHub: 接单主页（S3/S4）此刻在屏上。
    ///
    /// **两个参数的先后就是优先级**：陪跑中压倒一切。顺序写反的表现是「一边跑一边被弹卡」，
    /// 而那一刻他一只手牵着引导绳 —— 所以用例里专门有一条同时为真的输入，
    /// 那是唯一能分辨顺序被写反的取值（只测「陪跑中 + 不在接单主页」的话，
    /// 反过来的实现照样通过）。
    static func resolve(isEscortUnderway: Bool, isOnDispatchHub: Bool) -> Self {
        if isEscortUnderway { return .stashedDuringRun }
        return isOnDispatchHub ? .inviteCard : .banner
    }

    /// 要不要立刻把邀请卡顶上来。
    var presentsInviteSheet: Bool { self == .inviteCard }

    /// 轻震一次。陪跑中那一档明确不震（设计稿逐字「不推送、不横幅、不震动」）。
    var vibrates: Bool { self != .stashedDuringRun }

    /// 短提示音 + TTS 播报。**只有邀请卡那一档有**：
    /// 横幅那一行写的是「轻震一次，无声音」。
    var makesSound: Bool { self == .inviteCard }

    /// 顶部横幅。
    var showsBanner: Bool { self == .banner }
}
