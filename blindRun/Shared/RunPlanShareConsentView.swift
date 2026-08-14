import SwiftUI

/// 首次分享实时位置前的明示告知页。
///
/// **为什么是全屏页而不是对话框**：三条告知必须各自可听、可停、可回头再听。系统对话框的
/// VoiceOver 遍历会把 message 当成一整块念完，用户中途想回到第二条没有着力点；
/// 全屏页里每条是独立焦点，右滑一次一条。这不是排版偏好，是这段文本能不能起到告知作用的差别。
///
/// 之后每次分享走的是 `RunPlanShareConsentCopy.repeatConfirmation*` 的一句话确认，
/// 不再重复全文 —— 每次都念长文本，用户会开始跳过它，那才是真正失去告知效力的时候。
struct RunPlanShareConsentView: View {
    let onAgree: () -> Void
    let onDecline: () -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var actionButtonHeight: CGFloat = 88

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text(RunPlanShareConsentCopy.title)
                    .font(AppFonts.largeTitle())
                    .foregroundColor(AppColors.textPrimary)
                    .accessibilityAddTraits(.isHeader)

                // 三条告知各自成为一个 VoiceOver 焦点。**不要**在这个 VStack 上加
                // `.accessibilityElement(children: .combine)` —— 那会把三条并成一段，
                // 正是本页要避免的东西。
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(RunPlanShareConsentCopy.allDisclosures, id: \.self) { text in
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

                VStack(spacing: 14) {
                    Button(action: onAgree) {
                        Text(RunPlanShareConsentCopy.agreeButtonTitle)
                            .font(AppFonts.title())
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: actionButtonHeight)
                            .background(AppColors.primary)
                            .cornerRadius(16)
                    }
                    .accessibilityLabel(RunPlanShareConsentCopy.agreeButtonTitle)
                    .accessibilityIdentifier("runPlanShareConsentAgreeButton")

                    // 拒绝与同意**同样大**、同样整行铺满。把拒绝做小、做成一行浅色文字，
                    // 对低视力用户就是一个找不到的出口，对读屏用户则是最后才遍历到的东西。
                    Button(action: onDecline) {
                        Text(RunPlanShareConsentCopy.declineButtonTitle)
                            .font(AppFonts.title())
                            .foregroundColor(AppColors.primary)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: actionButtonHeight)
                            .background(AppColors.secondaryBackground)
                            .cornerRadius(16)
                    }
                    .accessibilityLabel(RunPlanShareConsentCopy.declineButtonTitle)
                    .accessibilityIdentifier("runPlanShareConsentDeclineButton")
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 32)
        }
        .background(AppColors.background)
        // `children: .contain` 是必须的：不加的话这个标识符会向下盖到每个子元素上，
        // 子视图自己的 identifier 被吃掉，UI 测试再也找不到那两个按钮。
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("runPlanShareConsentView")
    }
}
