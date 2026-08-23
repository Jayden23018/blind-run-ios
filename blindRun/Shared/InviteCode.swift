import Foundation

// MARK: - Contract

/// `GET /api/users/me/invite-code` 的响应（SPEC-E 第 4 步）。
///
/// ⚠️ **这个端点会写库**：邀请码是惰性生成的，第一次调用时才落库。
/// **别按纯读端点做缓存或预取**，也别在列表里对每个用户调它 —— 一次 `.task` 拉一次即可。
///
/// ⚠️ **尚未设角色（UNSET）的用户调它会 403**，所以入口只能放在设完角色之后的界面里。
struct InviteCodeResponse: Decodable, Sendable, Equatable {
    /// 8 位大写字母数字，**稳定不变**（不是一次一码）。
    ///
    /// 🚨 **字符集排除了 `0 O 1 I L`** —— 第一版走「注册时手填」，邀请人多半是**口头念**给对方听的。
    /// 展示与播报的处理见 `InviteCodeFormatting`。
    let inviteCode: String?

    /// 我一共邀请了几个人（含盲人 —— 邀请盲人只记录不奖励）。
    let invitedCount: Int64?

    /// 其中几个已发奖 = 被邀请的**志愿者**跑完了首单。
    let rewardedCount: Int64?

    var resolvedInvitedCount: Int64 { max(0, invitedCount ?? 0) }
    var resolvedRewardedCount: Int64 { max(0, rewardedCount ?? 0) }
}

// MARK: - 展示与播报

/// 邀请码的展示与播报处理。
///
/// 这是本模块唯一一处「视觉与听觉必须分别处理」的地方：
///
/// - **看**：等宽字体 + 字符间留空。契约点名要求「别用会把 `O`/`0` 渲染得难分的字体」——
///   虽然字符集已经排掉了易混字符，等宽仍然必要，因为用户要照着念、照着抄。
/// - **听**：**逐字播报**（「A、K、3、7…」），不要整串当成一个词念。
///   走 SwiftUI 原生的 `Text.speechSpellsOutCharacters()`（iOS 15+，本机 SDK 实证），
///   **不要**自己在字符串里插顿号 —— 那样 VoiceOver 会把顿号当标点念出来或吞掉，
///   而且拿不到读屏自己的拼读语速。
///
/// ⚠️ 落地时真机验过一次：见 `docs/research/incentive-ui-blind-first-20260823.md` 反对意见 2。
enum InviteCodeFormatting {
    /// 视觉展示用。字符间的空隙靠 SwiftUI 的 `kerning`/`tracking` 给，
    /// **不在字符串里插空格** —— 插了的话用户复制出来的码是坏的。
    static func display(_ code: String?) -> String? {
        code?.nilIfBlank?.uppercased()
    }

    /// 复制到剪贴板的值：与后端下发的原样一致，不加空格、不改大小写以外的任何东西。
    static func copyable(_ code: String?) -> String? {
        code?.nilIfBlank
    }
}

// MARK: - 文案

/// 邀请码页文案。
///
/// 🔴 **不得写「邀请好友双方得积分」这种不分角色的说法。**
/// 只有邀请**志愿者**且他完成首单才发分；**邀请盲人只记录关系、不发任何积分**
/// （后端决策 14：奖励它就是直接鼓励「拉视障者凑数」，凑来的用户没有真实出行需求）。
///
/// 🔴 同样受积分那三条合规红线约束：不可转让、不可提现、不可兑换现金。
enum InviteCodeCopy {
    static let navigationTitle = "我的邀请码"

    static let codeCaption = "我的邀请码"
    static let copyAction = "复制邀请码"
    static let copied = "邀请码已复制"

    static let rulesSectionTitle = "怎么算数"

    /// 🔴 逐字锁定的发奖口径。
    static let rewardRule = "邀请志愿者加入，等他完成第一次陪跑，你们各得 20 积分。邀请视障跑者只记录关系，不发积分。"

