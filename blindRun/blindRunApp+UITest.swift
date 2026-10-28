import SwiftUI

// 从 `blindRunApp.swift` 挪出（SwiftLint 棘轮 #488：那个文件只许变短）。
extension blindRunApp {
    /// UI 测试截深色图用（`AIDRUN_UI_TEST_COLOR_SCHEME` = `light` / `dark`）。
    ///
    /// **只在 DEBUG 构建生效**：两端跟随系统明暗是定死的（`docs/ui/design-direction.md` §2），
    /// 发布构建里这里恒为 `nil` = 不覆盖。没有它，真机截深色图就得先手动去系统设置里切。
    static var uiTestColorScheme: ColorScheme? {
        #if DEBUG
        switch ProcessInfo.processInfo.environment["AIDRUN_UI_TEST_COLOR_SCHEME"] {
        case "dark": return .dark
        case "light": return .light
        default: return nil
        }
        #else
        return nil
        #endif
    }
}
