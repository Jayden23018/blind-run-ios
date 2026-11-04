//
//  MockAPIClient+AuthenticatedReads.swift
//  blindRun
//
//  需登录、不限角色、无参数的只读端点。从 `MockAPIClient.routeRequest` 原样搬出，行为零改动 ——
//  那个函数与文件只许变短（SwiftLint 棘轮 #488），而每加一个端点就多一个分支。
//

import Foundation

extension MockAPIClient {

    /// 不是这里管的路径返回 `nil`，由 `routeRequest` 继续往下匹配。
    func handleAuthenticatedRead(path: String) throws -> Any? {
        switch path {
        // 功能开关（`GET /api/config/features`）。需登录、不限角色。
        //
        // 🚩 **默认返回「全开」，与 Mock 其余激励数据保持同一个前提**（见
        // `MockAPIClient+Incentive` 顶部：Mock 演的是三个开关都打开之后的行为）。
        // 若这里返回生产的真实值（全关），火花种子数据与空态文案会自相矛盾：
        // 列表里有四位搭档，空态却说「功能还没有开放」。
        //
        // 生产现状那一档（全关）由 `AIDRUN_MOCK_FEATURE_FLAGS_OFF=1` 覆盖 ——
        // 「关着时空态说什么」这条分支正是本次改动要验的，没有它就只能靠单测。
        case "/api/config/features":
            guard mockToken != nil, !isAccountDeleted else { throw APIError.unauthorized }
            let allOff = ProcessInfo.processInfo.environment["AIDRUN_MOCK_FEATURE_FLAGS_OFF"] == "1"
            return FeatureFlagsResponse(
                partnerStreakEnabled: !allOff,
                favoriteDispatchRoundEnabled: !allOff,
                invitationRewardEnabled: !allOff
            )

        // 待回复邀请（`GET /api/volunteer/pending-invites`，后端 #366）。**裸对象**，不套信封。
        // Mock 没有派单链路，所以默认是空列表；UI 测试种了邀请时返回同样的那几张 ——
        // 种子只进首页、不进这里的话，首页一对账就会把它们全判成失效（真实后端不会这样自相矛盾）。
        case "/api/volunteer/pending-invites":
            guard mockToken != nil, !isAccountDeleted else { throw APIError.unauthorized }
            return PendingInvitesResponse(consecutiveDeclineCount: 0, invites: Self.uiTestSeededPendingInvites())

        // 规则参数（`GET /api/config/rules`）。需登录、不限角色。返回契约里的默认值
        // （`RuleParamsResponse` 的 `example`），与客户端的回退值相同 —— Mock 里两条路走出来的行为一样，
        // 拿不到时那条由 `RuleParamsAndLateCancelTests` 覆盖。`launchScope` 默认无限制；
        // `AIDRUN_MOCK_LAUNCH_SCOPE=closed / restricted` 演「暂不接受预约」「只开放部分城市和时段」（#667）。
        case "/api/config/rules":
            guard mockToken != nil, !isAccountDeleted else { throw APIError.unauthorized }
            return RuleParamsResponse(
                lateCancelWindowHours: 12,
                volunteerOrderAutoOpenLeadMinutes: 120,
                launchScope: Self.mockLaunchScope(ProcessInfo.processInfo.environment["AIDRUN_MOCK_LAUNCH_SCOPE"])
            )

        // 版本要求（`GET /api/config/app-version`）。这个文件里唯一免登录的一条。默认全是 null，
        // 与「后端没配置」相同，其余 UI 用例不受影响。`AppUpdateGateUITests` 用这两个开关演版本过低。
        case "/api/config/app-version":
            let environment = ProcessInfo.processInfo.environment
            return AppVersionResponse(
                iosMinSupportedVersion: environment["AIDRUN_MOCK_APP_MIN_VERSION"],
                iosLatestVersion: environment["AIDRUN_MOCK_APP_LATEST_VERSION"],
                iosUpdateUrl: "https://apps.apple.com/cn/app/aidrun"
            )

        default:
            return nil
        }
    }

