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
        let perRow = dynamicTypeSize.isAccessibilitySize ? 1 : min(4, max(1, items.count))
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: perRow),
            spacing: 14
        ) {
            ForEach(items) { item in
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
    }
}

private struct VolunteerBadgeCell: View {
    let item: VolunteerBadgeItem
    let medalSize: CGFloat

    var body: some View {
        VStack(spacing: 6) {
            VolunteerBadgeMedal(item: item, size: medalSize)
            Text(item.name)
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
        NavigationStack {
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
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(VolunteerSecondaryPagesCopy.badgeDetailClose, action: close)
                        .accessibilityIdentifier("volunteerBadgeDetailClose")
                }
            }
        }
        .presentationDetents([.medium, .large])
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
