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
    /// 未解锁那一格用虚线圈，形状差异不依赖色觉。
    private func badgeCellBody(
        symbol: String,
        caption: VolunteerProfileBadgeRow.Caption,
        isLocked: Bool,
        spoken: String
    ) -> some View {
        VStack(spacing: 6) {
            ZStack {
                if isLocked {
                    Circle()
                        .strokeBorder(
                            AppColors.textSecondary.opacity(0.55),
                            style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                        )
                } else {
                    Circle().fill(AppColors.secondaryBackground)
                }
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundColor(isLocked ? AppColors.textSecondary : AppColors.primary)
            }
            .frame(width: 48, height: 48)

            Text(caption.title)
                .font(AppFonts.caption())
                .foregroundColor(isLocked ? AppColors.textSecondary : AppColors.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let detail = caption.detail {
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
