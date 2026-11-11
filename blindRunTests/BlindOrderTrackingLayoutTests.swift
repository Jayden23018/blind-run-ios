import CoreLocation
import XCTest
@testable import blindRun

/// 订单页 v7（#918）地图 + 抽屉的纯逻辑。
///
/// 这一页的错误形态都是静默的：竖线该藏不藏、读屏用户读不到竖线、地图画错东西，屏幕上都不报错。
final class BlindOrderTrackingLayoutTests: XCTestCase {
    private let meet = CLLocationCoordinate2D(latitude: 22.5210, longitude: 113.9300)
    private let volunteer = CLLocationCoordinate2D(latitude: 22.5300, longitude: 113.9400)
    private let me = CLLocationCoordinate2D(latitude: 22.5212, longitude: 113.9302)
    private let size = CGSize(width: 390, height: 360)

    // MARK: - 哪几态走地图

    func testOnlyDepartureThroughCompletionUseTheMapPage() {
        let expected: Set<RunOrderStatus> = [.driverEnRoute, .driverArrived, .inProgress, .completed]
        for status in RunOrderStatus.allCases {
            XCTAssertEqual(status.usesBlindTrackingMap, expected.contains(status), "\(status)")
        }
    }

    // MARK: - 竖线透明度

    func testTimelineIsHiddenWhenCollapsedAndFullWhenExpanded() {
        XCTAssertEqual(BlindOrderTrackingLayout.timelineOpacity(progress: 0, voiceOverRunning: false), 0)
        XCTAssertEqual(BlindOrderTrackingLayout.timelineOpacity(progress: 0.5, voiceOverRunning: false), 0.5, accuracy: 0.0001)
        XCTAssertEqual(BlindOrderTrackingLayout.timelineOpacity(progress: 1, voiceOverRunning: false), 1)
        XCTAssertEqual(BlindOrderTrackingLayout.timelineOpacity(progress: 1.4, voiceOverRunning: false), 1)
        XCTAssertEqual(BlindOrderTrackingLayout.timelineOpacity(progress: -0.3, voiceOverRunning: false), 0)
    }

    /// 读屏用户拖不动抽屉：收起态（进度 0）下竖线也必须完整可读。
    func testTimelineIsAlwaysVisibleWithVoiceOver() {
        XCTAssertEqual(BlindOrderTrackingLayout.timelineOpacity(progress: 0, voiceOverRunning: true), 1)
    }

    func testDrawerProgressFollowsTheFinger() {
        XCTAssertEqual(BlindOrderTrackingLayout.drawerProgress(top: 300, collapsedTop: 300, expandedTop: 100), 0)
        XCTAssertEqual(BlindOrderTrackingLayout.drawerProgress(top: 200, collapsedTop: 300, expandedTop: 100), 0.5, accuracy: 0.0001)
        XCTAssertEqual(BlindOrderTrackingLayout.drawerProgress(top: 100, collapsedTop: 300, expandedTop: 100), 1)
    }

    // MARK: - 最大字号 / 横屏

    func testMapCollapsesAtAccessibilitySizesAndInLandscape() {
        XCTAssertTrue(BlindOrderTrackingLayout.showsMap(isAccessibilitySize: false, isCompactHeight: false))
        XCTAssertFalse(BlindOrderTrackingLayout.showsMap(isAccessibilitySize: true, isCompactHeight: false))
        XCTAssertFalse(BlindOrderTrackingLayout.showsMap(isAccessibilitySize: false, isCompactHeight: true))
    }

    // MARK: - 地图内容

    func testEnRouteShowsMeetPointVolunteerAndMe() throws {
        let content = try XCTUnwrap(BlindOrderTrackingLayout.mapContent(
            status: .driverEnRoute, meetPoint: meet, volunteer: volunteer, me: me, route: [], size: size
        ))
        XCTAssertEqual(Set(content.annotations.map(\.id)), [BlindOrderTrackingLayout.meetPointID, BlindOrderTrackingLayout.volunteerID])
        XCTAssertTrue(content.showsUserLocation)
        XCTAssertTrue(content.polylines.isEmpty)
    }

