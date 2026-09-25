import XCTest
@testable import blindRun

/// 视障跑者跑后详情（OpenSpec `add-runner-run-record-detail`）：文案、讲述、声音路线的时间线与合成。
/// 听感（音高、左右、与 VoiceOver 的交替）这里验不了，只能真机人耳验。
@MainActor
final class RunnerRunRecordTests: XCTestCase {

    // MARK: - 头部与讲述

    func testHeaderIsOneSentenceWithComparison() {
        let content = RunnerRunRecordContent(record: record())
        XCTAssertEqual(
            content.headerLabel,
            "9月20日星期日早上，和林在深圳湾公园跑步。5.21 公里，运动时间32分34秒，平均每公里6分15秒，比上次多跑 0.41 公里。"
        )
        XCTAssertEqual(content.dateLine, "9月20日 周日早上")
        XCTAssertEqual(content.title, "和林*在深圳湾公园", "屏幕上照原样显示掩码")
        XCTAssertEqual(content.facts, ["用时 32分34秒", "每公里 6分15秒", "比上次多跑 0.41 公里"])
    }

    func testNarrationCoversTheRunInHandoffOrder() {
        let content = RunnerRunRecordContent(record: record())
        XCTAssertEqual(
            content.narration,
            "9月20日星期日，早上6点42分，你和林在深圳湾公园跑了5.21公里，运动时间32分34秒，平均每公里6分15秒，比上一次多跑了0.41公里。"
                + "最慢的是第1公里，用了6分38秒。第3公里你跑得最快，5分58秒。"
                + "跑到2.6公里处，你们停下来休息了1分40秒。"
                + "全程步频很稳，平均每分钟168步。"
                + "林给你留了一句话：今天节奏很稳。"
        )
    }

    /// 阈值 5：各段步频差 5 算稳、差 6 不算。两个取值正好落在阈值两侧。
    func testSteadyCadenceThresholdSitsAtFiveStepsPerMinute() throws {
        var splits = Self.splits
        splits[0] = RunSplit(index: 1, distanceM: 1000, durationSec: 398, paceSecPerKm: 398, avgCadence: 165)
        let narration = try XCTUnwrap(RunnerRunRecordContent(record: record(splits: splits)).narration)
        XCTAssertTrue(narration.contains("平均步频每分钟168步。"), narration)
        XCTAssertFalse(narration.contains("全程步频很稳"), narration)
    }

    func testComparisonCanBeShorterAndIsDroppedWhenAbsent() {
        let shorter = RunnerRunRecordContent(record: record(comparison: RunComparison(previousOrderId: 1, previousDistanceM: 5_500, deltaDistanceM: -290)))
        XCTAssertTrue(shorter.headerLabel.contains("比上次少跑 0.29 公里"), shorter.headerLabel)
        let none = RunnerRunRecordContent(record: record(comparison: nil))
        XCTAssertFalse(none.headerLabel.contains("上次"))
        XCTAssertFalse(none.narration?.contains("上一次") ?? true)
    }

    func testMissingPhoneDataDropsClausesInsteadOfSayingZero() throws {
        let summary = RunSummary(distanceM: 5210, movingSec: 1954, elapsedSec: 2054, restSec: 100, avgPaceSecPerKm: 375, steps: nil, avgCadence: nil, elevationGainM: nil)
        let splits = Self.splits.map { RunSplit(index: $0.index, distanceM: $0.distanceM, durationSec: $0.durationSec, paceSecPerKm: $0.paceSecPerKm, avgCadence: nil) }
        let content = RunnerRunRecordContent(record: record(summary: summary, splits: splits))
        let narration = try XCTUnwrap(content.narration)
        XCTAssertFalse(narration.contains("步频"), narration)
        XCTAssertEqual(content.moreData.map(\.label), ["中途休息", "总时长（含休息）", "林*累计陪跑"])
        XCTAssertEqual(content.splits[0].accessibilityLabel, "第1公里，6分38秒。")
    }

    /// HANDOFF 5.3：跑者页屏幕和读屏都不许出现 `6'15"`。用真实生产响应（#131）和手写样例各过一遍。
    func testNoPrimeNotationAnywhereOnTheRunnerPage() throws {
        let data = try fixture("RunRecordResponse__blind-ready")
        let production = try APIPayloadDecoder.decodePayload(RunRecordResponse.self, from: data, decoder: JSONDecoder())
        for record in [record(), production] {
            let content = RunnerRunRecordContent(record: record, geometry: record.track.flatMap(RunRouteGeometry.init(track:)))
            let texts = [content.headerLabel, content.narration ?? "", content.routeDescription ?? "", content.title]
                + content.facts
                + content.splits.flatMap { [$0.title, $0.value, $0.detail ?? "", $0.accessibilityLabel] }
                + content.moreData.flatMap { [$0.label, $0.value, $0.accessibilityLabel] }
            for text in texts {
                XCTAssertFalse(text.contains("'") || text.contains("\""), "出现了撇号写法：\(text)")
            }
        }
    }

