import SwiftUI

/// 单独同意的通用形态：压暗背景上的**居中小弹窗** —— 标题 + 一两句摘要 + 可展开的「详细说明」+
/// 上「同意」下「不同意」两个整行铺满的按钮（#776 起上下排，照系统弹窗）。
///
/// 位置轨迹的同意不用这个：它排在系统定位框前面，按 HIG 用 `LocationTrackPreAlertView`（#776）。
///
/// 2026-11-05 由整页逐条告知改成小弹窗（#769）。负责人真机体验后的原话是「每做一步就需要同意一次」
/// 「展示的形式和市面上主流的 app 也不一样」。调研（`docs/research/consent-forms-mainstream-20261105.md`）
/// 的结论：法规与国标要求的是「先告知、明示同意、不默认勾选、不打包、拒绝后不频繁再问」，
/// **没有要求整页逐条告知**；小弹窗或表单底部勾选框都站得住。
///
/// 完整告知原文（`disclosures`）没有删：收在「详细说明」里，展开后每条仍是独立的读屏焦点。
/// 摘要只能点名 `disclosures` 里已有的处理行为，不能引入新内容。
///
/// 弹窗放在调用方给的容器里（`fullScreenCover`、导航页或根视图 `overlay`），这里只画压暗背景和卡片。
/// 背景对读屏隐藏，卡片标 `isModal`，焦点只在卡片内。
struct ConsentDisclosureView<Footer: View>: View {
    let title: String
    /// 卡片正文。为 nil 时正文直接列出 `disclosures`（行程分享那种本来就只有三句短话的告知）。
    let summary: String?
    let disclosures: [String]
    let agreeButtonTitle: String
    let declineButtonTitle: String
    /// 用于 UI 测试定位。三个 identifier 同源，避免调用方各拼各的。
    let identifierPrefix: String
    let onAgree: () -> Void
    let onDecline: () -> Void
    @ViewBuilder let footer: () -> Footer

    @State private var showsDetails = false
    @State private var cardHeight: CGFloat = 320

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .accessibilityHidden(true)
            GeometryReader { geo in
                card(maxHeight: geo.size.height * 0.85)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .consentPopupClearPresentationBackground()
        // `children: .contain` 是必须的：不加的话这个标识符会向下盖到每个子元素上，
        // 子视图自己的 identifier 被吃掉，UI 测试再也找不到那两个按钮。
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("\(identifierPrefix)View")
    }

    // MARK: - Card

    private func card(maxHeight: CGFloat) -> some View {
        // 高度 = min(内容高度, 屏高 85%)：常规字号下卡片就是内容那么高；
        // 辅助功能字号或展开详细说明后封顶，在卡片内滚动。
        ScrollView {
            VStack(spacing: 16) {
                Text(title)
                    .font(AppFonts.title().weight(.bold))
                    .foregroundColor(AppColors.textPrimary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .accessibilityAddTraits(.isHeader)

                VStack(alignment: .leading, spacing: 8) {
                    if let summary {
                        Text(summary)
                            .font(AppFonts.body())
                            .foregroundColor(AppColors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        detailsToggle
                        if showsDetails {
                            disclosureList
                        }
                    } else {
                        disclosureList
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                footer()

                actions
            }
            .padding(20)
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(key: ConsentCardHeightKey.self, value: proxy.size.height)
                }
            )
        }
        .onPreferenceChange(ConsentCardHeightKey.self) { cardHeight = $0 }
        .frame(height: min(cardHeight, maxHeight))
        .background(AppColors.background)
        .cornerRadius(20)
        .frame(maxWidth: 420)
        .padding(.horizontal, 28)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("\(identifierPrefix)Popup")
    }

    private var detailsToggle: some View {
        Button {
            showsDetails.toggle()
        } label: {
            Text(showsDetails ? "收起详细说明" : "查看详细说明")
                .font(AppFonts.body().weight(.semibold))
                .foregroundColor(AppColors.primary)
                .frame(maxWidth: .infinity, minHeight: AppTouchTarget.blindPrimary, alignment: .leading)
                .contentShape(Rectangle())
        }
        .accessibilityHint(showsDetails ? "收起逐条说明" : "逐条展开我们会怎么使用这些信息")
        .accessibilityIdentifier("\(identifierPrefix)DetailsToggle")
    }

    /// 每条告知各自成为一个读屏焦点。**不要**在这个 VStack 上加
    /// `.accessibilityElement(children: .combine)` —— 那会把它们并成一段念完，用户回不去第二条。
    private var disclosureList: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(disclosures, id: \.self) { text in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("·")
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.textSecondary)
                        .accessibilityHidden(true)
                    Text(text)
                        .font(summary == nil ? AppFonts.body() : .callout)
                        .foregroundColor(summary == nil ? AppColors.textPrimary : AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Actions

    /// 上「同意」下「不同意」，都整行铺满（#776）：一样宽，把拒绝做小是在用视觉权重替用户做决定。
    private var actions: some View {
        VStack(spacing: 0) { agreeButton; declineButton }
    }

    private var agreeButton: some View {
        Button(agreeButtonTitle, action: onAgree)
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityLabel(agreeButtonTitle)
            .accessibilityIdentifier("\(identifierPrefix)AgreeButton")
    }

    private var declineButton: some View {
        Button(declineButtonTitle, action: onDecline)
            .buttonStyle(NeutralButtonStyle())
            .accessibilityLabel(declineButtonTitle)
            .accessibilityIdentifier("\(identifierPrefix)DeclineButton")
    }
}

private struct ConsentCardHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private extension View {
    /// 放在 `fullScreenCover` 里时让背后的页面透出来，看起来就是一个弹窗。
    /// iOS 16.4 以下没有这个 API，退化为压暗的纯色底，按钮和文字不受影响。
    @ViewBuilder
    func consentPopupClearPresentationBackground() -> some View {
        if #available(iOS 16.4, *) {
            presentationBackground(.clear)
        } else {
            self
        }
    }
}

extension ConsentDisclosureView where Footer == EmptyView {
    init(
        title: String,
        summary: String? = nil,
        disclosures: [String],
        agreeButtonTitle: String,
        declineButtonTitle: String,
        identifierPrefix: String,
        onAgree: @escaping () -> Void,
        onDecline: @escaping () -> Void
    ) {
        self.init(
            title: title,
            summary: summary,
            disclosures: disclosures,
            agreeButtonTitle: agreeButtonTitle,
            declineButtonTitle: declineButtonTitle,
            identifierPrefix: identifierPrefix,
            onAgree: onAgree,
            onDecline: onDecline,
            footer: { EmptyView() }
        )
    }

    /// 需要单独同意的处理目的（PIPL 第 29 条）共用的入口：文案全部取自 `PrivacyConsentPurpose`，
    /// 调用方不许在 View 里另写一份 —— 文案是被单测钉住的合规文本。
    init(
        purpose: PrivacyConsentPurpose,
        onAgree: @escaping () -> Void,
        onDecline: @escaping () -> Void
    ) {
        self.init(
            title: purpose.title,
            summary: purpose.popupSummary,
            disclosures: purpose.disclosures,
            agreeButtonTitle: purpose.agreeButtonTitle,
            declineButtonTitle: purpose.declineButtonTitle,
            identifierPrefix: "\(purpose.rawValue)Consent",
            onAgree: onAgree,
            onDecline: onDecline
        )
    }
}
