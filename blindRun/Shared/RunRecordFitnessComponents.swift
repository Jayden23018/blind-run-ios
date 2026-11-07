import SwiftUI

// 跑步记录照苹果「健身」重做（#823，负责人 2026-11-07 批准定稿）的共享组件：两端详情页与列表都从这里取。
// 版式照健身体能训练详情；颜色只用 `AppColors.RunRecordMetric`（已批准取值的别名），组件用本 App 的分组卡。
// 决定与原话见 `docs/ui/mockups/run-record/DECISIONS.md`「11-07 照健身重做」。
//
// 字号一律系统文字样式（不乘 `@ScaledMetric`，记忆 scaledmetric-system-size-fails-dynamic-type-audit）；
// 大字号下改竖排用 `dynamicTypeSize` 判断，不用竖向 `ViewThatFits`（记忆 viewthatfits-fails-dynamic-type-audit）。

// MARK: - 文字

enum RunRecordFitness {
    /// 两端详情标题（列表行 #829 起不写标题；负责人 11-07：不写和谁一起跑，「就只要记录跑步了就可以了」）。
    static let title = "户外跑步"

    /// 「0:19:57」：健身的时间格写法，小时位为 0 也写。
    static func longClock(_ seconds: Int) -> String {
        String(format: "%d:%02d:%02d", seconds / 3600, seconds % 3600 / 60, seconds % 60)
    }

    /// 单段表的累计用时：「06:12」「19:57」，满一小时「1:02:03」（照健身）。
    static func splitClock(_ seconds: Int) -> String {
        seconds >= 3600 ? longClock(seconds) : String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    /// 屏幕上的配速。跑者端「6分14秒」（HANDOFF 5.3：跑者页不许出现撇号），陪跑员端「6'14"」。
    static func paceText(_ secondsPerKm: Int, apostrophe: Bool) -> String {
        apostrophe ? RunRecordText.pace(secondsPerKm) : RunRecordText.spokenDuration(secondsPerKm)
    }

    /// 「2026年9月24日 05:10–05:32」。没有结束时间就只写开始。
    static func dateRange(start: Date?, end: Date?) -> String? {
        guard let start else { return nil }
        let head = dayFormatter.string(from: start) + " " + timeFormatter.string(from: start)
        guard let end, end > start else { return head }
        return head + "–" + timeFormatter.string(from: end)
    }

    /// 读屏版：「05:10到05:32」。
    static func spokenDateRange(start: Date?, end: Date?) -> String? {
        dateRange(start: start, end: end)?.replacingOccurrences(of: "–", with: "到")
    }

    /// 「详细信息」卡，照健身顺序。没有数据（null）的格整格不出现，不写 0（HANDOFF 6.4）。
    static func detailMetrics(summary: RunSummary?, apostrophePace: Bool) -> [RunRecordMetric] {
        guard let summary else { return [] }
        return [
            summary.movingSec.map {
                RunRecordMetric(label: "运动时间", value: longClock($0), unit: nil, tone: .time,
                                spoken: "运动时间，\(RunRecordText.spokenDuration($0))")
            },
            summary.distanceM.map {
                RunRecordMetric(label: "距离", value: RunRecordText.kilometres($0), unit: "公里", tone: .distance,
                                spoken: "距离，\(RunRecordText.kilometres($0, spoken: true)) 公里")
            },
            summary.avgPaceSecPerKm.map {
                RunRecordMetric(label: "平均配速", value: paceText($0, apostrophe: apostrophePace), unit: "/公里", tone: .pace,
                                spoken: "平均配速，\(RunRecordText.spokenPace($0))")
            },
            summary.elevationGainM.map {
                RunRecordMetric(label: "累计爬升", value: "\($0)", unit: "米", tone: .climb, spoken: "累计爬升，\($0) 米")
            },
            summary.steps.map {
                RunRecordMetric(label: "步数", value: $0.formatted(), unit: "步", tone: .cadence, spoken: "步数，\($0)步")
            },
            summary.avgCadence.map {
                RunRecordMetric(label: "平均步频", value: "\($0)", unit: "步/分", tone: .cadence, spoken: "平均步频，每分钟\($0)步")
            },
            summary.elapsedSec.map {
                RunRecordMetric(label: "总时长（含休息）", value: longClock($0), unit: nil, tone: .time,
                                spoken: "总时长（含休息），\(RunRecordText.spokenDuration($0))")
            },
            summary.restSec.map {
                RunRecordMetric(label: "中途休息", value: RunRecordText.clock($0), unit: nil, tone: .time,
                                spoken: "中途休息，\(RunRecordText.spokenDuration($0))")
            }
        ].compactMap { $0 }
    }

    /// 每一段跑完时的累计用时（秒），与 `splits` 一一对应。单段表的时间列照健身写累计（负责人 11-07 选）。
    static func cumulativeSeconds(_ splits: [RunSplit]) -> [Int] {
        var total = 0
        return splits.map { split in
            total += split.durationSec
            return total
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

enum RunRecordMetricTone: Hashable {
    case time, distance, pace, cadence, climb

    var color: Color {
        switch self {
        case .time: return AppColors.RunRecordMetric.timeAmber
        case .distance: return AppColors.RunRecordMetric.distanceIndigo
        case .pace: return AppColors.RunRecordMetric.paceTeal
        case .cadence: return AppColors.RunRecordMetric.cadenceOrange
        case .climb: return AppColors.RunRecordMetric.climbGreen
        }
    }
}

struct RunRecordMetric: Hashable {
    let label: String
    let value: String
    let unit: String?
    let tone: RunRecordMetricTone
    let spoken: String
}

/// 头部下面那一行小数据（照健身的天气行）：值在上、灰标签在下。
struct RunRecordSmallStat: Hashable {
    let value: String
    let label: String
    let spoken: String
}

/// 单段表的一行。时间列是累计用时（负责人 11-07 选），不标「最快」（「最快这种标识不需要标，让用户看就可以了」）。
struct RunRecordSplitTableRow: Hashable {
    let index: Int
    /// 灰色序号：满公里写「1」，最后不足一公里写「0.2」。
    let indexText: String
    let elapsedText: String
    let paceText: String
    let cadenceText: String?
    let accessibilityLabel: String
    let identifier: String
}

// MARK: - 页面骨架

/// 跑步记录详情的分组卡：白卡 / `#1C1C1E` 卡，压 `Flow.page` 页底（同健康 App）。
struct RunRecordCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.Flow.surface)
        .clipShape(RoundedRectangle(cornerRadius: GroupedCardMetrics.cardRadius, style: .continuous))
    }
}

/// 卡片上方的节标题（「详细信息」「单段」「配速」）。
struct RunRecordSectionTitle: View {
    let text: String
    var spoken: String?

