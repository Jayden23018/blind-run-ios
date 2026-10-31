import XCTest
@testable import blindRun

/// 跑后记录阶段 7 的读屏文字（OpenSpec `audit-run-record-accessibility`）。
/// 写成扩展而不是塞进类里：`VolunteerRunRecordTests` 已超过类长度上限（SwiftLint 棘轮只许变小）。
extension VolunteerRunRecordTests {

    /// 原型 data-vo：地图描述还要说颜色的意思和最快的一公里；单色路线（没有配速采样）不提颜色。
    func testMapDescriptionSaysWhatTheColoursMeanAndWhichKilometreWasFastest() {
        let samples = [RunPaceSample(distanceM: 100, paceSecPerKm: 380), RunPaceSample(distanceM: 1500, paceSecPerKm: 340)]
        let coloured = VolunteerRunRecordContent(record: record(fastest: 2, paceSamples: samples))
        XCTAssertTrue(coloured.mapDescription.contains("颜色表示配速，蓝色快，黄色慢。"), coloured.mapDescription)
        XCTAssertTrue(coloured.mapDescription.contains("第2公里最快。"), coloured.mapDescription)
        XCTAssertTrue(coloured.mapDescription.hasSuffix("数字见下方。"), coloured.mapDescription)

        let plain = VolunteerRunRecordContent(record: record())
        XCTAssertFalse(plain.mapDescription.contains("颜色"), plain.mapDescription)
        XCTAssertFalse(plain.mapDescription.contains("最快"), plain.mapDescription)
    }

    /// 图上画了休息竖线，读屏摘要也要有「X 公里处休息」（原型 data-vo）。
    func testPaceChartSummaryMentionsEveryRest() {
        let samples = [RunPaceSample(distanceM: 100, paceSecPerKm: 380), RunPaceSample(distanceM: 3000, paceSecPerKm: 340)]
        let stops = [
            RunStop(startedAt: "2026-09-20T08:16:00", durationSec: 100, atDistanceM: 2600, lat: nil, lng: nil, placeName: nil),
            RunStop(startedAt: "2026-09-20T08:30:00", durationSec: 40, atDistanceM: 3000, lat: nil, lng: nil, placeName: nil)
        ]
        let summary = RunPaceChartDescriptor(samples: samples, average: 360, stops: stops).summary
        XCTAssertEqual(summary, "平均每公里6分，最快每公里5分40秒，最慢每公里6分20秒，2.6 公里处休息，3 公里处休息")
        XCTAssertFalse(RunPaceChartDescriptor(samples: samples, average: nil).summary.contains("休息"))
    }

    func testSendButtonHintSaysWhoWillHearItWithoutTheMask() {
        XCTAssertEqual(VolunteerRunRecordContent(record: record()).spokenSendHint, "陈在这条跑步记录里可以听到这句话")
    }

    /// 走查发现：配速图摘要没说最快的是第几公里（原型「第3公里最快」），步频少了「平均」（原型「平均步频每分钟168步」）。
    func testPaceChartSummaryNamesTheFastestKilometreAndCadenceSaysAverage() {
        let samples = [RunPaceSample(distanceM: 100, paceSecPerKm: 380), RunPaceSample(distanceM: 3000, paceSecPerKm: 340)]
        let summary = RunPaceChartDescriptor(samples: samples, average: 360, fastestKilometre: 3).summary
        XCTAssertTrue(summary.contains("第3公里最快"), summary)
        XCTAssertFalse(RunPaceChartDescriptor(samples: samples, average: 360).summary.contains("公里最快"))

        let cadence = VolunteerRunRecordContent(record: record()).primaryStats.first { $0.label == "步频" }
        XCTAssertEqual(cadence?.spoken, "平均步频 每分钟162步")
    }

    /// Audio Graph 与声音路线同方向：跑得越快值越大、音越高（#581）。直接用配速秒数会反过来。
    func testAudioGraphPlotsFasterRunningHigher() {
        let fast = RunPaceChartDescriptor.audioGraphValue(paceSecPerKm: 300)
        let slow = RunPaceChartDescriptor.audioGraphValue(paceSecPerKm: 420)
        XCTAssertGreaterThan(fast, slow, "5 分配速的值要高于 7 分配速")
        XCTAssertEqual(fast, 12, accuracy: 0.001, "取速度：3600 ÷ 300 = 12 公里/小时")
        XCTAssertEqual(RunPaceChartDescriptor.audioGraphValue(paceSecPerKm: 0), 0, "没有配速的点不画成无穷大")
    }

    /// 陪跑员页地图描述与跑者页同一个模板，带「最远跑到起点…」（#580）。
    func testMapDescriptionSaysHowFarFromTheStartTheRunWent() {
        let geometry = RunRouteGeometry(track: RunTrack(
            coordSystem: "GCJ02",
            startedAt: "2026-09-20T08:00:00",
            points: [(0.0, 0), (1_000.0, 1_100), (0.0, 2_200)].enumerated().map {
                RunTrackPoint(t: Double($0.offset), lat: 22.5 + $0.element.0 * 1e-5, lng: 113.9, d: $0.element.1)
            }
        ))
        let description = VolunteerRunRecordContent(record: record(), geometry: geometry).mapDescription
        XCTAssertTrue(description.contains("最远跑到起点"), description)
    }
}

