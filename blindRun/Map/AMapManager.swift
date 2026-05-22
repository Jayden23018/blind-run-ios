import Foundation
import AMapFoundationKit

// MARK: - AMap SDK Manager

/// 高德地图 SDK 初始化管理器。
/// 从 Info.plist 读取 AMap API Key 并初始化 SDK。
/// 当 Key 未配置时优雅降级，不会导致崩溃。
enum AMapManager {

    /// SDK 是否已成功配置（Key 有效且 SDK 初始化完成）
    private(set) static var isConfigured = false

    /// 初始化高德地图 SDK。
    /// 应在 App 启动时调用一次（如 blindRunApp.onAppear）。
    static func configure() {
        guard let key = resolveAPIKey(),
              !key.isEmpty,
              key != "YOUR_AMAP_IOS_KEY_HERE" else {
            isConfigured = false
            #if DEBUG
            print("[AMapManager] 高德地图 Key 未配置，地图功能不可用。请参考 LocalConfig.xcconfig.example 配置 Key。")
            #endif
            return
        }

        AMapServices.shared().apiKey = key
        AMapServices.shared().enableHTTPS = true
        isConfigured = true

        #if DEBUG
        print("[AMapManager] 高德地图 SDK 初始化成功")
        #endif
    }

    // MARK: - Private

    private static func resolveAPIKey() -> String? {
        // 优先从 Info.plist 的 AMapApiKey 字段读取（由 xcconfig 注入）
        if let key = Bundle.main.infoDictionary?["AMapApiKey"] as? String {
            return key
        }
        // 备选：从 AMAP_API_KEY 字段读取
        if let key = Bundle.main.infoDictionary?["AMAP_API_KEY"] as? String {
            return key
        }
        return nil
    }
}
