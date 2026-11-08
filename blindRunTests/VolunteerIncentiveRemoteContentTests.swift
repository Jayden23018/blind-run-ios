import SwiftUI
import UIKit
import XCTest
@testable import blindRun

/// 陪跑员激励与跑步数据几页迁到 `RemoteContent` 之后（#865）：读不到时「可见且可听」。
///
/// 页面整页挂进真窗口验，不是只挂 `RemoteContent`：`.task` 只在视图真的出现在层级里时才跑
/// （记忆 `task-on-empty-view-never-fires`），挂整页才能钉住「页面 → 状态 → 失败块」这一整段。
/// 所有请求都打桩失败，不发真网络请求。
@MainActor
final class VolunteerIncentiveRemoteContentTests: XCTestCase {

    /// 等播报的上限。请求失败 + `FailureAnnouncement.settleDelayNanoseconds`（0.3 秒）通常不到 1 秒，
    /// 真机忙时会更久，所以轮询到念了为止，再多留一截看会不会念第二遍。
    private static let announcementDeadline: TimeInterval = 3
    private static let waitAfterFirstAnnouncement: TimeInterval = 0.5

    func testPointsPageFailureIsSpoken() {
        let service = FakeIncentiveService()
        service.volunteerPointsResult = .failure(URLError(.notConnectedToInternet))
        let appState = AppState(incentive: service, tokenStore: VolunteerIncentiveInMemoryTokenStore())

        let spoken = Self.spokenAfterHosting(VolunteerPointsView(), appState: appState)

        XCTAssertEqual(spoken.filter { $0 == VolunteerPointsCopy.loadFailure }.count, 1, "实际念过：\(spoken)")
    }

    func testPartnersPageFailureIsSpoken() {
        let service = FakeIncentiveService()
        service.volunteerFavoritedByResult = .failure(URLError(.notConnectedToInternet))
        let appState = AppState(incentive: service, tokenStore: VolunteerIncentiveInMemoryTokenStore())

        let spoken = Self.spokenAfterHosting(VolunteerPartnersView(), appState: appState)

        XCTAssertEqual(spoken.filter { $0 == PartnerStreakCopy.loadFailure }.count, 1, "实际念过：\(spoken)")
    }

    func testRatingsRecentSectionFailureIsSpoken() throws {
        let orders = FakeOrderService()
        orders.dispatchSummaryResult = .failure(URLError(.notConnectedToInternet))
        let appState = AppState(orders: orders, tokenStore: VolunteerIncentiveInMemoryTokenStore())

        let spoken = Self.spokenAfterHosting(VolunteerRatingsView(achievements: try Self.achievements()), appState: appState)

        XCTAssertEqual(spoken.filter { $0 == VolunteerRatingsView.recentLoadFailure }.count, 1, "实际念过：\(spoken)")
    }

    func testServiceRecognitionPageFailureIsSpoken() {
        let service = FakeIncentiveService()
        service.volunteerAchievementsResult = .failure(URLError(.notConnectedToInternet))
        // 月度趋势走 `appState.runRecord`，架在这个一律失败的 client 上。
        let appState = AppState(
            apiClient: VolunteerIncentiveFailingAPIClient(),
            incentive: service,
            tokenStore: VolunteerIncentiveInMemoryTokenStore()
        )

        let spoken = Self.spokenAfterHosting(VolunteerServiceRecognitionView(), appState: appState)

        XCTAssertEqual(
            spoken.filter { $0 == VolunteerAchievementsViewModel.loadFailure }.count, 1,
            "实际念过：\(spoken)"
        )
    }

    /// 12 个月全失败才是整页失败，那一句要念出来。
    func testRunDataPageAllMonthsFailedIsSpoken() throws {
        let appState = AppState(
            apiClient: VolunteerIncentiveFailingAPIClient(),
            tokenStore: VolunteerIncentiveInMemoryTokenStore()
        )
        let display = try XCTUnwrap(PartnerStreakDisplay(currentWeeks: 2, bestWeeks: 3))
        let page = VolunteerRunDataView(
            streak: VolunteerRunDataStreak(display: display, partnerName: "李*", lastCreditedWeek: nil),
            achievements: try Self.achievements(),
            favoritedByCount: 1
        )

        let spoken = Self.spokenAfterHosting(page, appState: appState)

        XCTAssertEqual(spoken.filter { $0 == VolunteerRunDataCopy.allFailed }.count, 1, "实际念过：\(spoken)")
    }

