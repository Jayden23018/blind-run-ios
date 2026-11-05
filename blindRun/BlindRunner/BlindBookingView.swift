import Combine
import CoreLocation
import SwiftUI
import UIKit

// MARK: - Booking Option Types

enum BookingDurationOption: Int, CaseIterable, Identifiable {
    case none = 0
    case fifteen = 15
    case thirty = 30
    case fortyFive = 45
    case sixty = 60
    case ninety = 90
    case oneTwenty = 120

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .none: return "不填写"
        case .fifteen: return "15 分钟"
        case .thirty: return "30 分钟"
        case .fortyFive: return "45 分钟"
        case .sixty: return "1 小时"
        case .ninety: return "1.5 小时"
        case .oneTwenty: return "2 小时"
        }
    }

    var minutes: Int? {
        rawValue == 0 ? nil : rawValue
    }
}

/// 预约时间过不了的三种原因。文案集中在这里，是为了让「提示行 / 步骤阻断语 / 语音摘要」
/// 三处说的是同一句话 —— 它们此前各写各的，其中两处把 30 分钟硬编码进了句子。
enum BookingTimeProblem: Equatable {
    case tooSoon
    case tooFar
    case nightWindow

    var message: String {
        switch self {
        case .tooSoon:
            // 数字取自常量，与 `minimumAppointmentTime` 同源 —— 写死会在后端调整提前量时变成假话。
            return "当前选择的时间太近了，请改到 \(AppConstants.Timing.minimumBookingLeadMinutes) 分钟以后。"
        case .tooFar:
            return "最多只能约 \(AppConstants.Timing.maximumBookingLeadDays) 天以内的时间，请改到近一些的日子。"
        case .nightWindow:
            // 🚨 必须说清判据是**整段**。只说「这个时间不能约」的话，21 点出发的用户会认为
            // 自己没碰到 22 点，把开始时间往前挪一点再试 —— 而真正越界的是结束时间。
            //
            // 时刻从常量取（同 `.tooSoon` / `.tooFar`），不写死在句子里：后端改窗口时
            // 写死的那两个数会变成骗人的话，而这条与本文件早就写着的
            // 「写死 30 会在后端调整提前量时变成一句骗人的话」是同一条理由。
            // 念「晚上10点 / 早上5点」而不是 `22:00` / `05:00`：这段要过 TTS，
            // 念钟点比念数字冒号稳，所以只取小时数、自己拼成钟点。
            let start = AppConstants.Timing.nightWindowStartHour
            let end = AppConstants.Timing.nightWindowEndHour
            return "晚上\(start - 12)点到次日早上\(end)点之间不安排陪跑。此订单从开始到结束整段都要避开这个时段，"
                + "请改到白天，或者把时长改短、让它在晚上\(start - 12)点前结束。"
        }
    }
}

enum BlindBookingGuidedStep: Int, CaseIterable, Identifiable {
    case startPoint
    case appointmentTime
    case runningNeeds
    case review

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .startPoint:
            return "确认出发地点"
        case .appointmentTime:
            return "确认预约时间"
        case .runningNeeds:
            return "跑步需求"
        case .review:
            return "确认并提交"
        }
    }

    var shortName: String {
        switch self {
        case .startPoint:
            return "地点"
        case .appointmentTime:
            return "时间"
        case .runningNeeds:
            return "需求"
        case .review:
            return "确认"
        }
    }

    var nextActionTitle: String {
        switch self {
        case .startPoint:
            return "下一步：预约时间"
        case .appointmentTime:
            return "下一步：跑步需求"
        case .runningNeeds:
            return "下一步：确认预约"
        case .review:
            return "提交预约"
        }
    }

    var nextSpeechAction: String {
        switch self {
        case .startPoint:
            return "确认地点后进入预约时间。"
        case .appointmentTime:
            return "确认时间后进入跑步需求。"
        case .runningNeeds:
            return "可跳过选填需求，进入确认预约。"
        case .review:
            return "确认无误后提交预约。"
        }
    }
}

struct BookingReviewItem: Identifiable, Equatable {
    let id: String
    let title: String
    let value: String
}

