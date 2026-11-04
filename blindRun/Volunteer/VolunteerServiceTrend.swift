import Accessibility
import Combine
import Foundation
import SwiftUI

// 服务成就页头卡的「近 6 个月陪伴时长」与提要卡（#697，照健康 · 步数详情）。
//
// 数据：契约里没有按月的历史数组，只能逐月调 `GET /api/orders/mine/run-records?month=`，
// 取 `monthSummary.serviceMin`（仅陪跑员有值）。一次进页 6 个请求，并发发出。

/// 一个月的陪伴时长。`minutes == nil` = 这个月没读到（请求失败或后端没给），**不当 0 画**。
struct VolunteerServiceMonth: Equatable, Identifiable {
    let year: Int
    let month: Int
    let minutes: Int64?

    var id: String { "\(year)-\(month)" }
    /// 柱子下面的「11月」。
    var label: String { "\(month)月" }
}

enum VolunteerServiceTrend {
    static let monthCount = 6
    /// 提要卡比较的是本月与「前 5 个月」。
    static var previousMonthCount: Int { monthCount - 1 }

    /// 含本月在内往前 6 个月，**从早到晚**。
    static func recentMonths(endingAt now: Date, calendar: Calendar = .current) -> [(year: Int, month: Int)] {
        (0..<monthCount).reversed().compactMap { back in
            guard let date = calendar.date(byAdding: .month, value: -back, to: now) else { return nil }
            let parts = calendar.dateComponents([.year, .month], from: date)
            guard let year = parts.year, let month = parts.month else { return nil }
            return (year, month)
        }
    }

    /// 前 5 个月里**读到了的**那些月的平均分钟数（向下取整）。一个都没读到时为 nil。
    static func previousAverage(_ months: [VolunteerServiceMonth]) -> Int64? {
        let previous = months.dropLast().compactMap(\.minutes)
        guard !previous.isEmpty else { return nil }
        return previous.reduce(0, +) / Int64(previous.count)
    }

    static func current(_ months: [VolunteerServiceMonth]) -> Int64? {
        months.last?.minutes
    }

    /// 6 个月一个都没读到 ⇒ 不画图表、不显示提要卡。
    static func hasAnyData(_ months: [VolunteerServiceMonth]) -> Bool {
        months.contains { $0.minutes != nil }
    }

    /// 提要卡那一句结论。本月或平均缺一个就没有结论（不编比较）。
    static func summarySentence(_ months: [VolunteerServiceMonth]) -> String? {
        guard let current = current(months), let average = previousAverage(months) else { return nil }
        if current > average {
            return "这个月的陪伴时长比前 \(previousMonthCount) 个月平均多。"
        }
        if current < average {
            return "这个月的陪伴时长比前 \(previousMonthCount) 个月平均少。"
        }
        return "这个月的陪伴时长和前 \(previousMonthCount) 个月平均一样。"
    }

    /// 柱状图的一句总结（HIG Charting data：图要有一句总结；读屏也念这一句）。
    /// 「近 6 个月，11月最多，3 小时 20 分钟」。
    static func chartSummary(_ months: [VolunteerServiceMonth]) -> String {
        let read = months.filter { $0.minutes != nil }
        guard let top = read.max(by: { ($0.minutes ?? 0) < ($1.minutes ?? 0) }),
              let minutes = top.minutes, minutes > 0 else {
            return "近 \(monthCount) 个月还没有陪伴时长"
        }
        let name = top == months.last ? "本月" : top.label
        return "近 \(monthCount) 个月，\(name)最多，\(duration(minutes))"
    }

    static func duration(_ minutes: Int64) -> String {
        RunRecordHistoryViewModel.serviceDuration(max(0, minutes))
    }

    /// 「12 小时 40 分钟」拆成数字和单位两段，好让数字大、单位小。
    static func durationParts(_ minutes: Int64) -> [(value: String, unit: String)] {
        let clamped = max(0, minutes)
        let hours = clamped / 60
        let rest = clamped % 60
        switch (hours, rest) {
        case (0, _): return [("\(rest)", "分钟")]
        case (_, 0): return [("\(hours)", "小时")]
        default: return [("\(hours)", "小时"), ("\(rest)", "分钟")]
        }
    }
}

// MARK: - 加载

/// 并发拉 6 个月。只用 async/await（AGENTS.md：不混 Combine 订阅）。
@MainActor
final class VolunteerServiceTrendLoader: ObservableObject {
    /// nil = 还没拉完。拉完后恒为 6 个月（读不到的那个月 `minutes == nil`）。
    @Published private(set) var months: [VolunteerServiceMonth]?

    func load(service: any RunRecordServing, now: Date = Date(), calendar: Calendar = .current) async {
        let targets = VolunteerServiceTrend.recentMonths(endingAt: now, calendar: calendar)
        let results = await withTaskGroup(of: (Int, Int64?).self) { group in
            for (index, target) in targets.enumerated() {
                group.addTask {
                    // 单月失败不连坐：这个月记缺失，其余照画。错误不弹，成就页主体自己有失败态。
                    let minutes = try? await service
                        .monthlyRecords(year: target.year, month: target.month)
                        .monthSummary.serviceMin
                    return (index, minutes)
                }
            }
            var collected: [Int: Int64?] = [:]
            for await (index, minutes) in group {
                collected[index] = minutes
            }
            return collected
        }
        months = targets.enumerated().map { index, target in
            VolunteerServiceMonth(year: target.year, month: target.month, minutes: results[index] ?? nil)
        }
    }
}

// MARK: - 读屏图表

/// 柱状图的读屏描述与 Audio Graph（照 `RunPaceChartDescriptor`）。
struct VolunteerServiceChartDescriptor: AXChartDescriptorRepresentable {
    let months: [VolunteerServiceMonth]

    func makeChartDescriptor() -> AXChartDescriptor {
        let read = months.filter { $0.minutes != nil }
        let top = Double(read.compactMap(\.minutes).max() ?? 0)
        let xAxis = AXCategoricalDataAxisDescriptor(title: "月份", categoryOrder: months.map(\.label))
        let yAxis = AXNumericDataAxisDescriptor(
            title: "陪伴时长",
            range: 0...max(1, top),
            gridlinePositions: []
        ) { VolunteerServiceTrend.duration(Int64($0)) }
        let series = AXDataSeriesDescriptor(
            name: "陪伴时长",
            isContinuous: false,
            dataPoints: read.map { AXDataPoint(x: $0.label, y: Double($0.minutes ?? 0)) }
        )
        return AXChartDescriptor(
            title: "近 \(VolunteerServiceTrend.monthCount) 个月陪伴时长",
            summary: VolunteerServiceTrend.chartSummary(months),
            xAxis: xAxis,
            yAxis: yAxis,
            additionalAxes: [],
            series: [series]
        )
    }
}
