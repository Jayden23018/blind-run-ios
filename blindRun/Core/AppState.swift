import Combine
import Foundation
import SwiftUI

enum SessionRestorationState: Equatable {
    case restoring
    case validationFailed(message: String)
    case unauthenticated
    case choosingRole
    case authenticated
}

// MARK: - AppState

/// 全局应用状态，管理用户会话、Token 和环境配置。
/// 作为 @EnvironmentObject 注入整个应用的 View 层级。
@MainActor
final class AppState: ObservableObject {
    let mockAPIClient = MockAPIClient()
    /// 补撤（`revocationTransport`）也要用它，所以不是 private。
    let apiClientOverride: (any APIClientProtocol)?
    let authOverride: (any AuthServing)?
    let incentiveOverride: (any IncentiveServing)?
    let safetyOverride: (any SafetyServing)?
    let ordersOverride: (any OrderServing)?
    let persistence: AppStatePersistence
    let tokenStore: any TokenStoring
    /// refresh token 续期（#391）。每次新建的 `URLSessionAPIClient` 都带上它，single-flight 才是全 App 一份。
    let tokenRefresher: SessionTokenRefresher
    /// 退出登录时服务端没撤成的部分（解绑推送、登出），联网 / 回前台 / 下次登录前补撤（#459）。
    private(set) lazy var pendingSessionRevoker = PendingSessionRevoker(
        store: PendingSessionRevocationStore(storage: TokenStoreFactory.makeDefault(account: .pendingSessionRevocation)),
        transport: { [weak self] accessToken in self?.revocationTransport(accessToken: accessToken) },
        currentUserID: { [weak self] in self?.isLoggedIn == true ? self?.userId : nil },
        onSameAccountUnbound: { [weak self] in self?.pushNotificationsManager?.reportTokenAgainAfterServerUnbind() }
    )
    let realtimeCoordinator: AppRealtimeCoordinator
    let liveEscortCoordinator: LiveEscortSessionCoordinator
    let emergencyCoordinator: EmergencyCoordinator
    /// 由 `blindRunApp.configurePushNotifications()` 注入。`weak` 是因为真正持有它的是那边的
    /// `@StateObject` —— 这里只是为了让登出流程能在**拉黑 JWT 之前**解绑本机 APNs token。
    weak var pushNotificationsManager: PushNotificationsManager?
    /// 由 `blindRunApp` 根视图注入，`weak` 的理由同上。持续定位按账号 + 角色的位置轨迹同意收（#417）：
    /// 退出登录、换到没同意的角色时，这里替整个 App 停掉 —— 没有别的地方会停。
    /// 角色这一层的定位意图（`syncRoleLocationIntents`）也由这里管，注入时补算一次（#425）。
    weak var locationService: LocationService? {
        didSet { syncRoleLocationIntents() }
    }
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Session

    /// JWT 访问令牌（持久化在 Keychain，见 `KeychainTokenStore`）
    ///
    /// 🔴 **续期换 token 不走下面那段重置**（`applyRenewedAccessToken`）。值变了就断实时通道、
    /// 重置陪跑会话与求助协调器，是为登录 / 登出 / 换账号写的 —— 续期也走它的话，
    /// 跑步途中每次续期都会把正在进行的会话清一遍，比被踢回登录页还隐蔽。
    @Published var accessToken: String? {
        didSet {
            persistToken()
            if oldValue != accessToken, !isApplyingRenewedAccessToken {
                sessionGeneration &+= 1
                realtimeCoordinator.detach(clearSessionState: true)
                liveEscortCoordinator.reset(clearIdentity: false)
                emergencyCoordinator.reset()
                locationTrackConsentGrantedThisSession = []
                volunteerWantsDispatch = false
            }
        }
    }

    /// 「这是哪一次登录」。登录 / 登出 / 换账号时变，**续期换 token 时不变**。
    ///
    /// 凡是想判「会话还是不是刚才那个」的地方用它，别拿 access token 的值比：
    /// token 现在会在一次登录里换好几次（`ContentView.rootRoutingKey`、资料加载的过期判据、
    /// `sessionIdentityKey` 原来都比 token 值，续期一次就会重跑根路由、丢掉加载结果、重置陪跑会话）。
    @Published private(set) var sessionGeneration: UInt64 = 0

