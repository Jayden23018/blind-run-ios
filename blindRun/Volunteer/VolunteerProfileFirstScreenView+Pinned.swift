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

        let segments = VolunteerHomePinnedLayout.visibleSegments(pinnedStore.pinned, showsHalfCards: showsHalfCards)
        if let notice = VolunteerHomePinnedLayout.notice(pinned: pinnedStore.pinned, visible: segments) {
            VolunteerSecondaryCard {
                Text(notice == .nothingPinned ? VolunteerProfileCopy.pinnedHomeEmpty : VolunteerProfileCopy.pinnedHomeWaitingForFirstRun)
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

    /// 成就没到时按「会画」算（那时画的是占位，不是空白）；到了且是新人态才不画半宽卡。
    private var showsHalfCards: Bool {
        guard let loaded = loadedAchievements else { return true }
        return Self.headline(loaded.achievements).showsImpactSections
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
                if isFirstDependent {
                    // 徽章排在最前时，「成就数据画出来了」的标识挂在它身上（理由见 `achievementCards`）。
                    VStack(alignment: .leading, spacing: 0) { badgesSection }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("volunteerHomeIncentiveCard")
                } else {
                    badgesSection
                }
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
