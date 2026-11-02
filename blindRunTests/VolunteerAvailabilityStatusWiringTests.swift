import XCTest
@testable import blindRun

final class VolunteerAvailabilityStatusWiringTests: XCTestCase {
    /// 审计 V-6：开关开着不等于在接单。判定读摘要，不读 `isAvailable`。
    @MainActor
    func testAvailabilityStatusFollowsTheSummaryNotTheSwitch() throws {
        let viewModel = VolunteerHomeViewModel()
        func summary(_ json: String) throws -> VolunteerDispatchSummaryResponse {
            try JSONDecoder().decode(VolunteerDispatchSummaryResponse.self, from: Data(json.utf8))
        }

        viewModel.isAvailable = true
        XCTAssertEqual(viewModel.availabilityStatus, .confirming, "摘要没到时不能往好处猜")

        viewModel.apply(summary: try summary(
            #"{"canDispatch":false,"notAvailableReasons":["TRAINING_INCOMPLETE"],"wantsDispatch":true}"#
        ))
        XCTAssertEqual(viewModel.availabilityStatus, .blockedByTraining)

        viewModel.apply(summary: try summary(
            #"{"canDispatch":true,"notAvailableReasons":[],"wantsDispatch":true}"#
        ))
        XCTAssertEqual(viewModel.availabilityStatus, .accepting)
    }
}
