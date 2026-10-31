import SwiftUI

// MARK: - 跑者端「我的」的紧急入口

/// 从「我的」或全屏手势要订单页做的事。
///
/// 云端求助的结果面（状态提示、失败后的兜底拨号、撤销）全在订单页上，所以陪跑中一律把人带到订单页，
/// 不在标签页这一层另开一条云端链路（#605）。
enum BlindOrderSafetyRequest: Equatable {
    /// 打开求助中心。给列表那一行用：按下去看到全部选项。
    case safetyHub
    /// 直接弹逐字锁定的二次确认。给全屏手势用：读屏用户此刻只要发出求助，别多一层。
    case confirmEmergency
}

extension BlindHomeSOSMode {
    /// 按全屏手势时要订单页做什么。`nil` = 不去订单页，就地弹本地拨号单。
    var orderSafetyRequestForGesture: BlindOrderSafetyRequest? {
        self == .cloudTrigger ? .confirmEmergency : nil
    }

    /// 按列表那一行时要订单页做什么。`nil` 同上。
    var orderSafetyRequestForRow: BlindOrderSafetyRequest? {
        self == .cloudTrigger ? .safetyHub : nil
    }

    /// 云端这一档按下去只是打开选项，不叫「一键求助」：那四个字在本 App 里指已经会发出去的动作。
    var profileRowTitle: String {
        self == .cloudTrigger ? EmergencySafetyCopy.hubTitle : EmergencySafetyCopy.homeCallTitle
    }

    var profileRowAccessibilityLabel: String {
        self == .cloudTrigger ? EmergencySafetyCopy.hubAccessibilityLabel : EmergencySafetyCopy.homeCallAccessibilityLabel
    }

    var profileRowAccessibilityHint: String {
        self == .cloudTrigger
            ? EmergencySafetyCopy.profileRowHubAccessibilityHint
            : EmergencyCallContext.runner(for: self).accessibilityHint
    }
}

/// 订单页接走「我的」或全屏手势转来的紧急请求（#605）。
struct OrderSafetyRequestPresenter: ViewModifier {
    private static let presentDelay: UInt64 = 500_000_000
    private static let orderPollInterval: UInt64 = 100_000_000
    private static let orderPollLimit = 20

    @Binding var request: BlindOrderSafetyRequest?
    let isOrderLoaded: () -> Bool
    let isCloudMode: () -> Bool
    let showConfirmation: () -> Void
    let showSafetyHub: () -> Void

    func body(content: Content) -> some View {
        // `.task(id:)` 同时盖住「订单页已在栈里」和「刚被推上来」两种到达顺序。
        content.task(id: request) {
            guard let pending = request else { return }
            // 推入动画没结束时弹 alert 会被系统丢掉，而这是紧急入口，丢了就是按了没反应。
            try? await Task.sleep(nanoseconds: Self.presentDelay)
            await waitForOrder()
            guard !Task.isCancelled else { return }
            request = nil
            present(pending)
        }
    }

    /// 订单页刚推上来时订单还在加载。等一下再判，否则网络一慢手势就多出求助中心这一层。
    private func waitForOrder() async {
        for _ in 0..<Self.orderPollLimit where !isOrderLoaded() {
            try? await Task.sleep(nanoseconds: Self.orderPollInterval)
        }
    }

    /// 等过之后订单还没到时不是云端档，这时弹确认框，确认后会因为没有订单而零反应。
    /// 所以落到求助中心：它按当前模式给出能按的选项，订单加载完自动换成云端档。
    private func present(_ pending: BlindOrderSafetyRequest) {
        if pending == .confirmEmergency, isCloudMode() {
            showConfirmation()
        } else {
            showSafetyHub()
        }
    }
}

/// 设置页要显示的紧急入口：模式由标签页这一层算好，动作也由它接管。
struct BlindSettingsEmergencyEntry {
    let mode: BlindHomeSOSMode
    let action: () -> Void
}

/// 「我的」设置列表里的紧急入口。判据只读 `BlindHomeSOSMode`，不自己判订单状态（`AGENTS.md` §6）。
struct BlindProfileEmergencyRow: View {
    let mode: BlindHomeSOSMode
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.small) {
                Image(systemName: mode == .cloudTrigger ? "shield" : "phone.fill")
                    .accessibilityHidden(true)
                Text(mode.profileRowTitle)
                    .font(AppFonts.body().weight(.semibold))
                Spacer(minLength: 0)
            }
            .foregroundColor(AppColors.destructive)
            .frame(maxWidth: .infinity, minHeight: AppTouchTarget.blindPrimary, alignment: .leading)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(mode.profileRowAccessibilityLabel)
        .accessibilityHint(mode.profileRowAccessibilityHint)
        .accessibilityIdentifier("blindProfileEmergencyRow")
    }
}