// MARK: - Booking Gate

/// `POST /api/orders` 的硬门槛，枚举顺序即「第一个可操作的缺失项」的播报顺序。
///
/// 服务端门槛的唯一真源是 `OrderCreationService.createOrder`：无紧急联系人 → 403 `EMERGENCY_CONTACT_REQUIRED`。
/// 2026-11-05 起不再校验实名（#767，后端 blind-run-backend#924）。
/// `basicProfile` 是客户端自有的前置项（后端不校验 `BlindProfile.name`），保持在最前。
///
/// ⚠️ **定位权限被拒不在这里，这是刻意的。** 2026-08-18 之前它是第四道门槛，拒绝定位后
/// 整个出发地点区块被权限提示顶掉（搜索框、常用地点、语音输入全不渲染），`canSubmit` 恒 false ——
/// 也就是关掉定位等于 App 的核心功能不可用。Apple 审核指南 **5.1.1(iv)** 举的例子与这个场景
/// 逐字吻合：拒绝定位后应当提供手动输入地址的替代路径。高德 POI 搜索本来就不需要定位权限
/// （`searchPlaces` 只依赖 `placeSearchProvider`），那条替代路径一直存在，只是被这道门槛藏起来了。
///
/// 拿掉门槛**不等于**当作没事：定位关着会真的降级两件事（陪跑中志愿者看不到实时位置、
/// 云端求助拿不到坐标会发不出去，见 `EmergencyCoordinator.allowsSubmissionWithoutLocation`），
/// 所以改成**可听可见的降级告知**而不是拦截 —— `BlindBookingViewModel.locationDegradationNotice(isDenied:)`。
/// 志愿者侧的「无定位不接单」没有动：那一侧的实时位置是服务本体，不是可替代的输入。
enum BlindBookingGate: Equatable {
    case basicProfile
    case emergencyContacts
    case startPoint
    case appointmentTime

    static func firstMissing(
        isBasicProfileComplete: Bool,
        hasValidEmergencyContacts: Bool,
        hasStartPoint: Bool,
        isAppointmentTimeValid: Bool
    ) -> BlindBookingGate? {
        if !isBasicProfileComplete { return .basicProfile }
        if !hasValidEmergencyContacts { return .emergencyContacts }
        if !hasStartPoint { return .startPoint }
        if !isAppointmentTimeValid { return .appointmentTime }
        return nil
    }

    /// 要去别的页面补的两项（昵称 / 紧急联系人）。约跑页顶部的 `BlindBookingMissingSetupCard` 就是补它们的入口。
    static let setupGates: [BlindBookingGate] = [.basicProfile, .emergencyContacts]

    /// 这句话是不是上面两项之一的缺失说明。补齐回来时据它撤掉留在屏幕上的旧句子。
    static func isSetupMessage(_ text: String) -> Bool {
        setupGates.contains { $0.message == text }
    }

    /// 展示与朗读共用的缺失说明。
    var message: String {
        switch self {
        case .basicProfile:
            // 约跑页最上面就是补这一项的入口（`BlindBookingMissingSetupCard`，#781）。
            return "约跑前还要填一个昵称。点本页最上面的「昵称」去填。"
        case .emergencyContacts:
            return "约跑前还要设好紧急联系人：至少 1 位，并设其中 1 位为主联系人。点本页最上面的「紧急联系人」去设。"
        case .startPoint:
            return "请选择出发地点。"
        case .appointmentTime:
            // 只是兜底：要说「具体哪里不行」走 `BlindBookingViewModel.message(for:)`，它读 `appointmentTimeProblem`。
            return "预约时间需至少在 \(AppConstants.Timing.minimumBookingLeadMinutes) 分钟后。"
        }
    }
}

// MARK: - Blind Booking View

