import Combine
import CoreLocation
import SwiftUI

// 陪跑员跑后详情（OpenSpec `add-volunteer-run-record-detail`，HANDOFF 6.2 的 P0 部分，DECISIONS D13）。
// 数据只来自 `RunRecordServing.record(orderId:)`。并发只用 async/await。
//
// 11-07 照苹果「健身」重做（#823），与跑者页同一套组件（`RunRecordFitnessComponents.swift`）：通栏地图 + 头部、
// 指标格、单段表、配速图；标题「户外跑步」，全页不写和谁一起跑（跑者只在留言里出现）；留言输入区样式不动，只进卡片。
// 没做（P1 / 后续阶段）：轨迹回放、配速图拖动与地图联动。留言输入是阶段 6（OpenSpec `add-run-record-messages`）。

// MARK: - Content（纯计算，用例直接钉）

struct VolunteerRunRecordContent {
    struct TimelineEntry: Hashable {
        let time: String
        let text: String
        let accessibilityLabel: String
    }

    struct SplitRow: Hashable {
        let index: Int
        let kilometreText: String
        let paceText: String
        let cadenceText: String?
        let isFastest: Bool
        /// 条长：本段速度 ÷ 最快一段的速度。
        let barFraction: Double
        /// 条的颜色位置，0 = 快、1 = 慢。
        let paceFraction: Double
        let bubbleText: String
        let accessibilityLabel: String
        /// 单段表（照健身）的一行：灰序号 + 累计用时 + 平均配速 + 步频。
        let table: RunRecordSplitTableRow
    }

    struct Message: Hashable {
        let id: Int64
        let fromRole: RunRecordRole
        let header: String
        let text: String
        let accessibilityLabel: String
    }

    let title: String
    let spokenTitle: String
    let place: String?
    /// 「2026年9月24日 05:10–05:32」。
    let dateRange: String?
    let spokenDateRange: String?
    let distanceText: String?
    let spokenDistance: String?
    /// 「详细信息」两列格（照健身）。取代改版前的两行三列数字。
    let metrics: [RunRecordMetric]
    let serviceText: String?
    /// 「23 分钟」：小数据行的值（`serviceText` 去掉「志愿服务」）。
    let serviceDuration: String?
    let serviceRange: String?
    let timeline: [TimelineEntry]
    let sosLine: String
    let mapDescription: String
    let splits: [SplitRow]
    let showsCadenceColumn: Bool
    let messages: [Message]
    /// 「给X留句话」。nil = 跑者已注销（`blindName` 为 null），不给输入框。
    let composerTitle: String?
    let spokenComposerTitle: String?
    /// 发送成功后那句。原型是「X打开这条记录时会听到」—— 跑者页不会自动念，改成这句（负责人 2026-09-25）。
    let sentConfirmation: String
    let spokenSentConfirmation: String
    /// 发送按钮的读屏提示（原型 data-vo「老陈会在他的记录里听到这句话」，按阶段 6 的确认句改）。
    let spokenSendHint: String

    /// 原型的三个快捷短语，点一下把输入框换成「短语。」。
    static let quickPhrases = ["节奏很稳", "下次可以再快一点", "折返配合得很好"]
    static let partnerGoneNotice = "对方已注销账号，留言无法送达。"

