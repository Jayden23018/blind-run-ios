import Foundation

// MARK: - Rule Params（`GET /api/config/rules`）

extension AppState {
    /// 拉规则参数（需登录、不限角色）。失败静默、下一次调用时重试；失败期间 `ruleParams` 是默认值。
    ///
    /// - Parameter force: 不管拉没拉过都重读。下单入口每次进入都这样读 `launchScope`（#667）：
    ///   开放范围随运营调整，按账号下发，不能拿一份旧的去告诉用户「哪里能约」。
    ///
    /// 请求回来时账号已经换了（登出、换号登录）就丢弃 —— 上一个账号的开放范围不能留给下一个账号。
    func loadRuleParamsIfNeeded(force: Bool = false) async {
        guard force || !didLoadRuleParams, let token = accessToken else { return }
        do {
            let response = try await auth.ruleParams()
            guard accessToken == token else { return }
            ruleParamsResponse = response
            didLoadRuleParams = true
        } catch {
            ClientFlowDiagnostics.record(event: "failed", operation: "rule-params")
        }
    }

    /// 会话结束时清空：`launchScope` 按账号下发，下一个账号要重新读。
    func resetRuleParams() {
        ruleParamsResponse = nil
        didLoadRuleParams = false
    }

    /// 下单被 422 `ORDER_SERVICE_NOT_OPEN` 拒：后端刚说了暂不接受预约。
    /// 下单入口闸门（`BlindBookingLaunchScopeGate`）据此当场换成告知页，念后端这句。下次进入入口时会重读真实数据。
    func noteBookingServiceNotOpen(message: String) {
        var response = ruleParamsResponse ?? RuleParamsResponse(lateCancelWindowHours: nil, volunteerOrderAutoOpenLeadMinutes: nil)
        response.launchScope = .closed(notice: message)
        ruleParamsResponse = response
    }
}
