import AVFoundation
import Combine
import CoreLocation
import UIKit

// 跑者详情的两条声音（OpenSpec `add-runner-run-record-detail`，HANDOFF 6.3 第 2、3 条、第 7 节最后一条）：
// 「听这次跑步」的讲述，与「用声音走一遍路线」。
//
// ⚠️ 音频会话**不在这里配**：启动时 `SystemSpeechAudioSession.configurePlaybackCategory` 已经是
// `.playback` / `.spokenAudio` / `.duckOthers`，正是 HANDOFF 要的那一套。
// 听感（音高、左右、提示音个数、与 VoiceOver 的交替）读代码验不出来，只能真机人耳验
// （记忆 audio-correctness-needs-real-ears-not-code-reading）。

// MARK: - 声音路线（纯计算 + 离线合成）

/// 把一次跑步排成一条时间线，再合成一段双声道 WAV（负责人 2026-09-25：离线合成 + `AVAudioPlayer`，不用 `AVAudioEngine`）。
nonisolated struct RunRouteSonification: Equatable, Sendable {
    static let secondsPerHundredMetres = 0.45
    /// 超过就压速率，整段不超过这么长（负责人 2026-09-25）。
    static let maxDuration = 45.0
    static let restGap = 1.1
    static let endTail = 1.1
    static let lowestHz = 380.0
    static let highestHz = 760.0
    static let kilometreBeepHz = 1250.0
    static let kilometreBeepSpacing = 0.14
    static let restBeepHz = 190.0
    static let endBeeps: [(hz: Double, offset: Double, length: Double)] = [(880, 0.35, 0.3), (1320, 0.55, 0.45)]
    static let toneLevel = 0.3
    static let maxPan = 0.9
    static let sampleRate = 22_050

    /// 每 100 米一格。
    struct Bar: Equatable, Sendable {
        let start: Double
        let metres: Int
        let hz: Double
        let pan: Double
    }

    struct Beep: Equatable, Sendable {
        let start: Double
        let hz: Double
        let level: Double
        let length: Double
    }

    let bars: [Bar]
    let barDuration: Double
    let beeps: [Beep]
    /// 休息那一段的起止（屏幕上写「休息」用）。
    let rests: [ClosedRange<Double>]
    let duration: Double

    /// 没有配速采样（或全程不足 100 米）返回 nil，这一节整节不显示。
    init?(samples: [RunPaceSample], stops: [RunStop], totalMetres: Int?, geometry: RunRouteGeometry?) {
        let sorted = samples.sorted { $0.distanceM < $1.distanceM }
        guard let scale = RunPaceScale(samples: sorted),
              let total = totalMetres ?? sorted.last?.distanceM,
              total >= 100 else { return nil }
        let barCount = Int((Double(total) / 100).rounded(.up))
        let restIndexes = Set(stops.map { min($0.atDistanceM / 100, barCount - 1) })
        let fixed = Double(restIndexes.count) * Self.restGap + Self.endTail
        barDuration = min(Self.secondsPerHundredMetres, max((Self.maxDuration - fixed) / Double(barCount), 0.05))

        // 左右只看东西向：取整条路线的经度范围，西边在左耳。没有路线就居中。
        let longitudes = geometry?.coordinates.map(\.longitude) ?? []
        let west = longitudes.min(), east = longitudes.max()
        func pan(atMetres metres: Int) -> Double {
            guard let geometry, let west, let east, east > west else { return 0 }
            let lng = geometry.coordinate(atMetres: metres).longitude
            return ((lng - west) / (east - west) * 2 - 1) * Self.maxPan
        }
        func hz(atMetres metres: Int) -> Double {
            let nearest = sorted.min { abs($0.distanceM - metres) < abs($1.distanceM - metres) }!
            // 按对数取（380–760 Hz 正好一个八度）：同样的配速差听起来是同样的音程。快 = 高。
            return Self.lowestHz * pow(Self.highestHz / Self.lowestHz, 1 - scale.fraction(nearest.paceSecPerKm))
        }

        var bars: [Bar] = []
        var beeps: [Beep] = []
        var rests: [ClosedRange<Double>] = []
        var t = 0.0
        for index in 0..<barCount {
            let middle = min(index * 100 + 50, total)
            bars.append(Bar(start: t, metres: index * 100, hz: hz(atMetres: middle), pan: pan(atMetres: middle)))
            // 第 N 公里响 N 声。
            if index > 0, index % 10 == 0 {
                for n in 0..<(index / 10) {
                    beeps.append(Beep(start: t + Double(n) * Self.kilometreBeepSpacing, hz: Self.kilometreBeepHz, level: 0.55, length: 0.12))
                }
            }
            t += barDuration
            if restIndexes.contains(index) {
                beeps.append(Beep(start: t + 0.35, hz: Self.restBeepHz, level: 0.8, length: 0.18))
                rests.append(t...(t + Self.restGap))
                t += Self.restGap
            }
        }
        for end in Self.endBeeps {
            beeps.append(Beep(start: t + end.offset, hz: end.hz, level: 0.55, length: end.length))
        }
        self.bars = bars
        self.beeps = beeps
        self.rests = rests
        duration = t + Self.endTail
    }

    /// 播放到 `time` 时落在哪一格；还没开始是 nil。
    func barIndex(at time: Double) -> Int? {
        guard let first = bars.first, time >= first.start else { return nil }
        return bars.lastIndex { $0.start <= time }
    }

    /// 屏幕上那一行字（HANDOFF：「第 N 公里」）。
    func caption(at time: Double) -> String? {
        if rests.contains(where: { $0.contains(time) }) { return "休息" }
        guard let index = barIndex(at: time) else { return nil }
        return "第 \(bars[index].metres / 1000 + 1) 公里"
    }

    /// 连续音的音量（不含 `toneLevel`）：开头 0.25 秒淡入，每次休息淡出 → 静 → 淡入，结尾淡出。
    func toneGain(at time: Double) -> Double {
        let fade = 0.25
        var gain = min(time / fade, 1)
        for rest in rests where rest.contains(time) {
            let out = 1 - (time - rest.lowerBound) / fade
            let back = 1 - (rest.upperBound - time) / fade
            gain = min(gain, max(out, back, 0))
        }
        let end = duration - Self.endTail
        if time >= end { gain = min(gain, max(1 - (time - end) / 0.3, 0)) }
        return gain
    }

    /// 16-bit 双声道 PCM 包成 WAV。几十万帧的循环，调用方放后台任务。
    func renderWAV() -> Data {
        let rate = Double(Self.sampleRate)
        let frames = Int(duration * rate)
        var left = [Double](repeating: 0, count: frames)
        var right = [Double](repeating: 0, count: frames)
        // 一阶低通 1.6 kHz：三角波的高次谐波直接进耳机偏刺。
        let alpha = 1 - exp(-2 * .pi * 1_600 / rate)
        var phase = 0.0
        var filtered = 0.0
        var barCursor = 0
        for frame in 0..<frames {
            let time = Double(frame) / rate
            while barCursor + 1 < bars.count, bars[barCursor + 1].start <= time { barCursor += 1 }
            // 每一格前 60% 从上一格的音高 / 位置滑过来，不跳变。
            let bar = bars[barCursor]
            let previous = barCursor > 0 ? bars[barCursor - 1] : bar
            let glide = min(max((time - bar.start) / (barDuration * 0.6), 0), 1)
            let hz = previous.hz + (bar.hz - previous.hz) * glide
            let pan = previous.pan + (bar.pan - previous.pan) * glide
            phase += hz / rate
            phase -= phase.rounded(.down)
            filtered += alpha * ((4 * abs(phase - 0.5) - 1) - filtered)
            let tone = filtered * toneGain(at: time) * Self.toneLevel
            // 等功率声像：-1 全左，+1 全右。
            let angle = (pan + 1) * .pi / 4
            left[frame] = tone * cos(angle)
            right[frame] = tone * sin(angle)
        }
        // 提示音居中、叠在连续音上面，各自只算自己那一小段。
        for beep in beeps {
            let first = Int(beep.start * rate)
            let last = min(Int((beep.start + beep.length + 0.05) * rate), frames)
            guard first < last else { continue }
            for frame in first..<last {
                let local = Double(frame) / rate - beep.start
                let envelope = local < 0.006 ? local / 0.006 : exp(-7 * (local - 0.006) / beep.length)
                let value = sin(2 * .pi * beep.hz * local) * envelope * beep.level * 0.7
                left[frame] += value
                right[frame] += value
            }
        }
        var pcm = Data(count: frames * 4)
        pcm.withUnsafeMutableBytes { raw in
            let out = raw.bindMemory(to: Int16.self)
            for frame in 0..<frames {
                out[frame * 2] = Int16(max(-1, min(1, left[frame])) * Double(Int16.max))
                out[frame * 2 + 1] = Int16(max(-1, min(1, right[frame])) * Double(Int16.max))
            }
        }
        return ToneSynthesizer.container(pcm: pcm, channels: 2, sampleRate: Self.sampleRate)
    }
}

