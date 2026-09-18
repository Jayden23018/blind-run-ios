import AudioToolbox
import Foundation
import OSLog

// MARK: - 新邀请的提示音（设计交付 v3 §4.4.1）

/// 派单弹出邀请卡那一刻响的那一声。设计稿逐字：「**轻震一次 + 短提示音一次（跟随静音开关）**，
/// 从底部升起」（`png/02-新邀请进来.png` 的注解与 §4.4.1 的表格）。
///
/// 🔴 **它是本仓库唯一一条跟随静音拨杆的提示音，走的通道也和其余三条不一样。**
///
/// `RecordingCue` / `EmergencyAlarm` / `AnnouncementCue` 全部是
/// `AVAudioPlayer` + `.playback` 分类，**刻意不跟随静音开关** —— 理由写在
/// `SpeechInputService.swift:93-95`：侧面那个拨杆是盲人看不见、也想不到要去检查的物理开关，
/// 录音起音提示和求助警报被它悄悄关掉是事故。
///
/// 邀请这一声反过来：接收它的是**看得见屏幕的陪跑员**，而且它不是安全链路上的一环
/// （漏掉一声的代价是这一单转给下一位，不是有人出事）。半夜把一台静音的手机叫醒，
/// 代价比漏一条邀请大。所以走**响铃通道**（`AudioServicesPlaySystemSound`），
/// 它天生受静音拨杆管 —— 那正是 `RecordingCue` 当初避开它的原因，在这里恰好是我们要的。
///
/// 🚩 **不打包音频资源**，复用 `ToneSynthesizer` 合成一条 WAV 落盘一次，理由与那三条同源
/// （几段正弦波不值得进 bundle，也不用动 `project.pbxproj`）。
/// 频率避开已在用的四组（录音起 660/990、录音止 880/587、倒计时 1318.5/987.8、
/// 警报 740/988）与播报那三声（784 / 1046.5 / 1174.7）：同一个 App 里两种提示音听混，
/// 等于两条都失效。
enum VolunteerInviteCue {
    /// C5 → F5，上行两声。**上行方向本身携带语义**（有东西来了），与录音止的下行相对。
    static let frequencies: [Double] = [523.25, 698.46]
    static let segmentDuration: TimeInterval = 0.11

    #if DEBUG
    /// 测试替身。设了就**接管**发声并记下它发生过。理由同 `AnnouncementCue.observerForTesting`：
    /// 没有断言的实现和不存在的实现，在下一个人眼里是一样的。
    nonisolated(unsafe) static var observerForTesting: (() -> Void)?
    #endif

    /// 线程处理与 `HapticFeedback.play` / `AnnouncementCue.play` 一致：调用点在 WebSocket 回调里，
    /// 线程不确定，而这里的静态缓存只该在主线程上碰。
    static func play() {
        let fire = { emit() }
        if Thread.isMainThread {
            fire()
        } else {
            DispatchQueue.main.async(execute: fire)
        }
    }

    /// 提前把 WAV 合成好、写盘、注册成 `SystemSoundID`。**进志愿者端时调一次。**
    ///
    /// 🔴 **不预热的表现是「第一条派单弹得一顿一顿的」。** `makeSoundID()` 要合成正弦波、
    /// 写一个文件、再进 `AudioServicesCreateSystemSoundID` —— 第一次派单进来时这些全发生在
    /// 主线程上，而同一拍里邀请卡的 spring 正要画第一帧。第二条之后就顺了，
    /// 所以这个缺陷**只在每次冷启动后的第一条派单上出现**，最容易被当成偶发。
    ///
    /// 合成与落盘放后台，只有最后写 `soundID` 那一下回主线程 —— 那个静态量的既有约定是
    /// 「只在主线程上碰」（见 `play()`），预热不能把它破掉。
    static func prewarm() {
        guard soundID == nil else { return }
        DispatchQueue.global(qos: .utility).async {
            guard let url = try? writeWaveFileIfNeeded() else { return }
            DispatchQueue.main.async {
                guard soundID == nil else { return }
                _ = registerSoundID(at: url)
            }
        }
    }

    /// 建一次、永不 `AudioServicesDisposeSystemSoundID`。
    /// 与 `AnnouncementCue.players` 同一条理由：播放中被释放会让系统回调打在已被复用的内存上。
    private nonisolated(unsafe) static var soundID: SystemSoundID?

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "AidRun",
        category: "VolunteerInviteCue"
    )

    private static func emit() {
        #if DEBUG
        if let observerForTesting {
            observerForTesting()
            return
        }
        #endif
        // 响不出来**不该影响别的**：邀请卡照常弹、震动照常震、播报照常播。
        guard let id = soundID ?? makeSoundID() else { return }
        AudioServicesPlaySystemSound(id)
    }

    private static func makeSoundID() -> SystemSoundID? {
        guard let url = try? writeWaveFileIfNeeded() else { return nil }
        return registerSoundID(at: url)
    }

    /// 合成 + 落盘。**没有共享可变状态，可以在任意线程跑**（`prewarm` 就在后台跑它）。
    ///
    /// `AudioServicesCreateSystemSoundID` 只收文件 URL，所以合成完要落一次盘。
    /// 放 caches 而不是 temporary：后者系统随时可以清，而我们持有的 sound id
    /// 在文件消失之后会静默不出声。caches 在进程活着时不会被清。
    private static func writeWaveFileIfNeeded() throws -> URL {
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let url = directory.appendingPathComponent("aidrun-volunteer-invite-cue.wav")
        guard !FileManager.default.fileExists(atPath: url.path) else { return url }
        do {
            let data = ToneSynthesizer.wav(
                frequencies: frequencies,
                segmentDuration: segmentDuration
            )
            try data.write(to: url, options: .atomic)
        } catch {
            logger.error("邀请提示音落盘失败：\(error.localizedDescription, privacy: .public)")
            throw error
        }
        return url
    }

    /// 写 `soundID` 的唯一入口。**只在主线程调**（`play` 与 `prewarm` 都保证了这一点）。
    private static func registerSoundID(at url: URL) -> SystemSoundID? {
        var created: SystemSoundID = 0
        let status = AudioServicesCreateSystemSoundID(url as CFURL, &created)
        guard status == kAudioServicesNoError else {
            logger.error("邀请提示音注册失败，OSStatus \(status, privacy: .public)")
            return nil
        }
        soundID = created
        return created
    }
}
