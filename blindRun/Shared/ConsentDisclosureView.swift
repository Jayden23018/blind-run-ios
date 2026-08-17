import SwiftUI

/// 明示告知页的通用形态：标题 + 逐条告知 + 同意 / 拒绝两个等大按钮。
///
/// **为什么是全屏页而不是对话框**：每条告知必须各自可听、可停、可回头再听。系统对话框的
/// VoiceOver 遍历会把 message 当成一整块念完，用户中途想回到第二条没有着力点；
/// 全屏页里每条是独立焦点，右滑一次一条。这不是排版偏好，是这段文本能不能起到告知作用的差别。
///
/// 三个调用方共用这一个实现（行程分享、首次启动、两端实名认证）：告知页的排版规则是合规约束，
/// 复制三份意味着改一处时另外两处会静默漂移。
struct ConsentDisclosureView<Footer: View>: View {
    let title: String
    let disclosures: [String]
    let agreeButtonTitle: String
    let declineButtonTitle: String
    /// 用于 UI 测试定位。三个 identifier 同源，避免调用方各拼各的。
    let identifierPrefix: String
    let onAgree: () -> Void
    let onDecline: () -> Void
    @ViewBuilder let footer: () -> Footer

    @ScaledMetric(relativeTo: .largeTitle) private var actionButtonHeight: CGFloat = 88

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text(title)
                    .font(AppFonts.largeTitle())
                    .foregroundColor(AppColors.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                // 每条告知各自成为一个 VoiceOver 焦点。**不要**在这个 VStack 上加
                // `.accessibilityElement(children: .combine)` —— 那会把它们并成一段，
                // 正是本页要避免的东西。
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(disclosures, id: \.self) { text in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            // 装饰性圆点：对读屏隐藏，避免每条前面多念一次「圆点」。
                            Circle()
                                .fill(AppColors.primary)
                                .frame(width: 10, height: 10)
                                .accessibilityHidden(true)
                            Text(text)
                                .font(AppFonts.title())
                                .foregroundColor(AppColors.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                footer()

                VStack(spacing: 14) {
                    Button(action: onAgree) {
                        Text(agreeButtonTitle)
                            .font(AppFonts.title())
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: actionButtonHeight)
                            .background(AppColors.primary)
                            .cornerRadius(16)
                    }
                    .accessibilityLabel(agreeButtonTitle)
                    .accessibilityIdentifier("\(identifierPrefix)AgreeButton")

                    // 拒绝与同意**同样大**、同样整行铺满。把拒绝做小、做成一行浅色文字，
                    // 对低视力用户就是一个找不到的出口，对读屏用户则是最后才遍历到的东西。
                    Button(action: onDecline) {
                        Text(declineButtonTitle)
                            .font(AppFonts.title())
                            .foregroundColor(AppColors.primary)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: actionButtonHeight)
                            .background(AppColors.secondaryBackground)
                            .cornerRadius(16)
                    }
                    .accessibilityLabel(declineButtonTitle)
                    .accessibilityIdentifier("\(identifierPrefix)DeclineButton")
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 32)
            // iPad / 横屏上不限宽的话，字调大之后仍要横扫整行，换行极易串行。
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .background(AppColors.background)
        // `children: .contain` 是必须的：不加的话这个标识符会向下盖到每个子元素上，
        // 子视图自己的 identifier 被吃掉，UI 测试再也找不到那两个按钮。
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("\(identifierPrefix)View")
    }
}

extension ConsentDisclosureView where Footer == EmptyView {
    init(
        title: String,
        disclosures: [String],
        agreeButtonTitle: String,
        declineButtonTitle: String,
        identifierPrefix: String,
        onAgree: @escaping () -> Void,
        onDecline: @escaping () -> Void
    ) {
        self.init(
            title: title,
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
            disclosures: purpose.disclosures,
            agreeButtonTitle: purpose.agreeButtonTitle,
            declineButtonTitle: purpose.declineButtonTitle,
            identifierPrefix: "\(purpose.rawValue)Consent",
            onAgree: onAgree,
            onDecline: onDecline
        )
    }
}
