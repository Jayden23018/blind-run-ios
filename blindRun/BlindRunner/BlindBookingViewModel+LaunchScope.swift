import SwiftUI

/// 下单页的开放范围提示（#667）。原由旧四步表单显示，表单界面已删（#810），约跑页还没接上（#813）。
/// **只提示不阻断**：能不能下单以 `POST /api/orders` 为准。
/// 句子由后端拼好（`areaHint` / `dutyHoursHint`），客户端只在「已选的不在范围里」时加一句前缀。
extension BlindBookingViewModel {
    /// 「出发地点」一步的提示。没有限制时 `nil`，界面一个字不提。
    var launchScopeAreaNotice: String? {
        appState?.ruleParamsResponse?.launchScope?.areaNotice(
            latitude: resolvedStartPlace?.latitude,
            longitude: resolvedStartPlace?.longitude
        )
    }

    /// 「预约时间」一步的提示。没有限制时 `nil`。
    var launchScopeDutyHoursNotice: String? {
        appState?.ruleParamsResponse?.launchScope?.dutyHoursNotice(start: appointmentTime)
    }
}

/// 两步共用的那一行提示。`text == nil` 时什么都不画。
struct LaunchScopeStepNotice: View {
    let text: String?
    let identifier: String

    var body: some View {
        if let text {
            Text(text)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier(identifier)
        }
    }
}