    /// `applyRenewedAccessToken` 写 `accessToken` 期间为真，让 `didSet` 只持久化、不重置会话。
    var isApplyingRenewedAccessToken = false

    /// 当前用户 ID
    @Published var userId: Int64? {
        didSet {
            // Token changes already clear initial login/logout. A non-nil account switch
            // needs its own boundary even if an integration reuses the same token value.
            if oldValue != nil, oldValue != userId {
                realtimeCoordinator.detach(clearSessionState: true)
                liveEscortCoordinator.reset(clearIdentity: false)
                emergencyCoordinator.reset()
                locationTrackConsentGrantedThisSession = []
                volunteerWantsDispatch = false
                // 角色不变时 `activeRole` 那一道不会经过：换成的账号没同意就得在这里停（#417）。
                stopLocationUpdatesWithoutTrackConsent()
            }
            // 同意按账号记：账号一变，角色这一层要不要定位就得重算（包括从 nil 变成有值的恢复登录）。
            syncRoleLocationIntents()
        }
    }

    /// 仅保存在内存中的当前用户，不额外持久化手机号等身份信息。
    @Published var currentUser: CurrentUserResponse?

    @Published var sessionRestorationState: SessionRestorationState = .restoring
    @Published var logoutState: SessionOperationState = .idle
    @Published var accountDeletionState: SessionOperationState = .idle

    /// 当前激活角色（首次登录可能为 nil，需路由到角色选择）
    @Published var activeRole: UserRole? {
        didSet {
            persistActiveRole()
            mockAPIClient.syncRoleFromAppState(activeRole)
            if oldValue != activeRole {
                realtimeCoordinator.detach(clearSessionState: true)
                liveEscortCoordinator.reset(clearIdentity: false)
                emergencyCoordinator.reset()
                stopLocationUpdatesWithoutTrackConsent()
                syncRoleLocationIntents()
            }
        }
    }

    /// 当前用户的盲人跑者资料
    @Published var blindProfile: BlindProfileResponse?

    /// 当前用户的志愿者资料
    @Published var volunteerProfile: VolunteerProfileResponse?

    /// 当前用户的志愿者主注册流程状态
    @Published var volunteerRegistrationStatus: VolunteerRegistrationStatus?

    /// 紧急联系人列表
    @Published var emergencyContacts: [EmergencyContactResponse] = []

    /// 首次使用引导是否已经看过。**按设备记，登出不清**（理由见
    /// `AppConstants.UserDefaultsKeys.blindFirstRunHelpSeen`）。
    /// 走 `persistence` 而不是 `@AppStorage`，否则单元/UI 测试会写进 App 的标准域。
    @Published var didSeeBlindFirstRunHelp = false

    /// 首次启动的隐私告知是否已同意（`PrivacyConsentPurpose.appLaunch`）。
    /// 按**设备**记：同意发生在登录之前，那时还没有账号。登出不清 —— 告知的是这个 App 会收集什么，
    /// 与谁登录无关。告知内容改版时靠 key 里的版本号失效，不靠登出。
    @Published var didAcceptPrivacyConsent = false

    /// 会话过期后带到登录页展示的一次性提示。
    @Published var sessionExpirationMessage: String?

    /// 跑步中收到 401 后的「登录过期、暂缓退出」状态（#376）。nil = 没有暂缓。
    ///
    /// 后端 JWT 有有效期，订单页每 5 秒轮询一次，所以跑步途中过期是现实场景。#391 起 401 会先续期
    /// （`SessionTokenRefresher`），只有续期也被拒（refresh 过期 / 登出 / 被强制下线）才走到这里。此前任何 401 都立刻 `expireSession()`：盲人在跑道上被踢回登录页、
    /// WebSocket 断开、云端求助不可用，还要重新收短信。暂缓期间：会话保留，订单页停轮询，
    /// 云端求助一律不发（`EmergencyCoordinator.blocksCloudSOSForExpiredSession`），横幅可见可听。
    @Published var sessionExpiryDeferral: SessionExpiryDeferral?

    var isSessionExpiryDeferred: Bool { sessionExpiryDeferral != nil }

