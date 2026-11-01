import XCTest
@testable import blindRun

@MainActor
final class BlindHomeBelowCardTests: XCTestCase {
    private let summary = BlindHomeRunSummary(monthTitle: "11月", runs: 3, distanceM: 12_400, spokenText: "11月跑了 3 次。")
    private let place = ResolvedPlace(
        id: "a", title: "家附近操场", addressText: "家附近操场", latitude: 39.9, longitude: 116.4, source: .manual
    )

    private func resolve(
        verified: Bool = true,
        summary: BlindHomeRunSummary? = nil,
        hasRunBefore: Bool = false,
        favorites: Int = 0,
        defaultTitle: String? = nil,
        denied: Bool = false
    ) -> BlindHomeBelowCard {
        BlindHomeBelowCard.resolve(
            isIdentityVerified: verified,
            runSummary: summary,
            hasRunBefore: hasRunBefore,
            favoriteCount: favorites,
            defaultPlaceTitle: defaultTitle,
            isLocationDenied: denied
        )
    }

    func testUnverifiedRunnerOnlySeesIdentityRowEvenWithHistory() {
        let content = resolve(verified: false, summary: summary, hasRunBefore: true)

        XCTAssertTrue(content.showsIdentityRow)
        XCTAssertNil(content.runSummary)
        XCTAssertNil(content.startRowTitle)
    }

    func testVerifiedNewRunnerHasNothingBelowTheCard() {
        XCTAssertTrue(resolve().isEmpty)
    }

    func testReturningRunnerUsesCurrentLocationByDefault() {
        let content = resolve(summary: summary, hasRunBefore: true)

        XCTAssertEqual(content.runSummary, summary)
        XCTAssertEqual(content.startRowTitle, "用当前定位出发")
    }

    func testDefaultFavoriteReplacesCurrentLocation() {
        XCTAssertEqual(resolve(favorites: 1, defaultTitle: "家附近操场").startRowTitle, "从家附近操场出发")
    }

    func testDeniedLocationDoesNotClaimCurrentLocation() {
        XCTAssertEqual(resolve(hasRunBefore: true, denied: true).startRowTitle, "选择出发地点")
    }

    func testZeroRunsProducesNoSummary() {
        XCTAssertNil(BlindHomeRunSummary(monthTitle: "11月", runs: 0, distanceM: nil, spokenText: ""))
    }

    func testSummaryWithoutDistanceOnlyStatesRuns() {
        let summary = BlindHomeRunSummary(monthTitle: "11月", runs: 2, distanceM: nil, spokenText: "")

        XCTAssertEqual(summary?.headline, "2 次")
        XCTAssertEqual(summary?.period, "11月已跑")
    }

    func testDefaultPlaceSurvivesReloadAndFallsBackWhenRemoved() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FavoritePlaceStore(directory: directory)
        store.add(place)
        let saved = try XCTUnwrap(store.places.first)

        store.setDefaultPlace(saved)
        XCTAssertEqual(FavoritePlaceStore(directory: directory).defaultPlace?.title, "家附近操场")

        store.remove(id: saved.id)
        XCTAssertNil(store.defaultPlace)
    }

    func testClearingPlacesAlsoClearsDefaultPlace() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FavoritePlaceStore(directory: directory)
        store.add(place)
        store.setDefaultPlace(try XCTUnwrap(store.places.first))

        FavoritePlaceStore.clearPersistedPlaces(directory: directory, defaults: UserDefaults(suiteName: UUID().uuidString)!)

        XCTAssertNil(FavoritePlaceStore(directory: directory).defaultPlaceID)
    }

    func testRetellingKeepsTheDefaultStartPlace() {
        let viewModel = BlindBookingViewModel()
        viewModel.defaultStartPlace = place
        viewModel.selectPlace(place, announce: false)

        viewModel.resetVoiceFilledSlots()

        XCTAssertEqual(viewModel.selectedStartPlace, place)
    }
}
