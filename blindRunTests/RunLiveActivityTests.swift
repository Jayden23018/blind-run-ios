import AVFoundation
import XCTest
@testable import blindRun

/// 锁屏实时活动（状态清单 §16 跑者端 / §17 陪跑员端）。
///
/// 这一片的检查有个特殊处境：**锁屏上的真实表现只能人工看**（本仓库 CI 跑不了 XCTest，
/// 而实时活动连真机 XCUITest 也够不着 —— 它不在 App 的进程里渲染）。所以下面这些用例
/// 守的不是「卡片长什么样」，而是三类**会静默漂移**的东西：
///
/// 1. 取值与 `AppColors.Flow` 分家（widget target 编译不到 `AppColors`，见
///    `RunLiveActivityShared.swift` 文件头）；
/// 2. 锁屏播报的 utterance 与 `VoiceService` 的语速策略分家；
/// 3. 「只在 `IN_PROGRESS` 出现」「陪跑员端不显示对方姓名」这两条红线被改掉。
/// 整类 `@available(iOS 16.2, *)`：`ActivityKit` 的类型从 16.2 起才有。
/// 真机在 16.2 以上，所以这些用例真的会跑 —— **看到 `passed=0` 一律当失败查**，
/// 那说明整类被系统跳过了，而不是「没有回归」。
@available(iOS 16.2, *)
@MainActor
final class RunLiveActivityTests: XCTestCase {

    // MARK: - 取值对撞

    /// widget target 编译不到 `AppColors`，所以锁屏卡的颜色是**第二份**取值。
    /// 这条用例是那两份之间唯一的连接 —— 没有它，改 `FlowPalette` 不会有任何东西提示
    /// 锁屏上还留着旧色。
    ///
    /// 取暗色档：实时活动在锁屏上永远是深色呈现，不跟随系统亮暗。
    func testPaletteMatchesTheFlowPaletteDarkTones() {
        XCTAssertEqual(RunLiveActivityPalette.cta, AppColors.Flow.ctaTone.dark)
        XCTAssertEqual(RunLiveActivityPalette.onCTA, AppColors.Flow.onCTATone.dark)
        XCTAssertEqual(RunLiveActivityPalette.cardSurface, AppColors.Flow.surfaceTone.dark)
        XCTAssertEqual(RunLiveActivityPalette.numberInk, AppColors.Flow.primaryTextTone.dark)
        XCTAssertEqual(RunLiveActivityPalette.labelInk, AppColors.Flow.secondaryTextTone.dark)
        XCTAssertEqual(RunLiveActivityPalette.avatarBackground, AppColors.Flow.avatarBackgroundTone.dark)
    }

    /// 锁屏播报也必须跟随用户的 VoiceOver 语速（设计包：「合成语音沿用用户 VoiceOver 的
    /// 声音与语速设置」）。`prefersAssistiveTechnologySettings` 是这条要求的**唯一**载体，
    /// 而它同样是第二份 —— `VoiceService.makeUtterance` 在 app target 里，widget 够不着。
    ///
    /// ⚠️ 阶段 2 那条线正在改 `SpeechService.swift`。它改了语速策略而这里没跟的话，
    /// 表现是「App 里念得飞快、锁屏上念得很慢」，没有任何别的东西会说话。
    func testLockScreenUtteranceKeepsTheSameVoicePolicyAsTheApp() {
        let text = "3.20 公里，用时 21 分 4 秒，配速 6 分 30 秒每公里"
        let lockScreen = RunLiveActivitySpeaker.makeUtterance(text)
        let inApp = VoiceService.makeUtterance(text)

        XCTAssertTrue(lockScreen.prefersAssistiveTechnologySettings)
        XCTAssertEqual(lockScreen.prefersAssistiveTechnologySettings, inApp.prefersAssistiveTechnologySettings)
        XCTAssertEqual(lockScreen.voice?.language, inApp.voice?.language)
        XCTAssertEqual(lockScreen.rate, inApp.rate)
        XCTAssertEqual(lockScreen.pitchMultiplier, inApp.pitchMultiplier)
    }

    /// 两边拉的是同一个 `GET /api/orders/{id}/track`。节流间隔对不上时盲人端会在跑动中
    /// **每 10 秒多发一个请求**，而那是最费电的一段。
    func testLiveActivityRefreshIntervalMatchesTheOrderPageThrottle() {
        XCTAssertEqual(
            LiveEscortSessionCoordinator.liveActivityRefreshInterval,
            BlindOrderStatusViewModel.trackPollingInterval
        )
    }

    // MARK: - 内容

    func testWatchFormatsGoToTheScreenAndSpokenFormsGoToVoiceOver() {
        // 3200 米 / 1264 秒（21 分 4 秒）/ 390 秒每公里（6 分 30 秒）
        let stats = TrackStats(distanceMeters: 3_200, durationSeconds: 1_264, avgPaceSecPerKm: 390)
        let content = RunLiveActivityContentBuilder.contentState(from: stats)

        XCTAssertEqual(content.distanceText, "3.20")
        XCTAssertEqual(content.durationText, "21:04")
        XCTAssertEqual(content.paceText, "6'30\"")

        XCTAssertEqual(content.spokenDistance, "3.20 公里")
        XCTAssertEqual(content.spokenDuration, "21 分 4 秒")
        XCTAssertEqual(content.spokenPace, "6 分 30 秒每公里")
    }

