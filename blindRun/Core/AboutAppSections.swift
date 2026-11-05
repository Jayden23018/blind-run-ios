import SwiftUI
import UIKit

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

    /// App 自己的图标，给「关于」页顶部用。
    ///
    /// 资源目录里的 `AppIcon` 不能直接按名字取：编译后它变成安装包里的 `AppIcon60x60` 一类文件，
    /// 名字登记在 Info.plist 的 `CFBundleIcons`。先按登记的名字取，取不到再按目录名试一次；
    /// 都取不到返回 `nil`，页面就不画图标，名字和版本照常显示。
    static func iconImage(info: [String: Any]? = Bundle.main.infoDictionary) -> UIImage? {
        let icons = info?["CFBundleIcons"] as? [String: Any]
        let primary = icons?["CFBundlePrimaryIcon"] as? [String: Any]
        let files = primary?["CFBundleIconFiles"] as? [String] ?? []
        for name in files.reversed() {
            if let image = UIImage(named: name) { return image }
        }
        return UIImage(named: "AppIcon")
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
    static let filingQueryTitle = "工信部备案查询"

    /// 国家网信办 2026-05-13 公告要求公示模型名称和备案号。
    /// 后端换模型或换厂商（`app.voice.llm.model`）时这里要一起改。
    /// 同一家的 `网信算备…` 是算法备案号，不是大模型备案号。
    static let voiceOrderModelName = "通义千问大模型"
    static let voiceOrderModelFilingNumber = "ZheJiang-TongYiQianWen-20230901"
}

// MARK: - Sections

/// 顶部居中：App 图标、名字、版本（定稿 #755，替代原来第一组的两行）。没有白底，直接放在灰底上。
struct AppIdentitySection: View {
    private static let iconSide: CGFloat = 80

    var body: some View {
        Section {
            VStack(spacing: 6) {
                if let icon = AppIdentity.iconImage() {
                    Image(uiImage: icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: Self.iconSide, height: Self.iconSide)
                        .clipShape(RoundedRectangle(cornerRadius: Self.iconSide * 0.225, style: .continuous))
                        .padding(.bottom, 6)
                        .accessibilityHidden(true)
                }
                Text(AppIdentity.name)
                    .font(.title2.weight(.bold))
                    .foregroundColor(AppColors.textPrimary)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("aboutAppName")
                Text(AppIdentity.versionLine())
                    .font(.subheadline)
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .accessibilityIdentifier("aboutAppVersion")
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
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
                spellsOutValue: true,
                layout: .inline
            )
            .accessibilityIdentifier("aboutAppFilingNumber")

            // 外链交给系统浏览器，理由见 `LegalDocumentsSection`。
            // 定稿 #755：蓝字「工信部备案查询」+ 箭头；网址仍显示在下面一行，通知要求网址在编号下方。
            Link(destination: AppFilingDisclosure.filingQueryURL) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(AppFilingDisclosure.filingQueryTitle)
                            .font(AppFonts.body())
                            .foregroundColor(AppColors.primary)
                        Text(AppFilingDisclosure.filingQueryURL.absoluteString)
                            .font(.subheadline)
                            .foregroundColor(AppColors.textSecondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    SettingsChevron()
                }
                .frame(maxWidth: .infinity, minHeight: AppTouchTarget.blindPrimary, alignment: .leading)
                .contentShape(Rectangle())
            }
            .accessibilityLabel(AppFilingDisclosure.filingQueryLabel)
            // 语音控制按屏幕上看到的字匹配，读屏标签里没有完整网址。
            .accessibilityInputLabels([
                AppFilingDisclosure.filingQueryLabel,
                AppFilingDisclosure.filingQueryTitle,
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
            DisclosureValueRow(
                title: "语音下单使用的大模型",
                value: AppFilingDisclosure.voiceOrderModelName,
                layout: .inline
            )
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

/// 公示的一行，两种排法（定稿 #755）：
/// - `.stacked`：名在上、值在下。长的值（地图审图号、大模型备案号）用它，大字号下也不截短。
/// - `.inline`：名在左、值在右；大字号下改上下排（`AdaptiveHStack`），值照样换行不截短。
///
/// 不用 `LabeledContent`：备案号很长，左右排列时大字号下会被挤成多行窄条。
struct DisclosureValueRow: View {
    enum Layout {
        case stacked
        case inline
    }

    let title: String
    let value: String
    var spellsOutValue = false
    var layout: Layout = .stacked

    var body: some View {
        content
            .padding(.vertical, 4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(title)：") + spokenValue)
    }

    @ViewBuilder
    private var content: some View {
        switch layout {
        case .stacked:
            VStack(alignment: .leading, spacing: 4) {
                titleText
                Text(value)
                    .font(.subheadline)
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .inline:
            AdaptiveHStack(spacing: 8) {
                titleText
                Spacer(minLength: 8)
                Text(value)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var titleText: some View {
        Text(title)
            .font(AppFonts.body())
            .foregroundColor(AppColors.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// 编号逐字念，否则 VoiceOver 会把数字段当成一个大数。写法同 `InviteCodeView.codeCard`。
    private var spokenValue: Text {
        spellsOutValue ? Text(value).speechSpellsOutCharacters() : Text(value)
    }
}
