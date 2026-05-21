import Foundation

// MARK: - API Environment

enum APIEnvironment: String, CaseIterable, Sendable {
    case mock
    case localBackend
    case production

    var displayName: String {
        switch self {
        case .mock:
            return "Mock (本地模拟)"
        case .localBackend:
            return "本地后端"
        case .production:
            return "生产环境"
        }
    }

    var baseURL: URL? {
        switch self {
        case .mock:
            // Mock 模式不使用网络，返回 nil
            return nil
        case .localBackend:
            let ip = UserDefaults.standard.string(forKey: AppConstants.UserDefaultsKeys.localBackendIP)
                ?? AppConstants.Defaults.localBackendIP
            return URL(string: "http://\(ip):8080")
        case .production:
            // 占位 URL，部署后替换
            return URL(string: "https://api.aidrun.example.com")
        }
    }

    var isMock: Bool {
        self == .mock
    }
}

// MARK: - App Constants

enum AppConstants {
    enum UserDefaultsKeys {
        static let accessToken = "com.aidrun.mvp.accessToken"
        static let activeRole = "com.aidrun.mvp.activeRole"
        static let apiEnvironment = "com.aidrun.mvp.apiEnvironment"
        static let localBackendIP = "com.aidrun.mvp.localBackendIP"
    }

    enum Defaults {
        static let localBackendIP = "192.168.1.100"
        // 北京默认测试坐标，供模拟器 Demo 使用
        static let demoLatitude: Double = 39.9042
        static let demoLongitude: Double = 116.4074
    }

    enum Timing {
        // 盲人端订单状态轮询间隔
        static let orderPollingInterval: TimeInterval = 5.0
        // 预约最少提前时间（分钟）
        static let minimumBookingLeadMinutes: Int = 30
    }
}
