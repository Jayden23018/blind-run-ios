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

enum SessionOperationState: Equatable {
    case idle
    case inProgress
    case revocationFailed(message: String)
}

@MainActor
final class AccountDeletionViewModel: ObservableObject {
    @Published var showFinalConfirmation = false
    @Published var preflightMessage: String?

    private static let blockingStatuses: Set<RunOrderStatus> = [
        .pendingMatch, .pendingAccept, .driverEnRoute, .driverArrived, .inProgress, .rematching
    ]

    func preflight(appState: AppState, speechService: SpeechService) async {
        preflightMessage = nil
        do {
            let orders: PagedOrderResponse = try await appState.apiClient.get(
                "/api/orders/mine",
                query: ["page": "0", "size": "100"]
            )
            if orders.content.contains(where: { Self.blockingStatuses.contains($0.status) }) {
                let message = "当前存在进行中的服务，请处理完成后再删除账户。"
                preflightMessage = message
                speechService.speakError(message)
                return
            }
        } catch APIError.unauthorized {
            appState.expireSession()
            return
        } catch {
            // 预检只提供及时提示；最终权限与订单状态始终由删除接口裁决。
        }
        showFinalConfirmation = true
    }

    /// 最终确认弹窗正文。逐条对着后端 `UserService.deleteAccount` 的真实行为写：
    /// 用户行软删除 + 手机号改写释放，PII 级联硬删（盲人是实名资料 / 紧急联系人 / 常用地址，
    /// 志愿者是证件照 OSS / 资料 / 可服务时间，两端都删轨迹点 / 工单 / APNs token），
    /// 而**订单、评价、求助事件刻意保留** —— 后端注释写明它们不存姓名手机号，留作纠纷复核审计。
    ///
    /// 两端说各自删的那份：文案里出现用户根本没有的东西（对盲人说「证件照」）会让他怀疑自己填过什么。
    /// 保留项必须说 —— PIPL 第 47 条下用户对「删了什么、留了什么」有知情权，
    /// 而「此操作不可撤销」配上只字不提的保留项，很容易被理解成订单记录也一并没了。
    static func finalConfirmationMessage(for role: UserRole) -> String {
        let deleted: String
        switch role {
        case .blind:
            deleted = "你的实名信息、紧急联系人、常用地址和跑步轨迹"
        case .volunteer:
            deleted = "你的资质证件照、志愿者资料、可服务时间和服务轨迹"
        case .unset:
            // 角色还没定的账号只有登录信息，没有上面任何一份资料。
            deleted = "你的账户资料"
        }
        return """
        将删除\(deleted)。历史订单与评价会保留用于纠纷复核，其中不含你的姓名和手机号。\
        所有登录令牌立即失效，手机号可以重新注册。此操作不可撤销。
        """
    }
}

// MARK: - AppState

/// 全局应用状态，管理用户会话、Token 和环境配置。
/// 作为 @EnvironmentObject 注入整个应用的 View 层级。
@MainActor
final class AppState: ObservableObject {
    private let mockAPIClient = MockAPIClient()
    private let apiClientOverride: (any APIClientProtocol)?
    let persistence: AppStatePersistence
    private let tokenStore: any TokenStoring
    let realtimeCoordinator: AppRealtimeCoordinator
    let liveEscortCoordinator: LiveEscortSessionCoordinator
    let emergencyCoordinator: EmergencyCoordinator
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Session

    /// JWT 访问令牌（持久化在 Keychain，见 `KeychainTokenStore`）
    @Published var accessToken: String? {
        didSet {
            persistToken()
            if oldValue != accessToken {
                realtimeCoordinator.detach(clearSessionState: true)
                liveEscortCoordinator.reset(clearIdentity: false)
                emergencyCoordinator.reset()
            }
        }
    }

    /// 当前用户 ID
    @Published var userId: Int64? {
        didSet {
            // Token changes already clear initial login/logout. A non-nil account switch
            // needs its own boundary even if an integration reuses the same token value.
            if oldValue != nil, oldValue != userId {
                realtimeCoordinator.detach(clearSessionState: true)
                liveEscortCoordinator.reset(clearIdentity: false)
                emergencyCoordinator.reset()
            }
        }
    }

