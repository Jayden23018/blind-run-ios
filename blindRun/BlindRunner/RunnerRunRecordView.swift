import CoreLocation
import SwiftUI

// 视障跑者跑后详情（OpenSpec `add-runner-run-record-detail`，HANDOFF 6.3 的 P0 部分，DECISIONS D13）。
// 数据只来自 `RunRecordServing.record(orderId:)`；view model 与陪跑员页共用（`RunRecordViewModel`）。
//
// 这一页**任何地方都不出现 `6'15"`**（HANDOFF 5.3）：屏幕与读屏一律「6分15秒」。
// 没做（P1 / 后续阶段）：低视力高对比大地图、分享给家人、休息点地名、留言一节与回复（阶段 6）。

// MARK: - Content（纯计算，用例直接钉）

struct RunnerRunRecordContent {
    struct Row: Hashable {
        let label: String
        let value: String
        let accessibilityLabel: String
    }

    struct SplitRow: Hashable {
        let index: Int
        let title: String
        let value: String
        let detail: String?
        let isFastest: Bool
        let accessibilityLabel: String
    }

    /// 两个及以上满公里分段的步频，最大减最小不超过这个数就说「很稳」（HANDOFF 没给阈值）。
    static let steadyCadenceSpread = 5

    let dateLine: String?
    let title: String
    let distanceText: String?
    let facts: [String]
    let headerLabel: String
    /// nil = 没有可讲的（生成中 / 失败），不给「听这次跑步」。
    let narration: String?
    let splits: [SplitRow]
    let moreData: [Row]
    /// nil = 没有路线。
    let routeDescription: String?

    init(record: RunRecordResponse, geometry: RunRouteGeometry? = nil) {
        let partner = record.volunteerName?.trimmingCharacters(in: .whitespaces).nonEmpty
        let spokenPartner = partner?.unmaskedForSpeech
        let place = record.place?.trimmingCharacters(in: .whitespaces).nonEmpty
        let start = (record.runStartedAt ?? record.service.startedAt)?.backendTimestamp
        let summary = record.summary

        dateLine = start.map { Self.shortDate.string(from: $0) + Self.period(of: $0) }
        let spokenDate = start.map { Self.longDate.string(from: $0) + Self.period(of: $0) }

        func activity(_ who: String?) -> String {
            switch (who, place) {
            case let (who?, place?): return "和\(who)在\(place)"
            case let (who?, nil): return "和\(who)一起"
            case let (nil, place?): return "在\(place)"
            case (nil, nil): return ""
            }
        }
        let shownActivity = activity(partner)
        // 屏幕标题：「和林*在深圳湾公园」「和林*一起跑」「在深圳湾公园」。
        title = shownActivity.isEmpty ? "这次跑步" : (place == nil ? shownActivity + "跑" : shownActivity)
        let spokenActivity = activity(spokenPartner)

        distanceText = summary?.distanceM.map { RunRecordText.kilometres($0) }
        let spokenKm = summary?.distanceM.map { RunRecordText.kilometres($0, spoken: true) }
        let comparison = record.comparison.map { Self.comparisonText($0) }

        facts = [
            summary?.movingSec.map { "用时 \(RunRecordText.spokenDuration($0))" },
            summary?.avgPaceSecPerKm.map { "每公里 \(RunRecordText.spokenDuration($0))" },
            comparison.map { "比上次\($0.verb) \($0.amount) 公里" }
        ].compactMap { $0 }

        // 头部整块一个元素（HANDOFF 6.3 第 1 条）。数字与单位之间留空格，审计判「标签不可读」（阶段 3）。
        var header = [spokenDate, spokenActivity.isEmpty ? "跑步" : spokenActivity + "跑步"]
            .compactMap { $0 }.joined(separator: "，") + "。"
        let stats = [
            spokenKm.map { "\($0) 公里" },
            summary?.movingSec.map { "运动时间\(RunRecordText.spokenDuration($0))" },
            summary?.avgPaceSecPerKm.map { "平均\(RunRecordText.spokenPace($0))" },
            comparison.map { "比上次\($0.verb) \($0.amount) 公里" }
        ].compactMap { $0 }
        if !stats.isEmpty { header += stats.joined(separator: "，") + "。" }
        headerLabel = header

        let fullSplits = record.splits.filter { $0.distanceM >= 1000 }
        splits = record.splits.map { split in
            let isFull = split.distanceM >= 1000
            let isFastest = split.index == record.fastestSplitIndex
            let cadence = split.avgCadence
            if isFull {
                let pace = RunRecordText.spokenDuration(split.paceSecPerKm)
                var label = "第\(split.index)公里，\(pace)"
                if isFastest { label += "，本次最快" }
                if let cadence { label += "，步频每分钟\(cadence)步" }
                return SplitRow(
                    index: split.index, title: "第 \(split.index) 公里", value: pace,
                    detail: cadence.map { "步频 \($0)" }, isFastest: isFastest, accessibilityLabel: label + "。"
                )
            }
            let km = RunRecordText.kilometres(split.distanceM, spoken: true)
            let used = RunRecordText.spokenDuration(split.durationSec)
            let pace = RunRecordText.spokenDuration(split.paceSecPerKm)
            var label = "最后 \(km) 公里，用时\(used)，折合每公里\(pace)"
            if let cadence { label += "，步频每分钟\(cadence)步" }
            return SplitRow(
                index: split.index, title: "最后 \(km) 公里", value: used,
                detail: (["折合每公里 \(pace)"] + [cadence.map { "步频 \($0)" }].compactMap { $0 }).joined(separator: "，"),
                isFastest: false, accessibilityLabel: label + "。"
            )
        }

        var rows: [Row] = []
        func row(_ label: String, _ value: String, spoken: String? = nil) {
            rows.append(Row(label: label, value: value, accessibilityLabel: "\(label)，\(spoken ?? value)"))
        }
        if let steps = summary?.steps { row("步数", "\(steps.formatted()) 步", spoken: "\(steps)步") }
        if let cadence = summary?.avgCadence { row("平均步频", "\(cadence) 步/分", spoken: "每分钟\(cadence)步") }
        if let climb = summary?.elevationGainM { row("累计爬升", "\(climb) 米") }
        if let rest = summary?.restSec { row("中途休息", RunRecordText.spokenDuration(rest)) }
        if let elapsed = summary?.elapsedSec { row("总时长（含休息）", RunRecordText.spokenDuration(elapsed)) }
        // D6：跑者看得到这位陪跑员的累计服务时长。
        if let total = record.service.volunteerTotalServiceMinutes {
            let value = RunRecordHistoryViewModel.serviceDuration(total)
            rows.append(Row(
                label: "\(partner ?? "陪跑员")累计陪跑", value: value,
                accessibilityLabel: "\(spokenPartner ?? "陪跑员")累计陪跑，\(value)"
            ))
        }
        moreData = rows

        routeDescription = geometry.map { Self.routeDescription($0, stops: record.stops.count) }

        guard let summary, record.status == .ready || record.status == .insufficientTrack else {
            narration = nil
            return
        }
        narration = Self.narration(
            record: record, summary: summary, start: start, spokenPartner: spokenPartner, place: place,
            comparison: comparison, fullSplits: fullSplits
        )
    }

