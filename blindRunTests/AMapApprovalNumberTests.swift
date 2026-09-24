import MAMapKit
import XCTest
@testable import blindRun

/// 地图左下角的审图号（后端 issue #382，《地图审核管理规定》第二十七条）。
@MainActor
final class AMapApprovalNumberTests: XCTestCase {

    func testMapShowsTheSDKApprovalNumberAboveTheLogo() throws {
        try XCTSkipUnless(AMapManager.isConfigured, "高德 key 未配置，没有地图也就没有审图号")
        let host = AMapHostView(mapView: MAMapView(frame: .zero))
        host.frame = CGRect(x: 0, y: 0, width: 390, height: 300)
        host.layoutIfNeeded()

        // 开了自定义样式 SDK 会返回 nil。
        XCTAssertFalse(host.mapView.customMapStyleEnabled)
        let text = try XCTUnwrap(host.approvalNumberLabel.text)
        XCTAssertTrue(text.contains("GS"), "审图号应形如 GS(2024)xxxx号，实际：\(text)")
        XCTAssertFalse(host.approvalNumberLabel.isAccessibilityElement)

        let label = host.approvalNumberLabel.frame
        let logo = host.mapView.logoSize
        let logoTop = host.mapView.logoCenter.y - logo.height / 2
        XCTAssertGreaterThan(label.height, 0)
        XCTAssertLessThanOrEqual(label.maxY, logoTop, "不许压在高德 logo 上")
        XCTAssertLessThan(label.minX, host.bounds.midX, "要在左下角")
        XCTAssertGreaterThan(label.minY, host.bounds.midY, "要在左下角")
        XCTAssertEqual(AMapManager.mapContentApprovalNumber(), text, "「关于」页与地图上的是同一个值")
    }
}
