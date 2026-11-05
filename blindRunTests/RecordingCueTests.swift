import XCTest
import AMapSearchKit
import AVFAudio
import CoreLocation
import SwiftUI
@testable import blindRun

@MainActor
final class RecordingCueTests: XCTestCase, BlindRunTestSupport {
    // MARK: - 录音起止的非视觉提示（RecordingCue）
    //
    // 这一组存在的直接原因：`RecordingCue` 实现完整、两个调用点也都正确，却因为**一条断言
    // 都没有**，被三份文档集体误判成「尚未实现」（2026-08-06 订正）。对全盲用户，这两声提示
    // 是判断「麦克风开没开」的唯一非视觉信号 —— 屏幕上的波形动画对他们是零价值。
    // 没有守卫的实现，在下一个人眼里和不存在是一样的。

    /// 观察点是静态的，漏收会串到别的用例上。
    private func captureRecordingCues() -> () -> [RecordingCue.Kind] {
        var cues: [RecordingCue.Kind] = []
        RecordingCue.observerForTesting = { cues.append($0) }
        addTeardownBlock { @MainActor in RecordingCue.observerForTesting = nil }
        return { cues }
    }

    func testRecordingCueSoundsWhenRecognitionStarts() {
        let cues = captureRecordingCues()
        let service = SpeechInputService(audioSession: MockSpeechAudioSession())

        service.startRecognitionForTesting(field: .remark)

        XCTAssertEqual(cues(), [.begin], "起听成功必须发出起音提示，否则用户不知道可以开口了")
        XCTAssertTrue(service.isListening)
    }

    func testRecordingCueSoundsWhenRecognitionStops() {
        let cues = captureRecordingCues()
        let service = SpeechInputService(audioSession: MockSpeechAudioSession())
        service.startRecognitionForTesting(field: .remark)

        service.finishRecognitionForTesting(text: "大观楼")

        XCTAssertEqual(cues(), [.begin, .end], "停止必须发出收音提示，两端各一次、不重复")
    }

    /// 收音提示**必须在音频会话切回播放之后**才响。
    ///
    /// 录音会话下放系统音会被路由到录音链路，用户可能根本听不见 —— 那等于没有这个提示。
    /// 这条顺序约束只写在 `stopAudioRecognition` 的注释里，把它钉成断言。
    func testRecordingCueEndComesAfterThePlaybackSessionIsRestored() {
        let audioSession = MockSpeechAudioSession()
        var observedAtCue: [String] = []
        RecordingCue.observerForTesting = { kind in
            guard kind == .end else { return }
            observedAtCue = audioSession.operations + ["cue:end"]
        }
        addTeardownBlock { @MainActor in RecordingCue.observerForTesting = nil }
        let service = SpeechInputService(audioSession: audioSession)
        service.startRecognitionForTesting(field: .remark)

        service.finishRecognitionForTesting(text: "大观楼")

        XCTAssertEqual(
            observedAtCue,
            ["deactivateRecording", "configurePlayback", "activatePlayback", "cue:end"],
            "收音提示在音频会话切回播放之前响，用户就听不见它"
        )
    }

    /// 从来没起听成功过就不该有任何提示音 —— 响一声等于告诉盲人「在录了」，而麦克风根本没开。
    /// 锁的是 `stopAudioRecognition` 里那道 `wasListening` 守卫。
    func testRecordingCueStaysSilentWhenRecognitionNeverStarted() {
        let cues = captureRecordingCues()
        let service = SpeechInputService(audioSession: MockSpeechAudioSession())
        service.startPendingAuthorizationForTesting(field: .voiceOrderFreeform)

        service.denyAuthorizationForTesting()
        service.stopRecognition()

        XCTAssertEqual(cues(), [], "授权被拒的这一路从头到尾没开过麦克风，不该有任何提示音")
    }