    // MARK: 讲述（HANDOFF 6.3 第 2 条）

    private static func narration(
        record: RunRecordResponse,
        summary: RunSummary,
        start: Date?,
        spokenPartner: String?,
        place: String?,
        comparison: (verb: String, amount: String)?,
        fullSplits: [RunSplit]
    ) -> String {
        var sentences: [String] = []

        var opening = ""
        if let start {
            opening += longDate.string(from: start) + "，" + period(of: start) + clock(start) + "，"
        }
        opening += "你"
        if let spokenPartner { opening += "和\(spokenPartner)" }
        if let place { opening += "在\(place)" }
        opening += "跑了"
        opening += summary.distanceM.map { "\(RunRecordText.kilometres($0, spoken: true))公里" } ?? "一次"
        let clauses = [
            summary.movingSec.map { "运动时间\(RunRecordText.spokenDuration($0))" },
            summary.avgPaceSecPerKm.map { "平均\(RunRecordText.spokenPace($0))" },
            comparison.map { "比上一次\($0.verb)了\($0.amount)公里" }
        ].compactMap { $0 }
        sentences.append(([opening] + clauses).joined(separator: "，") + "。")

        // 最慢、最快的一公里：满公里至少两段、且两者不是同一段时才说。
        if fullSplits.count >= 2,
           let slowest = fullSplits.max(by: { $0.paceSecPerKm < $1.paceSecPerKm }),
           let fastest = fullSplits.first(where: { $0.index == record.fastestSplitIndex })
            ?? fullSplits.min(by: { $0.paceSecPerKm < $1.paceSecPerKm }),
           slowest.index != fastest.index {
            sentences.append("最慢的是第\(slowest.index)公里，用了\(RunRecordText.spokenDuration(slowest.paceSecPerKm))。")
            sentences.append("第\(fastest.index)公里你跑得最快，\(RunRecordText.spokenDuration(fastest.paceSecPerKm))。")
        }

        // 休息：本期没有地名（P1），按距离说。多于 3 次只报次数和总时长，免得讲述拖太长。
        let stops = record.stops
        let we = spokenPartner == nil ? "你" : "你们"
        if stops.count > 3 {
            let total = stops.reduce(0) { $0 + $1.durationSec }
            sentences.append("途中\(we)休息了\(stops.count)次，一共\(RunRecordText.spokenDuration(total))。")
        } else {
            for stop in stops {
                sentences.append("跑到\(RunRecordText.kilometres(stop.atDistanceM, spoken: true))公里处，\(we)停下来休息了\(RunRecordText.spokenDuration(stop.durationSec))。")
            }
        }

        if let cadence = summary.avgCadence {
            let perSplit = record.splits.compactMap(\.avgCadence)
            if perSplit.count >= 2, let high = perSplit.max(), let low = perSplit.min(), high - low <= steadyCadenceSpread {
                sentences.append("全程步频很稳，平均每分钟\(cadence)步。")
            } else {
                sentences.append("平均步频每分钟\(cadence)步。")
            }
        }

        // 最后读出陪跑员最近一条留言（HANDOFF 6.3 第 2 条）。
        if let note = record.messages.last(where: { $0.fromRole == .volunteer })?.text?.nonEmpty {
            sentences.append("\(spokenPartner ?? "陪跑员")给你留了一句话：\(note)")
        }
        return sentences.joined()
    }

