import XCTest
@testable import blindRun

/// 跑步详情「陪跑员」一节（#831）：搭档状态按这一单的陪跑员 id 判，举报带这一单的订单号。
@MainActor
final class RunnerRunFeedbackViewModelTests: XCTestCase, BlindRunTestSupport {
    private static let volunteerId: Int64 = 7
    /// 另一位已是固定搭档的人：用来分辨「按 id 找」和「列表里有人就算是」。
    private static let otherPartner = FavoriteVolunteerResponse(
        volunteerId: 8, volunteerName: "王*", completedRunsTogether: 4,
        favoritedAt: "2026-07-03T09:15:00", streakWeeks: nil, partnerOptedOut: false
    )

    private func makeViewModel(favorites: Result<[FavoriteVolunteerResponse], Error>) -> (RunnerRunFeedbackViewModel, AppState) {
        let service = FakeIncentiveService()
        service.blindFavoriteVolunteersResult = favorites
        service.blindPartnerStreaksResult = .success([])
        let appState = AppState(incentive: service)
        let viewModel = RunnerRunFeedbackViewModel()
        viewModel.configure(appState: appState, speech: nil)
        var order = makeOrder(orderId: 42, status: .completed)
        order.volunteerId = Self.volunteerId
        order.volunteerName = "陈*"
        viewModel.bind(order: order)
        return (viewModel, appState)
    }

    func testVolunteerNotInFavoritesIsNotAPartnerEvenWhenSomeoneElseIs() async {
        let (viewModel, appState) = makeViewModel(favorites: .success([Self.otherPartner]))
        await viewModel.loadPartnerState()
        _ = appState

        XCTAssertEqual(viewModel.partnerStatus, .notPartner)
        XCTAssertEqual(viewModel.personRow?.userId, Self.volunteerId)
        XCTAssertEqual(viewModel.personRow?.isFavorite, false)
    }

    func testVolunteerInFavoritesIsYourPartnerAndOptedOutIsSaidSo() async {
        let mine = FavoriteVolunteerResponse(
            volunteerId: Self.volunteerId, volunteerName: "陈*", completedRunsTogether: 5,
            favoritedAt: "2026-07-03T09:15:00", streakWeeks: nil, partnerOptedOut: false
        )
        var (viewModel, appState) = makeViewModel(favorites: .success([Self.otherPartner, mine]))
        await viewModel.loadPartnerState()
        XCTAssertEqual(viewModel.partnerStatus, .partner)
        XCTAssertEqual(viewModel.partnerStatus.text, "你的固定搭档")
        XCTAssertEqual(viewModel.personRow?.completedRunsTogether, 5, "是搭档时个人页那一行取自固定搭档列表")

        let optedOut = FavoriteVolunteerResponse(
            volunteerId: Self.volunteerId, volunteerName: "陈*", completedRunsTogether: 5,
            favoritedAt: "2026-07-03T09:15:00", streakWeeks: nil, partnerOptedOut: true
        )
        (viewModel, appState) = makeViewModel(favorites: .success([optedOut]))
        await viewModel.loadPartnerState()
        _ = appState
        XCTAssertEqual(viewModel.partnerStatus, .optedOut)
        XCTAssertEqual(viewModel.partnerStatus.text, PartnerStreakCopy.partnerOptedOutSuffix)
    }

    func testUnknownPartnerStateStillLeadsToThePersonPageWithoutFavoriteActions() async {
        let (viewModel, appState) = makeViewModel(favorites: .failure(URLError(.notConnectedToInternet)))
        await viewModel.loadPartnerState()
        _ = appState

        XCTAssertEqual(viewModel.partnerStatus, .unknown)
        XCTAssertNil(viewModel.partnerStatus.text, "查不到时不写状态句")
        XCTAssertEqual(viewModel.personRow?.userId, Self.volunteerId, "查不到也要能点进去举报")
    }

    func testReportFromTheRunRecordCarriesThisOrderId() {
        let row = RunnerRunFeedbackViewModel.bareRow(volunteerId: Self.volunteerId, name: "陈*")

        XCTAssertEqual(BlindPartnerDetailView.safetyTarget(row: row, reportOrderId: 42)?.orderId, 42)
        XCTAssertEqual(BlindPartnerDetailView.safetyTarget(row: row, reportOrderId: 42)?.userId, Self.volunteerId)
        XCTAssertNil(BlindPartnerDetailView.safetyTarget(row: row, reportOrderId: nil)?.orderId, "从固定搭档列表进来没有哪一单")
    }

    func testBlockingFromThePersonPageRemovesTheAddButton() async {
        let (viewModel, appState) = makeViewModel(favorites: .success([]))
        await viewModel.volunteerBlocked()
        _ = appState

        XCTAssertTrue(viewModel.didBlockVolunteer)
        XCTAssertEqual(viewModel.favoriteNotice, UserSafetyCopy.blockSucceeded)
    }
}