    /// 首页「最近陪跑」：失败落到带原文的 `.failed`，由 `RemoteContent` 念出来。
    func testHomeRecentRunFailureBecomesAFailedStateWithTheSpokenCopy() async {
        let appState = AppState(
            apiClient: VolunteerIncentiveFailingAPIClient(),
            tokenStore: VolunteerIncentiveInMemoryTokenStore()
        )
        let model = VolunteerHomeRecentRunModel()
        XCTAssertEqual(model.state, .idle, "前提：还没开始加载")

        await model.load(appState: appState)

        XCTAssertEqual(model.state, .failed(message: VolunteerProfileCopy.recentLoadFailure))
    }

    /// 从评分页、徽章页返回时 `.task` 会再拉一次：这一次失败不许把正在看的成就清掉。
    func testRefreshFailureKeepsTheAchievementsOnScreen() async throws {
        let service = FakeIncentiveService()
        service.volunteerAchievementsResult = .success(
            try JSONDecoder().decode(VolunteerAchievementsResponse.self, from: Data(#"{"totalCompleted":3,"badges":[]}"#.utf8))
        )
        let appState = AppState(incentive: service)
        let viewModel = VolunteerAchievementsViewModel()
        viewModel.configure(appState: appState)
        await viewModel.load()
        XCTAssertEqual(viewModel.achievements?.completedCount, 3, "前提：第一次读到了")

        service.volunteerAchievementsResult = .failure(URLError(.notConnectedToInternet))
        await viewModel.load()

        XCTAssertEqual(viewModel.achievements?.completedCount, 3, "刷新失败把已显示的成就换成了失败块")
    }

    // MARK: - 辅助

    private static func achievements() throws -> VolunteerAchievementsResponse {
        try JSONDecoder().decode(
            VolunteerAchievementsResponse.self,
            from: Data(#"{"totalCompleted":3,"totalServiceMinutes":180,"totalRatings":2,"avgRating":4.5,"badges":[]}"#.utf8)
        )
    }

    /// 挂进真窗口、等请求失败并过了播报的等待时间，返回这段时间念过的话。
    private static func spokenAfterHosting<V: View>(_ view: V, appState: AppState) -> [String] {
        let speech = SpeechService()
        let controller = UIHostingController(rootView: AnyView(
            NavigationStack { view }
                .environmentObject(appState)
                .environmentObject(speech)
        ))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        defer { window.isHidden = true }

        let deadline = Date().addingTimeInterval(announcementDeadline)
        while speech.spokenHistoryForTesting.isEmpty, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        RunLoop.current.run(until: Date().addingTimeInterval(waitAfterFirstAnnouncement))
        return speech.spokenHistoryForTesting
    }
}

/// 每个请求都断网失败。
private final class VolunteerIncentiveFailingAPIClient: APIClientProtocol, @unchecked Sendable {
    func request<T: Decodable>(
        method: HTTPMethod,
        path: String,
        query: [String: String]?,
        body: (any Encodable & Sendable)?,
        requiresAuth: Bool
    ) async throws -> T {
        throw URLError(.notConnectedToInternet)
    }

    func upload<T: Decodable>(
        path: String,
        query: [String: String]?,
        fields: [String: String]?,
        files: [MultipartFile],
        requiresAuth: Bool
    ) async throws -> T {
        throw URLError(.notConnectedToInternet)
    }
}

private final class VolunteerIncentiveInMemoryTokenStore: TokenStoring, @unchecked Sendable {
    private var token: String?
    func save(_ token: String) { self.token = token }
    func read() -> String? { token }
    func delete() { token = nil }
}
