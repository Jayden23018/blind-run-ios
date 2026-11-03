import Foundation

/// `GET /api/config/app-version` 响应体（`APIClient` 已自动解包 `{success, data}` 外层信封）。
///
/// 只解 iOS 的三个字段。安卓的字段同在 `data` 里，这里用不上。
/// 三个字段都可能是 null，表示这一项没有配置，判定在 `AppUpdatePolicy.verdict`。
struct AppVersionResponse: Codable, Sendable, Equatable {
    let iosMinSupportedVersion: String?
    let iosLatestVersion: String?
    let iosUpdateUrl: String?
}
