import SwiftUI

// MARK: - Location Permission Guard

/// 定位权限被拒绝时显示的引导视图。
/// 根据用户角色显示不同的提示信息，引导用户前往系统设置开启定位权限。
struct LocationPermissionGuard: View {

    let role: UserRole

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "location.slash.fill")
                .font(.system(size: 48))
                .foregroundColor(AppColors.destructive)

            Text("需要定位权限")
                .font(AppFonts.title())
                .foregroundColor(AppColors.textPrimary)

            Text(messageForRole)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            PrimaryButton("前往设置") {
                openSettings()
            }
            .padding(.horizontal, 32)
            .padding(.top, 8)
            .accessibilityLabel("前往设置开启定位权限")
            .accessibilityHint("点击后打开系统设置页面")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Private

    private var messageForRole: String {
        switch role {
        case .blind:
            return "需要定位权限才能创建预约。请在设置中开启定位权限。"
        case .volunteer:
            return "需要定位权限才能查看距离和接单。请在设置中开启定位权限。"
        case .unset:
            return "需要定位权限才能使用位置服务。请在设置中开启定位权限。"
        }
    }

    private func openSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        UIApplication.shared.open(settingsURL) // guard:allow raw-open-url 系统设置，不是拨号
    }
}

// MARK: - Demo Fallback Banner

/// 使用 Demo 默认位置时显示的提示横幅
struct DemoLocationBanner: View {

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundColor(AppColors.textSecondary)
            Text("使用默认演示位置")
                .font(AppFonts.caption())
                .foregroundColor(AppColors.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AppColors.secondaryBackground)
        .cornerRadius(8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("使用默认演示位置")
        .accessibilityHint("当前显示的位置为演示用途，非真实定位")
    }
}

#if DEBUG
#Preview("Blind Runner") {
    LocationPermissionGuard(role: .blind)
}

#Preview("Volunteer") {
    LocationPermissionGuard(role: .volunteer)
}

#Preview("Demo Banner") {
    DemoLocationBanner()
        .padding()
}
#endif
