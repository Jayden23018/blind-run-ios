import SwiftUI

// MARK: - App Identity

/// 「关于」页顶部的 App 名称和版本号。
enum AppIdentity {
    /// 不读安装包：主 App 没有 `CFBundleDisplayName`，`CFBundleName` 是工程名 `blindRun`（#628）。
    static let name = "助盲跑"

    /// 取安装包的版本号，发版改 `MARKETING_VERSION` 时这里不用动。
    static func versionLine(info: [String: Any]? = Bundle.main.infoDictionary) -> String {
        guard let version = (info?["CFBundleShortVersionString"] as? String)?.nilIfBlank else {
            return "版本未知"
        }
        return "版本 \(version)"
    }
}

// MARK: - Filing Disclosure

/// 上架合规要公示的固定值。依据和来源见 `docs/research/llm-filing-disclosure-20261031.md`。
enum AppFilingDisclosure {
    /// 工信部信管〔2023〕105 号第二条第（八）项。**`-4A` 后缀是 App 备案号的一部分，不能去掉**：
    /// 不带后缀的号不是这个 App 的号。
    static let appFilingNumber = "粤ICP备20047259号-4A"
    static let filingQueryURL = URL(string: "https://beian.miit.gov.cn/")! // guard:allow server-addr 工信部备案查询页，用浏览器打开，不是 API
    static let filingQueryLabel = "工信部备案查询网站 beian.miit.gov.cn"

    /// 国家网信办 2026-05-13 公告要求公示模型名称和备案号。
    /// 后端换模型或换厂商（`app.voice.llm.model`）时这里要一起改。
    /// 同一家的 `网信算备…` 是算法备案号，不是大模型备案号。
    static let voiceOrderModelName = "通义千问大模型"
    static let voiceOrderModelFilingNumber = "ZheJiang-TongYiQianWen-20230901"
}

// MARK: - Sections

struct AppIdentitySection: View {
    var body: some View {
        Section {
            Text(AppIdentity.name)
                .font(AppFonts.body().weight(.semibold))
                .foregroundColor(AppColors.textPrimary)
                .accessibilityIdentifier("aboutAppName")
            Text(AppIdentity.versionLine())
                .foregroundColor(AppColors.textSecondary)
                .accessibilityIdentifier("aboutAppVersion")
        }
    }
}

/// 备案编号和查询网址放在同一分段、上下相邻：通知要求网址在编号下方。
/// 全是本地常量，不等网络、不看登录态，所有构建内容一致。
struct AppFilingSection: View {
    let mapApprovalNumber: String?

    var body: some View {
        Section {
            DisclosureValueRow(
                title: "App 备案编号",
                value: AppFilingDisclosure.appFilingNumber,
                spellsOutValue: true
            )
            .accessibilityIdentifier("aboutAppFilingNumber")

            // 外链交给系统浏览器，理由见 `LegalDocumentsSection`。
            Link(destination: AppFilingDisclosure.filingQueryURL) {
                Text(AppFilingDisclosure.filingQueryURL.absoluteString)
                    .font(AppFonts.body())
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: AppTouchTarget.blindPrimary, alignment: .leading)
            }
            .accessibilityLabel(AppFilingDisclosure.filingQueryLabel)
            // 语音控制按屏幕上看到的字匹配，读屏标签里没有完整网址。
            .accessibilityInputLabels([
                AppFilingDisclosure.filingQueryLabel,
                AppFilingDisclosure.filingQueryURL.absoluteString
            ])
            .accessibilityHint("在浏览器里打开")
            .accessibilityIdentifier("aboutFilingQueryLink")

            // 地图左下角那行读屏是隐藏的，这里给一份能念的（后端 issue #382）。
            if let mapApprovalNumber {
                DisclosureValueRow(title: "地图审图号", value: mapApprovalNumber, spellsOutValue: true)
                    .accessibilityIdentifier("aboutMapApprovalNumber")
            }
        } header: {
            Text("备案信息")
                .foregroundColor(AppColors.textSecondary)
                .accessibilityAddTraits(.isHeader)
        }
    }
}

struct GenerativeModelDisclosureSection: View {
    var body: some View {
        Section {
            DisclosureValueRow(title: "语音下单使用的大模型", value: AppFilingDisclosure.voiceOrderModelName)
                .accessibilityIdentifier("aboutVoiceOrderModelName")
            DisclosureValueRow(
                title: "大模型备案号",
                value: AppFilingDisclosure.voiceOrderModelFilingNumber,
                spellsOutValue: true
            )
            .accessibilityIdentifier("aboutVoiceOrderModelFilingNumber")
        } header: {
            Text("大模型公示")
                .foregroundColor(AppColors.textSecondary)
                .accessibilityAddTraits(.isHeader)
        }
    }
}

extension View {
    /// 盲人端「我的」的求助条挂在 `NavigationStack` 外层，二级页的 `List` 不会让开它。
    /// 这一页超过一屏后，不留这段空白，最后的「用户协议」就滚不出来。
    ///
    /// ponytail: 固定高度，两端都留。陪跑员端多一段空白无害。#611 删掉求助条时一起删这个方法。
    func aboutPageClearsBlindSOSBar() -> some View {
        safeAreaInset(edge: .bottom) {
            Color.clear
                .frame(height: 96)
                .accessibilityHidden(true)
        }
    }
}

/// 标题在上、取值在下，不用 `LabeledContent`：备案号很长，左右排列时大字号下会被挤成多行窄条。
struct DisclosureValueRow: View {
    let title: String
    let value: String
    var spellsOutValue = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(AppFonts.caption())
                .foregroundColor(AppColors.textSecondary)
            Text(value)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(title)：") + spokenValue)
    }

    /// 编号逐字念，否则 VoiceOver 会把数字段当成一个大数。写法同 `InviteCodeView.codeCard`。
    private var spokenValue: Text {
        spellsOutValue ? Text(value).speechSpellsOutCharacters() : Text(value)
    }
}
