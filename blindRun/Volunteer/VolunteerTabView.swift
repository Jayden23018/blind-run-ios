import SwiftUI

// MARK: - Volunteer Tab Container

/// 陪跑员端的根容器：首页 / 记录 / 我的（设计交付 v3 §4.1「导航结构」）。
///
/// 改版前这三样散在一处：`VolunteerHomeView` 自己就是根，「记录」只能从首屏
/// 「最近一次」旁的「全部 ›」进去、「我的」只能从首屏右上角一枚齿轮进去。
///
/// **三个 tab 挂的都是已经存在的页面**，不是新写的：
/// `VolunteerHomeView` / `RunRecordHistoryView(role: .volunteer)` / `VolunteerSettingsView`。
/// 首屏那两个旧入口**刻意保留**（项目负责人 2026-09-17 拍板）：两条路通同一页，
/// 功能上无害，而首屏那一版信息架构要不要跟设计稿重排是另一件事。
///
/// 🔴 **这一层还承担两件本来不在这里的事，都是 `TabView` 逼出来的：**
///
/// ① **派单弹窗挂在这里**（不是首页 tab 里）。原注释说的「不管他在哪一页，30 秒倒计时
///    都必须看得见」现在多了一种「哪一页」—— 他可能正在「记录」或「我的」tab 上。
///    留在首页 tab 里就等于在另外两个 tab 上收不到派单。
///
/// ② **view model 的所有权和整条生命周期都在这里。** 盲人端已经踩过并把理由写在
///    `BlindRunnerHomeView.swift:583-596`：切 tab 会走子视图的 `onDisappear` /
///    `onAppear`，`.task` 会随每次切回重跑。这套东西留在首页 tab 里的话，切一次
///    「记录」就 `setSceneActive(false)` 掐掉刷新循环与在途请求，切回来再整套重拉一遍
///    —— 而派单要靠那条循环持续上报位置。挂在容器上之后，`onDisappear` 只在真正离开
///    志愿者端（切角色 / 退出登录）时才触发，那正是它原本的语义。
struct VolunteerTabView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @EnvironmentObject private var locationService: LocationService

    @StateObject private var viewModel = VolunteerHomeViewModel()

    @State private var selection: Tab = .home

    private enum Tab: Hashable {
        case home
        case xinghuo
        case records
        case profile
    }

    init() {
        FlowTabBarAppearance.apply()
    }

    var body: some View {
        TabView(selection: $selection) {
            VolunteerHomeView(viewModel: viewModel)
                .tabItem {
                    Label("首页", systemImage: "house")
                }
                // §4.4.1「App 在前台，位于其他页面 → 顶部横幅 + **首页标签加数字角标**」。
                // 横幅只活 4 秒，角标是它散掉之后唯一还留在屏幕上的痕迹。
                .badge(viewModel.inviteBadgeCount)
                .tag(Tab.home)

            #if DEBUG
            // 星火页一期只有演示数据，正式版不编译这个 tab（二期接上聚合端点后放开）。
            XinghuoMapView(role: .volunteer)
                .tabItem {
                    Label("星火", systemImage: "sparkles")
                }
                .tag(Tab.xinghuo)
            #endif

            NavigationStack {
                RunRecordHistoryView(role: .volunteer)
            }
            .tabItem {
                Label("记录", systemImage: "list.bullet")
            }
            .tag(Tab.records)

            NavigationStack {
                VolunteerSettingsView()
            }
            .tabItem {
                Label("我的", systemImage: "person")
            }
            .tag(Tab.profile)
        }
        .tint(AppColors.Flow.tabSelected)
        // 🔴 **导航触发时先切回首页 tab。** 三个落点（通话磨合 / 已接下的单 / 接单主页）的
        // `navigationDestination` 都在首页 tab 的栈里 —— 人在「记录」或「我的」上时
        // push 照常发生，而他**看不见**：屏幕上什么都没变，通话窗口却在走。
        //
        // 两条到达路径都会命中这里：派单接单后 view model 写 `acceptedDispatchOrderId`，
        // 以及冷启动三岔路自动打开订单页（§4.1）。与盲人端 `activateSOS()` 里那行
        // `selection = .profile` 是同一类修正。
        .onChange(of: viewModel.acceptedDispatchOrderId) { orderId in
            if orderId != nil { selection = .home }
        }
        .onChange(of: viewModel.pendingIntroCallOrder?.orderId) { orderId in
            if orderId != nil { selection = .home }
        }
        .onAppear {
            // **删地图 ≠ 停定位**：这两行是派单的前提，没有位置上报就收不到单。
            locationService.requestPermission()
            locationService.startUpdating()
            // 第一条派单进来时，邀请卡的 spring 和「合成 WAV + 写盘 + 注册 SystemSoundID」
            // 会挤在同一拍主线程上 —— 表现是冷启动后的**第一条**派单弹得一顿一顿的。
            // 提前在后台把它做掉，理由见 `VolunteerInviteCue.prewarm()`。
            VolunteerInviteCue.prewarm()
        }
        .onDisappear {
            viewModel.setSceneActive(false)
        }
        .task(id: scenePhase) {
            viewModel.configure(
                with: appState,
                speechService: speechService,
                currentLocationProvider: { locationService.currentLocation },
                locationAuthorizedProvider: { locationService.isAuthorized }
            )
            let isActive = scenePhase == .active
            viewModel.setSceneActive(isActive)
            guard isActive else { return }
            await viewModel.load(
                currentLocation: locationService.currentLocation,
                locationAuthorized: locationService.isAuthorized
            )
            viewModel.startRefreshLoop()
        }
        // §4.4.1 的顶部横幅。**挂在 `TabView` 外面**，理由与邀请卡同一条：
        // 它出现的前提正是「他不在接单主页」，也就是可能在任何一个 tab、任何一层栈上。
        //
        // 🚩 计时放在视图侧而不是 view model：`.task(id:)` 随横幅换人自动重起、
        // 随视图消失自动取消，而 view model 里要自己管一个 `Task` 的生命周期。
        .overlay(alignment: .top) {
            if let banner = viewModel.bannerInvite {
                VolunteerInviteBanner(invite: banner) {
                    viewModel.presentInviteSheetFromBanner()
                }
                .padding(.horizontal, FlowMetrics.pageHorizontalPadding)
                .padding(.top, 8)
                // 开了「减弱动态效果」就只淡入淡出，不从屏幕顶端滑下来。
                .transition(
                    reduceMotion
                        ? .opacity
                        : .move(edge: .top).combined(with: .opacity)
                )
                .zIndex(99)
                .task(id: banner.id) {
                    try? await Task.sleep(
                        nanoseconds: UInt64(VolunteerInviteCopy.bannerDisplaySeconds * 1_000_000_000)
                    )
                    guard !Task.isCancelled else { return }
                    viewModel.dismissInviteBanner()
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: viewModel.bannerInvite?.id)
        // 撤销 toast 挂在邀请卡**下面一层**：点完「这次去不了」卡片就收起了，
        // 而 toast 正是那一刻唯一还在屏幕上的东西（§4.4.3）。
        //
        // 🚩 **顺序不能和下面那个 overlay 对调。** 队列里还有下一条时卡片不收起，
        // 那一刻 toast 应当被卡片盖住（`.sheet` 时代就是这个行为）——
        // 放到上面去会让它正好压在「这次去不了 / 查看详情」那两枚按钮上。
        .overlay(alignment: .bottom) {
            if viewModel.pendingDecline != nil {
                VolunteerDeclineUndoToast { viewModel.undoPendingDecline() }
                    .padding(.bottom, 8)
                    // 开了「减弱动态效果」就只淡入淡出，不从屏幕下缘滑上来。
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .move(edge: .bottom).combined(with: .opacity)
                    )
            }
        }
        .animation(.easeOut(duration: 0.2), value: viewModel.pendingDecline?.id)
        // 🔴 **邀请卡弹出时把下面整棵树对读屏屏蔽。**
        //
        // `.sheet` 白送这件事，自定义 overlay 不送。少了它的表现是：VoiceOver 用户
        // 一路右划就滑到了被压暗层盖住的首页、标签栏和「开始接单」滑轨上 ——
        // 念得到、按得动，而屏幕上它们在一块半透明黑布底下。
        //
        // 卡片自己那层 `.isModal` 保留（见 `VolunteerInviteSheet.card`），两道管的不是一件事：
        // 一道拦「焦点跑到下面去」，一道告诉 VoiceOver「这是一层模态」。
        // overlay 不是真的模态容器，只靠 `.isModal` 在 iOS 16 上兜不住。
        //
        // 🔴 **光有下面这行 `.accessibilityHidden` 不够，真正起作用的是 `.background` 那一行。**
        // `TabView` 在 UIKit 侧是一个 `UITabBarController`：SwiftUI 的 hidden 跨不过这道边界，
        // 底下那棵树（首页 ScrollView、「开始接单」滑轨、标签栏）照样暴露。
        // 2026-09-23 iPhone 16 Pro 真机逐个试过（诊断把结果写进探针自己的 label，读失败消息里的树）：
        //   · 这行 SwiftUI hidden 单独用                                → 首页那一行、TabBar 都还在
        //   · tab bar controller 根视图 / 子视图设 `accessibilityElementsHidden` → 标志读回是 true，树里照样都在
        //   · tab bar controller 根视图设 `accessibilityElements = []`    → 两者都消失 ✅
        // 这行留着管的是横幅与撤销 toast 那两层纯 SwiftUI 的 overlay（与 TabView 同一个宿主，hidden 管得到）。
        // 用例：`testMockVolunteerInviteSheetExposesItsThreeActions`（弹出时首页与标签栏都不在树里）
        // + `testMockVolunteerInviteSheetGivesTheScreenBehindBackOnceDismissed`（收起后回来）。
        .background(TabBarAccessibilityHider(isHidden: viewModel.isInviteSheetPresented))
        .accessibilityHidden(viewModel.isInviteSheetPresented)
        // 🚩 **邀请卡挂在 `TabView` 外面。**
        //
        // 挂在某个 tab 的栈内根视图上时，push 出任何二级页（陪跑培训、服务记录、成就、设置）
        // 之后它会被那一页盖住；挂在某一个 tab 上时，他切到别的 tab 就看不见。
        // 不管他在哪一页、哪一个 tab，那个回复窗口都必须看得见。
        //
        // 🔴 **2026-09-18 从 `.sheet` 改回自定义 overlay。** 三条理由，`presentationDetents`
        // 一条都给不了：① §4.4.1 要 spring 从底部升起；② 高度必须由内容决定
        //（钉死的 `.fraction(0.67)` 就是真机截图里底部那一大片空白）；③ 横滑翻页被
        // sheet 自己的拖拽吃掉。**因此「这一层不能再挂第二个 sheet」那条约束随之作废** ——
        // 但也别急着往回加：栈内的 `NavigationLink` 本来就够用。
        //
        // 视图**无条件挂载**、由它内部按 `isInviteSheetPresented` 决定渲染什么：
        // 压暗层与卡片要各自带各自的转场（淡入 / 升起），而在这里写 `if` 会让整块
        // 只能共用一种转场。没有邀请时它渲染出来是空的，不拦手势。
        .overlay {
            VolunteerInviteSheet(
                viewModel: viewModel,
                // 发 ACCEPT 还是 INTERESTED 由推送里的 `requiresIntroCall` 决定
                // （`WSNewOrder.dispatchRespondAction`，调用方算好传进来）。
                // 🚨 这里**不做第二次判断** —— 判据在后端，客户端自己算必然漂移，
                // 而漂移的表现是「界面说能直接接、后端回 409」。
                onRespond: { orderId, action in
                    viewModel.respondToDispatch(
                        action: action,
                        currentLocation: locationService.currentLocation,
                        locationAuthorized: locationService.isAuthorized,
                        orderId: orderId
                    )
                },
                onDecline: { viewModel.declineInvite(orderID: $0) }
            )
            // 没有邀请时这一层什么都不画，但它铺满全屏 —— 关掉命中测试，
            // 免得哪天有人在里面加一个带背景色的容器就把整个标签栏点不动了。
            .allowsHitTesting(viewModel.isInviteSheetPresented)
        }
    }
}