    /// 讲述大约多少秒。中文 TTS 默认语速约每秒 4 个字，按 5 秒取整；用户调快了只会更短。
    static func estimatedSeconds(_ text: String) -> Int {
        max(5, Int((Double(text.count) / 4 / 5).rounded()) * 5)
    }

    // MARK: 路线描述（HANDOFF 6.3 第 6 条，MVP 模板）

    static func routeDescription(_ geometry: RunRouteGeometry, stops: Int) -> String {
        var parts = ["全程 \(RunRecordText.kilometres(geometry.totalMetres, spoken: true)) 公里"]
        parts.append(geometry.startEndCoincide ? "起点和终点在同一处" : "起点和终点不在同一处")
        if let farthest = farthestPoint(geometry) {
            parts.append("最远跑到起点\(farthest.direction)约 \(farthest.kilometres) 公里处")
        }
        parts.append(stops > 0 ? "途中休息\(stops)次" : "途中没有休息")
        return parts.joined(separator: "，") + "。"
    }

    /// 离起点最远的那一点：八个方位 + 百米取整的公里数。不到 100 米不说。
    static func farthestPoint(_ geometry: RunRouteGeometry) -> (direction: String, kilometres: String)? {
        guard let origin = geometry.coordinates.first else { return nil }
        let start = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        let far = geometry.coordinates.max {
            start.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude))
                < start.distance(from: CLLocation(latitude: $1.latitude, longitude: $1.longitude))
        }
        guard let far else { return nil }
        let metres = start.distance(from: CLLocation(latitude: far.latitude, longitude: far.longitude))
        let rounded = Int((metres / 100).rounded()) * 100
        guard rounded >= 100 else { return nil }
        // 小范围内经纬度按平面算：东向要乘 cos(纬度)。0° = 北，顺时针。
        let east = (far.longitude - origin.longitude) * cos(origin.latitude * .pi / 180)
        let north = far.latitude - origin.latitude
        var degrees = atan2(east, north) * 180 / .pi
        if degrees < 0 { degrees += 360 }
        let names = ["正北", "东北", "正东", "东南", "正南", "西南", "正西", "西北"]
        let direction = names[Int((degrees / 45).rounded()) % 8] + "方向"
        return (direction, RunRecordText.kilometres(rounded, spoken: true))
    }

    // MARK: 时间与比较

    private static func comparisonText(_ comparison: RunComparison) -> (verb: String, amount: String) {
        let amount = RunRecordText.kilometres(abs(comparison.deltaDistanceM), spoken: true)
        if comparison.deltaDistanceM > 0 { return ("多跑", amount) }
        if comparison.deltaDistanceM < 0 { return ("少跑", amount) }
        return ("多跑", "0")
    }

    /// HANDOFF 没给切分点：0–5 凌晨、5–9 早上、9–12 上午、12–14 中午、14–18 下午、18–24 晚上。
    static func period(of date: Date) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 0..<5: return "凌晨"
        case 5..<9: return "早上"
        case 9..<12: return "上午"
        case 12..<14: return "中午"
        case 14..<18: return "下午"
        default: return "晚上"
        }
    }

    /// 「6点42分」「3点」（下午三点念 3 点，前面已经有「下午」）。
    static func clock(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        let hour24 = components.hour ?? 0
        let hour = hour24 > 12 ? hour24 - 12 : hour24
        let minute = components.minute ?? 0
        return minute == 0 ? "\(hour)点" : "\(hour)点\(minute)分"
    }

    /// 屏幕：「9月20日 周六早上」
    private static let shortDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEE"
        return formatter
    }()

    /// 朗读：「9月20日星期六早上」
    private static let longDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日EEEE"
        return formatter
    }()
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

