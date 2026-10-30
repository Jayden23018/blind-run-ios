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
        self == .cloudTrigger ? "打开当前订单的求助选项" : EmergencyCallContext.runner(for: self).accessibilityHint
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
