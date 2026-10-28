import Foundation

// 撤回单独同意（#393「隐私与授权」页）。放在扩展文件里：`AppState.swift` 已超长（SwiftLint 棘轮）。
extension AppState {

    /// 撤回「语音下单把转写文字交给第三方大模型」的同意（#374 / #393）。
    /// `ConsentGatedVoiceOrderService` 每次调用现读，删掉记录闸门立刻生效：之后 `/api/orders/voice/parse` 不再发出，
    /// 下次用语音下单前重新询问。
    ///
    /// 两个作用域都删：同意的作用域在「拿不到当前用户 → 按设备」与「按账号」之间会切换
    /// （`voiceOrderConsentScope`），只删当下那一份的话，另一份在作用域切回去时会让闸门重新放行。
    func revokeVoiceOrderConsent() {
        let store = PrivacyConsentStore(persistence: persistence)
        store.revokeConsent(to: .voiceOrderThirdPartyLLM, scope: .device)
        if let id = currentUser?.userId ?? userId {
            store.revokeConsent(to: .voiceOrderThirdPartyLLM, scope: .user(String(id)))
        }
    }

    /// 陪跑会话进行中（出发 / 汇合 / 跑步）不让在 App 里撤回位置同意：撤回会让同行会话立刻停发、
    /// 同意页马上再弹出来。真要停，系统设置关定位权限是即时的。
    var canRevokeLocationTrackConsentNow: Bool {
        !liveEscortCoordinator.isSessionEligible
    }

    /// 撤回这一角色的位置轨迹同意（#368 / #393）。删本机记录与本次登录里记下的那一份，
    /// 立刻重算定位意图（停掉角色那一份持续定位），并让同行协调器重新判一次。
    /// - Returns: 撤回了没有。陪跑进行中返回 false，同意保留。
    @discardableResult
    func revokeLocationTrackConsent(_ purpose: PrivacyConsentPurpose) -> Bool {
        guard purpose == .blindLocationTrack || purpose == .volunteerLocationTrack,
              canRevokeLocationTrackConsentNow else { return false }
        forgetLocationTrackConsentThisSession(purpose)
        if let scope = locationTrackConsentScope {
            PrivacyConsentStore(persistence: persistence).revokeConsent(to: purpose, scope: scope)
        }
        liveEscortCoordinator.trackConsentDidChange()
        syncRoleLocationIntents()
        return true
    }
}
