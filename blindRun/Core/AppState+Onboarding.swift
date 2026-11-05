import Combine
import Foundation
import SwiftUI

extension AppState {
    // MARK: - Computed

    var isLoggedIn: Bool {
        accessToken != nil
    }

    // MARK: 盲人完成度（拆成互相独立、可单独测试的判断）

    /// 基础资料：目前只要求昵称非空。与紧急联系人无关。
    var isBlindBasicProfileComplete: Bool {
        guard let name = blindProfile?.name else { return false }
        return !name.trimmed.isEmpty
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

    /// 下单硬门槛：基础资料 + 至少 1 个紧急联系人 + 恰好 1 个主联系人。
    /// 2026-11-05 起不再要求实名（#767，后端 blind-run-backend#924 同时去掉 403 `IDENTITY_NOT_VERIFIED`）。
    var isBlindBookingReady: Bool {
        isBlindBasicProfileComplete && hasValidEmergencyContacts
    }

    /// 盲人引导流当前该停在哪一步；nil 表示可以直接进首页。
    var blindOnboardingStep: BlindOnboardingStep? {
        BlindOnboardingStep.first(
            isBasicProfileComplete: isBlindBasicProfileComplete,
            hasValidEmergencyContacts: hasValidEmergencyContacts
        )
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
