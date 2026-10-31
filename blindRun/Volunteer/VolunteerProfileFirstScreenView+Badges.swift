import SwiftUI

// 志愿者「我的」首屏的徽章行。主体与排序在 `VolunteerProfileFirstScreenView.swift`。

extension VolunteerProfileFirstScreen {
    // MARK: - 徽章

    /// 一排 + 「全部 N 枚 ›」。徽章铺满首屏会变成一片图标噪音，前几枚的意义随之被稀释
    /// （Strava Overview 的 Trophies 行 + `View more`，调研 §1.2 S8）。
    @ViewBuilder
    var badgesSection: some View {
        // 🔴 同 `impactSection`：读不到成就数据时**整块不画**，不要拿 `?? []` 顶上。
        // 空数组会渲染成「完成第一次陪跑就会解锁第一枚徽章。」—— 对一个已经解锁 7 枚的人
        // 那是一句假话，而失败信号已经由上面的影响力区给过了，这里再画一遍只会互相矛盾。
        if let achievements = incentive.summary?.achievements {
            let unlocked = achievements.unlockedBadges
            let cells = VolunteerProfileBadgeRow.cells(
                unlocked: unlocked,
                next: achievements.nextBadge
            )

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    sectionLabel(VolunteerProfileCopy.badgesSectionTitle)
                    Spacer(minLength: 8)
                    // 🚩 这个链接必须在任何 `.combine` 的**外面**才点得到
                    // （同作业区那张培训卡为什么不套 `.combine` 的那条判据）。
                    NavigationLink {
                        VolunteerServiceRecognitionView()
                    } label: {
                        linkLabel(VolunteerProfileBadgeRow.allLinkTitle(unlockedCount: unlocked.count))
                    }
                    .accessibilityLabel(VolunteerHomeIncentiveCopy.achievementsLinkTitle)
                    .accessibilityHint(VolunteerProfileCopy.badgesLinkHint)
                    .accessibilityIdentifier("volunteerHomeIncentiveAchievementsLink")
                }

                if cells.isEmpty {
                    Text(VolunteerProfileCopy.badgesEmpty)
                        .font(AppFonts.caption())
                        .foregroundColor(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    HStack(alignment: .top, spacing: 11) {
                        ForEach(cells) { cell in
                            badgeCell(cell)
                        }
                        // 不足四格时补空位，让每格宽度稳定 —— 否则两枚徽章会被拉成半屏宽。
                        if cells.count < VolunteerProfileBadgeRow.cellCount {
                            ForEach(cells.count..<VolunteerProfileBadgeRow.cellCount, id: \.self) { _ in
                                Color.clear
                                    .frame(maxWidth: .infinity)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func badgeCell(_ cell: VolunteerProfileBadgeRow.Cell) -> some View {
        switch cell {
        case .unlocked(let badge):
            badgeCellBody(
                symbol: badge.symbolName,
                caption: VolunteerProfileBadgeRow.caption(name: badge.displayName),
                isLocked: false,
                spoken: VolunteerAchievementsCopy.badgeAccessibilityLabel(badge)
            )

        case .next(let next):
            badgeCellBody(
                // 🔴 不写死一个图标。图标是这一栏**区分档位的非颜色手段**（WCAG 1.4.1），
                // 写死等于把它废掉 —— 无论下一枚是「陪跑 10 次」还是「高分好评」都画成同一个。
                // 查的是同一张 `code → SF Symbol` 表，未知 code 落 `rosette`。
                symbol: VolunteerBadgeSymbol.name(for: next.code),
                caption: VolunteerProfileBadgeRow.nextBadgeCaption(next),
                isLocked: true,
                spoken: VolunteerAchievementsCopy.nextBadgeAccessibilityLabel(next)
            )
        }
    }

    /// 图标 + 名称共同区分徽章，**颜色不是唯一指示**（WCAG 1.4.1）；
    /// 未解锁那一格用虚线圈，形状差异不依赖色觉。实现在共享的 `VolunteerBadgeMedallion`（成就页也用）。
    private func badgeCellBody(
        symbol: String,
        caption: VolunteerProfileBadgeRow.Caption,
        isLocked: Bool,
        spoken: String
    ) -> some View {
        VolunteerBadgeMedallion(symbol: symbol, title: caption.title, detail: caption.detail, isLocked: isLocked, spoken: spoken)
    }
}

/// 一枚圆形徽章：圆 + 图标 + 名称（+ 可选的一行进度）。首页「我的徽章」与服务成就页共用。
///
/// 图标 + 名称共同区分徽章，**颜色不是唯一指示**（WCAG 1.4.1）；未解锁用虚线圈，
/// 形状差异不依赖色觉。`prominent` 是成就页的大号实心版（激励页属「明快」档，
/// `docs/ui/design-direction.md` §6）：主色实心圆 + 白色图标，同一对颜色已在 `PrimaryButton` 上验过对比度。
struct VolunteerBadgeMedallion: View {
    let symbol: String
    let title: String
    let detail: String?
    let isLocked: Bool
    let spoken: String
    var diameter: CGFloat = 48
    var prominent = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                if isLocked {
                    Circle()
                        .strokeBorder(
                            AppColors.textSecondary.opacity(0.55),
                            style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                        )
                } else {
                    Circle().fill(prominent ? AppColors.primary : AppColors.secondaryBackground)
                }
                Image(systemName: symbol)
                    .font(prominent ? .title : .title3)
                    .foregroundColor(isLocked ? AppColors.textSecondary : (prominent ? .white : AppColors.primary))
            }
            .frame(width: diameter, height: diameter)

            Text(title)
                .font(prominent ? AppFonts.body().weight(.semibold) : AppFonts.caption())
                .foregroundColor(isLocked ? AppColors.textSecondary : AppColors.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(detail)
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(spoken)
    }
}

/// 服务成就页的勋章一排：与首页「我的徽章」同一个组件，用大号实心版 ——
/// 勋章的视觉分级是 `docs/ui/design-direction.md` §1 允许从跑步 App 抄的三样之一。无障碍字号档由调用方退回逐行。
struct VolunteerBadgeMedallionRow: View {
    let badges: [VolunteerBadgeDto]

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(badges) { badge in
                VolunteerBadgeMedallion(
                    symbol: badge.symbolName,
                    title: badge.displayName,
                    detail: nil,
                    isLocked: false,
                    spoken: VolunteerAchievementsCopy.badgeAccessibilityLabel(badge),
                    diameter: 64,
                    prominent: true
                )
            }
            // 不足四枚时补空位，让每枚宽度稳定，不被拉成半屏宽（同首页）。
            ForEach(badges.count..<VolunteerBadgeWall.previewLimit, id: \.self) { _ in
                Color.clear
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 8)
    }
}

