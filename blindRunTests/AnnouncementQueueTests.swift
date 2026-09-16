import AVFoundation
import XCTest
@testable import blindRun

/// 播报队列的五条规则（`状态清单.md` §全局规则「防叠声」逐字）。
///
/// **为什么必须是纯结构的单测**：这一层的每一条规则都只有真机、戴着耳机、
/// 在恰好两条播报撞上的那一刻才听得出来。真机那一遍只能回答「出声了没有」，
/// 回答不了「十秒前那条丢了没有」——它和「压根没排队」在耳朵里是同一个样子。
///
/// 错误形态全是**静默**的：丢错一条、排错一档，屏幕上不报任何错，
/// 而看不见屏幕的人只会觉得「刚才好像少听见了点什么」。
@MainActor
final class AnnouncementQueueTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func announcement(
        _ priority: AnnouncementPriority,
        text: String = "文本",
        at offset: TimeInterval = 0
    ) -> PendingAnnouncement {
        PendingAnnouncement(text: text, priority: priority, enqueuedAt: now.addingTimeInterval(offset))
    }

    // MARK: - 优先级本身

    /// 紧急求助 > 警示 > 对方操作 > 按需播报 > 每公里播报。
    ///
    /// 逐对比较而不是比 `rawValue`：把 `Comparable` 实现反了的话 `rawValue` 照样单调，
    /// 而整个队列会精确地反过来跑 —— 求助被每公里播报压住。
    func testPriorityOrderMatchesTheDesignSpec() {
        XCTAssertTrue(AnnouncementPriority.emergency > .alert)
        XCTAssertTrue(AnnouncementPriority.alert > .counterpartAction)
        XCTAssertTrue(AnnouncementPriority.counterpartAction > .onDemand)
        XCTAssertTrue(AnnouncementPriority.onDemand > .perKilometer)
        XCTAssertEqual(AnnouncementPriority.allCases.count, 5, "档位只有设计稿那五档，不许新增")
    }

    // MARK: - 一次只播一条，按优先级排队

    func testIdleQueueSpeaksImmediately() {
        var queue = AnnouncementQueue()
        XCTAssertEqual(
            queue.submit(announcement(.perKilometer), speaking: nil, isCallActive: false),
            .speakNow
        )
        XCTAssertTrue(queue.pending.isEmpty)
    }

    /// 低档来者排队，不打断。
    func testLowerPriorityWaitsForTheOneBeingSpoken() {
        var queue = AnnouncementQueue()
        XCTAssertEqual(
            queue.submit(announcement(.perKilometer), speaking: .emergency, isCallActive: false),
            .enqueued
        )
        XCTAssertEqual(queue.pending.count, 1)
    }

    /// 高档来者抢过去。
    func testHigherPriorityPreemptsTheOneBeingSpoken() {
        var queue = AnnouncementQueue()
        XCTAssertEqual(
            queue.submit(announcement(.emergency), speaking: .perKilometer, isCallActive: false),
            .speakNow
        )
    }

    /// 🔴 **同档 = 打断，不是排队。**
    ///
    /// 这条守的是本次改动**刻意没有改**的那一半行为。改成排队的直接受害者是求助倒计时：
    /// 它每秒调一次 `speak("还有 N 秒")`，靠「谁后说谁赢」盖掉上一秒 ——
    /// 排队的话三秒会念成「3」「3」「2」，而那三秒是用户反悔的唯一窗口。
    /// 顺带守着另外 230 个没传优先级的既有调用点：它们全落在默认档，行为必须与改动前逐字相同。
    func testSamePriorityStillInterruptsSoTheCountdownStaysCurrent() {
        var queue = AnnouncementQueue()
        XCTAssertEqual(
            queue.submit(announcement(.emergency), speaking: .emergency, isCallActive: false),
            .speakNow
        )
        XCTAssertTrue(queue.pending.isEmpty, "同档不该在队列里留下一条陈旧的备份")
    }

    /// 队列里每档至多一条：同档再来一条是**替换**，不是追加。
    func testSamePriorityReplacesInsteadOfPilingUp() {
        var queue = AnnouncementQueue()
        _ = queue.submit(announcement(.perKilometer, text: "已跑 1 公里"), speaking: .emergency, isCallActive: false)
        _ = queue.submit(announcement(.perKilometer, text: "已跑 2 公里"), speaking: .emergency, isCallActive: false)
        XCTAssertEqual(queue.pending.count, 1)
        XCTAssertEqual(queue.pending.first?.text, "已跑 2 公里", "排队时该听到的是最新那个里程，不是一串旧的")
    }

    /// 出队按优先级，不按先来后到。
    func testNextDrainsTheHighestPriorityFirst() {
        var queue = AnnouncementQueue()
        _ = queue.submit(announcement(.perKilometer, text: "公里"), speaking: .emergency, isCallActive: false)
        _ = queue.submit(announcement(.counterpartAction, text: "状态"), speaking: .emergency, isCallActive: false)
        XCTAssertEqual(queue.next(now: now, isCallActive: false)?.text, "状态")
        XCTAssertEqual(queue.next(now: now, isCallActive: false)?.text, "公里")
        XCTAssertNil(queue.next(now: now, isCallActive: false))
    }

    // MARK: - 按需播报打断排队中的每公里播报

    func testOnDemandDiscardsTheQueuedKilometerAnnouncement() {
        var queue = AnnouncementQueue()
        _ = queue.submit(announcement(.perKilometer, text: "已跑 2 公里"), speaking: .emergency, isCallActive: false)
        _ = queue.submit(announcement(.onDemand, text: "重复当前状态"), speaking: .emergency, isCallActive: false)
        XCTAssertEqual(queue.pending.count, 1, "每公里那条该被按需播报顶掉，而不是排在它后面接着念")
        XCTAssertEqual(queue.pending.first?.priority, .onDemand)
    }

    // MARK: - 每公里播报排队超过 10 秒即丢弃

    /// 取值挑在 10 秒两侧而不是随手取一个「明显该丢」的大数：
    /// 9.9 秒那一组是用来分辨「压根没实现丢弃」与「丢得太早」的，只验 30 秒分辨不出后者。
    func testKilometerAnnouncementExpiresAfterTenSecondsInTheQueue() {
        XCTAssertEqual(AnnouncementQueue.perKilometerMaxQueueAge, 10)

        var fresh = AnnouncementQueue()
        _ = fresh.submit(announcement(.perKilometer), speaking: .emergency, isCallActive: false)
        XCTAssertNotNil(
            fresh.next(now: now.addingTimeInterval(9.9), isCallActive: false),
            "还没到 10 秒就丢，等于每公里播报在有任何别的播报时都不会响"
        )

        var stale = AnnouncementQueue()
        _ = stale.submit(announcement(.perKilometer), speaking: .emergency, isCallActive: false)
        XCTAssertNil(
            stale.next(now: now.addingTimeInterval(10.1), isCallActive: false),
            "一句迟到的『已跑 2 公里』会让跑者按一个过期的数字判断还能跑多久"
        )
    }

    /// 只有每公里那一档会过期。按需档排了半分钟也要念 —— 用户按过按钮，静默等于「点了没反应」。
    func testOnlyTheKilometerPriorityExpires() {
        var queue = AnnouncementQueue()
        _ = queue.submit(announcement(.onDemand), speaking: .emergency, isCallActive: false)
        XCTAssertNotNil(queue.next(now: now.addingTimeInterval(30), isCallActive: false))
    }

    // MARK: - 通话中只保留警示

    func testDuringACallOnlyAlertsAndAboveGetThrough() {
        for priority in [AnnouncementPriority.perKilometer, .onDemand, .counterpartAction] {
            var queue = AnnouncementQueue()
            XCTAssertEqual(
                queue.submit(announcement(priority), speaking: nil, isCallActive: true),
                .dropped,
                "\(priority) 在通话中该被丢掉"
            )
            XCTAssertTrue(queue.pending.isEmpty)
        }
        for priority in [AnnouncementPriority.alert, .emergency] {
            var queue = AnnouncementQueue()
            XCTAssertEqual(
                queue.submit(announcement(priority), speaking: nil, isCallActive: true),
                .speakNow,
                "\(priority) 在通话中必须照播 —— 走散和求助正是最需要打断一通电话的两件事"
            )
        }
    }

    /// 排队期间电话打进来：出队时同样要把低档的清掉，不能等它排到头再念。
    func testACallStartedWhileQueuedStillSilencesTheLowPriorityOnes() {
        var queue = AnnouncementQueue()
        _ = queue.submit(announcement(.counterpartAction), speaking: .emergency, isCallActive: false)
        _ = queue.submit(announcement(.alert), speaking: .emergency, isCallActive: false)
        XCTAssertEqual(queue.next(now: now, isCallActive: true)?.priority, .alert)
        XCTAssertNil(queue.next(now: now, isCallActive: true))
    }

    // MARK: - 通告（倒计时那三拍）也认优先级

    /// 阶段 1 留下的账①：倒计时三拍此前直接 `UIAccessibility.post`，绕开了整条 funnel。
    func testCountdownBeatsNeverOverrideAHigherPriorityUtterance() {
        XCTAssertFalse(
            AnnouncementQueue.allowsAnnouncement(.counterpartAction, speaking: .emergency, isCallActive: false),
            "求助正在播的时候，倒计时的『3』不该把它从读屏通道里挤掉"
        )
        XCTAssertTrue(
            AnnouncementQueue.allowsAnnouncement(.counterpartAction, speaking: .counterpartAction, isCallActive: false)
        )
        XCTAssertTrue(
            AnnouncementQueue.allowsAnnouncement(.counterpartAction, speaking: .onDemand, isCallActive: false)
        )
        XCTAssertTrue(AnnouncementQueue.allowsAnnouncement(.perKilometer, speaking: nil, isCallActive: false))
        XCTAssertFalse(
            AnnouncementQueue.allowsAnnouncement(.counterpartAction, speaking: nil, isCallActive: true),
            "通话中连通告也只保留警示"
        )
    }

    // MARK: - 四种提示音

    /// 四种提示音必须**彼此可分辨**：同一个 App 里两种提示音听混，等于两条都失效。
    ///
    /// 断言频率组本身而不是「播过了」：只记调用的替身分不出「响了正确的那一声」
    /// 和「四种全响成同一声」—— 后者在代码里只是一个复制粘贴没改的常量名。
    func testTheFourCuesUseDistinctToneSignatures() {
        let signatures: [[Double]] = [
            AnnouncementCue.leadInFrequencies,
            AnnouncementCue.attentionFrequencies,
            AnnouncementCue.alertFrequencies,
            EmergencyAlarm.countdownTickFrequencies
        ]
        // 连既有的录音起止两声一起对，全 App 六组提示音两两不同。
        let all = signatures + [RecordingCue.beginToneFrequencies, RecordingCue.endToneFrequencies]
        XCTAssertEqual(Set(all.map { $0.description }).count, all.count, "有两种提示音撞了同一组频率")
    }

    /// 前置音是**单声 0.3 秒**（`状态清单.md` §全局规则逐字）。
    func testLeadInCueIsASingleThreeHundredMillisecondTone() {
        XCTAssertEqual(AnnouncementCue.leadInFrequencies.count, 1, "前置音是单声，不是双音")
        XCTAssertEqual(AnnouncementCue.duration(.leadIn), 0.3, accuracy: 0.0001)
        XCTAssertEqual(AnnouncementCue.attentionFrequencies.count, 2, "注意音是两声短音")
        XCTAssertEqual(AnnouncementCue.alertFrequencies.count, 3, "警示音是三连音")
    }

    /// 哪一档带前置音。**对方操作不带**——状态推进一天几十次，每条配一声「叮」就成了噪音。
    func testOnlyOnDemandAndKilometerGetTheLeadInTone() {
        XCTAssertEqual(AnnouncementCue.leadIn(for: .perKilometer), .leadIn)
        XCTAssertEqual(AnnouncementCue.leadIn(for: .onDemand), .leadIn)
        XCTAssertEqual(AnnouncementCue.leadIn(for: .alert), .alert)
        XCTAssertNil(AnnouncementCue.leadIn(for: .counterpartAction))
        XCTAssertNil(AnnouncementCue.leadIn(for: .emergency))
    }

    /// 播放器按种类各持有一个、创建后永不释放。
    ///
    /// 这不是优化而是防崩：播放中被释放会让 `AVAudioPlayer` 自己的完成回调
    /// `finishedPlaying:` 打在已被复用的内存上，表现是**崩在任意一条与音频无关的用例上**
    /// （记忆 `finishedplaying-crash-means-player-freed-not-delegate`）。
    func testEachCueReusesOnePlayer() {
        AnnouncementCue.observerForTesting = nil
        for kind in AnnouncementCue.Kind.allCases {
            AnnouncementCue.play(kind)
            let first = AnnouncementCue.playerForTesting(kind)
            XCTAssertNotNil(first, "\(kind) 的播放器没建起来，提示音等于不存在")
            AnnouncementCue.play(kind)
            XCTAssertTrue(
                first === AnnouncementCue.playerForTesting(kind),
                "\(kind) 每次发声都新建播放器 —— 上一声还在播时被释放就会崩在随机的用例上"
            )
        }
    }

    // MARK: - 播报接进合成器的那一段

    /// 前置音要先响完再开口，靠系统的 `preUtteranceDelay`，不自己起定时器。
    func testLeadInDelayLandsOnTheUtterance() {
        XCTAssertEqual(VoiceService.makeUtterance("测试").preUtteranceDelay, 0, accuracy: 0.0001)
        XCTAssertEqual(
            VoiceService.makeUtterance("测试", leadInDelay: 0.3).preUtteranceDelay,
            0.3,
            accuracy: 0.0001
        )
    }

    /// 音乐**只压低不暂停**（`状态清单.md` §全局规则逐字）。
    ///
    /// 断言分类常量而不是替身的调用序列：`configurePlaybackCategory()` 不带参数，
    /// 只记「调过了」的替身看不见 options —— 那正是这条此前没有任何守卫的原因
    /// （同 `testRecordingCategoryAllowsPlaybackSoTheStartCueIsAudible` 的理由）。
    func testPlaybackCategoryDucksMusicInsteadOfPausingIt() {
        XCTAssertTrue(
            SystemSpeechAudioSession.playbackCategoryOptions.contains(.duckOthers),
            "不带 duckOthers 的 .playback 会打断其它音频：每念一句就把用户的音乐掐停一次"
        )
    }

    /// 通话中只保留警示 —— 这一条从 `VoiceService` 这一端再验一次。
    ///
    /// 纯结构那几条验的是判定，这条验的是**判定真的接上了**：`isCallActive` 若没被读，
    /// 上面所有用例照样全绿，而真机上通话时会照念每公里播报。
    func testVoiceServiceHonoursTheCallGate() {
        let service = VoiceService()
        service.isCallActive = { true }
        service.resetSpokenHistoryForTesting()

        service.speak("已跑 2 公里", priority: .perKilometer)
        XCTAssertTrue(service.spokenHistoryForTesting.isEmpty, "通话中不该念每公里播报")

        service.speak("你们可能走散了", priority: .alert)
        XCTAssertEqual(service.spokenHistoryForTesting, ["你们可能走散了"], "通话中必须保留警示")
        service.stop()
    }

    /// 排队中的那条**可能永远不会播**，所以入队不算「说过了」。
    ///
    /// 记错的后果精确落在「重复当前状态」上：它念 `latestRepeatableText`，
    /// 而那个按钮存在的全部意义就是复述**用户刚才听到的**那一句。
    func testQueuedAnnouncementDoesNotCountAsSpokenUntilItPlays() {
        let service = VoiceService()
        service.isCallActive = { false }
        service.resetSpokenHistoryForTesting()

        service.speak("求助已发出", priority: .emergency)
        service.speak("已跑 2 公里", priority: .perKilometer)

        XCTAssertEqual(service.spokenHistoryForTesting, ["求助已发出"])
        XCTAssertEqual(
            service.latestRepeatableText,
            "求助已发出",
            "排着队的那句还没被任何人听到，不该成为『重复当前状态』的内容"
        )
        service.stop()
    }

    /// 合成器代理丢一次 `didFinish`，队列不能就此永远卡住。
    ///
    /// 这不是假想故障：`VoiceOrderWizard.speechSettleDeadline` 的注释逐字写着它
    /// 「存在只是为了在合成器代理丢事件时不至于无限等下去」。本次改动把后果放大了 ——
    /// 卡住的不再只是「等久一点」，而是此后每一条低档播报都被静默排队，
    /// 表现是「App 从某一刻起就不说话了」，屏幕上一个字都不变。
    ///
    /// 用 `.distantFuture` 推时钟而不是真的等 8 秒：等待版在真机上是一条必然变慢、
    /// 偶尔变红的用例，而它要验的那个分支跟等多久没有关系。
    func testAStuckUtteranceStopsBlockingTheQueueOnceItsDeadlinePasses() {
        let service = VoiceService()
        service.isCallActive = { false }
        service.resetSpokenHistoryForTesting()

        service.speak("求助已发出", priority: .emergency)
        service.speak("已跑 2 公里", priority: .perKilometer)
        XCTAssertEqual(service.spokenHistoryForTesting, ["求助已发出"], "低档那条该在排队")

        // 代理没回来，但这条按字数算怎么也该念完了。
        service.clearStaleUtteranceIfNeeded(now: .distantFuture)
        service.speak("已跑 3 公里", priority: .perKilometer)

        XCTAssertEqual(
            service.spokenHistoryForTesting,
            ["求助已发出", "已跑 3 公里"],
            "兜底没接上时这一句会被永远排在一条早就播完的播报后面"
        )
        service.stop()
    }
}
