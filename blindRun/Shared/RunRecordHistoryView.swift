import Combine
import SwiftUI

// 两端「记录」tab（OpenSpec `add-run-record-history-tab`，DECISIONS D9）。
//
// 上半部分是跑后记录的月度列表（`RunRecordServing.monthlyRecords`，`add-post-run-record` 交的数据层）；
// 已取消 / 暂无志愿者的单仍从 `GET /api/orders/mine` 取，收进底部「未完成的预约」。
// 两端共用一个结构（HANDOFF 6.1、`design-direction.md` §5.2：两端只在密度 / 层级 / 语气上有差异，
// 不分叉组件）—— 角色只决定文案、行的密度和点进去落到哪一页。
//
// 并发只用 async/await（AGENTS.md 硬约束）。

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

// MARK: - Month

/// 列表一次只显示一个月（项目负责人 2026-09-24 拍板：月份切换，不往下追加）。
nonisolated struct RunRecordMonth: Equatable, Sendable {
    let year: Int
    let month: Int

    init(year: Int, month: Int) {
        self.year = year
        self.month = month
    }

    init(containing date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month], from: date)
        self.init(year: parts.year ?? 2026, month: parts.month ?? 1)
    }

    var previous: RunRecordMonth {
        month == 1 ? RunRecordMonth(year: year - 1, month: 12) : RunRecordMonth(year: year, month: month - 1)
    }

    var next: RunRecordMonth {
        month == 12 ? RunRecordMonth(year: year + 1, month: 1) : RunRecordMonth(year: year, month: month + 1)
    }

    /// 同一年只说「9月」；跨年才带年份，不然 1 月往回翻到的「12月」会被听成今年的 12 月。
    func title(relativeTo current: RunRecordMonth) -> String {
        year == current.year ? "\(month)月" : "\(year)年\(month)月"
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

    func load() async {
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

    private func switchTo(_ target: RunRecordMonth) async {
        month = target
        history = nil
        errorMessage = nil
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
        } catch {
            guard target == month else { return }
            recordFailure(error)
        }
        if target == month { isLoading = false }
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

    /// 已取消 / 暂无志愿者，最近的在前。进行中的由首页管，未知状态不当成「已结束」替用户下结论。
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

    /// 跑者端加载完要出声：加载态那一行被列表换掉时读屏焦点会被系统收走，
    /// 用户既没听到结果也不知道停在哪（此前 `BlindRunHistoryViewModel` 的同一条理由）。
    /// 陪跑员端一直是静默的，不在这次顺手加。
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

    /// 月度汇总。`spoken` 时去掉姓名里的掩码星号（只进读屏，屏幕上照原样显示）。
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
            text += "。"
            if let partner = summary.topPartner, let name = partner.name {
                text += "其中和\(spoken ? name.unmaskedForSpeech : name)跑了 \(partner.runs) 次。"
            }
            return text
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
            return ("还没有陪跑记录", "完成第一次陪跑后，记录会出现在这里。开启可服务状态后，系统会自动派单。")
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

// MARK: - Row Content

/// 一行记录的全部文字。抽出来是为了让「null 整段不显示」「朗读不念星号」能被单测钉住。
struct RunHistoryRowContent: Equatable {
    let dateText: String
    let detailText: String?
    let distanceText: String?
    let accessibilityLabel: String
    /// 转子条目只念日期：转子是用来跳的，念完整行等于没有加速。
    let rotorLabel: String

    init(item: RunHistoryItem, role: RunRecordHistoryRole) {
        let date = item.finishedAt.backendTimestamp
        dateText = date.map { Self.dateFormatter.string(from: $0) } ?? item.finishedAt
        let spokenDate = dateText

        func detail(spoken: Bool) -> String? {
            let name = item.partnerName.map { spoken ? $0.unmaskedForSpeech : $0 }
            let parts: [String?]
            switch role {
            case .runner: parts = [item.place, name.map { "和\($0)" }]
            case .volunteer: parts = [name.map { "陪\($0)" }, item.place]
            }
            let joined = parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "，")
            return joined.isEmpty ? nil : joined
        }
        detailText = detail(spoken: false)
        distanceText = item.distanceM.map { "\(RunRecordHistoryViewModel.kilometres($0)) 公里" }

        let spokenDistance = item.distanceM.map { "\(RunRecordHistoryViewModel.kilometres($0, spoken: true)) 公里" }
        accessibilityLabel = [spokenDate, detail(spoken: true), spokenDistance]
            .compactMap { $0 }
            .joined(separator: "，")
        rotorLabel = spokenDate
    }

    /// 「9月20日 周六」。
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 EEE"
        return formatter
    }()
}

