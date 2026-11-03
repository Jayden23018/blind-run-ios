import Foundation

/// 点分数字版本号。逐段按数字比较：`1.10` 大于 `1.9`，按字符串比较时结果相反。
///
/// 缺的尾段按 0 算：工程的 `MARKETING_VERSION` 是两段（`1.0`），后端下发三段（`1.0.0`），两者相等。
struct AppVersionNumber: Comparable {
    private let segments: [Int]

    /// 只认 ASCII 数字段。`Int("+1")` 能解析，但 `+1.2` 不是版本号；`1.2.0-beta`、`v1.2`、`1..2` 同样解析失败。
    init?(_ raw: String?) {
        guard let parts = raw?.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ".", omittingEmptySubsequences: false) else {
            return nil
        }
        var parsed: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy({ $0.isASCII && $0.isNumber }), let value = Int(part) else { return nil }
            parsed.append(value)
        }
        segments = parsed
    }

    private func segment(at index: Int) -> Int {
        index < segments.count ? segments[index] : 0
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        for index in 0..<max(lhs.segments.count, rhs.segments.count) where lhs.segment(at: index) != rhs.segment(at: index) {
            return lhs.segment(at: index) < rhs.segment(at: index)
        }
        return false
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}

/// 要更新到的版本和去哪更新。两样都有才算一个能执行的更新要求。
struct AppUpdateTarget: Equatable {
    let version: String
    let url: URL
}

/// 服务端的版本要求对当前版本意味着什么。
enum AppUpdateVerdict: Equatable {
    case upToDate
    case optional(AppUpdateTarget)
    case required(AppUpdateTarget)
}

/// 这个用户此刻是不是走在陪跑里。
enum AppUpdateOrderPresence: Equatable {
    case none
    /// `DRIVER_EN_ROUTE` / `DRIVER_ARRIVED` / `IN_PROGRESS`，或有未结束的求助。
    case underway
    /// 查不到。与 `.underway` 同样不弹：宁可少弹一次，也不能挡住一个正在跑步的人。
    case unknown
}

/// 根视图此刻要弹什么。
enum AppUpdatePresentation: Equatable {
    case none
    case optionalPrompt(AppUpdateTarget)
    case requiredPrompt(AppUpdateTarget)

    var target: AppUpdateTarget? {
        switch self {
        case .none: return nil
        case .optionalPrompt(let target), .requiredPrompt(let target): return target
        }
    }

    var isRequired: Bool {
        if case .requiredPrompt = self { return true }
        return false
    }
}

/// 🔴 **所有拿不准的分支都落到「不弹」。** 契约原话：「字段是 null、请求失败、版本号解析不了，一律不拦用户」。
/// 这里写错的后果是所有人进不了 App，所以判定是纯函数，由 `AppUpdatePolicyTests` 逐项钉住。
enum AppUpdatePolicy {
    /// - Parameter requirements: `nil` = 请求失败。线上后端未部署时这个接口返回 401，走的就是这里。
    static func verdict(currentVersion: String?, requirements: AppVersionResponse?) -> AppUpdateVerdict {
        guard let requirements,
              let current = AppVersionNumber(currentVersion),
              let url = updateURL(requirements.iosUpdateUrl) else {
            return .upToDate
        }
        if let target = target(version: requirements.iosMinSupportedVersion, above: current, url: url) {
            return .required(target)
        }
        if let target = target(version: requirements.iosLatestVersion, above: current, url: url) {
            return .optional(target)
        }
        return .upToDate
    }

    /// - Parameter dismissedVersion: 用户点过「稍后」的那个最新版本。只对可关闭的提示生效。
    static func presentation(
        verdict: AppUpdateVerdict,
        orderPresence: AppUpdateOrderPresence,
        dismissedVersion: String?
    ) -> AppUpdatePresentation {
        guard orderPresence == .none else { return .none }
        switch verdict {
        case .upToDate:
            return .none
        case .required(let target):
            return .requiredPrompt(target)
        case .optional(let target):
            return target.version == dismissedVersion ? .none : .optionalPrompt(target)
        }
    }

    private static func target(version: String?, above current: AppVersionNumber, url: URL) -> AppUpdateTarget? {
        guard let version = version?.trimmingCharacters(in: .whitespacesAndNewlines),
              let parsed = AppVersionNumber(version),
              current < parsed else {
            return nil
        }
        return AppUpdateTarget(version: version, url: url)
    }

    /// 只放行 https（#526 后端评论）。没有能打开的地址时不弹：弹窗上唯一的按钮按下去没有去处。
    private static func updateURL(_ raw: String?) -> URL? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: raw),
              url.scheme?.lowercased() == "https",
              url.host?.isEmpty == false else {
            return nil
        }
        return url
    }
}

/// 更新弹窗的文案。
enum AppUpdateCopy {
    static let requiredTitle = "版本过低"
    static let optionalTitle = "有新版本"
    static let updateButtonTitle = "去更新"
    static let laterButtonTitle = "稍后"
    static let openFailed = "打不开更新页面。请打开 App Store，搜索「助盲跑」手动更新。"

    static func requiredMessage(targetVersion: String) -> String {
        "当前版本过低，请更新到\(targetVersion)后继续使用。"
    }

    static func optionalMessage(targetVersion: String) -> String {
        "助盲跑\(targetVersion)已发布，建议更新。"
    }
}