    /// 🔴 这句给**邀请人**看。抄 Uber 官方帮助页的做法：它把「忘了填就没有了」做成一个
    /// 独立的 "Remember this" 小节，因为忘记填的成本落在邀请人身上
    /// （原文：We cannot offer retrospective referral bonuses if your friend forgets
    /// to use your invite code during sign-up）。
    static let oneShotWarning = "对方必须在选择身份那一步填写你的邀请码，注册完成后无法补填。"

    static let pointsDisclaimer = "积分不能提现、不能转让、不能兑换现金。"

    static let empty = "还没有人使用你的邀请码。"

    /// UNSET 用户调这个端点会 403。入口本就该放在设完角色之后，这一屏是防御分支。
    static let roleRequired = "需要先选择身份才能拿到邀请码。"

    static let loadFailure = "暂时没能读到邀请码，请稍后重试。"
    static let retry = "重新加载"

    static func countsText(_ response: InviteCodeResponse) -> String {
        let invited = response.resolvedInvitedCount
        guard invited > 0 else { return empty }
        return "已经有 \(invited) 人使用了你的邀请码，其中 \(response.resolvedRewardedCount) 人已发放奖励。"
    }
}

// MARK: - 选身份那一屏的邀请码格

/// 选身份屏上「我有邀请码」这一格的文案与校验。
///
/// 🚩 **为什么挂在选身份而不是登录/验证码那一步**：后者是登录与注册合一的入口，
/// 老用户每次登录都会经过它 —— 挂在那里等于给任何老用户开一个「随时补填邀请码」的入口，
/// 那就是刷分入口。设角色天然只能成功一次（角色已设定时返 409，且角色不可修改）。
enum InviteCodeEntryCopy {
    /// 默认折叠。
    ///
    /// 两个坏处各消掉一半：默认展开会让**每个**新用户都要听读屏念一遍一个跟自己无关的输入框；
    /// 默认折叠又可能让真被邀请的人错过，而它**只有一次机会**。
    /// ⇒ 折叠成一个按钮（读屏一次划动就跳过），并在进页面的播报里提一句它存在。
    static let disclosureTitle = "我有邀请码（可选）"
    static let fieldLabel = "邀请码"
    static let fieldPrompt = "AK37PQR9"

    /// 🔴 诚实红线。**填错不会让请求失败**：码不存在、填了自己的、已被别人邀请过，
    /// 一律照常设角色成功，只是不建立邀请关系。而本轮**没有**「我的邀请人是谁」这个端点。
    /// ⇒ 客户端**永远无从判断邀请码是否生效**，所以：
    /// 1. 不要根据 `POST /api/user/role` 的成功与否说「邀请码已生效」；
    /// 2. 必须把这件事在填之前就告诉用户，而不是让他以为填了就一定算数。
    static let oneShotNotice = "只能在这里填一次，设定身份后无法补填。填错不会影响身份设置，但不会建立邀请关系。"

    /// 进页面时的播报追加句。折叠态下这是读屏用户知道有这个格子的**唯一**途径。
    static let speechHint = "如果有人邀请你，可以在页面下方填写邀请码，只能填这一次。"

    /// 契约：`maxLength: 16`，`pattern: ^[A-Za-z0-9]*$`。
    /// **大小写不敏感、首尾空格会被忽略**（后端做），所以客户端不必自己转大写。
    static let maxLength = 16

    /// 本地只做「不合法就不发」这一件事，**不做「这个码存不存在」的判断** —— 那是后端的事，
    /// 而且后端刻意不拦。空串按「没填」处理（契约允许不传或传空串）。
    ///
    /// ⚠️ 超长或含非法字符时返回 `nil`（当作没填），而不是报错拦住注册 ——
    /// 为一个可有可无的邀请码打断注册流程，对盲人用户是灾难性的。
    static func sanitize(_ raw: String) -> String? {
        let trimmed = raw.trimmed
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.count <= maxLength else { return nil }
        guard trimmed.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }
        return trimmed
    }
}