struct BlindBookingView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var locationService: LocationService
    @EnvironmentObject var speechService: SpeechService
    @EnvironmentObject var speechInputService: SpeechInputService
    @EnvironmentObject private var amapGeocodingService: AMapGeocodingService
    @Environment(\.dismiss) private var dismiss
    @StateObject var viewModel = BlindBookingViewModel()
    @StateObject var voiceWizard = VoiceOrderWizard()
    /// 常用出发地点。纯本地（`UserDefaults`），不与后端同步 —— 理由见 `FavoritePlaceStore`。
    @StateObject var favorites = FavoritePlaceStore()
    @AccessibilityFocusState var focusedSearchResultID: String?
    /// 换步后读屏焦点的落点。绑在 `guidedStepHeader` 的标题行上。
    @AccessibilityFocusState var focusedStepHeader: BlindBookingGuidedStep?
    /// 选定出发地点后读屏焦点的落点：结果列表选中即整块消失，被点的按钮随之销毁（#295 走查 A3）。
    @AccessibilityFocusState var focusedStartPlaceCard: Bool
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) var differentiateWithoutColor
    @Environment(\.verticalSizeClass) var verticalSizeClass
    @State var isPulsing = false
    /// 零输入下单走到第二步（复核整单）了没有。见 `zeroInputBookingSection`。
    @State var isZeroInputConfirming = false
    /// 第一次用语音下单前的单独同意页（转写文字交给第三方大模型，#374）。
    @State var showsVoiceConsent = false
    /// 这一次进入下单页后用户拒绝过同意。只拦 `onAppear` 的**自动**启动：同意页关闭后若下单页又触发
    /// 一次 `onAppear`，没有它就会再弹一次 —— 对刚拒绝的人那是劝返，也可能是循环。
    /// 用户自己再点语音按钮 / Magic Tap 不受影响，那是他主动再次发起。
    @State var declinedVoiceConsentThisVisit = false
    /// 这一页已经出现过一次。从「约跑前还差 N 项」推进去的页面返回时 `onAppear` 会再触发一次，
    /// 那一次不能再自动开语音（用户可能刚改用表单），只更新「还差什么」（#781）。
    @State var hasAppearedOnce = false
    /// 从首页「语音下单」进来时为 `true`，页面出现即启动向导。表单入口进来则为 `false`，
    /// 语音仍可随时手动启动 —— 语音是加速器，不是另一条平行流程。
    let startsWithVoice: Bool
    /// 用户在首页设的默认出发地点。nil 表示用当前定位。
    let initialStartPlace: ResolvedPlace?
    let onOrderCreated: (OrderResponse) -> Void

    init(
        startsWithVoice: Bool = false,
        initialStartPlace: ResolvedPlace? = nil,
        onOrderCreated: @escaping (OrderResponse) -> Void
    ) {
        self.startsWithVoice = startsWithVoice
        self.initialStartPlace = initialStartPlace
        self.onOrderCreated = onOrderCreated
    }

    var body: some View {
        // **语音态与表单态互斥，不并排。** 这一页此前把语音区和四步表单堆在同一个滚动视图里，
        // 于是「语音下单」进来看到的是十几条 StaticText 加两个文本框 —— 那不是语音下单页，
        // 是一张表单外加给每个字段配了一个麦克风按钮。用户 2026-08-08 的原话：
        // 「表单的形式不应该给盲人用」。
        //
        // 表单没有消失，它是**降级出路**（语音坏了）也是**隐私出路**（在地铁上不想说出自己在哪，
        // 见 `docs/research/blind-voice-booking-ia-20260805.md` §9.3）。它只是不再与语音同屏共存。
        Group {
            if showsVoiceStage {
                voiceStage
            } else {
                ScrollView {
                    formStage
                        .padding(.horizontal, 24)
                        .padding(.top, 24)
                        .padding(.bottom, 120)
                        // 表单在 iPad 上不铺满整屏：输入框横跨 1024pt 时，低视力用户把字放大后
                        // 每填一项都要横扫全屏才找得到右边的按钮。见 `BlindLayout.readableContentWidth`。
                        .readableContentColumn()
                }
            }
        }
        .background(AppColors.background)
        // 两指双击是 iOS 上「开始/停止录音」的标准手势（Apple 把 recording 列为 Magic Tap 的典型用途）。
        // `voiceStatusBlock` 那一整块对**触摸**用户是零成本的，但对 VoiceOver 用户不是：读屏下必须先把
        // 焦点滑到那个元素才能双击激活，「不用找」这个目标恰恰对真正的目标用户没实现。Magic Tap 补的是这一半。
        //
        // 顺带堵住一个副作用：不实现时，两指双击会沿响应链穿透到系统去播放/暂停音乐 ——
        // 用户在录音中做这个手势会莫名开始放歌。
        .accessibilityAction(.magicTap) {
            if voiceWizard.isRunning {
                voiceWizard.finishSpeakingOrSkipPrompt()
            } else {
                startVoiceWizard()
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !placesVoiceControlsBeside {
                // 整条底栏的范围：审计按它判「内容滚到栏后面」，不按文案放行（`AccessibilityAuditTests+Audit`）。
                submitArea.accessibilityElement(children: .contain).accessibilityIdentifier("blindBookingBottomBar")
            }
        }
        .safeAreaInset(edge: .trailing, spacing: 0) {
            if placesVoiceControlsBeside {
                submitArea
            }
        }
        .navigationTitle("创建预约")
        .navigationBarTitleDisplayMode(.inline)
        // 二级页藏标签栏：横屏下悬浮胶囊压在「重复一遍 / 改用表单」上（记忆 tab-bar-clips-the-last-line-of-secondary-pages）。
        // 这一页的返回箭头始终在，藏栏不会丢出口。
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            if locationService.isNotDetermined {
                locationService.requestPermission()
            }
            viewModel.configure(
                appState: appState,
                locationService: locationService,
                speechService: speechService,
                amapGeocodingService: amapGeocodingService
            )
            Task { await viewModel.refreshCurrentLocation() }
            voiceWizard.configure(
                bookingViewModel: viewModel,
                speechService: speechService,
                speechInputService: speechInputService,
                voiceOrderService: appState.voiceOrder,
                // ⚠️ **必须放宽新鲜度门，别用默认的 15 秒**（2026-08-10，N48 的客户端那一级）。
                //
                // 非陪跑模式下 `distanceFilter = 10`，站着不动 Core Location 就不推新样本；
                // 而语音下单恰恰是**站着说完一整句**，说完通常已经超过 15 秒 ——
                // 于是这个闭包返回 nil、请求不带坐标，后端只能做全国范围解析。
                // 用户报的「定位开着，在深圳说的地名却定位到海南」根因链的第一环就是这里。
                //
                // 300 秒对「50 公里半径内就近消歧」绰绰有余：真要走出这个误差，人早就不在原地了。
                // **只改这一处、不动方法默认值** —— 另外三个调用点（`ContentView`、
                // `EmergencyCoordinator`、`VolunteerOrderFlowViews`）各有各的新鲜度要求，不该被顺带改掉。
                currentCoordinate: { locationService.latestBackendSample(freshness: 300) }
            )
            if let initialStartPlace, viewModel.selectedStartPlace == nil {
                viewModel.defaultStartPlace = initialStartPlace
                viewModel.selectPlace(initialStartPlace, announce: false)
            }
            if holdVoiceStageForUITestingIfRequested() {
                // 接缝已经把向导按在运行态，下面两条分支都会去碰麦克风，跳过。
            } else if hasAppearedOnce {
                // 从补资料的页面回来：只更新「还差什么」，不重开语音。
                voiceWizard.refreshSetupGateFallback()
                viewModel.announceEntryGateIfNeeded()
            } else if startsWithVoice, !voiceWizard.isRunning, !declinedVoiceConsentThisVisit {
                startVoiceWizard()
            } else {
                viewModel.announceEntryGateIfNeeded()
            }
            hasAppearedOnce = true
        }
        .onDisappear {
            // 页面离开就停录音：麦克风不该在用户看不见的地方继续开着。
            voiceWizard.stop()
        }
        .requestsLocationUpdates(.blindBooking)
        // 用户在系统弹窗里允许了临时精确位置：不等下一个坐标，立刻按新的授权重新解析（#373）。
        .onChange(of: locationService.accuracyAuthorization) { _ in
            Task { await viewModel.refreshCurrentLocationIfNeeded() }
        }
        .onChange(of: locationService.currentLocation) { _ in
            Task { await viewModel.refreshCurrentLocationIfNeeded() }
        }
        .onChange(of: viewModel.searchResultFocusID) { focusID in
            focusedSearchResultID = focusID
        }
        // 语音态下卡片不在视图树里，别把焦点状态置位成悬空的 true。
        .onChange(of: viewModel.selectedStartPlace?.id) { placeID in
            if placeID != nil, !voiceWizard.isRunning { focusedStartPlaceCard = true }
        }
        // 换步之后把读屏焦点搬到新步骤的标题上。
        //
        // 不搬的话焦点留在刚按下的「下一步」按钮上 —— 那个按钮在页面**底部**，
        // 而新内容整块出现在它**上面**。读屏用户按完只听到按钮标题变了，
        // 得反向往上滑好几次才够得着这一步要他做的事。看得见的人一眼扫到，看不见的人没有这条捷径。
        //
        // 用 `@AccessibilityFocusState` 而不是 `UIAccessibility.post(.screenChanged)`：
        // 后者把焦点扔到屏幕**第一个**元素（导航栏），还得再往下滑过标题和进度点；
        // 前者精确落在「当前步骤」那行标题上，下一个元素就是要填的东西。
        .onChange(of: viewModel.currentStep) { step in
            focusedStepHeader = step
        }
        // 前提消失就回到第一步。这一条堵的是「门槛中途变化」那类路径（例如用户去系统设置关掉定位
        // 再打开）：`zeroInputBookingSection` 期间被整块藏起来，再出现时不该还停在提交那一步。
        //
        // 它**盖不住**「重启语音后又失败」那条 —— 那条路上这个布尔值一直是 true（`fallBack` 换的是
        // 消息内容，不是有无），所以 `startVoiceWizard()` 里另有一次显式复位。两处缺一不可。
        .onChange(of: isZeroInputOfferAvailable) { isAvailable in
            if !isAvailable {
                isZeroInputConfirming = false
            }
        }
        // 全屏而不是 sheet：每条告知要各自可听、可停、可回头再听。
        // ⚠️ 系统模态**不会**把背后的下单页移出读屏树（2026-10-14 真机实测），由 `voiceConsentScreen`
        // 里的 `PresenterAccessibilityHider` 藏（记忆 hide-uikit-hosted-tree-from-accessibility）。
        .fullScreenCover(isPresented: $showsVoiceConsent) {
            voiceConsentScreen
        }
        .onChange(of: voiceWizard.step) { step in
            // 表单跟着向导走：语音填到哪一项，屏幕上就停在哪一项，读屏用户切回手动时不用重新找位置。
            // 只剩整句和读回两轮，两轮屏幕都停在确认页：向导念的就是这一页的内容，
            // 用户中途切回手动时看到的和刚听到的是同一件事。
            //
            // 逐项修改删掉之后，这里再也不会在用户说话的中途把屏幕换成另一张表单
            // （2026-08-06 用户报的「点了改地点之后跳转到了一个界面」）。
            // 候选消歧轮同样停在确认页：它问的是「出发地是哪一个」，而出发地就在这一页上。
            // 换页会把用户从他刚听到的内容上挪开 —— 那正是 2026-08-06 删掉逐项追问的理由。
            switch step {
            case .freeform, .disambiguateStart, .confirm: viewModel.currentStep = .review
            }
        }
        // 语音提交与按钮提交共用同一个出口，跳转逻辑只有一份。
        .onReceive(voiceWizard.$createdOrder.compactMap { $0 }) { response in
            onOrderCreated(response)
        }
    }

}

// MARK: - 语音态底栏按钮样式

#if DEBUG
#Preview {
    NavigationStack {
        BlindBookingView { _ in }
            .environmentObject(AppState())
            .environmentObject(LocationService())
            .environmentObject(SpeechService())
            .environmentObject(SpeechInputService())
            .environmentObject(AMapGeocodingService())
    }
}
#endif

/// 语音预约屏上的固定文字。
enum VoiceBookingCopy {
    /// 第一步的大标题：屏幕上只放问题本身，说明与示例走语音与读屏（2026-10-07）。
    static let freeformHeadline = "什么时候、在哪里跑？"
}
