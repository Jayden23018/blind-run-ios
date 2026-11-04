import SwiftUI

// 志愿者首页的「置顶 · 编辑」分区：按志愿者保存的顺序画卡（#694，负责人 2026-11-04 看截图后要求）。
// 取值与存储在 `VolunteerHomePinnedCards.swift`，各张卡的零件在 `+Impact` / `+Recent` / `+Badges`。

extension VolunteerProfileFirstScreen {
    // MARK: - 置顶

    /// 默认顺序（陪伴时长 → 连续陪跑 + 评分 → 最近陪跑 → 徽章）下，这一块和定稿样例逐张一致。
    /// 最近陪跑、徽章自带分区标题（「全部记录」「全部 N 枚」入口在标题右边），挪到哪里都带着。
    @ViewBuilder
    var pinnedSection: some View {
        sectionHeader(VolunteerProfileCopy.pinnedSectionTitle) {
            NavigationLink {
                VolunteerHomePinnedEditView(store: pinnedStore)
            } label: {
                linkLabel(VolunteerProfileCopy.pinnedEditTitle)
            }
            .accessibilityLabel(VolunteerProfileCopy.pinnedEditNavigationTitle)
            .accessibilityHint(VolunteerProfileCopy.pinnedEditHint)
            .accessibilityIdentifier("volunteerHomePinnedEditLink")
        }

        let segments = visiblePinnedSegments
        if pinnedStore.pinned.isEmpty {
            VolunteerHomeCard {
                Text(VolunteerProfileCopy.pinnedHomeEmpty)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityIdentifier("volunteerHomePinnedEmpty")
        }

        // 成就还没到时，占位只在**第一张**依赖成就的卡的位置画一次，不每张都画一遍。
        let firstDependent = segments.firstIndex { $0.kinds.contains(where: \.needsAchievements) }
        ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
            pinnedSegment(segment, isFirst: index == 0, isFirstDependent: index == firstDependent)
        }
    }

    /// 要画的段。新人态（成就已到、0 次）连续陪跑 / 评分不画，先滤掉：
    /// 否则排在第一位时会留下一段空白间距，「第一张依赖成就的卡」的标识也会挂到一个空视图上。
    private var visiblePinnedSegments: [VolunteerHomePinnedLayout.Segment] {
        let segments = VolunteerHomePinnedLayout.segments(pinnedStore.pinned)
        guard let loaded = loadedAchievements, !Self.headline(loaded.achievements).showsImpactSections else {
            return segments
        }
        return segments.filter { !$0.kinds.contains(.streak) && !$0.kinds.contains(.rating) }
    }

    @ViewBuilder
    private func pinnedSegment(
        _ segment: VolunteerHomePinnedLayout.Segment,
        isFirst: Bool,
        isFirstDependent: Bool
    ) -> some View {
        switch segment {
        case .single(.recentRun):
            recentSection
        case .single(.badges):
            if loadedAchievements != nil {
                badgesSection
            } else if isFirstDependent {
                achievementsPlaceholder.padding(.top, isFirst ? 0 : 12)
            }
        default:
            if let loaded = loadedAchievements {
                achievementCards(segment, summary: loaded.summary, achievements: loaded.achievements, isFirstDependent: isFirstDependent)
                    .padding(.top, isFirst ? 0 : 12)
            } else if isFirstDependent {
                achievementsPlaceholder.padding(.top, isFirst ? 0 : 12)
            }
        }
    }

    /// 陪伴时长卡，或连续陪跑 / 评分（成对时并排，单张时占一整行）。
    ///
    /// 第一张依赖成就的卡外面包一层带 `volunteerHomeIncentiveCard` 的容器：回归用例
    /// `testVolunteerHomeShowsTheIncentiveCard` 拿它判「成就数据真的画出来了」。
    /// 包在 `VStack` 上再 `.contain`，不直接挂在 `NavigationLink` 上 —— 挂上去会把链接变成容器、丢掉按钮 trait。
    @ViewBuilder
    private func achievementCards(
        _ segment: VolunteerHomePinnedLayout.Segment,
        summary: VolunteerHomeIncentiveSummary,
        achievements: VolunteerAchievementsResponse,
        isFirstDependent: Bool
    ) -> some View {
        let showsHalfCards = Self.headline(achievements).showsImpactSections
        let content = VStack(alignment: .leading, spacing: 0) {
            switch segment {
            case .single(.duration):
                durationCard(achievements: achievements)
            case .pair(let first, let second) where showsHalfCards:
                halfCards(
                    left: halfCardModel(first, summary: summary, achievements: achievements),
                    right: halfCardModel(second, summary: summary, achievements: achievements)
                )
            case .single(let kind) where showsHalfCards:
                // 新人态两张半宽卡都不画：此刻全是 `--`，「一屏只强调一个主指标」的反面是「把一排空值摆出来」。
                halfCard(halfCardModel(kind, summary: summary, achievements: achievements))
            default:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        if isFirstDependent {
            content
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("volunteerHomeIncentiveCard")
        } else {
            content
        }
    }
}
