import SwiftUI

// MARK: - 盲人端「固定搭档」

/// 数据源是**两个端点合并**：`GET /api/blind/favorite-volunteers` 与
/// `GET /api/blind/partners/streaks`。为什么不能只读前者见 `PartnerRowMerge` 顶部。
///
/// 2026-11-05 照健康 App「共享」重做（#752，定稿 `docs/ui/mockups/blind-partners-20261105/`）：
/// 列表只放人，一人一行，整行进搭档详情页（`BlindPartnerDetailView`）；
/// 取消、设为固定搭档、举报、不再匹配全部挪进详情页 —— 改版前一屏 3 位搭档就有 9 枚按钮。
/// 分两组：「固定搭档」（收藏关系，含对方已退出的人）、「一起跑过的人」（只有连续记录）。
///
/// 入口放「我的」而不是首页 —— 首页按 `blind-ui-visual-benchmark-20260808.md` 做过减法
/// （主按钮吃掉内容区七成），再塞一个列表入口会把那次结论推翻。
struct BlindFavoriteVolunteersView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService

    @State private var rows: [PartnerRow] = []
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var hasLoadedOnce = false
    @State private var actionNotice: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
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
                        identifier: "blindFavoriteVolunteersRetryButton"
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
        .navigationTitle(PartnerStreakCopy.blindNavigationTitle)
        .navigationBarTitleDisplayMode(.large)
        // 二级页不挂标签栏：末行会被标签栏切掉（记忆 `tab-bar-clips-the-last-line-of-secondary-pages`）。
        .toolbar(.hidden, for: .tabBar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("blindFavoriteVolunteersView")
        .task {
            guard !hasLoadedOnce else { return }
            await load()
        }
    }

    @ViewBuilder
    private var loadedContent: some View {
        // 操作结果既要看得见也要听得见 —— 这一屏在盲人端，
        // 只把状态画进列表等于对读屏用户什么都没说（播报在 `setFavorite` / 拉黑组件里）。
        if let actionNotice {
            Text(actionNotice)
                .font(AppFonts.body())
                .foregroundColor(AppColors.success)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("blindFavoriteActionNotice")
        }

        // 列表已经加载出来之后再失败（重拉失败），错误要就地显示 ——
        // 下面那个失败态整块只在**首次加载**失败时才出现。
        if let errorMessage, actionNotice == nil {
            Text(errorMessage)
                .font(AppFonts.body())
                .foregroundColor(AppColors.destructive)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("blindFavoriteActionError")
        }

        if rows.isEmpty {
            emptyCard
        } else {
            let keyed = KeyedPartnerRow.make(rows)
            heroCard

            let favorites = keyed.filter { $0.row.isFavorite }
            if !favorites.isEmpty {
                section(title: PartnerStreakCopy.blindFavoritesSectionTitle, rows: favorites)
            }
            let ranTogether = keyed.filter { !$0.row.isFavorite }
            if !ranTogether.isEmpty {
                section(title: PartnerStreakCopy.blindRanTogetherSectionTitle, rows: ranTogether)
            }
        }
    }

    /// 顶部说明卡：图标 +「N 位固定搭档」+ 派单说明。N 只数没退出的。
    private var heroCard: some View {
        let count = rows.filter { $0.isFavorite && !$0.hasOptedOut }.count
        return GroupedCard {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "person.2.fill")
                    .font(.title2)
                    .foregroundColor(AppColors.primary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    // 只有「一起跑过的人」时不写「0 位固定搭档」：读屏先念到 0，容易以为整页是空的。
                    Text(count > 0 ? PartnerStreakCopy.blindHeroTitle(count) : PartnerStreakCopy.blindEmptyTitle)
                        .font(AppFonts.body().weight(.semibold))
                        .foregroundColor(AppColors.textPrimary)
                    Text(PartnerStreakCopy.blindHeroCaption)
                        .font(.subheadline)
                        .foregroundColor(AppColors.textSecondary)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(16)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("blindFavoriteHeroCard")
    }

    /// 空态：图标 + 标题 + 现有三种空态文案之一（按开关）。
    private var emptyCard: some View {
        GroupedCard {
            VStack(spacing: 12) {
                Image(systemName: "person.2.fill")
                    .font(.largeTitle)
                    .foregroundColor(AppColors.primary)
                    .accessibilityHidden(true)
                Text(PartnerStreakCopy.blindEmptyTitle)
                    .font(AppFonts.title())
                    .foregroundColor(AppColors.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(PartnerStreakCopy.blindEmpty(
                    streakEnabled: appState.featureFlags?.partnerStreakEnabled
                ))
                    .font(.subheadline)
                    .foregroundColor(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("blindFavoriteVolunteersEmpty")
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
        }
    }

    /// 组上灰色小标题 + 白卡一人一行。
    ///
    /// 🔴 按 userId 作身份，不按下标：拉黑后这一行从重拉的列表里消失，按下标的话
    /// 已经推开的详情页会被下一位接手（连同「已不再匹配」的状态）。userId 为 nil（已注销）才退回下标。
    private func section(title: String, rows keyed: [KeyedPartnerRow]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(AppColors.textSecondary)
                .padding(.horizontal, GroupedCardMetrics.rowHorizontalPadding)
                .padding(.top, 8)
                .accessibilityAddTraits(.isHeader)
            GroupedCard {
                ForEach(keyed) { item in
                    NavigationLink {
                        BlindPartnerDetailView(
                            row: item.row,
                            index: item.index,
                            setFavorite: { isFavorite in await setFavorite(isFavorite, row: item.row) },
                            onBlocked: { await blocked() }
                        )
                    } label: {
                        BlindPartnerRowLabel(row: item.row, index: item.index)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(PartnerStreakCopy.blindRowSpoken(item.row))
                    .accessibilityHint(PartnerStreakCopy.blindRowHint)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("blindPartnerRow.\(item.index)")

                    if item.id != keyed.last?.id {
                        GroupedCardDivider(leadingInset: 72)
                    }
                }
            }
        }
    }

    /// `PUT` / `DELETE /api/blind/favorite-volunteers/{volunteerId}` —— 两个都**幂等、恒 204**，
    /// 所以不看响应体、也不做本地乐观更新（本地改一份状态就有了第二个真相源），改完重新拉一次列表。
    ///
    /// 成功返回 nil（详情页据此关掉自己），失败返回给人看的原因（详情页写在按钮下面）。
    /// 🚩 **重拉放在返回之后**：这一行会换组或消失，先让详情页关掉，再改列表。
    ///
    /// 上屏那份带掩码星号；播报走不带星号那份，见 `String.unmaskedForSpeech`。
    private func setFavorite(_ isFavorite: Bool, row: PartnerRow) async -> String? {
        guard let userId = row.userId else { return PartnerStreakCopy.favoriteFailed }
        let name = row.displayName(fallback: PartnerStreakCopy.unknownVolunteerName)
        let spokenName = row.spokenName(fallback: PartnerStreakCopy.unknownVolunteerName)
        do {
            if isFavorite {
                try await appState.incentive.addBlindFavoriteVolunteer(volunteerId: userId)
            } else {
                try await appState.incentive.removeBlindFavoriteVolunteer(volunteerId: userId)
            }
            actionNotice = isFavorite
                ? PartnerStreakCopy.favoriteAdded(name)
                : PartnerStreakCopy.favoriteRemoved(name)
            errorMessage = nil
            speechService.announce(
                isFavorite
                    ? PartnerStreakCopy.favoriteAdded(spokenName)
                    : PartnerStreakCopy.favoriteRemoved(spokenName)
            )
            Task {
                await load()
                // 重拉失败时列表还是旧的，要让用户看到错误，不能被成功提示盖住（同 `blocked()`）。
                if errorMessage != nil { actionNotice = nil }
            }
            return nil
        } catch let error as APIError {
            let message = error.localizedMessage
            speechService.speakError(message)
            return message
        } catch {
            speechService.speakError(PartnerStreakCopy.favoriteFailed)
            return PartnerStreakCopy.favoriteFailed
        }
    }

    /// 拉黑后这一行会从重拉的列表里消失，结果挂在页面顶部。
    private func blocked() async {
        actionNotice = UserSafetyCopy.blockSucceeded
        await load()
        // 重拉失败时被拉黑的人还留在列表里，要让用户看到这一句，不能被成功提示盖住。
        if errorMessage != nil { actionNotice = nil }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        // 空态要说哪一句取决于开关，所以**在拉列表之前**先把它取到位 ——
        // 反过来的话，列表回来得快、开关回来得慢时，用户会先看到 nil 档那句、
        // 再被替换成另一句，而读屏已经把第一句念完了。
        // 它自己带一次性标记与静默失败，失败只是让空态少说一句话。
        await appState.loadFeatureFlagsIfNeeded()
        do {
            // 两个只读端点，谁先回来都行 —— 串行写法足够（这一页低频、且两条都很轻）。
            // ponytail: 不为两个请求引入 async let 的并发编排，等真慢了再说。
            let favorites = try await appState.incentive.blindFavoriteVolunteers()
            let streaks = try await appState.incentive.blindPartnerStreaks()
            rows = PartnerRowMerge.blindRows(favorites: favorites, streaks: streaks)
            errorMessage = nil
            hasLoadedOnce = true
        } catch let error as APIError {
            errorMessage = error.localizedMessage
        } catch {
            errorMessage = PartnerStreakCopy.loadFailure
        }
    }
}
