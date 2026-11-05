import SwiftUI

// 跑步数据页（#710）的上半页：结论卡、陪跑日历、里程、陪伴时长。
// 页面骨架在 `VolunteerRunDataView.swift`，下半页在 `VolunteerRunDataView+Sections.swift`。

extension VolunteerRunDataView {
    // MARK: 结论卡

    var streakCard: some View {
        let credited = streak.isCreditedThisWeek(now: model.now, calendar: calendar)
        return VolunteerSecondaryCard {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 8) {
                    VolunteerSecondaryCardHeader(
                        title: VolunteerRunDataCopy.streakTitle(partner: streak.partnerName),
                        symbol: .system("flame.fill"),
                        tint: AppColors.VolunteerHome.streakOrange
                    )
                    (Text("\(streak.display.currentWeeks)").font(AppFonts.largeTitle())
                        + Text(" \(VolunteerRunDataCopy.streakWeeksUnit)").font(AppFonts.body().weight(.semibold))
                            .foregroundColor(AppColors.textSecondary))
                        .foregroundColor(AppColors.textPrimary)
                    Text(VolunteerRunDataCopy.streakProgress(streak.display))
                        .font(.subheadline)
                        .foregroundColor(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let credited {
                        Divider().padding(.vertical, 4)
                        Text(VolunteerRunDataCopy.thisWeekLine(partner: streak.partnerName, credited: credited))
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(AppColors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(VolunteerRunDataCopy.streakSpoken(streak, credited: credited))
                .accessibilityIdentifier("volunteerRunData.streak")
                if credited == nil { Divider().padding(.vertical, 4) }
                VolunteerRunDataWeekDots(dots: summary.thisWeek)
            }
        }
    }

    // MARK: 陪跑日历

    var calendarCard: some View {
        VolunteerSecondaryCard {
            VStack(alignment: .leading, spacing: 12) {
                VolunteerSecondaryCardHeader(
                    title: VolunteerRunDataCopy.calendarTitle,
                    symbol: .system("calendar"),
                    tint: AppColors.VolunteerHome.streakOrange,
                    meta: VolunteerRunDataCopy.calendarMeta
                )
                stats([
                    (VolunteerRunDataCopy.daysRunLabel, "\(summary.daysRunInWindow)", VolunteerRunDataCopy.dayUnit, nil),
                    (VolunteerRunDataCopy.longestLabel, "\(summary.longestWeeksInWindow)", VolunteerRunDataCopy.weekUnit,
                     VolunteerRunDataCopy.longestCaption)
                ])
                // AX3 及以上一格只有几个点大，换成按月一行的列表（OpenSpec「陪跑日历一格一天」）。
                if dynamicTypeSize >= .accessibility3 {
                    VStack(spacing: 0) {
                        ForEach(Array(summary.calendarMonths.enumerated()), id: \.offset) { index, entry in
                            HStack(alignment: .firstTextBaseline) {
                                Text(VolunteerRunDataCopy.monthTitle(entry.month, current: model.currentMonth))
                                Spacer(minLength: 8)
                                Text(VolunteerRunDataCopy.monthRowValue(entry.days.count))
                                    .fontWeight(.semibold)
                            }
                            .font(AppFonts.body())
                            .padding(.vertical, 8)
                            if index < summary.calendarMonths.count - 1 { Divider() }
                        }
                    }
                } else {
                    VolunteerRunDataCalendarGrid(weeks: summary.calendarWeeks, calendar: calendar)
                    VolunteerRunDataCalendarLegend()
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(VolunteerRunDataCopy.calendarTitle)
        .accessibilityValue(VolunteerRunDataCopy.calendarSpoken(summary, current: model.currentMonth))
        .accessibilityIdentifier("volunteerRunData.calendar")
    }

    // MARK: 里程

    var mileageCard: some View {
        let series = summary.mileage[range]
        return VolunteerSecondaryCard {
            VStack(alignment: .leading, spacing: 10) {
                if let series {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(VolunteerRunDataCopy.headlineLabel(range))
                            .font(.subheadline)
                            .foregroundColor(AppColors.textSecondary)
                        bigNumber(VolunteerRunDataCopy.km(series.headlineKm), unit: VolunteerRunDataCopy.kmUnit)
                        Text(VolunteerRunDataCopy.rangeText(series, calendar: calendar))
                            .font(.subheadline)
                            .foregroundColor(AppColors.textSecondary)
                        VolunteerRunDataBarChart(
                            values: series.bars.map(\.value),
                            tint: AppColors.VolunteerHome.distanceIndigo,
                            average: series.isAverage ? series.headlineKm : nil,
                            axisLabels: axisLabels(series),
                            highlightsLast: range != .month
                        )
                        .padding(.top, 6)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(VolunteerRunDataCopy.mileageSpoken(series, calendar: calendar))
                    .accessibilityIdentifier("volunteerRunData.mileageChart")
                }
                Divider()
                totalRow(
                    VolunteerRunDataCopy.cumulativeMileage,
                    "\(VolunteerSecondaryPagesCopy.kilometres(achievements.totalDistanceMeters)) \(VolunteerRunDataCopy.kmUnit)"
                )
            }
        }
    }

    // MARK: 陪伴时长

    var durationCard: some View {
        VolunteerSecondaryCard {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 8) {
                    VolunteerSecondaryCardHeader(
                        title: VolunteerRunDataCopy.durationTitle,
                        symbol: .system("clock"),
                        tint: AppColors.VolunteerHome.durationTeal,
                        meta: VolunteerRunDataCopy.durationMeta
                    )
                    if let average = summary.averageServiceMinutes {
                        Text(VolunteerRunDataCopy.monthlyAverageLabel)
                            .font(.subheadline)
                            .foregroundColor(AppColors.textSecondary)
                        durationNumber(average)
                    }
                    VolunteerRunDataBarChart(
                        values: summary.serviceMonths.map { Double($0.minutes ?? 0) },
                        tint: AppColors.VolunteerHome.durationTeal,
                        average: summary.averageServiceMinutes.map(Double.init),
                        axisLabels: Dictionary(uniqueKeysWithValues: summary.serviceMonths.enumerated().map {
                            ($0.offset, "\($0.element.month.month)月")
                        }),
                        height: 96
                    )
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(VolunteerRunDataCopy.durationSpoken(summary, current: model.currentMonth))
                .accessibilityIdentifier("volunteerRunData.durationChart")
                Divider()
                totalRow(
                    VolunteerRunDataCopy.cumulativeDuration,
                    VolunteerRunDataCopy.duration(achievements.totalServiceMinutes ?? 0)
                )
            }
        }
    }
}