    func testSplitRowsReadAsOneSentence() {
        let content = RunnerRunRecordContent(record: record())
        XCTAssertEqual(content.splits[2].accessibilityLabel, "第3公里，5分58秒，本次最快，步频每分钟171步。")
        XCTAssertTrue(content.splits[2].isFastest)
        XCTAssertEqual(content.splits[5].accessibilityLabel, "最后 0.21 公里，用时1分16秒，折合每公里6分2秒，步频每分钟170步。")
        XCTAssertEqual(content.splits[5].value, "1分16秒")
    }

    /// D6：跑者看得到陪跑员累计服务时长；陪跑员注销（null）时整行不出现。
    func testVolunteerCumulativeServiceTimeRow() {
        let row = RunnerRunRecordContent(record: record()).moreData.last
        XCTAssertEqual(row?.label, "林*累计陪跑")
        XCTAssertEqual(row?.accessibilityLabel, "林累计陪跑，21 小时")
        let deleted = RunnerRunRecordContent(record: record(totalServiceMinutes: nil))
        XCTAssertFalse(deleted.moreData.contains { $0.label.contains("累计陪跑") })
    }

    func testGeneratingRecordOffersNoNarration() {
        XCTAssertNil(RunnerRunRecordContent(record: record(status: .generating, summary: nil)).narration)
        XCTAssertNil(RunnerRunRecordContent(record: record(status: .failed, summary: nil)).narration)
    }

    func testRouteDescriptionNamesTheFarthestDirection() throws {
        // 往正东跑 1 公里再折回。
        let geometry = try XCTUnwrap(RunRouteGeometry(track: eastAndBack()))
        XCTAssertEqual(
            RunnerRunRecordContent.routeDescription(geometry, stops: 1),
            "全程 2 公里，起点和终点在同一处，最远跑到起点正东方向约 1 公里处，途中休息1次。"
        )
    }

    // MARK: - 声音路线

    func testSonificationRunsAtFortyFiveHundredthsPerHundredMetresWithKilometreBeeps() throws {
        let stops = [RunStop(startedAt: "2026-09-20T07:00:00", durationSec: 100, atDistanceM: 2_600, lat: nil, lng: nil, placeName: nil)]
        let sound = try XCTUnwrap(RunRouteSonification(samples: samples(upTo: 5_210), stops: stops, totalMetres: 5_210, geometry: nil))
        XCTAssertEqual(sound.bars.count, 53)
        XCTAssertEqual(sound.barDuration, 0.45, accuracy: 1e-9)
        XCTAssertEqual(sound.duration, 53 * 0.45 + 1.1 + 1.1, accuracy: 1e-9)
        // 第 1…5 公里各响 1…5 声。
        XCTAssertEqual(sound.beeps.filter { $0.hz == 1_250 }.count, 1 + 2 + 3 + 4 + 5)
        XCTAssertEqual(sound.beeps.filter { $0.hz == 190 }.count, 1)
        XCTAssertEqual(sound.caption(at: 0), "第 1 公里")
        XCTAssertEqual(sound.caption(at: sound.bars[10].start), "第 2 公里")
        XCTAssertEqual(sound.caption(at: try XCTUnwrap(sound.rests.first).lowerBound + 0.5), "休息")
    }

    /// 封顶 45 秒：9.5 公里还放得下 0.45 秒一格，10 公里就要压速率。两个距离落在阈值两侧。
    func testLongRunsAreCappedAtFortyFiveSeconds() throws {
        let under = try XCTUnwrap(RunRouteSonification(samples: samples(upTo: 9_500), stops: [], totalMetres: 9_500, geometry: nil))
        XCTAssertEqual(under.barDuration, 0.45, accuracy: 1e-9)
        let over = try XCTUnwrap(RunRouteSonification(samples: samples(upTo: 10_000), stops: [], totalMetres: 10_000, geometry: nil))
        XCTAssertLessThan(over.barDuration, 0.45)
        XCTAssertEqual(over.duration, 45, accuracy: 1e-9)
        let half = try XCTUnwrap(RunRouteSonification(samples: samples(upTo: 21_100), stops: [], totalMetres: 21_100, geometry: nil))
        XCTAssertEqual(half.duration, 45, accuracy: 1e-9)
    }

