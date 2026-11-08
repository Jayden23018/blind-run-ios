import Combine
import Foundation

// 跑步数据页（#710）的取数：近 12 个月的月度列表，并发拉，每到一个月重算一次（先到先画）。
// 火花、累计里程、累计陪伴由首页带进来（同一份数据，不另发请求，理由见 `VolunteerRunDataStreak`）。

nonisolated extension RunRecordMonth: Hashable {
    // `RunRecordMonth` 声明在别的文件里，合成的 Hashable 只在声明所在文件生效，所以手写。
    func hash(into hasher: inout Hasher) {
        hasher.combine(year)
        hasher.combine(month)
    }
}

@MainActor
final class VolunteerRunDataModel: ObservableObject {
    /// 页面加载状态（#865）：
    /// - `.loading`：一个月都还没回来。
    /// - `.loaded`：至少回来了一个月；`failedMonths` 里是没回来的（部分失败由页面另画一张会念的卡）。
    /// - `.failed`：12 个月全失败。
    @Published private(set) var phase: AsyncLoadState<VolunteerRunDataSummary> = .loading(requestID: UUID())
    @Published private(set) var failedMonths: Set<RunRecordMonth> = []
    /// 还在路上的月份数。全部回来前日历和平均都可能再变。
    @Published private(set) var pendingCount = 0

    let now: Date
    let calendar: Calendar
    let currentMonth: RunRecordMonth
    private var months: [RunRecordMonth: RunRecordHistoryResponse] = [:]
    private var hasStarted = false
    /// 一个月都没回来时的空汇总，只给 `summary` 兜底。
    private let emptySummary: VolunteerRunDataSummary

    /// 已经回来的那几个月的汇总。
    var summary: VolunteerRunDataSummary { phase.value ?? emptySummary }

    init(now: Date = Date(), calendar: Calendar = .volunteerRunData) {
        self.now = now
        self.calendar = calendar
        currentMonth = RunRecordMonth(containing: now, calendar: calendar)
        emptySummary = VolunteerRunDataSummary(months: [:], now: now, calendar: calendar)
    }

    /// 本月往前共 12 个月，旧的在前。
    var targetMonths: [RunRecordMonth] {
        var list = [currentMonth]
        while list.count < VolunteerRunDataSummary.yearMonths { list.insert(list[0].previous, at: 0) }
        return list
    }

    func loadIfNeeded(appState: AppState) async {
        guard !hasStarted else { return }
        hasStarted = true
        await fetch(targetMonths, appState: appState)
    }

    /// 只重拉失败的那几个月。
    func retry(appState: AppState) async {
        let failed = targetMonths.filter { failedMonths.contains($0) }
        guard !failed.isEmpty else { return }
        if months.isEmpty { phase = .loading(requestID: UUID()) }
        await fetch(failed, appState: appState)
    }

    private func fetch(_ targets: [RunRecordMonth], appState: AppState) async {
        let service = appState.runRecord
        let requestedUserId = appState.userId
        pendingCount += targets.count
        await withTaskGroup(of: (RunRecordMonth, RunRecordHistoryResponse?).self) { group in
            for month in targets {
                group.addTask {
                    do {
                        return (month, try await service.monthlyRecords(year: month.year, month: month.month))
                    } catch {
                        return (month, nil)
                    }
                }
            }
            for await (month, response) in group {
                pendingCount -= 1
                // 请求途中退出登录时不写回，否则上一个账号的记录会留给下一个账号（同首页「最近陪跑」）。
                guard BlindHomeIdleModel.isStillCurrent(
                    requestedUserId: requestedUserId,
                    currentUserId: appState.userId,
                    isCancelled: Task.isCancelled
                ) else { continue }
                record(month: month, response: response)
            }
        }
        // 取消（离开页面）不算失败：下次进页面重新来过。
        if Task.isCancelled {
            hasStarted = false
            pendingCount = 0
        }
    }

    /// 回来一个月写一个月。单测直接调它验「先到先画」与失败计数。
    func record(month: RunRecordMonth, response: RunRecordHistoryResponse?) {
        if let response {
            months[month] = response
            failedMonths.remove(month)
            phase = .loaded(VolunteerRunDataSummary(months: months, now: now, calendar: calendar))
        } else {
            failedMonths.insert(month)
            ClientFlowDiagnostics.record(event: "failed", operation: "volunteer-run-data-month")
            if months.isEmpty, failedMonths.count == targetMonths.count {
                phase = .failed(message: VolunteerRunDataCopy.allFailed)
            }
        }
    }
}
