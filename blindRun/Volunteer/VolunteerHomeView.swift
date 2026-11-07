import Combine
import CoreLocation
import SwiftUI

/// 首页那个「可服务」开关叫什么名字 —— **全 App 单一来源**。
///
/// 🔴 存在的理由是一个真实缺陷：资质审核通过的引导语此前写的是
/// 「请回到首页开启**接单开关**」（`VolunteerCertificateUploadView.swift:105`、`:130`），
/// 而首页那个控件叫「可服务开关」。**首页上根本没有叫「接单开关」的东西** ——
/// 用户照着那句话回首页找，找到的是另一个名字，没有办法确认这是不是同一个控件。
/// 对按控件名导航的读屏用户尤其致命，但看得见的人一样要停顿一下。
///
/// 抽成常量而不是写一条「两处文案要一致」的用例：常量化之后两处**不可能**再各叫各的，
/// 而用例只能在漂移发生之后报警。
enum VolunteerAvailabilityCopy {
    static let toggleTitle = "可服务开关"

    /// 引导用户去开这个开关的那半句。资质审核通过、身份材料通过两条路径共用。
    static let goOpenItHint = "请回到首页开启\(toggleTitle)。"
}

// MARK: - Volunteer Home Layout Helpers

/// 志愿者首页这一屏的圆角档位。**四档各有语义，不是四个可以互换的数。**
///
/// 立这个表的起因：全 App 的 `cornerRadius` 实测有 10 个取值
/// （8×46 / 12×36 / 16×17 / 14×11 / 18×4 / 20·28·999×2 / 10·24×1），
/// 而同一屏上派单状态卡是 16、当前订单卡是 20、卡内小格是 12 —— 没有规律可循，
/// 下一个人加卡片时只能随手挑一个，于是取值继续发散。
///
/// ⛔ **作用域刻意只到这一屏。** 跨屏共用的 `PartnerRowCard` 是 14，改它会波及盲人端的固定搭档页 —— 那不在本次范围内，
/// 且纯视觉收敛没有任何测试守得住，改坏了不会有信号。要全 App 统一是另一件事。
enum VolunteerHomeRadius {
    /// 居中弹出的模态对话框（派单弹窗）。
    static let modal: CGFloat = 24
    /// 内容流里的每一张卡片。
    static let card: CGFloat = 16
    /// 卡片**内部**的元素：小格子、整行按钮、内嵌地图。
    /// 比外层小是为了套着好看，不是另一套体系。
    static let tile: CGFloat = 12
}

// MARK: - Volunteer Home View

