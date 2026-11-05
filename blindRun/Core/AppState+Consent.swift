import Combine
import Foundation
import SwiftUI

extension AppState {
    // MARK: - 语音下单的第三方大模型同意

    /// 按**账号**记（理由同 `ProfileModule` 的视力状况同意）。拿不到 userId 时退到 `.device`：
    /// 宁可多问一次，也不让界面一声不响。
    private var voiceOrderConsentScope: PrivacyConsentScope {
        currentUser.map { .user(String($0.userId)) } ?? .device
    }

    /// 当前账号是否同意了「语音下单的转写文字交给阿里云通义千问」。每次现读，不缓存。
    var hasVoiceOrderConsent: Bool {
        if Self.uiTestSkipsVoiceOrderConsent() { return true }
        return PrivacyConsentStore(persistence: persistence)
            .hasConsented(to: .voiceOrderThirdPartyLLM, scope: voiceOrderConsentScope)
    }

    /// UI 用例默认跳过这道同意：好几条用例靠「点开始约跑」进下单页，同意页会把它们全部挡在门外。
    /// 与首启告知同一个做法（`resolveInitialPrivacyConsent`）：专测同意页的用例设
    /// `AIDRUN_UI_TEST_FORCE_VOICE_ORDER_CONSENT=1` 走真实路径。UI 用例跑的是进程内 Mock，
    /// 跳过它不会让任何文字发往第三方；真实安装没有这两个环境变量，一律要同意。
    static func uiTestSkipsVoiceOrderConsent(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        #if DEBUG || DEMO
        return environment["AIDRUN_UI_TEST_RESET_STATE"] == "1"
            && environment["AIDRUN_UI_TEST_FORCE_VOICE_ORDER_CONSENT"] != "1"
        #else
        return false
        #endif
    }

    /// 唯一的写入点：触发者只能是用户按下同意页上的「同意并使用语音下单」。
    func recordVoiceOrderConsent() {
        PrivacyConsentStore(persistence: persistence)
            .recordConsent(to: .voiceOrderThirdPartyLLM, scope: voiceOrderConsentScope)
    }

    // MARK: - 位置轨迹的单独同意（#368）

    /// 按**账号**记。拿不到 userId 时不读盘 —— 宁可多问一次，也不让一个身份不明的会话继承别人的同意。
    var locationTrackConsentScope: PrivacyConsentScope? {
        userId.map { .user(String($0)) }
    }

    /// 本账号在本机有没有这一角色的位置轨迹同意。**后端不存这项同意**：没有记录就当没同意过。
    /// 每次现读，不缓存。`purpose` 只接受两个位置轨迹目的，其余一律 false。
    func hasLocationTrackConsent(_ purpose: PrivacyConsentPurpose) -> Bool {
        guard purpose == .blindLocationTrack || purpose == .volunteerLocationTrack else { return false }
        if Self.uiTestSkipsLocationTrackConsent() { return true }
        if locationTrackConsentGrantedThisSession.contains(purpose) { return true }
        guard let scope = locationTrackConsentScope else { return false }
        return PrivacyConsentStore(persistence: persistence).hasConsented(to: purpose, scope: scope)
    }

    /// 撤回时忘掉本次登录里记下的那一份（#393）。集合本身保持私有，「唯一写入点」的约定不破。
    func forgetLocationTrackConsentThisSession(_ purpose: PrivacyConsentPurpose) {
        locationTrackConsentGrantedThisSession.remove(purpose)
    }

    /// 唯一的写入点：触发者只能是用户按下同意页上的「同意共享位置」。
    func recordLocationTrackConsent(_ purpose: PrivacyConsentPurpose) {
        guard purpose == .blindLocationTrack || purpose == .volunteerLocationTrack else { return }
        locationTrackConsentGrantedThisSession.insert(purpose)
        if let scope = locationTrackConsentScope {
            PrivacyConsentStore(persistence: persistence).recordConsent(to: purpose, scope: scope)
        }
        // 同一个目的可能同时有两处在问（接单开关的同意页 + 同行态的同意页），答了一处另一处要跟着收。
        liveEscortCoordinator.trackConsentDidChange()
        syncRoleLocationIntents()
    }

    /// 求助取坐标前读（#368）：当前角色在本机没有位置轨迹同意（还没回答或已拒绝）⇒ 求助**不附位置**，
    /// 按「拿不到坐标就不发」处理（`AGENTS.md` §6），原因由 `LocationError.locationSharingNotConsented` 说清。
    ///
    /// 按角色判，**不看同行会话此刻有没有订单**：协调器在换 token / 换角色 / 冷启动之后会有几秒拿不到
    /// 订单状态，按会话判的话那几秒会放行一个用户说过不的位置。云端求助只在 `IN_PROGRESS` 开放，
    /// 而那一态没有同意的人一定被问过（同意页盖在界面上），所以按角色判不会误拦。拿不到角色时按「被拦」算。
    var isEmergencyLocationSharingBlocked: Bool {
        guard let purpose = PrivacyConsentPurpose.locationTrack(for: activeRole) else { return true }
        return !hasLocationTrackConsent(purpose)
    }

    /// UI 用例默认跳过这道同意，理由同 `uiTestSkipsVoiceOrderConsent`：好几十条用例靠「预约 / 接单开关 /
    /// 种一张同行态的单」进页面，同意页会把它们全挡在门外。专测同意页的用例设
    /// `AIDRUN_UI_TEST_FORCE_LOCATION_TRACK_CONSENT=1`。真实安装没有这两个环境变量，一律要同意。
    static func uiTestSkipsLocationTrackConsent(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        #if DEBUG || DEMO
        return environment["AIDRUN_UI_TEST_RESET_STATE"] == "1"
            && environment["AIDRUN_UI_TEST_FORCE_LOCATION_TRACK_CONSENT"] != "1"
        #else
        return false
        #endif
    }
}
