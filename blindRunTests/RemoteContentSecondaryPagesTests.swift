import SwiftUI
import UIKit
import XCTest
@testable import blindRun

/// #864：两端共用的四个二级页迁到 `RemoteContent` 之后，首次加载失败要「可见且可听」。
///
/// 迁之前工单页和已拉黑页的失败只是一行红字，不念 —— VoiceOver 用户只会以为「点了没反应」。
/// 这里挂的是真页面（不是单独的 `RemoteContent`），钉住「页面 → 状态 → 失败视图」整条链没断。
/// 只能挂进真窗口验：`.task` 只在视图真的出现在层级里时才跑（记忆 `task-on-empty-view-never-fires`）。
@MainActor
final class RemoteContentSecondaryPagesTests: XCTestCase {

    /// 比 `FailureAnnouncement.settleDelayNanoseconds`（0.3 秒）长出一截，另留出 `.task` 起跑的时间。
    private static let waitBeyondSettle: TimeInterval = 1.0

    // MARK: - 我的工单

    func testSupportTicketsLoadFailureIsSpoken() {
        let safety = FakeSafetyService()
        safety.myTicketsResult = .failure(URLError(.notConnectedToInternet))
        let appState = AppState(safety: safety)
        let speech = SpeechService()

        let host = Self.host(AnyView(MySupportTicketsView()), appState: appState, speech: speech)
        defer { host.window.isHidden = true }
        Self.spin(Self.waitBeyondSettle)

        XCTAssertTrue(
            speech.spokenHistoryForTesting.contains(SupportTicketCopy.myTicketsFailed),
            "工单读取失败要念出来。实际念过：\(speech.spokenHistoryForTesting)"
        )
    }

    /// 重试：失败 → 加载中 → 已加载。
    func testSupportTicketsRetryAfterFailureLoadsTheList() async {
        let safety = FakeSafetyService()
        safety.myTicketsResult = .failure(URLError(.timedOut))
        let appState = AppState(safety: safety)
        let viewModel = MySupportTicketsViewModel()
        XCTAssertEqual(viewModel.phase, .idle)

        await viewModel.load(appState: appState)
        XCTAssertEqual(viewModel.phase, .failed(message: SupportTicketCopy.myTicketsFailed))

        let ticket = SupportTicketSummary(id: 3, content: "x", status: .open)
        safety.myTicketsResult = .success([ticket])
        await viewModel.retry(appState: appState)
        XCTAssertEqual(viewModel.phase, .loaded([ticket]))
    }

    // MARK: - 已拉黑的人

    func testBlockedUsersLoadFailureIsSpoken() {
        let safety = FakeSafetyService()
        safety.blockedUsersResult = .failure(URLError(.notConnectedToInternet))
        let appState = AppState(safety: safety)
        let speech = SpeechService()

        let host = Self.host(AnyView(BlockedUsersView()), appState: appState, speech: speech)
        defer { host.window.isHidden = true }
        Self.spin(Self.waitBeyondSettle)

        XCTAssertTrue(
            speech.spokenHistoryForTesting.contains(UserSafetyCopy.blockedListFailed),
            "已拉黑列表读取失败要念出来。实际念过：\(speech.spokenHistoryForTesting)"
        )
    }

    // MARK: - 邀请码

    func testInviteCodeLoadFailureIsSpoken() {
        let incentive = FakeIncentiveService()
        incentive.inviteCodeResult = .failure(URLError(.notConnectedToInternet))
        let appState = AppState(incentive: incentive)
        let speech = SpeechService()

        let host = Self.host(AnyView(InviteCodeView()), appState: appState, speech: speech)
        defer { host.window.isHidden = true }
        Self.spin(Self.waitBeyondSettle)

        XCTAssertTrue(
            speech.spokenHistoryForTesting.contains(InviteCodeCopy.loadFailure),
            "邀请码读取失败要念出来。实际念过：\(speech.spokenHistoryForTesting)"
        )
    }

    /// 403 的两种形状都说「先选身份」，不是通用失败文案；非 API 错误用通用失败文案。
    func testInviteCodeFailureMessageNamesTheRoleProblemForBothForbiddenShapes() {
        XCTAssertEqual(InviteCodeView.failureMessage(for: APIError.unknown(statusCode: 403)), InviteCodeCopy.roleRequired)
        XCTAssertEqual(InviteCodeView.failureMessage(for: URLError(.timedOut)), InviteCodeCopy.loadFailure)
        XCTAssertNotEqual(InviteCodeView.failureMessage(for: APIError.unknown(statusCode: 500)), InviteCodeCopy.roleRequired)
    }

    // MARK: - 固定搭档（盲人端）

    func testBlindPartnersFirstLoadFailureIsSpoken() {
        let incentive = FakeIncentiveService()
        incentive.blindFavoriteVolunteersResult = .failure(URLError(.notConnectedToInternet))
        let appState = AppState(incentive: incentive)
        let speech = SpeechService()

        let host = Self.host(AnyView(BlindFavoriteVolunteersView()), appState: appState, speech: speech)
        defer { host.window.isHidden = true }
        Self.spin(Self.waitBeyondSettle)

        XCTAssertTrue(
            speech.spokenHistoryForTesting.contains(PartnerStreakCopy.loadFailure),
            "固定搭档首次读取失败要念出来。实际念过：\(speech.spokenHistoryForTesting)"
        )
    }

    // MARK: - 辅助

    private static func host(
        _ view: AnyView,
        appState: AppState,
        speech: SpeechService
    ) -> (controller: UIHostingController<AnyView>, window: UIWindow) {
        let root = AnyView(NavigationStack { view }.environmentObject(appState).environmentObject(speech))
        let controller = UIHostingController(rootView: root)
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
