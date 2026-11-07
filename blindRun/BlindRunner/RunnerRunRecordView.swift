import CoreLocation
import SwiftUI

// 视障跑者跑后详情（OpenSpec `add-runner-run-record-detail`，HANDOFF 6.3 的 P0 部分，DECISIONS D13）。
// 数据只来自 `RunRecordServing.record(orderId:)`；view model 与陪跑员页共用（`RunRecordViewModel`）。
//
// 这一页**任何地方都不出现 `6'15"`**（HANDOFF 5.3）：屏幕与读屏一律「6分15秒」。
// 11-07 照苹果「健身」重做（#823）：通栏地图 + 头部、指标格、单段表、配速图；「听」两个大按钮换成地图右上两个圆钮，
// VoiceOver 开着时头部后紧跟两个读屏元素（§7：头部右划一次到「听」）。全页不写和谁一起跑（搭档只在留言标题与订单页出现）。
// 没做（P1 / 后续阶段）：分享给家人、休息点地名、留言回复。

// MARK: - Content（纯计算，用例直接钉）

struct RunnerRunRecordContent {
    struct SplitRow: Hashable {
        let index: Int
        let title: String
        let value: String
        let detail: String?
        let isFastest: Bool
        let accessibilityLabel: String
        /// 单段表（照健身）的一行：灰序号 + 累计用时 + 平均配速（「6分12秒」）+ 步频。
        let table: RunRecordSplitTableRow
    }

    /// 两个及以上满公里分段的步频，最大减最小不超过这个数就说「很稳」（HANDOFF 没给阈值）。
    static let steadyCadenceSpread = 5

    let dateLine: String?
    /// 头部：地点、「户外跑步」、距离、「2026年9月24日 05:10–05:32」。
    let place: String?
    let title: String
    let distanceText: String?
    let dateRange: String?
    /// 头部下面一行小数据：比上次多跑 / 中途休息次数，没有值的格不出现。
    let smallStats: [RunRecordSmallStat]
    let headerLabel: String
    /// nil = 没有可讲的（生成中 / 失败），不给「听这次跑步」。
    let narration: String?
    let splits: [SplitRow]
    /// 「详细信息」两列格（照健身）。取代改版前的「更多数据」平铺行；D6 的「陪跑员累计陪跑」11-07 收回（不写和谁一起跑）。
    let metrics: [RunRecordMetric]
    /// nil = 没有路线。
    let routeDescription: String?
    /// 「X的留言」一节（阶段 6）。nil = 陪跑员没留过言，整节不出现。
    let messages: Messages?

    struct Messages: Equatable {
        let title: String
        let spokenTitle: String
        let texts: [String]
        /// 与 `texts` 一一对应的留言本身，举报要用它的 `id`。
        let notes: [RunRecordMessageResponse]
        /// 「朗读留言」念的：「X的留言：」+ 全部陪跑员留言，按先后。
        let readAloud: String
    }

