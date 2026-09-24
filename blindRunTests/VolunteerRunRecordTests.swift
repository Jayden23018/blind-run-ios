//
//  VolunteerRunRecordTests.swift
//  blindRunTests
//
//  陪跑员跑后详情（OpenSpec `add-volunteer-run-record-detail`）：配速着色、路线几何、文案、状态。
//

import CoreLocation
import XCTest
@testable import blindRun

@MainActor
final class VolunteerRunRecordTests: XCTestCase {

    // MARK: - 数字文案

    func testPaceIsWrittenWithPrimesOnScreenAndInWordsForVoiceOver() {
        XCTAssertEqual(RunRecordText.pace(375), "6'15\"")
        XCTAssertEqual(RunRecordText.pace(365), "6'05\"")
        XCTAssertEqual(RunRecordText.spokenPace(375), "每公里6分15秒")
        XCTAssertEqual(RunRecordText.spokenPace(360), "每公里6分", "整分不念「0秒」")
        XCTAssertEqual(RunRecordText.clock(2530), "42:10")
        XCTAssertEqual(RunRecordText.clock(3723), "1:02:03")
        XCTAssertEqual(RunRecordText.spokenDuration(3723), "1小时2分3秒")
        XCTAssertEqual(RunRecordText.spokenDuration(0), "0秒")
    }

    // MARK: - 配速着色

    /// 两端是第 5 / 第 95 百分位，不是最小 / 最大值。306 这个点能分开两种实现：
    /// 百分位口径下它几乎就是「最快」（≈0），按最小值算会得到 0.05。
    func testPaceScaleUsesTheFifthAndNinetyFifthPercentiles() throws {
        let samples = (301...400).map { RunPaceSample(distanceM: $0 * 10, paceSecPerKm: $0) }
        let scale = try XCTUnwrap(RunPaceScale(samples: samples))

        XCTAssertEqual(scale.fastEnd, 305.95, accuracy: 0.001)
        XCTAssertEqual(scale.slowEnd, 395.05, accuracy: 0.001)
        XCTAssertEqual(scale.fraction(306), 0, accuracy: 0.01)
        XCTAssertEqual(scale.fraction(395), 1, accuracy: 0.01)
        XCTAssertEqual(scale.fraction(301), 0, "比第 5 百分位还快的截到 0")
        XCTAssertEqual(scale.fraction(400), 1)
        XCTAssertEqual(scale.fraction(350), 44.05 / 89.1, accuracy: 0.0001)
    }

    func testPaceScaleWithOneRepeatedPaceSitsInTheMiddle() throws {
        let scale = try XCTUnwrap(RunPaceScale(samples: [RunPaceSample(distanceM: 0, paceSecPerKm: 360), RunPaceSample(distanceM: 50, paceSecPerKm: 360)]))
        XCTAssertEqual(scale.fraction(360), 0.5)
        XCTAssertNil(RunPaceScale(samples: []))
    }

    func testPacePaletteRunsFastMidSlowWithoutRedOrGreen() {
        XCTAssertEqual(RunPacePalette.rgb(fraction: 0, isDark: false), AppColors.paceFastTone.light)
        XCTAssertEqual(RunPacePalette.rgb(fraction: 0.5, isDark: false), AppColors.paceMidTone.light)
        XCTAssertEqual(RunPacePalette.rgb(fraction: 1, isDark: false), AppColors.paceSlowTone.light)
        XCTAssertEqual(RunPacePalette.rgb(fraction: 0, isDark: true), AppColors.paceFastTone.dark, "深色要用换过值的那一档")
    }

    // MARK: - 路线几何

    func testRouteDropsConsecutiveDuplicatePointsAndNeedsTwo() throws {
        let geometry = try XCTUnwrap(RunRouteGeometry(track: track([(0, 0), (0, 0), (100, 100), (200, 200)])))
        XCTAssertEqual(geometry.coordinates.count, 3, "SDK：连续重复点必须去掉")
        XCTAssertEqual(geometry.distances, [0, 100, 200])
        XCTAssertNil(RunRouteGeometry(track: track([(0, 0), (0, 0)])))
    }

