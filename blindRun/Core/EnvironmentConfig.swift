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
            return .production
        }
    }

    func allows(_ environment: APIEnvironment) -> Bool {
        switch self {
        case .development:
            return [.mock, .demoCloud].contains(environment)
        case .demo:
            return environment == .demoCloud
        case .production:
            return environment == .production
        }
    }
}

// MARK: - API Environment

enum APIEnvironment: String, CaseIterable, Sendable {
    case mock
    case localBackend
    case demoCloud
    case production

    var displayName: String {
        switch self {
        case .mock:
            return "Mock (本地模拟)"
        case .localBackend:
            return "本地后端"
        case .demoCloud:
            return "演示云端"
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
            return AppConstants.LocalBackend.normalizedBaseURL(
                from: UserDefaults.standard.string(forKey: AppConstants.UserDefaultsKeys.localBackendBaseURL)
                    ?? UserDefaults.standard.string(forKey: AppConstants.UserDefaultsKeys.localBackendIP)
                    ?? AppConstants.Defaults.localBackendIP
            )
        case .demoCloud:
            return AppConstants.DemoCloud.baseURL
        case .production:
            return AppConstants.ProductionBackend.configuredBaseURL()
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
        static let localBackendBaseURL = "com.aidrun.mvp.localBackendBaseURL"
    }

    enum Defaults {
        static let localBackendIP = "127.0.0.1"
        static let legacyLocalBackendIP = "192.168.1.100"
        static let productionBackendBaseURL = "https://api.aidrun.example.com"
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

    enum LocalBackend {
        nonisolated static func normalizedBaseURL(from value: String) -> URL? {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return URL(string: "http://127.0.0.1:8081")
            }

            if let url = URL(string: trimmed), url.scheme != nil, url.host != nil {
                return normalizedHTTPURL(from: url)
            }

            return URL(string: "http://\(trimmed):8081").flatMap(normalizedHTTPURL(from:))
        }

        nonisolated static func normalizedDisplayString(from value: String) -> String {
            normalizedBaseURL(from: value)?.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                ?? "http://127.0.0.1:8081"
        }

        nonisolated static func save(_ value: String) {
            let displayString = normalizedDisplayString(from: value)
            UserDefaults.standard.set(displayString, forKey: "com.aidrun.mvp.localBackendBaseURL")
            UserDefaults.standard.set(displayString, forKey: "com.aidrun.mvp.localBackendIP")
        }

        nonisolated private static func normalizedHTTPURL(from url: URL) -> URL? {
            guard let host = url.host else { return nil }
            var components = URLComponents()
            components.scheme = url.scheme ?? "http"
            components.host = host
            components.port = url.port ?? 8081
            return components.url
        }
    }

    enum DemoCloud {
        static let baseURL = URL(string: "http://47.114.113.171")!
    }

    enum ProductionBackend {
        static func configuredBaseURL(bundle: Bundle = .main) -> URL? {
            let rawValue = bundle.object(forInfoDictionaryKey: "AidRunProductionAPIBaseURL") as? String
            return normalizedBaseURL(from: rawValue ?? AppConstants.Defaults.productionBackendBaseURL)
        }

        static func normalizedBaseURL(from value: String) -> URL? {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let url = URL(string: trimmed),
                  url.scheme == "https",
                  url.host != nil else {
                return nil
            }
            return url
        }
    }
}