    /// 陪跑员位置拿不到时只画集合点，不编一个位置。
    func testEnRouteWithoutVolunteerLocationOnlyShowsMeetPoint() throws {
        let content = try XCTUnwrap(BlindOrderTrackingLayout.mapContent(
            status: .driverEnRoute, meetPoint: meet, volunteer: nil, me: nil, route: [], size: size
        ))
        XCTAssertEqual(content.annotations.map(\.id), [BlindOrderTrackingLayout.meetPointID])
        XCTAssertEqual(content.zoomLevel, BlindOrderTrackingLayout.singlePointZoom)
    }

    /// 两人相距约 1.4 公里时，取景要比单点更远（证明按外框算了缩放，而不是停在默认级别）。
    func testFramingZoomsOutToFitBothPeople() throws {
        let content = try XCTUnwrap(BlindOrderTrackingLayout.mapContent(
            status: .driverArrived, meetPoint: meet, volunteer: volunteer, me: nil, route: [], size: size
        ))
        XCTAssertLessThan(content.zoomLevel, BlindOrderTrackingLayout.singlePointZoom)
    }

    func testRunningDrawsRouteInsteadOfMeetPoint() throws {
        let route = [meet, volunteer]
        let content = try XCTUnwrap(BlindOrderTrackingLayout.mapContent(
            status: .inProgress, meetPoint: meet, volunteer: volunteer, me: me, route: route, size: size
        ))
        XCTAssertEqual(content.polylines.map(\.id), [BlindOrderTrackingLayout.routeID])
        XCTAssertFalse(content.annotations.contains { $0.id == BlindOrderTrackingLayout.meetPointID })
        XCTAssertTrue(content.showsUserLocation)
    }

    /// ⑧ 画整条路线 + 起终点，不画「我」，也不画陪跑员当前位置。
    func testCompletedDrawsWholeRouteWithoutLivePeople() throws {
        let route = [meet, volunteer, me]
        let content = try XCTUnwrap(BlindOrderTrackingLayout.mapContent(
            status: .completed, meetPoint: meet, volunteer: volunteer, me: me, route: route, size: size
        ))
        XCTAssertFalse(content.showsUserLocation)
        XCTAssertEqual(content.polylines.map(\.id), [BlindOrderTrackingLayout.routeID])
        XCTAssertFalse(content.annotations.contains { $0.id == BlindOrderTrackingLayout.volunteerID })
        XCTAssertEqual(content.annotations.count, 2)
    }

    func testNoCoordinatesAtAllGivesNoMap() {
        XCTAssertNil(BlindOrderTrackingLayout.mapContent(
            status: .driverEnRoute, meetPoint: nil, volunteer: nil, me: nil, route: [], size: size
        ))
        XCTAssertNil(BlindOrderTrackingLayout.mapContent(
            status: .scheduledConfirmed, meetPoint: meet, volunteer: volunteer, me: me, route: [], size: size
        ))
    }

    // MARK: - 抽屉标题

    func testDrawerTitlesFollowTheMockup() {
        XCTAssertEqual(BlindTrackingDrawerCopy.title(status: .driverEnRoute, name: "陈", meetSpot: nil), "陈正在来找你")
        XCTAssertEqual(BlindTrackingDrawerCopy.title(status: .driverArrived, name: "陈", meetSpot: "南门"), "陈到了，在南门等你")
        XCTAssertEqual(BlindTrackingDrawerCopy.title(status: .driverArrived, name: "陈", meetSpot: " "), "陈到了，在集合点等你")
        XCTAssertEqual(BlindTrackingDrawerCopy.title(status: .inProgress, name: "陈", meetSpot: nil), "和陈一起跑步中")
        XCTAssertEqual(BlindTrackingDrawerCopy.title(status: .completed, name: "陈", meetSpot: nil), "跑完了，和陈一起")
        XCTAssertNil(BlindTrackingDrawerCopy.title(status: .pendingMatch, name: "陈", meetSpot: nil))
    }

    /// 拿不到距离时不编数字（「N 分钟后到」等 backend#943）。
    func testEnRouteSubtitleNeverInventsADistance() {
        XCTAssertEqual(BlindTrackingDrawerCopy.enRouteSubtitle(distanceText: nil, place: nil), "请在集合点原地等")
        XCTAssertEqual(
            BlindTrackingDrawerCopy.enRouteSubtitle(distanceText: "距出发地点约 300 米", place: "南门"),
            "距出发地点约 300 米 · 请在南门原地等"
        )
    }
}
