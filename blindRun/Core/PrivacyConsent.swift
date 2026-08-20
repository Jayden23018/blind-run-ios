import Foundation

// MARK: - Purpose

/// 需要**单独同意**的处理目的。
///
/// **这不是产品文案，是合规文本。** PIPL 第 14 条要求告知后取得同意，第 29 条要求处理敏感个人信息
/// 取得**单独**同意 —— 「单独」的意思是：一次概括的「同意隐私政策」不能覆盖身份证号、人脸、
/// 行踪轨迹这三类，到收集它们的那一步必须再问一次。
///
/// 已有的 `RunPlanShareConsent` 走的就是这条路（轨迹→第三方）。本枚举补齐另外两个收集点：
/// 首次启动的整体告知，以及两端实名认证收集身份证号（志愿者还叠一次人脸活体）。
///
/// ponytail: `RunPlanShareConsentStore` 与这里的 `PrivacyConsentStore` 形状相同。没有合并是因为
/// 前者已发布且有自己的用例；下一次动到那块时再合，不要为了对称去改跑着的代码。
enum PrivacyConsentPurpose: String, CaseIterable, Sendable {
    /// 首次启动的整体告知。按**设备**记 —— 同意发生在登录之前，那时还没有账号。
    case appLaunch
    /// 视障跑者实名认证：姓名 + 身份证号。
    case blindIdentity
    /// 志愿者实名认证：姓名 + 身份证号，下一步还有人脸活体与证件照。
    case volunteerIdentity

    /// 告知内容的版本。**改下面任何一条 `disclosures` 就 +1**：旧同意没有覆盖到新内容，
    /// 必须重新征得。版本号进存储 key，旧记录自然失效 —— 这是唯一能让「告知内容」和
    /// 「已同意」不漂移的做法，靠人记必然漏。
    /// `PrivacyConsentTests.testDisclosureFingerprintIsPinnedToItsVersion` 会在文案变了
    /// 而版本没变时失败。
    var disclosureVersion: Int {
        switch self {
        // v2（2026-08-20）：删除账户那句从「里面不含这些资料」这种**否定式列举**改成正面列举。
        // 后端逐句核了代码（handoff 2026-08-19）：保留的订单里逐条存着精确起终点坐标和
        // `specialNotes`（用户自己口述的身体状况），求助记录里存着按下 SOS 那一刻的 GPS 单点。
        // 旧那句逐字成立，但读起来像「位置都清干净了」—— 用户关心的是「我的位置还在不在」，
        // 不是「哪张表还在」。⚠️ 后端说他们的删除语义没变、不用 bump；这里仍然 bump，
        // 因为版本号钉的是**告知内容**，而旧文案让人以为位置被删了，这是实质变化。
        case .appLaunch: return 2
        case .blindIdentity: return 1
        case .volunteerIdentity: return 1
        }
    }

    var title: String {
        switch self {
        case .appLaunch:
            return "开始前，先说清楚我们会收集什么"
        case .blindIdentity:
            return "提交实名信息前，请先确认"
        case .volunteerIdentity:
            return "提交实名信息前，请先确认"
        }
    }

