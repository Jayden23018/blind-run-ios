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
struct PrivacyConsentGateView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService

    /// 按下「先不同意」后的说明。**留在本页**，不退出 App ——
    /// 退出对看不见屏幕的人是「App 坏了」，而拒绝本身是一个合法选择，
    /// 他需要的是一条能回头的路（看全文、再决定）。
    @State private var declineNotice: String?

    private let purpose = PrivacyConsentPurpose.appLaunch

    var body: some View {
        NavigationStack {
            ConsentDisclosureView(
                title: purpose.title,
                disclosures: purpose.disclosures,
                agreeButtonTitle: purpose.agreeButtonTitle,
                declineButtonTitle: purpose.declineButtonTitle,
                identifierPrefix: "\(purpose.rawValue)Consent",
                onAgree: {
                    appState.acceptPrivacyConsent()
                },
                onDecline: {
                    declineNotice = purpose.declinedFeedback
                    speechService.speak(purpose.declinedFeedback)
                },
                footer: { footer }
            )
            .navigationTitle("隐私说明")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            // 外链地址免鉴权、拉一次；拿不到就走内置全文，两条分支都保证「可点且有内容」。
            await appState.loadLegalLinksIfNeeded()
            speak()
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let declineNotice {
                Text(declineNotice)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.destructive)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(declineNotice)
                    .accessibilityIdentifier("appLaunchConsentDeclineNotice")
            }

            // 与首次引导页同一个理由：一次性播报漏听就再也拿不回来。
            Button("再听一遍") { speak() }
                .font(AppFonts.body().weight(.semibold))
                .foregroundColor(AppColors.primary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 64)
                .background(AppColors.secondaryBackground)
                .cornerRadius(12)
                .accessibilityLabel("再听一遍")
                .accessibilityHint("从头重新播报这段隐私说明")
                .accessibilityIdentifier("appLaunchConsentRepeatButton")

            ForEach(LegalDocumentKind.allCases) { kind in
                legalRow(kind)
            }
        }
    }

    @ViewBuilder
    private func legalRow(_ kind: LegalDocumentKind) -> some View {
        let title = "\(kind.title)全文"
        switch kind.destination(in: appState.legalLinks) {
        case .remote(let url):
            // 外链交给系统浏览器，理由见 `LegalDocumentsSection`：应用内 WebView 的失败态是空白页。
            Link(destination: url) {
                legalRowLabel(title)
            }
            .accessibilityLabel(title)
            .accessibilityHint("在浏览器中打开\(kind.title)")
        case .builtInFallback:
            NavigationLink {
                LegalFallbackDocumentView(kind: kind)
            } label: {
                legalRowLabel(title)
            }
            .accessibilityLabel(title)
            .accessibilityHint("查看\(kind.title)")
        }
    }

    private func legalRowLabel(_ title: String) -> some View {
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
        .background(AppColors.secondaryBackground)
        .cornerRadius(12)
    }

    private func speak() {
        speechService.speak(text: purpose.spokenScript)
    }
}

#if DEBUG
#Preview {
    PrivacyConsentGateView()
        .environmentObject(AppState())
        .environmentObject(SpeechService())
}
#endif