    init(record: RunRecordResponse, geometry: RunRouteGeometry? = nil) {
        let partner = record.volunteerName?.trimmingCharacters(in: .whitespaces).nonEmpty
        let spokenPartner = partner?.unmaskedForSpeech
        let place = record.place?.trimmingCharacters(in: .whitespaces).nonEmpty
        let start = (record.runStartedAt ?? record.service.startedAt)?.backendTimestamp
        let end = record.runEndedAt?.backendTimestamp
        let summary = record.summary

        dateLine = start.map { Self.shortDate.string(from: $0) + Self.period(of: $0) }
        let spokenDate = start.map { Self.longDate.string(from: $0) + Self.period(of: $0) }
        self.place = place
        title = RunRecordFitness.title
        dateRange = RunRecordFitness.dateRange(start: start, end: end)

        distanceText = summary?.distanceM.map { RunRecordText.kilometres($0) }
        let spokenKm = summary?.distanceM.map { RunRecordText.kilometres($0, spoken: true) }
        let comparison = record.comparison.map { Self.comparisonText($0) }

        smallStats = [
            comparison.map {
                RunRecordSmallStat(value: "\($0.amount) 公里", label: "比上次\($0.verb)", spoken: "比上次\($0.verb) \($0.amount) 公里")
            },
            record.stops.isEmpty ? nil : RunRecordSmallStat(
                value: "\(record.stops.count) 次", label: "中途休息", spoken: "中途休息 \(record.stops.count) 次"
            )
        ].compactMap { $0 }

        // 头部整块一个元素（HANDOFF 6.3 第 1 条）。数字与单位之间留空格，审计判「标签不可读」（阶段 3）。
        // 不念和谁一起跑（负责人 11-07）。
        var header = [spokenDate, place.map { "在\($0)跑步" } ?? "跑步"]
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
        let cumulative = RunRecordFitness.cumulativeSeconds(record.splits)
        // 「最快」只留在读屏句里（看不见屏幕的人没法「自己看」）；屏幕上不标（负责人 11-07）。
        splits = zip(record.splits, cumulative).map { split, elapsed in
            let isFull = split.distanceM >= 1000
            let isFastest = split.index == record.fastestSplitIndex
            let cadence = split.avgCadence
            let pace = RunRecordText.spokenDuration(split.paceSecPerKm)
            let elapsedSpoken = "，累计用时\(RunRecordText.spokenDuration(elapsed))"
            let table = { (indexText: String, label: String) in
                RunRecordSplitTableRow(
                    index: split.index, indexText: indexText, elapsedText: RunRecordFitness.splitClock(elapsed),
                    paceText: pace, cadenceText: cadence.map(String.init), accessibilityLabel: label,
                    identifier: "runnerRunRecordSplit-\(split.index)"
                )
            }
            if isFull {
                var label = "第\(split.index)公里，\(pace)"
                if isFastest { label += "，本次最快" }
                if let cadence { label += "，步频每分钟\(cadence)步" }
                label += elapsedSpoken + "。"
                return SplitRow(
                    index: split.index, title: "第 \(split.index) 公里", value: pace,
                    detail: cadence.map { "步频 \($0)" }, isFastest: isFastest, accessibilityLabel: label,
                    table: table("\(split.index)", label)
                )
            }
            let km = RunRecordText.kilometres(split.distanceM, spoken: true)
            let used = RunRecordText.spokenDuration(split.durationSec)
            var label = "最后 \(km) 公里，用时\(used)，折合每公里\(pace)"
            if let cadence { label += "，步频每分钟\(cadence)步" }
            label += elapsedSpoken + "。"
            return SplitRow(
                index: split.index, title: "最后 \(km) 公里", value: used,
                detail: (["折合每公里 \(pace)"] + [cadence.map { "步频 \($0)" }].compactMap { $0 }).joined(separator: "，"),
                isFastest: false, accessibilityLabel: label,
                table: table(RunRecordText.kilometres(split.distanceM), label)
            )
        }

        metrics = RunRecordFitness.detailMetrics(summary: summary, apostrophePace: false)

        routeDescription = geometry.map { Self.routeDescription($0, stops: record.stops.count) }

        let noteMessages = record.messages.filter { $0.fromRole == .volunteer && $0.text?.nonEmpty != nil }
        let notes = noteMessages.compactMap { $0.text?.nonEmpty }
        if notes.isEmpty {
            messages = nil
        } else {
            let spokenTitle = "\(spokenPartner ?? "陪跑员")的留言"
            messages = Messages(
                title: "\(partner ?? "陪跑员")的留言",
                spokenTitle: spokenTitle,
                texts: notes,
                notes: noteMessages,
                readAloud: spokenTitle + "：" + notes.map { "。！？!?.…".contains($0.last!) ? $0 : $0 + "。" }.joined()
            )
        }

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
    @AccessibilityFocusState private var headerFocused: Bool

    /// 与圆钮 / 读屏元素的 `accessibilityIdentifier` 字面量一致（焦点移开就暂停靠它认控件）。
    static let listenID = "runnerRunRecordListen"
    static let readMessagesID = "runnerRunRecordReadMessages"

    init(orderId: Int64) {
        _viewModel = StateObject(wrappedValue: RunRecordViewModel(orderId: orderId))
    }

    var body: some View {
        content
            .background(AppColors.Flow.page.ignoresSafeArea())
            // 标题只给读屏和下一页的返回键；屏幕上不显示，大标题在地图下沿的头部里（照健身）。
            .navigationTitle(RunRecordFitness.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("").accessibilityHidden(true)
                }
            }
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
            RunRecordLoadingPlaceholder(title: RunRecordFitness.title)
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
        // VoiceOver 关着（多半是低视力）：地图固定在页面背后，头部压在它下沿，往上滑地图渐渐模糊（照健身）。
        // VoiceOver 开着：地图挪进「路线」一节并隐藏（HANDOFF 6.3），头部直接在页顶。
        return Group {
            if !voiceOverRunning, let geometry {
                RunRecordMapScrollPage(geometry: geometry, record: record, hasTopButtons: content.narration != nil) {
                    header(content)
                } buttons: {
                    listenButton(content.narration)
                } content: {
                    sections(record, content: content, geometry: geometry)
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 32)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if !voiceOverRunning, content.narration != nil {
                            listenButton(content.narration)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                                .padding(.trailing, 8)
                        }
                        header(content)
                            .padding(.horizontal, 20)
                            .padding(.top, voiceOverRunning || content.narration == nil ? 16 : 0)
                        sections(record, content: content, geometry: geometry)
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            .padding(.bottom, 32)
                    }
                    .readableContentColumn()
                }
            }
        }
    }

    private func sections(_ record: RunRecordResponse, content: RunnerRunRecordContent, geometry: RunRouteGeometry?) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            listenSections(record, content: content, geometry: geometry)
            dataSections(record, content: content)
            if let messages = content.messages {
                messagesBlock(messages)
            }
            tailSections(record, content: content, geometry: geometry)
        }
    }

    /// 读屏元素紧跟头部：进页面焦点在头部，往右划一次就到「听这次跑步」（HANDOFF 第 7 节）。
    /// 然后是无路线提示（在「听」之后，§7 第 2 条）。讲述只出声，不显示文字稿（负责人 11-07 第二轮第 1 条）。
    @ViewBuilder
    private func listenSections(_ record: RunRecordResponse, content: RunnerRunRecordContent, geometry: RunRouteGeometry?) -> some View {
        if voiceOverRunning, let narration = content.narration {
            voiceOverListen(narration)
        }
        RunRecordStatusNotice(status: record.status, hasMap: geometry != nil, retry: retry)
    }

    /// 小数据行、「详细信息」两列格、「单段」表、「配速」图。
    @ViewBuilder
    private func dataSections(_ record: RunRecordResponse, content: RunnerRunRecordContent) -> some View {
        if !content.smallStats.isEmpty {
            RunRecordSmallStatsRow(stats: content.smallStats)
                .padding(.horizontal, 4)
        }
        if !content.metrics.isEmpty {
            RunRecordSectionTitle(text: "详细信息").padding(.top, 8)
            RunRecordMetricGrid(metrics: content.metrics)
        }
        if !content.splits.isEmpty {
            RunRecordSectionTitle(text: "单段").padding(.top, 8)
            RunRecordSplitTable(rows: content.splits.map(\.table))
        }
        if record.paceSamples.count >= 2, let scale = RunPaceScale(samples: record.paceSamples) {
            RunRecordSectionTitle(text: "配速").padding(.top, 8)
            RunPaceChart(
                samples: record.paceSamples, average: record.summary?.avgPaceSecPerKm, stops: record.stops,
                fastestKilometre: record.fastestSplitIndex, scale: scale, apostrophePace: false
            )
        }
    }

    /// 「路线」（VoiceOver 开着时地图在这里）、「订单详情与评价」、举报与拉黑。
    @ViewBuilder
    private func tailSections(_ record: RunRecordResponse, content: RunnerRunRecordContent, geometry: RunRouteGeometry?) -> some View {
        if let geometry, let description = content.routeDescription {
            RunRecordSectionTitle(text: "路线").padding(.top, 8)
            RunRecordCard {
                if voiceOverRunning {
                    routeMap(geometry, record: record, height: 240)
                        .padding(.bottom, 12)
                }
                Text(description)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("路线描述：\(description)")
                    .accessibilityIdentifier("runnerRunRecordRouteDescription")
            }
        }
        orderLink(record.orderId)
            .padding(.top, 8)
        if let target = viewModel.counterpartTarget {
            CounterpartSafetyActions(target: target)
        }
    }

    // MARK: 头部

    private func header(_ content: RunnerRunRecordContent) -> some View {
        RunRecordHeroHeader(place: content.place, distanceText: content.distanceText, dateRange: content.dateRange)
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

}

