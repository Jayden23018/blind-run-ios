import Combine
import Charts
import CoreLocation
import SwiftUI

// 陪跑员跑后详情（OpenSpec `add-volunteer-run-record-detail`，HANDOFF 6.2 的 P0 部分，DECISIONS D13）。
// 数据只来自 `RunRecordServing.record(orderId:)`。并发只用 async/await。
//
// 没做（P1 / 后续阶段）：轨迹回放、夜跑样式、配速图拖动与地图联动、地图视差与导航栏渐变、
// 留言输入（阶段 6）。

// MARK: - Content（纯计算，用例直接钉）

struct VolunteerRunRecordContent {
    struct Stat: Hashable {
        let label: String
        let value: String
        let spoken: String
    }

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
    }

    struct Message: Hashable {
        let header: String
        let text: String
        let accessibilityLabel: String
    }

    let title: String
    let spokenTitle: String
    let runnerInitial: String?
    let volunteerInitial: String?
    let subtitle: String?
    let distanceText: String?
    let spokenDistance: String?
    let primaryStats: [Stat]
    let secondaryStats: [Stat]
    let serviceText: String?
    let serviceRange: String?
    let timeline: [TimelineEntry]
    let sosLine: String
    let mapDescription: String
    let splits: [SplitRow]
    let showsCadenceColumn: Bool
    let messages: [Message]

    init(record: RunRecordResponse, geometry: RunRouteGeometry? = nil) {
        let name = record.blindName?.trimmingCharacters(in: .whitespaces)
        if let name, !name.isEmpty {
            title = "和\(name)一起跑"
            spokenTitle = "和\(name.unmaskedForSpeech)一起跑"
        } else {
            title = "这次陪跑"
            spokenTitle = title
        }
        runnerInitial = name.flatMap(\.first).map(String.init)
        volunteerInitial = record.volunteerName.flatMap(\.first).map(String.init)

        let start = (record.runStartedAt ?? record.service.startedAt)?.backendTimestamp
        subtitle = [start.map(Self.dateTimeFormatter.string(from:)), record.place]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
            .nilIfEmpty

        let summary = record.summary
        distanceText = summary?.distanceM.map { RunRecordText.kilometres($0) }
        spokenDistance = summary?.distanceM.map { RunRecordText.kilometres($0, spoken: true) }

        // 没有数据是 null：对应一格整格不出现，不写 0（HANDOFF 6.4）。
        primaryStats = [
            summary?.movingSec.map { Stat(label: "运动时间", value: RunRecordText.clock($0), spoken: "运动时间 \(RunRecordText.spokenDuration($0))") },
            summary?.avgPaceSecPerKm.map { Stat(label: "平均配速", value: RunRecordText.pace($0), spoken: "平均配速 \(RunRecordText.spokenPace($0))") },
            summary?.avgCadence.map { Stat(label: "步频", value: "\($0)步/分", spoken: "步频 每分钟\($0)步") }
        ].compactMap { $0 }
        secondaryStats = [
            summary?.steps.map { Stat(label: "步数", value: $0.formatted(), spoken: "步数 \($0)步") },
            summary?.elevationGainM.map { Stat(label: "累计爬升", value: "\($0)米", spoken: "累计爬升 \($0)米") },
            summary?.restSec.map { Stat(label: "中途休息", value: RunRecordText.clock($0), spoken: "中途休息 \(RunRecordText.spokenDuration($0))") }
        ].compactMap { $0 }

        // D5：没有「待确认」之类的状态。
        serviceText = record.service.durationMin.map { "志愿服务 \(RunRecordHistoryViewModel.serviceDuration(Int64($0)))" }
        let serviceStart = record.service.startedAt?.backendTimestamp.map(Self.timeFormatter.string(from:))
        let serviceEnd = record.service.completedAt?.backendTimestamp.map(Self.timeFormatter.string(from:))
        serviceRange = serviceStart.flatMap { s in serviceEnd.map { "\(s)–\($0)" } }

        timeline = record.events.map { Self.timelineEntry($0) }
        sosLine = record.sosTriggered ? "这一单触发过紧急求助" : "全程没有触发紧急求助"

        let restCount = record.stops.count
        var description = "路线地图"
        if let spokenDistance { description += "，全程 \(spokenDistance) 公里" }
        if let geometry {
            description += geometry.startEndCoincide ? "，起点和终点在同一处" : "，起点和终点不在同一处"
        }
        description += restCount > 0 ? "，途中休息\(restCount)次" : "，途中没有休息"
        mapDescription = description + "。数字见下方。"

        let scale = RunPaceScale(samples: record.paceSamples)
        let fastestPace = record.splits.map(\.paceSecPerKm).filter { $0 > 0 }.min()
        showsCadenceColumn = record.splits.contains { $0.avgCadence != nil }
        splits = record.splits.map { split in
            let isFull = split.distanceM >= 1000
            let kilometre = isFull ? "\(split.index)" : RunRecordText.kilometres(split.distanceM)
            // 小数和单位之间留空格：「0.2公里」会被审计判成标签不可读（阶段 3 同一条）。
            let spokenKilometre = isFull ? "第\(split.index)公里" : "最后 \(RunRecordText.kilometres(split.distanceM, spoken: true)) 公里"
            let isFastest = split.index == record.fastestSplitIndex
            var label = "\(spokenKilometre)，\(RunRecordText.spokenPace(split.paceSecPerKm))"
            if let cadence = split.avgCadence { label += "，步频每分钟\(cadence)步" }
            if isFastest { label += "，最快" }
            return SplitRow(
                index: split.index,
                kilometreText: kilometre,
                paceText: RunRecordText.pace(split.paceSecPerKm),
                cadenceText: split.avgCadence.map(String.init),
                isFastest: isFastest,
                barFraction: fastestPace.map { split.paceSecPerKm > 0 ? Double($0) / Double(split.paceSecPerKm) : 0 } ?? 0,
                paceFraction: scale?.fraction(split.paceSecPerKm) ?? 0,
                bubbleText: "\(isFull ? "第\(split.index)公里" : "最后\(kilometre)公里") \(RunRecordText.pace(split.paceSecPerKm))",
                accessibilityLabel: label
            )
        }

        messages = record.messages.compactMap { message in
            guard let text = message.text, !text.isEmpty else { return nil }
            let from: (shown: String, spoken: String)
            switch message.fromRole {
            case .volunteer: from = ("我", "我")
            case .blind: from = (name ?? "跑者", name?.unmaskedForSpeech ?? "跑者")
            case .unknown: from = ("对方", "对方")
            }
            let time = message.createdAt.backendTimestamp.map(Self.dateTimeFormatter.string(from:))
            return Message(
                header: [from.shown, time].compactMap { $0 }.joined(separator: " · "),
                text: text,
                accessibilityLabel: "\(from.spoken)说：\(text)"
            )
        }
    }

    private static func timelineEntry(_ event: RunEvent) -> TimelineEntry {
        let clock = event.at.backendTimestamp.map(timeFormatter.string(from:)) ?? ""
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

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

// MARK: - Page

struct VolunteerRunRecordView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel: RunRecordViewModel
    @State private var highlightedSplit: Int?
    /// 「重试」起的任务。`.task` 那条随页面取消，这条要自己管：离开页面时还在 GENERATING 就会一直轮询，
    /// 连点两下会起两个并行的轮询。
    @State private var retryTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let topID = "runRecordTop"
    /// 卡片压住地图的那一截，地图适配视野时要让开。
    private static let cardOverlap: CGFloat = 28

    init(orderId: Int64) {
        _viewModel = StateObject(wrappedValue: RunRecordViewModel(orderId: orderId))
    }

    var body: some View {
        content
            .background(AppColors.background)
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            // 二级页藏标签栏：悬浮胶囊会盖住最后一行（记忆 tab-bar-clips-the-last-line-of-secondary-pages）。
            // 这一页是 push 进来的，返回箭头一直在。
            .toolbar(.hidden, for: .tabBar)
            // `children: .contain` 不能省：容器上的 identifier 会向下覆盖子元素（记忆 accessibility-identifier-overwrites-children）。
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("volunteerRunRecordDetail")
            .task {
                viewModel.configure(with: appState)
                await viewModel.loadUntilSettled()
            }
            .onDisappear { retryTask?.cancel() }
    }

    private var navigationTitle: String {
        if case .loaded(let record) = viewModel.phase {
            return VolunteerRunRecordContent(record: record).title
        }
        return "跑后记录"
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .loading:
            RunRecordLoadingPlaceholder(title: "和陈*一起跑")
        case .failed(let message):
            RunRecordFailedView(message: message, retry: retry)
        case .loaded(let record):
            loaded(record)
        }
    }

    @ViewBuilder
    private func loaded(_ record: RunRecordResponse) -> some View {
        let geometry = record.status == .ready ? record.track.flatMap(RunRouteGeometry.init(track:)) : nil
        let content = VolunteerRunRecordContent(record: record, geometry: geometry)
        if let geometry {
            GeometryReader { proxy in
                let mapHeight = proxy.size.height * 0.6
                ZStack(alignment: .top) {
                    RunRecordRouteMap(
                        geometry: geometry,
                        record: record,
                        highlight: highlightedSplit.flatMap { index in content.splits.first { $0.index == index } },
                        bottomInset: Self.cardOverlap + 24
                    )
                    .frame(height: mapHeight)

                    ScrollViewReader { scroll in
                        ScrollView {
                            VStack(spacing: 0) {
                                // 地图本身不进无障碍树（标记不逐个暴露），它的整体描述挂在正好盖住它的这块透明区上。
                                Color.clear
                                    .frame(height: max(mapHeight - Self.cardOverlap, 0))
                                    .contentShape(Rectangle())
                                    .accessibilityElement()
                                    .accessibilityLabel(content.mapDescription)
                                    .accessibilityIdentifier("runRecordMapDescription")
                                    .id(Self.topID)
                                card(record, content, onSelectSplit: { select($0, scroll: scroll) })
                                    .background(
                                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                                            .fill(AppColors.background)
                                            .shadow(color: .black.opacity(0.12), radius: 8, y: -2)
                                    )
                            }
                        }
                    }
                }
            }
        } else {
            ScrollView {
                card(record, content, onSelectSplit: nil)
            }
        }
    }

    private func select(_ index: Int, scroll: ScrollViewProxy) {
        highlightedSplit = index
        withAnimation(reduceMotion ? nil : .easeInOut) {
            scroll.scrollTo(Self.topID, anchor: .top)
        }
    }

    // MARK: Card

    private func card(
        _ record: RunRecordResponse,
        _ content: VolunteerRunRecordContent,
        onSelectSplit: ((Int) -> Void)?
    ) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            RunRecordHeader(content: content)
            RunRecordStatusNotice(status: record.status, hasMap: onSelectSplit != nil, retry: retry)
            if let distance = content.distanceText, let spoken = content.spokenDistance {
                RunRecordBigDistance(text: distance, spoken: spoken)
            }
            if !content.primaryStats.isEmpty {
                RunRecordStatsRow(stats: content.primaryStats, prominent: true)
            }
            if !content.secondaryStats.isEmpty {
                RunRecordStatsRow(stats: content.secondaryStats, prominent: false)
            }
            if let service = content.serviceText {
                serviceRow(service, range: content.serviceRange)
            }
            if record.paceSamples.count >= 2, let scale = RunPaceScale(samples: record.paceSamples) {
                section("配速") {
                    RunPaceChart(samples: record.paceSamples, average: record.summary?.avgPaceSecPerKm, stops: record.stops, scale: scale)
                }
            }
            if !content.splits.isEmpty {
                section("分段") {
                    RunSplitList(
                        rows: content.splits,
                        showsCadence: content.showsCadenceColumn,
                        selected: highlightedSplit,
                        onSelect: onSelectSplit
                    )
                }
            }
            section("途中记录") {
                RunTimeline(entries: content.timeline, sosLine: content.sosLine)
            }
            if !content.messages.isEmpty {
                section("留言") {
                    ForEach(content.messages, id: \.self) { message in
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
                    }
                }
            }
        }
        .padding(20)
        // 滚到底时最后一行（求助那句）别贴着 Home 条。
        .padding(.bottom, 24)
        .readableContentColumn()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func retry() {
        retryTask?.cancel()
        retryTask = Task { await viewModel.retry() }
    }

    private func serviceRow(_ text: String, range: String?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "clock")
                .foregroundColor(AppColors.textSecondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(text)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textPrimary)
                if let range {
                    Text(range)
                        .font(AppFonts.caption())
                        .foregroundColor(AppColors.textSecondary)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([text, range.map { $0.replacingOccurrences(of: "–", with: "到") }].compactMap { $0 }.joined(separator: "，"))
        .accessibilityIdentifier("runRecordServiceRow")
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

// MARK: 状态（两个角色的详情页共用，HANDOFF 6.4）

/// 骨架屏，读屏只读一句。
struct RunRecordLoadingPlaceholder: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(AppFonts.title())
            Text("5.21 公里").font(.largeTitle.weight(.heavy))
            Text("运动时间 平均配速 步频")
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .redacted(reason: .placeholder)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("正在加载跑步记录")
        .accessibilityIdentifier("runRecordLoading")
    }
}