    var body: some View {
        Text(text)
            .font(.title2.weight(.bold))
            .foregroundColor(AppColors.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(spoken ?? text)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - 头部

/// 地图下沿叠着的头部：地点、大标题「户外跑步」、彩色距离、日期与起止时间。读屏是调用方给的一整句。
struct RunRecordHeroHeader: View {
    let place: String?
    let distanceText: String?
    let dateRange: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let place {
                Label(place, systemImage: "mappin.circle")
                    .font(.subheadline)
                    .foregroundColor(AppColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(RunRecordFitness.title)
                .font(.largeTitle.weight(.heavy))
                .foregroundColor(AppColors.textPrimary)
            if let distanceText {
                // 数字和单位之间留空格（阶段 3 审计判「标签不可读」）。
                Text("\(distanceText) 公里")
                    .font(.largeTitle.weight(.heavy))
                    .monospacedDigit()
                    .foregroundColor(AppColors.RunRecordMetric.distanceIndigo)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let dateRange {
                Text(dateRange)
                    .font(AppFonts.body())
                    .monospacedDigit()
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 头部下面一行小数据；大字号下竖排。读屏每格一句。
struct RunRecordSmallStatsRow: View {
    let stats: [RunRecordSmallStat]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 28))
        layout {
            ForEach(stats, id: \.self) { stat in
                VStack(alignment: .leading, spacing: 2) {
                    Text(stat.value)
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                        .foregroundColor(AppColors.textPrimary)
                    Text(stat.label)
                        .font(.subheadline)
                        .foregroundColor(AppColors.textSecondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(stat.spoken)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 详细信息

/// 两列指标格；大字号（≥ accessibility1）退单列。每格读屏一句「标签，值」。
struct RunRecordMetricGrid: View {
    let metrics: [RunRecordMetric]
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let columns = dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible(), alignment: .leading)]
            : [GridItem(.flexible(), spacing: 12, alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading)]
        RunRecordCard {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                ForEach(metrics, id: \.label) { metric in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(metric.label)
                            .font(.subheadline)
                            .foregroundColor(AppColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(metric.value)
                                .font(.title.weight(.bold))
                                .monospacedDigit()
                            if let unit = metric.unit {
                                Text(unit).font(.headline)
                            }
                        }
                        .foregroundColor(metric.tone.color)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(metric.spoken)
                }
            }
        }
    }
}

// MARK: - 单段

/// 照健身的单段表：灰序号 + 累计用时（琥珀）+ 平均配速（天青）+ 步频（橙），列头小灰字、行间细线。
/// `onSelect` 非 nil 时（陪跑员端有地图）点一行在地图上高亮那一段。大字号下每行竖排、去掉列头。
struct RunRecordSplitTable: View {
    let rows: [RunRecordSplitTableRow]
    var selected: Int?
    var onSelect: ((Int) -> Void)?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var showsCadence: Bool { rows.contains { $0.cadenceText != nil } }

    var body: some View {
        RunRecordCard {
            if !dynamicTypeSize.isAccessibilitySize {
                columns(index: Text(""), elapsed: Text("累计用时"), pace: Text("平均配速"), cadence: showsCadence ? Text("步频") : nil)
                    .font(.footnote)
                    .foregroundColor(AppColors.textSecondary)
                    .padding(.bottom, 8)
                    .accessibilityHidden(true)
                GroupedCardDivider(leadingInset: 0)
            }
            ForEach(Array(rows.enumerated()), id: \.element.index) { offset, row in
                if offset > 0 { GroupedCardDivider(leadingInset: 0) }
                if let onSelect {
                    Button { onSelect(row.index) } label: { rowContent(row) }
                        .buttonStyle(.plain)
                        .accessibilityHint("在地图上高亮这一段")
                        .accessibilityAddTraits(selected == row.index ? .isSelected : [])
                        .accessibilityIdentifier(row.identifier)
                } else {
                    rowContent(row)
                        .accessibilityIdentifier(row.identifier)
                }
            }
        }
    }

    @ViewBuilder
    private func rowContent(_ row: RunRecordSplitTableRow) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.indexText).font(.title3.weight(.semibold)).foregroundColor(AppColors.textSecondary)
                    Text(row.elapsedText).foregroundColor(AppColors.RunRecordMetric.timeAmber)
                    Text(row.paceText).foregroundColor(AppColors.RunRecordMetric.paceTeal)
                    if let cadence = row.cadenceText {
                        Text(cadence).foregroundColor(AppColors.RunRecordMetric.cadenceOrange)
                    }
                }
                .font(.title2.weight(.bold))
                .padding(.vertical, 8)
            } else {
                columns(
                    index: Text(row.indexText).foregroundColor(AppColors.textSecondary),
                    elapsed: Text(row.elapsedText).foregroundColor(AppColors.RunRecordMetric.timeAmber),
                    pace: Text(row.paceText).foregroundColor(AppColors.RunRecordMetric.paceTeal),
                    cadence: showsCadence ? Text(row.cadenceText ?? "").foregroundColor(AppColors.RunRecordMetric.cadenceOrange) : nil
                )
                .font(.title3.weight(.bold))
            }
        }
        .monospacedDigit()
        .frame(maxWidth: .infinity, minHeight: FlowMetrics.actionButtonMinHeight, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected == row.index ? AppColors.secondaryBackground : Color.clear)
                .padding(.horizontal, -8)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.accessibilityLabel)
    }

    /// 四列：序号定宽，时间与配速平分，步频按内容。列头与每行用同一份，竖线对齐。
    private func columns(index: Text, elapsed: Text, pace: Text, cadence: Text?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            index.frame(width: 36, alignment: .leading)
            elapsed.frame(maxWidth: .infinity, alignment: .leading)
            pace.frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
            if let cadence {
                cadence.frame(minWidth: 44, alignment: .leading) // guard:allow small-touch-target（列宽，不是触达目标）
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}