    /// 暂缓期间再收到 401 时最多多久补念一次。轮询已经停了，剩下的 401 多半来自用户自己按的按钮 ——
    /// 不补念就是「点了没反应」；每次都念又会在连按时把人淹没。
    static let deferredExpiryReminderInterval: TimeInterval = 30

    #if DEBUG
    /// 限频用的时钟。单测换成可拨的钟，免得为了 30 秒真睡 30 秒。
    var sessionClockForTesting: (() -> Date)?
    #endif

    var sessionNow: Date {
        #if DEBUG
        if let sessionClockForTesting { return sessionClockForTesting() }
        #endif
        return Date()
    }

    // MARK: - Legal Links

    /// `GET /api/misc/legal-links` 的结果。`nil` = 尚未加载 / 加载失败 / 后端未配置 URL，
    /// 三种情况入口一律回退到内置文案页（`LegalDocumentKind.destination(in:)` 已如此处理）。
    @Published var legalLinks: LegalLinksResponse?

    /// 只请求一次就够：这两个 URL 来自后端配置，不会在一次会话里变。
    /// 失败也不重试 —— 回退文案页本来就是完整可读的，为它反复打请求不值得。
    var didAttemptLegalLinksLoad = false

    // MARK: - Feature Flags

    /// `GET /api/config/features` 的结果。`nil` = 尚未加载 / 加载失败。
    ///
    /// 🔴 **拿不到时不许落成「全关」。** 消费方（目前是固定搭档两侧的空态）必须把 `nil`
    /// 当成第三种情况处理，说一句两种开关状态下都成立的话 —— 一次网络抖动不该让用户
    /// 听到「这个功能还没开放」这种关于产品状态的断言。
    @Published var featureFlags: FeatureFlagsResponse?

    /// 与 `didAttemptLegalLinksLoad` **刻意不同：失败会重试。**
    ///
    /// 那边失败的后果是回退到一份完整可读的内置文案页，代价近于零；
    /// 这边失败的后果是空态少说一句话，而用户**下一次进这一页**很可能网络已经好了。
    /// 所以只在成功后置位，失败保持 false。
    var didLoadFeatureFlags = false

    // MARK: - Rule Params

    /// `GET /api/config/rules` 的原始结果。`nil` = 尚未加载 / 加载失败。**按账号**，只由 `AppState+RuleParams.swift` 写。
    @Published var ruleParamsResponse: RuleParamsResponse?

    /// 客户端实际用的规则参数。拿不到或不合法时是默认值（见 `RuleParams`），所以**永远有值**：
    /// 这两个数只决定「多不多说一句提醒」「要不要自动打开订单页」，没有它们时退回旧行为即可。
    var ruleParams: RuleParams { RuleParams(response: ruleParamsResponse) }

    /// 与 `didLoadFeatureFlags` 同一个写法：只在成功后置位，失败下次再试。
    var didLoadRuleParams = false

    /// 待回复邀请对账的并发闸（`restorePendingInvites`，见 `AppState+PendingInvites.swift`）。
    let pendingInvitesRestoreGate = CoalescedRerun()

    // MARK: - WebSocket

    /// WebSocket 服务实例（登录后创建，登出时销毁）
    @Published var webSocketService: WebSocketService? {
        didSet {
            let role: WSRole?
            switch activeRole {
            case .blind: role = .blind
            case .volunteer: role = .volunteer
            case .unset, .none: role = nil
            }
            realtimeCoordinator.attach(to: webSocketService, role: role)
            liveEscortCoordinator.configure(
                identityKey: sessionIdentityKey,
                role: activeRole,
                webSocketService: webSocketService
            )
        }
    }

    /// WebSocket 连接状态的便捷访问
    var isWebSocketConnected: Bool {
        if case .connected = webSocketService?.connectionState {
            return true
        }
        return false
    }

    // MARK: - Environment

