import XCTest
@testable import blindRun

/// 警示档（`.alert`）的两条特殊规则与陪跑员跑步中的取消确认（#653）。
///
/// 放在单独的文件：`AnnouncementQueueTests.swift` 已到棘轮上限。
@MainActor
final class AlertAnnouncementPriorityTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() {
        super.setUp()
        // 接管提示音与震动：`.alert` 档每句都会响一次。
        AnnouncementCue.observerForTesting = { _ in }
    }

    override func tearDown() {
        AnnouncementCue.observerForTesting = nil
        super.tearDown()
    }

    private func announcement(_ priority: AnnouncementPriority, text: String = "文本") -> PendingAnnouncement {
        PendingAnnouncement(text: text, priority: priority, enqueuedAt: now)
    }

    /// 🔴 **警示档同档排队：后到的不切断正在念的那句。**
    ///
    /// 这一档存在的理由就是「听全」。用 `.alert` 对 `.alert` 取值：打断型实现在这里返回 `.speakNow`。
    func testAlertDoesNotInterruptAnotherAlert() {
        var queue = AnnouncementQueue()
        XCTAssertEqual(
            queue.submit(announcement(.alert, text: "第二句"), speaking: .alert, isCallActive: false),
            .enqueued
        )
    }

    /// 警示档只抢低于自己的档位，紧急求助照样压得住它。
    func testAlertPreemptsTheDefaultPriorityButWaitsForAnEmergency() {
        var queue = AnnouncementQueue()
        XCTAssertEqual(queue.submit(announcement(.alert), speaking: .counterpartAction, isCallActive: false), .speakNow)
        XCTAssertEqual(queue.submit(announcement(.alert), speaking: .emergency, isCallActive: false), .enqueued)
        XCTAssertEqual(
            queue.submit(announcement(.emergency), speaking: .alert, isCallActive: false),
            .speakNow,
            "求助不能排在警示后面"
        )
    }

    /// 排着的警示不互相替换，并且先到先播。替换的话，一串警示只剩最后一条被听到。
    func testQueuedAlertsPlayInArrivalOrder() {
        var queue = AnnouncementQueue()
        _ = queue.submit(announcement(.alert, text: "第一句"), speaking: .emergency, isCallActive: false)
        _ = queue.submit(announcement(.alert, text: "第二句"), speaking: .emergency, isCallActive: false)
        _ = queue.submit(announcement(.alert, text: "第三句"), speaking: .emergency, isCallActive: false)

        XCTAssertEqual(queue.next(now: now, isCallActive: false)?.text, "第一句")
        XCTAssertEqual(queue.next(now: now, isCallActive: false)?.text, "第二句")
        XCTAssertEqual(queue.next(now: now, isCallActive: false)?.text, "第三句")
        XCTAssertNil(queue.next(now: now, isCallActive: false))
    }

    /// 同一句重复投递只念一遍。
    func testIdenticalQueuedAlertsCollapse() {
        var queue = AnnouncementQueue()
        _ = queue.submit(announcement(.alert, text: "同一句"), speaking: .emergency, isCallActive: false)
        _ = queue.submit(announcement(.alert, text: "同一句"), speaking: .emergency, isCallActive: false)
        XCTAssertEqual(queue.pending.count, 1)
    }

    /// 🔴 #653 的现场：警示念到一半，轮询送来通用状态句。
    ///
    /// 断言整个数组，理由见记忆 `later-speak-silently-cuts-the-earlier-one`：
    /// 切断型实现的最后一句也可能是对的，只看 `lastSpokenText` 抓不到。
    func testPollingSentenceWaitsForTheAlertToFinish() {
        let service = VoiceService()
        service.isCallActive = { false }
        service.resetSpokenHistoryForTesting()

        service.speak("现在只有您一个人", priority: .alert)
        service.speak("正在确认陪跑员状态，请稍候。")
        service.speak("另一条安全提醒", priority: .alert)

        XCTAssertEqual(service.spokenHistoryForTesting, ["现在只有您一个人"], "后到的两句都不能切断正在念的警示")

        // 警示那句念完（用兜底时钟代替代理回调），排着的警示先接上。
        service.clearStaleUtteranceIfNeeded(now: .distantFuture)
        XCTAssertEqual(service.spokenHistoryForTesting, ["现在只有您一个人", "另一条安全提醒"])
        service.stop()
    }

    // MARK: - 陪跑员跑步中取消

    /// 跑步中取消的确认层要提醒别把跑者留在原地，也不能再说「离开始不到 N 小时」。
    /// 取一个已经开跑的时间，这样窗口判定一定命中，能抓到套用通用文案的实现。
    func testCancelSheetDuringTheRunWarnsAboutLeavingTheRunnerAlone() {
        let sheet = VolunteerOrderFlowCopy.cancelSheet(
            for: .inProgress,
            plannedStart: Date().addingTimeInterval(-600),
            lateCancelWindowHours: 12
        )

        XCTAssertTrue(sheet.title.contains("跑步中"))
        XCTAssertTrue(sheet.message.contains("安全的地方"))
        XCTAssertTrue(sheet.message.contains("转给其他陪跑员"), "后果仍要说清")
        XCTAssertEqual(sheet.keep, "继续陪跑")
        XCTAssertEqual(sheet.cancel, "仍然取消")
        XCTAssertTrue(sheet.lateNotice?.contains("会记一次临时取消") == true)
        XCTAssertFalse(sheet.lateNotice?.contains("离开始") == true, "已经开跑了，这句话不成立")

        let withoutStart = VolunteerOrderFlowCopy.cancelSheet(for: .inProgress, plannedStart: nil, lateCancelWindowHours: 12)
        XCTAssertNotNil(withoutStart.lateNotice, "开跑之后取消一定会记，不看计划时间解析得出来与否")

        for status in [RunOrderStatus.driverEnRoute, .driverArrived] {
            let sheet = VolunteerOrderFlowCopy.cancelSheet(for: status, plannedStart: nil, lateCancelWindowHours: 12)
            XCTAssertEqual(sheet.title, "取消这次陪跑？", "\(status) 保持原文案")
        }
    }
}
