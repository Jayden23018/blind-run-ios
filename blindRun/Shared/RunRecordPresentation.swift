import Combine
import CoreLocation
import UIKit

// 跑后详情的纯计算（OpenSpec `add-volunteer-run-record-detail`）：配速着色、路线几何、文案。
// 与视图分开，好让用例直接钉；阶段 5（跑者详情）也从这里取。

// MARK: - View Model（两个角色的详情页共用）

@MainActor
final class RunRecordViewModel: ObservableObject {
    enum Phase: Equatable {
        case loading
        case loaded(RunRecordResponse)
        case failed(String)
    }

    /// 契约 `getRunRecord`：`GENERATING` 时「客户端 1–2 秒后重试」。
    static let generatingRetryNanoseconds: UInt64 = 2_000_000_000

    /// 留言发送（OpenSpec `add-run-record-messages`）。草稿是视图状态，不在这里。
    enum SendState: Equatable {
        case idle
        case sending
        case sent
        case failed(String)
    }

    /// 与后端 `@Size(max = 200)` 同口径：Java `String.length()` = UTF-16 码元。
    static let messageMaxLength = 200

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var sendState: SendState = .idle
    /// 本页发出去的留言。记录重读（GENERATING）后按 `id` 去重合并，不会出现两遍。
    @Published private(set) var sentMessages: [RunRecordMessageResponse] = []

    let orderId: Int64
    private let retryNanoseconds: UInt64
    private weak var appState: AppState?
    private weak var speech: SpeechService?
    private var runRecordOverride: (any RunRecordServing)?

    init(orderId: Int64, retryNanoseconds: UInt64 = generatingRetryNanoseconds) {
        self.orderId = orderId
        self.retryNanoseconds = retryNanoseconds
    }

    /// ⚠️ `appState` / `speech` 是 weak：用例要自己持有。`runRecord` 只给用例换替身。
    func configure(with appState: AppState, speech: SpeechService? = nil, runRecord: (any RunRecordServing)? = nil) {
        self.appState = appState
        self.speech = speech
        self.runRecordOverride = runRecord
    }

    // MARK: 留言

    /// 记录里的留言 + 本页发出的，按时间先后。
    func messages(of record: RunRecordResponse) -> [RunRecordMessageResponse] {
        let known = Set(record.messages.map(\.id))
        return record.messages + sentMessages.filter { !known.contains($0.id) }
    }

    /// 去掉首尾空白后 1–200 个字才发；不合格返回要显示并念出来的原因。
    static func draftProblem(_ draft: String) -> String? {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return "先写一句话再发送。" }
        if text.utf16.count > messageMaxLength {
            return "留言最多 \(messageMaxLength) 个字，现在是 \(text.utf16.count) 个字。"
        }
        return nil
    }

    /// 发成功返回 true（调用方据此清空草稿）；失败时草稿留着，原因显示并念出来。
    @discardableResult
    func send(_ draft: String) async -> Bool {
        guard sendState != .sending, let appState else { return false }
        if let problem = Self.draftProblem(draft) {
            fail(problem)
            return false
        }
        sendState = .sending
        let service = runRecordOverride ?? appState.runRecord
        do {
            let message = try await service.postMessage(
                orderId: orderId,
                text: draft.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            sentMessages.append(message)
            sendState = .sent
            return true
        } catch let error as APIError {
            if appState.handleAuthenticatedAPIError(error) {
                sendState = .idle
                return false
            }
            fail("留言没有发出。" + Self.sendFailureReason(error))
        } catch is CancellationError {
            sendState = .idle
        } catch {
            fail("留言没有发出。请检查网络后再发一次。")
        }
        return false
    }

    /// 用户开始改草稿时，把上一次的「已发送 / 没发出」收起来。
    func clearSendOutcome() {
        if sendState != .sending { sendState = .idle }
    }

    static func sendFailureReason(_ error: APIError) -> String {
        switch error {
        case .networkError:
            return "请检查网络后再发一次。"
        case .serverError(let response):
            switch response.errorCode {
            case .invalidOrderStatus: return "这一单还没完成，暂时不能留言。"
            case .notOrderParticipant: return "你不是这一单的参与者。"
            case .orderNotFound: return "这一单已经不存在了。"
            default: return error.localizedMessage
            }
        default:
            return error.localizedMessage
        }
    }

    private func fail(_ reason: String) {
        sendState = .failed(reason)
        speech?.speakError(reason)
    }

    /// 读到不是 `GENERATING` 为止；页面关掉（任务取消）就停。
    func loadUntilSettled() async {
        while !Task.isCancelled {
            await loadOnce()
            guard case .loaded(let record) = phase, record.status == .generating else { return }
            try? await Task.sleep(nanoseconds: retryNanoseconds)
        }
    }

    func retry() async {
        phase = .loading
        await loadUntilSettled()
    }

    private func loadOnce() async {
        guard let appState else { return }
        let service = runRecordOverride ?? appState.runRecord
        do {
            phase = .loaded(try await service.record(orderId: orderId))
        } catch let error as APIError {
            if appState.handleAuthenticatedAPIError(error) { return }
            phase = .failed("跑后记录没能加载。\(error.localizedMessage)")
        } catch is CancellationError {
            return
        } catch {
            phase = .failed("跑后记录没能加载，请检查网络后重试。")
        }
    }
}

