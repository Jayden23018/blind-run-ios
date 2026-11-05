import SwiftUI

// 跑步数据页（#710）的下半页：提要、一起跑的人、个人纪录，以及几处共用的小部件。
// 上半页与页面骨架在 `VolunteerRunDataView.swift`。

extension VolunteerRunDataView {
    // MARK: 提要

    @ViewBuilder
    var highlights: some View {
        VolunteerSecondarySectionTitle(title: VolunteerRunDataCopy.highlightsSection)
        if let comparison = summary.mileageComparison {
            let top = max(comparison.lastKm, comparison.previousKm, 0.1)
            highlightCard(
                title: VolunteerRunDataCopy.comparisonTitle, symbol: .route, tint: AppColors.VolunteerHome.distanceIndigo,
                sentence: VolunteerRunDataCopy.comparison(comparison),
                spoken: VolunteerRunDataCopy.comparison(comparison, spoken: true),
                identifier: "volunteerRunData.comparison"
            ) {
                VStack(spacing: 8) {
                    VolunteerRunDataHorizontalBar(
                        label: "\(comparison.lastMonth.month) 月", value: VolunteerRunDataCopy.km(comparison.lastKm),
                        fraction: comparison.lastKm / top, tint: AppColors.VolunteerHome.distanceIndigo
                    )
                    VolunteerRunDataHorizontalBar(
                        label: "\(comparison.previousMonth.month) 月", value: VolunteerRunDataCopy.km(comparison.previousKm),
                        fraction: comparison.previousKm / top, tint: AppColors.VolunteerHome.distanceIndigo.opacity(0.35)
                    )
                }
            }
        }
        if !summary.favoriteWeekdays.isEmpty {
            highlightCard(
                title: VolunteerRunDataCopy.weekdayTitle, symbol: .system("calendar"), tint: AppColors.VolunteerHome.streakOrange,
                sentence: VolunteerRunDataCopy.favoriteWeekday(summary.favoriteWeekdays),
                spoken: VolunteerRunDataCopy.weekdaySpoken(summary.weekdayCounts, favorite: summary.favoriteWeekdays),
                identifier: "volunteerRunData.weekdays"
            ) {
                VolunteerRunDataBarChart(
                    values: summary.weekdayCounts.map(Double.init),
                    tint: AppColors.VolunteerHome.streakOrange,
                    axisLabels: Dictionary(uniqueKeysWithValues: VolunteerRunDataCopy.weekdayNames.enumerated().map { ($0.offset, $0.element) }),
                    height: 64,
                    highlightsLast: false
                )
            }
        }
        if let longest = summary.longestRun, let metres = longest.metres {
            longestCard(longest, metres: metres)
        }
    }

