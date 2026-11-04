import SwiftUI

// 服务成就页上半部分的三张卡：陪伴时长（大数字 + 近 6 个月柱状图）、提要、国标星级圆环。
// 照健康 · 步数详情（#697）。页面主体在 `VolunteerServiceRecognitionView.swift`。

// MARK: - 陪伴时长头卡

/// 大数字（累计陪伴时长）+ 近 6 个月柱状图。本月深色、其余浅色，虚线是前 5 个月平均。
///
/// `months == nil`（还在拉）或 6 个月都没读到时只有数字、不画图 —— 月度数据是附加信息，
/// 拉不到不影响这张卡最重要的那个数。
struct VolunteerServiceDurationCard: View {
    let achievements: VolunteerAchievementsResponse
    let months: [VolunteerServiceMonth]?

    private var minutes: Int64 { max(0, achievements.totalServiceMinutes ?? 0) }
    private var chartMonths: [VolunteerServiceMonth]? {
        guard let months, VolunteerServiceTrend.hasAnyData(months) else { return nil }
        return months
    }

    var body: some View {
        VolunteerSecondaryCard {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 10) {
                    VolunteerSecondaryCardHeader(
                        title: VolunteerSecondaryPagesCopy.durationTitle,
                        symbol: .system("clock.fill"),
                        tint: VolunteerSecondaryTint.duration,
                        meta: chartMonths == nil ? nil : VolunteerSecondaryPagesCopy.durationRange
                    )
                    VolunteerValueText(
                        parts: VolunteerServiceTrend.durationParts(minutes),
                        numberSize: 34,
                        unitSize: 17
                    )
                    Text(VolunteerSecondaryPagesCopy.durationCaption(completed: achievements.completedCount))
                        .font(.subheadline)
                        .foregroundColor(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // 卡名、数字、小字是同一件事，合成一句念（「陪伴时长，累计 12 小时 40 分钟，共陪跑 18 次」）。
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(VolunteerSecondaryPagesCopy.durationSpoken(
                    minutes: minutes,
                    completed: achievements.completedCount
                ))

                if let chartMonths {
                    VolunteerServiceBarChart(months: chartMonths)
                        .padding(.top, 8)
                }
            }
        }
        // 数字与那行小字合成一句；图表另成一个焦点（它有自己的 Audio Graph）。
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("volunteerServiceRecognitionHeader")
    }
}

/// 6 根柱子。对读屏是一个元素：一句总结 + Audio Graph（HIG Charting data）。
private struct VolunteerServiceBarChart: View {
    let months: [VolunteerServiceMonth]
    @ScaledMetric(relativeTo: .body) private var chartHeight: CGFloat = 140

    private var peak: Int64 { max(1, months.compactMap(\.minutes).max() ?? 1) }
    private var average: Int64? { VolunteerServiceTrend.previousAverage(months) }