// MARK: - 播放控制

/// 讲述与声音路线的唯一播放者。HANDOFF 第 7 节：两者与 VoiceOver 不互相打断 ——
/// 开始一个就停掉另一个和 App 自己的播报；VoiceOver 焦点移开就暂停，回到按钮再点从暂停处继续。
@MainActor
final class RunRecordAudioController: NSObject, ObservableObject {
    /// `narration` 与 `message`（「朗读留言」）共用一个合成器，规则一样。
    enum Source: Equatable {
        case narration, message, route
        var isSpeech: Bool { self != .route }
    }
    enum State: Equatable {
        case idle
        case preparing(Source)
        case playing(Source)
        case paused(Source)
    }

    @Published private(set) var state: State = .idle
    /// 声音路线已经放到第几秒（屏幕上的进度用）。
    @Published private(set) var routeTime: Double = 0

    /// 讲述用自己的合成器，**不走 `VoiceService.speak`**：那条同时发一次 VoiceOver 通告，
    /// 35 秒的讲述会被念两遍。
    private let synthesizer = AVSpeechSynthesizer()
    private var utterance: AVSpeechUtterance?
    /// 常驻，页面在它就在：播放中被释放 = `finishedPlaying:` 打在野指针上
    /// （记忆 finishedplaying-crash-means-player-freed-not-delegate）。
    private var player: AVAudioPlayer?
    private var renderedFor: RunRouteSonification?
    private var ticker: Task<Void, Never>?
    nonisolated(unsafe) private var focusObserver: NSObjectProtocol?
    private weak var voice: VoiceService?