    /// 同一种提示音必须始终复用**同一个** `AVAudioPlayer`。
    ///
    /// 这条不是性能优化，是 use-after-free 的守卫。播放器只要还会被「换掉」，就存在
    /// 「上一声还在播（0.22 秒）就被释放」的窗口 —— 而起听→停听在测试里只隔几微秒。
    /// 音频队列随后把 `AVAudioPlayer` 自己的完成回调 `-[AVAudioPlayer finishedPlaying:]`
    /// 派回主线程，打在那块已被复用的内存上，**崩在任意一条与音频无关的用例上**：
    /// 2026-08-16 真机同命令连跑两次，288 passed / 3 failed（限流、验证码、志愿者途中确认三条
    /// 各报 `-[__NSDictionaryM finishedPlaying:] unrecognized selector` 或 signal segv）
    /// 随后 291 passed / 0 failed。生产里就是 App 当场挂掉，而看不见屏幕的人只会觉得「点了没反应」。
    ///
    /// 一旦有人改回「每次发声 new 一个播放器」，这条当场变红。
    func testRecordingCueReusesOnePlayerPerKind() {
        // 必须走**真实**播放路径：装了观察者 `emit` 直接 return，播放器一个都不会建。
        RecordingCue.observerForTesting = nil

        RecordingCue.begin()
        let firstBeginPlayer = RecordingCue.playerForTesting(.begin)
        XCTAssertNotNil(firstBeginPlayer, "起音播放器没建起来，后面的对身份是空对空")

        RecordingCue.end()
        RecordingCue.begin()

        XCTAssertTrue(
            RecordingCue.playerForTesting(.begin) === firstBeginPlayer,
            "起音换了播放器 —— 旧的那个会在还在播的时候被释放，完成回调打到野指针上"
        )
        XCTAssertFalse(
            RecordingCue.playerForTesting(.end) === firstBeginPlayer,
            "起止两声必须各有自己的播放器，共用一个等于互相打断"
        )
    }

    /// 启动时必须把音频分类配成播放，否则冷启动第一句播报要等合成器自己去协商会话。
    ///
    /// 在这条之前，整个 App 的 `setCategory` 只在第一次开麦时才跑 —— 冷启动到那之前会话是
    /// 系统默认的 `.soloAmbient`。2026-08-06 真机报的「点开始约跑之后要等一下才开始读」是这条。
    func testLaunchPreparesThePlaybackCategoryBeforeAnythingIsSpoken() {
        let audioSession = MockSpeechAudioSession()
        let service = SpeechInputService(audioSession: audioSession)
        XCTAssertEqual(audioSession.operations, [], "构造函数不该碰音频会话")

        service.prepareForPlaybackAtLaunch()

        XCTAssertEqual(
            audioSession.operations,
            ["configurePlayback"],
            "启动只配分类、不激活 —— 激活会当场打断用户正在听的音乐，而这时我们还没有话要说"
        )
    }

    /// 起止提示音必须走**媒体通道**，不能走响铃 / 系统提示音通道。
    ///
    /// 2026-08-06 真机：合成器念得清清楚楚，起止提示一声都没有。根因是
    /// `AudioServicesPlaySystemSound` 走响铃通道，受侧面静音拨杆和响铃音量控制，
    /// 而 TTS 走媒体通道 —— iOS 上这是两套独立音量。**对全盲用户，这条提示是他判断
    /// 「麦克风开没开」的唯一非视觉信号，不能挂在一个他看不见、也想不到要检查的物理开关上。**
    ///
    /// 改成自己合成纯音、用 `AVAudioPlayer` 走 App 自己的会话播。这条断言锁的是「音频数据
    /// 真的能被解出来」—— 合成器写错一个字节头，提示音就又静悄悄地消失了，而那正是上一次
    /// 它消失时的样子：代码在，没人听得见。
    func testRecordingCueTonesAreDecodableAudioOnTheMediaChannel() throws {
        for (name, data) in [("起音", RecordingCue.beginToneData), ("收音", RecordingCue.endToneData)] {
            let player = try AVAudioPlayer(data: data)
            XCTAssertEqual(
                player.duration,
                RecordingCue.toneDuration,
                accuracy: 0.01,
                "\(name)提示音时长不对，WAV 头多半写错了"
            )
            XCTAssertGreaterThan(player.numberOfChannels, 0, "\(name)提示音没有声道")
        }
        XCTAssertNotEqual(
            RecordingCue.beginToneData,
            RecordingCue.endToneData,
            "起止两声必须可区分 —— 音色一样等于只告诉用户「有事发生」，没告诉他是开始还是结束"
        )
    }

    /// 合成出来的必须是**有声音**的，不是一段静音。
    ///
    /// WAV 头写对、时长也对，但采样点全是 0 的话，`AVAudioPlayer` 照样能解、照样「播放成功」，
    /// 而用户什么都听不见 —— 上面那条断言抓不到这种。
    func testSynthesizedToneIsNotSilence() {
        let data = ToneSynthesizer.wav(frequencies: [660, 990], segmentDuration: 0.11)
        let header = 44
        let samples = data.dropFirst(header)

        XCTAssertFalse(samples.isEmpty, "没有采样数据")
        let peak = stride(from: 0, to: samples.count - 1, by: 2).map { offset -> Int16 in
            let index = samples.startIndex + offset
            return Int16(littleEndian: Int16(samples[index]) | (Int16(samples[index + 1]) << 8))
        }.map { abs(Int32($0)) }.max() ?? 0

        XCTAssertGreaterThan(peak, 1000, "采样点几乎全是 0 —— 播放器会「成功播放」一段静音，用户什么都听不见")
    }

