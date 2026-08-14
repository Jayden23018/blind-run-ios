import SwiftUI

// MARK: - Map Placeholder View

/// 当高德地图 API Key 未配置时显示的占位视图。
/// 提供清晰的引导信息，不会导致白屏或崩溃。
struct MapPlaceholderView: View {

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "map.fill")
                .font(.system(size: 48))
                .foregroundColor(AppColors.textSecondary)

            Text("地图服务暂不可用")
                .font(AppFonts.title())
                .foregroundColor(AppColors.textPrimary)

            Text("请配置高德地图 API Key")
                .font(AppFonts.body())
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)

            #if DEBUG
            Text("参考 LocalConfig.xcconfig.example 创建配置文件")
                .font(AppFonts.caption())
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.secondaryBackground)
        .cornerRadius(12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("地图服务暂不可用，请配置高德地图 API Key")
        // 无障碍审计要按 identifier 认出它 —— 它是地图的替身，而地图本身已在白名单里。
        // 没有这个 id 时审计拿到的是空字符串，只能连同真问题一起放行或一起拦。
        .accessibilityIdentifier("mapPlaceholder")
    }
}

#if DEBUG
#Preview {
    MapPlaceholderView()
        .frame(height: 300)
        .padding()
}
#endif
