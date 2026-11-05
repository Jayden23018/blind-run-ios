import SwiftUI

extension BlindOrderStatusView {
    /// 把这次行程告诉家人。主路径是**实时分享**（后端生成免登录链接，家属能看到位置与轨迹），
    /// 短信是它失败时的降级路径。
    ///
    /// 排在主动作与 `actionSection` 之后、地图之前：它是**附属**动作（不该抢 140pt 的主按钮
    /// 版位，也不该排在「取消订单」这种状态机动作前面），但也不能沉到订单信息下面 ——
    /// 看不见屏幕的人靠遍历顺序发现功能存在，沉下去等于没做。样式用整行铺满的次级按钮，与
    /// `docs/research/blind-ui-visual-benchmark-20260808.md` 那条「次级操作一律整行铺满
    /// 竖直堆叠」一致。
    ///
    /// 终态整段消失（`offersRunPlanShare`），不是禁用：后端对终态返 409，
    /// 摆一个按下去必然报错的按钮，对读屏用户是纯噪音。
    @ViewBuilder
    func runPlanShareSection(_ order: OrderDetailResponse) -> some View {
        if order.status.offersRunPlanShare {
            VStack(spacing: 10) {
                if shareViewModel.isLiveSharing {
                    runPlanShareButton(
                        title: RunPlanLiveShareCopy.stopButtonTitle,
                        hint: RunPlanLiveShareCopy.stopAccessibilityHint,
                        identifier: "blindOrderStatusStopLiveShareButton",
                        tint: AppColors.destructive,
                        action: { Task { await shareViewModel.stopLiveShare() } }
                    )
                } else {
                    runPlanShareButton(
                        title: RunPlanLiveShareCopy.buttonTitle,
                        hint: RunPlanLiveShareCopy.accessibilityHint,
                        identifier: "blindOrderStatusLiveShareButton",
                        tint: AppColors.primary,
                        action: { requestLiveShare() }
                    )
                }

                // 只在实时分享走不通时露出来。`canSendText` 一并判掉：这台设备本来就发不了短信时
                // 摆出降级入口，等于把用户支上一条同样走不通的路。
                if shareViewModel.showSMSFallback, MessageComposeSheet.canSendText {
                    runPlanShareButton(
                        title: RunPlanLiveShareCopy.smsFallbackButtonTitle,
                        hint: RunPlanLiveShareCopy.smsFallbackHint,
                        identifier: "blindOrderStatusShareRunPlanButton",
                        tint: AppColors.primary,
                        action: { shareRunPlanBySMS(order) }
                    )
                }

                if let notice = shareViewModel.notice {
                    Text(notice.text)
                        .font(AppFonts.body())
                        .foregroundColor(notice.isProblem ? AppColors.destructive : AppColors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel(notice.text)
                        .accessibilityIdentifier("blindOrderStatusShareRunPlanNotice")
                }
            }
        }
    }

    func runPlanShareButton(
        title: String,
        hint: String,
        identifier: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(AppFonts.title())
                .foregroundColor(tint)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 64)
                .background(AppColors.secondaryBackground)
                .cornerRadius(16)
        }
        .disabled(shareViewModel.isWorking)
        .accessibilityLabel(title)
        .accessibilityHint(hint)
        .accessibilityIdentifier(identifier)
    }

    // MARK: - Live share

    var consentStore: RunPlanShareConsentStore {
        RunPlanShareConsentStore(persistence: appState.persistence)
    }

    /// 同意按**用户**存。未登录拿不到 userId 时用一个恒不命中的 key，效果是每次都走全屏告知 ——
    /// 这条路正常走不到（这一页在登录后才可达），宁可多告知一次也不要让一个空 key
    /// 被所有账号共用。
    var consentUserKey: String {
        appState.currentUser.map { String($0.userId) } ?? "anonymous"
    }

    /// 按下分享：先过明示同意这道门。**不许直接发请求** ——
    /// 调 `POST /api/orders/{id}/share` 本身就等同于盲人对「向持链接者提供实时位置与轨迹」
    /// 作出单独同意（PIPL 第 23/29 条，轨迹属第 28 条敏感个人信息）。后端挡不住这一层，
    /// 只有客户端能，判定在 `RunPlanShareConsentStep.next`。
    func requestLiveShare() {
        shareViewModel.clearNotice(hidingSMSFallback: true)
        switch RunPlanShareConsentStep.next(hasGivenConsent: consentStore.hasGivenConsent(userKey: consentUserKey)) {
        case .fullDisclosure:
            showLiveShareConsent = true
        case .shortConfirmation:
            showLiveShareConfirmation = true
        }
    }
}