// MARK: - Page

struct RunnerRunRecordView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @StateObject private var viewModel: RunRecordViewModel
    @StateObject private var audio = RunRecordAudioController()
    @State private var retryTask: Task<Void, Never>?
    @State private var voiceOverRunning = UIAccessibility.isVoiceOverRunning
    @State private var showsTranscript = false
    @AccessibilityFocusState private var headerFocused: Bool

    /// 与两个按钮的 `accessibilityIdentifier` 字面量一致（焦点移开就暂停靠它认按钮）。
    static let listenID = "runnerRunRecordListen"
    static let soundRouteID = "runnerRunRecordSoundRoute"

    init(orderId: Int64) {
        _viewModel = StateObject(wrappedValue: RunRecordViewModel(orderId: orderId))
    }

    var body: some View {
        content
            .background(AppColors.background)
            .navigationTitle("这次跑步")
            .navigationBarTitleDisplayMode(.inline)
            // 二级页藏标签栏（记忆 tab-bar-clips-the-last-line-of-secondary-pages）。
            .toolbar(.hidden, for: .tabBar)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("runnerRunRecordDetail")
            .task {
                viewModel.configure(with: appState)
                audio.configure(voice: speechService)
                await viewModel.loadUntilSettled()
            }
            // HANDOFF 6.3：VoiceOver 开关变了，地图位置实时跟着换。
            .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.voiceOverStatusDidChangeNotification)) { _ in
                voiceOverRunning = UIAccessibility.isVoiceOverRunning
            }
            .onDisappear {
                retryTask?.cancel()
                audio.stop()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .loading:
            RunRecordLoadingPlaceholder(title: "和林*在深圳湾公园")
        case .failed(let message):
            RunRecordFailedView(message: message, retry: retry)
        case .loaded(let record):
            loaded(record)
        }
    }

    private func retry() {
        retryTask?.cancel()
        retryTask = Task { await viewModel.retry() }
    }

    private func loaded(_ record: RunRecordResponse) -> some View {
        let geometry = record.status == .ready ? record.track.flatMap(RunRouteGeometry.init(track:)) : nil
        let content = RunnerRunRecordContent(record: record, geometry: geometry)
        let sonification = RunRouteSonification(
            samples: record.paceSamples, stops: record.stops, totalMetres: record.summary?.distanceM, geometry: geometry
        )
        return ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                // VoiceOver 关着（多半是低视力）：地图放最上面。高对比样式是 P1，这里先用阶段 4 那张。
                if !voiceOverRunning, let geometry {
                    routeMap(geometry, record: record, height: 300)
                }
                header(content)
                RunRecordStatusNotice(status: record.status, hasMap: geometry != nil, retry: retry)
                if let narration = content.narration {
                    listenBlock(narration)
                }
                if let sonification {
                    soundRouteBlock(sonification)
                }
                if !content.splits.isEmpty {
                    section("每一公里") {
                        VStack(spacing: 0) {
                            ForEach(content.splits, id: \.index) { RunnerSplitRow(row: $0) }
                        }
                    }
                }
                if let geometry, let description = content.routeDescription {
                    section("路线") {
                        if voiceOverRunning {
                            routeMap(geometry, record: record, height: 240)
                        }
                        Text(description)
                            .font(AppFonts.body())
                            .foregroundColor(AppColors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel("路线描述：\(description)")
                            .accessibilityIdentifier("runnerRunRecordRouteDescription")
                    }
                }
                if !content.moreData.isEmpty {
                    section("更多数据") {
                        VStack(spacing: 0) {
                            ForEach(content.moreData, id: \.label) { RunnerDataRow(row: $0) }
                        }
                    }
                }
                orderLink(record.orderId)
            }
            .padding(20)
            .padding(.bottom, 24)
            .readableContentColumn()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: 头部

    private func header(_ content: RunnerRunRecordContent) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let date = content.dateLine {
                Text(date)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textSecondary)
            }
            Text(content.title)
                .font(AppFonts.largeTitle())
                .foregroundColor(AppColors.textPrimary)
            if let distance = content.distanceText {
                RunnerBigDistance(text: distance)
            }
            ForEach(content.facts, id: \.self) { fact in
                Text(fact)
                    .font(AppFonts.title())
                    .foregroundColor(AppColors.textPrimary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.headerLabel)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("runnerRunRecordHeader")
        .accessibilityFocused($headerFocused)
        // 进页面焦点落在头部，往右划一次就到「听这次跑步」（HANDOFF 第 7 节）。
        // 立刻设会被导航转场吃掉，等转场走完再设。
        .task {
            guard voiceOverRunning else { return }
            try? await Task.sleep(nanoseconds: 600_000_000)
            headerFocused = true
        }
    }

    // MARK: 听这次跑步

    private func listenBlock(_ narration: String) -> some View {
        let seconds = RunnerRunRecordContent.estimatedSeconds(narration)
        let title: String
        let spoken: String
        switch audio.state {
        case .playing(.narration): title = "停止讲述"; spoken = "停止讲述"
        case .paused(.narration): title = "继续讲述"; spoken = "继续讲述"
        default: title = "听这次跑步"; spoken = "听这次跑步"
        }
        return VStack(alignment: .leading, spacing: 12) {
            Button {
                showsTranscript = true
                audio.activeControlIdentifier = Self.listenID
                audio.toggleNarration(narration)
            } label: {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(AppFonts.title().weight(.bold))
                        Text("语音讲述，约 \(seconds) 秒")
                            .font(AppFonts.body())
                    }
                    Spacer(minLength: 8)
                    TactileDots()
                        .accessibilityHidden(true)
                }
                .foregroundColor(.black)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(AppColors.tactileYellow))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(spoken)
            .accessibilityHint("语音讲述这次跑步，大约 \(seconds) 秒")
            .accessibilityIdentifier("runnerRunRecordListen")

            if showsTranscript {
                Text(narration)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("文字稿：\(narration)")
                    .accessibilityIdentifier("runnerRunRecordTranscript")
            }
        }
    }

    // MARK: 用声音走一遍路线

    private func soundRouteBlock(_ sonification: RunRouteSonification) -> some View {
        let seconds = Int(sonification.duration.rounded())
        let active = audio.state == .playing(.route) || audio.state == .paused(.route)
        let time = active ? audio.routeTime : 0
        let lit = active ? sonification.barIndex(at: time) : nil
        let title: String
        switch audio.state {
        case .playing(.route): title = "停止"
        case .paused(.route): title = "继续播放"
        case .preparing(.route): title = "正在准备"
        default: title = "播放，约 \(seconds) 秒"
        }
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("用声音走一遍路线")
                    .font(AppFonts.title())
                    .foregroundColor(AppColors.textPrimary)
                Text(Self.soundRouteExplanation)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("用声音走一遍路线。\(Self.soundRouteExplanation)")
            .accessibilityAddTraits(.isHeader)

            RunRouteSoundStrip(sonification: sonification, litIndex: lit)
                .frame(height: 44)
                .accessibilityHidden(true)

            // 只做屏幕文字，不发 VoiceOver 通告：通告会和提示音叠在一起（HANDOFF 6.3 第 3 条）。
            if active, let caption = sonification.caption(at: time) {
                Text(caption)
                    .font(AppFonts.title())
                    .monospacedDigit()
                    .foregroundColor(AppColors.textPrimary)
                    .accessibilityHidden(true)
            }

            Button {
                audio.activeControlIdentifier = Self.soundRouteID
                audio.toggleRoute(sonification)
            } label: {
                Label(title, systemImage: audio.state == .playing(.route) ? "stop.fill" : "play.fill")
                    .font(AppFonts.body().weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: FlowMetrics.actionButtonMinHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(audio.state == .idle ? "播放声音路线，大约 \(seconds) 秒" : "\(title)声音路线")
            .accessibilityIdentifier("runnerRunRecordSoundRoute")
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(AppColors.secondaryBackground))
    }

    static let soundRouteExplanation = "音调越高，跑得越快。声音在左右耳之间移动，跟着路线往东或往西走。每过一公里会响几声，响几声就是第几公里；中途休息时会响一声低音。建议戴耳机。"

    // MARK: 其余

    private func routeMap(_ geometry: RunRouteGeometry, record: RunRecordResponse, height: CGFloat) -> some View {
        RunRecordRouteMap(geometry: geometry, record: record, highlight: nil, bottomInset: 32)
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            // 地图不进无障碍树：路线描述另有文字（遍历顺序跟随绘制顺序，只能 hidden，见 skill aidrun-a11y-voice）。
            .accessibilityHidden(true)
            .accessibilityIdentifier("runnerRunRecordMap")
    }

    private func orderLink(_ orderId: Int64) -> some View {
        // 补评价仍在订单页（负责人 2026-09-25）。
        NavigationLink {
            BlindOrderStatusView(orderId: orderId) { _ in }
        } label: {
            HStack {
                Text("订单详情与评价")
                    .font(AppFonts.body())
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .accessibilityHidden(true)
            }
            .foregroundColor(AppColors.textPrimary)
            .frame(maxWidth: .infinity, minHeight: FlowMetrics.actionButtonMinHeight, alignment: .leading)
            .contentShape(Rectangle())
        }
        .accessibilityHint("查看订单，提交或查看评价")
        .accessibilityIdentifier("runnerRunRecordOrderLink")
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(AppFonts.title())
                .foregroundColor(AppColors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }
}

// MARK: - Pieces

/// 大号距离（HANDOFF 5.2：跑者页约 72pt）。辅助字号下「公里」换行。
private struct RunnerBigDistance: View {
    let text: String
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 72
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 6))
        layout {
            Text(text)
                .font(.system(size: size, weight: .heavy))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text("公里")
                .font(AppFonts.title())
        }
        .foregroundColor(AppColors.textPrimary)
    }
}