// MARK: - View

struct RunRecordHistoryView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService
    @StateObject private var viewModel: RunRecordHistoryViewModel
    /// 加载完成后把读屏焦点落到第一条记录上，只在条数从 0 变成非 0 时动（沿用旧跑者列表的做法）。
    @AccessibilityFocusState private var focusedRecordID: Int64?

    init(role: RunRecordHistoryRole) {
        _viewModel = StateObject(wrappedValue: RunRecordHistoryViewModel(role: role))
    }

    private var role: RunRecordHistoryRole { viewModel.role }
    private var items: [RunHistoryItem] { viewModel.history?.items ?? [] }

    var body: some View {
        List {
            if let errorMessage = viewModel.errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundColor(AppColors.destructive)
                    Button("重试") {
                        Task { await viewModel.load() }
                    }
                    .frame(maxWidth: .infinity, minHeight: FlowMetrics.actionButtonMinHeight, alignment: .leading)
                    .accessibilityHint("重新加载\(role.title)")
                    .accessibilityIdentifier("runRecordHistoryRetry")
                }
            }

            Section {
                if let summary = viewModel.summaryText() {
                    Text(summary)
                        .font(role == .runner ? .title3 : AppFonts.body())
                        .foregroundColor(AppColors.textPrimary)
                        .accessibilityLabel(viewModel.summaryText(spoken: true) ?? summary)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("runRecordHistorySummary")
                }
                monthSwitchRow(
                    title: "上个月：\(viewModel.previousMonthTitle)",
                    identifier: "runRecordHistoryPreviousMonth"
                ) { await viewModel.showPreviousMonth() }
                if viewModel.canShowNextMonth {
                    monthSwitchRow(
                        title: "下个月：\(viewModel.nextMonthTitle)",
                        identifier: "runRecordHistoryNextMonth"
                    ) { await viewModel.showNextMonth() }
                }
            }

            Section {
                if viewModel.history == nil && viewModel.isLoading {
                    loadingPlaceholder
                } else if viewModel.showsFirstRunEmptyState {
                    EmptyStateView(title: viewModel.emptyStateCopy.title, message: viewModel.emptyStateCopy.message)
                } else {
                    ForEach(items, id: \.orderId) { item in
                        NavigationLink {
                            completedDestination(orderId: item.orderId)
                        } label: {
                            RunHistoryRow(content: RunHistoryRowContent(item: item, role: role), role: role, thumbnail: item.thumbnail)
                        }
                        .accessibilityFocused($focusedRecordID, equals: item.orderId)
                    }
                }
            }

            if !viewModel.unfinished.isEmpty {
                Section {
                    ForEach(viewModel.unfinished, id: \.orderId) { order in
                        NavigationLink {
                            unfinishedDestination(order)
                        } label: {
                            UnfinishedBookingRow(order: order, role: role)
                        }
                    }
                } header: {
                    // 系统组标题色是 `secondaryLabel`，浅色下只有 3.26:1（`AppColors.textSecondary` 那段注释），
                    // 真机审计报了 Contrast nearly passed。
                    Text("未完成的预约")
                        .foregroundColor(AppColors.textSecondary)
                        .accessibilityAddTraits(.isHeader)
                }
            }
        }
        .navigationTitle(role.title)
        .accessibilityIdentifier("runRecordHistoryList")
        // 自定义转子：列表里混着本月记录和未完成的预约，逐行右滑要听完每一条。条件与 ForEach 同源。
        .accessibilityRotor(
            "已完成的跑步",
            entries: items,
            entryID: \.orderId,
            entryLabel: \.rotorDateLabel
        )
        .onChange(of: items.count) { count in
            guard count > 0, focusedRecordID == nil else { return }
            focusedRecordID = items.first?.orderId
        }
        .task {
            viewModel.configure(with: appState, speechService: speechService)
            await viewModel.load()
        }
        .refreshable {
            await viewModel.load()
        }
    }

    private func monthSwitchRow(title: String, identifier: String, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            Text(title)
                .font(AppFonts.body())
                .frame(maxWidth: .infinity, minHeight: FlowMetrics.actionButtonMinHeight, alignment: .leading)
                .contentShape(Rectangle())
        }
        .disabled(viewModel.isLoading)
        .accessibilityIdentifier(identifier)
    }

    /// 骨架屏：三行占位，读屏只读一句（HANDOFF 6.4）。
    private var loadingPlaceholder: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 4) {
                    Text("9月20日 周六")
                    Text("深圳湾公园，和小林")
                }
                .frame(minHeight: FlowMetrics.actionButtonMinHeight, alignment: .leading)
            }
        }
        .redacted(reason: .placeholder)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(viewModel.loadingLabel)
        .accessibilityIdentifier("runRecordHistoryLoading")
    }

    /// 陪跑员进跑后详情（阶段 4）；跑者仍落到订单详情，跑者跑后详情是阶段 5。
    @ViewBuilder
    private func completedDestination(orderId: Int64) -> some View {
        switch role {
        case .runner:
            // 跑者详情页是补评价唯一的入口，也内嵌轨迹摘要。
            BlindOrderStatusView(orderId: orderId) { _ in }
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

// MARK: - Rows

private struct RunHistoryRow: View {
    let content: RunHistoryRowContent
    let role: RunRecordHistoryRole
    let thumbnail: [RunLatLng]?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            // 最大几档字号下横排必然截断（`design-direction.md` §7：窄屏三列网格在 AX5 截成「…」），
            // 改成竖排；不用 `ViewThatFits`（记忆 `viewthatfits-fails-dynamic-type-audit`）。
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    thumbnailView
                    texts
                    distance
                }
            } else {
                HStack(spacing: 12) {
                    thumbnailView
                    texts.frame(maxWidth: .infinity, alignment: .leading)
                    distance
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: FlowMetrics.actionButtonMinHeight, alignment: .leading)
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.accessibilityLabel)
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if role == .volunteer {
            RunRouteThumbnail(points: thumbnail)
                .frame(width: 48, height: 48)
                .accessibilityHidden(true)
        }
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(content.dateText)
                .font(role == .runner ? .title3.weight(.semibold) : AppFonts.body().weight(.semibold))
                .foregroundColor(AppColors.textPrimary)
            if let detail = content.detailText {
                Text(detail)
                    .font(role == .runner ? AppFonts.body() : .subheadline)
                    .foregroundColor(AppColors.textSecondary)
            }
        }
    }

    @ViewBuilder
    private var distance: some View {
        if let distanceText = content.distanceText {
            Text(distanceText)
                .font((role == .runner ? Font.title3 : .body).weight(.semibold).monospacedDigit())
                .foregroundColor(AppColors.textPrimary)
        }
    }
}

