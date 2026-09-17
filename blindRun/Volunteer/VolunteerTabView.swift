import SwiftUI

// MARK: - Volunteer Tab Container

/// 陪跑员端的根容器：首页 / 记录 / 我的（设计交付 v3 §4.1「导航结构」）。
///
/// 改版前这三样散在一处：`VolunteerHomeView` 自己就是根，「记录」只能从首屏
/// 「最近一次」旁的「全部 ›」进去、「我的」只能从首屏右上角一枚齿轮进去。
///
/// **三个 tab 挂的都是已经存在的页面**，不是新写的：
/// `VolunteerHomeView` / `VolunteerServiceRecordsView` / `VolunteerSettingsView`。
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
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @EnvironmentObject private var locationService: LocationService

    @StateObject private var viewModel = VolunteerHomeViewModel()

    @State private var selection: Tab = .home

    private enum Tab: Hashable {
        case home
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
                .tag(Tab.home)

            NavigationStack {
                VolunteerServiceRecordsView()
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
        // 🚩 **派单弹窗挂在 `TabView` 外面。**
        //
        // 挂在某个 tab 的栈内根视图上时，push 出任何二级页（陪跑培训、服务记录、成就、设置）
        // 之后弹窗会被那一页盖住；挂在某一个 tab 上时，他切到别的 tab 就看不见。
        // 模态是最高优先级：不管他在哪一页、哪一个 tab，30 秒倒计时都必须看得见。
        //
        // 🚩 同一条理由决定了首屏那些入口一律用 `NavigationLink` 而不是 `.sheet`：
        // sheet 是盖在整个容器之上的，会反过来把这个 overlay 挡住。
        .overlay {
            if let incomingOrder = viewModel.incomingOrder {
                VolunteerDispatchOverlay(
                    order: incomingOrder,
                    countdown: viewModel.dispatchCountdown,
                    isResponding: viewModel.isRespondingToDispatch,
                    currentLocation: locationService.currentLocation,
                    locationAuthorized: locationService.isAuthorized,
                    fallbackCoordinate: locationService.effectiveBackendLocation,
                    // 主动作是「有意向，想先聊聊」还是「接单」，由推送里的
                    // `requiresIntroCall` 决定（`WSNewOrder.dispatchRespondAction`）。
                    // 🚨 这里**不做第二次判断** —— 判据在后端，客户端自己算必然漂移，
                    // 而漂移的表现是「界面说能直接接、后端回 409」。
                    onRespond: { action in
                        viewModel.respondToDispatch(
                            action: action,
                            currentLocation: locationService.currentLocation,
                            locationAuthorized: locationService.isAuthorized
                        )
                    },
                    onDecline: {
                        viewModel.respondToDispatch(
                            action: .decline,
                            currentLocation: nil,
                            locationAuthorized: false
                        )
                    }
                )
            }
        }
    }
}
