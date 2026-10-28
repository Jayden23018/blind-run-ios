import SwiftUI
import UIKit
import XCTest
@testable import blindRun

/// 失败页「可见且可听」（#527）：`announcesFailure` 与接了它的 `IncentiveFailureSection`。
///
/// 只能挂进真窗口验：`.task` 只在视图真的出现在层级里时才跑，单测直接调 view model 看不见它
/// （记忆 `task-on-empty-view-never-fires`）。
final class FailureAnnouncementTests: XCTestCase {

    /// 比 `FailureAnnouncement.settleDelayNanoseconds`（0.3 秒）长出一截，给主线程排队留余量。
    private static let waitBeyondSettle: TimeInterval = 0.8

    func testFailureSectionSpeaksItsMessageWhenItAppears() {
        let speech = SpeechService()
        let host = Self.host(AnyView(Self.failureSection("暂时没能读到邀请码。").environmentObject(speech)))
        defer { host.window.isHidden = true }

        Self.spin(Self.waitBeyondSettle)

        XCTAssertEqual(speech.spokenHistoryForTesting.filter { $0 == "暂时没能读到邀请码。" }.count, 1)
    }

    /// 首次加载前闪一帧失败态（志愿者培训页初始 `isLoading = false`）不能误报一句「加载失败」。
    func testFailureThatIsReplacedBeforeItSettlesIsNotSpoken() {
        let speech = SpeechService()
        let host = Self.host(AnyView(Self.failureSection("加载失败").environmentObject(speech)))
        defer { host.window.isHidden = true }

        Self.spin(0.05)
        host.controller.rootView = AnyView(ProgressView().environmentObject(speech))
        Self.spin(Self.waitBeyondSettle)

        XCTAssertFalse(speech.spokenHistoryForTesting.contains("加载失败"), "失败态只闪了一帧就被替换，不该念")
    }

    /// 重试又失败、原因换了：再念一次新的原因。
    func testChangedMessageIsSpokenAgain() {
        let speech = SpeechService()
        let host = Self.host(AnyView(Self.failureSection("网络不太稳定。").environmentObject(speech)))
        defer { host.window.isHidden = true }

        Self.spin(Self.waitBeyondSettle)
        // 先停掉第一句：同档的第二句可能排在它后面，等合成器念完才进历史，断言就取决于念得多快。
        speech.stop()
        host.controller.rootView = AnyView(Self.failureSection("服务器开小差了。").environmentObject(speech))
        Self.spin(Self.waitBeyondSettle)

        XCTAssertTrue(speech.spokenHistoryForTesting.contains("网络不太稳定。"))
        XCTAssertTrue(speech.spokenHistoryForTesting.contains("服务器开小差了。"))
    }

    // MARK: - 辅助

    private static func failureSection(_ message: String) -> IncentiveFailureSection {
        IncentiveFailureSection(message: message, retryTitle: "重试", identifier: "failureAnnouncementTestRetry") {}
    }

    private static func host(_ view: AnyView) -> (controller: UIHostingController<AnyView>, window: UIWindow) {
        let controller = UIHostingController(rootView: view)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        return (controller, window)
    }

    private static func spin(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }
}