    /// 阈值 50 米：45 米合并、55 米不合并。
    func testStartAndEndMergeOnlyWithinFiftyMetres() throws {
        let metresPerDegree = 111_195.0
        let near = try XCTUnwrap(RunRouteGeometry(track: track([(0, 0), (500, 500), (45 / metresPerDegree * 1e5, 1000)])))
        let far = try XCTUnwrap(RunRouteGeometry(track: track([(0, 0), (500, 500), (55 / metresPerDegree * 1e5, 1000)])))
        XCTAssertTrue(near.startEndCoincide)
        XCTAssertFalse(far.startEndCoincide)
    }

    func testKilometreMarkersAndSplitSegmentsAreInterpolatedAlongTheRoute() throws {
        // 纬度每步 1e-5 度，累计米数给 0 / 1500 / 3000。
        let geometry = try XCTUnwrap(RunRouteGeometry(track: track([(0, 0), (100, 1500), (200, 3000)])))
        XCTAssertEqual(geometry.kilometreMarkers.map(\.km), [1, 2, 3])
        XCTAssertEqual(geometry.kilometreMarkers[0].coordinate.latitude, 0.001 * 1000 / 1500, accuracy: 1e-12)

        let second = geometry.segment(index: 2)
        XCTAssertEqual(second.first!.latitude, geometry.coordinate(atMetres: 1000).latitude, accuracy: 1e-12)
        XCTAssertEqual(second.last!.latitude, geometry.coordinate(atMetres: 2000).latitude, accuracy: 1e-12)
        XCTAssertEqual(second.count, 3, "两端插值点 + 中间 1500 米那个原始点")
        XCTAssertTrue(geometry.segment(index: 4).isEmpty, "3 公里的路线没有第 4 段")
    }

    /// 索引点只放在颜色档位变化处（SDK：索引点不抽稀，要少放）。
    func testPaceLineOnlyPlacesStyleIndexesWhereTheColourLevelChanges() throws {
        let geometry = try XCTUnwrap(RunRouteGeometry(track: track((0..<6).map { (Double($0 * 10), $0 * 100) })))
        let samples = [300, 300, 300, 420, 420, 420].enumerated().map { RunPaceSample(distanceM: $0.offset * 100, paceSecPerKm: $0.element) }
        let scale = try XCTUnwrap(RunPaceScale(samples: samples))
        let style = geometry.paceStyle(samples: samples, scale: scale)
        XCTAssertEqual(style.indexes, [3])
        XCTAssertEqual(style.fractions, [0, 1])
    }

    // MARK: - 文案

    func testMissingPhoneDataHidesItsCellsInsteadOfShowingZero() {
        let content = VolunteerRunRecordContent(record: record(summary: RunSummary(
            distanceM: 5210, movingSec: 1950, elapsedSec: 2050, restSec: 100,
            avgPaceSecPerKm: 375, steps: nil, avgCadence: nil, elevationGainM: nil
        )))
        XCTAssertEqual(content.primaryStats.map(\.label), ["运动时间", "平均配速"])
        XCTAssertEqual(content.secondaryStats.map(\.label), ["中途休息"])
        XCTAssertEqual(content.distanceText, "5.21")
        XCTAssertEqual(content.primaryStats[1].spoken, "平均配速 每公里6分15秒")
        XCTAssertFalse(content.primaryStats.contains { $0.spoken.contains("'") }, "读屏不念 6'15\" 这种写法")
    }

    func testServiceRowNeverCarriesAConfirmationStatus() {
        let content = VolunteerRunRecordContent(record: record())
        XCTAssertEqual(content.serviceText, "志愿服务 45 分钟")
        XCTAssertEqual(content.serviceRange, "08:00–08:45")
        let everything = [content.serviceText, content.serviceRange, content.title, content.sosLine].compactMap { $0 }.joined()
        XCTAssertFalse(everything.contains("确认"), "D5：不出现「待确认」")
    }

