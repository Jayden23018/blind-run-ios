import Foundation

/// 陪跑员使用帮助的「已看过」标志（#656）。放在独立文件里：`AppState.swift` 与它的 `init` 已经超出
/// SwiftLint 基线，新增的行不该再往里堆。
extension AppState {
    /// 是否已经看过。按**设备**记，登出不清，理由同 `didSeeBlindFirstRunHelp`。
    /// 直接读持久化而不是 `@Published`：只有订单页出现时读一次，没有视图要随它重绘。
    var didSeeVolunteerFirstRunHelp: Bool {
        persistence.object(forKey: AppConstants.UserDefaultsKeys.volunteerFirstRunHelpSeen) as? Bool ?? false
    }

    /// 帮助看完（按了「知道了」）。**只有这一个写入点**，理由同 `markBlindFirstRunHelpSeen`。
    func markVolunteerFirstRunHelpSeen() {
        persistence.set(true, forKey: AppConstants.UserDefaultsKeys.volunteerFirstRunHelpSeen)
    }

    #if DEBUG || DEMO
    /// UI 用例的首次引导默认**跳过**。UI 用例一律 `RESET_STATE`，于是每一条都会在首页或订单页被引导挡住，
    /// 全部断言当场红 —— 让二十多条用例各加一个环境变量是把关系搞反了。
    /// 专门测引导的用例设 `AIDRUN_UI_TEST_FORCE_FIRST_RUN_HELP=1`（盲人端）、
    /// `AIDRUN_UI_TEST_FORCE_VOLUNTEER_FIRST_RUN_HELP=1`（陪跑员端）走真实首次路径。
    func applyUITestFirstRunHelpDefaults(environment: [String: String]) {
        if environment["AIDRUN_UI_TEST_FORCE_FIRST_RUN_HELP"] != "1" { markBlindFirstRunHelpSeen() }
        if environment["AIDRUN_UI_TEST_FORCE_VOLUNTEER_FIRST_RUN_HELP"] != "1" { markVolunteerFirstRunHelpSeen() }
        // 第一次接单时的手机号说明（#660 V-17）。专门测它的用例设 `AIDRUN_UI_TEST_FORCE_PHONE_SHARE_DISCLOSURE=1`。
        if environment["AIDRUN_UI_TEST_FORCE_PHONE_SHARE_DISCLOSURE"] != "1" {
            persistence.set(true, forKey: VolunteerOnceNotice.uiTestSkipKey)
        }
    }
    #endif
}