    /// `messages` 传 view model 合并过的（含本页刚发出的），不传就用记录里的。
    init(record: RunRecordResponse, geometry: RunRouteGeometry? = nil, messages allMessages: [RunRecordMessageResponse]? = nil) {
        let name = record.blindName?.trimmingCharacters(in: .whitespaces)
        // 负责人 11-07：不写和谁一起跑（「就只要记录跑步了就可以了」）。跑者的名字只在留言里出现。
        title = RunRecordFitness.title
        spokenTitle = title
        place = record.place?.trimmingCharacters(in: .whitespaces).nilIfEmpty

        let start = (record.runStartedAt ?? record.service.startedAt)?.backendTimestamp
        let end = record.runEndedAt?.backendTimestamp
        dateRange = RunRecordFitness.dateRange(start: start, end: end)
        spokenDateRange = RunRecordFitness.spokenDateRange(start: start, end: end)

        let summary = record.summary
        distanceText = summary?.distanceM.map { RunRecordText.kilometres($0) }
        spokenDistance = summary?.distanceM.map { RunRecordText.kilometres($0, spoken: true) }

        // 没有数据是 null：对应一格整格不出现，不写 0（HANDOFF 6.4）。
        metrics = RunRecordFitness.detailMetrics(summary: summary, apostrophePace: true)

        // D5：没有「待确认」之类的状态。
        serviceDuration = record.service.durationMin.map { RunRecordHistoryViewModel.serviceDuration(Int64($0)) }
        serviceText = serviceDuration.map { "志愿服务 \($0)" }
        let serviceStart = record.service.startedAt?.backendTimestamp.map(DateFormatter.aidRunDisplayClockPadded.string(from:))
        let serviceEnd = record.service.completedAt?.backendTimestamp.map(DateFormatter.aidRunDisplayClockPadded.string(from:))
        serviceRange = serviceStart.flatMap { s in serviceEnd.map { "\(s)–\($0)" } }

        timeline = record.events.map { Self.timelineEntry($0) }
        sosLine = record.sosTriggered ? "此订单触发过紧急求助" : "全程没有触发紧急求助"

        mapDescription = Self.spokenMapDescription(record: record, spokenDistance: spokenDistance, geometry: geometry)
        let scale = RunPaceScale(samples: record.paceSamples)

        let fastestPace = record.splits.map(\.paceSecPerKm).filter { $0 > 0 }.min()
        showsCadenceColumn = record.splits.contains { $0.avgCadence != nil }
        let cumulative = RunRecordFitness.cumulativeSeconds(record.splits)
        splits = zip(record.splits, cumulative).map { split, elapsed in
            let isFull = split.distanceM >= 1000
            let kilometre = isFull ? "\(split.index)" : RunRecordText.kilometres(split.distanceM)
            // 小数和单位之间留空格：「0.2公里」会被审计判成标签不可读（阶段 3 同一条）。
            let spokenKilometre = isFull ? "第\(split.index)公里" : "最后 \(RunRecordText.kilometres(split.distanceM, spoken: true)) 公里"
            let isFastest = split.index == record.fastestSplitIndex
            var label = "\(spokenKilometre)，\(RunRecordText.spokenPace(split.paceSecPerKm))"
            if let cadence = split.avgCadence { label += "，步频每分钟\(cadence)步" }
            // 「最快」只留在读屏句里（看不见屏幕的人没法「自己看」）；屏幕上不标（负责人 11-07）。
            if isFastest { label += "，最快" }
            label += "，累计用时\(RunRecordText.spokenDuration(elapsed))"
            return SplitRow(
                index: split.index,
                kilometreText: kilometre,
                paceText: RunRecordText.pace(split.paceSecPerKm),
                cadenceText: split.avgCadence.map(String.init),
                isFastest: isFastest,
                barFraction: fastestPace.map { split.paceSecPerKm > 0 ? Double($0) / Double(split.paceSecPerKm) : 0 } ?? 0,
                paceFraction: scale?.fraction(split.paceSecPerKm) ?? 0,
                bubbleText: "\(isFull ? "第\(split.index)公里" : "最后\(kilometre)公里") \(RunRecordText.pace(split.paceSecPerKm))",
                accessibilityLabel: label,
                table: RunRecordSplitTableRow(
                    index: split.index, indexText: kilometre, elapsedText: RunRecordFitness.splitClock(elapsed),
                    paceText: RunRecordText.pace(split.paceSecPerKm), cadenceText: split.avgCadence.map(String.init),
                    accessibilityLabel: label, identifier: "runRecordSplit-\(split.index)"
                )
            )
        }

        let partner = name?.nilIfEmpty
        composerTitle = partner.map { "给\($0)留句话" }
        spokenComposerTitle = partner.map { "给\($0.unmaskedForSpeech)留句话" }
        sentConfirmation = "已发送。\(partner ?? "对方")在这条跑步记录里可以听到这句话。"
        spokenSentConfirmation = "已发送。\(partner?.unmaskedForSpeech ?? "对方")在这条跑步记录里可以听到这句话。"
        spokenSendHint = "\(partner?.unmaskedForSpeech ?? "对方")在这条跑步记录里可以听到这句话"

        messages = (allMessages ?? record.messages).compactMap { message in
            guard let text = message.text, !text.isEmpty else { return nil }
            let from: (shown: String, spoken: String)
            switch message.fromRole {
            case .volunteer: from = ("我", "我")
            case .blind: from = (name ?? "跑者", name?.unmaskedForSpeech ?? "跑者")
            case .unknown: from = ("对方", "对方")
            }
            let time = message.createdAt.backendTimestamp.map(Self.dateTimeFormatter.string(from:))
            return Message(
                id: message.id,
                fromRole: message.fromRole,
                header: [from.shown, time].compactMap { $0 }.joined(separator: " · "),
                text: text,
                accessibilityLabel: "\(from.spoken)说：\(text)"
            )
        }
    }