/// 志愿者端「首页」tab 的内容。**它本身只剩三件事**：装第一屏、把可服务开关挂在底部、
/// 管这一条 `NavigationStack` 上的三个落点。内容**全部**在 `VolunteerProfileFirstScreen` 里，
/// 志愿者端主屏现在只有这一屏，没有任何二级的「工作台」。
///
/// > 2026-09-14 从「地图铺满 + 底部可拖面板」的叠层结构改成这样。原结构有两个硬伤：
/// > ① 那张底图 `annotations` 恒为 `[]`，只画「我在哪」，却占着整屏；
/// > ② 面板拖到 `.compact` 档时**整块内容不渲染**，志愿者的服务量、勋章、最近陪跑
/// >   随手一拖就全没了。设计稿与依据见
/// >   `docs/ui/mockups/volunteer-profile-first-screen-20260914/`。
/// >
/// > 2026-09-15 又删掉了那一轮引入的二级页 `VolunteerDispatchWorkbenchView`（用户原话
/// > 「好像是没什么用的」）。连带删掉那张辅助地图：它的 `annotations` 仍恒为 `[]`，
/// > 唯一信息「我在哪」在派单卡的覆盖范围文字里已经有一份。**删地图 ≠ 停定位** ——
/// > 那两行现在在 `VolunteerTabView` 上，不许跟着删。
/// >
/// > 2026-09-17 它**不再是志愿者端的根**（设计交付 v3 §4.1 的底部三标签）。
/// > 根是 `VolunteerTabView`，view model 的所有权、生命周期与派单弹窗都在那一层 ——
/// > 搬上去的理由见那个文件，不是为了好看，是 `TabView` 的硬约束。
struct VolunteerHomeView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var locationService: LocationService
    /// **由 `VolunteerTabView` 注入，不再自己 `@StateObject` 持有。**
    /// 派单弹窗挂在 tab 容器上，而它和这一屏必须读同一份派单状态。
    @ObservedObject var viewModel: VolunteerHomeViewModel
    /// 接单主页（设计交付 v3 的 S3/S4）。滑块向右滑过阈值时置位。
    @State private var showsDispatchHub = false
    @State private var showsReadinessProgress = false

    var body: some View {
        NavigationStack {
            VolunteerProfileFirstScreen(viewModel: viewModel, onReload: loadHome)
                .navigationTitle("")
                .navigationBarHidden(true)
                // 一个 destination 分三种落点，不是三个 `navigationDestination(isPresented:)` ——
                // 同一个视图上挂多条 `isPresented` 版本在 iOS 16 上会互相顶掉。
                //
                // 🚩 顺序即优先级：通话磨合 > 已接下的单 > 接单主页。前两者是**有时限**的
                // （通话窗口 20 分钟、订单在走），接单主页随时可以再进。
                .navigationDestination(
                    isPresented: Binding(
                        get: {
                            viewModel.acceptedDispatchOrderId != nil
                                || viewModel.pendingIntroCallOrder != nil
                                || showsDispatchHub
                                || showsReadinessProgress
                        },
                        set: { isPresented in
                            if !isPresented {
                                viewModel.acceptedDispatchOrderId = nil
                                viewModel.acceptedDispatchInitialOrder = nil
                                viewModel.clearIntroCall()
                                showsDispatchHub = false
                                showsReadinessProgress = false
                            }
                        }
                    )
                ) {
                    if let introCallRoute = viewModel.pendingIntroCallOrder {
                        VolunteerIntroCallView(route: introCallRoute)
                    } else if let orderId = viewModel.acceptedDispatchOrderId {
                        VolunteerInServiceView(
                            orderId: orderId,
                            initialOrder: viewModel.acceptedDispatchInitialOrder
                        )
                    } else if showsDispatchHub {
                        VolunteerDispatchHubView(viewModel: viewModel, onReload: loadHome)
                    } else if showsReadinessProgress {
                        VolunteerReadinessProgressView()
                    }
                }
                // 🚩 **挂在栈内的根视图上，不是挂在 `NavigationStack` 或 `TabView` 上。**
                // 挂高一层的话 push 出去的接单主页 / 订单页底部也会长出一个滑块，
                // 与那一页自己的「暂停接单」直接打架；而设计交付 v3 §4.2 总表里
                // S3/S4 的主按钮一栏写的就是「无」。
                //
                // `safeAreaInset` 本身就让滚动内容停在底座上方 —— v3 验收「底座不能压住内容」靠的是它，
                // 不是靠底座半透明。
                .safeAreaInset(edge: .bottom) {
                    availabilityCTA
                }
                .onChange(of: viewModel.entersDispatchHubAfterTrackConsent) { enters in
                    guard enters else { return }
                    viewModel.entersDispatchHubAfterTrackConsent = false
                    showsDispatchHub = true
                }
        }
    }

    /// 底部的可服务开关。**它替代了原来那个 `Toggle`** —— 依据是 Uber Base
    /// Sliding button 的用途判据「引入摩擦以确认意图」，而「从这一刻起开始收派单」
    /// 正是一个有后果的动作（`docs/research/volunteer-profile-first-screen-20260914.md` §3）。
    ///
    /// 🚩 **向右滑同时做两件事：开启接单 + 进入接单主页。** 设计交付 v3 的流程就是这一条
    /// （主页 → 滑动 → 接单主页），理由是开启之后志愿者要看的「下一次陪跑 / 待回复的邀请」
    /// 都不在首页上。已经开启时点按胶囊只做后一件。
    private var availabilityCTA: some View {
        let status = viewModel.availabilityStatus
        let isEnabled = status.allowsOpening(isRegistrationComplete: appState.isVolunteerProfileApproved)
        // v3（#694）：白色底座里一枚胶囊，替换改版前那条饱和绿色通栏。取值照样例
        // （底座圆角 24、内边距 8、左右各留 16）。
        return VStack(alignment: .leading, spacing: 8) {
            trackConsentDeclinedNotice
            VolunteerAvailabilitySlider(
                isAvailable: viewModel.isAvailable,
                isEnabled: isEnabled,
                isUpdating: viewModel.isUpdatingAvailability,
                status: status,
                notice: status.notice(
                    certificate: .from(
                        status: .parse(appState.volunteerProfile?.verificationStatus),
                        statusLoadFailed: false
                    ),
                    isAlternativeIdentityPath: appState.volunteerRegistrationStatus?.hasDeclinedFaceVerification == true
                ),
                statusText: viewModel.statusText,
                onChange: { viewModel.setAvailability($0) },
                // #368：滑开时若要先问位置轨迹同意，同意页盖上来，接单主页等同意之后再推。
                onEnterHub: {
                    guard viewModel.trackConsentRequest == nil else { return }
                    showsDispatchHub = true
                },
                onShowProgress: { showsReadinessProgress = true }
            )
            // 🔴 **开着却进不了接单页时，停止接单必须还有一条看得见的路。**
            // v3 去掉了向左滑停止，常规的停止入口是接单页的「暂停接单」；可接单期间资质被撤销 / 培训被重置
            // （胶囊点进去是接单前进度）或注册状态没同步时，接单页够不着 ——
            // 「停止接单」任何时候都必须能做（`VolunteerAvailabilitySlide.acceptsGesture`）。
            if viewModel.isAvailable, status.blocksOpening || !isEnabled {
                Button(VolunteerAvailabilityCopy.closeTitle) { viewModel.setAvailability(false) }
                    .buttonStyle(TextButtonStyle())
                    .frame(maxWidth: .infinity)
                    .disabled(viewModel.isUpdatingAvailability)
                    .accessibilityHint(VolunteerAvailabilityCopy.closeHint)
                    .accessibilityIdentifier("volunteerHomeStopAvailabilityButton")
            }
        }
        .padding(8)
        // 🔴 阴影只挂在底座的形状上。挂在整个 VStack 上的话，胶囊里的字也会带一圈暗影，
        // 真机审计把「接单中 · 进入接单」判成对比度不足（2026-11-04）。
        .background {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(AppColors.Flow.surface)
                .shadow(color: .black.opacity(0.09), radius: 5, x: 0, y: 2)
        }
        .padding(.horizontal, FlowMetrics.pageHorizontalPadding)
        .padding(.top, 14)
        .padding(.bottom, 8)
        // 底座后面那条渐隐：内容滚到底座下面时淡出，不是一刀切（样例 `linear-gradient(… 0, bg 26px)`）。
        .background {
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [AppColors.Flow.page.opacity(0), AppColors.Flow.page],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 26)
                AppColors.Flow.page
            }
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier("volunteerHomeBottomBar") // 审计按它判内容滚到栏后，栏里的滑块照常审
    }

    /// 拒绝位置轨迹同意之后，滑块上方那句后果说明（#368）。拒绝时已念过一遍，这里是留在屏幕上的那一份。
    @ViewBuilder
    private var trackConsentDeclinedNotice: some View {
        if let notice = viewModel.trackConsentDeclinedNotice {
            Text(notice)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.top, 4)
                .accessibilityIdentifier("volunteerTrackConsentDeclinedNotice")
        }
    }

    private func loadHome() async {
        await viewModel.load(
            currentLocation: locationService.currentLocation,
            locationAuthorized: locationService.isAuthorized
        )
    }
}

#if DEBUG
#Preview {
    VolunteerTabView()
        .environmentObject(AppState())
        .environmentObject(SpeechService())
        .environmentObject(LocationService())
}
#endif