/// 把同一个宿主里 `TabView` 背后的 `UITabBarController` 整棵视图树对读屏藏起来。
/// 为什么要下到 UIKit，见 `VolunteerTabView.body` 里 `.accessibilityHidden` 上方那段注释。
///
/// 从自己往上找到第一个 view controller（托管 `TabView` 的那个 hosting controller），
/// 再往下找它的 `UITabBarController` 子控制器，把它根视图的 `accessibilityElements` 置空。
/// 一处就盖住所有 tab、每个 tab 里 push 出去的二级页和标签栏本身；
/// 从卡片里弹出的 `fullScreenCover` 不在这棵树里，不受影响（同一条用例点「查看详情」验过）。
///
/// ⚠️ 用的是「子元素列表置空」而不是 `accessibilityElementsHidden` —— 后者在这里真机实测无效，
/// 理由见 `VolunteerTabView.body` 里那段注释。
private struct TabBarAccessibilityHider: UIViewRepresentable {
    let isHidden: Bool

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        let isHidden = isHidden
        // 第一次 update 时这个 view 还没进窗口、responder 链是断的 —— 推到下一拍再找。
        DispatchQueue.main.async {
            Self.tabBarController(near: uiView)?.view.accessibilityElements = isHidden ? [] : nil
        }
    }

    private static func tabBarController(near view: UIView) -> UITabBarController? {
        guard let host = sequence(first: view as UIResponder, next: \.next)
            .first(where: { $0 is UIViewController }) as? UIViewController
        else { return nil }
        return firstTabBarController(in: host)
    }

    private static func firstTabBarController(in controller: UIViewController) -> UITabBarController? {
        if let tabBarController = controller as? UITabBarController { return tabBarController }
        return controller.children.lazy.compactMap(firstTabBarController(in:)).first
    }
}
