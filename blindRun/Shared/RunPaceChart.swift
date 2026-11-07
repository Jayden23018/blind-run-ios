import Charts
import SwiftUI

// 跑后详情的配速图（#823 从陪跑员页挪到 Shared，两端共用）。共享组件的说明见 `RunRecordFitnessComponents.swift`。

// MARK: - 配速图（照健身心率图，两端共用）

/// 按配速着色的竖条 + 平均虚线 + 「最慢」标注 + 休息竖线。条越高跑得越快。
/// 整张卡是一个读屏元素，逐点浏览与声音图表交给 `RunPaceChartDescriptor`（HANDOFF 第 7 节）。
struct RunPaceChart: View {
    let samples: [RunPaceSample]
    let average: Int?
    let stops: [RunStop]
    let fastestKilometre: Int?
    let scale: RunPaceScale
    /// 跑者端 `false`：屏幕上一律「6分14秒」（HANDOFF 5.3）。
    var apostrophePace: Bool = true
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        RunRecordCard {
            VStack(alignment: .leading, spacing: 8) {
                if let slowest = samples.map(\.paceSecPerKm).max() {
                    Text("最慢 \(RunRecordFitness.paceText(slowest, apostrophe: apostrophePace))")
                        .font(.footnote)
                        .foregroundColor(AppColors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                chart
                if let average {
                    Text("平均 \(RunRecordFitness.paceText(average, apostrophe: apostrophePace))/公里")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(AppColors.RunRecordMetric.paceTeal)
                }
                // 颜色表达的信息要有文字冗余（HANDOFF 第 7 节）：路线和竖条同一套配色，图例写明两端是快和慢。
                RunPaceLegend()
            }
            // 整张卡一个元素：上下几行字和图说的是同一件事，摘要里都有。
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("配速图")
            .accessibilityValue(descriptor.summary)
            .accessibilityChartDescriptor(descriptor)
            .accessibilityIdentifier("runRecordPaceChart")
        }
    }

    private var chart: some View {
        // 条高 = 「最慢再慢 30 秒」减去配速：快（数小）条高、慢条矮，最慢那根也看得见。范围按数据定死。
        let paces = samples.map(\.paceSecPerKm)
        let floor = Double((paces.max() ?? 0) + 30)
        let ceiling = floor - Double((paces.min() ?? 0) - 10)
        let isDark = colorScheme == .dark
        let total = Double(samples.last?.distanceM ?? 0)
        // 每根竖条占「上一个采样点 → 本采样点」那一段距离：x 是连续的公里数，`BarMark` 的 `.ratio` 宽度在这里没有步长可比。
        let bars = Self.bars(samples)
        return Chart {
            ForEach(bars, id: \.sample.distanceM) { bar in
                RectangleMark(
                    xStart: .value("起", bar.startKm),
                    xEnd: .value("止", bar.endKm),
                    yStart: .value("底", 0),
                    yEnd: .value("配速", floor - Double(bar.sample.paceSecPerKm))
                )
                .foregroundStyle(Color(uiColor: RunPacePalette.color(fraction: scale.fraction(bar.sample.paceSecPerKm), isDark: isDark)))
            }
            if let average {
                RuleMark(y: .value("平均配速", floor - Double(average)))
                    .foregroundStyle(AppColors.textSecondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
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
        .chartYScale(domain: 0...max(ceiling, 1))
        .chartYAxis(.hidden)
        .chartXScale(domain: 0...max(total / 1000, 0.1))
        // 刻度只写数字、单位写一次：每个刻度都带「公里」在大字号下会叠在一起。
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisValueLabel {
                    if let km = value.as(Double.self) {
                        Text(km.formatted(.number.precision(.fractionLength(0...1))))
                    }
                }
            }
        }
        .chartXAxisLabel("公里", alignment: .trailing)
        .frame(height: dynamicTypeSize.isAccessibilitySize ? 260 : 170)
    }

    /// 按距离排好序，每个采样点占从上一个点到它的那一段；第一个点从 0 起。条与条之间留 2% 的缝（照健身）。
    static func bars(_ samples: [RunPaceSample]) -> [(sample: RunPaceSample, startKm: Double, endKm: Double)] {
        let sorted = samples.sorted { $0.distanceM < $1.distanceM }
        var previous = 0.0
        return sorted.map { sample in
            let end = Double(sample.distanceM) / 1000
            let start = previous
            previous = end
            return (sample, start + (end - start) * 0.02, end)
        }
    }

    private var descriptor: RunPaceChartDescriptor {
        RunPaceChartDescriptor(samples: samples, average: average, stops: stops, fastestKilometre: fastestKilometre)
    }
}
