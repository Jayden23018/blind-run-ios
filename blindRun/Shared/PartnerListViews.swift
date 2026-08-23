import SwiftUI

// MARK: - 一行搭档

/// 固定搭档 / 火花的一行，两侧共用。
///
/// **整张卡片是一个 VoiceOver 焦点**，念一句完整的话 —— 姓名、连续周数、进度、
/// 一起跑过几次、有没有人退出，分开念会让读屏用户为同一个人划四五次。
/// 卡片里因此**不放任何按钮**：`children: .ignore` 会让按钮拿不到焦点，
/// 所以志愿者侧的「退出」是卡片下面的独立一行（见 `VolunteerPartnersView`）。
private struct PartnerRowCard: View {
    let row: PartnerRow
    let fallbackName: String
    /// 盲人侧是「对方已退出固定搭档」，志愿者侧是「你已退出」。
    let optedOutText: String

    private var displayName: String {
        row.name?.nilIfBlank ?? fallbackName
    }

    private var subtitleParts: [String] {
        var parts: [String] = []
        if let together = PartnerStreakCopy.togetherText(row.completedRunsTogether) {
            parts.append(together)
        }
        if let favoritedAt = PartnerStreakCopy.favoritedAtText(row.favoritedAt) {
            parts.append(favoritedAt)
        }
        return parts
    }