/// 盲道提示砖一样的圆点纹理，纯装饰。
private struct TactileDots: View {
    var body: some View {
        Grid(horizontalSpacing: 6, verticalSpacing: 6) {
            ForEach(0..<3, id: \.self) { _ in
                GridRow {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle().fill(Color.black.opacity(0.35)).frame(width: 8, height: 8)
                    }
                }
            }
        }
    }
}

private struct RunnerSplitRow: View {
    let row: RunnerRunRecordContent.SplitRow
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        layout {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(row.title)
                        .font(AppFonts.body().weight(.semibold))
                    if row.isFastest {
                        // 「最快」用文字标签，不只靠颜色（HANDOFF 第 7 节）。
                        Text("最快")
                            .font(AppFonts.caption().weight(.semibold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(AppColors.tactileYellow))
                    }
                }
                if let detail = row.detail {
                    Text(detail)
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.textSecondary)
                }
            }
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
            Text(row.value)
                .font(AppFonts.title())
                .monospacedDigit()
        }
        .foregroundColor(AppColors.textPrimary)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: FlowMetrics.actionButtonMinHeight, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
        .accessibilityIdentifier("runnerRunRecordSplit-\(row.index)")
    }
}

private struct RunnerDataRow: View {
    let row: RunnerRunRecordContent.Row
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        layout {
            Text(row.label)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textPrimary)
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
            Text(row.value)
                .font(AppFonts.body())
                .monospacedDigit()
                .foregroundColor(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: FlowMetrics.actionButtonMinHeight, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
    }
}

/// 每 100 米一根竖条，颜色按配速；播放时已走过的点亮、没走到的变淡。纯装饰（信息在讲述与分段里）。
private struct RunRouteSoundStrip: View {
    let sonification: RunRouteSonification
    let litIndex: Int?
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let bars = sonification.bars
        GeometryReader { proxy in
            let width = proxy.size.width / CGFloat(max(bars.count, 1))
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(Array(bars.enumerated()), id: \.offset) { offset, bar in
                    // 音高反推回 0（快）…1（慢），与地图、分段同一套配色。
                    let fraction = 1 - log2(bar.hz / RunRouteSonification.lowestHz)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color(uiColor: RunPacePalette.color(fraction: fraction, isDark: colorScheme == .dark)))
                        .opacity(litIndex.map { offset <= $0 ? 1 : 0.3 } ?? 1)
                        .frame(width: max(width - 1, 1), height: proxy.size.height * (0.35 + 0.65 * (1 - fraction)))
                        .frame(width: width)
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
}
