import Combine
import Foundation
import SwiftUI

extension AppState {
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
            // 未包会话处理的那份（#872）：下面 `.unauthorized` 分支自己清会话、写「登录状态已失效」。
            let user = try await sessionUnawareAuth.currentUser()
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
                // 冷启动：WS 首次连上不发恢复信号（只有重连才发），回前台那条补读又可能跑在
                // 会话恢复之前被 `isLoggedIn` 挡掉 —— 求助恢复不能押在这两者的先后上。
                Task { await recoverActiveEmergency() }
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
        tokenRefresher.storeCredential(from: response)
        accessToken = response.token
        userId = response.userId
        activeRole = Self.resolvedLoginRole(from: response.role)
        currentUser = CurrentUserResponse(userId: response.userId, phone: nil, role: response.role)
        persistUserId()
        sessionRestorationState = activeRole == nil ? .choosingRole : .authenticated
        connectWebSocketIfNeeded()
    }

    /// 续期拿到新 access 后由 `tokenRefresher` 调。只换值、持久化，**不重置会话**（见 `accessToken`）。
    ///
    /// WebSocket 不断开：契约说已建立的连接不受续期影响，只要下次重连握手用新的。
    /// 已经登出（`accessToken == nil`）就什么都不做 —— 迟到的续期结果不能把会话复活。
    func applyRenewedAccessToken(_ token: String) {
        guard accessToken != nil, accessToken != token, !token.isEmpty else { return }
        isApplyingRenewedAccessToken = true
        accessToken = token
        isApplyingRenewedAccessToken = false
        webSocketService?.updateAccessTokenForReconnect(token)
    }

    /// 回前台时调（`blindRunApp`）：过了半衰期就续。续不了也不打扰用户 —— 旧 access 此刻还能用，
    /// 真过期时 401 那条路会再试。
    func renewSessionIfDue() async {
        guard isLoggedIn else { return }
        await tokenRefresher.renewIfDue()
    }

    /// 角色切换成功后替换 token（新后端: SetRoleResponse 包含新 token）
    ///
    /// refresh token 不动：选角色换发的 access 属于同一次登录（契约：登出时一起撤）。
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
    ///
    /// 契约（后端 #642 / #669）：登出撤销**这一次登录**的全部 token，仍要求 access 有效。
    /// - access 已过期：`APIClient` 的 401 分支会先续期、再用新 access 重试一次 —— 这里不用另写。
    ///   只删本地不调登出的话，服务器上的 refresh 还能用 30 天。
    /// - 5xx：服务端什么都还没撤，拿同一个 token 原样重试一次。
    /// - **无论成败都清本地会话**（用户的意图是退出）。原来的「服务端退出失败 → 重试 / 仅退出本机」
    ///   弹窗因此删除：它保留会话的前提是「客户端拿着 token 才有机会再撤」，而契约改为由客户端放手。
    func logout() async {
        guard logoutState != .inProgress else { return }
        logoutState = .inProgress
        // **顺序不能换**：logout 会把 JWT 拉黑，之后再调解绑必然 401、token 删不掉，
        // 而旧账号的 HIGH 推送（求助 / 走散告警 / 到达 / 取消预警）会继续送到这台手机
        // 并被前台朗读出来。后端契约把这条顺序写在 `unregisterApnsToken` 的 description 里。
        // 解绑失败不阻断登出：接口幂等、可安全重试。
        let stillBoundDeviceToken = await pushNotificationsManager?.unregisterDeviceTokenBeforeLogout()
        // 解绑没成就先不登出：登出会作废这次登录的 JWT，之后谁都解不了绑。两步都记下，补撤时按顺序来。
        let serverLoggedOut = stillBoundDeviceToken == nil ? await logOutOnServer() : false
        // 没撤成的部分记进待撤记录，之后补撤（#459）。凭据要在下面清本地会话之前取。
        recordUnfinishedRevocation(deviceToken: stillBoundDeviceToken, needsLogout: !serverLoggedOut)
        performLocalSessionCleanup()
    }

    func dismissAccountDeletionFailure() {
        if accountDeletionState.accountDeletionFailureAlert != nil { accountDeletionState = .idle }
    }

    func deleteCurrentAccount() async {
        guard accountDeletionState != .inProgress, let userId = currentUser?.userId ?? self.userId else { return }
        accountDeletionState = .inProgress
        do {
            let response = try await auth.deleteAccount(userId: userId)
            guard response.success else {
                accountDeletionState = .revocationFailed(message: response.message ?? "账户删除未完成。")
                return
            }
            performLocalSessionCleanup()
        } catch APIError.unauthorized {
            // 不直接 `expireSession()`（#872）：那会绕过跑步中暂缓。经 `apiClient` 来的 401 已由 adapter 处理过，
            // 这里再交一次是给 `authOverride` 注入的替身用的 —— `handleAuthenticatedAPIError` 幂等，不会登出两次。
            handleAuthenticatedAPIError(.unauthorized)
            // 暂缓中会话还在：删除没做成，退出「删除中」，别让遮罩一直挂着。
            if accountDeletionState == .inProgress { accountDeletionState = .idle }
        } catch let error as APIError {
            accountDeletionState = .accountDeletionFailure(for: error)
        } catch {
            accountDeletionState = .revocationFailed(message: "账户删除未完成，请重试。")
        }
    }

    func performLocalSessionCleanup() {
        // 排在最前：下面清 token 会触发 `liveEscortCoordinator.reset`，进而触发结束暂缓的订阅。
        sessionExpiryDeferral = nil
        // refresh token 与 access 一起删（契约：登出、注销、`REFRESH_TOKEN_INVALID` 时一起删）。
        // 在清 access 之前：进行中的续期回来时先看 refresh 还在不在，不在就丢弃结果。
        tokenRefresher.clearCredential()
        disconnectWebSocket()
        // 盲人端「约跑进度」锁屏卡（#919）不挂在同行会话上，退出登录要单独收：锁屏谁都看得见，卡上有见面地点。
        if #available(iOS 16.2, *) { BlindOrderActivityController.shared.endAll() }
        // 连续拒绝次数按账号记（#552），要在 `userId = nil` 之前清：清的是这个账号的键。
        VolunteerDeclineStreak.clearStoredCounts(for: userId, in: persistence)
        accessToken = nil
        userId = nil
        currentUser = nil
        activeRole = nil
        blindProfile = nil
        volunteerProfile = nil
        volunteerRegistrationStatus = nil
        emergencyContacts = []
        resetRuleParams()
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
        // 补读游标同样是按账号的：留着会让新账号补读到上一个账号的时间窗。
        persistence.removeObject(forKey: AppConstants.UserDefaultsKeys.lastSeenNotificationTimestamp)
        // 「这个 device token 已经报给这个账号了」这份记忆也是按账号的。留着会让下一个账号的
        // 上报被 `submitToken` 的短路判成「报过了」—— 推送从此静默失效，且没有任何报错。
        // 与上面的解绑请求分开：那条只在主动登出时可能成功，而这一条每条会话结束路径都要走
        // （401 过期那条路上 token 已经废了，解绑必然失败，本地这份记忆照样得清）。
        pushNotificationsManager?.forgetLocalTokenBinding()
        // 常用出发地点通常就是家庭住址。它不在 `persistence` 里（见 `FavoritePlaceStore`），
        // 但同样是按账号的：换账号登录后，上一个人「什么时候会在哪」不该原样留在这台设备上。
        FavoritePlaceStore.clearPersistedPlaces()
        // 上面 `activeRole = nil` 已经会停，但退出时角色本来就是 nil（停在角色选择页）不经过那一道。
        // 所有意图一起撤回：只停硬件的话，下一个账号改一次系统权限，授权回调就会把它开回来（#417）。
        stopLocationUpdates()
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
        if var deferral = sessionExpiryDeferral {
            let now = sessionNow
            if now.timeIntervalSince(deferral.lastAnnouncedAt) >= Self.deferredExpiryReminderInterval {
                deferral.announcementSerial += 1
                deferral.lastAnnouncedAt = now
                sessionExpiryDeferral = deferral
            }
            return true
        }
        // 幂等（#872）：同一次失效会被报好几次 —— adapter 一次、还没清理的旧调用方一次，首页并发的几个请求各一次。
        // 会话已经清掉了就别再 `expireSession()`：再清一遍没有意义，再写一次提示会让登录页念两遍「登录已过期」，
        // 用户已经在登录页上时还会凭空冒出一句。
        guard accessToken != nil || tokenRefresher.currentRefreshToken != nil else {
            return true
        }
        // 正在退出登录：交给登出流程收尾。抢先清会话会让它读不到凭据记补撤，还会在登录页多念一句「登录已过期」。
        guard logoutState != .inProgress else { return true }
        // 判据读 `liveEscortCoordinator.activeStatus`：全 App 唯一记着「本账号当前订单状态」的地方，
        // 两端首页与订单页都往里写。冷启动时它还是空的 ⇒ 重启后的 401 照旧登出（design.md Non-Goals）。
        guard liveEscortCoordinator.activeStatus == .inProgress else {
            expireSession()
            return true
        }
        sessionExpiryDeferral = SessionExpiryDeferral(
            role: activeRole,
            announcementSerial: 1,
            lastAnnouncedAt: sessionNow
        )
        emergencyCoordinator.blockCloudSOSForExpiredSession()
        return true
    }

    /// `SessionAwareAPIClient` 的回调：需要登录的请求续期后仍 401（#872）。全 App 只有这一处从网络层进会话处理。
    func handleSessionEndedByNetworkLayer() {
        handleAuthenticatedAPIError(.unauthorized)
    }

    /// 结束暂缓，按原逻辑登出。三个入口：本单离开 `IN_PROGRESS`（`init` 里的两条订阅）、
    /// 跑者从首页导航栈退出订单页（`BlindRunnerHomeView`）、横幅上的「现在重新登录」。
    ///
    /// **先归零再清会话**：`clearSession` 会让 `liveEscortCoordinator.activeStatus` 变 nil，
    /// 那条订阅会再进来一次 —— 不先归零就是重入。
    func endDeferredSessionExpiry() {
        guard sessionExpiryDeferral != nil else { return }
        sessionExpiryDeferral = nil
        expireSession()
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
        // 同意门走同一个解析器，于是「默认跳过、显式要求时才真弹」的规则只有一处。
        didAcceptPrivacyConsent = AppState.resolveInitialPrivacyConsent(persistence: persistence)
        // Keychain 不随 App 沙盒一起清除：只清 UserDefaults 的话，重置后 Token 仍会残留，
        // 「本该未登录」的 UI 用例会拿着上一轮的 Token 继续跑。必须显式删除。
        tokenStore.delete()
    }
    #endif
}