    private static func timelineEntry(_ event: RunEvent) -> TimelineEntry {
        let clock = event.at.backendTimestamp.map(DateFormatter.aidRunDisplayClockPadded.string(from:)) ?? ""
        // 由轨迹推算的时刻（REST、RUN_ENDED）标「约」，不冒充订单日志里的真实时刻。
        let time = event.inferred ? "约\(clock)" : clock
        let text: String
        let spoken: String
        switch event.type {
        case .arrived: text = "到达会合点"; spoken = text
        case .runStarted: text = "开始服务"; spoken = text
        case .rest:
            text = event.durationSec.map { "休息 \(RunRecordText.clock($0))" } ?? "休息"
            spoken = event.durationSec.map { "休息\(RunRecordText.spokenDuration($0))" } ?? "休息"
        case .runEnded: text = "跑步结束"; spoken = text
        case .orderCompleted: text = "订单完成"; spoken = text
        }
        return TimelineEntry(time: time, text: text, accessibilityLabel: "\(time)，\(spoken)")
    }

    /// 「7月21日 周二 08:00」。
    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEE HH:mm"
        return formatter
    }()
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

// MARK: - Page

struct VolunteerRunRecordView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @StateObject private var viewModel: RunRecordViewModel
    @State private var highlightedSplit: Int?
    /// 留言草稿。发成功才清空；没发出去原样留着。
    @State private var draft = ""
    @FocusState private var draftFocused: Bool
    /// 「重试」起的任务。`.task` 那条随页面取消，这条要自己管：离开页面时还在 GENERATING 就会一直轮询，
    /// 连点两下会起两个并行的轮询。
    @State private var retryTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let topID = "runRecordTop"

    init(orderId: Int64) {
        _viewModel = StateObject(wrappedValue: RunRecordViewModel(orderId: orderId))
    }

    var body: some View {
        content
            .background(AppColors.Flow.page.ignoresSafeArea())
            // 标题只给读屏和下一页的返回键；屏幕上不显示，大标题在地图下沿的头部里（照健身）。
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("").accessibilityHidden(true)
                }
            }
            // 二级页藏标签栏：悬浮胶囊会盖住最后一行（记忆 tab-bar-clips-the-last-line-of-secondary-pages）。
            // 这一页是 push 进来的，返回箭头一直在。
            .toolbar(.hidden, for: .tabBar)
            // `children: .contain` 不能省：容器上的 identifier 会向下覆盖子元素（记忆 accessibility-identifier-overwrites-children）。
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("volunteerRunRecordDetail")
            .task {
                viewModel.configure(with: appState, speech: speechService)
                await viewModel.loadUntilSettled()
            }
            .onDisappear { retryTask?.cancel() }
    }

    private var navigationTitle: String {
        if let record = viewModel.phase.value {
            return VolunteerRunRecordContent(record: record).navigationTitle.spoken
        }
        return "跑后记录"
    }

    /// 加载中与失败只是一小块，放在页顶并留边距；记录读到后整页交给 `loaded`。
    private var content: some View {
        RemoteContent(
            viewModel.phase,
            loadingLabel: "正在加载跑步记录",
            failureIdentifier: "runRecordRetry",
            retry: retry
        ) { record in
            loaded(record)
        }
        .padding(viewModel.phase.value == nil ? 20 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func loaded(_ record: RunRecordResponse) -> some View {
        let geometry = record.status == .ready ? record.track.flatMap(RunRouteGeometry.init(track:)) : nil
        let content = VolunteerRunRecordContent(record: record, geometry: geometry, messages: viewModel.messages(of: record))
        return ScrollViewReader { scroll in
            let onSelectSplit: ((Int) -> Void)? = geometry == nil ? nil : { select($0, scroll: scroll) }
            if let geometry {
                // 地图固定在页面背后，往上滑渐渐模糊（照健身，负责人 11-07 第二轮第 5 条）。
                RunRecordMapScrollPage(
                    geometry: geometry,
                    record: record,
                    highlight: highlightedSplit.flatMap { index in content.splits.first { $0.index == index } },
                    mapAccessibilityLabel: content.mapDescription,
                    topID: Self.topID
                ) {
                    header(content)
                } content: {
                    sections(record, content, onSelectSplit: onSelectSplit)
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        // 滚到底时最后一行别贴着 Home 条。
                        .padding(.bottom, 32)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        header(content)
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                        sections(record, content, onSelectSplit: onSelectSplit)
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            .padding(.bottom, 32)
                    }
                    .readableContentColumn()
                }
            }
        }
    }

    private func select(_ index: Int, scroll: ScrollViewProxy) {
        highlightedSplit = index
        withAnimation(reduceMotion ? nil : .easeInOut) {
            scroll.scrollTo(Self.topID, anchor: .top)
        }
    }

    // MARK: 头部

    /// 一整句读屏：「户外跑步，3.2 公里，2026年9月24日 05:10到05:32，奥林匹克森林公园」。
    /// identifier 沿用改版前距离那一格的 `runRecordDistance`（UI 用例按它等页面加载完）。
    private func header(_ content: VolunteerRunRecordContent) -> some View {
        RunRecordHeroHeader(place: content.place, distanceText: content.distanceText, dateRange: content.dateRange)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                [content.spokenTitle, content.spokenDistance.map { "\($0) 公里" }, content.spokenDateRange, content.place]
                    .compactMap { $0 }
                    .joined(separator: "，")
            )
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("runRecordDistance")
    }

    // MARK: Sections

    private func sections(
        _ record: RunRecordResponse,
        _ content: VolunteerRunRecordContent,
        onSelectSplit: ((Int) -> Void)?
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            RunRecordStatusNotice(status: record.status, hasMap: onSelectSplit != nil, retry: retry)
            if let service = content.serviceText, let duration = content.serviceDuration {
                serviceRow(service, duration: duration, range: content.serviceRange, stops: record.stops.count)
            }
            if !content.metrics.isEmpty {
                RunRecordSectionTitle(text: "详细信息").padding(.top, 8)
                RunRecordMetricGrid(metrics: content.metrics)
            }
            if !content.splits.isEmpty {
                RunRecordSectionTitle(text: "单段").padding(.top, 8)
                RunRecordSplitTable(rows: content.splits.map(\.table), selected: highlightedSplit, onSelect: onSelectSplit)
            }
            if record.paceSamples.count >= 2, let scale = RunPaceScale(samples: record.paceSamples) {
                RunRecordSectionTitle(text: "配速").padding(.top, 8)
                RunPaceChart(
                    samples: record.paceSamples, average: record.summary?.avgPaceSecPerKm, stops: record.stops,
                    fastestKilometre: record.fastestSplitIndex, scale: scale
                )
            }
            RunRecordSectionTitle(text: "途中记录").padding(.top, 8)
            RunRecordCard {
                RunTimeline(entries: content.timeline, sosLine: content.sosLine)
            }
            if !content.messages.isEmpty {
                RunRecordSectionTitle(text: "留言").padding(.top, 8)
                RunRecordCard {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(content.messages, id: \.self) { message in
                            messageRow(message, viewerRole: record.viewerRole)
                        }
                    }
                }
            }
            RunRecordCard {
                composer(content)
            }
            .padding(.top, 8)
            if let target = viewModel.counterpartTarget {
                CounterpartSafetyActions(target: target)
            }
        }
    }

    @ViewBuilder
    private func messageRow(_ message: VolunteerRunRecordContent.Message, viewerRole: RunRecordRole) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(message.header)
                .font(AppFonts.caption())
                .foregroundColor(AppColors.textSecondary)
            Text(message.text)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(message.accessibilityLabel)
        if let target = CounterpartSafetyGate.messageTarget(
            messageId: message.id,
            fromRole: message.fromRole,
            text: message.text,
            viewerRole: viewerRole,
            counterpart: viewModel.counterpartTarget
        ) {
            MessageReportButton(target: target)
        }
    }

    private func retry() {
        retryTask?.cancel()
        retryTask = Task { await viewModel.retry() }
    }

    // MARK: 给X留句话（阶段 6，HANDOFF 6.2 第 9 条）

    @ViewBuilder
    private func composer(_ content: VolunteerRunRecordContent) -> some View {
        if let title = content.composerTitle, let spokenTitle = content.spokenComposerTitle {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(AppFonts.title())
                    .foregroundColor(AppColors.textPrimary)
                    .accessibilityLabel(spokenTitle)
                    .accessibilityAddTraits(.isHeader)
                TextField("写一句话", text: $draft, axis: .vertical)
                    .lineLimit(3...6)
                    .font(AppFonts.body())
                    .focused($draftFocused)
                    .padding(12)
                    .frame(minHeight: FlowMetrics.infoRowTappableMinHeight, alignment: .topLeading)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(AppColors.secondaryBackground))
                    .accessibilityLabel("留言输入框")
                    .accessibilityIdentifier("runRecordMessageField")
                    // 发成功后清空草稿也会走到这里，空串不收「已发送」。
                    .onChange(of: draft) { if !$0.isEmpty { viewModel.clearSendOutcome() } }
                characterCount
                quickPhrases
                sendButton(content)
                sendOutcome(content)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("runRecordMessageComposer")
        } else {
            Text(VolunteerRunRecordContent.partnerGoneNotice)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("runRecordMessagePartnerGone")
        }
    }

    private var characterCount: some View {
        let count = draft.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count
        let max = RunRecordViewModel.messageMaxLength
        return Text("\(count)/\(max)")
            .font(AppFonts.caption())
            .monospacedDigit()
            .foregroundColor(count > max ? AppColors.destructive : AppColors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .accessibilityLabel(count > max ? "超出 \(count - max) 个字，最多 \(max) 个字" : "已写 \(count) 个字，最多 \(max) 个字")
    }

    /// 放得下就一行，放不下（大字号）就竖排。只在横向上选，竖向 ViewThatFits 会让字号审计误判
    /// （记忆 viewthatfits-fails-dynamic-type-audit）。
    private var quickPhrases: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { quickPhraseButtons }
            VStack(alignment: .leading, spacing: 8) { quickPhraseButtons }
        }
    }

    private var quickPhraseButtons: some View {
        ForEach(VolunteerRunRecordContent.quickPhrases, id: \.self) { phrase in
            Button {
                draft = phrase + "。"
            } label: {
                // 不能 `.fixedSize()`：最大字号下不折行会把整个输入区撑出屏幕（2026-09-25 截图）。
                Text(phrase)
                    .font(AppFonts.body())
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 14)
                    .frame(minHeight: FlowMetrics.infoRowTappableMinHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(OutlineSecondaryButtonStyle(fillsWidth: false))
            .accessibilityLabel("快捷短语：\(phrase)")
            .accessibilityHint("填进输入框")
        }
    }

    private func sendButton(_ content: VolunteerRunRecordContent) -> some View {
        let sending = viewModel.sendState == .sending
        return Button {
            draftFocused = false
            let submitted = draft
            Task {
                guard await viewModel.send(submitted) else { return }
                // 发送途中又改过草稿就不清：清掉的会是还没发的字。
                if draft == submitted { draft = "" }
                speechService.announce(content.spokenSentConfirmation)
            }
        } label: {
            HStack(spacing: 8) {
                if sending { ProgressView().tint(AppColors.background) }
                Text(sending ? "正在发送" : "发送")
                    .font(AppFonts.body().weight(.semibold))
            }
            .foregroundColor(AppColors.background)
            .frame(maxWidth: .infinity, minHeight: FlowMetrics.actionButtonMinHeight)
            .background(Capsule().fill(AppColors.Flow.tabSelected))
            .opacity(sending ? 0.6 : 1)
            .contentShape(Rectangle())
        }
        // 不用 `.borderedProminent`：tab 容器把 tint 设成 `tabSelected`（深色 = 纯白），
        // 那个 style 的字恒为白 ⇒ 深色下白底白字（2026-09-25 截图）。填充与字色显式成对给。
        .buttonStyle(.plain)
        .disabled(sending)
        .accessibilityLabel(sending ? "正在发送留言" : "发送留言")
        .accessibilityHint(content.spokenSendHint)
        .accessibilityIdentifier("runRecordMessageSend")
    }

    @ViewBuilder
    private func sendOutcome(_ content: VolunteerRunRecordContent) -> some View {
        switch viewModel.sendState {
        case .sent:
            Text(content.sentConfirmation)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(content.spokenSentConfirmation)
                .accessibilityIdentifier("runRecordMessageSent")
        case .failed(let reason):
            Text(reason)
                .font(AppFonts.body())
                .foregroundColor(AppColors.destructive)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("runRecordMessageFailed")
        case .idle, .sending:
            EmptyView()
        }
    }

    /// 头部下面一行小数据（照健身的天气行）：志愿服务时长、中途休息次数。D5：没有「待确认」之类的状态。
    private func serviceRow(_ text: String, duration: String, range: String?, stops: Int) -> some View {
        var stats = [RunRecordSmallStat(
            value: duration,
            label: "志愿服务",
            spoken: [text, range.map { $0.replacingOccurrences(of: "–", with: "到") }].compactMap { $0 }.joined(separator: "，")
        )]
        if stops > 0 {
            stats.append(RunRecordSmallStat(value: "\(stops) 次", label: "中途休息", spoken: "中途休息 \(stops) 次"))
        }
        return RunRecordSmallStatsRow(stats: stats)
            .padding(.horizontal, 4)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("runRecordServiceRow")
    }
}