    func testPitchRisesWithSpeedAndPanFollowsLongitude() throws {
        // 前半程快（300 秒/公里），后半程慢（420）；路线从西往东再回来。
        let paces = stride(from: 0, through: 2_000, by: 50).map { RunPaceSample(distanceM: $0, paceSecPerKm: $0 < 1_000 ? 300 : 420) }
        let sound = try XCTUnwrap(RunRouteSonification(
            samples: paces, stops: [], totalMetres: 2_000, geometry: RunRouteGeometry(track: eastAndBack())
        ))
        let first = try XCTUnwrap(sound.bars.first), middle = sound.bars[9], last = try XCTUnwrap(sound.bars.last)
        XCTAssertEqual(first.hz, RunRouteSonification.highestHz, accuracy: 0.5, "最快一档是最高音")
        XCTAssertEqual(last.hz, RunRouteSonification.lowestHz, accuracy: 0.5, "最慢一档是最低音")
        XCTAssertLessThan(first.pan, -0.8, "起点在最西边，声音在左耳")
        XCTAssertGreaterThan(middle.pan, 0.8, "折返点在最东边，声音在右耳")
    }

    func testNoPaceSamplesHidesTheSoundRoute() {
        XCTAssertNil(RunRouteSonification(samples: [], stops: [], totalMetres: 5_000, geometry: nil))
    }

    func testRenderedWAVIsStereoAndAsLongAsTheTimeline() throws {
        let sound = try XCTUnwrap(RunRouteSonification(samples: samples(upTo: 500), stops: [], totalMetres: 500, geometry: nil))
        let wav = sound.renderWAV()
        func u16(_ offset: Int) -> Int { Int(wav[offset]) | Int(wav[offset + 1]) << 8 }
        func u32(_ offset: Int) -> Int { u16(offset) | u16(offset + 2) << 16 }
        XCTAssertEqual(u16(22), 2, "双声道")
        XCTAssertEqual(u32(24), RunRouteSonification.sampleRate)
        XCTAssertEqual(u32(40), Int(sound.duration * Double(RunRouteSonification.sampleRate)) * 4)
        XCTAssertTrue(wav.dropFirst(44).contains { $0 != 0 }, "不能是一段静音")
    }

    // MARK: - 播放控制

    /// 焦点移到别处就暂停；落在正在响的那个控件上不暂停；再点继续；离开页面停。
    /// ⚠️ 真机上会念出一个字：这是合成器本身，不是替身。
    func testNarrationPausesWhenVoiceOverFocusMovesAwayAndResumes() {
        let audio = RunRecordAudioController()
        audio.activeControlIdentifier = "listen"
        audio.toggleSpeech("一")
        XCTAssertEqual(audio.state, .playing(.narration))
        audio.focusMoved(to: "listen")
        XCTAssertEqual(audio.state, .playing(.narration), "焦点还在按钮上，不该暂停")
        audio.focusMoved(to: "runnerRunRecordSplit-1")
        XCTAssertEqual(audio.state, .paused(.narration))
        audio.toggleSpeech("一")
        XCTAssertEqual(audio.state, .playing(.narration))
        audio.stop()
        XCTAssertEqual(audio.state, .idle)
    }

    // MARK: - 留言（阶段 6）

    /// 只收陪跑员的；全部按先后念；没带句末标点的补一个句号，免得两条粘成一句。
    func testMessagesSectionReadsEveryVolunteerMessageInOrder() throws {
        let messages = [
            RunRecordMessageResponse(id: 1, fromRole: .volunteer, type: .text, text: "今天节奏很稳。", createdAt: "2026-09-20T08:01:00"),
            RunRecordMessageResponse(id: 2, fromRole: .blind, type: .text, text: "谢谢", createdAt: "2026-09-20T08:02:00"),
            RunRecordMessageResponse(id: 3, fromRole: .volunteer, type: .text, text: "下周六见", createdAt: "2026-09-20T08:03:00")
        ]
        let section = try XCTUnwrap(RunnerRunRecordContent(record: record(messages: messages)).messages)
        XCTAssertEqual(section.title, "林*的留言")
        XCTAssertEqual(section.spokenTitle, "林的留言", "读屏不念星号")
        XCTAssertEqual(section.texts, ["今天节奏很稳。", "下周六见"])
        XCTAssertEqual(section.readAloud, "林的留言：今天节奏很稳。下周六见。")
    }

    func testNoVolunteerMessageMeansNoSection() {
        let onlyMine = [RunRecordMessageResponse(id: 1, fromRole: .blind, type: .text, text: "谢谢", createdAt: "2026-09-20T08:02:00")]
        XCTAssertNil(RunnerRunRecordContent(record: record(messages: onlyMine)).messages)
        XCTAssertNil(RunnerRunRecordContent(record: record(messages: [])).messages)
    }

