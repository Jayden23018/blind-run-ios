import SwiftUI

// MARK: - 跑步中登录过期的提示（#376）

/// 提示组件要的两样东西：说什么，以及「现在重新登录」按下去做什么。
///
/// 走自定义环境值而不是 `@EnvironmentObject AppState`：这个组件挂在共享底栏
/// （`OrderFlowBottomActions`、`VolunteerRunningPage`）里，预览与快照测试渲染那些底栏时不注入 `AppState`，
/// `@EnvironmentObject` 取不到会直接崩；环境值默认 nil，组件就什么都不渲染。
struct SessionExpiryNoticeContext {
    let deferral: SessionExpiryDeferral
    let relogin: () -> Void
}

private struct SessionExpiryNoticeKey: EnvironmentKey {
    static let defaultValue: SessionExpiryNoticeContext? = nil
}

extension EnvironmentValues {
    /// 由 `ContentView` 在根部注入；只在 `AppState.sessionExpiryDeferral` 非 nil 时有值。
    var sessionExpiryNotice: SessionExpiryNoticeContext? {
        get { self[SessionExpiryNoticeKey.self] }
        set { self[SessionExpiryNoticeKey.self] = newValue }
    }
}

/// 跑步页固定底栏里、按钮上方的那块提示。没有暂缓时不渲染任何东西。
///
/// 🔴 **放在页面自己的底栏里，不做成 `ContentView` 层的浮层。** 第一版挂在 `ContentView` 的
/// `safeAreaInset(edge: .bottom)` 上，真机截图里它**整块压住了跑步页的「求助与安全」与主按钮**
/// （2026-10-09，UI 用例 `testRunnerKeepsTheSession…` 点「求助与安全」点到了横幅上）：
/// 那一层与页面之间隔着 UIKit 承载的 `TabView` / `NavigationStack`，安全区内边距传不进去，
/// 横幅不参与页面布局，只是盖在上面。放进底栏的 `VStack` 里，它就把按钮往上推，而不是盖住按钮。
///
/// 播报不在这里（`ContentView` 按 `announcementSerial` 念），这里只管可见与那枚按钮。
struct SessionExpiryNotice: View {
    @Environment(\.sessionExpiryNotice) private var context
    @State private var confirmsRelogin = false

    var body: some View {
        if let context {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(AppColors.warning)
                        .accessibilityHidden(true)
                    Text(context.deferral.bannerMessage)
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(context.deferral.bannerMessage)
                .accessibilityIdentifier("sessionExpiryDeferralMessage")

                // `frame` 挂在 label 里：挂在 Button 外面只撑布局、不撑可点区域
                // （记忆 `button-frame-outside-label-does-not-grow-hit-area`，第一版真机量到 34.3pt）。
                Button {
                    confirmsRelogin = true
                } label: {
                    Text("现在重新登录")
                        .frame(maxWidth: .infinity, minHeight: 64)
                }
                .buttonStyle(.bordered)
                .accessibilityHint("退出当前账号并回到登录页，会先让你确认")
                .accessibilityIdentifier("sessionExpiryReloginButton")
            }
            // `.contain`：不配它，容器的 identifier 会盖掉上面两个子元素各自的 identifier。
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("sessionExpiryDeferralBanner")
            // 要二次确认：读屏用户在底栏横扫时可能误触，而跑步中退出会连本地拨号的求助入口一起带走
            // （登录页没有求助条）。
            .alert("现在重新登录？", isPresented: $confirmsRelogin) {
                Button("重新登录", role: .destructive) { context.relogin() }
                Button("先不", role: .cancel) {}
            } message: {
                Text("会退出当前账号、回到登录页，需要重新收验证码。退出后 App 里暂时没有求助入口，紧急情况请直接拨打120或110。")
            }
        }
    }
}
