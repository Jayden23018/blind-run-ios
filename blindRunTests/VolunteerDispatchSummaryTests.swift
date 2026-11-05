import XCTest
import AMapSearchKit
import AVFAudio
import CoreLocation
import SwiftUI
@testable import blindRun

@MainActor
final class VolunteerDispatchSummaryTests: XCTestCase {
    func testVolunteerLocationReporterSendsAuthorizedCloudLocation() {
        var sentCoordinates: [(Double, Double)] = []
        let didReport = VolunteerLocationReporter.reportIfNeeded(
            currentLocation: CLLocationCoordinate2D(latitude: 39.905, longitude: 116.408),
            locationAuthorized: true,
            shouldReportToCloud: true,
            send: { sentCoordinates.append(($0, $1)) }
        )

        XCTAssertTrue(didReport)
        XCTAssertEqual(sentCoordinates.count, 1)
        let expected = BackendCoordinateNormalizer.wgs84ToGCJ02(
            CLLocationCoordinate2D(latitude: 39.905, longitude: 116.408)
        )
        XCTAssertEqual(sentCoordinates[0].0, expected.latitude, accuracy: 0.000001)
        XCTAssertEqual(sentCoordinates[0].1, expected.longitude, accuracy: 0.000001)
    }

    func testVolunteerLocationReporterSkipsUnauthorizedOrMockLocation() {
        var sendCount = 0
        let coordinate = CLLocationCoordinate2D(latitude: 39.905, longitude: 116.408)

        XCTAssertFalse(VolunteerLocationReporter.reportIfNeeded(
            currentLocation: coordinate,
            locationAuthorized: false,
            shouldReportToCloud: true,
            send: { _, _ in sendCount += 1 }
        ))
        XCTAssertFalse(VolunteerLocationReporter.reportIfNeeded(
            currentLocation: coordinate,
            locationAuthorized: true,
            shouldReportToCloud: false,
            send: { _, _ in sendCount += 1 }
        ))
        XCTAssertFalse(VolunteerLocationReporter.reportIfNeeded(
            currentLocation: nil,
            locationAuthorized: true,
            shouldReportToCloud: true,
            send: { _, _ in sendCount += 1 }
        ))
        XCTAssertEqual(sendCount, 0)
    }

    func testDispatchSummaryExplainsMissingBackendReasons() throws {
        let data = #"{"canDispatch":false,"notAvailableReasons":[],"wantsDispatch":true}"#.data(using: .utf8)!
        let summary = try JSONDecoder().decode(VolunteerDispatchSummaryResponse.self, from: data)

        XCTAssertEqual(summary.reasonText, "服务端未返回不可接单原因")
        XCTAssertEqual(summary.dispatchStatusText, "服务端未返回不可接单原因")
        XCTAssertFalse(summary.canDispatch ?? true)
    }

    /// 后端 `DispatchBlockReason.java` 只有三个取值，且 `VolunteerService.getDispatchSummary`
    /// 只评估这三个独立条件。客户端刻意不再定义后端不会下发的取值。
    func testDispatchSummaryMapsEveryBackendReadinessReason() throws {
        let data = #"{"canDispatch":false,"notAvailableReasons":["DISPATCH_DISABLED","NOT_VERIFIED","OFFLINE"]}"#.data(using: .utf8)!
        let summary = try JSONDecoder().decode(VolunteerDispatchSummaryResponse.self, from: data)

        XCTAssertEqual(
            summary.notAvailableReasons,
            [.dispatchDisabled, .notVerified, .offline]
        )
        XCTAssertEqual(summary.reasonText, "已关闭接单、尚未通过资质认证、当前未在线")
    }

    /// 后端新增原因值时整份响应不能因为严格解码而丢失（曾导致志愿者首页被静默吞成全 nil）。
    func testDispatchSummaryDecodesUnknownReasonInsteadOfFailing() throws {
        let data = #"{"canDispatch":false,"notAvailableReasons":["DISPATCH_DISABLED","SOMETHING_NEW"],"totalCompleted":7}"#.data(using: .utf8)!
        let summary = try JSONDecoder().decode(VolunteerDispatchSummaryResponse.self, from: data)

        XCTAssertEqual(summary.completedCount, 7, "未知原因值不得连累同一份响应里的其他字段")
        XCTAssertEqual(summary.notAvailableReasons, [.dispatchDisabled, .unknown])
        XCTAssertEqual(summary.reasonText, "已关闭接单", "未识别的取值不参与文案拼接")
    }

    /// 全是未识别取值时不能拼出空串。
    func testDispatchSummaryFallsBackWhenEveryReasonIsUnknown() throws {
        let data = #"{"canDispatch":false,"notAvailableReasons":["SOMETHING_NEW"]}"#.data(using: .utf8)!
        let summary = try JSONDecoder().decode(VolunteerDispatchSummaryResponse.self, from: data)

        XCTAssertEqual(summary.reasonText, VolunteerDispatchNotAvailableReason.unknown.displayText)
        XCTAssertFalse(summary.reasonText.isEmpty)
    }
}