struct RunRecordFailedView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(message)
                .font(AppFonts.body())
                .foregroundColor(AppColors.destructive)
            RunRecordRetryButton(action: retry)
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

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
            VStack(alignment: .leading, spacing: 12) {
                Text(status == .failed ? "这条记录没能生成。" : "这条记录暂时无法显示。")
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.destructive)
                RunRecordRetryButton(action: retry)
            }
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

struct RunRecordRetryButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("重试")
                .font(AppFonts.body())
                .frame(maxWidth: .infinity, minHeight: FlowMetrics.actionButtonMinHeight, alignment: .leading)
                .contentShape(Rectangle())
        }
        .accessibilityHint("重新加载跑后记录")
        .accessibilityIdentifier("runRecordRetry")
    }
}

private struct RunRecordHeader: View {
    let content: VolunteerRunRecordContent

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // 辅助字号下头像放上面，标题才有整行宽度。
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 16))
        layout {
            // 两个叠放头像（跑者黄底黑字、陪跑员近黑底白字），纯装饰。
            ZStack(alignment: .topLeading) {
                avatar(content.runnerInitial, fill: AppColors.tactileYellow, ink: .black)
                avatar(content.volunteerInitial, fill: Color(uiColor: UIColor(rgb: RunRouteGlyph.outlineRGB)), ink: .white)
                    .offset(x: 26, y: 12)
            }
            .frame(width: 70, height: 56, alignment: .topLeading)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(content.title)
                    .font(AppFonts.title())
                    .foregroundColor(AppColors.textPrimary)
                if let subtitle = content.subtitle {
                    Text(subtitle)
                        .font(AppFonts.caption())
                        .foregroundColor(AppColors.textSecondary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel([content.spokenTitle, content.subtitle].compactMap { $0 }.joined(separator: "，"))
            .accessibilityAddTraits(.isHeader)
        }
    }

    private func avatar(_ initial: String?, fill: Color, ink: Color) -> some View {
        Circle()
            .fill(fill)
            .overlay(Circle().stroke(AppColors.background, lineWidth: 2))
            .overlay {
                if let initial {
                    Text(initial).font(.system(size: 18, weight: .bold)).foregroundColor(ink)
                } else {
                    Image(systemName: "person.fill").foregroundColor(ink)
                }
            }
            .frame(width: 44, height: 44)
    }
}

