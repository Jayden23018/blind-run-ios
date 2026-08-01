import Foundation

// MARK: - Legal Links Response

/// `GET /api/misc/legal-links` 响应体（`APIClient` 已自动解包 `{success, data}` 外层信封）。
///
/// 后端 `SecurityConfig` 对该端点 permitAll：未登录用户和 App Store 审核员都能访问，
/// 因此请求时必须传 `requiresAuth: false`。
///
/// 两个字段都可能为 `null`：后端从 `app.legal.privacy-policy-url` /
/// `app.legal.user-agreement-url` 配置注入，生产 URL 未上线时默认返回 `null`。
/// 此时入口必须回退到应用内置文案页（App Store 审核 5.1.1 / 5.1.2 阻塞项）。
struct LegalLinksResponse: Codable, Sendable, Equatable {
    let privacyPolicyUrl: String?
    let userAgreementUrl: String?
}

// MARK: - Legal Document Kind

/// 两类法律文档入口。
/// 不做未知值兜底：这是客户端自己的入口枚举，后端只返回两个 URL 字符串，没有对应字段被解码成它。
enum LegalDocumentKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case privacyPolicy
    case userAgreement

    var id: String { rawValue }

    var title: String {
        switch self {
        case .privacyPolicy: return "隐私政策"
        case .userAgreement: return "用户协议"
        }
    }

    /// 从响应中取出本类型对应的原始 URL 字符串。
    func rawURLString(in links: LegalLinksResponse?) -> String? {
        switch self {
        case .privacyPolicy: return links?.privacyPolicyUrl
        case .userAgreement: return links?.userAgreementUrl
        }
    }
}

// MARK: - Legal Document Destination

/// 一个法律文档入口点击后的落点。
///
/// 抽成独立枚举 + 纯函数（而不是把判断埋在 View body 里），
/// 以便单测直接覆盖「外链」和「内置回退文案」两条分支。
enum LegalDocumentDestination: Equatable, Sendable {
    /// 后端下发了可用的 http(s) URL，点击后在浏览器打开。
    case remote(URL)
    /// URL 为 null / 空 / 非法，或请求失败：点击后打开应用内置文案页。
    /// 绝不允许出现空白页、报错弹窗或禁用的灰按钮。
    case builtInFallback

    var isRemote: Bool {
        if case .remote = self { return true }
        return false
    }

    var remoteURL: URL? {
        if case .remote(let url) = self { return url }
        return nil
    }
}

extension LegalDocumentKind {
    /// 决定该入口走外链还是走内置回退文案。纯函数，无副作用。
    ///
    /// `links` 为 `nil` 表示尚未加载完成或请求失败 —— 一律回退到内置文案，
    /// 这样入口在任何时刻都是可点且有内容的。
    func destination(in links: LegalLinksResponse?) -> LegalDocumentDestination {
        guard let url = Self.validatedWebURL(rawURLString(in: links)) else {
            return .builtInFallback
        }
        return .remote(url)
    }

    /// 校验后端下发的字符串是否是可安全打开的网页地址。
    ///
    /// 后端配置是外部输入，不可信：必须挡掉空串、纯空白、字面量 "null"、
    /// 相对路径，以及 `javascript:` / `file:` / 自定义 scheme 等非网页地址。
    static func validatedWebURL(_ rawValue: String?) -> URL? {
        guard let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty,
              trimmed.lowercased() != "null",
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host,
              !host.isEmpty else {
            return nil
        }
        return url
    }
}

// MARK: - Built-in Fallback Copy

/// 内置回退文案。
///
/// 正式法律文本未上线时的过渡版本：只陈述本应用当前真实的数据处理方式和使用要点，
/// 不编造法律条款，不承诺尚未实现的能力。
enum LegalFallbackCopy {

    struct Section: Identifiable, Equatable, Sendable {
        let id = UUID()
        let heading: String
        /// 每条单独成段，VoiceOver 可逐条浏览。
        let bullets: [String]
    }

    struct Document: Equatable, Sendable {
        let title: String
        /// 页首的状态说明，明确告知用户这是过渡版本。
        let notice: String
        let sections: [Section]
    }

    static func document(for kind: LegalDocumentKind) -> Document {
        switch kind {
        case .privacyPolicy: return privacyPolicy
        case .userAgreement: return userAgreement
        }
    }

    private static let privacyPolicy = Document(
        title: "隐私政策",
        notice: "正式版隐私政策全文正在上线中。以下是本应用当前版本实际收集和使用信息的说明。",
        sections: [
            Section(
                heading: "我们收集的信息",
                bullets: [
                    "手机号：用于登录和账户识别。",
                    "昵称和资料：用于向本次服务的另一方展示必要的身份信息。",
                    "位置信息：仅在你创建预约、接单或服务进行中使用，用于匹配附近的志愿者、计算距离和展示地图。",
                    "紧急联系人姓名和电话：由视障跑者填写，用于紧急情况下联系。",
                    "志愿者身份认证资料：用于审核志愿者接单资格。"
                ]
            ),
            Section(
                heading: "我们如何使用这些信息",
                bullets: [
                    "仅用于完成陪跑服务的匹配、进行和结束。",
                    "服务开始后，向已接单的志愿者展示视障跑者的联系方式；接单前不展示。",
                    "不用于广告投放，不向第三方出售个人信息。"
                ]
            ),
            Section(
                heading: "你的选择",
                bullets: [
                    "可以在系统设置中关闭定位权限。关闭后无法创建预约或接单，其他功能不受影响。",
                    "可以在本应用「设置 - 删除账户」中删除账户。删除后所有登录令牌立即失效，手机号可以重新注册。"
                ]
            ),
            Section(
                heading: "关于本说明",
                bullets: [
                    "本说明为正式文本上线前的过渡版本，内容与应用当前行为一致。",
                    "正式隐私政策和对外联系方式将随正式文本一同发布。在此之前，你可以使用「设置 - 删除账户」自助删除账户及相关数据。"
                ]
            )
        ]
    )

    private static let userAgreement = Document(
        title: "用户协议",
        notice: "正式版用户协议全文正在上线中。以下是本应用当前版本的使用要点。",
        sections: [
            Section(
                heading: "服务内容",
                bullets: [
                    "本应用为视障跑者和志愿者提供陪跑服务的预约与匹配。",
                    "本应用不提供医疗、康复或急救服务。"
                ]
            ),
            Section(
                heading: "使用规则",
                bullets: [
                    "请填写真实的手机号、昵称和紧急联系人信息。",
                    "志愿者需要通过身份认证并开启接单开关后才能接单。",
                    "一个手机号可以同时拥有视障跑者和志愿者两个身份，有进行中的订单时不能切换身份。"
                ]
            ),
            Section(
                heading: "安全与责任",
                bullets: [
                    "陪跑服务由用户之间线下完成，参与前请自行评估身体状况和路线安全。",
                    "遇到紧急情况，请优先联系当地急救服务。"
                ]
            ),
            Section(
                heading: "账户",
                bullets: [
                    "你可以随时在「设置 - 删除账户」中删除账户。",
                    "本要点为正式协议上线前的过渡版本，内容与应用当前行为一致。"
                ]
            )
        ]
    )
}