    func highlightCard<Graphic: View>(
        title: String,
        symbol: VolunteerSecondarySymbol,
        tint: Color,
        sentence: String,
        spoken: String,
        identifier: String,
        @ViewBuilder graphic: () -> Graphic
    ) -> some View {
        VolunteerSecondaryCard {
            VStack(alignment: .leading, spacing: 10) {
                VolunteerSecondaryCardHeader(title: title, symbol: symbol, tint: tint)
                Text(sentence)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                graphic()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title)。\(spoken)")
        .accessibilityIdentifier(identifier)
    }

    func longestCard(_ run: VolunteerRunDataRun, metres: Int) -> some View {
        VolunteerSecondaryCard {
            VStack(alignment: .leading, spacing: 10) {
                VolunteerSecondaryCardHeader(
                    title: VolunteerRunDataCopy.longestTitle, symbol: .route, tint: AppColors.VolunteerHome.distanceIndigo
                )
                HStack(alignment: .center, spacing: 12) {
                    // 超过 90 天留存期 / 后端没补算时没有缩略图：只写文字，不画占位图标。
                    if let points = run.thumbnail, RunRouteShape.hasExtent(points), !dynamicTypeSize.isAccessibilitySize {
                        RunRouteThumbnail(points: points)
                            .frame(width: 120, height: 78)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        bigNumber(VolunteerRunDataCopy.km(metres: metres), unit: VolunteerRunDataCopy.kmUnit)
                        Text(VolunteerRunDataCopy.longestDetail(run, calendar: calendar))
                            .font(.subheadline)
                            .foregroundColor(AppColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("和 \(VolunteerRunDataCopy.partner(run.partnerName, spoken: false))")
                            .font(.subheadline)
                            .foregroundColor(AppColors.textSecondary)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(VolunteerRunDataCopy.longestSpoken(run, calendar: calendar))
        .accessibilityIdentifier("volunteerRunData.longest")
    }

    // MARK: 一起跑的人

    var partnersCard: some View {
        let top = Double(summary.partners.first?.count ?? 1)
        return VolunteerSecondaryCard {
            VStack(alignment: .leading, spacing: 10) {
                VolunteerSecondaryCardHeader(
                    title: VolunteerRunDataCopy.partnersTitle, symbol: .system("person.2.fill"),
                    tint: AppColors.VolunteerHome.streakOrange
                )
                Text(VolunteerRunDataCopy.partnersHeadline(summary.partners))
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                VStack(spacing: 8) {
                    ForEach(Array(summary.partners.enumerated()), id: \.offset) { index, partner in
                        VolunteerRunDataHorizontalBar(
                            label: VolunteerRunDataCopy.partner(partner.name, spoken: false),
                            value: VolunteerRunDataCopy.timesValue(partner.count),
                            fraction: Double(partner.count) / top,
                            tint: AppColors.VolunteerHome.streakOrange.opacity(index == 0 ? 1 : 0.4)
                        )
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(VolunteerRunDataCopy.partnersSpoken(summary.partners))
        .accessibilityIdentifier("volunteerRunData.partners")
    }

    // MARK: 个人纪录

    @ViewBuilder
    var recordsSection: some View {
        VolunteerSecondarySectionTitle(title: VolunteerRunDataCopy.recordsSection)
        let records = summary.records
        let rows: [(String, String)] = [
            (VolunteerRunDataCopy.recordLongest, records.longestRunMetres.map { "\(VolunteerRunDataCopy.km(metres: $0)) 公里" } ?? "--"),
            (VolunteerRunDataCopy.recordMostRuns, VolunteerRunDataCopy.timesValue(records.mostRunsInWeek)),
            (VolunteerRunDataCopy.recordMostKm, "\(VolunteerRunDataCopy.km(metres: records.mostMetresInWeek)) 公里"),
            (VolunteerRunDataCopy.recordLongestWeeks, "\(records.longestWeeks) 周")
        ]
        VolunteerSecondaryCard(padding: EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16)) {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    totalRow(row.0, row.1)
                        .padding(.vertical, 12)
                        .accessibilityIdentifier("volunteerRunData.record.\(index)")
                    if index < rows.count - 1 { Divider() }
                }
            }
        }
        VolunteerSecondaryFootnote(text: VolunteerRunDataCopy.recordsFootnote)
    }

    // MARK: 小部件

    func stats(_ items: [(label: String, value: String, unit: String, caption: String?)]) -> some View {
        HStack(alignment: .top, spacing: 28) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.label)
                        .font(.subheadline)
                        .foregroundColor(AppColors.textSecondary)
                    bigNumber(item.value, unit: item.unit)
                    if let caption = item.caption {
                        Text(caption)
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary)
                    }
                }
            }
        }
    }

    /// 大号数字 + 小一号次要色单位，拼成一个 `Text`（大字号下自己换行，不被挤截断）。
    func bigNumber(_ value: String, unit: String) -> some View {
        (Text(value).font(.title.bold())
            + Text(" \(unit)").font(AppFonts.body().weight(.semibold)).foregroundColor(AppColors.textSecondary))
            .foregroundColor(AppColors.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }

    func durationNumber(_ minutes: Int64) -> some View {
        let hours = minutes / 60
        let rest = minutes % 60
        let parts: [(String, String)] = hours > 0 ? [("\(hours)", "小时"), ("\(rest)", "分钟")] : [("\(rest)", "分钟")]
        return parts.enumerated().reduce(Text("")) { text, item in
            text
                + Text(item.offset == 0 ? item.element.0 : " \(item.element.0)").font(.title.bold())
                + Text(" \(item.element.1)").font(AppFonts.body().weight(.semibold)).foregroundColor(AppColors.textSecondary)
        }
        .foregroundColor(AppColors.textPrimary)
        .fixedSize(horizontal: false, vertical: true)
    }

    func totalRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundColor(AppColors.textSecondary)
            Spacer(minLength: 8)
            Text(value)
                .fontWeight(.semibold)
                .foregroundColor(AppColors.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .font(AppFonts.body())
        .accessibilityElement(children: .combine)
    }

    /// 横轴刻度：周档每天、月档 1 / 15 / 月末、半年档隔月写月份、年档首中尾三个月。
    func axisLabels(_ series: VolunteerRunDataSummary.MileageSeries) -> [Int: String] {
        switch series.range {
        case .week:
            return Dictionary(uniqueKeysWithValues: VolunteerRunDataCopy.weekdayNames.enumerated().map { ($0.offset, $0.element) })
        case .month:
            let last = series.bars.count - 1
            return [0: "1日", 14: "15日", last: "\(last + 1)日"]
        case .halfYear:
            var labels: [Int: String] = [:]
            var previous = -1
            var changes = 0
            for (index, bar) in series.bars.enumerated() {
                let month = calendar.component(.month, from: bar.start)
                guard month != previous else { continue }
                previous = month
                if changes % 2 == 0 { labels[index] = "\(month)月" }
                changes += 1
            }
            return labels
        case .year:
            let label: (Int) -> String = { "\(calendar.component(.month, from: series.bars[$0].start))月" }
            guard series.bars.count == VolunteerRunDataSummary.yearMonths else { return [:] }
            return [0: label(0), 5: label(5), 11: label(11)]
        }
    }
}