private struct RunRecordBigDistance: View {
    let text: String
    let spoken: String
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 60
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // 辅助字号下「公里」换到下一行，大数字才不会被挤出屏幕。
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 6))
        layout {
            Text(text)
                .font(.system(size: size, weight: .heavy))
                .monospacedDigit()
                .foregroundColor(AppColors.textPrimary)
            Text("公里")
                .font(AppFonts.title())
                .foregroundColor(AppColors.textPrimary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("距离 \(spoken) 公里")
        .accessibilityIdentifier("runRecordDistance")
    }
}

/// 三列并排；辅助字号下改竖排，不靠缩字（design-direction §7）。语序「标签 值」，理由同 `TrackStatsRow`。
private struct RunRecordStatsRow: View {
    let stats: [VolunteerRunRecordContent.Stat]
    let prominent: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let vertical = dynamicTypeSize.isAccessibilitySize
        let layout = vertical
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
        layout {
            ForEach(stats, id: \.label) { stat in
                VStack(alignment: .leading, spacing: 4) {
                    Text(stat.value)
                        .font(prominent ? .title2.weight(.bold) : .title3.weight(.semibold))
                        .monospacedDigit()
                        .foregroundColor(AppColors.textPrimary)
                    Text(stat.label)
                        .font(AppFonts.caption())
                        .foregroundColor(AppColors.textSecondary)
                }
                .frame(maxWidth: vertical ? nil : .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(stat.spoken)
            }
        }
    }
}

