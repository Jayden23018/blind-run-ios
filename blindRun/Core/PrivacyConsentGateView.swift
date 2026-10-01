import SwiftUI

/// 首次启动的告知与同意弹窗。**在登录之前**，是 App 里第一个可见的界面。
///
/// 为什么必须有：PIPL 第 14 条要求「充分告知后取得同意」，中国区应用商店与工信部检测都把
/// 「首次运行未经同意即开始收集」列为违规项；App Store 审核 5.1.1 同样要求收集前取得同意。
/// 此前这个 App 的隐私政策只在「设置 → 关于」里可读，**没有任何一步征求过同意** ——
/// 入口存在不等于同意存在，这两件事在合规上是分开的。
///
/// 敏感项（身份证号、人脸、行踪轨迹）**不靠这一页解决**：PIPL 第 29 条要的是单独同意，
/// 一次概括同意覆盖不了它们。这一页只做整体告知，并明说「到那一步会再单独问一次」；
/// 真正的单独同意在实名认证页和行程分享页。
///
/// **形态（issue #277）**：与常规 App 一致的**居中卡片弹窗** —— 压暗的背景 + 标题 + 一段摘要 +
/// 隐私政策 / 用户协议 / 完整清单入口 + 左「不同意」右「同意」。不是整页。
/// 背后只放品牌底板，**不渲染登录页**：手机号是个人信息，同意之前登录页不许出现。
/// 7 条完整告知原文不变（`disclosures` 仍是合规文本的唯一来源），放在二级页「完整收集清单」。
///
/// 无障碍三处取舍：
/// - 两个按钮常规字号**左右并排**（左拒右同意，与常规 App 一致）、大小相同；辅助功能字号退回竖排，
///   否则一行放不下两个按钮的字。不用 `ViewThatFits`（本仓库已知它会让整页被审计判成改不了字号）。
/// - 所有可点控件 ≥ 64pt（盲人端触达下限）；为了不把弹窗撑成整页，入口两两并排成两行。
/// - 弹窗标 `isModal`，背景对读屏隐藏，焦点只在卡片内。
struct PrivacyConsentGateView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// 按下「先不同意」后的说明。**留在本页**，不退出 App ——
    /// 退出对看不见屏幕的人是「App 坏了」，而拒绝本身是一个合法选择，
    /// 他需要的是一条能回头的路（看全文、再决定）。
    @State private var declineNotice: String?
    @State private var cardHeight: CGFloat = 400

    @ScaledMetric(relativeTo: .body) private var touchHeight: CGFloat = 64

    private let purpose = PrivacyConsentPurpose.appLaunch

    private var stacksActions: Bool { dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        NavigationStack {
            ZStack {
                backdrop
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
                GeometryReader { geo in
                    popup(maxHeight: geo.size.height * 0.85)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            // `children: .contain` 是必须的：不加的话这个标识符会向下盖到每个子元素上，
            // 子视图自己的 identifier 被吃掉，UI 测试再也找不到那两个按钮。
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("\(purpose.rawValue)ConsentView")
            .toolbar(.hidden, for: .navigationBar)
        }
        .task {
            // 外链地址免鉴权、拉一次；拿不到就走内置全文，两条分支都保证「可点且有内容」。
            await appState.loadLegalLinksIfNeeded()
            speak()
        }
    }

    // MARK: - Backdrop

    /// 弹窗背后的底板：只有品牌名。**不是登录页** —— 同意之前任何会收集信息的界面都不许出现。
    private var backdrop: some View {
        AppColors.background
            .ignoresSafeArea()
            .overlay(
                Text("助盲跑")
                    .font(AppFonts.largeTitle())
                    .foregroundColor(AppColors.textPrimary)
            )
            .accessibilityHidden(true)
    }

    // MARK: - Popup

    private func popup(maxHeight: CGFloat) -> some View {
        // 整张卡的内容放进同一个 ScrollView，高度 = min(内容高度, 屏高 85%)：
        // 常规字号下内容装得下，卡片就是内容那么高、不滚动；辅助功能字号下卡片封顶，在卡片内滚动。
        // （曾只让正文滚、按钮钉在卡底 —— 最大字号下两个竖排按钮自己就超过半屏，卡片整个冲出屏幕。）
        ScrollView {
            VStack(spacing: 16) {
                Text(purpose.launchTitle ?? purpose.title)
                    .font(AppFonts.title().weight(.bold))
                    .foregroundColor(AppColors.textPrimary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .accessibilityAddTraits(.isHeader)

                VStack(alignment: .leading, spacing: 8) {
                    if let summary = purpose.launchSummary {
                        Text(summary)
                            .font(AppFonts.body())
                            .foregroundColor(AppColors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    links
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let declineNotice {
                    Text(declineNotice)
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.destructive)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel(declineNotice)
                        .accessibilityIdentifier("appLaunchConsentDeclineNotice")
                }

                actions
            }
            .padding(20)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: BodyHeightKey.self, value: proxy.size.height)
                }
            )
        }
        .onPreferenceChange(BodyHeightKey.self) { cardHeight = $0 }
        .frame(height: min(cardHeight, maxHeight))
        .background(AppColors.background)
        .cornerRadius(20)
        .frame(maxWidth: 420)
        .padding(.horizontal, 28)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("appLaunchConsentPopup")
    }

    // MARK: - Links

    /// 弹窗里的入口，两两并排成两行：《隐私政策》《用户协议》 / 完整收集清单、再听一遍。
    /// 每个是独立的读屏焦点（而不是一段文字里的内联链接 —— 内联链接要靠转子才找得到，
    /// 对读屏用户等于藏起来）。辅助功能字号下竖排。
    private var links: some View {
        VStack(alignment: .leading, spacing: 0) {
            rowOfTwo {
                ForEach(LegalDocumentKind.allCases) { kind in
                    legalLink(kind)
                }
            }
            rowOfTwo {
                NavigationLink {
                    LegalFallbackDocumentView(
                        document: Self.fullDisclosureDocument(for: purpose),
                        footer: { EmptyView() }
                    )
                } label: {
                    linkLabel("完整收集清单")
                }
                .accessibilityLabel("查看完整收集清单")
                .accessibilityHint("逐条查看我们会收集哪些信息")
                .accessibilityIdentifier("appLaunchConsentFullListLink")

                // 与首次引导页同一个理由：一次性播报漏听就再也拿不回来。
                Button(action: speak) {
                    linkLabel("再听一遍")
                }
                .accessibilityLabel("再听一遍")
                .accessibilityHint("从头重新播报这段隐私说明")
                .accessibilityIdentifier("appLaunchConsentRepeatButton")
            }
        }
    }

    @ViewBuilder
    private func rowOfTwo<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if stacksActions {
            VStack(alignment: .leading, spacing: 0) { content() }
        } else {
            HStack(spacing: 12) { content() }
        }
    }

    @ViewBuilder
    private func legalLink(_ kind: LegalDocumentKind) -> some View {
        let title = "《\(kind.title)》"
        switch kind.destination(in: appState.legalLinks) {
        case .remote(let url):
            // 外链交给系统浏览器，理由见 `LegalDocumentsSection`：应用内 WebView 的失败态是空白页。
            Link(destination: url) {
                linkLabel(title)
            }
            .accessibilityLabel("\(kind.title)全文")
            .accessibilityHint("在浏览器中打开\(kind.title)")
        case .builtInFallback:
            NavigationLink {
                LegalFallbackDocumentView(kind: kind)
            } label: {
                linkLabel(title)
            }
            .accessibilityLabel("\(kind.title)全文")
            .accessibilityHint("查看\(kind.title)")
        }
    }

    private func linkLabel(_ text: String) -> some View {
        Text(text)
            .font(AppFonts.body().weight(.semibold))
            .foregroundColor(AppColors.primary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, minHeight: touchHeight, alignment: .leading)
            .contentShape(Rectangle())
    }

    // MARK: - Actions

    /// 左「先不同意」右「同意并开始使用」，**同样大**：把拒绝做小是在用视觉权重替用户做决定，
    /// 而这里的用户看不见视觉权重（理由见 `RunPlanShareConsentView`）。
    @ViewBuilder
    private var actions: some View {
        if stacksActions {
            VStack(spacing: 12) { declineButton; agreeButton }
        } else {
            HStack(spacing: 12) { declineButton; agreeButton }
        }
    }

    private var declineButton: some View {
        Button(action: decline) {
            Text(purpose.declineButtonTitle)
                .font(AppFonts.body().weight(.semibold))
                .foregroundColor(AppColors.primary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: touchHeight)
                .background(AppColors.secondaryBackground)
                .cornerRadius(12)
        }
        .accessibilityLabel(purpose.declineButtonTitle)
        .accessibilityIdentifier("appLaunchConsentDeclineButton")
    }

    private var agreeButton: some View {
        Button(action: { appState.acceptPrivacyConsent() }) {
            Text(purpose.agreeButtonTitle)
                .font(AppFonts.body().weight(.semibold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, minHeight: touchHeight)
                .background(AppColors.primary)
                .cornerRadius(12)
        }
        .accessibilityLabel(purpose.agreeButtonTitle)
        .accessibilityIdentifier("appLaunchConsentAgreeButton")
    }

    private func decline() {
        declineNotice = purpose.declinedFeedback
        speechService.speak(purpose.declinedFeedback)
    }

    private func speak() {
        speechService.speak(text: purpose.launchSpokenScript)
    }

    /// 二级页「完整收集清单」：`disclosures` 原文逐条成行，不改一个字。
    static func fullDisclosureDocument(for purpose: PrivacyConsentPurpose) -> LegalFallbackCopy.Document {
        LegalFallbackCopy.Document(
            title: "完整收集清单",
            notice: "以下是首次使用前我们需要告知你的全部内容。看完回到上一页再选择同意或不同意。",
            sections: [
                LegalFallbackCopy.Section(heading: "我们会收集和使用什么", bullets: purpose.disclosures)
            ]
        )
    }
}

private struct BodyHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

#if DEBUG
#Preview {
    PrivacyConsentGateView()
        .environmentObject(AppState())
        .environmentObject(SpeechService())
}
#endif