/// 「未完成的预约」一行。沿用两端改版前各自的行：跑者状态排最前（第一个词就判断「这单跑成没有」），
/// 陪跑员沿用 `VolunteerServiceRecordRow`。
private struct UnfinishedBookingRow: View {
    let order: OrderDetailResponse
    let role: RunRecordHistoryRole

    var body: some View {
        switch role {
        case .runner:
            let dateText = (order.createdAt ?? order.plannedStart ?? "").displayDateTime
            VStack(alignment: .leading, spacing: 6) {
                Text(order.status.displayName)
                    .font(AppFonts.body().weight(.semibold))
                    .foregroundColor(AppColors.textSecondary)
                Text(dateText)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textPrimary)
                Text(order.startAddress ?? "地点未记录")
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: FlowMetrics.actionButtonMinHeight, alignment: .leading)
            .padding(.vertical, 4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(order.status.displayName)，\(dateText)，出发地 \(order.startAddress ?? "未记录")")
        case .volunteer:
            let record = VolunteerServiceRecord(order: order)
            VolunteerServiceRecordRow(record: record)
                .frame(maxWidth: .infinity, minHeight: FlowMetrics.actionButtonMinHeight, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(record.accessibilityLabel)
        }
    }
}

// MARK: - Thumbnail

/// 陪跑员行左侧的路线缩略图。纯 `Path`，不用高德截图（负责人 2026-09-24 拍板，
/// 依据 `docs/research/amap-snapshot-for-list-thumbnail-20260924.md`）。
/// 没有点（超过 90 天留存期 / 后端这次没补算）时只画底块，保持各行对齐。
struct RunRouteThumbnail: View {
    let points: [RunLatLng]?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppColors.secondaryBackground)
            if let points, !points.isEmpty {
                RunRouteShape(points: points)
                    .stroke(AppColors.paceFast, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .padding(7)
            }
        }
    }
}

nonisolated struct RunRouteShape: Shape {
    let points: [RunLatLng]

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