    /// 一句话念完。顺序按信息价值排：谁 → 连续多久 → 距离最好成绩 → 一起跑过几次 → 谁退出了。
    ///
    /// 🔴 `row.streak == nil` 时**整段不出现**，不念「连续 0 周」——
    /// 契约里「未点亮」是 `null` 而不是 0，两者含义不同。
    private var spokenLabel: String {
        var parts = [displayName]
        if let streak = row.streak {
            parts.append("已经连续 \(streak.currentWeeks) 周一起跑步")
            parts.append(streak.progressText)
        }
        parts.append(contentsOf: subtitleParts)
        if row.hasOptedOut {
            parts.append(optedOutText)
        }
        return parts.joined(separator: "，")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(displayName)
                .font(AppFonts.body().weight(.semibold))
                .foregroundColor(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let streak = row.streak {
                StreakStrip(partnerName: displayName, streak: streak)
            }

            if !subtitleParts.isEmpty {
                Text(subtitleParts.joined(separator: " · "))
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if row.hasOptedOut {
                OptedOutBadge(text: optedOutText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppColors.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        // `.ignore` 而不是 `.combine`：里面的 `StreakStrip` 自己已经是一个合成元素，
        // `.combine` 会把它的整句再拼一遍，念出来是重复的。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
    }
}

// MARK: - 盲人端「我的固定搭档」

/// 数据源是**两个端点合并**：`GET /api/blind/favorite-volunteers` 与
/// `GET /api/blind/partners/streaks`。为什么不能只读前者见 `PartnerRowMerge` 顶部。
///
/// 入口放设置页而不是首页 —— 首页按 `blind-ui-visual-benchmark-20260808.md` 做过减法
/// （主按钮吃掉内容区七成），再塞一个列表入口会把那次结论推翻。
struct BlindFavoriteVolunteersView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var speechService: SpeechService

    @State private var rows: [PartnerRow] = []
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var hasLoadedOnce = false
    @State private var actionNotice: String?
    @State private var busyUserId: Int64?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if hasLoadedOnce {
                    // 操作结果既要看得见也要听得见 —— 这一屏在盲人端，
                    // 只把状态画进列表等于对读屏用户什么都没说。
                    if let actionNotice {
                        Text(actionNotice)
                            .font(AppFonts.body())
                            .foregroundColor(AppColors.success)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("blindFavoriteActionNotice")
                    }

                    // 列表已经加载出来之后再失败（收藏 / 取消收藏），错误要就地显示 ——
                    // 下面那个失败态整块只在**首次加载**失败时才出现，
                    // 光把 errorMessage 赋上而不在这里渲染，用户什么都看不到。
                    if let errorMessage, actionNotice == nil {
                        Text(errorMessage)
                            .font(AppFonts.body())
                            .foregroundColor(AppColors.destructive)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("blindFavoriteActionError")
                    }

                    if rows.isEmpty {
                        Text(PartnerStreakCopy.blindEmpty)
                            .font(AppFonts.body())
                            .foregroundColor(AppColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("blindFavoriteVolunteersEmpty")
                    } else {
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            partnerSection(row)
                        }
                    }
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
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .readableContentColumn()
        }
        .background(AppColors.background)
        .navigationTitle(PartnerStreakCopy.blindNavigationTitle)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("blindFavoriteVolunteersView")
        .task {
            guard !hasLoadedOnce else { return }
            await load()
        }
    }

    /// 一行搭档 + 它的收藏动作。按钮在卡片**外面**：卡片是 `children: .ignore` 的单焦点，
    /// 放进去按钮就拿不到焦点了。
    @ViewBuilder
    private func partnerSection(_ row: PartnerRow) -> some View {
        PartnerRowCard(
            row: row,
            fallbackName: PartnerStreakCopy.unknownVolunteerName,
            optedOutText: PartnerStreakCopy.partnerOptedOutSuffix
        )

        if let userId = row.userId {
            let name = row.name?.nilIfBlank ?? PartnerStreakCopy.unknownVolunteerName
            if row.isFavorite {
                // 取消收藏是可逆的（再收藏一次即可），所以**不做二次确认** ——
                // AGENTS.md 的二次确认清单给的是不可逆或高代价的动作，
                // 给每个可逆动作都加一道弹窗，读屏用户要多听一遍、多点一次。
                Button(PartnerStreakCopy.removeFavoriteTitle(name)) {
                    Task { await setFavorite(false, userId: userId, name: name) }
                }
                .font(AppFonts.body().weight(.semibold))
                .foregroundColor(AppColors.destructive)
                .buttonShapeOutlineIfNeeded(color: AppColors.destructive)
                .disabled(busyUserId == userId)
                .padding(.bottom, 6)
                .accessibilityIdentifier("blindRemoveFavoriteButton")
            } else {
                // 只有火花、还没收藏的一对。
                //
                // 🚩 这里是全 App **唯一**能拿到 volunteerId 的地方：`OrderDetailResponse`
                // 契约里根本没有这个字段（只有 volunteerName / volunteerPhone），
                // 所以订单详情、历史订单都给不出收藏入口。已投 handoff 请后端补。
                //
                // 好在这条路的覆盖面正好对得上：收藏的门槛是「一起跑完过至少一单」，
                // 而能出现在火花列表里的一对**必然**满足这个门槛。
                Button(PartnerStreakCopy.addFavoriteTitle(name)) {
                    Task { await setFavorite(true, userId: userId, name: name) }
                }
                .font(AppFonts.body().weight(.semibold))
                .foregroundColor(AppColors.primary)
                .buttonShapeOutlineIfNeeded(color: AppColors.primary)
                .disabled(busyUserId == userId)
                .accessibilityHint(PartnerStreakCopy.favoriteExplanation)
                .padding(.bottom, 6)
                .accessibilityIdentifier("blindAddFavoriteButton")
            }
        }
    }

    /// `PUT` / `DELETE /api/blind/favorite-volunteers/{volunteerId}` —— 两个都**幂等、恒 204**，
    /// 所以不看响应体、也不做本地乐观更新（本地改一份状态就有了第二个真相源），
    /// 改完直接重新拉一次列表。
    private func setFavorite(_ isFavorite: Bool, userId: Int64, name: String) async {
        busyUserId = userId
        defer { busyUserId = nil }
        do {
            let _: EmptyResponse = try await appState.apiClient.request(
                method: isFavorite ? .put : .delete,
                path: "/api/blind/favorite-volunteers/\(userId)",
                query: nil,
                body: nil,
                requiresAuth: true
            )
            let notice = isFavorite
                ? PartnerStreakCopy.favoriteAdded(name)
                : PartnerStreakCopy.favoriteRemoved(name)
            actionNotice = notice
            errorMessage = nil
            // 盲人端：结果必须念出来。列表刷新是看得见的反馈，播报是听得见的那一半。
            speechService.announce(notice)
            await load()
        } catch let error as APIError {
            actionNotice = nil
            let message = error.localizedMessage
            errorMessage = message
            speechService.speakError(message)
        } catch {
            actionNotice = nil
            errorMessage = PartnerStreakCopy.favoriteFailed
            speechService.speakError(PartnerStreakCopy.favoriteFailed)
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            // 两个只读端点，谁先回来都行 —— 串行写法足够（这一页低频、且两条都很轻）。
            // ponytail: 不为两个请求引入 async let 的并发编排，等真慢了再说。
            let favorites: [FavoriteVolunteerResponse] = try await appState.apiClient.get(
                "/api/blind/favorite-volunteers"
            )
            let streaks: [PartnerStreakResponse] = try await appState.apiClient.get(
                "/api/blind/partners/streaks"
            )
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

// MARK: - 志愿者端「固定搭档」

/// 数据源同样是两个端点合并：`GET /api/volunteer/favorites`（谁把我设为固定搭档）与
/// `GET /api/volunteer/partners/streaks`。
///
/// 「有几位跑者把你设为固定搭档」取的是**收藏那条**的数组长度，不含只有火花的那些 ——
/// 那句话说的是收藏关系，不是关系亲疏。
struct VolunteerPartnersView: View {
    @EnvironmentObject private var appState: AppState

    @State private var rows: [PartnerRow] = []
    @State private var favoritedByCount = 0
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var hasLoadedOnce = false
    @State private var pendingOptOut: PartnerRow?
    @State private var optOutNotice: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if hasLoadedOnce {
                    IncentiveHeroCard(
                        value: "\(favoritedByCount)",
                        caption: "位跑者把你设为固定搭档",
                        spokenLabel: PartnerStreakCopy.favoritedByCountText(favoritedByCount)
                    )
                    .accessibilityIdentifier("volunteerFavoritedByCount")

                    if let optOutNotice {
                        Text(optOutNotice)
                            .font(AppFonts.body())
                            .foregroundColor(AppColors.success)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("volunteerPartnerOptOutNotice")
                    }

                    if rows.isEmpty {
                        Text(PartnerStreakCopy.volunteerEmpty)
                            .font(AppFonts.body())
                            .foregroundColor(AppColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("volunteerPartnersEmpty")
                    } else {
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            partnerSection(row)
                        }
                    }
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
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .readableContentColumn()
        }
        .background(AppColors.background)
        .navigationTitle(PartnerStreakCopy.volunteerNavigationTitle)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("volunteerPartnersView")
        .task {
            guard !hasLoadedOnce else { return }
            await load()
        }
        // 🔴 二次确认必须把后果写进正文，不能只给「确定 / 取消」——
        // 退出是单方面的，且本轮后端没有「撤销退出」端点。
        .alert(
            PartnerStreakCopy.optOutConfirmTitle,
            isPresented: Binding(
                get: { pendingOptOut != nil },
                set: { if !$0 { pendingOptOut = nil } }
            )
        ) {
            Button(PartnerStreakCopy.optOutConfirmAction, role: .destructive) {
                if let row = pendingOptOut {
                    Task { await optOut(row) }
                }
            }
            Button(PartnerStreakCopy.optOutCancel, role: .cancel) { pendingOptOut = nil }
        } message: {
            Text(PartnerStreakCopy.optOutConfirmMessage)
        }
    }

    @ViewBuilder
    private func partnerSection(_ row: PartnerRow) -> some View {
        PartnerRowCard(
            row: row,
            fallbackName: PartnerStreakCopy.unknownBlindName,
            optedOutText: PartnerStreakCopy.selfOptedOutSuffix
        )

        // 只对「还没退出、且确实是收藏关系」的那些给退出入口：
        // 只有火花没有收藏关系的一对，本来就不在优先轮里，没有可退的东西。
        if row.isFavorite, !row.hasOptedOut, row.userId != nil {
            Button(PartnerStreakCopy.optOutButtonTitle(
                row.name?.nilIfBlank ?? PartnerStreakCopy.unknownBlindName
            )) {
                pendingOptOut = row
            }
            .font(AppFonts.body().weight(.semibold))
            .foregroundColor(AppColors.destructive)
            .buttonShapeOutlineIfNeeded(color: AppColors.destructive)
            .padding(.bottom, 6)
            .accessibilityIdentifier("volunteerPartnerOptOutButton")
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let favorites: [VolunteerFavoritedByResponse] = try await appState.apiClient.get(
                "/api/volunteer/favorites"
            )
            let streaks: [PartnerStreakResponse] = try await appState.apiClient.get(
                "/api/volunteer/partners/streaks"
            )
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

    /// `DELETE /api/volunteer/favorites/{blindUserId}` → **恒 204**。
    ///
    /// ⚠️ 契约点名：**不要根据响应判断「这个人是不是收藏了我」** —— 区分开就成了
    /// 「拿任意 userId 试一下看响应差异」的探测器。所以这里点完直接重新拉一次列表，
    /// 不看响应体、也不做本地乐观更新（本地改一份状态就有了第二个真相源）。
    private func optOut(_ row: PartnerRow) async {
        pendingOptOut = nil
        guard let userId = row.userId else { return }
        let name = row.name?.nilIfBlank ?? PartnerStreakCopy.unknownBlindName
        do {
            let _: EmptyResponse = try await appState.apiClient.delete(
                "/api/volunteer/favorites/\(userId)"
            )
            optOutNotice = PartnerStreakCopy.optOutSucceeded(name)
            await load()
        } catch let error as APIError {
            optOutNotice = nil
            errorMessage = error.localizedMessage
        } catch {
            optOutNotice = nil
            errorMessage = PartnerStreakCopy.optOutFailed
        }
    }
}