    /// 每条都是完整的一句话，且在 UI 上是**独立的 VoiceOver 焦点**。
    /// 挤进一段长文本等于没有告知：读屏会一口气念完，用户记不住也回不去。
    var disclosures: [String] {
        switch self {
        case .appLaunch:
            return [
                "登录用你的手机号。视障跑者预约前要先实名认证，会收集姓名和身份证号；志愿者还要提供证件照并做一次人脸核验。",
                "陪跑服务进行中会持续获取你的位置，用来把双方位置显示给对方、记录这次的路线；锁屏后仍在定位。",
                "语音下单会录下你说的话并转成文字，只用于识别这一单的内容。",
                "身份证号、人脸和位置轨迹属于敏感个人信息。到收集它们的那一步，我们会再单独问你一次。",
                "这些信息只用于完成陪跑服务，不做广告、不卖给第三方。你随时可以在设置里删除账户：实名资料、紧急联系人和运动轨迹会被删除。",
                "订单、评价和求助记录会保留用于纠纷复核。里面仍有每次陪跑的起终点位置、你填写的备注和求助时的位置，但没有你的姓名、身份证号和紧急联系人。"
            ]
        case .blindIdentity:
            return [
                "提交后，你的姓名和身份证号会发给助盲跑的服务器做实名核验。",
                "身份证号属于敏感个人信息，只用于核验身份和判断预约资格，不会展示给志愿者。",
                "身份证号不会保存在这台手机上。删除账户时，实名资料会一并删除。"
            ]
        case .volunteerIdentity:
            return [
                "提交后，你的姓名和身份证号会发给助盲跑的服务器做实名核验，下一步还要做一次人脸活体核验。",
                "身份证号和人脸属于敏感个人信息，只用于核验身份和审核接单资格，不会展示给视障跑者。",
                "身份证号不会保存在这台手机上。删除账户时，实名资料和证件照会一并删除。"
            ]
        }
    }

    var agreeButtonTitle: String {
        switch self {
        case .appLaunch: return "同意并开始使用"
        case .blindIdentity, .volunteerIdentity: return "同意并提交"
        }
    }

    /// 拒绝按钮与同意按钮**同样大、同样整行铺满**（理由见 `RunPlanShareConsentView`）：
    /// 把拒绝做小是在用视觉权重替用户做决定，而这里的用户看不见视觉权重。
    var declineButtonTitle: String {
        switch self {
        case .appLaunch: return "先不同意"
        case .blindIdentity, .volunteerIdentity: return "先不提交"
        }
    }

    /// 拒绝后的反馈。不劝、不重试 —— 拒绝是一个完整的答案。
    /// 首启这条要说清后果，否则用户按下去只会看到一个没有反应的页面。
    var declinedFeedback: String {
        switch self {
        case .appLaunch:
            return "没有同意就无法使用助盲跑的服务。你可以先看隐私政策全文，想好了再按同意。"
        case .blindIdentity, .volunteerIdentity:
            return "没有提交。你可以随时回到这一页再提交。"
        }
    }

    /// 播报脚本。标题也念 —— 听的人没有视觉分段。
    var spokenScript: String {
        ([title] + disclosures).joined(separator: " ")
    }
}

// MARK: - Scope

/// 同意的归属。首启那条按设备（同意时还没有账号），实名那两条按账号 ——
/// 同一台手机换人用不是罕见场景，视障用户的设备常由家人协助设置。
enum PrivacyConsentScope: Equatable, Sendable {
    case device
    case user(String)

    var storageComponent: String {
        switch self {
        case .device: return "device"
        case .user(let id): return "user.\(id)"
        }
    }
}

// MARK: - Store

struct PrivacyConsentStore {
    private let persistence: any AppStatePersistence

    init(persistence: any AppStatePersistence) {
        self.persistence = persistence
    }

    static func storageKey(
        purpose: PrivacyConsentPurpose,
        scope: PrivacyConsentScope,
        version: Int? = nil
    ) -> String {
        let resolvedVersion = version ?? purpose.disclosureVersion
        return "com.aidrun.mvp.privacyConsent.\(purpose.rawValue).v\(resolvedVersion).\(scope.storageComponent)"
    }

    func hasConsented(to purpose: PrivacyConsentPurpose, scope: PrivacyConsentScope) -> Bool {
        persistence.object(forKey: Self.storageKey(purpose: purpose, scope: scope)) as? Bool == true
    }

    func recordConsent(to purpose: PrivacyConsentPurpose, scope: PrivacyConsentScope) {
        persistence.set(true, forKey: Self.storageKey(purpose: purpose, scope: scope))
    }
}
