import SwiftUI

/// 徽章页（#697 照健身 · 奖章重做）。
///
/// 改版前是一张只列已解锁的系统列表、点不动，且只在解锁 5 枚以上时才进得来。现在：
/// 顶部「加油」= `nextBadge` 及进度；7 枚按类别分块，没获得的画同形状灰线框；每枚都能点开看条件。
/// **不写获得日期**：后端没有解锁时间（「宁可不给也不编」）。
struct VolunteerBadgeWallView: View {
    let achievements: VolunteerAchievementsResponse

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selected: VolunteerBadgeItem?

    private var items: [VolunteerBadgeItem] { VolunteerBadgeBoard.items(achievements) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VolunteerSecondaryMetrics.sectionSpacing) {
                Text(VolunteerBadgeBoard.countText(items))
                    .font(.subheadline)
                    .foregroundColor(AppColors.textSecondary)
                    .accessibilityIdentifier("volunteerBadgeWallCount")

                if let next = achievements.nextBadge {
                    encourageCard(next)
                }

                sections
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .readableContentColumn()
        }
        .background(AppColors.Flow.page.ignoresSafeArea())
        .navigationTitle(VolunteerSecondaryPagesCopy.badgeWallTitle)
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.hidden, for: .tabBar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("volunteerBadgeWallView")
        .sheet(item: $selected) { item in
            VolunteerBadgeDetailSheet(item: item)
        }
    }

    /// 「加油」卡：下一枚 + 进度。
    private func encourageCard(_ next: VolunteerNextBadgeDto) -> some View {
        let item = items.first { $0.id == next.code }
        let line = VolunteerBadgeBoard.encouragementText(next)
        return VolunteerSecondaryCard {
            HStack(spacing: 14) {
                if let item {
                    VolunteerBadgeMedal(item: item, size: 60)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(VolunteerSecondaryPagesCopy.encourageTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(VolunteerSecondaryTint.blue)
                    Text(VolunteerBadgeBoard.nextName(next))
                        .font(AppFonts.title())
                        .foregroundColor(AppColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let line {
                        Text(line)
                            .font(.subheadline)
                            .foregroundColor(AppColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let fraction = next.progressFraction {
                        VolunteerSecondaryProgressBar(fraction: fraction, tint: VolunteerSecondaryTint.blue)
                            .padding(.top, 4)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            [VolunteerSecondaryPagesCopy.encourageTitle, VolunteerBadgeBoard.nextName(next), line]
                .compactMap { $0 }
                .joined(separator: "，")
        )
        .accessibilityIdentifier("volunteerBadgeEncourage")
    }

    /// 陪跑次数一整行；陪伴时长与评价在常规字号下并排两张半宽卡（稿子），大字号下全部单列。
    @ViewBuilder
    private var sections: some View {
        let grouped = VolunteerBadgeBoard.sections(items)
        let runs = grouped.first { $0.category == .runs }
        let pair = grouped.filter { $0.category == .hours || $0.category == .rating }
        let others = grouped.filter { $0.category == .other }

        if let runs {
            categoryCard(runs)
        }
        if dynamicTypeSize.isAccessibilitySize || pair.count < 2 {
            ForEach(pair) { section in
                categoryCard(section)
            }
        } else {
            HStack(alignment: .top, spacing: VolunteerSecondaryMetrics.sectionSpacing) {
                ForEach(pair) { section in
                    categoryCard(section)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        ForEach(others) { section in
            categoryCard(section)
        }
    }

    private func categoryCard(_ section: VolunteerBadgeSection) -> some View {
        VolunteerSecondaryCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(section.category.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(Self.tint(section.category))
                    .accessibilityAddTraits(.isHeader)
                VolunteerBadgeGrid(items: section.items, onSelect: { selected = $0 })
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("volunteerBadgeSection.\(section.category.rawValue)")
    }

    static func tint(_ category: VolunteerBadgeCategory) -> Color {
        switch category {
        case .runs, .other: return VolunteerSecondaryTint.blue
        case .hours: return VolunteerSecondaryTint.duration
        case .rating: return VolunteerSecondaryTint.rating
        }
    }
}

// MARK: - 网格

/// 一类里的几枚。常规字号一行最多 4 枚，大字号一行 1 枚。每枚一个按钮、一个焦点。
private struct VolunteerBadgeGrid: View {
    let items: [VolunteerBadgeItem]
    let onSelect: (VolunteerBadgeItem) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var medalSize: CGFloat = 56

    var body: some View {
        // 默认字号一行 4 枚；调大一档起一行 2 枚（4 枚时第 4 列的名字放不下）；无障碍字号一行 1 枚。
        let maxPerRow = dynamicTypeSize.isAccessibilitySize ? 1 : (dynamicTypeSize >= .xLarge ? 2 : 4)
        let perRow = min(maxPerRow, max(1, items.count))
        let rows = stride(from: 0, to: items.count, by: perRow).map { Array(items[$0..<min($0 + perRow, items.count)]) }
        // 不用 `LazyVGrid`：审计 `.dynamicType` 放大字号重排后，被挤出屏幕的格子不渲染，
        // 那一格的字被判「改不了字号」（#697 真机：只点名第 4 枚「陪跑 100 次」「未获得」）。最多 7 枚，不需要懒加载。
        VStack(alignment: .leading, spacing: 14) {
            ForEach(rows.indices, id: \.self) { rowIndex in
                HStack(alignment: .top, spacing: 8) {
                    ForEach(rows[rowIndex]) { item in
                        cell(item)
                    }
                    // 末行不满时补空位，列宽与上面几行对齐
                    ForEach(rows[rowIndex].count..<perRow, id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
                    }
                }
            }
        }
    }

    private func cell(_ item: VolunteerBadgeItem) -> some View {
        Button {
            onSelect(item)
        } label: {
            VolunteerBadgeCell(item: item, medalSize: medalSize)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.spoken)
        .accessibilityHint(VolunteerSecondaryPagesCopy.badgeTapHint)
        .accessibilityIdentifier("volunteerBadge.\(item.id)")
    }
}

private struct VolunteerBadgeCell: View {
    let item: VolunteerBadgeItem
    let medalSize: CGFloat

    var body: some View {
        VStack(spacing: 6) {
            VolunteerBadgeMedal(item: item, size: medalSize)
            Text(item.gridName)
                .font(.footnote.weight(.semibold))
                .foregroundColor(AppColors.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(item.state.shortText)
                .font(.footnote)
                .foregroundColor(AppColors.textSecondary)
            if case .inProgress(let fraction, _, _) = item.state {
                VolunteerSecondaryProgressBar(fraction: fraction, tint: VolunteerSecondaryTint.blue, height: 4)
                    .frame(maxWidth: medalSize)
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

// MARK: - 点开一枚

/// 弹层：大奖章 + 名称 + 状态 + 怎么获得（**不写日期**）。
///
/// 动效：奖章放大并转半圈停下（健身奖章是立体转动，我们用平面翻转）；
/// 「减弱动态效果」打开时直接显示，不转不放大。
private struct VolunteerBadgeDetailSheet: View {
    let item: VolunteerBadgeItem

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false
    @ScaledMetric(relativeTo: .largeTitle) private var medalSize: CGFloat = 150

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                VolunteerBadgeMedal(item: item, size: medalSize)
                    .scaleEffect(hasAppeared ? 1 : 0.6)
                    .rotation3DEffect(.degrees(hasAppeared ? 0 : 180), axis: (x: 0, y: 1, z: 0))
                    .padding(.top, 12)
                Text(item.name)
                    .font(AppFonts.largeTitle())
                    .foregroundColor(AppColors.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(item.state.isEarned ? VolunteerSecondaryPagesCopy.badgeDetailEarnedText : VolunteerSecondaryPagesCopy.badgeDetailLockedText)
                    .font(AppFonts.body().weight(.semibold))
                    .foregroundColor(item.state.isEarned ? AppColors.success : AppColors.textSecondary)
                Text(item.detailLine)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if case .inProgress(let fraction, _, _) = item.state {
                    VolunteerSecondaryProgressBar(fraction: fraction, tint: VolunteerSecondaryTint.blue)
                        .frame(maxWidth: 260)
                        .padding(.top, 4)
                }
                // 关闭放页内：iOS 27 把工具栏文字按钮包成玻璃胶囊，审计报对比度与改不了字号
                // （记忆 sheet-toolbar-text-button-fails-audit）。
                FlowActionButton(VolunteerSecondaryPagesCopy.badgeDetailClose, style: .ghost, action: close)
                    .accessibilityIdentifier("volunteerBadgeDetailClose")
                    .padding(.top, 12)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
        .background(AppColors.Flow.surface.ignoresSafeArea())
        .presentationDetents([.large])
        .accessibilityIdentifier("volunteerBadgeDetailSheet")
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.75)) {
                hasAppeared = true
            }
        }
    }

    private func close() {
        dismiss()
    }
}
