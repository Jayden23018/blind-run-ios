import Accessibility
import SwiftUI

/// 配速图的读屏描述与 Audio Graph 数据（HANDOFF §7 第 4 条）。两个角色的详情页共用。
struct RunPaceChartDescriptor: AXChartDescriptorRepresentable {
    let samples: [RunPaceSample]
    let average: Int?
    var stops: [RunStop] = []
    /// 最快的是第几公里（原型 data-vo「第3公里最快」）。地图描述和分段里有，图的摘要也要有。
    var fastestKilometre: Int?

    var summary: String {
        let paces = samples.map(\.paceSecPerKm)
        var parts: [String] = []
        if let average { parts.append("平均\(RunRecordText.spokenPace(average))") }
        if let fastest = paces.min() { parts.append("最快\(RunRecordText.spokenPace(fastest))") }
        if let slowest = paces.max() { parts.append("最慢\(RunRecordText.spokenPace(slowest))") }
        if let fastestKilometre { parts.append("第\(fastestKilometre)公里最快") }
        // 图上画了休息竖线，读屏也要有（原型 data-vo「2.6公里处休息」）。数字与单位间留空格（阶段 3 审计）。
        parts += stops.map { "\(RunRecordText.kilometres($0.atDistanceM, spoken: true)) 公里处休息" }
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
