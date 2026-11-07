import Combine
import SwiftUI

// 两端「记录」tab（OpenSpec `add-run-record-history-tab`，DECISIONS D9）。
//
// 上半部分是跑后记录的月度列表（`RunRecordServing.monthlyRecords`，`add-post-run-record` 交的数据层）；
// 订单仍从 `GET /api/orders/mine` 取：已取消 / 暂无志愿者的进底部「未完成的预约」。没走完的预约不进「记录」（负责人 11-07，#823 第二轮）。
// 两端共用一个结构（HANDOFF 6.1、`design-direction.md` §5.2：两端只在密度 / 层级 / 语气上有差异，
// 不分叉组件）—— 角色只决定文案、行的密度和点进去落到哪一页。并发只用 async/await（AGENTS.md 硬约束）。

enum RunRecordHistoryRole {
    case runner
    case volunteer

    var title: String {
        switch self {
        case .runner: return "跑步记录"
        case .volunteer: return "陪跑记录"
        }
    }
}

// MARK: - View Model

@MainActor
final class RunRecordHistoryViewModel: ObservableObject {
    @Published private(set) var month: RunRecordMonth
    /// 当前显示那个月的记录。切月份时先置 nil，界面回到加载态。
    @Published private(set) var history: RunRecordHistoryResponse?
    @Published private(set) var unfinished: [OrderDetailResponse] = []
    /// `/api/orders/mine` 里有没有任何一张已完成的单。nil = 还不知道（没加载完或加载失败）——
    /// 那种情况下**不**给「完成第一次陪跑后…」的首用文案，否则网络一抖老用户就被当成新人。
    @Published private(set) var hasAnyCompletedOrder: Bool?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    /// 选中月份之后往下接的更早月份（只收有记录的月份）。
    @Published private(set) var olderSections: [RunRecordMonthSection] = []
    @Published private(set) var isLoadingOlder = false
    /// 下一个要请求的更早月份；nil = 不再往下加载（还没加载完选中月份、出错、或连续空月够了）。
    @Published private(set) var olderCursor: RunRecordMonth?
    /// 每次重新加载 / 切月份加一：在途的旧请求回来时据此丢掉结果。
    @Published private(set) var generation = 0
    /// 从选中月份起连续多少个月没有记录。
    private var emptyStreak = 0
    /// 每次调 `loadOlderMonths` 加一：后来的调用接管，先前那次的结果作废。
    private var olderRun = 0

    let role: RunRecordHistoryRole
    let currentMonth: RunRecordMonth

    private weak var appState: AppState?
    private var speechService: SpeechService?
    private var runRecordOverride: (any RunRecordServing)?

    init(role: RunRecordHistoryRole, now: Date = Date()) {
        self.role = role
        let current = RunRecordMonth(containing: now)
        self.currentMonth = current
        self.month = current
    }

    /// ⚠️ `appState` 是 weak：用例要自己持有它。`runRecord` 只给用例换替身，生产走 `appState.runRecord`。
    func configure(with appState: AppState, speechService: SpeechService?, runRecord: (any RunRecordServing)? = nil) {
        self.appState = appState
        self.speechService = speechService
        self.runRecordOverride = runRecord
    }

    var monthTitle: String { month.title(relativeTo: currentMonth) }
    var canShowNextMonth: Bool { month != currentMonth }
    var previousMonthTitle: String { month.previous.title(relativeTo: currentMonth) }
    var nextMonthTitle: String { month.next.title(relativeTo: currentMonth) }
    /// 月份栏标题，总带年份。
    var monthBarTitle: String { month.fullTitle }

    /// 连续这么多个月没有记录就不再往下加载（#829：没有「最早月份」接口，用它当到底）。
    static let emptyMonthsBeforeStopping = 12
    /// 月份菜单从本月往回列多少个月。
    // ponytail: 固定列 24 个月；后端给出最早有记录的月份后改成列到那个月。
    static let monthPickerSpan = 24

    /// 菜单里的月份，新的在前。
    var pickerMonths: [RunRecordMonth] {
        Array(sequence(first: currentMonth) { $0.previous }.prefix(Self.monthPickerSpan))
    }

    /// 选中月份（有记录时）+ 已加载的更早月份。
    var sections: [RunRecordMonthSection] {
        guard let items = history?.items, !items.isEmpty else { return olderSections }
        return [RunRecordMonthSection(month: month, items: items)] + olderSections
    }

    /// 列表的全部记录，转子与读屏焦点用，和 `sections` 同源。
    var allItems: [RunHistoryItem] { sections.flatMap(\.items) }