    var body: some View {
        VolunteerGrowIn { progress in
            VStack(spacing: 6) {
                ZStack(alignment: .bottom) {
                    HStack(alignment: .bottom, spacing: 10) {
                        ForEach(Array(months.enumerated()), id: \.element.id) { index, month in
                            bar(month, isCurrent: index == months.count - 1, progress: progress)
                        }
                    }
                    if let average, average > 0 {
                        averageLine(average)
                    }
                }
                .frame(height: chartHeight)

                HStack(spacing: 10) {
                    ForEach(months) { month in
                        Text(month.label)
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(VolunteerServiceTrend.chartSummary(months))
        .accessibilityChartDescriptor(VolunteerServiceChartDescriptor(months: months))
        .accessibilityIdentifier("volunteerServiceChart")
    }

    private func bar(_ month: VolunteerServiceMonth, isCurrent: Bool, progress: Double) -> some View {
        let fraction = Double(month.minutes ?? 0) / Double(peak)
        return VStack {
            Spacer(minLength: 0)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(isCurrent ? VolunteerSecondaryTint.duration : VolunteerSecondaryTint.duration.opacity(0.25))
                // 没读到的月份不画柱子（高度 0），不当 0 也不编数。
                .frame(height: month.minutes == nil ? 0 : max(2, chartHeight * 0.82 * fraction * progress))
        }
        .frame(maxWidth: .infinity)
    }

    /// 虚线 + 线上那行小字「前 5 个月平均 1 小时 32 分钟」。
    private func averageLine(_ average: Int64) -> some View {
        let fraction = Double(average) / Double(peak)
        return GeometryReader { proxy in
            let y = proxy.size.height - proxy.size.height * 0.82 * fraction
            VStack(alignment: .leading, spacing: 2) {
                Text(VolunteerSecondaryPagesCopy.averageLineLabel(average))
                    .font(.caption)
                    .foregroundColor(AppColors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Path { path in
                    path.move(to: .zero)
                    path.addLine(to: CGPoint(x: proxy.size.width, y: 0))
                }
                .stroke(AppColors.textSecondary, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .frame(height: 1)
            }
            .offset(y: max(0, y - 18))
        }
    }
}

// MARK: - 提要卡

/// 健康「提要」的写法：卡名 → 一句结论 → 细灰分隔线 → 大数字小单位 → 标签写在横条里。
/// 本月是彩色条白字，前 5 个月平均是浅灰条深字（负责人 2026-11-04 两轮反馈后定稿）。
struct VolunteerServiceHighlightCard: View {
    let months: [VolunteerServiceMonth]

    var body: some View {
        if let sentence = VolunteerServiceTrend.summarySentence(months),
           let current = VolunteerServiceTrend.current(months),
           let average = VolunteerServiceTrend.previousAverage(months),
           let currentMonth = months.last {
            let top = Double(max(1, current, average))
            VolunteerSecondaryCard {
                VStack(alignment: .leading, spacing: 12) {
                    VolunteerSecondaryCardHeader(
                        title: VolunteerSecondaryPagesCopy.durationTitle,
                        symbol: .system("clock.fill"),
                        tint: VolunteerSecondaryTint.duration
                    )
                    Text(sentence)
                        .font(AppFonts.body().weight(.semibold))
                        .foregroundColor(AppColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Divider()
                    row(
                        minutes: current,
                        label: "\(currentMonth.month) 月",
                        fraction: Double(current) / top,
                        fill: VolunteerSecondaryTint.duration,
                        ink: VolunteerSecondaryTint.onDuration
                    )
                    row(
                        minutes: average,
                        label: VolunteerSecondaryPagesCopy.previousAverageLabel,
                        fraction: Double(average) / top,
                        fill: AppColors.Flow.progressTrack,
                        ink: AppColors.textPrimary
                    )
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(VolunteerSecondaryPagesCopy.highlightSpoken(
                sentence: sentence,
                month: currentMonth.month,
                current: current,
                average: average
            ))
            .accessibilityIdentifier("volunteerServiceHighlight")
        }
    }

    private func row(minutes: Int64, label: String, fraction: Double, fill: Color, ink: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            VolunteerValueText(parts: VolunteerServiceTrend.durationParts(minutes))
            VolunteerGrowIn { progress in
                VolunteerProportionalWidth(fraction: fraction * progress) {
                    Text(label)
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(ink)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(fill))
            }
        }
    }
}

/// 横条宽度 = 可用宽度 × `fraction`，但**至少放得下里面那行标签**（标签写在横条里，不许被截）。
///
/// iOS 16 的 `Layout`：测量标签的理想宽度后取两者较大的那个。`fraction` 可动画（进页长出）。
struct VolunteerProportionalWidth: Layout {
    var fraction: Double

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let label = subviews.first else { return .zero }
        let available = proposal.width ?? label.sizeThatFits(.unspecified).width
        let ideal = label.sizeThatFits(.unspecified)
        let width = min(available, max(ideal.width, available * min(1, max(0, fraction))))
        let height = label.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(
            at: bounds.origin,
            proposal: ProposedViewSize(width: bounds.width, height: bounds.height)
        )
    }
}

// MARK: - 国标星级圆环

/// 「12 / 100 小时」画成圆环，右边一句「距离一星还差 88 小时」和三档门槛。
///
/// 🔴 **仍与平台徽章分两块，不合并**（契约要求，理由见 `VolunteerStarLevel`）。
/// 整张卡一个焦点，标签沿用改版前那一句（`testVolunteerStarLevelExposesRemainingHoursAsText` 钉着）。
struct VolunteerStarRingCard: View {
    let level: VolunteerStarLevelDto
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var ringSize: CGFloat = 92

    private var hours: Int64 { max(0, level.currentHours ?? 0) }

    var body: some View {
        VolunteerSecondaryCard {
            VStack(alignment: .leading, spacing: 12) {
                VolunteerSecondaryCardHeader(
                    title: VolunteerAchievementsCopy.starSectionTitle,
                    symbol: .system("sparkle"),
                    tint: VolunteerSecondaryTint.blue,
                    meta: VolunteerSecondaryPagesCopy.starStandard
                )
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 12) {
                        ring
                        text
                    }
                } else {
                    HStack(spacing: 16) {
                        ring
                        text
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(VolunteerProfileCopy.starCardAccessibilityLabel(level))
        .accessibilityIdentifier("volunteerStarLevelSection")
    }

    private var ring: some View {
        VolunteerGrowIn { progress in
            ZStack {
                Circle()
                    .stroke(AppColors.Flow.progressTrack, lineWidth: ringSize * 0.13)
                Circle()
                    .trim(from: 0, to: VolunteerStarProgressCard.progress(level) * progress)
                    .stroke(VolunteerSecondaryTint.blue, style: StrokeStyle(lineWidth: ringSize * 0.13, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(hours)")
                        .font(.title2.weight(.semibold))
                        .foregroundColor(AppColors.textPrimary)
                    if let target = level.nextTarget, target > 0 {
                        Text("/\(target) 小时")
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary)
                    } else {
                        Text("小时")
                            .font(.caption)
                            .foregroundColor(AppColors.textSecondary)
                    }
                }
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .padding(ringSize * 0.16)
            }
            .frame(width: ringSize, height: ringSize)
        }
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(VolunteerProfileCopy.starCardTitle(level))
                .font(.title3.weight(.semibold))
                .foregroundColor(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(VolunteerSecondaryPagesCopy.starThresholds)
                .font(.subheadline)
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
