import Foundation

// MARK: - Build Channel

enum AppBuildChannel: Sendable {
    case development
    case demo
    case production

    static var current: AppBuildChannel {
        #if DEBUG
        return .development
        #elseif DEMO
        return .demo
        #else
        return .production
        #endif
    }

    var allowsEnvironmentSwitcher: Bool {
        self == .development
    }

    var defaultEnvironment: APIEnvironment {
        switch self {
        case .development:
            return .mock
        case .demo:
            return .demoCloud
        case .production:
            return .demoCloud
        }
    }

    func allows(_ environment: APIEnvironment) -> Bool {
        switch self {
        case .development:
            return [.mock, .demoCloud].contains(environment)
        case .demo, .production:
            return environment == .demoCloud
        }
    }
}

// MARK: - API Environment

enum APIEnvironment: String, CaseIterable, Sendable {
    case mock
    case demoCloud

    var displayName: String {
        switch self {
        case .mock:
            return "Mock (本地模拟)"
        case .demoCloud:
            return "演示云端"
        }
    }

    var baseURL: URL? {
        switch self {
        case .mock:
            // Mock 模式不使用网络，返回 nil
            return nil
        case .demoCloud:
            return AppConstants.DemoCloud.baseURL
        }
    }

    var isMock: Bool {
        self == .mock
    }
}

// MARK: - App Constants

enum AppConstants {
    enum Auth {
        static let demoVerificationCode = "000000"
    }

    enum UserDefaultsKeys {
        static let accessToken = "com.aidrun.mvp.accessToken"
        static let activeRole = "com.aidrun.mvp.activeRole"
        static let apiEnvironment = "com.aidrun.mvp.apiEnvironment"
    }

    enum Defaults {
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

    enum DemoCloud {
        static let baseURL = URL(string: "http://47.114.113.171")!
    }
}