// MARK: - Pieces

// MARK: 状态（两个角色的详情页共用，HANDOFF 6.4）
// 页面级的加载中 / 失败走 `RemoteContent`（#863）。

/// 生成中 / 失败 / 不认识的状态 / 没有路线。READY 且有地图时什么都不画。
struct RunRecordStatusNotice: View {
    let status: RunRecordStatus
    let hasMap: Bool
    let retry: () -> Void

    var body: some View {
        switch status {
        case .generating:
            HStack(spacing: 12) {
                ProgressView()
                Text("记录正在生成，大约 1 分钟后可以查看")
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textPrimary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("runRecordGenerating")
        case .failed, .unknown:
            // 和页面级失败同一套：会念出来（#863）。
            IncentiveFailureSection(
                message: status == .failed ? "记录生成失败。" : "这条记录暂时无法显示。",
                retryTitle: "重试",
                identifier: "runRecordRetry",
                retry: retry
            )
        case .ready, .insufficientTrack:
            if !hasMap {
                Text("这次没有记录到完整路线")
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textSecondary)
                    .accessibilityIdentifier("runRecordNoRoute")
            }
        }
    }
}

private struct RunTimeline: View {
    let entries: [VolunteerRunRecordContent.TimelineEntry]
    let sosLine: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // 辅助字号下时间放在事件上面，「约 08:09」才不会被挤成两截。
        let row = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        VStack(alignment: .leading, spacing: 12) {
            ForEach(entries, id: \.self) { entry in
                row {
                    Text(entry.time)
                        .font(AppFonts.body())
                        .monospacedDigit()
                        .foregroundColor(AppColors.textSecondary)
                        .frame(minWidth: 72, alignment: .leading)
                    Text(entry.text)
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.textPrimary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(entry.accessibilityLabel)
            }
            Label(sosLine, systemImage: "checkmark.shield")
                .font(AppFonts.body())
                .foregroundColor(AppColors.textSecondary)
                .labelStyle(DecorativeIconLabelStyle())
                .accessibilityIdentifier("runRecordSOSLine")
        }
    }
}