    /// 开麦头一小段的音量检测要丢掉 —— 那是自己放出来的起音提示。
    ///
    /// 录音分类改成 `.playAndRecord` 后，起音提示是真的从扬声器出去的，而 `.measurement` 模式没有
    /// 回声消除，那一声会被自己的麦克风录回来。当成「用户开口了」的话，静音判定立刻从首次静音
    /// （8 秒）切到尾静音（整句轮 2 秒）：刚听完提示、正在组织句子的人还没开口就被掐掉一轮，
    /// 然后听到一整单默认值的读回 —— **比原来的截断缺陷更糟**。
    func testInputLevelSoundIsIgnoredDuringTheStartCueWarmUp() {
        let startedAt = Date()

        XCTAssertFalse(
            SpeechInputService.acceptsInputLevelSound(startedAt: startedAt, now: startedAt),
            "开麦瞬间的响动是起音提示自己，不是用户说话"
        )
        XCTAssertFalse(
            SpeechInputService.acceptsInputLevelSound(
                startedAt: startedAt,
                now: startedAt.addingTimeInterval(SpeechInputService.inputWarmUpWindow - 0.05)
            ),
            "提示音还没放完就开始收，等于把它当成用户开口"
        )
        // 刻意不在恰好等于窗口的那一点上断言：`Date` 内部是相对参考日的 Double，
        // `addingTimeInterval(0.4)` 再取差回来会是 0.39999…，这里比的是浮点不是规则。
        XCTAssertTrue(
            SpeechInputService.acceptsInputLevelSound(
                startedAt: startedAt,
                now: startedAt.addingTimeInterval(SpeechInputService.inputWarmUpWindow + 0.05)
            ),
            "过了这一小段就必须正常收音，否则真的说话也检测不到"
        )
        XCTAssertFalse(
            SpeechInputService.acceptsInputLevelSound(startedAt: nil, now: startedAt),
            "还没正式起听就不该有「检测到声音」这回事"
        )
    }

    /// 录音分类**必须允许播放**，否则起音提示等于不存在。
    ///
    /// 这条和上面 `testRecordingCueEndComesAfterThePlaybackSessionIsRestored` 是同一个坑的两半：
    /// 「录音会话下放系统音听不见」。收音那一端 2026-08-06 靠调顺序修掉并留了断言，起音这一端
    /// 当时漏了 —— 它没有顺序可调（录音正要开始），只能改分类本身。2026-08-06 真机手测报的
    /// 「没有任何弹出语音的声音提示」就是漏掉的那一半。
    ///
    /// 断言分类常量而不是 `MockSpeechAudioSession` 的调用序列，是因为
    /// `SpeechAudioSessionManaging.configureRecordingCategory()` 不带参数，替身看不到分类是什么
    /// —— 只记录「调过了」的替身对这条缺陷是全盲的，这也正是它当初没被测出来的原因。
    func testRecordingCategoryAllowsPlaybackSoTheStartCueIsAudible() {
        XCTAssertEqual(
            SystemSpeechAudioSession.recordingCategory,
            .playAndRecord,
            "录音分类不允许播放时，起音提示对全盲用户等于不存在 —— 那是他判断麦克风开没开的唯一非视觉信号"
        )
        XCTAssertTrue(
            SystemSpeechAudioSession.recordingCategoryOptions.contains(.defaultToSpeaker),
            "playAndRecord 默认路由到听筒，不加 defaultToSpeaker 提示音会小到等于没有"
        )
        XCTAssertNotEqual(
            SystemSpeechAudioSession.recordingMode,
            .measurement,
            "measurement 把输出增益压得很低 —— 我们已经不是只录不放了，起音提示要在录音会话下响得出来"
        )
    }

    /// 起止提示必须是**方向相反的双音**，不是两个不同音高的单音。
    ///
    /// 人对音高「往上走 / 往下走」的敏感度远高于对绝对音高的记忆 —— 单音要求用户记住
    /// 「880 是开始、587 是结束」，双音不需要记任何东西。真机连续两轮反馈「不够响、
    /// 可能会被盲人忽略」，双音同时把频谱铺开，同样峰值电平下更容易被注意到。
    func testCueTonesRiseToStartAndFallToStop() {
        XCTAssertEqual(RecordingCue.beginToneFrequencies.count, 2)
        XCTAssertEqual(RecordingCue.endToneFrequencies.count, 2)
        XCTAssertLessThan(
            RecordingCue.beginToneFrequencies[0], RecordingCue.beginToneFrequencies[1],
            "起音必须上行 —— 「开始」在听感上是往上走的"
        )
        XCTAssertGreaterThan(
            RecordingCue.endToneFrequencies[0], RecordingCue.endToneFrequencies[1],
            "收音必须下行"
        )
    }
}
