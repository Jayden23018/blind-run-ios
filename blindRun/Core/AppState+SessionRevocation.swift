import Foundation

// 退出登录的服务端撤销与补撤（#391 / #459）。从 `AppState.swift` 挪出来：那个文件已经超长（SwiftLint 棘轮），
// 这一组只用 `AppState` 的凭据与环境，放在一处也更好找。
extension AppState {

    /// 服务端那边的错重试一次可能就过了。`.serverError` 不带状态码，4xx 业务错误也会落在这里 ——
    /// 登出幂等，多发一次无害，所以不再细分。断网不重试：超时要 15 秒，重试会让用户对着遮罩再等一轮。
    static func logoutIsWorthRetrying(_ error: APIError) -> Bool {
        switch error {
        case .serverError:
            return true
        case .unknown(let statusCode):
            return (500...599).contains(statusCode)
        case .unauthorized, .missingCredentials, .rateLimited, .networkError, .decodingError, .invalidURL:
            return false
        }
    }

    /// 撤销这一次登录。返回服务端是否已经不认这次登录了：登出成功，或 401（续期也救不回来 = 本来就结束了）。
    /// 断网、限流、服务端错误返回 false，由调用方记进待撤记录。
    func logOutOnServer() async -> Bool {
        do {
            _ = try await auth.logout()
            return true
        } catch let error as APIError where Self.logoutIsWorthRetrying(error) {
            do {
                _ = try await auth.logout()
                return true
            } catch {
                return !PendingSessionRevoker.isWorthRetrying(error)
            }
        } catch {
            return !PendingSessionRevoker.isWorthRetrying(error)
        }
    }

    /// 登出没撤完的部分记下来（#459）：推送 token 没解绑、或服务端登出没成。只存撤销要用的最少数据。
    /// 必须在清本地会话之前调：之后 access 与 refresh 都没了，本机再也补不了。
    func recordUnfinishedRevocation(deviceToken: String?, needsLogout: Bool) {
        guard let accessToken, deviceToken != nil || needsLogout else { return }
        pendingSessionRevoker.record(PendingSessionRevocation(
            accessToken: accessToken,
            refreshToken: tokenRefresher.currentRefreshToken,
            deviceToken: deviceToken,
            needsLogout: needsLogout,
            recordedAt: Date(),
            userId: userId
        ))
    }

    /// 「仅退出本机」（会话校验失败、联不上服务端时的出口）：只清本地，服务端这次登录与推送绑定都还在，
    /// 记进待撤记录，联网后补撤（#459）。不记的话 refresh 在服务端还能用 30 天，推送也一直绑着。
    func signOutLocallyRecordingRevocation() {
        recordUnfinishedRevocation(deviceToken: pushNotificationsManager?.boundDeviceToken, needsLogout: true)
        clearSession()
    }

    /// 补撤用的 transport：用记录里的 access，**不带续期器**（续期器属于当前会话）。
    /// 单测注入的 `apiClientOverride` 照样用；Mock 与发布构建禁用的环境返回 nil，记录留到能撤的时候。
    func revocationTransport(accessToken: String?) -> (any APIClientProtocol)? {
        if let apiClientOverride { return apiClientOverride }
        guard currentEnvironment == .demoCloud,
              AppBuildChannel.current.allows(currentEnvironment),
              let baseURL = currentEnvironment.baseURL else { return nil }
        return URLSessionAPIClient(baseURL: baseURL, tokenProvider: { accessToken })
    }
}
