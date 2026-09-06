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
        static let blindIdentityPromptDismissed = "com.aidrun.mvp.blindIdentityPromptDismissed"
        /// 首次使用引导是否已经看过。
        ///
        /// **刻意不进 `AppStatePersistenceKeys.all`，登出也不清。** 它记的是「这个人会不会用
        /// 这个 App」，不是账号数据 —— 换手机号重新登录的盲人被强制再听一遍一分钟的引导，
        /// 是实打实的打扰，而漏掉引导的代价有兜底：「设置 → 使用帮助」一直在。
        /// 测试不受影响：单测与 UI 测试都跑在独立 suite 上，`reset()` 整域清除。
        static let blindFirstRunHelpSeen = "com.aidrun.mvp.blindFirstRunHelpSeen"
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
        /// 预约最远提前天数。镜像后端 `app.order.max-lead-days`（默认 7，2026-09-05 随跨天预约上线）。
        ///
        /// 在此之前下单**只有下限没有上限**，选择器可以选到几个月后，提交时吃一个 422。
        /// 对盲人一次被拒 = 重走整套读回流程，所以拦在选择器上。
        ///
        /// ⚠️ 这是后端配置的镜像，与 `minimumBookingLeadMinutes` 同一性质（那条早就这么做了）。
        /// 后端调整它时这里要跟；跟不上的那段时间由 `ErrorCode.appointmentTooFar` 兜底，
        /// **所以那个错误码不能删**。
        static let maximumBookingLeadDays: Int = 7
        /// 夜间禁跑窗口 `[22:00, 05:00)`，镜像后端 N134（`OrderCreationService.overlapsNightWindow`）。
        ///
        /// 🚩 **判据是整段行程有没有交集，不是开始时刻**：`21:00–22:30` 拒、
        /// `21:00–22:00` 放行（恰好 22:00 结束不算重叠）、`05:00–06:00` 放行、
        /// `次日 04:00–06:00` 拒（凌晨 4 点属于前一天那扇窗口）。
        static let nightWindowStartHour: Int = 22
        static let nightWindowEndHour: Int = 5
        /// 用户没说时长时，给 `plannedEndTime` 的兜底。
        ///
        /// 🚨 **它不是 `expectedDurationMinutes`。** 那个字段在用户没说时长时必须保持 nil
        /// （没说就是没说，与 `hasGuideDogThisRun` 那条三态红线同源）；
        /// 只有 `plannedEndTime` 在契约上是必填，必须有个值。
        ///
        /// 🚨 **这个数字有真实后果，不是一个无害的默认值。** 后端全部超时判定都用
        /// `plannedEndTime`：`+15min` 推 `ORDER_OVERDUE`（家属/跑者会收到「可能失联」级别的提示）、
        /// `+60min` **自动把订单置成 COMPLETED**；行程分享链接的有效期也是
        /// `max(plannedEndTime, now) + 2h`。所以它必须被**说出来**，
        /// 见 `BlindBookingViewModel.plannedEndSummary`。
        static let defaultBookingDurationMinutes: Int = 60
    }

    enum DemoCloud {
        static let baseURL = URL(string: "http://47.114.113.171")!
    }
}
