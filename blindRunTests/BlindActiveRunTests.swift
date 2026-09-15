import XCTest
@testable import blindRun

/// 陪跑进行中那一屏（`BlindActiveRunView`）的判据。
///
/// 求助中心的顺序与文案在 `EmergencySOSTests`，这里只管**数字**：
/// 屏幕口径的格式化、每公里播报的触发、以及「定位正常」不许在没有定位时亮起。
final class BlindActiveRunTests: XCTestCase {

    private func stats(
        meters: Double? = nil,
        seconds: Int64? = nil,
        pace: Double? = nil
    ) -> TrackStats {
        TrackStats(distanceMeters: meters, durationSeconds: seconds, avgPaceSecPerKm: pace)
    }

    // MARK: - 显示口径 vs 播报口径

    /// 屏幕要跑表体例，耳朵要口语体例。**两套并存不是重复** ——
    /// `9'06"` 交给读屏会被念成「九撇零六引号」。
    func testDisplayFormattingIsSeparateFromSpokenFormatting() {
        let running = stats(meters: 2_412.7, seconds: 114, pace: 546)

        XCTAssertEqual(running.distanceKilometersText, "2.41")
        XCTAssertEqual(running.durationClockText, "01:54")
        XCTAssertEqual(running.paceClockText, "9'06\"")

        // 播报口径一个字没动 —— 它是 VoiceOver 与 TTS 的来源。
        XCTAssertEqual(running.distanceText, "2.41 公里")
        XCTAssertEqual(running.durationText, "1 分 54 秒")
        XCTAssertEqual(running.averagePaceText, "9 分 6 秒每公里")
    }

    /// 🔴 主数字**不足 1 公里也按公里给**，不切成「米」。
    ///
    /// 这条与播报口径刻意分叉：`distanceText` 在 1 公里以下返回「800 米」是对的（听着自然），
    /// 而屏幕上那个数字一旦从 `800` 跳成 `0.81`，同一个位置的量级在跑动中前后不可比 ——
    /// 它是这一屏唯一的大数字，跳一次就得重新理解一次。
    func testPrimaryNumberNeverSwitchesUnitsMidRun() {
        XCTAssertEqual(stats(meters: 812).distanceKilometersText, "0.81")
        XCTAssertEqual(stats(meters: 812).distanceText, "812 米", "播报口径保持原样，只有屏幕口径统一成公里")
        XCTAssertEqual(stats(meters: 0).distanceKilometersText, "0.00")
    }

    func testClockFormattingCoversHourBoundaryAndMissingValues() {
        XCTAssertEqual(stats(seconds: 0).durationClockText, "00:00")
        XCTAssertEqual(stats(seconds: 59).durationClockText, "00:59")
        XCTAssertEqual(stats(seconds: 3_600).durationClockText, "1:00:00")
        XCTAssertEqual(stats(seconds: 3_753).durationClockText, "1:02:33")

        // 缺值一律 `nil`，由界面渲染成占位符 + 「正在获取」的读屏文案。
        // **不许自己造一个 0** —— 那会把「还没采到轨迹点」显示成「一步没动」。
        XCTAssertNil(stats().distanceKilometersText)
        XCTAssertNil(stats().durationClockText)
        XCTAssertNil(stats().paceClockText)
        // 配速 0 是后端在轨迹点不足时的取值，不是「快到无穷」。
        XCTAssertNil(stats(pace: 0).paceClockText)
    }

    // MARK: - 每公里播报

    /// 首个样本**只定基线不播**。
    ///
    /// 🚩 这条不是性能优化，是防一个真实的静默缺陷：合成器全进程只有一个、`speak` 先
    /// `stopSpeaking`，进页面那一刻状态播报刚开口，紧接着播「已跑 3 公里」会把它切断，
    /// 表现是「状态只念了开头」。
    func testFirstSampleOnlySeedsTheBaseline() {
        var tracker = KilometerMilestoneTracker()
        XCTAssertNil(tracker.milestone(forDistanceMeters: 3_200), "中途进页面不该补播一次里程碑")
        // 基线是 3，所以接下来要到 4 公里才播。
        XCTAssertNil(tracker.milestone(forDistanceMeters: 3_900))
        XCTAssertEqual(tracker.milestone(forDistanceMeters: 4_010), 4)
    }