    /// 种子期限的基准：进程启动那一刻（与首页种下邀请的时刻只差几毫秒）。**不能每次请求现取 `Date()`**：
    /// 那样同一张种子每次都拿到一个新的 120 秒窗口，过期或回复过之后下一次对账又以新邀请复活 ——
    /// 而真实后端只返回「还没过期、还在等回复」的邀请。
    private static let uiTestSeedEpoch = Date()

    /// `GET /api/config/rules` 的 `launchScope`（#667）。默认无限制，与「后端没配置」相同，其余 UI 用例不受影响。
    /// `restricted` 只开放深圳、杭州的工作日晚上：Mock 的演示坐标在北京，出发地点那一步会显示「不在开放范围内」。
    static func mockLaunchScope(_ mode: String?) -> LaunchScopeResponse {
        switch mode {
        case "closed":
            return .closed(notice: "陪跑服务暂未开放，现在还不能预约，开放后再来下单。")
        case "restricted":
            return LaunchScopeResponse(
                acceptingOrders: true, areaRestricted: true, dutyHoursRestricted: true,
                areaHint: "目前只开放深圳市、杭州市。", dutyHoursHint: "可预约的开跑时间是周一到周五 18:00 到 21:00。",
                openAreas: [
                    .init(name: "深圳市", southLat: 22.4, northLat: 22.9, westLng: 113.7, eastLng: 114.6),
                    .init(name: "杭州市", southLat: 29.9, northLat: 30.6, westLng: 119.8, eastLng: 120.5)
                ],
                dutyWindows: [.init(days: ["MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY"], start: "18:00", end: "21:00")]
            )
        default:
            return LaunchScopeResponse(acceptingOrders: true, areaRestricted: false, dutyHoursRestricted: false)
        }
    }

    /// 建单被开放范围拒绝时后端的 422（#667）。message 照契约的写法：说清发生了什么、为什么、能做什么。
    static func mockLaunchScopeRejection(_ code: String?) -> APIError? {
        let messages = [
            "ORDER_SERVICE_NOT_OPEN": "陪跑服务暂未开放，现在还不能预约，开放后再来下单",
            "ORDER_OUTSIDE_OPEN_AREA": "这个出发点不在开放范围内。目前只开放深圳市、杭州市，请换一个开放范围内的出发点",
            "APPOINTMENT_OUTSIDE_DUTY_HOURS": "这个时间没有值守人员，暂不接受预约。可预约的开跑时间是周一到周五 18:00 到 21:00，请换个时间"
        ]
        guard let code, let message = messages[code] else { return nil }
        return .serverError(ErrorResponse(code: code, message: message))
    }

    /// 与 `VolunteerHomeViewModel.seedInvitesForUITestsIfNeeded` 同一个开关、同一批 id、同一个期限算法。
    /// 已过期的不返回（契约口径）；回复过的由协调器的「已了结」记录挡住，不在这里模拟。
    private static func uiTestSeededPendingInvites(now: Date = Date()) -> [WSNewOrder] {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        guard environment["AIDRUN_UI_TEST_RESET_STATE"] == "1",
              let raw = environment["AIDRUN_UI_TEST_SEED_INVITES"],
              let count = Int(raw), count > 0 else { return [] }
        return (0..<count).compactMap { index in
            let expiresAt = uiTestSeedEpoch.addingTimeInterval(TimeInterval(120 + index * 30))
            guard expiresAt > now else { return nil }
            var invite = VolunteerHomeViewModel.uiTestSeedInvite(orderId: Int64(9_000 + index), now: uiTestSeedEpoch)
            invite.expiresAt = DateFormatter.aidRunBackendLocalDateTime.string(from: expiresAt)
            return invite
        }
        #else
        return []
        #endif
    }
}
