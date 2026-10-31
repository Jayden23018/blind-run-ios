import SwiftUI
import UIKit

// MARK: - Blind Runner Tab Container

/// 视障跑者端的根容器：首页 / 记录 / 我的。
///
/// 改版前这三样散在三处：首页自建 `NavigationStack`、历史订单藏在设置页的一个列表行里、
/// 设置是悬浮在地图右上角的一枚齿轮。全仓 `TabView` 此前命中 **0 处**。
///
/// **三个 tab 都挂的是已经存在的页面**，不是新写的：
/// `BlindRunnerHomeView` / `RunRecordHistoryView(role: .runner)` / `BlindRunnerSettingsView`。
///
/// 🔴 **这一层还承担一件安全职责。** 全屏手势挂在这里，「我的」列表里那一行的动作也从这里走：
/// `activateSOS` 按 `BlindHomeSOSMode` 分流。本地拨号就地弹单；陪跑中把人带到订单页，
/// 因为云端求助的结果面都在订单页上（#605）。
///
/// ⚠️ **代价必须写明**：首页没有可见的紧急入口。VoiceOver 用户有全屏手势，
/// 不开读屏的低视力用户要切到「我的」。这是项目负责人 2026-09-16 与 2026-10-30 两次确认的产品取舍。
struct BlindRunnerTabView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService

    /// **所有权在这一层而不是首页**：紧急入口的分流需要同一个 `activeOrder`
    /// （`BlindHomeSOSMode.resolve` 要读订单状态）。两个 tab 各持一个 view model
    /// 会让两处看到不同的订单 —— 而其中一处决定的是求助走云端还是走拨号。
    @StateObject private var homeViewModel = BlindRunnerHomeViewModel()
    /// 陪跑员按了「让 TA 的手机响起来」。挂在根容器上：跑者此刻在哪个 tab、哪一层 push 都得响。
    @StateObject private var ringController = RunnerRingController()

    @State private var selection: Tab = .home
    @State private var showCallOptions = false
    #if DEBUG
    @Environment(\.scenePhase) private var scenePhase
    #endif

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
                RunRecordHistoryView(role: .runner)
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
        // 响铃遮罩盖住整屏时，背后的 TabView 对读屏藏起来 —— SwiftUI 的 hidden 跨不过
        // UIKit 容器，要两层一起挂（记忆 `hide-uikit-hosted-tree-from-accessibility`）。
        .accessibilityHidden(ringController.active != nil)
        .background(HostedContainersAccessibilityHider(isHidden: ringController.active != nil))
        .overlay {
            if let ring = ringController.active {
                RunnerRingOverlay(kind: ring.kind, onStop: { ringController.stop() })
            }
        }
        .onAppear { configureRingController() }
        // #521：第一次有订单时先说明用途再问通知权限（启动时不再弹）。
        .asksBlindForPushPermissionOnFirstOrder()
        // 协调器是 AppState 上的嵌套对象，改它不会让这一层重绘，只能订阅（记忆
        // `nested-observableobject-does-not-republish`）。重新订阅会回放当前值，控制器自己去重。
        .onReceive(appState.realtimeCoordinator.$runnerRing) { ringController.handle($0) }
        #if DEBUG
        .onChange(of: selection) { simulateSOSGestureForUITestIfNeeded(on: $0) }
        .onChange(of: scenePhase) { simulateSOSGestureOnResumeForUITestIfNeeded($0) }
        #endif
        // 全屏手势：读屏用户不必先找到按钮。**挂在这一层而不是某一个 tab 上** ——
        // 三个 tab 上都能用，而首页现在已经没有可见的求助入口了，这是它在首页唯一的通道。
        .accessibilityAction(.magicTap) { activateSOS(request: sosMode.orderSafetyRequestForGesture) }
        // 🔴 拨号单也必须挂在这一层。挂在「我的」tab 里的话，手势从首页或「记录」
        // 触发时弹窗所在的视图不在屏上 —— 用户做了手势、听到确认音、然后什么都没发生。
        .emergencyCallOptionsDialog(
            isPresented: $showCallOptions,
            context: callContext,
            primaryContact: primaryEmergencyContact
        )
    }

    private func configureRingController() {
        // 两者都活满整个 App 生命周期，强引用无妨。
        let speech = speechService
        let coordinator = appState.realtimeCoordinator
        ringController.speak = { speech.speak($0) }
        ringController.isSpeaking = { speech.isSpeaking }
        ringController.onFinish = { coordinator.dismissRunnerRing() }
        #if DEBUG
        simulateRunnerRingForUITestIfNeeded()
        #endif
    }

    #if DEBUG
    private static var didSimulateSOSGesture = false

    /// XCUITest 触发不了 Magic Tap（记忆 `xcuitest-cannot-invoke-accessibility-actions`）。
    /// 这个开关让用例在切到「我的」时走同一条手势分流，验「从别的 tab 回订单页并弹确认」。
    private func simulateSOSGestureForUITestIfNeeded(on tab: Tab) {
        let flag = ProcessInfo.processInfo.environment["AIDRUN_UI_TEST_SOS_GESTURE_ON_PROFILE"]
        guard flag == "1", tab == .profile, !Self.didSimulateSOSGesture else { return }
        Self.didSimulateSOSGesture = true
        activateSOS(request: sosMode.orderSafetyRequestForGesture)
    }

    /// 订单页藏标签栏，切不了 tab。这个开关让用例停在订单页时走手势分流：App 回到前台就触发。
    /// 判云端档是为了跳过冷启动那一次变化，那时订单还没加载。
    private func simulateSOSGestureOnResumeForUITestIfNeeded(_ phase: ScenePhase) {
        let flag = ProcessInfo.processInfo.environment["AIDRUN_UI_TEST_SOS_GESTURE_ON_RESUME"]
        guard flag == "1", phase == .active, sosMode == .cloudTrigger, !Self.didSimulateSOSGesture else { return }
        Self.didSimulateSOSGesture = true
        activateSOS(request: sosMode.orderSafetyRequestForGesture)
    }

    private static var didSimulateRunnerRing = false

    /// UI 测试与真机人耳验证用：启动后注入一条 10 秒的响铃，不用另找一台陪跑员手机。
    /// `1` = 汇合期 `RUNNER_RING`，`lost` = 陪跑中走散 `RUNNER_RING_LOST`。
    private func simulateRunnerRingForUITestIfNeeded() {
        let flag = ProcessInfo.processInfo.environment["AIDRUN_UI_TEST_RUNNER_RING"]
        guard flag == "1" || flag == "lost", !Self.didSimulateRunnerRing else { return }
        Self.didSimulateRunnerRing = true
        let kind: RunnerRingRequest.Kind = flag == "lost" ? .lost : .arrived
        let formatter = DateFormatter.aidRunBackendLocalDateTime
        let sentAt = Date()
        appState.realtimeCoordinator.simulateIncomingEventForTesting(.notification(WSAppNotification(
            type: WSMessageType.appNotification.rawValue,
            eventId: nil,
            messageId: UUID().uuidString,
            eventType: kind == .lost ? "RUNNER_RING_LOST" : "RUNNER_RING",
            title: nil,
            body: RunnerRingCopy.fallbackSpeech(kind),
            ttsText: RunnerRingCopy.fallbackSpeech(kind),
            priority: "HIGH",
            timestamp: formatter.string(from: sentAt),
            orderId: 1,
            until: formatter.string(from: sentAt.addingTimeInterval(10))
        )))
    }
    #endif

    // MARK: - 「我的」：设置 + 紧急入口

    private var profileTab: some View {
        NavigationStack {
            BlindRunnerSettingsView(
                isTabRoot: true,
                emergencyEntry: BlindSettingsEmergencyEntry(mode: sosMode) {
                    activateSOS(request: sosMode.orderSafetyRequestForRow)
                }
            )
        }
    }

    // MARK: - 求助判定（与改版前逐字相同）

    private var sosMode: BlindHomeSOSMode {
        BlindHomeSOSMode.resolve(
            order: homeViewModel.activeOrder,
            role: appState.activeRole,
            isSessionExpired: appState.isSessionExpiryDeferred
        )
    }

    private var primaryEmergencyContact: EmergencyContactResponse? {
        EmergencyContactResponse.singlePrimary(in: appState.emergencyContacts)
    }

    /// 同一个拨号弹窗有两个入口，第一句不同：`.localCall` 那档是「当前没有进行中的陪跑」，
    /// 而云端求助失败后按进来时陪跑正在进行，那句话是错的。跑步中登录过期（#376）又是另一句。
    /// 映射只在 `EmergencyCallContext.runner(for:)` 一处。
    private var callContext: EmergencyCallContext {
        EmergencyCallContext.runner(for: sosMode)
    }

    /// 紧急入口的统一分流。`request` 为 nil 就地弹本地拨号单，不切页面。
    ///
    /// 🔴 **陪跑中必须回到订单页。** 云端求助可能失败（拿不到新鲜坐标是设计上会发生的），
    /// 失败提示和兜底拨号只在订单页上。留在别的 tab 发，失败时屏幕零变化
    /// （记忆 `claimed-fallback-may-not-exist-in-release`）。
    private func activateSOS(request: BlindOrderSafetyRequest?) {
        guard let request else {
            showCallOptions = true
            return
        }
        selection = .home
        homeViewModel.orderSafetyRequest = request
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