    /// 「朗读留言」与讲述共用一个播放者：开始它就停掉讲述；焦点移开同样暂停。
    /// ⚠️ 真机上会念出一两个字：这是合成器本身，不是替身。
    func testReadingMessagesStopsTheNarrationAndPausesOnFocusMove() {
        let audio = RunRecordAudioController()
        audio.activeControlIdentifier = "listen"
        audio.toggleSpeech("一")
        XCTAssertEqual(audio.state, .playing(.narration))
        audio.activeControlIdentifier = RunnerRunRecordView.readMessagesID
        audio.toggleSpeech("二", as: .message)
        XCTAssertEqual(audio.state, .playing(.message), "讲述让位给朗读留言")
        audio.focusMoved(to: "runnerRunRecordListen")
        XCTAssertEqual(audio.state, .paused(.message))
        audio.toggleSpeech("一")
        XCTAssertEqual(audio.state, .playing(.narration), "暂停着的留言不会被讲述「继续」")
        audio.stop()
        XCTAssertEqual(audio.state, .idle)
    }

    // MARK: - Helpers

    nonisolated static let splits: [RunSplit] = [
        RunSplit(index: 1, distanceM: 1000, durationSec: 398, paceSecPerKm: 398, avgCadence: 166),
        RunSplit(index: 2, distanceM: 1000, durationSec: 372, paceSecPerKm: 372, avgCadence: 167),
        RunSplit(index: 3, distanceM: 1000, durationSec: 358, paceSecPerKm: 358, avgCadence: 171),
        RunSplit(index: 4, distanceM: 1000, durationSec: 381, paceSecPerKm: 381, avgCadence: 169),
        RunSplit(index: 5, distanceM: 1000, durationSec: 369, paceSecPerKm: 369, avgCadence: 168),
        RunSplit(index: 6, distanceM: 210, durationSec: 76, paceSecPerKm: 362, avgCadence: 170)
    ]

    private func record(
        status: RunRecordStatus = .ready,
        summary: RunSummary? = RunSummary(distanceM: 5210, movingSec: 1954, elapsedSec: 2054, restSec: 100, avgPaceSecPerKm: 375, steps: 5474, avgCadence: 168, elevationGainM: 6),
        splits: [RunSplit] = RunnerRunRecordTests.splits,
        comparison: RunComparison? = RunComparison(previousOrderId: 6, previousDistanceM: 4_800, deltaDistanceM: 410),
        totalServiceMinutes: Int64? = 1_260,
        messages: [RunRecordMessageResponse] = [
            RunRecordMessageResponse(id: 1, fromRole: .blind, type: .text, text: "谢谢", createdAt: "2026-09-20T08:00:00"),
            RunRecordMessageResponse(id: 2, fromRole: .volunteer, type: .text, text: "今天节奏很稳。", createdAt: "2026-09-20T08:01:00")
        ]
    ) -> RunRecordResponse {
        RunRecordResponse(
            orderId: 7, status: status, viewerRole: .blind, place: "深圳湾公园",
            blindName: "陈*", volunteerName: "林*",
            runStartedAt: "2026-09-20T06:42:00", runEndedAt: "2026-09-20T07:16:00",
            summary: summary, splits: splits, fastestSplitIndex: 3, paceSamples: samples(upTo: 5_210),
            stops: [RunStop(startedAt: "2026-09-20T06:58:00", durationSec: 100, atDistanceM: 2_600, lat: nil, lng: nil, placeName: nil)],
            events: [], sosTriggered: false,
            service: RunService(startedAt: "2026-09-20T06:42:00", completedAt: "2026-09-20T07:20:00", durationMin: 38, volunteerTotalServiceMinutes: totalServiceMinutes),
            comparison: comparison,
            messages: messages,
            track: nil
        )
    }

    private func samples(upTo metres: Int) -> [RunPaceSample] {
        stride(from: 0, through: metres, by: 50).map { RunPaceSample(distanceM: $0, paceSecPerKm: 360 + ($0 / 50) % 7 * 5) }
    }

    /// 纬度 22.5 上往正东 1 公里再折回，每 100 米一点。
    private func eastAndBack() -> RunTrack {
        let degreesPerMetre = 1 / (111_000 * cos(22.5 * .pi / 180))
        let points = (0...20).map { step -> RunTrackPoint in
            let out = step <= 10 ? step : 20 - step
            return RunTrackPoint(t: Double(step) * 36, lat: 22.5, lng: 113.9 + Double(out * 100) * degreesPerMetre, d: step * 100)
        }
        return RunTrack(coordSystem: "GCJ02", startedAt: "2026-09-20T06:42:00", points: points)
    }

    private func fixture(_ name: String) throws -> Data {
        let bundle = Bundle(for: Self.self)
        let url = bundle.url(forResource: name, withExtension: "json")
            ?? bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
        return try Data(contentsOf: XCTUnwrap(url, "测试包里没有 \(name).json"))
    }
}
