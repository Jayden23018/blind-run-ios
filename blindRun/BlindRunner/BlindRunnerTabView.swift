import SwiftUI
import UIKit

// MARK: - Blind Runner Tab Container

/// 视障跑者端的根容器：首页 / 记录 / 我的。
///
/// 改版前这三样散在三处：首页自建 `NavigationStack`、历史订单藏在设置页的一个列表行里、
/// 设置是悬浮在地图右上角的一枚齿轮。全仓 `TabView` 此前命中 **0 处**。
///
/// **三个 tab 都挂的是已经存在的页面**，不是新写的：
/// `BlindRunnerHomeView` / `BlindRunHistoryView` / `BlindRunnerSettingsView`。
///
/// 🔴 **这一层还承担一件安全职责。** 改版前盲人首页底部有一条常驻求助条
/// （`.safeAreaInset(edge: .bottom)`，`IN_PROGRESS` 走云端、其余状态降级为本地拨号），
/// `AGENTS.md` §6 把它定为「唯一的例外形态」。本次改版按设计稿把它从首页移除，
/// 由项目负责人 2026-09-16 拍板改由「我的」tab 兜底 —— 所以它现在挂在**「我的」那一个 tab**
/// 的底部，仍然是 `safeAreaInset`、仍然不滚动即可达、仍然是同一个 `BlindHomeSOSBar` 组件
/// 和同一条 `BlindHomeSOSMode.resolve` 判据（那条判据由 `EmergencySOSTests` 逐状态钉着，
/// 一行未改）。
///
/// ⚠️ **代价必须写明**：紧急入口从「打开 App 就在眼前」变成「先切到第三个 tab」。
/// 对 VoiceOver 用户仍有首页的 magic tap 手势兜住（见 `BlindRunnerHomeView`），
/// 而**不开读屏的低视力用户在首页确实够不到它**。这不是实现疏漏，是已知的产品取舍。
struct BlindRunnerTabView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @EnvironmentObject private var locationService: LocationService

    /// **所有权在这一层而不是首页**：「我的」tab 底部那条求助条的云端分支需要同一个
    /// `activeOrder`（`BlindHomeSOSMode.resolve` 要读订单状态）。两个 tab 各持一个
    /// view model 会让两处看到不同的订单 —— 而其中一处决定的是求助走云端还是走拨号。
    @StateObject private var homeViewModel = BlindRunnerHomeViewModel()

    @State private var selection: Tab = .home
    @State private var showEmergencyConfirmation = false
    @State private var showCallOptions = false

    private enum Tab: Hashable {
        case home
        case history
        case profile
    }

    init() {
        Self.applyTabBarAppearance()
    }

    var body: some View {
        TabView(selection: $selection) {
            BlindRunnerHomeView(viewModel: homeViewModel)
                .tabItem {
                    Label("首页", systemImage: "house")
                }
                .tag(Tab.home)

            NavigationStack {
                BlindRunHistoryView()
            }
            .tabItem {
                Label("记录", systemImage: "list.bullet")
            }
            .tag(Tab.history)

            profileTab
                .tabItem {
                    Label("我的", systemImage: "person")
                }
                .tag(Tab.profile)
        }
        .tint(AppColors.Flow.tabSelected)
        // 全屏手势：读屏用户不必先找到按钮。**挂在这一层而不是某一个 tab 上** ——
        // 三个 tab 上都能用，而首页现在已经没有可见的求助入口了，这是它在首页唯一的通道。
        .accessibilityAction(.magicTap) { activateSOS() }
        // 🔴 两个弹窗也必须挂在这一层。挂在「我的」tab 里的话，magic tap 从首页或「记录」
        // 触发时弹窗所在的视图不在屏上 —— 用户做了手势、听到确认音、然后什么都没发生。
        // 这正是「静默失败」最坏的一种形态，而且只在紧急时刻才会被发现。
        .emergencyConfirmationAlert(isPresented: $showEmergencyConfirmation, audience: .runner) {
            Task { await homeViewModel.enterEmergency(locationService: locationService) }
        }
        .emergencyCallOptionsDialog(
            isPresented: $showCallOptions,
            context: callContext,
            primaryContact: primaryEmergencyContact
        )
    }

    // MARK: - 「我的」：设置 + 兜底的紧急入口

    private var profileTab: some View {
        NavigationStack {
            BlindRunnerSettingsView()
        }
        // 与改版前首页同一个结构、同一个组件、同一条判据。挂 `safeAreaInset` 而不是塞进
        // `List` 的某一行：那条列表有十来行，紧急入口排在中间等于要先滚动才摸得到。
        .safeAreaInset(edge: .bottom) { sosBar }
    }

    private var sosBar: some View {
        BlindHomeSOSBar(
            coordinator: appState.emergencyCoordinator,
            mode: sosMode,
            action: activateSOS,
            onLocalCall: { showCallOptions = true }
        )
        // 与内容列同宽：不限的话求助条在 iPad 上是一条 1024pt 宽的红杠，
        // 和上面的设置列表左右都对不齐。材质背景仍铺满整宽。
        .readableContentColumn()
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 4)
        .background(.ultraThinMaterial)
    }

    // MARK: - 求助判定（与改版前逐字相同）

    private var sosMode: BlindHomeSOSMode {
        BlindHomeSOSMode.resolve(order: homeViewModel.activeOrder, role: appState.activeRole)
    }

    private var primaryEmergencyContact: EmergencyContactResponse? {
        EmergencyContactResponse.singlePrimary(in: appState.emergencyContacts)
    }

    /// 同一个拨号弹窗有两个入口，第一句不同：`.localCall` 那档是「当前没有进行中的陪跑」，
    /// 而云端求助失败后按进来时陪跑正在进行，那句话是错的。
    private var callContext: EmergencyCallContext {
        sosMode == .cloudTrigger ? .cloudFailed : .homeIdle
    }

    private func activateSOS() {
        switch sosMode {
        case .cloudTrigger:
            showEmergencyConfirmation = true
        case .localCall:
            showCallOptions = true
        }
    }

    // MARK: - 标签栏外观

    /// 标签栏未选中标签的取色。
    ///
    /// **必须走 `UITabBarAppearance`**：SwiftUI 到 iOS 16 只有 `.tint()`（管选中态），
    /// 未选中态没有对应的修饰符。全局改 `UITabBar.appearance()` 在这里是安全的 ——
    /// 全仓只有这一个 `TabView`。
    ///
    /// 不只是为了对设计稿：**iOS 默认的未选中灰 `#8E8E93` 压白底只有 3.26:1**，
    /// 而标签栏是 13pt 的小字。设计稿的 `#6B7385` 是 4.76:1。取值与理由在
    /// `AppColors.Flow.tabUnselectedTone`。
    private static func applyTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()

        let unselected = UIColor { traits in
            let tone = AppColors.Flow.tabUnselectedTone
            return UIColor(rgb: traits.userInterfaceStyle == .dark ? tone.dark : tone.light)
        }
        for item in [
            appearance.stackedLayoutAppearance,
            appearance.inlineLayoutAppearance,
            appearance.compactInlineLayoutAppearance,
        ] {
            item.normal.iconColor = unselected
            item.normal.titleTextAttributes = [.foregroundColor: unselected]
        }

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}

#if DEBUG
#Preview {
    BlindRunnerTabView()
        .environmentObject(AppState())
        .environmentObject(SpeechService())
        .environmentObject(LocationService())
        .environmentObject(SpeechInputService())
}
#endif
