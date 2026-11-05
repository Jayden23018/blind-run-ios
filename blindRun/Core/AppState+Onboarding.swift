import Combine
import Foundation
import SwiftUI

extension AppState {
    // MARK: - Computed

    var isLoggedIn: Bool {
        accessToken != nil
    }

    // MARK: 盲人完成度（拆成互相独立、可单独测试的判断）

    /// 基础资料：目前只要求昵称非空。与紧急联系人、实名状态无关。
    var isBlindBasicProfileComplete: Bool {
        guard let name = blindProfile?.name else { return false }
        return !name.trimmed.isEmpty
    }

    /// 实名状态。2026-07-30 起后端 `OrderCreationService` 在服务端硬校验
    /// `verifyStatus == VERIFIED`（否则 403 `IDENTITY_NOT_VERIFIED`），
    /// 所以这里既用于展示与语音引导，也参与下单门槛。
    var blindIdentityStatus: BlindVerifyStatus {
        blindProfile?.identityStatus ?? .unknown
    }

    /// 实名侧的下单硬门槛。状态未知（后端没返回 / 返回了不认识的值）时按未通过处理：
    /// 服务端会拒，客户端提前引导比让用户白填一遍订单再被 403 更可用。
    var isBlindIdentityVerified: Bool {
        blindIdentityStatus.isVerified
    }

    var emergencyContactCount: Int {
        emergencyContacts.count
    }

    /// 恰好一个主联系人时返回它；0 个或多个都返回 nil。
    var primaryEmergencyContact: EmergencyContactResponse? {
        EmergencyContactResponse.singlePrimary(in: emergencyContacts)
    }

    var hasExactlyOnePrimaryEmergencyContact: Bool {
        primaryEmergencyContact != nil
    }

    /// 紧急联系人侧的硬门槛：至少 1 位，且恰好 1 位主联系人。
    var hasValidEmergencyContacts: Bool {
        emergencyContactCount >= EmergencyContactRules.minCount && hasExactlyOnePrimaryEmergencyContact
    }

    /// 下单硬门槛：基础资料 + 实名认证通过 + 至少 1 个紧急联系人 + 恰好 1 个主联系人。
    /// 实名这一档与后端 `OrderCreationService` 的 403 `IDENTITY_NOT_VERIFIED` 对齐，
    /// 且与服务端同序（实名在紧急联系人之前）。
    var isBlindBookingReady: Bool {
        isBlindBasicProfileComplete && isBlindIdentityVerified && hasValidEmergencyContacts
    }

    /// 盲人引导流当前该停在哪一步；nil 表示可以直接进首页。
    var blindOnboardingStep: BlindOnboardingStep? {
        BlindOnboardingStep.first(
            isBasicProfileComplete: isBlindBasicProfileComplete,
            hasValidEmergencyContacts: hasValidEmergencyContacts,
            shouldPromptIdentity: blindIdentityStatus.shouldPromptVerification,
            didDismissIdentityPrompt: didDismissBlindIdentityPrompt
        )
    }

    /// 「稍后再说」：跳过实名引导页进首页。**不等于可以下单**——
    /// 未实名仍会被 `BlindBookingGate.identityVerification` 拦住（后端 403 `IDENTITY_NOT_VERIFIED`）。
    ///
    /// ⚠️ 这句话原本写的是「进首页**看历史订单**和设置」，而盲人端长期**没有任何历史入口** ——
    /// 跳过实名的用户进来只有一个必定失败的「开始约跑」。注释在描述一个不存在的能力。
    /// 入口现在有了：设置页 →「我的历史订单」（`BlindRunHistoryView`），
    /// 收全部终态、点进去是订单详情，补评价也在那里。
    func dismissBlindIdentityPrompt() {
        didDismissBlindIdentityPrompt = true
        persistence.set(true, forKey: AppConstants.UserDefaultsKeys.blindIdentityPromptDismissed)
    }

    /// 首次引导看完（按了「知道了」）。**只有这一个写入点** ——
    /// 「进过这一页」不算看完：自动进入的那次如果用户直接返回，下次还该给他。
    func markBlindFirstRunHelpSeen() {
        guard !didSeeBlindFirstRunHelp else { return }
        didSeeBlindFirstRunHelp = true
        persistence.set(true, forKey: AppConstants.UserDefaultsKeys.blindFirstRunHelpSeen)
    }

    /// 首次启动告知的同意。**只有这一个写入点**：唯一的触发者是用户按下「同意并开始使用」。
    /// 「看过这一页」不算同意 —— 同意必须是一个主动动作（PIPL 第 14 条）。
    func acceptPrivacyConsent() {
        guard !didAcceptPrivacyConsent else { return }
        didAcceptPrivacyConsent = true
        PrivacyConsentStore(persistence: persistence)
            .recordConsent(to: .appLaunch, scope: .device)
        // 高德要「用户同意之后」才声明已同意（#408）；这是冷启动时尚未同意的用户唯一的补发点。
        AMapManager.setUserAcceptedPrivacy(true)
    }

    /// 启动时的初值。**在 `init` 里解析而不是等 `onAppear`** —— 晚一帧的代价是 UI 用例先看到
    /// 同意页再看到它消失，断言打在那一帧上就是随机红。
    ///
    /// `environment` 可注入只是为了让下面这条规则本身有用例可测：它一旦写反，表现是**全部 UI 用例
    /// 被同意页挡住**，而真机 UI 通道时好时坏，坏的时候没人会发现是这里写反了。
    static func resolveInitialPrivacyConsent(
        persistence: any AppStatePersistence,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        if PrivacyConsentStore(persistence: persistence).hasConsented(to: .appLaunch, scope: .device) {
            return true
        }
        #if DEBUG || DEMO
        // UI 用例一律 `RESET_STATE`，于是每一条都会被同意页挡住 —— 与首次引导同一个理由，默认跳过。
        // 专门测同意门的用例设 `AIDRUN_UI_TEST_FORCE_PRIVACY_CONSENT=1` 走真实首启路径。
        if environment["AIDRUN_UI_TEST_RESET_STATE"] == "1",
           environment["AIDRUN_UI_TEST_FORCE_PRIVACY_CONSENT"] != "1" {
            return true
        }
        #endif
        return false
    }

    var isVolunteerProfileComplete: Bool {
        guard let profile = volunteerProfile else {
            return false
        }
        return profile.isProfileCompleteForDispatch
    }

    var isVolunteerProfileApproved: Bool {
        guard let profile = volunteerProfile else { return false }
        if let volunteerRegistrationStatus {
            return volunteerRegistrationStatus.isRegistrationComplete
        }
        return profile.isMainRegistrationCompleteWhenStatusUnavailable && profile.isAdminReviewApprovedWhenAvailable
    }
}
