import SwiftUI

/// 首次分享实时位置前的明示告知页。
///
/// 排版规则（全屏、每条独立焦点、拒绝与同意等大）已收进 `ConsentDisclosureView`，
/// 与首次启动告知、两端实名认证共用同一个实现 —— 三份复制品会在改一处时静默漂移。
/// 这里只保留本页特有的东西：文案来源，以及 UI 测试依赖的三个 identifier。
///
/// 之后每次分享走的是 `RunPlanShareConsentCopy.repeatConfirmation*` 的一句话确认，
/// 不再重复全文 —— 每次都念长文本，用户会开始跳过它，那才是真正失去告知效力的时候。
struct RunPlanShareConsentView: View {
    let onAgree: () -> Void
    let onDecline: () -> Void

    var body: some View {
        ConsentDisclosureView(
            title: RunPlanShareConsentCopy.title,
            disclosures: RunPlanShareConsentCopy.allDisclosures,
            agreeButtonTitle: RunPlanShareConsentCopy.agreeButtonTitle,
            declineButtonTitle: RunPlanShareConsentCopy.declineButtonTitle,
            // 前缀拼出的正是原来那三个 identifier（...View / ...AgreeButton / ...DeclineButton），
            // 改动它会让已有 UI 用例找不到按钮。
            identifierPrefix: "runPlanShareConsent",
            onAgree: onAgree,
            onDecline: onDecline
        )
    }
}