// 拆出来只是因为结构体正文超过 SwiftLint 上限（棘轮只许变小）；同一个文件，私有成员照常可见。
extension RunnerRunRecordView {
    // MARK: 听这次跑步

    private var listenTitle: String {
        switch audio.state {
        case .playing(.narration): return "停止讲述"
        case .paused(.narration): return "继续讲述"
        default: return "听这次跑步"
        }
    }

    private func toggleListen(_ narration: String) {
        audio.activeControlIdentifier = Self.listenID
        audio.toggleSpeech(narration)
    }

    /// 地图右上的圆钮（负责人 11-07 第 3 条：去掉页面里的大按钮）。
    /// 第二轮去掉了旁边的「声音路线」圆钮：音调听着像防空警报（负责人 11-07 第二轮第 2 条）。
    @ViewBuilder
    private func listenButton(_ narration: String?) -> some View {
        if let narration {
            RunRecordMapCircleButton(
                systemImage: audio.state == .playing(.narration) ? "stop.fill" : "speaker.wave.2.fill",
                accessibilityLabel: listenTitle,
                accessibilityHint: "语音讲述这次跑步，大约 \(RunnerRunRecordContent.estimatedSeconds(narration)) 秒",
                identifier: Self.listenID,
                isActive: audio.state == .playing(.narration)
            ) { toggleListen(narration) }
        }
    }