private struct RunSplitList: View {
    let rows: [VolunteerRunRecordContent.SplitRow]
    let showsCadence: Bool
    let selected: Int?
    /// nil = 没有地图可高亮，行只读。
    let onSelect: ((Int) -> Void)?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !dynamicTypeSize.isAccessibilitySize {
                HStack(spacing: 12) {
                    Text("公里").frame(minWidth: 36, alignment: .leading)
                    Text("配速").frame(minWidth: 56, alignment: .leading)
                    Spacer(minLength: 0)
                    if showsCadence { Text("步频") }
                }
                .font(AppFonts.caption())
                .foregroundColor(AppColors.textSecondary)
                .accessibilityHidden(true)
            }
            ForEach(rows, id: \.index) { row in
                if let onSelect {
                    Button { onSelect(row.index) } label: { rowContent(row) }
                        .buttonStyle(.plain)
                        .accessibilityHint("在地图上高亮这一段")
                        .accessibilityAddTraits(selected == row.index ? .isSelected : [])
                        .accessibilityIdentifier("runRecordSplit-\(row.index)")
                } else {
                    rowContent(row)
                        .accessibilityIdentifier("runRecordSplit-\(row.index)")
                }
            }
        }
    }

    private func rowContent(_ row: VolunteerRunRecordContent.SplitRow) -> some View {
        let color = Color(uiColor: RunPacePalette.color(fraction: row.paceFraction, isDark: colorScheme == .dark))
        let bar = GeometryReader { proxy in
            Capsule()
                .fill(color)
                .frame(width: max(proxy.size.width * row.barFraction, 6))
        }
        .frame(height: 10)
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        return layout {
            Text(row.kilometreText)
                .font(AppFonts.body().weight(.semibold))
                .frame(minWidth: 36, alignment: .leading)
            Text(row.paceText)
                .font(AppFonts.body())
                .monospacedDigit()
                .frame(minWidth: 56, alignment: .leading)
            bar
            if showsCadence {
                Text(row.cadenceText ?? "")
                    .font(AppFonts.body())
                    .monospacedDigit()
                    .frame(minWidth: 36, alignment: .trailing)
            }
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
        .foregroundColor(AppColors.textPrimary)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: FlowMetrics.actionButtonMinHeight, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(selected == row.index ? AppColors.secondaryBackground : Color.clear)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
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

// MARK: - Pace Chart

private struct RunPaceChart: View {
    let samples: [RunPaceSample]
    let average: Int?
    let stops: [RunStop]
    let scale: RunPaceScale
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        // 纵轴画的是「负的配速」：快（数小）在上、慢在下，范围按数据定死。
        // 用 `.automatic(reversed:)` 时 Charts 会把范围取整到 3'20"–8'20"，曲线只占中间一小截。
        let paces = samples.map(\.paceSecPerKm)
        let top = -Double((paces.min() ?? 0) - 10)
        let bottom = -Double((paces.max() ?? 0) + 20)
        let gradient = paceGradient
        Chart {
            ForEach(samples, id: \.distanceM) { sample in
                AreaMark(
                    x: .value("距离", Double(sample.distanceM) / 1000),
                    yStart: .value("配速", -Double(sample.paceSecPerKm)),
                    yEnd: .value("底", bottom)
                )
                .foregroundStyle(gradient.opacity(0.25))
                LineMark(
                    x: .value("距离", Double(sample.distanceM) / 1000),
                    y: .value("配速", -Double(sample.paceSecPerKm))
                )
                .foregroundStyle(gradient)
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
            if let average {
                RuleMark(y: .value("平均配速", -Double(average)))
                    .foregroundStyle(AppColors.textSecondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("平均 \(RunRecordText.pace(average))")
                            .font(AppFonts.caption())
                            .foregroundColor(AppColors.textSecondary)
                    }
            }
            ForEach(stops, id: \.atDistanceM) { stop in
                RuleMark(x: .value("休息", Double(stop.atDistanceM) / 1000))
                    .foregroundStyle(AppColors.textSecondary.opacity(0.6))
                    .annotation(position: .top) {
                        Text("休息")
                            .font(AppFonts.caption())
                            .foregroundColor(AppColors.textSecondary)
                    }
            }
        }
        .chartYScale(domain: bottom...top)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let negative = value.as(Double.self) {
                        Text(RunRecordText.pace(Int(-negative)))
                    }
                }
            }
        }
        // 刻度只写数字、单位写一次：每个刻度都带「公里」在大字号下会叠在一起。
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let km = value.as(Double.self) {
                        Text(km.formatted(.number.precision(.fractionLength(0...1))))
                    }
                }
            }
        }
        .chartXAxisLabel("公里", alignment: .trailing)
        .frame(height: dynamicTypeSize.isAccessibilitySize ? 320 : 200)
        // 整张图是一个元素，逐点浏览与声音图表交给 AXChartDescriptor（HANDOFF 第 7 节）。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("配速图")
        .accessibilityValue(descriptor.summary)
        .accessibilityChartDescriptor(descriptor)
        .accessibilityIdentifier("runRecordPaceChart")
    }

    private var descriptor: RunPaceChartDescriptor {
        RunPaceChartDescriptor(samples: samples, average: average)
    }

    private var paceGradient: LinearGradient {
        let total = Double(samples.last?.distanceM ?? 0)
        let isDark = colorScheme == .dark
        let stops = samples.map { sample in
            Gradient.Stop(
                color: Color(uiColor: RunPacePalette.color(fraction: scale.fraction(sample.paceSecPerKm), isDark: isDark)),
                location: total > 0 ? Double(sample.distanceM) / total : 0
            )
        }
        return LinearGradient(stops: stops, startPoint: .leading, endPoint: .trailing)
    }
}