    /// 底部的「加载更早月份」要在这个值变了时重跑：换了一批数据或又接上了一节。
    var olderLoadTrigger: [Int] { [generation, olderSections.count] }

    func load() async {
        generation += 1
        resetOlder()
        errorMessage = nil
        async let monthly: Void = loadMonth(month)
        async let orders: Void = loadUnfinished()
        _ = await (monthly, orders)
        announceLoaded()
    }

    func showPreviousMonth() async {
        await switchTo(month.previous)
    }

    func showNextMonth() async {
        guard canShowNextMonth else { return }
        await switchTo(month.next)
    }

    /// 月份菜单直接跳。比本月新的不接受。
    func jump(to target: RunRecordMonth) async {
        guard target <= currentMonth, target != month else { return }
        await switchTo(target)
    }

    private func switchTo(_ target: RunRecordMonth) async {
        generation += 1
        month = target
        history = nil
        errorMessage = nil
        resetOlder()
        // 订单那一路之前失败过（`hasAnyCompletedOrder` 还是 nil）就一起重试：
        // 上面刚把错误提示清掉，不重试的话「未完成的预约」会静默显示成「没有」。
        if hasAnyCompletedOrder == nil {
            async let monthly: Void = loadMonth(target)
            async let orders: Void = loadUnfinished()
            _ = await (monthly, orders)
        } else {
            await loadMonth(target)
        }
        announceLoaded()
    }

    private func loadMonth(_ target: RunRecordMonth) async {
        guard let appState else { return }
        isLoading = true
        do {
            let service = runRecordOverride ?? appState.runRecord
            let loaded = try await service.monthlyRecords(year: target.year, month: target.month)
            // 用户在请求途中又切了月份：这份结果属于上一个月，丢掉。
            guard target == month else { return }
            history = loaded
            emptyStreak = loaded.items.isEmpty ? 1 : 0
            olderCursor = target.previous
        } catch {
            guard target == month else { return }
            recordFailure(error)
        }
        if target == month { isLoading = false }
    }

    private func resetOlder() {
        olderSections = []
        olderCursor = nil
        emptyStreak = 0
        isLoadingOlder = false
    }

    /// 列表滑到底时调：一直往前请求，直到接上一个有记录的月份，或连续空月够了就停。
    /// 每月照旧调 `monthlyRecords`（后端不改）。被取消（滑走了）时不报错，下次从断点接着请求。
    func loadOlderMonths() async {
        guard let start = olderCursor, let appState else { return }
        // 不用 `isLoadingOlder` 挡：滑走被取消的旧任务可能还在等网络，挡住新任务后加载条会一直转。
        olderRun += 1
        let started = (generation, olderRun)
        func isCurrent() -> Bool { started == (generation, olderRun) }
        isLoadingOlder = true
        defer { if isCurrent() { isLoadingOlder = false } }
        let service = runRecordOverride ?? appState.runRecord
        var target = start
        while emptyStreak < Self.emptyMonthsBeforeStopping {
            let loaded: RunRecordHistoryResponse
            do {
                loaded = try await service.monthlyRecords(year: target.year, month: target.month)
            } catch {
                guard isCurrent(), !Task.isCancelled, !(error is CancellationError) else { return }
                olderCursor = nil
                recordFailure(error)
                return
            }
            guard isCurrent() else { return }
            olderCursor = target.previous
            guard loaded.items.isEmpty else {
                emptyStreak = 0
                olderSections.append(RunRecordMonthSection(month: target, items: loaded.items))
                return
            }
            emptyStreak += 1
            if Task.isCancelled { return }
            target = target.previous
        }
        olderCursor = nil
    }

    private func loadUnfinished() async {
        guard let appState else { return }
        do {
            let orders = try await appState.orders.myOrders().content
            hasAnyCompletedOrder = orders.contains { $0.status == .completed }
            unfinished = Self.unfinishedBookings(from: orders)
        } catch {
            recordFailure(error)
        }
    }

    /// 已取消 / 暂无志愿者，最近的在前。没走完的不在这里，未知状态不当成「已结束」替用户下结论。
    static func unfinishedBookings(from orders: [OrderDetailResponse]) -> [OrderDetailResponse] {
        orders
            .filter { $0.status == .cancelled || $0.status == .noVolunteer }
            .sorted { ($0.createdAt ?? $0.plannedStart ?? "") > ($1.createdAt ?? $1.plannedStart ?? "") }
    }

    private func recordFailure(_ error: Error) {
        let detail: String
        if let apiError = error as? APIError {
            if appState?.handleAuthenticatedAPIError(apiError) == true { return }
            detail = apiError.localizedMessage
        } else {
            detail = "请检查网络后重试"
        }
        let message = "\(role.title)没能加载完整。\(detail)"
        // 两路请求都失败时只念一次。
        guard errorMessage == nil else { return }
        errorMessage = message
        speechService?.speakError(message)
    }

