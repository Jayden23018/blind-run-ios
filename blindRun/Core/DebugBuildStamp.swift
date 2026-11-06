#if DEBUG
import Foundation

/// Debug 包顶部那枚小标记的文字（`ContentView` 里替换原「Mock 本地模拟」黄胶囊）。
///
/// `scripts/preview-build.sh` 把「最新 main + 开着的 PR」合成一个预览包装到手机，并把合进去的
/// PR 号写进 Info.plist 的 `AidRunPreviewPRs`，形如 `main,784,790`（打头的 `main` 标明这是预览包）。
/// 从 Xcode 直接装的包这一项为空 —— 那时只在 Mock 环境下显示「Mock」，与以前一致。
///
/// 文字必须短：标记钉在状态栏左侧，灵动岛左边只有约 119pt（iPhone 16 Pro，x 24..143）。
/// 所以只列 1 个 PR 号，多于 1 个就只报个数；完整列表在 `accessibilityLabel` 里和脚本输出里。
enum DebugBuildStamp {
    static let infoPlistKey = "AidRunPreviewPRs"
    static let previewMarker = "main"
    static let maxListedPRs = 1

    struct Contents: Equatable {
        let isPreviewBuild: Bool
        let prNumbers: [Int]
    }

    /// 读 Info.plist 原值。未知的片段直接丢掉：这是调试标记，宁可少显示也不能崩。
    static func parse(_ raw: String?) -> Contents {
        let tokens = (raw ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard tokens.first == previewMarker else {
            return Contents(isPreviewBuild: false, prNumbers: [])
        }
        let numbers = tokens.dropFirst().compactMap { Int($0) }.filter { $0 > 0 }
        return Contents(isPreviewBuild: true, prNumbers: numbers)
    }

    /// 屏幕上显示的短文字；返回 nil 表示不显示标记。
    static func label(isMock: Bool, contents: Contents) -> String? {
        var parts: [String] = []
        if isMock { parts.append("Mock") }
        if contents.isPreviewBuild { parts.append(previewSummary(contents.prNumbers)) }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// 读屏念的完整说明：PR 号全部列出。
    static func accessibilityLabel(isMock: Bool, contents: Contents) -> String {
        var parts: [String] = ["调试标记"]
        if isMock { parts.append("Mock 本地模拟，不连接云端") }
        if contents.isPreviewBuild {
            if contents.prNumbers.isEmpty {
                parts.append("预览包，只有 main")
            } else {
                let list = contents.prNumbers.map(String.init).joined(separator: "、")
                parts.append("预览包，包含 PR \(list)")
            }
        }
        return parts.joined(separator: "，")
    }

    private static func previewSummary(_ numbers: [Int]) -> String {
        if numbers.isEmpty { return previewMarker }
        if numbers.count <= maxListedPRs {
            return numbers.map { "#\($0)" }.joined(separator: " ")
        }
        return "\(numbers.count) 个 PR"
    }

    /// 本次运行的包里写的内容。
    static var current: Contents {
        parse(Bundle.main.object(forInfoDictionaryKey: infoPlistKey) as? String)
    }
}
#endif