    /// 跨整公里播一次，**同一公里内不重播**。
    ///
    /// ⚠️ 这条用例的取值是挑过的：`/track` 每 10 秒回一次，如果实现写成「距离变了就播」，
    /// 下面 900 → 950 → 990 这三轮会各播一次，而正确实现一次都不播。
    /// 换成「起点 0、终点 1100」那种取值分辨不出这两种实现。
    func testMilestoneFiresOncePerWholeKilometer() {
        var tracker = KilometerMilestoneTracker()
        XCTAssertNil(tracker.milestone(forDistanceMeters: 120))   // 基线 = 0
        XCTAssertNil(tracker.milestone(forDistanceMeters: 900))
        XCTAssertNil(tracker.milestone(forDistanceMeters: 950))
        XCTAssertNil(tracker.milestone(forDistanceMeters: 990))
        XCTAssertEqual(tracker.milestone(forDistanceMeters: 1_002), 1)
        XCTAssertNil(tracker.milestone(forDistanceMeters: 1_800), "同一公里内不许再播")
        XCTAssertEqual(tracker.milestone(forDistanceMeters: 2_000), 2)
    }

    /// 后端回的距离可能回退（轨迹点被重算、GPS 漂移修正），**回退不播、也不把基线拉回去**。
    /// 否则在 1.99 ↔ 2.01 之间抖一次，「已跑 2 公里」就会被播两遍。
    func testDistanceGoingBackwardsNeverRepeatsAMilestone() {
        var tracker = KilometerMilestoneTracker()
        XCTAssertNil(tracker.milestone(forDistanceMeters: 100))
        XCTAssertEqual(tracker.milestone(forDistanceMeters: 2_010), 2)
        XCTAssertNil(tracker.milestone(forDistanceMeters: 1_990))
        XCTAssertNil(tracker.milestone(forDistanceMeters: 2_030), "抖回来不该再播一次 2 公里")
        XCTAssertEqual(tracker.milestone(forDistanceMeters: 3_000), 3)
    }

    /// 换单必须清基线。不清的话新订单跑到 1 公里时**一声不响** ——
    /// 上一单已经到过 5 公里，而这个缺陷在界面上没有任何症状。
    func testResetClearsTheBaselineSoANewOrderAnnouncesFromZero() {
        var tracker = KilometerMilestoneTracker()
        XCTAssertNil(tracker.milestone(forDistanceMeters: 0))
        XCTAssertEqual(tracker.milestone(forDistanceMeters: 5_100), 5)

        tracker.reset()
        XCTAssertNil(tracker.milestone(forDistanceMeters: 10), "换单后第一个样本仍然只定基线")
        XCTAssertEqual(tracker.milestone(forDistanceMeters: 1_050), 1)
    }

    func testMissingOrNegativeDistanceNeverAnnounces() {
        var tracker = KilometerMilestoneTracker()
        XCTAssertNil(tracker.milestone(forDistanceMeters: nil))
        XCTAssertNil(tracker.milestone(forDistanceMeters: -5))
        // 上面两轮一个基线都没定下，所以下一轮仍然是「首个样本」。
        XCTAssertNil(tracker.milestone(forDistanceMeters: 2_000))
        XCTAssertEqual(tracker.milestone(forDistanceMeters: 3_000), 3)
    }

    // MARK: - 「定位正常」

    /// 🔴 拿不到本机定位时**不许亮「定位正常」**。
    ///
    /// 这一行是安全信息：用户据它判断「播报我的位置」给出的地名可不可信。
    /// 用 `simulateMissingDeviceLocationForTesting()` 而不是裸 `LocationService()` ——
    /// 后者在真机上是竞态，CoreLocation 几毫秒就回调出真实坐标，用例会随机变绿。
    @MainActor
    func testLocationIndicatorStaysOffWithoutADeviceFix() {
        let locationService = LocationService()
        locationService.simulateMissingDeviceLocationForTesting()
        let appState = AppState(persistence: AppStatePersistenceFactory.makeIsolatedTest())
        let viewModel = BlindOrderStatusViewModel()
        viewModel.configure(
            appState: appState,
            speechService: SpeechService(),
            locationService: locationService
        )
        XCTAssertFalse(viewModel.isDeviceLocationFresh)
    }

    /// 没有配置过 `locationService` 时同样判假 —— 失败方向必须是「说没有」而不是「说正常」。
    @MainActor
    func testLocationIndicatorStaysOffBeforeConfigure() {
        XCTAssertFalse(BlindOrderStatusViewModel().isDeviceLocationFresh)
    }
}
