import Foundation

/// `GET /api/config/features` 响应体（`APIClient` 已自动解包 `{success, data}` 外层信封）。
///
/// **它只回答「功能开没开」，不回答「你有没有」** —— 后者仍是各自列表端点的事。
/// 契约在这一点上写得很硬，理由是：混进来的话客户端就有两个地方能得出「显示什么」，
/// 而它们迟早不一致。同理这里没有任何阈值、分值、名单。
///
/// ## 存在的理由：同一个空数组有两个完全相反的含义
///
/// 三个 SPEC-E 开关后端默认全关，关着时相关端点返回空数组。而空数组既可能是
/// 「功能还没开放」，也可能是「你确实还没点亮」。客户端此前恒说后者 ——
/// 于是开关关着的那段时间里，那句文案是在**教用户去做一件做了也不会有结果的事**。
/// 对读屏用户尤其糟：他会照着做两周，回来发现还是空的。
///
/// ## 三个字段都是可选的，而且不能落 false
///
/// 🔴 **缺字段 / 拿不到响应时必须落到「不知道」，不能落到 false。**
/// false 的语义是「功能确实没开」，客户端会照着说「还没有开放」——
/// 而一次网络抖动不该让用户听到一个关于产品状态的断言。
/// 判据见 `PartnerStreakCopy.blindEmpty(streakEnabled:)`：`nil` 走的是第三套文案。
struct FeatureFlagsResponse: Codable, Sendable, Equatable {
    /// 双人火花是否开启（`app.incentive.streak.enabled`）。
    let partnerStreakEnabled: Bool?

    /// 派单的固定搭档优先轮是否开启（`app.dispatch.favorite-round.enabled`）。
    ///
    /// ⚠️ 它**不影响收藏本身** —— 关着时照样能收藏、列表照样有数据，只是派单不会先问收藏的搭档。
    /// 拿它决定要不要说「会优先派给他们」这句承诺，不要拿它去藏收藏入口。
    let favoriteDispatchRoundEnabled: Bool?

    /// 拉新**奖励**是否开启（`app.incentive.invitation.enabled`）。
    ///
    /// 🚨 **名字里的 Reward 是刻意的，语义与上面两个不一样：它只关奖励，不关关系建立。**
    /// 关着时邀请码照样要填、邀请关系照样落库，只是双方不发积分。
    /// **不要**因为它是 false 就把邀请码输入框藏掉 —— 那会让开关打开之后这批用户
    /// 永久拿不到奖励，而他们当时根本没机会填。（这句话是契约 description 的原文。）
    let invitationRewardEnabled: Bool?

    init(
        partnerStreakEnabled: Bool? = nil,
        favoriteDispatchRoundEnabled: Bool? = nil,
        invitationRewardEnabled: Bool? = nil
    ) {
        self.partnerStreakEnabled = partnerStreakEnabled
        self.favoriteDispatchRoundEnabled = favoriteDispatchRoundEnabled
        self.invitationRewardEnabled = invitationRewardEnabled
    }
}