    func testTimelineMarksInferredTimesAndEndsWithTheSOSLine() {
        let content = VolunteerRunRecordContent(record: record(events: [
            RunEvent(type: .runStarted, at: "2026-09-20T08:00:00", inferred: false, durationSec: nil, lat: nil, lng: nil),
            RunEvent(type: .rest, at: "2026-09-20T08:10:00", inferred: true, durationSec: 100, lat: nil, lng: nil)
        ]))
        XCTAssertEqual(content.timeline.map(\.text), ["开始服务", "休息 1:40"])
        XCTAssertEqual(content.timeline.map(\.time), ["08:00", "约08:10"])
        XCTAssertEqual(content.timeline[1].accessibilityLabel, "约08:10，休息1分40秒")
        XCTAssertEqual(content.sosLine, "全程没有触发紧急求助")
        XCTAssertEqual(VolunteerRunRecordContent(record: record(sosTriggered: true)).sosLine, "这一单触发过紧急求助")
    }

    func testSplitsCarryPaceAsTextAndMarkTheFastest() {
        let content = VolunteerRunRecordContent(record: record(splits: [
            RunSplit(index: 1, distanceM: 1000, durationSec: 372, paceSecPerKm: 372, avgCadence: 160),
            RunSplit(index: 2, distanceM: 1000, durationSec: 348, paceSecPerKm: 348, avgCadence: nil),
            RunSplit(index: 3, distanceM: 200, durationSec: 82, paceSecPerKm: 410, avgCadence: nil)
        ], fastest: 2))
        XCTAssertEqual(content.splits.map(\.paceText), ["6'12\"", "5'48\"", "6'50\""])
        XCTAssertEqual(content.splits.map(\.isFastest), [false, true, false])
        XCTAssertEqual(content.splits[1].barFraction, 1)
        XCTAssertEqual(content.splits[0].accessibilityLabel, "第1公里，每公里6分12秒，步频每分钟160步")
        XCTAssertEqual(content.splits[1].accessibilityLabel, "第2公里，每公里5分48秒，最快")
        XCTAssertEqual(content.splits[2].accessibilityLabel, "最后 0.2 公里，每公里6分50秒")
        XCTAssertEqual(content.splits[2].bubbleText, "最后0.20公里 6'50\"")
        XCTAssertTrue(content.showsCadenceColumn)
    }

    func testTitleSpeaksTheNameWithoutMaskStars() {
        let content = VolunteerRunRecordContent(record: record())
        XCTAssertEqual(content.title, "和陈*一起跑")
        XCTAssertEqual(content.spokenTitle, "和陈一起跑")
    }

    /// 真实生产响应（订单 #131，陪跑员视角）：步数/步频/爬升都是 null、触发过求助。
    func testProductionFixtureRendersHonestly() throws {
        let data = try fixture("RunRecordResponse__volunteer-ready")
        let record = try APIPayloadDecoder.decodePayload(RunRecordResponse.self, from: data, decoder: JSONDecoder())
        let geometry = record.track.flatMap(RunRouteGeometry.init(track:))
        let content = VolunteerRunRecordContent(record: record, geometry: geometry)

        XCTAssertEqual(content.primaryStats.map(\.label), ["运动时间", "平均配速"])
        XCTAssertFalse(content.secondaryStats.contains { $0.label == "步数" })
        XCTAssertEqual(content.sosLine, "这一单触发过紧急求助")
        XCTAssertEqual(content.splits.count, record.splits.count)
        XCTAssertEqual(content.timeline.count, record.events.count)
        XCTAssertTrue(content.mapDescription.contains("途中休息2次"))
    }

    // MARK: - 状态

    func testGeneratingIsReReadUntilTheRecordIsReady() async {
        let (viewModel, appState, service) = makeViewModel()
        service.results = [.success(record(status: .generating)), .success(record(status: .generating)), .success(record())]

        await viewModel.loadUntilSettled()

        XCTAssertEqual(service.calls, 3)
        XCTAssertEqual(viewModel.phase, .loaded(record()))
        _ = appState
    }