    /// 跑者端加载完要出声：加载态那一行被列表换掉时读屏焦点会被系统收走，用户既没听到结果也不知道停在哪
    /// （此前 `BlindRunHistoryViewModel` 的同一条理由）。陪跑员端一直是静默的，不在这次顺手加。
    private func announceLoaded() {
        guard role == .runner, errorMessage == nil, history != nil else { return }
        speechService?.speak(loadedAnnouncement)
    }

    var loadedAnnouncement: String {
        if showsFirstRunEmptyState { return emptyStateCopy.title + "。" + emptyStateCopy.message }
        var text = summaryText(spoken: true) ?? ""
        if !unfinished.isEmpty { text += "另有 \(unfinished.count) 条未完成的预约。" }
        return text
    }

    // MARK: 文案（纯计算，用例直接钉）

    /// 月度汇总。`spoken` 时朗读用的公里数去掉尾零。
    func summaryText(spoken: Bool = false) -> String? {
        guard let summary = history?.monthSummary else { return nil }
        guard summary.runs > 0 else {
            return "\(monthTitle)还没有\(role.title)。"
        }
        switch role {
        case .runner:
            var text = "\(monthTitle)跑了 \(summary.runs) 次"
            if let distance = summary.distanceM {
                text += "，一共 \(Self.kilometres(distance, spoken: spoken)) 公里"
            }
            return text + "。"
        case .volunteer:
            var text = "\(monthTitle)陪跑 \(summary.runs) 次"
            if let minutes = summary.serviceMin {
                text += "，服务 \(Self.serviceDuration(minutes))"
            }
            // 不说「其中和谁跑了几次」：列表不写和谁一起跑（负责人 2026-11-07，#823）。
            return text + "。"
        }
    }

    /// HANDOFF 6.4「历史列表为空」。只在「这个月空、且从没完成过一单」时用；
    /// 只是这个月空，汇总那句「X月还没有跑步记录」已经说清，下面再来一段是重复。
    var showsFirstRunEmptyState: Bool {
        history?.items.isEmpty == true && hasAnyCompletedOrder == false
    }

    var emptyStateCopy: (title: String, message: String) {
        switch role {
        case .runner:
            return ("还没有跑步记录", "完成第一次陪跑后，记录会出现在这里。")
        case .volunteer:
            return ("还没有陪跑记录", "完成第一次陪跑后，记录会出现在这里。")
        }
    }

    var loadingLabel: String { "正在加载\(role.title)" }

    /// 公里数，两位小数。朗读时去掉尾零：「5.00」念成「5点00」没有意义。
    static func kilometres(_ metres: Int, spoken: Bool = false) -> String {
        let text = String(format: "%.2f", Double(metres) / 1000)
        guard spoken, text.contains(".") else { return text }
        var trimmed = text
        while trimmed.hasSuffix("0") { trimmed.removeLast() }
        if trimmed.hasSuffix(".") { trimmed.removeLast() }
        return trimmed
    }

    static func serviceDuration(_ minutes: Int64) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        switch (hours, rest) {
        case (0, _): return "\(rest) 分钟"
        case (_, 0): return "\(hours) 小时"
        default: return "\(hours) 小时 \(rest) 分钟"
        }
    }
}

// MARK: - View

