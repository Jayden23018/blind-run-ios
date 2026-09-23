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
        case xinghuo
        case history
        case profile
    }

    init() {
        // 外观与未选中态取色见 `FlowTabBarAppearance` —— 2026-09-17 从这里搬出去，
        // 志愿者端加标签栏之后两个容器共用同一份（两份会漂移，而漂移的那半份是对比度）。
        FlowTabBarAppearance.apply()
    }

    var body: some View {
        TabView(selection: $selection) {
            BlindRunnerHomeView(viewModel: homeViewModel)
                .tabItem {
                    Label("首页", systemImage: "house")
                }
                .tag(Tab.home)

            #if DEBUG
            // 星火页一期只有演示数据，正式版不编译这个 tab（二期接上聚合端点后放开）。
            XinghuoMapView(role: .blind)
                .tabItem {
                    Label("星火", systemImage: "sparkles")
                }
                .tag(Tab.xinghuo)
            #endif

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

    /// 求助入口的统一分流。magic tap 与「我的」tab 底部那条求助条走同一个入口。
    ///
    /// 🔴 **先切到「我的」tab，再弹确认。** 这一行不是为了好看，是为了满足
    /// `AGENTS.md` §6 的「拿不到坐标就不发，并且**可见且可听**地告知用户」：
    ///
    /// 云端求助的**可见面**（`EmergencyStatusNotice`，以及失败时那枚「求助没发出去时
    /// 屏幕上必须有个能按的东西」的兜底拨号按钮）整块长在 `BlindHomeSOSBar` 里，
    /// 而这条 bar 只在「我的」tab。`BlindRunnerHomeViewModel.enterEmergency` 当初
    /// **刻意不写 `errorMessage`**，理由是「可见面就在同一屏，写了会让同一句话被念两遍」
    /// —— 那个前提在求助条搬走之后不再成立。
    ///
    /// 不切 tab 的后果：在首页做两指双击 → 确认 → 坐标拿不到（`allowsSubmissionWithoutLocation`
    /// 恒 false，这是**设计上会发生**的失败）→ 只有一句 TTS，屏幕零变化，
    /// 而那枚兜底拨号按钮在另一个 tab 上够不到。命中记忆
    /// `claimed-fallback-may-not-exist-in-release` 的第二种吃法。
    ///
    /// 紧急手势把用户带到安全面本身也是对的：他此刻要的就是这一屏。
    private func activateSOS() {
        selection = .profile
        switch sosMode {
        case .cloudTrigger:
            showEmergencyConfirmation = true
        case .localCall:
            showCallOptions = true
        }
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
