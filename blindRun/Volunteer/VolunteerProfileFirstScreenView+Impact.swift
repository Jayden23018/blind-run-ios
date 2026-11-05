import SwiftUI

// 志愿者首页的陪伴时长卡与连续陪跑 / 评分两张半宽卡。排序由「置顶」决定，见 `VolunteerProfileFirstScreenView+Pinned.swift`。

extension VolunteerProfileFirstScreen {
    // MARK: - 成就数据

    /// 陪伴时长、连续陪跑、评分、徽章都要等成就接口。
    ///
    /// 🔴 **判据是 `summary.achievements` 非空，不是 `summary` 非空。**
    ///
    /// `summary` 只要三条请求里**成功了任意一条**就会被赋值（收藏 / 成就 / 火花各自独立容错），
    /// 所以「成就那条失败、收藏那条成功」时 `summary != nil` 而 `achievements == nil`。
    /// 按 `summary` 判的话：失败 + 重试**永远走不到**，而 `totalCompleted` 为 nil 会被 `resolve`
    /// 当成 0 ⇒ 屏幕上出现「还没有完成的陪跑」——
    /// **跑过 200 次的老志愿者和真新人逐字不可区分，且没有任何出错信号。**
    var loadedAchievements: (summary: VolunteerHomeIncentiveSummary, achievements: VolunteerAchievementsResponse)? {
        guard let summary = incentive.summary, let achievements = summary.achievements else { return nil }
        return (summary, achievements)
    }

