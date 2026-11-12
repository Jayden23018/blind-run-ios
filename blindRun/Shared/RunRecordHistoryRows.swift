import SwiftUI

// 「记录」tab 列表的卡片（#823 照健身重做）。页面与 view model 在 `RunRecordHistoryView.swift`，
// 拆出来只是因为那边已超过文件长度上限（SwiftLint 棘轮只许变小）。

// MARK: - Summary Cells

/// 汇总卡里的彩色数字格（跑步 N 次 琥珀 / 距离 X 公里 靛蓝，#829 起卡里不再写月份）。陪跑员端多一格服务时长（天青）。
struct RunRecordSummaryCell: Equatable {
    let label: String
    let value: String
    let unit: String
    let tone: RunRecordMetricTone

    /// 数值拆成「数字 / 单位」交替的几段，数字用大字、单位用小字（#981）。
    /// 服务时长的 `value` 自带单位（「2 小时 32 分钟」），整串用大字时三格并排放不下，会被折成三行。
    var valueRuns: [(text: String, isNumber: Bool)] {
        value.split(separator: " ").map { token in
            (String(token), token.first?.isNumber == true)
        }
    }
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

/// 汇总卡的彩色数字格，格与格之间一条竖线（#829 参考图）；大字号下竖排、不画竖线。
/// 读屏由外层合成整句，这里不单独暴露。
struct RunRecordSummaryCells: View {
    let cells: [RunRecordSummaryCell]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(cells, id: \.label) { cellView($0) }
            }
        } else {
            HStack(alignment: .top, spacing: 12) {
                ForEach(Array(cells.enumerated()), id: \.element.label) { index, cell in
                    if index > 0 { Divider() }
                    cellView(cell)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        // 服务时长最长（「2 小时 32 分钟」），先拿够它要的宽度，余下的两格平分（#981）。
                        .layoutPriority(cell.valueRuns.count > 2 ? 1 : 0)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func cellView(_ cell: RunRecordSummaryCell) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(cell.label)
                .font(.subheadline)
                .foregroundColor(AppColors.textSecondary)
                .lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                ForEach(Array(cell.valueRuns.enumerated()), id: \.offset) { _, run in
                    Text(run.text)
                        .font(run.isNumber ? .title.weight(.bold) : .headline)
                        .monospacedDigit()
                }
                if !cell.unit.isEmpty { Text(cell.unit).font(.headline) }
            }
            // 一个数不许被拆成两行（「11.」「5 公里」，#981）；真放不下时整行等比缩小。
            // 大字号走上面的竖排分支，这里只管默认档附近。
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundColor(cell.tone.color)
        }
    }
}

// MARK: - Row Content

/// 一行记录的全部文字。抽出来是为了让「null 整段不显示」「朗读不念星号」能被单测钉住。
/// 负责人 11-07：不写和谁一起跑（「就只要记录跑步了就可以了」）。卡片版式照负责人参考图（#829）：
/// 左「11月6日 / 周五」，中间距离 + 地点，右小地图。
struct RunHistoryRowContent: Equatable {
    let dateText: String
    /// 卡片左栏两行：「11月6日」「周五」。时间解析不出时只有第一行（原样的时间串）。
    let dayText: String
    let weekdayText: String?
    let placeText: String?
    /// 「5.21」，没有距离为 nil（整格不出现）。
    let distanceValue: String?
    let distanceText: String?
    let accessibilityLabel: String
    /// 转子条目只念日期：转子是用来跳的，念完整行等于没有加速。
    let rotorLabel: String

    init(item: RunHistoryItem, role: RunRecordHistoryRole) {
        let date = item.finishedAt.backendTimestamp
        dateText = date.map { DateFormatter.aidRunDisplayMonthDayWeekday.string(from: $0) } ?? item.finishedAt
        dayText = date.map { DateFormatter.aidRunDisplayMonthDay.string(from: $0) } ?? item.finishedAt
        weekdayText = date.map { Self.weekdayFormatter.string(from: $0) }
        let place = item.place?.trimmingCharacters(in: .whitespaces)
        let shownPlace = place?.isEmpty == false ? place : nil
        placeText = shownPlace
        distanceValue = item.distanceM.map { RunRecordHistoryViewModel.kilometres($0) }
        distanceText = distanceValue.map { "\($0) 公里" }

        let spokenDistance = item.distanceM.map { "\(RunRecordHistoryViewModel.kilometres($0, spoken: true)) 公里" }
        accessibilityLabel = [dateText, shownPlace, spokenDistance]
            .compactMap { $0 }
            .joined(separator: "，")
        rotorLabel = dateText
    }

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "EEE"
        return formatter
    }()
}

// MARK: - Rows

/// 一次跑步一张卡（#829 参考图）：左「11月6日 / 周五」、竖线、中间靛蓝大号公里数 + 地点、右边小地图。
/// 大字号下竖排：小地图在上，文字才有整行宽度（不用 `ViewThatFits`，记忆 viewthatfits-fails-dynamic-type-audit）。
struct RunHistoryRow: View {
    let content: RunHistoryRowContent
    let thumbnail: [RunLatLng]?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        RunRecordCard {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    RunRecordListMap(points: thumbnail)
                    Text([content.dayText, content.weekdayText].compactMap { $0 }.joined(separator: " "))
                        .font(.headline)
                        .foregroundColor(AppColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    metrics
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    dateColumn
                    Divider().padding(.vertical, 8)
                    metrics.frame(maxWidth: .infinity, alignment: .leading)
                    RunRecordListMap(points: thumbnail)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(content.accessibilityLabel)
    }

    private var dateColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(content.dayText)
                .font(.headline)
                .foregroundColor(AppColors.textPrimary)
            if let weekday = content.weekdayText {
                Text(weekday)
                    .font(.subheadline)
                    .foregroundColor(AppColors.textSecondary)
            }
        }
        // 解析不出日期时 `dayText` 是后端原样的时间串，要让它换行，别把中间和地图挤出去。
        .fixedSize(horizontal: content.weekdayText != nil, vertical: false)
    }

    private var metrics: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let distance = content.distanceValue {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(distance).font(.title.weight(.bold)).monospacedDigit()
                    Text("公里").font(.headline)
                }
                .foregroundColor(AppColors.RunRecordMetric.distanceIndigo)
            }
            if let place = content.placeText {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Image(systemName: "mappin.and.ellipse")
                    Text(place).fixedSize(horizontal: false, vertical: true)
                }
                .font(.subheadline)
                .foregroundColor(AppColors.textSecondary)
            }
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