    /// 当前在响的那个控件。焦点落在它以外的元素上就暂停。
    var activeControlIdentifier: String?

    override init() {
        super.init()
        synthesizer.delegate = self
        focusObserver = NotificationCenter.default.addObserver(
            forName: UIAccessibility.elementFocusedNotification, object: nil, queue: .main
        ) { [weak self] note in
            // SwiftUI 的无障碍节点不一定声明遵守 `UIAccessibilityIdentification`，按选择子取。
            let element = note.userInfo?[UIAccessibility.focusedElementUserInfoKey] as? NSObject
            let selector = NSSelectorFromString("accessibilityIdentifier")
            let identifier = element?.responds(to: selector) == true
                ? element?.perform(selector)?.takeUnretainedValue() as? String
                : nil
            MainActor.assumeIsolated { self?.focusMoved(to: identifier) }
        }
    }

    deinit {
        if let focusObserver { NotificationCenter.default.removeObserver(focusObserver) }
    }

    func configure(voice: VoiceService) {
        self.voice = voice
    }

    // MARK: 讲述 / 朗读留言

    func toggleSpeech(_ text: String, as source: Source = .narration) {
        precondition(source.isSpeech)
        switch state {
        case .playing(source):
            stop()
        case .paused(source):
            synthesizer.continueSpeaking()
            state = .playing(source)
        default:
            stop()
            voice?.stop()
            let utterance = VoiceService.makeUtterance(text)
            self.utterance = utterance
            state = .playing(source)
            synthesizer.speak(utterance)
        }
    }

    // MARK: 声音路线

    func toggleRoute(_ sonification: RunRouteSonification) {
        switch state {
        case .playing(.route):
            stop()
        case .paused(.route):
            player?.play()
            state = .playing(.route)
            startTicker()
        case .preparing(.route):
            stop()
        default:
            stop()
            voice?.stop()
            if let player, renderedFor == sonification {
                player.currentTime = 0
                play(player)
                return
            }
            state = .preparing(.route)
            Task {
                let data = await Task.detached(priority: .userInitiated) { sonification.renderWAV() }.value
                guard state == .preparing(.route) else { return }
                do {
                    let player = try AVAudioPlayer(data: data)
                    player.delegate = self
                    player.prepareToPlay()
                    self.player?.stop()
                    self.player = player
                    renderedFor = sonification
                    play(player)
                } catch {
                    state = .idle
                    voice?.speakError("声音路线没能播放。")
                }
            }
        }
    }

    private func play(_ player: AVAudioPlayer) {
        routeTime = 0
        player.play()
        state = .playing(.route)
        startTicker()
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let player = self.player, self.state == .playing(.route) else { return }
                self.routeTime = player.currentTime
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }

    // MARK: 暂停 / 停止

    func pause() {
        switch state {
        case .playing(let source) where source.isSpeech:
            synthesizer.pauseSpeaking(at: .word)
            state = .paused(source)
        case .playing(.route):
            player?.pause()
            ticker?.cancel()
            state = .paused(.route)
        default:
            break
        }
    }

    /// 页面离开、或开始另一个时调用。
    func stop() {
        utterance = nil
        synthesizer.stopSpeaking(at: .immediate)
        player?.stop()
        ticker?.cancel()
        routeTime = 0
        state = .idle
    }

    func focusMoved(to identifier: String?) {
        guard case .playing = state, identifier != activeControlIdentifier else { return }
        pause()
    }

    fileprivate func narrationEnded(_ ended: AVSpeechUtterance) {
        guard ended === utterance else { return }
        utterance = nil
        switch state {
        case .playing(let source), .paused(let source):
            if source.isSpeech { state = .idle }
        default:
            break
        }
    }

    fileprivate func routeEnded() {
        ticker?.cancel()
        routeTime = 0
        if state == .playing(.route) { state = .idle }
    }
}

extension RunRecordAudioController: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.narrationEnded(utterance) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.narrationEnded(utterance) }
    }
}

extension RunRecordAudioController: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.routeEnded() }
    }
}
