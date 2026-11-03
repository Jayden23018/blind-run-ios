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

/// 这个用户手上有没有不能被盖住的订单或求助。
enum AppUpdateOrderPresence: Equatable {
    case none
    case active
    /// 查不到。与 `.active` 同样不拦：宁可少拦一次，也不能盖住一个正在跑步的人。
    case unknown
}

/// 根视图此刻要显示什么。
enum AppUpdatePresentation: Equatable {
    case none
    case optionalPrompt(AppUpdateTarget)
    case requiredGate(AppUpdateTarget)
}

/// 🔴 **所有拿不准的分支都落到「不拦」。** 契约原话：「字段是 null、请求失败、版本号解析不了，一律不拦用户」。
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

    /// - Parameter dismissedVersion: 用户关闭过提示的那个最新版本。只对可关闭的提示生效。
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
            return .requiredGate(target)
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

    /// 只放行 https（#526 后端评论）。没有能打开的地址时不提示：全屏页上没有更新按钮等于把人锁死。
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

/// 强制更新页与可关闭提示的文案。盲人端每句都会被念出来，所以每句都能脱离屏幕听懂。
enum AppUpdateCopy {
    static let requiredTitle = "需要更新才能继续使用"
    static let updateButtonTitle = "去更新"
    static let updateAccessibilityHint = "打开 App Store 的更新页面"
    static let repeatButtonTitle = "重复说明"
    static let repeatAccessibilityHint = "再听一遍为什么需要更新"
    static let openFailed = "打不开更新页面。请打开 App Store，搜索「助盲跑」手动更新。"
    static let optionalTitle = "有新版本"
    static let optionalLaterButtonTitle = "以后再说"

    /// 「App 不会代你发送求助」写在原因里：这一页的紧急入口只会拨号（`AGENTS.md` §6）。
    static func requiredReason(currentVersion: String, targetVersion: String) -> String {
        "你的助盲跑版本是\(currentVersion)，已经不再支持。请更新到\(targetVersion)或更新的版本。"
            + "紧急情况可以按「紧急呼叫」自己打电话，App 不会代你发送求助。"
    }

    static func optionalMessage(targetVersion: String) -> String {
        "助盲跑\(targetVersion)已经发布。现在的版本还能继续用，可以以后再更新。"
    }
}
