import SwiftUI

// 「记录」tab 列表的卡片（#823 照健身重做）。页面与 view model 在 `RunRecordHistoryView.swift`，
// 拆出来只是因为那边已超过文件长度上限（SwiftLint 棘轮只许变小）。

// MARK: - Summary Cells

/// 汇总卡里的彩色数字格（#823：「11月」+ 跑步 N 次 琥珀 / 距离 X 公里 靛蓝）。陪跑员端多一格服务时长（天青）。
struct RunRecordSummaryCell: Equatable {
    let label: String
    let value: String
    let unit: String
    let tone: RunRecordMetricTone
}

extension RunRecordHistoryViewModel {
    /// 这个月一次都没跑时为空：卡里改写「X月还没有跑步记录。」那一句。
    var summaryCells: [RunRecordSummaryCell] {
        guard let summary = history?.monthSummary, summary.runs > 0 else { return [] }
        var cells = [RunRecordSummaryCell(label: role == .runner ? "跑步" : "陪跑", value: "\(summary.runs)", unit: "次", tone: .time)]
        if let distance = summary.distanceM {
            cells.append(RunRecordSummaryCell(label: "距离", value: Self.kilometres(distance), unit: "公里", tone: .distance))
        }
        if role == .volunteer, let minutes = summary.serviceMin {
            cells.append(RunRecordSummaryCell(label: "服务", value: Self.serviceDuration(minutes), unit: "", tone: .pace))
        }
        return cells
    }
}

/// 汇总卡的彩色数字格；大字号下竖排。读屏由外层合成整句，这里不单独暴露。
struct RunRecordSummaryCells: View {
    let cells: [RunRecordSummaryCell]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        layout {
            ForEach(cells, id: \.label) { cell in
                VStack(alignment: .leading, spacing: 2) {
                    Text(cell.label)
                        .font(.subheadline)
                        .foregroundColor(AppColors.textSecondary)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(cell.value).font(.title.weight(.bold)).monospacedDigit()
                        if !cell.unit.isEmpty { Text(cell.unit).font(.headline) }
                    }
                    .foregroundColor(cell.tone.color)
                }
                .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? nil : .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Rows

/// 一次跑步一张卡：左边「户外跑步」、靛蓝大号公里数、「日期 · 地点」；右边 88pt 小地图。
/// 大字号下小地图放到文字上面，文字才有整行宽度（不用 `ViewThatFits`，记忆 viewthatfits-fails-dynamic-type-audit）。
struct RunHistoryRow: View {
    let content: RunHistoryRowContent
    let thumbnail: [RunLatLng]?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        RunRecordCard {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    RunRecordListMap(points: thumbnail)
                    texts
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    texts.frame(maxWidth: .infinity, alignment: .leading)
                    RunRecordListMap(points: thumbnail)
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.accessibilityLabel)
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(RunRecordFitness.title)
                .font(.headline)
                .foregroundColor(AppColors.textPrimary)
            if let distance = content.distanceValue {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(distance).font(.title.weight(.bold)).monospacedDigit()
                    Text("公里").font(.headline)
                }
                .foregroundColor(AppColors.RunRecordMetric.distanceIndigo)
            }
            Text(content.detailText)
                .font(.subheadline)
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minHeight: FlowMetrics.actionButtonMinHeight, alignment: .leading)
    }
}

/// 「未完成的预约」一张卡（同款卡，不带地图）。跑者状态排最前（第一个词就判断「这单跑成没有」），
/// 陪跑员沿用 `VolunteerServiceRecordRow`。
struct UnfinishedBookingRow: View {
    let order: OrderDetailResponse
    let role: RunRecordHistoryRole

    var body: some View {
        RunRecordCard {
            switch role {
            case .runner:
                let dateText = (order.createdAt ?? order.plannedStart ?? "").displayDateTime
                VStack(alignment: .leading, spacing: 4) {
                    Text(order.status.displayName)
                        .font(.headline)
                        .foregroundColor(AppColors.textPrimary)
                    Text(dateText)
                        .font(.subheadline)
                        .foregroundColor(AppColors.textSecondary)
                    Text(order.startAddress ?? "地点未记录")
                        .font(.subheadline)
                        .foregroundColor(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, minHeight: FlowMetrics.actionButtonMinHeight, alignment: .leading)
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
        .contentShape(Rectangle())
    }
}
