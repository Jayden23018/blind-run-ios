import SwiftUI

/// 首次启动的告知与同意页。**在登录之前**，是 App 里第一个可见的界面。
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
/// **形态（issue #277）**：一段摘要 + 入口 + 常驻在底部的同意 / 不同意，与常规 App 一致。
/// 此前整页摊开 6 条、按钮排在最底下。6 条完整告知原文不变，挪到二级页「完整收集清单」
/// （`disclosures` 仍是合规文本的唯一来源）。辅助功能字号下底部栏会吃掉大半屏，
/// 那一档退回到内容末尾内联 —— 否则正文只剩一条缝。
struct PrivacyConsentGateView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// 按下「先不同意」后的说明。**留在本页**，不退出 App ——
    /// 退出对看不见屏幕的人是「App 坏了」，而拒绝本身是一个合法选择，
    /// 他需要的是一条能回头的路（看全文、再决定）。
    @State private var declineNotice: String?

    @ScaledMetric(relativeTo: .title) private var actionButtonHeight: CGFloat = 64

    private let purpose = PrivacyConsentPurpose.appLaunch

    private var pinsActions: Bool { !dynamicTypeSize.isAccessibilitySize }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(purpose.title)
                        .font(AppFonts.largeTitle())
                        .foregroundColor(AppColors.textPrimary)
                        .accessibilityAddTraits(.isHeader)

                    if let summary = purpose.launchSummary {
                        Text(summary)
                            .font(AppFonts.body())
                            .foregroundColor(AppColors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    linkCard

                    // 辅助功能字号：底部栏不常驻，按钮内联在内容末尾。
                    if !pinsActions {
                        actionBar
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 32)
                // iPad / 横屏上不限宽的话，字调大之后仍要横扫整行，换行极易串行。
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
            }
            .background(AppColors.background)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if pinsActions {
                    actionBar
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .frame(maxWidth: 700)
                        .frame(maxWidth: .infinity)
                        .background(AppColors.background)
                }
            }
            // `children: .contain` 是必须的：不加的话这个标识符会向下盖到每个子元素上，
            // 子视图自己的 identifier 被吃掉，UI 测试再也找不到那两个按钮。
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("\(purpose.rawValue)ConsentView")
            .navigationTitle("隐私说明")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            // 外链地址免鉴权、拉一次；拿不到就走内置全文，两条分支都保证「可点且有内容」。
            await appState.loadLegalLinksIfNeeded()
            speak()
        }
    }

    // MARK: - Link card

    /// 摘要下面的入口：完整收集清单、两份全文、再听一遍。**一张卡、四行**，
    /// 每行 ≥ 64pt（盲人端触达下限），不是四个各自带底色的大块。
    private var linkCard: some View {
        VStack(spacing: 0) {
            NavigationLink {
                LegalFallbackDocumentView(document: Self.fullDisclosureDocument(for: purpose), footer: { EmptyView() })
            } label: {
                linkRowLabel("查看完整收集清单")
            }
            .accessibilityLabel("查看完整收集清单")
            .accessibilityHint("逐条查看我们会收集哪些信息")
            .accessibilityIdentifier("appLaunchConsentFullListLink")

            ForEach(LegalDocumentKind.allCases) { kind in
                Divider()
                legalRow(kind)
            }

            Divider()
            // 与首次引导页同一个理由：一次性播报漏听就再也拿不回来。
            Button(action: speak) {
                HStack {
                    Text("再听一遍")
                        .font(AppFonts.body().weight(.semibold))
                        .foregroundColor(AppColors.primary)
                    Spacer(minLength: 8)
                    Image(systemName: "speaker.wave.2")
                        .foregroundColor(AppColors.textSecondary)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: 64)
                .contentShape(Rectangle())
            }
            .accessibilityLabel("再听一遍")
            .accessibilityHint("从头重新播报这段隐私说明")
            .accessibilityIdentifier("appLaunchConsentRepeatButton")
        }
        .background(AppColors.secondaryBackground)
        .cornerRadius(12)
    }

    @ViewBuilder
    private func legalRow(_ kind: LegalDocumentKind) -> some View {
        let title = "\(kind.title)全文"
        switch kind.destination(in: appState.legalLinks) {
        case .remote(let url):
            // 外链交给系统浏览器，理由见 `LegalDocumentsSection`：应用内 WebView 的失败态是空白页。
            Link(destination: url) {
                linkRowLabel(title)
            }
            .accessibilityLabel(title)
            .accessibilityHint("在浏览器中打开\(kind.title)")
        case .builtInFallback:
            NavigationLink {
                LegalFallbackDocumentView(kind: kind)
            } label: {
                linkRowLabel(title)
            }
            .accessibilityLabel(title)
            .accessibilityHint("查看\(kind.title)")
        }
    }

    private func linkRowLabel(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(AppFonts.body().weight(.semibold))
                .foregroundColor(AppColors.primary)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .foregroundColor(AppColors.textSecondary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 64)
        .contentShape(Rectangle())
    }

    // MARK: - Actions

    /// 同意 / 先不同意。**同样大、同样整行铺满**：把拒绝做小是在用视觉权重替用户做决定，
    /// 而这里的用户看不见视觉权重（理由见 `RunPlanShareConsentView`）。
    /// 拒绝后的说明放在按钮正上方 —— 底部栏常驻时放进滚动区会被推到屏外。
    private var actionBar: some View {
        VStack(spacing: 12) {
            if let declineNotice {
                Text(declineNotice)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.destructive)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(declineNotice)
                    .accessibilityIdentifier("appLaunchConsentDeclineNotice")
            }

            Button(action: { appState.acceptPrivacyConsent() }) {
                Text(purpose.agreeButtonTitle)
                    .font(AppFonts.title())
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: actionButtonHeight)
                    .background(AppColors.primary)
                    .cornerRadius(16)
            }
            .accessibilityLabel(purpose.agreeButtonTitle)
            .accessibilityIdentifier("appLaunchConsentAgreeButton")

            Button(action: decline) {
                Text(purpose.declineButtonTitle)
                    .font(AppFonts.title())
                    .foregroundColor(AppColors.primary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: actionButtonHeight)
                    .background(AppColors.secondaryBackground)
                    .cornerRadius(16)
            }
            .accessibilityLabel(purpose.declineButtonTitle)
            .accessibilityIdentifier("appLaunchConsentDeclineButton")
        }
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

#if DEBUG
#Preview {
    PrivacyConsentGateView()
        .environmentObject(AppState())
        .environmentObject(SpeechService())
}
#endif