    /// 当前 API 环境
    ///
    /// 换环境等于换后端：mock 里拿到的 token / userId / 角色 / 资料 / 订单 ID 在真实后端一律不存在。
    /// 只持久化环境而不清会话，会让客户端拿着上一个环境的订单 ID 去查新后端（「订单不存在」），
    /// 而实时通道又按残留的订单状态把新派单显示成「已接单」，状态自相矛盾。
    /// 因此环境一变就做与 `clearSession()` 同级的本地清理，回到「刚装好」的状态。
    ///
    /// 清理会把 `sessionRestorationState` 置为 `.unauthenticated`，`ContentView` 随之路由回登录页，
    /// 持有订单的 `BlindRunnerHomeViewModel` / `BlindOrderStatusViewModel` / `VolunteerHomeViewModel`
    /// 等 `@StateObject` 随视图一起销毁，所以订单不会以 ViewModel 的形式残留。
    @Published var currentEnvironment: APIEnvironment {
        didSet {
            persistEnvironment()
            // didSet 在赋同值时也会触发，不能把用户正在用的会话误清掉。
            guard oldValue != currentEnvironment else { return }
            // 此时 currentEnvironment 已是新值：清理里的 disconnectWebSocket 只断不连，
            // connectWebSocketIfNeeded 仅由登录 / 角色切换 / 恢复会话触发，
            // 不存在用旧 baseURL 重连的顺序问题。
            performLocalSessionCleanup()
        }
    }

    /// 志愿者此刻开着接单开关（以首页 view model 为准，由它同步进来）。
    /// 不是 `@Published`：只有 `ContentView` 的定时上报读它，不驱动渲染。
    /// 关开关时连「获取」一起停（#425）：上报闸只管不上传，硬件定位要靠撤回 `.volunteerDispatch` 才停。
    var volunteerWantsDispatch = false {
        didSet { syncRoleLocationIntents() }
    }

    /// 本次登录里在位置轨迹说明页上同意过的目的。拿不到 userId 时写不了盘，
    /// 这一份让「刚同意完又被问一次」不会发生；换 token 就清掉。
    var locationTrackConsentGrantedThisSession: Set<PrivacyConsentPurpose> = []

    // MARK: - Init

    init(
        apiClient: (any APIClientProtocol)? = nil,
        auth: (any AuthServing)? = nil,
        incentive: (any IncentiveServing)? = nil,
        safety: (any SafetyServing)? = nil,
        orders: (any OrderServing)? = nil,
        persistence: AppStatePersistence? = nil,
        tokenStore: (any TokenStoring)? = nil,
        refreshTokenStore: (any TokenStoring)? = nil,
        renewalClock: @escaping () -> Date = { Date() }
    ) {
        let persistence = persistence ?? AppStatePersistenceFactory.makeDefault()
        let realtimeCoordinator = AppRealtimeCoordinator()
        self.realtimeCoordinator = realtimeCoordinator
        self.liveEscortCoordinator = LiveEscortSessionCoordinator(realtimeCoordinator: realtimeCoordinator)
        let emergencyCoordinator = EmergencyCoordinator()
        self.emergencyCoordinator = emergencyCoordinator
        self.apiClientOverride = apiClient
        self.authOverride = auth
        self.incentiveOverride = incentive
        self.safetyOverride = safety
        self.ordersOverride = orders
        self.persistence = persistence
        let tokenStore = tokenStore ?? TokenStoreFactory.makeDefault()
        self.tokenStore = tokenStore
        self.tokenRefresher = SessionTokenRefresher(
            accessStore: tokenStore,
            credentialStore: RefreshCredentialStore(
                storage: refreshTokenStore ?? TokenStoreFactory.makeDefault(account: .refreshSession)
            ),
            now: renewalClock
        )
        self.currentEnvironment = AppState.initialEnvironment(persistence: persistence)
        self.didSeeBlindFirstRunHelp =
            persistence.object(forKey: AppConstants.UserDefaultsKeys.blindFirstRunHelpSeen) as? Bool ?? false
        self.didAcceptPrivacyConsent = AppState.resolveInitialPrivacyConsent(persistence: persistence)

        // 紧急事件的后续推送在触发它的界面消失后才到，订阅点必须在 App 生命周期层。
        // provider 而不是直接传 service：环境可以在运行时切换（Mock / 生产），求助恢复必须打当下那一个。
        emergencyCoordinator.observe(realtimeCoordinator) { [weak self] in
            guard let self, self.activeRole == .blind else { return nil }
            return self.safety
        }

        // 锁屏实时活动要的三个数字。同样是 provider 而不是直接传 service：环境可以在运行时
        // 切换（Mock / 生产），锁屏卡必须跟着当下那一个走。
        //
        // 只有陪跑员端会真的走到它 —— 盲人端订单页本来就每 10 秒拉一次 `/track`，
        // 拉到后通过 `submitTrackStats` 推过去并复位节流器。
        liveEscortCoordinator.trackStatsProvider = { [weak self] orderID in
            guard let self else { throw CancellationError() }
            return try await self.safety.orderTrack(orderId: orderID).blindStats
        }

        // 同行定位前的位置轨迹同意（#368）。协调器自己不认识持久化，读写都回到这里的唯一入口。
        liveEscortCoordinator.trackConsent = LiveEscortTrackConsent(
            isGranted: { [weak self] purpose in self?.hasLocationTrackConsent(purpose) ?? false },
            record: { [weak self] purpose in self?.recordLocationTrackConsent(purpose) }
        )

        // 陪跑员出发 / 汇合锁屏卡的推送 token。provider 形态，理由同上。
        if #available(iOS 16.2, *) {
            GuideRunActivityController.shared.tokenUploader = { [weak self] orderID, hexToken in
                guard let self else { throw CancellationError() }
                try await self.orders.registerLiveActivityToken(hexToken, orderId: orderID)
            }
        }