    /// VoiceOver 开着时紧跟头部的「听这次跑步」：只进无障碍树，看得见的人看不到（负责人 11-07 选「右上圆钮 + 读屏保留」）。
    private func voiceOverListen(_ narration: String) -> some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: 1)
            .accessibilityElement()
            .accessibilityLabel(listenTitle)
            .accessibilityHint("语音讲述这次跑步，大约 \(RunnerRunRecordContent.estimatedSeconds(narration)) 秒")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { toggleListen(narration) }
            .accessibilityIdentifier(Self.listenID)
    }

    // MARK: X的留言（阶段 6）

    /// P0 没有「回复」：语音回复是 P1，文字回复没人要（负责人 2026-09-25）。
    /// 「朗读留言」11-07 从大按钮改成每条留言上的读屏自定义操作（负责人选「右上圆钮 + 读屏保留」）。
    private func messagesBlock(_ messages: RunnerRunRecordContent.Messages) -> some View {
        let reading = audio.state == .playing(.message)
        let actionName = reading ? "停止朗读" : (audio.state == .paused(.message) ? "继续朗读" : "朗读留言")
        return VStack(alignment: .leading, spacing: 12) {
            RunRecordSectionTitle(text: messages.title, spoken: messages.spokenTitle)
                .padding(.top, 8)
            RunRecordCard {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(messages.notes, id: \.id) { note in
                        Text(note.text ?? "")
                            .font(AppFonts.body())
                            .foregroundColor(AppColors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityAction(named: Text(actionName)) {
                                audio.activeControlIdentifier = Self.readMessagesID
                                audio.toggleSpeech(messages.readAloud, as: .message)
                            }
                            // 每条留言挂同一个 identifier：焦点在留言之间移动不算「离开」，朗读不暂停（`focusMoved` 按它认控件）。
                            .accessibilityIdentifier(Self.readMessagesID)
                        if let target = CounterpartSafetyGate.messageTarget(
                            messageId: note.id,
                            fromRole: note.fromRole,
                            text: note.text,
                            viewerRole: .blind,
                            counterpart: viewModel.counterpartTarget
                        ) {
                            MessageReportButton(target: target)
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("runnerRunRecordMessages")
    }

    // MARK: 其余

    private func routeMap(_ geometry: RunRouteGeometry, record: RunRecordResponse, height: CGFloat) -> some View {
        RunRecordRouteMap(
            geometry: geometry, record: record, highlight: nil,
            edgePadding: UIEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        )
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        // 地图不进无障碍树：路线描述另有文字（遍历顺序跟随绘制顺序，只能 hidden，见 skill aidrun-a11y-voice）。
        .accessibilityHidden(true)
        .accessibilityIdentifier("runnerRunRecordMap")
    }

    private func orderLink(_ orderId: Int64) -> some View {
        // 补评价仍在订单页（负责人 2026-09-25）。
        NavigationLink {
            BlindOrderStatusView(orderId: orderId) { _ in }
        } label: {
            RunRecordCard {
                HStack {
                    Text("订单详情与评价")
                        .font(AppFonts.body())
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .foregroundColor(AppColors.textSecondary)
                        .accessibilityHidden(true)
                }
                .foregroundColor(AppColors.textPrimary)
                .frame(maxWidth: .infinity, minHeight: FlowMetrics.actionButtonMinHeight - 32, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("查看订单，提交或查看评价")
        .accessibilityIdentifier("runnerRunRecordOrderLink")
    }
}