// MARK: - 数字文案

enum RunRecordText {
    /// `6'15"`。只给陪跑员的屏幕用（HANDOFF 5.3：跑者视图与读屏都不许出现这种写法）。
    static func pace(_ secondsPerKm: Int) -> String {
        "\(secondsPerKm / 60)'\(String(format: "%02d", secondsPerKm % 60))\""
    }

    /// 「每公里6分15秒」。整分时不念「0秒」。
    static func spokenPace(_ secondsPerKm: Int) -> String {
        "每公里" + spokenDuration(secondsPerKm)
    }

    /// `42:10` / `1:02:03`。
    static func clock(_ seconds: Int) -> String {
        let h = seconds / 3600, m = seconds % 3600 / 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// 「1小时2分3秒」，为 0 的段不念。
    static func spokenDuration(_ seconds: Int) -> String {
        let h = seconds / 3600, m = seconds % 3600 / 60, s = seconds % 60
        var text = ""
        if h > 0 { text += "\(h)小时" }
        if m > 0 { text += "\(m)分" }
        if s > 0 || text.isEmpty { text += "\(s)秒" }
        return text
    }

    static func kilometres(_ metres: Int, spoken: Bool = false) -> String {
        RunRecordHistoryViewModel.kilometres(metres, spoken: spoken)
    }
}

// MARK: - 配速着色（HANDOFF 5.1）

/// 以本次配速的第 5 与第 95 百分位为两端，映射到 0（快）…1（慢）。
nonisolated struct RunPaceScale: Equatable {
    let fastEnd: Double
    let slowEnd: Double

    init?(samples: [RunPaceSample]) {
        let sorted = samples.map { Double($0.paceSecPerKm) }.sorted()
        guard !sorted.isEmpty else { return nil }
        fastEnd = Self.percentile(sorted, 0.05)
        slowEnd = Self.percentile(sorted, 0.95)
    }

    /// 线性插值的百分位（与 numpy 默认口径一致）。
    static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        let position = p * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = min(lower + 1, sorted.count - 1)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * (position - Double(lower))
    }

    func fraction(_ secondsPerKm: Int) -> Double {
        // 全程配速一样时没有「快慢」可言，落在中间档。
        guard slowEnd > fastEnd else { return 0.5 }
        return min(max((Double(secondsPerKm) - fastEnd) / (slowEnd - fastEnd), 0), 1)
    }
}

enum RunPacePalette {
    /// 0…0.5 快→中，0.5…1 中→慢（故意不用红绿）。
    static func rgb(fraction: Double, isDark: Bool) -> UInt32 {
        let fast = isDark ? AppColors.paceFastTone.dark : AppColors.paceFastTone.light
        let mid = isDark ? AppColors.paceMidTone.dark : AppColors.paceMidTone.light
        let slow = isDark ? AppColors.paceSlowTone.dark : AppColors.paceSlowTone.light
        let f = min(max(fraction, 0), 1)
        return f <= 0.5 ? mix(fast, mid, f * 2) : mix(mid, slow, (f - 0.5) * 2)
    }

    static func color(fraction: Double, isDark: Bool) -> UIColor {
        UIColor(rgb: rgb(fraction: fraction, isDark: isDark))
    }

