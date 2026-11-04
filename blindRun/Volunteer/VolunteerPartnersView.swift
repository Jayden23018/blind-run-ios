import SwiftUI

// MARK: - 志愿者端「固定搭档」

/// 数据源是两个端点合并：`GET /api/volunteer/favorites`（谁把我设为固定搭档）与
/// `GET /api/volunteer/partners/streaks`。
///
/// 「有几位跑者把你设为固定搭档」取的是**收藏那条**的数组长度，不含只有火花的那些 ——
/// 那句话说的是收藏关系，不是关系亲疏。
///
/// 2026-11-04 照健康 App「共享」重做（#697，稿子 `docs/ui/mockups/volunteer-secondary-pages-20261104/`）：
/// 列表一人一行、只放内容，整行进搭档详情页；「退出 / 举报 / 不再匹配此人」全部挪进详情页 ——
/// 改版前一屏 3 位搭档就有 9 个操作按钮，搭档本身反而看不见。
/// 盲人端「我的固定搭档」（`BlindFavoriteVolunteersView`）不跟着改。
struct VolunteerPartnersView: View {
    @EnvironmentObject private var appState: AppState

    @State private var rows: [PartnerRow] = []
    @State private var favoritedByCount = 0
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var hasLoadedOnce = false
    @State private var notice: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: VolunteerSecondaryMetrics.sectionSpacing) {
                if hasLoadedOnce {
                    loadedContent
                } else if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .accessibilityLabel("正在加载固定搭档")
                } else {
                    IncentiveFailureSection(
                        message: errorMessage ?? PartnerStreakCopy.loadFailure,
                        retryTitle: PartnerStreakCopy.retry,
                        identifier: "volunteerPartnersRetryButton"
                    ) {
                        Task { await load() }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .readableContentColumn()
        }
        .background(AppColors.Flow.page.ignoresSafeArea())
        .navigationTitle(PartnerStreakCopy.volunteerNavigationTitle)
        .navigationBarTitleDisplayMode(.large)
        // 二级页不挂标签栏（稿子没有；服务成就页同一条，末行曾被标签栏盖住半行）。
        .toolbar(.hidden, for: .tabBar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("volunteerPartnersView")
        .task {
            guard !hasLoadedOnce else { return }
            await load()
        }
    }

    @ViewBuilder
    private var loadedContent: some View {
        if let notice {
            Text(notice)
                .font(AppFonts.body())
                .foregroundColor(AppColors.success)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("volunteerPartnerOptOutNotice")
        }
        // 列表加载出来之后再失败（退出），错误要就地显示。
        if let errorMessage, notice == nil {
            Text(errorMessage)
                .font(AppFonts.body())
                .foregroundColor(AppColors.destructive)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("volunteerPartnerActionError")
        }

        if rows.isEmpty {
            VolunteerPartnersEmptyCard()
            VolunteerSecondaryFootnote(text: PartnerStreakCopy.volunteerEmpty(
                streakEnabled: appState.featureFlags?.partnerStreakEnabled
            ))
            .accessibilityIdentifier("volunteerPartnersEmpty")
        } else {
            VolunteerPartnersCountCard(count: favoritedByCount)

            VolunteerSecondarySectionTitle(title: PartnerStreakCopy.volunteerListSectionTitle)
            VolunteerSecondaryCard(padding: EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 12)) {
                VStack(spacing: 0) {
                    // 🔴 按 userId 作身份，不按下标：拉黑后这一行从重拉的列表里消失，按下标的话
                    // 已经推开的详情页会被下一位跑者接手（连同「已不再匹配」的状态）。
                    // userId 为 nil（已注销）时才退回下标。
                    ForEach(KeyedPartnerRow.make(rows)) { keyed in
                        let index = keyed.index
                        let row = keyed.row
                        NavigationLink {
                            VolunteerPartnerDetailView(
                                row: row,
                                optOut: { await optOut(row) },
                                onBlocked: { await blocked() }
                            )
                        } label: {
                            VolunteerPartnerRowView(row: row, index: index)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(PartnerStreakCopy.volunteerRowSpoken(row))
                        .accessibilityHint(PartnerStreakCopy.volunteerRowHint)
                        .accessibilityIdentifier("volunteerPartnerRow.\(index)")

                        if index < rows.count - 1 {
                            Divider().padding(.leading, 52)
                        }
                    }
                }
            }
            VolunteerSecondaryFootnote(text: PartnerStreakCopy.volunteerListFootnote)

            VolunteerSecondarySectionTitle(title: PartnerStreakCopy.volunteerAboutTitle)
            VolunteerSecondaryCard {
                VolunteerPartnerExplainerList(items: [
                    PartnerStreakCopy.explainerAskFirst,
                    PartnerStreakCopy.explainerStreak
                ])
            }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        // 空态说哪一句取决于开关，先取到位再拉列表（理由见盲人侧 `BlindFavoriteVolunteersView.load`）。
        await appState.loadFeatureFlagsIfNeeded()
        do {
            let favorites = try await appState.incentive.volunteerFavoritedBy()
            let streaks = try await appState.incentive.volunteerPartnerStreaks()
            favoritedByCount = favorites.count
            rows = PartnerRowMerge.volunteerRows(favorites: favorites, streaks: streaks)
            errorMessage = nil
            hasLoadedOnce = true
        } catch let error as APIError {
            errorMessage = error.localizedMessage
        } catch {
            errorMessage = PartnerStreakCopy.loadFailure
        }
    }

    /// `DELETE /api/volunteer/favorites/{blindUserId}` → **恒 204**。成功返回 nil（详情页据此关掉自己），
    /// 失败返回给人看的原因 —— 详情页盖在列表上面，错误只写在列表上等于没说。
    ///
    /// ⚠️ 契约点名：**不要根据响应判断「这个人是不是收藏了我」** —— 区分开就成了
    /// 「拿任意 userId 试一下看响应差异」的探测器。所以这里点完直接重新拉一次列表，
    /// 不看响应体、也不做本地乐观更新（本地改一份状态就有了第二个真相源）。
    private func optOut(_ row: PartnerRow) async -> String? {
        guard let userId = row.userId else { return PartnerStreakCopy.optOutFailed }
        // 这条只上屏，志愿者端不播报，所以用可见那一份（带星号）。
        let name = row.displayName(fallback: PartnerStreakCopy.unknownBlindName)
        do {
            try await appState.incentive.volunteerOptOutOfFavorite(blindUserId: userId)
            notice = PartnerStreakCopy.optOutSucceeded(name)
            await load()
            return nil
        } catch let error as APIError {
            notice = nil
            errorMessage = error.localizedMessage
            return error.localizedMessage
        } catch {
            notice = nil
            errorMessage = PartnerStreakCopy.optOutFailed
            return PartnerStreakCopy.optOutFailed
        }
    }

    /// 拉黑后这一行会从重拉的列表里消失，结果挂在列表顶部。
    private func blocked() async {
        notice = UserSafetyCopy.blockSucceeded
        await load()
        // 重拉失败时被拉黑的人还留在列表里，要让用户看到这一句，不能被成功提示盖住。
        if errorMessage != nil { notice = nil }
    }
}

// MARK: - 顶部人数卡

/// 「3 位 / 跑者把你设为固定搭档」。数字大、量词小（同健康 App 的数值写法）。
private struct VolunteerPartnersCountCard: View {
    let count: Int

    var body: some View {
        VolunteerSecondaryCard {
            HStack(spacing: 14) {
                Image(systemName: "person.2.fill")
                    .font(.title2)
                    .foregroundColor(VolunteerSecondaryTint.blue)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    VolunteerValueText(parts: [("\(count)", "位")])
                    Text(PartnerStreakCopy.volunteerHeroCaption)
                        .font(.subheadline)
                        .foregroundColor(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(PartnerStreakCopy.favoritedByCountText(count))
        .accessibilityIdentifier("volunteerFavoritedByCount")
    }
}

// MARK: - 空状态

/// 照健康 App「共享」的说明卡：告诉第一次来的人这是什么、怎么来的。
/// **没有按钮**：陪跑员不能自己加搭档，只有跑者能设。
private struct VolunteerPartnersEmptyCard: View {
    var body: some View {
        VolunteerSecondaryCard(padding: EdgeInsets(top: 20, leading: 16, bottom: 20, trailing: 16)) {
            VStack(spacing: 16) {
                Image(systemName: "person.2.fill")
                    .font(.largeTitle)
                    .foregroundColor(VolunteerSecondaryTint.blue)
                    .accessibilityHidden(true)
                Text(PartnerStreakCopy.volunteerNavigationTitle)
                    .font(AppFonts.title())
                    .foregroundColor(AppColors.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                VolunteerPartnerExplainerList(items: [
                    PartnerStreakCopy.explainerHowItStarts,
                    PartnerStreakCopy.explainerAskFirst,
                    PartnerStreakCopy.explainerStreak
                ])
            }
            .frame(maxWidth: .infinity)
        }
    }
}

/// 说明卡里一条一条的「图标 + 粗标题 + 一句话」。每条一个焦点。
struct VolunteerPartnerExplainerList: View {
    let items: [PartnerStreakCopy.Explainer]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(items, id: \.title) { item in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: item.symbol)
                        .font(.body.weight(.semibold))
                        .foregroundColor(item.symbol == "flame.fill" ? VolunteerSecondaryTint.streak : VolunteerSecondaryTint.blue)
                        .frame(width: 24)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(AppFonts.body().weight(.semibold))
                            .foregroundColor(AppColors.textPrimary)
                        Text(item.detail)
                            .font(.subheadline)
                            .foregroundColor(AppColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 数字 + 单位

/// 「12 小时 40 分钟」：数字大号半粗、单位小一号常规灰（负责人 2026-11-04 定：28 / 16）。
/// 拼成**一个** `Text`，最大字号下会自己换行而不是被挤压截断。
///
/// 🔴 字号走**系统文字样式**，不走 `@ScaledMetric` + `Font.system(size:)`：真机审计把后者判成
/// 「改不了字号」（2026-11-04 本页实测）。默认字号下 `.title` = 28、`.callout` = 16，正好是定稿的两个数；
/// 头卡那一档 `.largeTitle` = 34、`.body` = 17。
struct VolunteerValueText: View {
    enum Size {
        /// 28 / 16：提要卡、半宽卡、人数卡。
        case regular
        /// 34 / 17：头卡大数字。
        case hero
    }

    let parts: [(value: String, unit: String)]
    var size: Size = .regular

    private var numberFont: Font {
        switch size {
        case .regular: return .system(.title, design: .rounded).weight(.semibold)
        case .hero: return .system(.largeTitle, design: .rounded).weight(.semibold)
        }
    }

    private var unitFont: Font {
        switch size {
        case .regular: return .callout
        case .hero: return .body
        }
    }

    var body: some View {
        parts.enumerated().reduce(Text("")) { text, item in
            let unit = item.element.unit.isEmpty ? Text("") : Text(" \(item.element.unit)")
                .font(unitFont)
                .foregroundColor(AppColors.textSecondary)
            return text
                + Text(item.offset == 0 ? item.element.value : " \(item.element.value)")
                    .font(numberFont)
                    .foregroundColor(AppColors.textPrimary)
                + unit
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
