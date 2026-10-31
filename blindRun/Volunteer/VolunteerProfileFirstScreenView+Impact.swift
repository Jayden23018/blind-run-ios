import SwiftUI

// 志愿者「我的」首屏的影响力区（主指标 + 3 列统计 + 火花 + 国标星级）。主体与排序在 `VolunteerProfileFirstScreenView.swift`。

extension VolunteerProfileFirstScreen {
    // MARK: - 影响力区

    /// 主指标 + 3 列统计 + 火花 + 国标星级。
    ///
    /// 四态**必有其一**（内容 / 加载中 / 失败+重试 / 空），一个都没有就是
    /// 「`.task` 没触发」那个缺陷复发了。identifier 沿用改版前那四个，
    /// 回归用例 `testVolunteerHomeShowsTheIncentiveCard` 断的就是它们。
    @ViewBuilder
    var impactSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel(VolunteerProfileCopy.impactSectionTitle)

            // 🔴 **判据是 `summary.achievements` 非空，不是 `summary` 非空。**
            //
            // `summary` 只要三条请求里**成功了任意一条**就会被赋值（收藏 / 成就 / 火花各自独立容错），
            // 所以「成就那条失败、收藏那条成功」时 `summary != nil` 而 `achievements == nil`。
            // 按 `summary` 判的话：第一个分支恒中 ⇒ 下面的失败 + 重试**永远走不到**，
            // 而 `totalCompleted` 为 nil 会被 `resolve` 当成 0 ⇒ 屏幕上出现
            // 「还没有完成的陪跑」+ 星级和 3 列统计一起消失 ——
            // **跑过 200 次的老志愿者和真新人逐字不可区分，且没有任何出错信号。**
            //
            // 这一屏把 `achievements` 变成了主指标的**唯一**来源（改版前那张卡的 `hero`
            // 还能退到 `favoritedByCount`），所以这个风险面是本次改版新造出来的。
            if let achievements = incentive.summary?.achievements, let summary = incentive.summary {
                impactContent(summary, achievements: achievements)
            } else if incentive.loadFailed {
                impactPlaceholder(
                    VolunteerHomeIncentiveCopy.loadFailure,
                    identifier: "volunteerHomeIncentiveFailure"
                )
                Button(VolunteerHomeIncentiveCopy.retry) {
                    Task { await incentive.load() }
                }
                .buttonStyle(TextButtonStyle())
                .accessibilityIdentifier("volunteerHomeIncentiveRetryButton")
            } else {
                impactPlaceholder(
                    VolunteerHomeIncentiveCopy.loading,
                    identifier: "volunteerHomeIncentiveLoading"
                )
            }
        }
    }

    /// `achievements` 作为**非可选**参数传进来，不是在这里现拆 —— 拆包失败时
    /// `resolve(totalCompleted: nil)` 会安静地落进 `.newcomer`，那正是上面那段注释说的缺陷。
    /// 让类型系统保证「走到这里就是真的读到了成就数据」。
    @ViewBuilder
    private func impactContent(
        _ summary: VolunteerHomeIncentiveSummary,
        achievements: VolunteerAchievementsResponse
    ) -> some View {
        let headline = VolunteerProfileHeadline.resolve(
            totalCompleted: achievements.totalCompleted,
            totalServiceMinutes: achievements.totalServiceMinutes
        )

        VStack(alignment: .leading, spacing: 14) {
            hero(headline)

            if headline.showsImpactSections {
                statsRow(summary, achievements: achievements)
            }

            if let streak = summary.streak {
                StreakStrip(
                    // 只念不显示，所以去掉掩码星号（见 `StreakStrip.partnerName`）。
                    partnerName: summary.streakPartnerName?.unmaskedForSpeech.nilIfBlank
                        ?? PartnerStreakCopy.unknownBlindName,
                    streak: streak
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("volunteerHomeIncentiveCard")

        if headline.showsImpactSections {
            starCard(achievements.resolvedStarLevel)
        }
    }

    /// 主指标。🔴 走 `AppFonts.largeTitle()` 而不是设计稿上那个 60pt 固定磅值 ——
    /// 一屏上最大的那个数字恰恰是低视力用户最需要放大的东西，固定磅值不跟 Dynamic Type 走。
    /// 本仓库为这条栽过一次（成就页头部原本写死 48pt）。
    @ViewBuilder
    private func hero(_ headline: VolunteerProfileHeadline) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            switch headline {
            case .newcomer:
                Text(VolunteerProfileCopy.newcomerHeadline)
                    .font(AppFonts.title())
                    .foregroundColor(AppColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(VolunteerProfileCopy.newcomerDetail)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

            case .completed(let count, let minutes):
                // 数字与量词同一行、量词小一号：主次靠**字号差**拉开，不靠卡片边框
                // （调研 §2.1，Nike Run Club 的 `20.6` + `5'14"` 是同一形态）。
                // 有时长时主数字是陪伴时长（「2 小时 5 分钟」两组），次数退到下一行；时长为 0 时主数字仍是次数。
                // 拼成**一个** `Text`：四段放进 HStack 在最大字号下会被挤压截断，拼接的 Text 会自己换行。
                heroNumber(
                    minutes.map(VolunteerProfileCopy.heroDurationParts)
                        ?? [(value: "\(count)", unit: VolunteerProfileCopy.heroUnit)]
                )
                .foregroundColor(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                if minutes != nil {
                    Text(VolunteerProfileCopy.heroRunsDetail(count))
                        .font(AppFonts.body())
                        .foregroundColor(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // 主数字和它的说明是同一件事的两种说法，分开念会让读屏用户听两遍同一个数。
        .accessibilityElement(children: .combine)
        .accessibilityLabel(VolunteerProfileCopy.heroSpoken(headline))
    }

    /// 「2 小时 5 分钟」：数字大号、量词小一号，组与组之间、数字与量词之间各一个空格。
    private func heroNumber(_ parts: [(value: String, unit: String)]) -> Text {
        parts.enumerated().reduce(Text("")) { text, item in
            text
                + Text(item.offset == 0 ? item.element.value : " \(item.element.value)").font(AppFonts.largeTitle())
                + Text(" \(item.element.unit)").font(AppFonts.body().weight(.semibold))
        }
    }

    /// 3 列统计。**数值在上、小标签在下** —— 中文跑步产品（悦跑圈）是这个方向，
    /// 与 Strava 的标签在上正好相反，中文语境按中文的来（调研 §1.5 C1）。
    private func statsRow(
        _ summary: VolunteerHomeIncentiveSummary,
        achievements: VolunteerAchievementsResponse
    ) -> some View {
        let stats = VolunteerProfileStats.row(
            achievements: achievements,
            favoritedByCount: summary.favoritedByCount
        )
        return HStack(alignment: .top, spacing: 8) {
            ForEach(stats) { stat in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(stat.value)
                            .font(AppFonts.title())
                            .foregroundColor(AppColors.textPrimary)
                        if let unit = stat.unit {
                            Text(unit)
                                .font(AppFonts.caption().weight(.semibold))
                                .foregroundColor(AppColors.textPrimary)
                        }
                    }
                    Text(stat.caption)
                        .font(AppFonts.caption())
                        .foregroundColor(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(stat.spoken)
            }
        }
        .padding(.top, 13)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppColors.textSecondary.opacity(0.18))
                .frame(height: 1)
                .accessibilityHidden(true)
        }
    }

    /// 国标星级。门槛由 GB/T 40143—2021 定、不由我们定、也不随用户表现漂移 ——
    /// 这正是它能替代「本月 N/M 次」那种 Moving Target 的原因（调研 §4.2）。
    /// 到了一星以后文案复用成就页那一套；还没到一星时标题、进度、读屏走首屏自己的
    /// `VolunteerProfileCopy.starCard*`（2026-10-03 试用反馈，成就页不变）。
    ///
    /// 🚩 **整张卡可点，去服务成就页。** 改版前「我的贡献」卡下有一条「查看服务成就 ›」，
    /// 改版后只剩徽章标题旁那枚小链接，而人会去点的是这张星级卡本身
    /// （真机反馈「以前可以点进去看，现在点不了」）。写法同 `trainingEntry`：
    /// `NavigationLink` 上不套 `.combine`，标签 / identifier 挂在链接本身。
    private func starCard(_ level: VolunteerStarLevelDto) -> some View {
        NavigationLink {
            VolunteerServiceRecognitionView()
        } label: {
            starCardBody(level)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(VolunteerProfileCopy.starCardAccessibilityLabel(level))
        .accessibilityHint(VolunteerProfileCopy.badgesLinkHint)
        .accessibilityIdentifier("volunteerProfileStarCard")
    }

    private func starCardBody(_ level: VolunteerStarLevelDto) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label(
                    VolunteerProfileCopy.starCardTitle(level),
                    systemImage: "star.fill"
                )
                .font(AppFonts.body().weight(.semibold))
                .foregroundColor(AppColors.textPrimary)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(AppColors.textSecondary.opacity(0.6))
                    .accessibilityHidden(true)
            }

            // 进度条对 VoiceOver 是空的，所以下面那行文字不是装饰 —— 它是这一栏
            // 唯一能被读出来的进度信息。两者顺序不能倒，也不能只留进度条。
            ProgressView(value: starProgress(level))
                .tint(AppColors.warning)
                .accessibilityHidden(true)

            Text(VolunteerProfileCopy.starCardProgress(level))
                .font(AppFonts.caption())
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppColors.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: VolunteerHomeRadius.card, style: .continuous))
        .contentShape(Rectangle())
    }

    private func starProgress(_ level: VolunteerStarLevelDto) -> Double {
        guard let nextTarget = level.nextTarget, nextTarget > 0 else { return 1 }
        return min(1, Double(max(0, level.currentHours ?? 0)) / Double(nextTarget))
    }

    private func impactPlaceholder(_ text: String, identifier: String) -> some View {
        Text(text)
            .font(AppFonts.body())
            .foregroundColor(AppColors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(AppColors.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: VolunteerHomeRadius.card, style: .continuous))
            .accessibilityLabel("\(VolunteerProfileCopy.impactSectionTitle)。\(text)")
            .accessibilityIdentifier(identifier)
    }
}