/// 照负责人参考图（#829）：月份栏 → 选中月份的汇总卡 → 按月分节的记录卡，滑到底接着加载更早的月份。
/// 读屏标签、转子、identifier、整行可点与改版前一致（#823）。
struct RunRecordHistoryView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @StateObject private var viewModel: RunRecordHistoryViewModel
    /// 首次加载完把读屏焦点落到第一条记录上（沿用旧跑者列表的做法），只落一次。
    @AccessibilityFocusState private var focusedRecordID: Int64?
    @State private var didPlaceInitialFocus = false

    init(role: RunRecordHistoryRole) {
        _viewModel = StateObject(wrappedValue: RunRecordHistoryViewModel(role: role))
    }

    private var role: RunRecordHistoryRole { viewModel.role }
    private var items: [RunHistoryItem] { viewModel.allItems }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if let errorMessage = viewModel.errorMessage {
                    RunRecordCard {
                        Text(errorMessage)
                            .font(AppFonts.body())
                            .foregroundColor(AppColors.destructive)
                            .fixedSize(horizontal: false, vertical: true)
                        Button {
                            Task { await viewModel.load() }
                        } label: {
                            Text("重试")
                                .frame(maxWidth: .infinity, minHeight: FlowMetrics.actionButtonMinHeight, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(TextButtonStyle())
                        .accessibilityHint("重新加载\(role.title)")
                        .accessibilityIdentifier("runRecordHistoryRetry")
                    }
                }

                RunRecordMonthBar(viewModel: viewModel)
                summaryCard

                if viewModel.history == nil && viewModel.isLoading {
                    loadingPlaceholder
                } else if viewModel.showsFirstRunEmptyState {
                    RunRecordCard {
                        EmptyStateView(title: viewModel.emptyStateCopy.title, message: viewModel.emptyStateCopy.message)
                    }
                } else {
                    ForEach(viewModel.sections) { section in
                        sectionTitle(section.month.title(relativeTo: viewModel.currentMonth))
                        ForEach(section.items, id: \.orderId) { item in
                            NavigationLink {
                                completedDestination(orderId: item.orderId)
                            } label: {
                                RunHistoryRow(content: RunHistoryRowContent(item: item, role: role), thumbnail: item.thumbnail)
                            }
                            .buttonStyle(.plain)
                            .accessibilityFocused($focusedRecordID, equals: item.orderId)
                        }
                    }
                    if viewModel.history != nil, viewModel.olderCursor != nil {
                        olderLoader
                    }
                }

                if !viewModel.unfinished.isEmpty {
                    sectionTitle("未完成的预约")
                    ForEach(viewModel.unfinished, id: \.orderId) { order in
                        NavigationLink {
                            unfinishedDestination(order)
                        } label: {
                            UnfinishedBookingRow(order: order, role: role)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
            .readableContentColumn()
        }
        .background(AppColors.Flow.page.ignoresSafeArea())
        .navigationTitle(role.title)
        .accessibilityIdentifier("runRecordHistoryList")
        // 自定义转子：列表里混着本月记录和未完成的预约，逐行右滑要听完每一条。条件与 ForEach 同源。
        .accessibilityRotor(
            "已完成的跑步",
            entries: items,
            entryID: \.orderId,
            entryLabel: \.rotorDateLabel
        )
        // 只在首次加载时落一次：之后切月份（读屏焦点在月份栏上，可能要连按「上个月」）
        // 或往下接更早的月份都不把焦点拽进列表。切完的结果由 `announceLoaded` 念出来。
        .onChange(of: items.first?.orderId) { firstID in
            guard let firstID, !didPlaceInitialFocus, focusedRecordID == nil else { return }
            didPlaceInitialFocus = true
            focusedRecordID = firstID
        }
        .task {
            viewModel.configure(with: appState, speechService: speechService)
            await viewModel.load()
        }
        .refreshable {
            await viewModel.load()
        }
    }

    // MARK: 汇总卡

    /// 选中月份的彩色数字格，中间竖线分隔；这个月没跑就写一句「X月还没有跑步记录。」。
    /// 整卡一个读屏元素，念的是整句汇总（与改版前同一句）。
    private var summaryCard: some View {
        RunRecordCard {
            if let summary = viewModel.summaryText() {
                Group {
                    if viewModel.summaryCells.isEmpty {
                        Text(summary)
                            .font(AppFonts.body())
                            .foregroundColor(AppColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        RunRecordSummaryCells(cells: viewModel.summaryCells)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(viewModel.summaryText(spoken: true) ?? summary)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("runRecordHistorySummary")
            } else {
                Text(" ")
                    .font(.title.weight(.bold))
                    .redacted(reason: .placeholder)
                    .accessibilityHidden(true)
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        RunRecordSectionTitle(text: text)
            .padding(.top, 12)
    }

    /// 列表底部：出现在屏幕上就去请求更早的月份；接上一节后它被推下去，再滑到底再请求。
    private var olderLoader: some View {
        HStack(spacing: 8) {
            ProgressView()
            Text("正在加载更早的记录")
                .font(.subheadline)
                .foregroundColor(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: FlowMetrics.actionButtonMinHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("正在加载更早的记录")
        .accessibilityIdentifier("runRecordHistoryLoadingOlder")
        .task(id: viewModel.olderLoadTrigger) {
            await viewModel.loadOlderMonths()
        }
    }

    /// 骨架屏：两张卡占位，读屏只读一句（HANDOFF 6.4）。
    private var loadingPlaceholder: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(0..<2, id: \.self) { _ in
                RunRecordCard {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("9月20日").font(.headline)
                            Text("周六").font(.subheadline)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("5.21 公里").font(.title.weight(.bold))
                            Text("深圳湾公园").font(.subheadline)
                        }
                        Spacer(minLength: 8)
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .frame(width: RunRecordListMap.side, height: RunRecordListMap.side)
                    }
                }
            }
        }
        .redacted(reason: .placeholder)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(viewModel.loadingLabel)
        .accessibilityIdentifier("runRecordHistoryLoading")
    }

    /// 两个角色都进各自的跑后详情（阶段 4、5）。跑者的补评价仍在订单页，从跑后详情最后一行进。
    @ViewBuilder
    private func completedDestination(orderId: Int64) -> some View {
        switch role {
        case .runner:
            RunnerRunRecordView(orderId: orderId)
        case .volunteer:
            VolunteerRunRecordView(orderId: orderId)
        }
    }

    @ViewBuilder
    private func unfinishedDestination(_ order: OrderDetailResponse) -> some View {
        switch role {
        case .runner: BlindOrderStatusView(orderId: order.orderId) { _ in }
        case .volunteer: VolunteerReadOnlyOrderView(order: order)
        }
    }
}

private extension RunHistoryItem {
    /// 转子 `entryLabel` 要一个 KeyPath。转子只念日期，与角色无关。
    var rotorDateLabel: String { RunHistoryRowContent(item: self, role: .runner).rotorLabel }
}

// MARK: - Thumbnail

/// 纯 `Path` 的路线缩略图（陪跑员首页、跑步数据页还在用）。跑步记录列表 11-07 起换成真实高德小地图（`RunRecordListMap`，#823）。
/// 此前列表用它，是负责人 2026-09-24 拍板「不用高德截图」（
/// 依据 `docs/research/amap-snapshot-for-list-thumbnail-20260924.md`）。
/// 画不出路线（没有点：超过 90 天留存期 / 后端没补算；或所有点重合：只跑了几秒）时
/// 画一个跑步图标。只画底块或一个小点看起来像图片加载失败（2026-10-03 试用反馈）。
struct RunRouteThumbnail: View {
    let points: [RunLatLng]?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppColors.secondaryBackground)
            if let points, RunRouteShape.hasExtent(points) {
                RunRouteShape(points: points)
                    .stroke(AppColors.paceFast, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .padding(7)
            } else {
                Image(systemName: "figure.run")
                    .font(.title3)
                    .foregroundColor(AppColors.textSecondary)
            }
        }
    }
}

nonisolated struct RunRouteShape: Shape {
    let points: [RunLatLng]

    /// 路线外框短于这个长度时不画线：只跑了几秒的单，定位抖动会被 `project` 放大成满格的乱线。
    static let minimumDrawableSpanMeters = 10.0

    /// 外框（纬向 / 经向取大）够长，才画得出一条有意义的线。
    static func hasExtent(_ points: [RunLatLng]) -> Bool {
        let lats = points.map(\.lat)
        let lngs = points.map(\.lng)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLng = lngs.min(), let maxLng = lngs.max() else { return false }
        let metersPerDegree = 111_000.0
        let latSpan = (maxLat - minLat) * metersPerDegree
        let lngSpan = (maxLng - minLng) * metersPerDegree * cos((minLat + maxLat) / 2 * .pi / 180)
        return max(latSpan, lngSpan) >= minimumDrawableSpanMeters
    }

    func path(in rect: CGRect) -> Path {
        let mapped = Self.project(points, into: rect)
        var path = Path()
        if mapped.count == 1, let only = mapped.first {
            path.addEllipse(in: CGRect(x: only.x - 2, y: only.y - 2, width: 4, height: 4))
        } else {
            path.addLines(mapped)
        }
        return path
    }

    /// 经纬度 → 视图坐标：经度乘 cos(纬度) 近似成等距（不然路线被横向拉宽），北在上，
    /// 按长边等比缩放后居中。GCJ-02 直接用，不转换（D1）。
    static func project(_ points: [RunLatLng], into rect: CGRect) -> [CGPoint] {
        guard !points.isEmpty else { return [] }
        let meanLatitude = points.map(\.lat).reduce(0, +) / Double(points.count)
        let xScale = cos(meanLatitude * .pi / 180)
        let xs = points.map { $0.lng * xScale }
        let ys = points.map(\.lat)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return [] }
        let span = max(maxX - minX, maxY - minY)
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        guard span > 0 else { return points.map { _ in centre } }
        let scale = Double(min(rect.width, rect.height)) / span
        let midX = (minX + maxX) / 2
        let midY = (minY + maxY) / 2
        return zip(xs, ys).map { x, y in
            CGPoint(x: centre.x + CGFloat((x - midX) * scale), y: centre.y - CGFloat((y - midY) * scale))
        }
    }
}
