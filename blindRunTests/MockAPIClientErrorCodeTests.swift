import XCTest
@testable import blindRun

/// 防止 Mock 抛出的 wire code 与 `ErrorCode` 枚举再次漂移。
///
/// 直接扫源码而不是逐条驱动 Mock：新增的 throw 点自动纳入检查，
/// 不需要每加一个失败分支就补一条用例。
final class MockAPIClientErrorCodeTests: XCTestCase {

    func testMockErrorCodesAllResolveToKnownErrorCode() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // blindRunTests
            .deletingLastPathComponent() // repo root
        let sourceURL = repoRoot
            .appendingPathComponent("blindRun/Core/MockAPIClient.swift")

        // 这是一条源码静态守卫：只有在能读到宿主机仓库文件时才有意义。
        // 真机/CI 上测试包里没有 .swift 源文件，此时跳过而不是伪装通过。
        guard let source = try? String(contentsOf: sourceURL, encoding: .utf8) else {
            throw XCTSkip(
                "读不到 \(sourceURL.path)：该守卫仅在宿主机文件系统可用时生效（真机或 CI 上源码不随测试包分发）。"
                + "请在 macOS 上跑同一条用例来校验 MockAPIClient 的 wire code。"
            )
        }
        let regex = try NSRegularExpression(pattern: #"code:\s*"([A-Z_]+)""#)
        let matches = regex.matches(
            in: source,
            range: NSRange(source.startIndex..., in: source)
        )

        XCTAssertFalse(matches.isEmpty, "未在 MockAPIClient.swift 中找到任何 wire code 字面量，正则可能已失效")

        var unknown: Set<String> = []
        for match in matches {
            guard let range = Range(match.range(at: 1), in: source) else { continue }
            let rawValue = String(source[range])
            if ErrorCode(rawValue: rawValue) == nil {
                unknown.insert(rawValue)
            }
        }

        XCTAssertTrue(
            unknown.isEmpty,
            "MockAPIClient 抛出的这些 code 在 ErrorCode 枚举里不存在，客户端会落到未知兜底：\(unknown.sorted())"
        )
    }
}