    /// 🔴 数字还没到时**不许显示 0.00**。
    ///
    /// 「跑了 0 公里」和「还没拿到数据」在锁屏上没有第二处能区分，而这张卡在刚进
    /// `IN_PROGRESS` 的头几秒必然处于后者 —— 那正是跑者最可能低头看一眼的时刻。
    func testPendingStatsShowPlaceholdersInsteadOfZero() {
        let content = RunLiveActivityContentBuilder.contentState(from: nil)

        XCTAssertEqual(content.distanceText, "--")
        XCTAssertEqual(content.durationText, "--")
        XCTAssertEqual(content.paceText, "--")
        XCTAssertEqual(content.spokenDistance, "暂无数据")
        XCTAssertNotEqual(content.distanceText, "0.00")
    }

    /// 后端把某一项算不出来时（配速在刚起跑时就是 `nil`）只该那一项变占位，
    /// 另外两项照常显示 —— 整张卡一起退化等于把已有的信息也扔了。
    func testOnlyTheMissingMetricFallsBackToAPlaceholder() {
        let stats = TrackStats(distanceMeters: 120, durationSeconds: 45, avgPaceSecPerKm: nil)
        let content = RunLiveActivityContentBuilder.contentState(from: stats)

        XCTAssertEqual(content.distanceText, "0.12")
        XCTAssertEqual(content.durationText, "00:45")
        XCTAssertEqual(content.paceText, "--")
    }

    func testAnnouncementReadsTheThreeNumbersInTheDesignedOrder() {
        let stats = TrackStats(distanceMeters: 3_200, durationSeconds: 1_264, avgPaceSecPerKm: 390)
        let content = RunLiveActivityContentBuilder.contentState(from: stats)

        let sentence = RunLiveActivityCopy.announcement(
            distance: content.spokenDistance,
            duration: content.spokenDuration,
            pace: content.spokenPace
        )

        XCTAssertEqual(sentence, "3.20 公里，用时 21 分 4 秒，配速 6 分 30 秒每公里")
    }

    // MARK: - 什么时候该有这张卡

    /// 🔴 **锁屏卡只在 `IN_PROGRESS` 出现。** 穷举全部订单状态 ——
    /// 后端加状态时编译器不会提醒这里，只有逐个走一遍才挡得住「约好了就先挂一张卡上去」。
    func testCardExistsOnlyWhileTheRunIsInProgress() {
        for status in RunOrderStatus.allCases {
            let plan = LiveEscortSessionCoordinator.liveActivityPlan(
                orderID: 42,
                status: status,
                role: .blind,
                partnerName: "张伟"
            )
            if status == .inProgress {
                XCTAssertNotNil(plan, "\(status) 应该有锁屏卡")
            } else {
                XCTAssertNil(plan, "\(status) 不该有锁屏卡")
            }
        }
    }

    /// 🔴 **陪跑员端那张卡不显示对方姓名**（项目负责人 2026-09-16 决定）。
    ///
    /// 这条同时是本阶段能零接触 `blindRun/Volunteer/**` 的前提：卡片不需要身份信息，
    /// 也就不需要从陪跑员的 view model 里取任何东西。有人把姓名加回去时这里会红，
    /// 提醒他那不只是「多显示一行」。
    func testVolunteerCardNeverCarriesTheCounterpartName() {
        let plan = LiveEscortSessionCoordinator.liveActivityPlan(
            orderID: 42,
            status: .inProgress,
            role: .volunteer,
            partnerName: "李明"
        )

        XCTAssertEqual(plan?.side, .volunteer)
        XCTAssertNil(plan?.partnerName)
    }

    func testRunnerCardCarriesThePartnerNameForTheHeadline() {
        let plan = LiveEscortSessionCoordinator.liveActivityPlan(
            orderID: 42,
            status: .inProgress,
            role: .blind,
            partnerName: "张伟"
        )

        XCTAssertEqual(plan?.side, .runner)
        XCTAssertEqual(plan?.partnerName, "张伟")
        XCTAssertEqual(RunLiveActivityCopy.partnerHeadline("张伟"), "陪跑中 · 张伟")
    }

    /// 还没选角色时不该有卡。`unset` 是 `UserRole` 的真实取值，不是理论分支。
    func testNoCardBeforeARoleIsChosen() {
        XCTAssertNil(
            LiveEscortSessionCoordinator.liveActivityPlan(
                orderID: 42,
                status: .inProgress,
                role: .unset,
                partnerName: "张伟"
            )
        )
        XCTAssertNil(
            LiveEscortSessionCoordinator.liveActivityPlan(
                orderID: 42,
                status: .inProgress,
                role: nil,
                partnerName: "张伟"
            )
        )
    }
}