struct RunPaceChartDescriptor: AXChartDescriptorRepresentable {
    let samples: [RunPaceSample]
    let average: Int?

    var summary: String {
        let paces = samples.map(\.paceSecPerKm)
        var parts: [String] = []
        if let average { parts.append("平均\(RunRecordText.spokenPace(average))") }
        if let fastest = paces.min() { parts.append("最快\(RunRecordText.spokenPace(fastest))") }
        if let slowest = paces.max() { parts.append("最慢\(RunRecordText.spokenPace(slowest))") }
        return parts.joined(separator: "，")
    }

    func makeChartDescriptor() -> AXChartDescriptor {
        let kilometres = samples.map { Double($0.distanceM) / 1000 }
        let paces = samples.map { Double($0.paceSecPerKm) }
        let xAxis = AXNumericDataAxisDescriptor(
            title: "距离",
            range: 0...(kilometres.max() ?? 0),
            gridlinePositions: []
        ) { "\($0.formatted(.number.precision(.fractionLength(0...2))))公里" }
        let yAxis = AXNumericDataAxisDescriptor(
            title: "配速",
            range: (paces.min() ?? 0)...(paces.max() ?? 0),
            gridlinePositions: []
        ) { RunRecordText.spokenPace(Int($0)) }
        let series = AXDataSeriesDescriptor(
            name: "配速",
            isContinuous: true,
            dataPoints: zip(kilometres, paces).map { AXDataPoint(x: $0, y: $1) }
        )
        return AXChartDescriptor(title: "配速图", summary: summary, xAxis: xAxis, yAxis: yAxis, additionalAxes: [], series: [series])
    }
}