    func testFailedStatusStopsPollingAndRetryReadsAgain() async {
        let (viewModel, appState, service) = makeViewModel()
        service.results = [.success(record(status: .failed)), .success(record())]

        await viewModel.loadUntilSettled()
        XCTAssertEqual(service.calls, 1, "FAILED 不自动重读，给「重试」")
        await viewModel.retry()
        XCTAssertEqual(service.calls, 2)
        XCTAssertEqual(viewModel.phase, .loaded(record()))
        _ = appState
    }

    func testNetworkErrorBecomesARetryableMessage() async {
        let (viewModel, appState, service) = makeViewModel()
        service.results = [.failure(URLError(.notConnectedToInternet))]

        await viewModel.loadUntilSettled()

        guard case .failed(let message) = viewModel.phase else {
            return XCTFail("应当落到 failed，实际 \(viewModel.phase)")
        }
        XCTAssertTrue(message.contains("重试"))
        _ = appState
    }

    // MARK: - Helpers

    private func makeViewModel() -> (VolunteerRunRecordViewModel, AppState, FakeRecordService) {
        let service = FakeRecordService()
        // AppState 由调用方持有：view model 对它是 weak。
        let appState = AppState(tokenStore: RecordInMemoryTokenStore())
        let viewModel = VolunteerRunRecordViewModel(orderId: 7, retryNanoseconds: 1_000_000)
        viewModel.configure(with: appState, runRecord: service)
        return (viewModel, appState, service)
    }

    /// `(纬度 ×1e-5 度, 累计米数)`，经度恒 0。
    private func track(_ points: [(Double, Int)]) -> RunTrack {
        RunTrack(
            coordSystem: "GCJ02",
            startedAt: "2026-09-20T08:00:00",
            points: points.enumerated().map { RunTrackPoint(t: Double($0.offset), lat: $0.element.0 * 1e-5, lng: 0, d: $0.element.1) }
        )
    }

    private func record(
        status: RunRecordStatus = .ready,
        summary: RunSummary? = RunSummary(distanceM: 3200, movingSec: 1197, elapsedSec: 1297, restSec: 100, avgPaceSecPerKm: 374, steps: 3180, avgCadence: 162, elevationGainM: 12),
        splits: [RunSplit] = [],
        fastest: Int? = nil,
        events: [RunEvent] = [],
        sosTriggered: Bool = false
    ) -> RunRecordResponse {
        RunRecordResponse(
            orderId: 7, status: status, viewerRole: .volunteer, place: "深圳湾公园",
            blindName: "陈*", volunteerName: "林*",
            runStartedAt: "2026-09-20T08:00:00", runEndedAt: "2026-09-20T08:40:00",
            summary: summary, splits: splits, fastestSplitIndex: fastest, paceSamples: [], stops: [],
            events: events, sosTriggered: sosTriggered,
            service: RunService(startedAt: "2026-09-20T08:00:00", completedAt: "2026-09-20T08:45:00", durationMin: 45, volunteerTotalServiceMinutes: 300),
            comparison: nil, messages: [], track: nil
        )
    }

    private func fixture(_ name: String) throws -> Data {
        let bundle = Bundle(for: Self.self)
        let url = bundle.url(forResource: name, withExtension: "json")
            ?? bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
        return try Data(contentsOf: XCTUnwrap(url, "测试包里没有 \(name).json"))
    }
}

/// 按顺序吐结果；吐完再调就抛，用例会红在「多调了一次」上。
private final class FakeRecordService: RunRecordServing, @unchecked Sendable {
    struct Exhausted: Error {}
    var results: [Result<RunRecordResponse, Error>] = []
    private(set) var calls = 0

    func record(orderId: Int64) async throws -> RunRecordResponse {
        defer { calls += 1 }
        guard calls < results.count else { throw Exhausted() }
        return try results[calls].get()
    }

    func monthlyRecords(year: Int, month: Int) async throws -> RunRecordHistoryResponse { throw Exhausted() }
    func postMessage(orderId: Int64, text: String) async throws -> RunRecordMessageResponse { throw Exhausted() }
}

private final class RecordInMemoryTokenStore: TokenStoring, @unchecked Sendable {
    private var token: String?
    func save(_ token: String) { self.token = token }
    func read() -> String? { token }
    func delete() { token = nil }
}