/// 图标只做装饰：读屏只念文字。
private struct DecorativeIconLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            configuration.icon.accessibilityHidden(true)
            configuration.title
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Route Map

/// 描边 + 配速线 + 公里标记 + 起终点 + 休息点 + 高亮那一公里。整张图对读屏是装饰（描述挂在页面上）。
/// 两端详情页固定在背后的地图（`RunRecordMapScrollPage`）与跑者端「路线」一节都用它，跑者端 `highlight` 传 nil。
/// 底图降饱和（#823 第 10 条）；配速图例挪到「配速」卡里（左上角现在是返回键）。
struct RunRecordRouteMap: View {
    let geometry: RunRouteGeometry
    let record: RunRecordResponse
    let highlight: VolunteerRunRecordContent.SplitRow?
    /// 路线的取景框：四边让开返回键、右上圆钮、头部（#823 第 11 条）。
    let edgePadding: UIEdgeInsets

    var body: some View {
        MapViewWrapper(
            centerCoordinate: center,
            showsUserLocation: false,
            annotations: annotations,
            polylines: polylines,
            tracksUserLocation: false,
            animatesCenterChanges: false,
            fitEdgePadding: edgePadding,
            isDecorative: true,
            mutedBasemap: true
        )
    }

    private var center: CLLocationCoordinate2D {
        let lats = geometry.coordinates.map(\.latitude)
        let lngs = geometry.coordinates.map(\.longitude)
        return CLLocationCoordinate2D(
            latitude: ((lats.min() ?? 0) + (lats.max() ?? 0)) / 2,
            longitude: ((lngs.min() ?? 0) + (lngs.max() ?? 0)) / 2
        )
    }