    /// 成就还没到时的那一块：失败 + 重试，或加载中。置顶里依赖成就的卡只在第一个位置画一次。
    ///
    /// 四态**必有其一**（内容 / 加载中 / 失败+重试 / 空），一个都没有就是
    /// 「`.task` 没触发」那个缺陷复发了。identifier 沿用改版前那四个，
    /// 回归用例 `testVolunteerHomeShowsTheIncentiveCard` 断的就是它们。
    @ViewBuilder
    var achievementsPlaceholder: some View {
        if incentive.loadFailed {
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

    /// 陪伴时长卡。`achievements` 作为**非可选**参数传进来，不是在这里现拆 ——
    /// 拆包失败时 `resolve(totalCompleted: nil)` 会安静地落进 `.newcomer`，那正是上面那段注释说的缺陷。
    func durationCard(achievements: VolunteerAchievementsResponse) -> some View {
        durationCard(Self.headline(achievements), level: achievements.resolvedStarLevel)
    }

    static func headline(_ achievements: VolunteerAchievementsResponse) -> VolunteerProfileHeadline {
        VolunteerProfileHeadline.resolve(
            totalCompleted: achievements.totalCompleted,
            totalServiceMinutes: achievements.totalServiceMinutes
        )
    }

    /// 连续陪跑（没有火花时退到固定搭档）或评分那张半宽卡的取值。
    func halfCardModel(
        _ kind: VolunteerHomeCardKind,
        summary: VolunteerHomeIncentiveSummary,
        achievements: VolunteerAchievementsResponse
    ) -> VolunteerHomeHalfCard {
        if kind == .rating {
            return .rating(average: achievements.avgRating, total: achievements.totalRatings)
        }
        return .left(
            streak: summary.streak,
            streakPartnerName: summary.streakPartnerName,
            favoritedByCount: summary.favoritedByCount
        )
    }

    // MARK: 陪伴时长卡

    /// 主数字 + 「共陪跑 N 次」+ 右侧到下一星级的进度（改版前的星级卡并进来了）。
    ///
    /// 🚩 **整张卡可点，去服务成就页**（国标星级、全部勋章、累计时长都在那里）。
    /// `NavigationLink` 上不套 `.combine`，标签 / identifier 挂在链接本身（套了有丢 link 特性的风险）。
    ///
    /// 🔴 不画样例 v1 那组柱图：后端没有按周的历史，画出来就是编数据。
    func durationCard(_ headline: VolunteerProfileHeadline, level: VolunteerStarLevelDto) -> some View {
        NavigationLink {
            VolunteerServiceRecognitionView()
        } label: {
            VolunteerHomeCard {
                VStack(alignment: .leading, spacing: 14) {
                    VolunteerHomeCardHeader(
                        title: VolunteerProfileCopy.durationCardTitle,
                        symbol: "clock",
                        tint: AppColors.VolunteerHome.durationTeal,
                        showsChevron: true
                    )
                    durationBody(headline, level: level)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(durationSpoken(headline, level: level))
        .accessibilityHint(VolunteerProfileCopy.badgesLinkHint)
        .accessibilityIdentifier("volunteerProfileStarCard")
    }

    @ViewBuilder
    private func durationBody(_ headline: VolunteerProfileHeadline, level: VolunteerStarLevelDto) -> some View {
        switch headline {
        case .newcomer:
            VStack(alignment: .leading, spacing: 6) {
                Text(VolunteerProfileCopy.newcomerHeadline)
                    .font(AppFonts.title())
                    .foregroundColor(AppColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(VolunteerProfileCopy.newcomerDetail)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .completed(let count, let minutes):
            let progress = VolunteerHomeStarProgress(level)
            // 无障碍字号下左右排放不下，进度改到数字下面（不用竖向 `ViewThatFits`，理由见主体）。
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    durationNumbers(count: count, minutes: minutes)
                    starProgress(progress)
                }
            } else {
                HStack(alignment: .bottom, spacing: 12) {
                    durationNumbers(count: count, minutes: minutes)
                    Spacer(minLength: 0)
                    starProgress(progress)
                        .frame(width: 130)
                }
            }
        }
    }

    /// 主数字。🔴 走 `AppFonts.largeTitle()` 而不是固定磅值 —— 一屏上最大的那个数字恰恰是
    /// 低视力用户最需要放大的东西（本仓库为这条栽过一次：成就页头部原本写死 48pt）。
    ///
    /// 有时长时主数字是陪伴时长（「2 小时 5 分钟」两组），次数退到下一行；时长为 0 时主数字是次数。
    /// 拼成**一个** `Text`：四段放进 HStack 在最大字号下会被挤压截断，拼接的 Text 会自己换行。
    private func durationNumbers(count: Int, minutes: Int64?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            heroNumber(
                minutes.map(VolunteerProfileCopy.heroDurationParts)
                    ?? [(value: "\(count)", unit: VolunteerProfileCopy.heroUnit)]
            )
            .foregroundColor(AppColors.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            if minutes != nil {
                Text(VolunteerProfileCopy.durationCardRunsLine(count))
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 「2 小时 5 分钟」：数字大号、量词小一号且是次要色，组与组之间、数字与量词之间各一个空格。
    private func heroNumber(_ parts: [(value: String, unit: String)]) -> Text {
        parts.enumerated().reduce(Text("")) { text, item in
            text
                + Text(item.offset == 0 ? item.element.value : " \(item.element.value)").font(AppFonts.largeTitle())
                + Text(" \(item.element.unit)").font(AppFonts.body().weight(.semibold))
                    .foregroundColor(AppColors.textSecondary)
        }
    }

    /// 进度条对 VoiceOver 是空的，所以上面那行字不是装饰 —— 它是这一栏
    /// 唯一能被看清的进度数字。两者顺序不能倒，也不能只留进度条。
    private func starProgress(_ progress: VolunteerHomeStarProgress) -> some View {
        VStack(alignment: .trailing, spacing: 5) {
            Text(progress.label)
                .font(AppFonts.caption())
                .foregroundColor(AppColors.textSecondary)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
            // 样例进度条 8pt 高、圆头；系统 `ProgressView` 只有 4pt。
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppColors.VolunteerHome.durationTeal.opacity(0.18))
                    Capsule()
                        .fill(AppColors.VolunteerHome.durationTeal)
                        .frame(width: max(8, proxy.size.width * progress.fraction))
                }
            }
            .frame(height: 8)
            .accessibilityHidden(true)
        }
        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil, alignment: .trailing)
    }

    /// 整张卡一句话：主数字那句 + 星级那句（「国标星级，距离一星还差 99 小时，已累计 1 小时」）。
    private func durationSpoken(_ headline: VolunteerProfileHeadline, level: VolunteerStarLevelDto) -> String {
        guard headline.showsImpactSections else { return VolunteerProfileCopy.heroSpoken(headline) }
        return VolunteerProfileCopy.heroSpoken(headline) + VolunteerProfileCopy.starCardAccessibilityLabel(level)
    }

    // MARK: 半宽卡

    @ViewBuilder
    func halfCards(left: VolunteerHomeHalfCard, right: VolunteerHomeHalfCard) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 12) {
                halfCard(left)
                halfCard(right)
            }
        } else {
            HStack(alignment: .top, spacing: 12) {
                halfCard(left)
                halfCard(right)
            }
            // ScrollView 里给的是不定高度，不固定的话两张卡各取自己的理想高度、底边一高一低。
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    func halfCard(_ card: VolunteerHomeHalfCard) -> some View {
        if card.hasDestination {
            // 有连续周数的卡去「连续陪跑」跑步数据页（#710）；退成「固定搭档 N 位」的卡仍去固定搭档页。
            NavigationLink {
                halfCardDestination(card)
            } label: {
                halfCardBody(card)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(card.spoken)
            .accessibilityHint(card.kind == .streak ? VolunteerRunDataCopy.homeCardHint : VolunteerProfileCopy.partnersCardHint)
            .accessibilityIdentifier("volunteerHomeHalfCard.\(card.kind)")
        } else {
            halfCardBody(card)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(card.spoken)
                .accessibilityIdentifier("volunteerHomeHalfCard.\(card.kind)")
        }
    }

    /// 🔴 火花、姓名、周号都从**生成这张卡的同一份摘要**里取，原样交给数据页 ——
    /// 数据页不重拉火花，否则两次请求之间数据变了，结论卡会和刚点的卡说两个人。
    @ViewBuilder
    private func halfCardDestination(_ card: VolunteerHomeHalfCard) -> some View {
        if card.kind == .streak,
           let summary = incentive.summary,
           let streak = summary.streak,
           let achievements = summary.achievements {
            VolunteerRunDataView(
                streak: VolunteerRunDataStreak(
                    display: streak,
                    partnerName: summary.streakPartnerName,
                    lastCreditedWeek: summary.streakLastCreditedWeek
                ),
                achievements: achievements,
                favoritedByCount: summary.favoritedByCount
            )
        } else {
            VolunteerPartnersView()
        }
    }

    private func halfCardBody(_ card: VolunteerHomeHalfCard) -> some View {
        VolunteerHomeCard(padding: EdgeInsets(top: 12, leading: 14, bottom: 14, trailing: 14)) {
            VStack(alignment: .leading, spacing: 10) {
                VolunteerHomeCardHeader(
                    title: card.title,
                    symbol: card.symbol,
                    // 连续陪跑 / 固定搭档橙、评分琥珀：两张并排时颜色分开（负责人 2026-11-04 看截图要求）。
                    tint: card.kind == .rating ? AppColors.VolunteerHome.ratingAmber : AppColors.VolunteerHome.streakOrange,
                    showsChevron: card.hasDestination
                )
                VStack(alignment: .leading, spacing: 4) {
                    // 样例半宽卡数字 30pt，比主数字（34pt）小一档：取 `.title`（28pt）加粗，跟字号走。
                    (Text(card.value).font(.title.bold())
                        + Text(card.unit.map { " \($0)" } ?? "").font(AppFonts.body().weight(.semibold))
                            .foregroundColor(AppColors.textSecondary))
                        .foregroundColor(AppColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(card.caption)
                        .font(.subheadline)
                        .foregroundColor(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        // 两张并排时等高：内容短的那张也要撑满，否则底边一高一低。
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func impactPlaceholder(_ text: String, identifier: String) -> some View {
        VolunteerHomeCard {
            Text(text)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(VolunteerProfileCopy.impactSectionTitle)。\(text)")
        .accessibilityIdentifier(identifier)
    }
}
