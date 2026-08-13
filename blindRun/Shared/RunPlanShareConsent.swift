import Foundation

// MARK: - Copy

/// 实时行程分享的明示同意文案。
///
/// **这不是产品文案，是合规文本。** 调 `POST /api/orders/{id}/share` 等同于盲人对
/// 「向持链接者提供本人实时位置与轨迹」作出单独同意 —— 轨迹是 PIPL 第 28 条明列的
/// 「行踪轨迹」（敏感个人信息），向第三方提供适用第 23 条，处理敏感信息适用第 29 条。
/// 后端 2026-08-13 的通报逐字写着：**做成一键静默分享，这个同意在法律上不成立，
/// 后端挡不住这一层，只有客户端能。**
///
/// 三件事缺一不可，且**每一条都必须是独立的 VoiceOver 焦点** —— 对看不见屏幕的人，
/// 把三件事挤进一段长文本等于没有告知：读屏会一口气念完，用户记不住也回不去。
enum RunPlanShareConsentCopy {
    static let title = "分享实时位置给家人"

    /// 三条告知。顺序即重要性：先说分享什么，再说给谁，最后说能撤回。
    /// 「给谁」排在「能撤回」前面是因为它是唯一有意外性的一条 —— 用户默认以为只有家人能看。
    static let whatIsShared = "分享的是你的实时位置和这次跑步的轨迹。"
    static let whoCanSee = "任何拿到这个链接的人都能看到，不只是你发给的那个人。"
    static let howToStop = "你可以随时停止分享，停止后链接立刻失效。"

    static var allDisclosures: [String] { [whatIsShared, whoCanSee, howToStop] }

    static let agreeButtonTitle = "我知道了，开始分享"
    static let declineButtonTitle = "先不分享"

    /// 之后每次分享的简短确认。**不重复全文**（每次都念一遍长文本，用户会开始跳过它，
    /// 那才是真正失去告知效力的时候），但必须保留「谁能看」这条最有意外性的。
    static let repeatConfirmationTitle = "开始分享实时位置？"
    static let repeatConfirmationMessage = "任何拿到链接的人都能看到你的实时位置，随时可以停止。"

    /// 用户拒绝时的反馈。不劝、不重试 —— 拒绝是一个完整的答案。
    static let declined = "没有分享，位置只有你和志愿者能看到。"
}

// MARK: - Consent Store

/// 明示同意的记录。**按用户 + 告知版本存**，两者缺一不可：
///
/// - 按用户：同意是个人作出的，换账号登录不继承前一个人的同意。
/// - 按版本：`RunPlanShareConsentCopy` 的三条告知内容一旦改动，旧同意就没有覆盖到新内容，
///   必须重新征得。改文案时同步 bump `disclosureVersion`，旧记录自然失效 ——
///   这是**唯一**能让「告知内容」和「已同意」不漂移的做法，靠人记必然漏。
struct RunPlanShareConsentStore {
    /// 告知内容的版本。改 `RunPlanShareConsentCopy` 里任何一条 disclosure 就 +1。
    /// `RunPlanShareConsentTests.testDisclosureVersionCoversEveryDisclosure` 会在
    /// 文案变了而版本没变时失败。
    static let disclosureVersion = 1

    private let persistence: any AppStatePersistence

    init(persistence: any AppStatePersistence) {
        self.persistence = persistence
    }

    static func storageKey(userKey: String, version: Int = disclosureVersion) -> String {
        "runPlanShareConsent.v\(version).\(userKey)"
    }

    func hasGivenConsent(userKey: String) -> Bool {
        persistence.object(forKey: Self.storageKey(userKey: userKey)) as? Bool == true
    }

    func recordConsent(userKey: String) {
        persistence.set(true, forKey: Self.storageKey(userKey: userKey))
    }

    // ponytail: 没有 clearConsent —— key 里带了 userKey，换账号天然不命中，
    // 登出再登录是同一个人、同意本就该还在。真要清（注销账号）时再加。
}

// MARK: - Flow

/// 按下分享后该走哪一步。判定与展示分开，是为了让这三条分支能被单测钉住 ——
/// 「首次没走全屏引导」这种缺陷在 UI 里几乎测不出来，在这里是一行断言。
enum RunPlanShareConsentStep: Equatable {
    /// 首次：全屏引导页，三条告知各自独立朗读。
    case fullDisclosure
    /// 之后：一句话确认。
    case shortConfirmation

    static func next(hasGivenConsent: Bool) -> RunPlanShareConsentStep {
        hasGivenConsent ? .shortConfirmation : .fullDisclosure
    }
}