        // 跑步中登录过期的暂缓（#376）在本单离开 `IN_PROGRESS` 时结束。两路来源都要听：
        // 订单页 / 首页写进来的本地记录，以及实时推送 —— 暂缓期间 HTTP 都是 401，
        // 跑完这件事往往只能从推送里知道。
        //
        // 🔴 **登出放到下一拍，不在订阅回调里同步做。** 这两个回调都在发布方的调用栈中途：
        // `$activeStatus` 是在 `activeStatus` 的 setter 还没返回时发的，同步清会话会经
        // `liveEscortCoordinator.reset` 再写一次 `activeStatus`（对同一个 `@Published` 的重入写）；
        // 推送那条在 `AppRealtimeCoordinator.route()` 中途，清完会话它还会接着往下写本单的刷新请求。
        liveEscortCoordinator.$activeStatus
            .sink { [weak self] status in
                guard let self, self.sessionExpiryDeferral != nil, status != .inProgress else { return }
                Task { @MainActor [weak self] in self?.endDeferredSessionExpiry() }
            }
            .store(in: &cancellables)
        realtimeCoordinator.statusUpdatePublisher
            .sink { [weak self] update in
                guard let self, self.sessionExpiryDeferral != nil,
                      update.orderId == self.liveEscortCoordinator.activeOrderID,
                      update.fromStatus == .inProgress, update.toStatus != .inProgress else { return }
                Task { @MainActor [weak self] in self?.endDeferredSessionExpiry() }
            }
            .store(in: &cancellables)

        // 续期（#391）。provider 形态，理由同上：环境可以运行时切换，续期必须打当下那一个。
        tokenRefresher.exchange = { [weak self] refreshToken in
            guard let self else { throw CancellationError() }
            return try await self.auth.refreshSession(refreshToken: refreshToken)
        }
        tokenRefresher.onAccessTokenRenewed = { [weak self] token in
            self?.applyRenewedAccessToken(token)
        }
        SessionTokenRefresher.appSessionRenewer = tokenRefresher

        // WS 重连成功后补读断线期间遗漏的通知，喂回 coordinator 复用去重/优先级排队。
        realtimeCoordinator.recoveryPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { await self?.catchUpMissedNotifications() }
            }
            .store(in: &cancellables)
    }

    /// 不含 token 值：续期换 token 不该让陪跑会话以为换了个人（见 `sessionGeneration`）。
    var sessionIdentityKey: String? {
        guard accessToken != nil, let userId else { return nil }
        return "\(userId):\(activeRole?.rawValue ?? "none"):\(sessionGeneration)"
    }
}

// MARK: - UserDefaults Keys Extension

extension AppConstants.UserDefaultsKeys {
    static let userId = "com.aidrun.mvp.userId"
    static let emergencyRecoveryMetadata = "com.aidrun.safety.emergencyRecoveryMetadata"
    /// 重连补读游标：上次见到通知的 ISO-8601 时刻（后端 `sent_at` 同格式）。
    static let lastSeenNotificationTimestamp = "com.aidrun.mvp.lastSeenNotificationTimestamp"
}
