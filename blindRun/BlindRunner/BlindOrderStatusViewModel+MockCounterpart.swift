import SwiftUI

extension BlindOrderStatusViewModel {
    // MARK: - Mock 环境的对家代打

#if DEBUG
    /// Mock 状态测试面板上那几个按钮代表的一步。志愿者那半边在单设备上凑不齐，
    /// 由这一组按钮代打。
    enum MockCounterpartStep {
        case respond(OrderRespondAction)
        /// 跨天预约单的临期确认。志愿者那半边在单设备上凑不齐，由这个按钮代打 ——
        /// 不做的话 `SCHEDULED_CONFIRMED` 之后的整条链路在 Mock 里根本走不下去。
        case confirmDeparture
        case enRoute
        case arrived
        case startService
        case finish
    }

    /// 代对方角色推进一次状态机（`.mock` 环境专用，调用点自己判环境）。
    ///
    /// 🚨 **失败必须说出来。** 这段原来是 6 个 `try?`，散在 view body 里：
    /// 从 `PENDING_ACCEPT` 直接打 `/arrived` 会被 Mock 按真实状态机拒掉，
    /// 而 `try?` 把拒绝吞成静默，现象是「点了没反应」，后续依赖 `DRIVER_ARRIVED`
    /// 的「模拟服务开始」永不出现 —— 排查时看不出是被拒了还是按钮没接上。
    func runMockCounterpartSteps(_ steps: [MockCounterpartStep], orderId: Int64) async {
        guard let appState else { return }
        let orders = appState.orders
        do {
            for step in steps {
                switch step {
                case .respond(let action):
                    try await orders.respond(orderId: orderId, action: action)
                case .confirmDeparture:
                    try await orders.confirmDeparture(orderId: orderId)
                case .enRoute:
                    try await orders.enRoute(orderId: orderId)
                case .arrived:
                    try await orders.arrived(orderId: orderId)
                case .startService:
                    try await orders.startService(orderId: orderId)
                case .finish:
                    try await orders.finish(orderId: orderId)
                }
            }
            errorMessage = nil
        } catch let error as APIError {
            errorMessage = "Mock 状态测试失败：\(error.localizedMessage)"
        } catch {
            errorMessage = "Mock 状态测试失败。"
        }
        startPolling(orderId: orderId)
    }
#endif
}