    /// 仅保存在内存中的当前用户，不额外持久化手机号等身份信息。
    @Published private(set) var currentUser: CurrentUserResponse?

    @Published private(set) var sessionRestorationState: SessionRestorationState = .restoring
    @Published private(set) var logoutState: SessionOperationState = .idle
    @Published private(set) var accountDeletionState: SessionOperationState = .idle

    /// 当前激活角色（首次登录可能为 nil，需路由到角色选择）
    @Published var activeRole: UserRole? {
        didSet {
            persistActiveRole()
            mockAPIClient.syncRoleFromAppState(activeRole)
            if oldValue != activeRole {
                realtimeCoordinator.detach(clearSessionState: true)
                liveEscortCoordinator.reset(clearIdentity: false)
                emergencyCoordinator.reset()
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

    /// 实名引导页「稍后再说」的标记。按账号记：`performLocalSessionCleanup` 会清掉它。
    /// 只影响引导流是否还停在实名提示页，**不影响下单门槛**（`isBlindBookingReady` 仍看实名状态）。
    /// 走 `persistence` 而不是 `@AppStorage`，否则单元/UI 测试会写进 App 的标准域。
    @Published private(set) var didDismissBlindIdentityPrompt = false

    /// 首次使用引导是否已经看过。**按设备记，登出不清**（理由见
    /// `AppConstants.UserDefaultsKeys.blindFirstRunHelpSeen`）——
    /// 与上面那条按账号记的实名标记刻意不同。
    @Published private(set) var didSeeBlindFirstRunHelp = false

    /// 会话过期后带到登录页展示的一次性提示。
    @Published private(set) var sessionExpirationMessage: String?

    // MARK: - Legal Links

    /// `GET /api/misc/legal-links` 的结果。`nil` = 尚未加载 / 加载失败 / 后端未配置 URL，
    /// 三种情况入口一律回退到内置文案页（`LegalDocumentKind.destination(in:)` 已如此处理）。
    @Published private(set) var legalLinks: LegalLinksResponse?

    /// 只请求一次就够：这两个 URL 来自后端配置，不会在一次会话里变。
    /// 失败也不重试 —— 回退文案页本来就是完整可读的，为它反复打请求不值得。
    private var didAttemptLegalLinksLoad = false

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

    // MARK: - Computed

    var isLoggedIn: Bool {
        accessToken != nil
    }

    // MARK: 盲人完成度（拆成互相独立、可单独测试的判断）

    /// 基础资料：目前只要求昵称非空。与紧急联系人、实名状态无关。
    var isBlindBasicProfileComplete: Bool {
        guard let name = blindProfile?.name else { return false }
        return !name.trimmed.isEmpty
    }

    /// 实名状态。2026-07-30 起后端 `OrderCreationService` 在服务端硬校验
    /// `verifyStatus == VERIFIED`（否则 403 `IDENTITY_NOT_VERIFIED`），
    /// 所以这里既用于展示与语音引导，也参与下单门槛。
    var blindIdentityStatus: BlindVerifyStatus {
        blindProfile?.identityStatus ?? .unknown
    }

    /// 实名侧的下单硬门槛。状态未知（后端没返回 / 返回了不认识的值）时按未通过处理：
    /// 服务端会拒，客户端提前引导比让用户白填一遍订单再被 403 更可用。
    var isBlindIdentityVerified: Bool {
        blindIdentityStatus.isVerified
    }

    var emergencyContactCount: Int {
        emergencyContacts.count
    }

    /// 恰好一个主联系人时返回它；0 个或多个都返回 nil。
    var primaryEmergencyContact: EmergencyContactResponse? {
        EmergencyContactResponse.singlePrimary(in: emergencyContacts)
    }

    var hasExactlyOnePrimaryEmergencyContact: Bool {
        primaryEmergencyContact != nil
    }

    /// 紧急联系人侧的硬门槛：至少 1 位，且恰好 1 位主联系人。
    var hasValidEmergencyContacts: Bool {
        emergencyContactCount >= EmergencyContactRules.minCount && hasExactlyOnePrimaryEmergencyContact
    }

    /// 下单硬门槛：基础资料 + 实名认证通过 + 至少 1 个紧急联系人 + 恰好 1 个主联系人。
    /// 实名这一档与后端 `OrderCreationService` 的 403 `IDENTITY_NOT_VERIFIED` 对齐，
    /// 且与服务端同序（实名在紧急联系人之前）。
    var isBlindBookingReady: Bool {
        isBlindBasicProfileComplete && isBlindIdentityVerified && hasValidEmergencyContacts
    }

    /// 盲人引导流当前该停在哪一步；nil 表示可以直接进首页。
    var blindOnboardingStep: BlindOnboardingStep? {
        BlindOnboardingStep.first(
            isBasicProfileComplete: isBlindBasicProfileComplete,
            hasValidEmergencyContacts: hasValidEmergencyContacts,
            shouldPromptIdentity: blindIdentityStatus.shouldPromptVerification,
            didDismissIdentityPrompt: didDismissBlindIdentityPrompt
        )
    }

    /// 「稍后再说」：跳过实名引导页进首页。**不等于可以下单**——
    /// 未实名仍会被 `BlindBookingGate.identityVerification` 拦住（后端 403 `IDENTITY_NOT_VERIFIED`）。
    ///
    /// ⚠️ 这句话原本写的是「进首页**看历史订单**和设置」，而盲人端**没有任何历史入口** ——
    /// 跳过实名的用户进来只有一个必定失败的「开始约跑」。注释在描述一个不存在的能力。
    /// 入口由 PR #24（`BlindRunHistoryView`，跑步记录）补，合入前这里不要再写「历史订单」。
    /// 那一页只收 `COMPLETED`，取消掉的订单和补评价仍然没有去处。
    func dismissBlindIdentityPrompt() {
        didDismissBlindIdentityPrompt = true
        persistence.set(true, forKey: AppConstants.UserDefaultsKeys.blindIdentityPromptDismissed)
    }

    /// 首次引导看完（按了「知道了」）。**只有这一个写入点** ——
    /// 「进过这一页」不算看完：自动进入的那次如果用户直接返回，下次还该给他。
    func markBlindFirstRunHelpSeen() {
        guard !didSeeBlindFirstRunHelp else { return }
        didSeeBlindFirstRunHelp = true
        persistence.set(true, forKey: AppConstants.UserDefaultsKeys.blindFirstRunHelpSeen)
    }

    var isVolunteerProfileComplete: Bool {
        guard let profile = volunteerProfile else {
            return false
        }
        return profile.isProfileCompleteForDispatch
    }

    var isVolunteerProfileApproved: Bool {
        guard let profile = volunteerProfile else { return false }
        if let volunteerRegistrationStatus {
            return volunteerRegistrationStatus.isRegistrationComplete
        }
        return profile.isMainRegistrationCompleteWhenStatusUnavailable && profile.isAdminReviewApprovedWhenAvailable
    }

    /// 根据当前环境返回对应的 API Client
    var apiClient: any APIClientProtocol {
        if let apiClientOverride { return apiClientOverride }
        switch currentEnvironment {
        case .mock where AppBuildChannel.current == .development:
            return mockAPIClient
        case .mock:
            return DisabledAPIClient()
        case .demoCloud:
            guard AppBuildChannel.current.allows(currentEnvironment) else {
                return DisabledAPIClient()
            }
            guard let baseURL = currentEnvironment.baseURL else {
                return DisabledAPIClient()
            }
            return URLSessionAPIClient(
                baseURL: baseURL,
                tokenProvider: { [weak self] in self?.accessToken }
            )
        }
    }

    // MARK: - Init

    init(
        apiClient: (any APIClientProtocol)? = nil,
        persistence: AppStatePersistence? = nil,
        tokenStore: (any TokenStoring)? = nil
    ) {
        let persistence = persistence ?? AppStatePersistenceFactory.makeDefault()
        let realtimeCoordinator = AppRealtimeCoordinator()
        self.realtimeCoordinator = realtimeCoordinator
        self.liveEscortCoordinator = LiveEscortSessionCoordinator(realtimeCoordinator: realtimeCoordinator)
        let emergencyCoordinator = EmergencyCoordinator()
        self.emergencyCoordinator = emergencyCoordinator
        self.apiClientOverride = apiClient
        self.persistence = persistence
        self.tokenStore = tokenStore ?? TokenStoreFactory.makeDefault()
        if let envRaw = persistence.string(forKey: AppConstants.UserDefaultsKeys.apiEnvironment),
           let env = AppState.storedEnvironment(from: envRaw) {
            self.currentEnvironment = AppState.resolvedInitialEnvironment(env, channel: AppBuildChannel.current)
        } else {
            self.currentEnvironment = AppBuildChannel.current.defaultEnvironment
        }
        self.didDismissBlindIdentityPrompt =
            persistence.object(forKey: AppConstants.UserDefaultsKeys.blindIdentityPromptDismissed) as? Bool ?? false
        self.didSeeBlindFirstRunHelp =
            persistence.object(forKey: AppConstants.UserDefaultsKeys.blindFirstRunHelpSeen) as? Bool ?? false

        // 紧急事件的后续推送在触发它的界面消失后才到，订阅点必须在 App 生命周期层。
        // provider 而不是直接传 client：环境可以在运行时切换（Mock / 生产），求助恢复必须打当下那一个。
        emergencyCoordinator.observe(realtimeCoordinator) { [weak self] in
            guard let self, self.activeRole == .blind else { return nil }
            return self.apiClient
        }

        // WS 重连成功后补读断线期间遗漏的通知，喂回 coordinator 复用去重/优先级排队。
        realtimeCoordinator.recoveryPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { await self?.catchUpMissedNotifications() }
            }
            .store(in: &cancellables)
    }

    private var sessionIdentityKey: String? {
        guard let accessToken, let userId else { return nil }
        return "\(userId):\(activeRole?.rawValue ?? "none"):\(accessToken)"
    }

    // MARK: - 重连补读

    /// WS 重连后补读断线期间遗漏的通知（`GET /api/notifications/since`）。
    ///
    /// `after` 优先用本次会话实时见到的最新 timestamp，其次读持久化游标；
    /// 两者都是 ISO-8601（无时区），与后端 `notification_logs.sent_at` 同格式 ——
    /// 传 epoch 毫秒会被后端判 400 `INVALID_TIMESTAMP`。
    /// 首次安装且从未收到过通知时游标为空，此时不补读（后端窗口只有 24h/50 条，全量拉没有意义）。
    func catchUpMissedNotifications() async {
        guard isLoggedIn else { return }
        // 断线期间可能整条求助都发生完了（志愿者代触发、家属短信回执、客服解除），而通知信封不带
        // eventId，补读文本无法还原事件状态。恢复只能问 `GET /api/emergency/active`，且必须先于补读，
        // 免得补读把已解除的旧文案念成当前状态。仅盲人有该端点权限。
        if activeRole == .blind {
            await emergencyCoordinator.refreshActiveEvent(userID: userId)
        }
        let after = realtimeCoordinator.lastObservedNotificationTimestamp
            ?? persistence.string(forKey: AppConstants.UserDefaultsKeys.lastSeenNotificationTimestamp)
        guard let after, !after.isEmpty else { return }
        do {
            let missed: [MissedNotificationResponse] = try await apiClient.get(
                "/api/notifications/since",
                query: ["after": after]
            )
            realtimeCoordinator.ingestCatchUp(missed)
            if let latest = realtimeCoordinator.lastObservedNotificationTimestamp {
                persistence.set(latest, forKey: AppConstants.UserDefaultsKeys.lastSeenNotificationTimestamp)
            }
        } catch {
            // 补读是 best-effort：失败不阻断实时链路，下次重连自然重试。
            ClientFlowDiagnostics.record(event: "failed", operation: "notification-catch-up")
        }
    }

    // MARK: - Legal Links

    /// 拉一次隐私政策 / 用户协议的外链地址。
    ///
    /// **必须 `requiresAuth: false`** —— 后端对该端点 permitAll，App Store 审核员是未登录状态，
    /// 而 5.1.1/5.1.2 要求他们能在应用内找到隐私政策。带鉴权会让未登录时 401 直接失败。
    ///
    /// 失败静默：入口在任何时刻都得是可点且有内容的，回退文案页承担这件事。
    /// 这里冒出一个错误弹窗，反而会把审核员挡在隐私政策之外。
    func loadLegalLinksIfNeeded() async {
        guard !didAttemptLegalLinksLoad else { return }
        didAttemptLegalLinksLoad = true
        do {
            legalLinks = try await apiClient.get("/api/misc/legal-links", requiresAuth: false)
        } catch {
            ClientFlowDiagnostics.record(event: "failed", operation: "legal-links")
        }
    }

    // MARK: - Session Management

    /// 启动时恢复会话（Token 从 Keychain 读取，兼容旧版本 UserDefaults 存量）
    func restoreSession() async {
        sessionRestorationState = .restoring
        accessToken = restoredToken()
        if let roleRaw = persistence.string(forKey: AppConstants.UserDefaultsKeys.activeRole) {
            activeRole = UserRole(rawValue: roleRaw)
        }
        if let savedUserId = persistence.object(forKey: AppConstants.UserDefaultsKeys.userId) as? NSNumber {
            userId = savedUserId.int64Value
        }
        guard accessToken != nil else {
            sessionRestorationState = .unauthenticated
            return
        }
        mockAPIClient.syncSessionFromAppState(token: accessToken, role: activeRole)
        do {
            let user: CurrentUserResponse = try await apiClient.get("/api/auth/me")
            guard user.roleResolution != .invalid else {
                performLocalSessionCleanup()
                sessionExpirationMessage = "登录角色信息异常，请重新登录。"
                return
            }
            currentUser = user
            userId = user.userId
            persistUserId()
            activeRole = user.resolvedRole
            if activeRole == nil {
                disconnectWebSocket()
                sessionRestorationState = .choosingRole
            } else {
                sessionRestorationState = .authenticated
                connectWebSocketIfNeeded()
            }
        } catch let error as APIError {
            switch error {
            case .unauthorized:
                performLocalSessionCleanup()
                sessionExpirationMessage = "登录状态已失效，请重新登录。"
            default:
                // 无法权威确认时不进入已认证页面，也不丢弃可能仍有效的凭据。
                disconnectWebSocket()
                sessionRestorationState = .validationFailed(message: error.localizedMessage)
            }
        } catch {
            disconnectWebSocket()
            sessionRestorationState = .validationFailed(message: "暂时无法验证登录状态，请检查网络后重试。")
        }
    }

    /// 登录成功后保存会话（新后端: LoginResponse{token, userId, role}）
    func handleLoginSuccess(response: LoginResponse) {
        accessToken = response.token
        userId = response.userId
        activeRole = Self.resolvedLoginRole(from: response.role)
        currentUser = CurrentUserResponse(userId: response.userId, phone: nil, role: response.role)
        persistUserId()
        sessionRestorationState = activeRole == nil ? .choosingRole : .authenticated
        connectWebSocketIfNeeded()
    }

    /// 角色切换成功后替换 token（新后端: SetRoleResponse 包含新 token）
    func handleRoleSwitchSuccess(response: SetRoleResponse, requestedRole: UserRole) {
        if let newToken = response.token {
            accessToken = newToken
        }
        activeRole = requestedRole
        if let currentUser {
            self.currentUser = CurrentUserResponse(userId: currentUser.userId, phone: currentUser.phone, role: requestedRole.rawValue)
        }
        sessionRestorationState = .authenticated
        connectWebSocketIfNeeded()
    }

    /// 清除会话（退出登录）
    func clearSession() {
        performLocalSessionCleanup()
    }

    /// 所有用户退出入口使用该服务端撤销操作。
    func logout() async {
        guard logoutState != .inProgress else { return }
        logoutState = .inProgress
        do {
            let _: LogoutResponse = try await apiClient.post("/api/auth/logout")
            performLocalSessionCleanup()
        } catch APIError.unauthorized {
            performLocalSessionCleanup()
        } catch let error as APIError {
            logoutState = .revocationFailed(message: error.localizedMessage)
        } catch {
            logoutState = .revocationFailed(message: "未能确认服务端退出，请重试。")
        }
    }

    /// 仅在服务端撤销失败且用户再次明确确认后调用。
    func confirmLocalOnlySignOut() {
        guard case .revocationFailed = logoutState else { return }
        performLocalSessionCleanup()
    }

    func dismissLogoutFailure() {
        if case .revocationFailed = logoutState { logoutState = .idle }
    }

    func dismissAccountDeletionFailure() {
        if case .revocationFailed = accountDeletionState { accountDeletionState = .idle }
    }

    func deleteCurrentAccount() async {
        guard accountDeletionState != .inProgress, let userId = currentUser?.userId ?? self.userId else { return }
        accountDeletionState = .inProgress
        do {
            let response: DeleteAccountResponse = try await apiClient.delete("/api/users/\(userId)")
            guard response.success else {
                accountDeletionState = .revocationFailed(message: response.message ?? "账户删除未完成。")
                return
            }
            performLocalSessionCleanup()
        } catch APIError.unauthorized {
            expireSession()
        } catch let error as APIError {
            accountDeletionState = .revocationFailed(message: error.localizedMessage)
        } catch {
            accountDeletionState = .revocationFailed(message: "账户删除未完成，请重试。")
        }
    }

    private func performLocalSessionCleanup() {
        disconnectWebSocket()
        accessToken = nil
        userId = nil
        currentUser = nil
        activeRole = nil
        blindProfile = nil
        volunteerProfile = nil
        volunteerRegistrationStatus = nil
        emergencyContacts = []
        didDismissBlindIdentityPrompt = false
        sessionExpirationMessage = nil
        logoutState = .idle
        accountDeletionState = .idle
        sessionRestorationState = .unauthenticated
        // Keychain 里的 Token 由上面 `accessToken = nil` 经 didSet -> persistToken 删除；
        // 这里只清理旧版本可能遗留在 UserDefaults 的 Token，避免退出后又被迁移回来。
        persistence.removeObject(forKey: AppConstants.UserDefaultsKeys.accessToken)
        persistence.removeObject(forKey: AppConstants.UserDefaultsKeys.activeRole)
        persistence.removeObject(forKey: AppConstants.UserDefaultsKeys.userId)
        persistence.removeObject(forKey: AppConstants.UserDefaultsKeys.emergencyRecoveryMetadata)
        // 实名引导页的「稍后再说」是按账号记的：换账号后应重新提示一次。
        persistence.removeObject(forKey: AppConstants.UserDefaultsKeys.blindIdentityPromptDismissed)
        // 补读游标同样是按账号的：留着会让新账号补读到上一个账号的时间窗。
        persistence.removeObject(forKey: AppConstants.UserDefaultsKeys.lastSeenNotificationTimestamp)
    }

    /// 会话过期：清除本地登录态并让登录页展示一次性提示。
    func expireSession(message: String = "登录已过期，请重新登录。") {
        clearSession()
        sessionExpirationMessage = message
    }

    func consumeSessionExpirationMessage() -> String? {
        let message = sessionExpirationMessage
        sessionExpirationMessage = nil
        return message
    }

    @discardableResult
    func handleAuthenticatedAPIError(_ error: APIError) -> Bool {
        guard case .unauthorized = error else { return false }
        expireSession()
        return true
    }

    /// 切换角色
    func switchRole(to role: UserRole) {
        activeRole = role
    }

    /// 更新盲人资料
    func updateBlindProfile(_ profile: BlindProfileResponse) {
        blindProfile = profile
    }

    /// 更新志愿者资料
    func updateVolunteerProfile(_ profile: VolunteerProfileResponse) {
        volunteerProfile = profile
    }

    /// 只更新志愿者资料里的资质审核状态。
    /// `GET /api/volunteer/verification/status` 只返回 `{status}`，不返回整份资料，
    /// 因此这里保留其余字段，避免把已知资料覆盖成 nil。
    func updateVolunteerVerificationStatus(_ status: String) {
        let current = volunteerProfile
        volunteerProfile = VolunteerProfileResponse(
            name: current?.name,
            verificationStatus: status,
            adminReviewStatus: current?.adminReviewStatus,
            registrationStep: current?.registrationStep,
            canAcceptOrders: current?.canAcceptOrders,
            isAvailable: current?.isAvailable,
            wantsDispatch: current?.wantsDispatch,
            availableTimeSlots: current?.availableTimeSlots,
            acceptsGuideDog: current?.acceptsGuideDog,
            paceRange: current?.paceRange
        )
    }

    /// 更新志愿者主注册流程状态
    func updateVolunteerRegistrationStatus(_ status: VolunteerRegistrationStatus) {
        volunteerRegistrationStatus = status
    }

    /// 更新紧急联系人
    func updateEmergencyContacts(_ contacts: [EmergencyContactResponse]) {
        emergencyContacts = contacts
    }

    #if DEBUG
    func returnToRoleSelectionForTesting() {
        activeRole = nil
    }

    func switchToNextEnvironmentForTesting() {
        let allEnvironments = AppState.debugTestEnvironments
        let currentEnvironment = AppState.resolvedInitialEnvironment(currentEnvironment, channel: .development)
        guard let currentIndex = allEnvironments.firstIndex(of: currentEnvironment) else {
            self.currentEnvironment = allEnvironments[0]
            clearSession()
            return
        }
        let nextIndex = (currentIndex + 1) % allEnvironments.count
        // 会话清理由 `currentEnvironment` 的 didSet 统一负责，这里不再重复调用。
        self.currentEnvironment = allEnvironments[nextIndex]
    }
    #endif

    #if DEBUG || DEMO
    func resetUITestPersistence() {
        persistence.reset()
        performLocalSessionCleanup()
        // 按**设备**记的标志不进 `performLocalSessionCleanup`（登出不该清它们），
        // 但这里的语义是「恢复到全新安装」，必须一起清。
        //
        // 只清盘不够：`persistence.reset()` 抹掉的是磁盘，而 `AppState` 早在 init 里
        // 就把值读进内存了。漏掉这一行的表现是**跨用例串味** —— 前一条用例按过「知道了」，
        // 后一条就再也等不到引导页，报「引导页没起来」，看着像功能坏了。
        didSeeBlindFirstRunHelp = false
        // Keychain 不随 App 沙盒一起清除：只清 UserDefaults 的话，重置后 Token 仍会残留，
        // 「本该未登录」的 UI 用例会拿着上一轮的 Token 继续跑。必须显式删除。
        tokenStore.delete()
    }
    #endif

    /// 纯函数、无状态；`MockAPIClient` 等非 MainActor 上下文也要用它做与后端
    /// `@Pattern(^1[3-9]\d{9}$)` 同源的校验，所以显式 nonisolated。
    nonisolated static func isValidMainlandPhone(_ phoneNumber: String) -> Bool {
        let pattern = #"^1[3-9]\d{9}$"#
        return phoneNumber.range(of: pattern, options: .regularExpression) != nil
    }

    static func resolvedInitialEnvironment(
        _ environment: APIEnvironment,
        channel: AppBuildChannel = AppBuildChannel.current
    ) -> APIEnvironment {
        channel.allows(environment) ? environment : channel.defaultEnvironment
    }

    static func storedEnvironment(from rawValue: String) -> APIEnvironment? {
        return APIEnvironment(rawValue: rawValue)
    }

    static func resolvedLoginRole(from rawValue: String?) -> UserRole? {
        guard let rawValue,
              let role = UserRole(rawValue: rawValue),
              role != .unset else {
            return nil
        }
        return role
    }

    #if DEBUG
    static let debugTestEnvironments: [APIEnvironment] = [.mock, .demoCloud]
    #endif

    // MARK: - WebSocket (Private)

    /// 根据当前 token 和角色连接 WebSocket（mock 环境跳过）
    private func connectWebSocketIfNeeded() {
        #if DEBUG || DEMO
        if ProcessInfo.processInfo.environment["AIDRUN_UI_TEST_DISABLE_WEBSOCKET"] == "1" {
            return
        }
        #endif

        guard currentEnvironment != .mock,
              AppBuildChannel.current.allows(currentEnvironment),
              let token = accessToken,
              let role = activeRole,
              role != .unset,
              let baseURL = currentEnvironment.baseURL else {
            return
        }

        let wsRole: WSRole = (role == .blind) ? .blind : .volunteer

        // 如果已有连接先断开
        webSocketService?.disconnect()

        let service = WebSocketService()
        webSocketService = service
        service.connect(baseURL: baseURL, token: token, role: wsRole)
    }

    /// 断开 WebSocket 并清除引用
    private func disconnectWebSocket() {
        webSocketService?.disconnect()
        webSocketService = nil
    }

    // MARK: - Persistence (Private)

    private func persistToken() {
        if let token = accessToken {
            tokenStore.save(token)
        } else {
            tokenStore.delete()
        }
    }

    /// Keychain 优先读取；只有命中旧版本遗留在 UserDefaults 的 Token 时才做一次性迁移
    /// （写入 Keychain 并清除旧值），保证老用户升级后不掉登录态。
    private func restoredToken() -> String? {
        if let token = tokenStore.read() {
            return token
        }
        guard let legacyToken = persistence.string(forKey: AppConstants.UserDefaultsKeys.accessToken),
              !legacyToken.isEmpty else {
            return nil
        }
        tokenStore.save(legacyToken)
        persistence.removeObject(forKey: AppConstants.UserDefaultsKeys.accessToken)
        return legacyToken
    }

    private func persistActiveRole() {
        if let role = activeRole {
            persistence.set(role.rawValue, forKey: AppConstants.UserDefaultsKeys.activeRole)
        } else {
            persistence.removeObject(forKey: AppConstants.UserDefaultsKeys.activeRole)
        }
    }

    private func persistUserId() {
        if let id = userId {
            persistence.set(id, forKey: AppConstants.UserDefaultsKeys.userId)
        }
    }

    private func persistEnvironment() {
        persistence.set(currentEnvironment.rawValue, forKey: AppConstants.UserDefaultsKeys.apiEnvironment)
    }
}

// MARK: - UserDefaults Keys Extension

extension AppConstants.UserDefaultsKeys {
    static let userId = "com.aidrun.mvp.userId"
    static let emergencyRecoveryMetadata = "com.aidrun.safety.emergencyRecoveryMetadata"
    /// 重连补读游标：上次见到通知的 ISO-8601 时刻（后端 `sent_at` 同格式）。
    static let lastSeenNotificationTimestamp = "com.aidrun.mvp.lastSeenNotificationTimestamp"
}

// MARK: - Disabled API Client

private final class DisabledAPIClient: APIClientProtocol, @unchecked Sendable {
    func request<T: Decodable>(
        method: HTTPMethod,
        path: String,
        query: [String: String]?,
        body: (any Encodable & Sendable)?,
        requiresAuth: Bool
    ) async throws -> T {
        throw APIError.invalidURL
    }

    func upload<T: Decodable>(
        path: String,
        query: [String: String]?,
        fields: [String: String]?,
        files: [MultipartFile],
        requiresAuth: Bool
    ) async throws -> T {
        throw APIError.invalidURL
    }
}