    private static func mix(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
        func channel(_ shift: UInt32) -> UInt32 {
            let x = Double((a >> shift) & 0xFF), y = Double((b >> shift) & 0xFF)
            return UInt32((x + (y - x) * t).rounded()) << shift
        }
        return channel(16) | channel(8) | channel(0)
    }
}

// MARK: - 路线几何

nonisolated struct RunRouteGeometry {
    /// 起终点相距不超过这么多米就合并成一个「起终点」标记（HANDOFF 6.2「重合时合并」没给阈值）。
    static let startEndMergeMetres: CLLocationDistance = 50
    /// 配速颜色量化成几档。每换一档放一个 `drawStyleIndexes` —— SDK 说索引点不抽稀、要少放。
    static let paceLevels = 8

    let coordinates: [CLLocationCoordinate2D]
    /// 与 `coordinates` 一一对应的累计米数。
    let distances: [Int]

    /// 去掉连续重复点（SDK：「如果有连续重复点，需要去重处理…否则会导致绘制有问题」）。不足 2 点返回 nil。
    init?(track: RunTrack) {
        var coordinates: [CLLocationCoordinate2D] = []
        var distances: [Int] = []
        for point in track.points {
            if let last = coordinates.last, last.latitude == point.lat, last.longitude == point.lng { continue }
            coordinates.append(CLLocationCoordinate2D(latitude: point.lat, longitude: point.lng))
            distances.append(point.d)
        }
        guard coordinates.count >= 2 else { return nil }
        self.coordinates = coordinates
        self.distances = distances
    }

    var totalMetres: Int { distances.last ?? 0 }

    var startEndCoincide: Bool {
        guard let first = coordinates.first, let last = coordinates.last else { return false }
        return CLLocation(latitude: first.latitude, longitude: first.longitude)
            .distance(from: CLLocation(latitude: last.latitude, longitude: last.longitude)) <= Self.startEndMergeMetres
    }

    /// 累计米数落在 `metres` 的那个位置（两点之间线性插值）。
    func coordinate(atMetres metres: Int) -> CLLocationCoordinate2D {
        guard let upper = distances.firstIndex(where: { $0 >= metres }) else { return coordinates[coordinates.count - 1] }
        guard upper > 0 else { return coordinates[0] }
        let d0 = distances[upper - 1], d1 = distances[upper]
        let t = d1 > d0 ? Double(metres - d0) / Double(d1 - d0) : 0
        let a = coordinates[upper - 1], b = coordinates[upper]
        return CLLocationCoordinate2D(latitude: a.latitude + (b.latitude - a.latitude) * t,
                                      longitude: a.longitude + (b.longitude - a.longitude) * t)
    }

    /// 1、2、3… 公里处。
    var kilometreMarkers: [(km: Int, coordinate: CLLocationCoordinate2D)] {
        guard totalMetres >= 1000 else { return [] }
        return (1...(totalMetres / 1000)).map { ($0, coordinate(atMetres: $0 * 1000)) }
    }

    /// 第 `index` 段（从 1 起）那一截，两端插值。
    func segment(index: Int) -> [CLLocationCoordinate2D] {
        let start = (index - 1) * 1000
        let end = min(index * 1000, totalMetres)
        guard end > start else { return [] }
        let inner = zip(coordinates, distances).filter { $0.1 > start && $0.1 < end }.map(\.0)
        return [coordinate(atMetres: start)] + inner + [coordinate(atMetres: end)]
    }

    /// 配速线的 `drawStyleIndexes` 与每段的颜色位置。每个点取距离最近的配速采样。
    func paceStyle(samples: [RunPaceSample], scale: RunPaceScale) -> (indexes: [Int], fractions: [Double]) {
        let sorted = samples.sorted { $0.distanceM < $1.distanceM }
        func level(at metres: Int) -> Int {
            guard let nearest = sorted.min(by: { abs($0.distanceM - metres) < abs($1.distanceM - metres) }) else {
                return Self.paceLevels / 2
            }
            return Int((scale.fraction(nearest.paceSecPerKm) * Double(Self.paceLevels - 1)).rounded())
        }
        let levels = distances.map(level(at:))
        var indexes: [Int] = []
        var fractions = [Double(levels[0]) / Double(Self.paceLevels - 1)]
        for i in 1..<levels.count where levels[i] != levels[i - 1] {
            indexes.append(i)
            fractions.append(Double(levels[i]) / Double(Self.paceLevels - 1))
        }
        return (indexes, fractions)
    }
}