    private var polylines: [MapPolylineItem] {
        // 没有配速采样时整条画成「快」那一档的单色。
        let noPace: (indexes: [Int], fractions: [Double]) = ([], [0])
        let pace = RunPaceScale(samples: record.paceSamples).map { geometry.paceStyle(samples: record.paceSamples, scale: $0) } ?? noPace
        var items = [MapPolylineItem(id: "run-outline", coordinates: geometry.coordinates, isPrimary: true, routeStyle: .outline)]
        if let highlight {
            items.append(MapPolylineItem(id: "run-highlight", coordinates: geometry.segment(index: highlight.index), routeStyle: .highlight))
        }
        items.append(MapPolylineItem(
            id: "run-pace",
            coordinates: geometry.coordinates,
            routeStyle: .pace(indexes: pace.indexes, fractions: pace.fractions)
        ))
        return items
    }

    private var annotations: [MapAnnotationItem] {
        var items: [MapAnnotationItem] = []
        // 起点绿点、终点红点照健身（#823 第 10 条）；重合时红点压在绿点上，两个都露一半。
        // 「起点和终点在不在同一处」读屏从地图描述 / 路线描述里听到。
        if let first = geometry.coordinates.first, let last = geometry.coordinates.last {
            items.append(MapAnnotationItem(id: "run-start", coordinate: first, title: nil, subtitle: nil, kind: .runEndpoint(isStart: true, compact: false)))
            items.append(MapAnnotationItem(id: "run-end", coordinate: last, title: nil, subtitle: nil, kind: .runEndpoint(isStart: false, compact: false)))
        }
        for marker in geometry.kilometreMarkers {
            items.append(MapAnnotationItem(id: "run-km-\(marker.km)", coordinate: marker.coordinate, title: nil, subtitle: nil, kind: .runKilometre(marker.km)))
        }
        for (offset, stop) in record.stops.enumerated() {
            guard let lat = stop.lat, let lng = stop.lng else { continue }
            items.append(MapAnnotationItem(
                id: "run-rest-\(offset)",
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                title: nil,
                subtitle: nil,
                kind: .runRest("休息 \(RunRecordText.clock(stop.durationSec))")
            ))
        }
        if let highlight {
            let segment = geometry.segment(index: highlight.index)
            if !segment.isEmpty {
                items.append(MapAnnotationItem(
                    id: "run-bubble",
                    coordinate: segment[segment.count / 2],
                    title: nil,
                    subtitle: nil,
                    kind: .runBubble(highlight.bubbleText)
                ))
            }
        }
        return items
    }
}