// MARK: - Route Map

/// 描边 + 配速线 + 公里标记 + 起终点 + 休息点 + 高亮那一公里。整张图对读屏是装饰（描述挂在页面上）。
/// 跑者详情（阶段 5）也用它，`highlight` 传 nil。
struct RunRecordRouteMap: View {
    let geometry: RunRouteGeometry
    let record: RunRecordResponse
    let highlight: VolunteerRunRecordContent.SplitRow?
    let bottomInset: CGFloat

    var body: some View {
        MapViewWrapper(
            centerCoordinate: center,
            showsUserLocation: false,
            annotations: annotations,
            polylines: polylines,
            tracksUserLocation: false,
            animatesCenterChanges: false,
            fitEdgePadding: UIEdgeInsets(top: 40, left: 32, bottom: bottomInset, right: 32),
            isDecorative: true
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
        if let first = geometry.coordinates.first, let last = geometry.coordinates.last {
            if geometry.startEndCoincide {
                items.append(MapAnnotationItem(id: "run-start-end", coordinate: first, title: nil, subtitle: nil, kind: .runLabel("起终点")))
            } else {
                items.append(MapAnnotationItem(id: "run-start", coordinate: first, title: nil, subtitle: nil, kind: .runLabel("起点")))
                items.append(MapAnnotationItem(id: "run-end", coordinate: last, title: nil, subtitle: nil, kind: .runLabel("终点")))
            }
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
