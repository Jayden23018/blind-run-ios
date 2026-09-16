import Combine
import SwiftUI

// 展示口径与文案在 `VolunteerHomeIncentive.swift`（同一目录）。
//
// ⚠️ 本文件用 Combine **只为了 `@Published` / `ObservableObject`**，
// 没有也不许有 `AnyCancellable` 或任何 publisher 订阅 ——
// 数据流一律 async/await（AGENTS.md 硬约束「并发模型只用一种」）。

// MARK: - ViewModel

/// 首页激励卡自己的一次加载。
///
/// **刻意不并进 `VolunteerHomeViewModel`**（那份已经一千行，且它带着一条 5 秒轮询）。
/// 照 `VolunteerAchievementsViewModel` 抄，那份是范例。
///
/// 🚩 **每次会话只加载一次，绝不进那条 5 秒轮询。**
/// `GET /api/volunteer/achievements` 的 `totalServiceMinutes` 要扫该志愿者的全部已完成订单，
/// 后端**刻意**把它和 `dispatch-summary` 分成两个端点，就是为了不让低频页面的代价
/// 压在最热的端点上（契约那条 description，转述在 `VolunteerServiceRecognitionView` 顶部）。
/// 一次性标记的写法抄 `AppState.loadFeatureFlagsIfNeeded()`：**失败不置位**，
/// 下次进首页时重试。
///
/// 并发只用 async/await，没有 `AnyCancellable`（AGENTS.md 硬约束）。
@MainActor
final class VolunteerHomeIncentiveViewModel: ObservableObject {
    @Published private(set) var summary: VolunteerHomeIncentiveSummary?

    /// 这一轮有没有请求失败。
    ///
    /// 🔴 **必须发布出去，不能只记诊断。** 此前失败是完全静默的 ——
    /// 「加载失败」「数据确实为空」「视图压根没加载」三种情况在屏幕上长得一模一样，
    /// 2026-09-14 真机排查这张卡不出现时，正是这一点让三种假设分不开。
    @Published private(set) var loadFailed = false

    /// ⚠️ `appState` 是 `weak`：传临时对象等于传 nil，用例要自己持有它
    /// （守卫规则 `weak-temporary`）。
    private weak var appState: AppState?

    private var hasLoaded = false

    func configure(appState: AppState) {
        self.appState = appState
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await load()
    }

    /// 三个只读端点各自独立容错：**一条失败只少显示一行，不让整张卡消失**。
    ///
    /// 这与本仓库的解码习惯同向（缺一个字段该少显示一行，而不是整页空白）。
    /// 三条全空时 `summary.isRenderable` 为 false，卡片整块不渲染。
    ///
    /// 🚩 **失败不在首页画错误块。** 这张卡是纯正反馈、没有任何可操作内容，
    /// 它读不到的代价是少一张卡，而在首页给一张装饰性卡片画红色错误提示是净噪音。
    /// 判据与 `AppState.loadFeatureFlagsIfNeeded()` 那条一样（「失败的后果是空态少说一句话」），
    /// 所以同样只记一条诊断、保持可重试。
    ///
    /// 🚩 **「这一轮算加载过了」的判据是「该跑的全成了」，不是「成了任意一条」。**
    ///
    /// 写成后者会造出一条**这张卡整个会话消失且永不重试**的路径，而且那条路径很常见：
    /// 新人的收藏列表成功返回空数组（`count == 0`），紧接着成就那条失败 ——
    /// 「成功过一条」成立 ⇒ 置位 ⇒ `loadIfNeeded` 的 guard 此后一直拦住重试，
    /// 而此刻 `summary` 三样都空、`isRenderable` 为 false。用户看到的是「这功能没有」。
    ///
    /// 🚩 **取消不是结果，一律不置位、也不覆盖已有的 `summary`。**
    /// 这张卡住在派单面板的 `ScrollView` 里，而那块在 `.compact` 档位**整个不渲染**
    /// （`VolunteerHomeView.nearbyDemandPanel` 的 `if !isCompact`）——
    /// 志愿者刚进首页就把面板拖下去是很平常的操作，`.task` 随之取消。
    /// 不拦的话，那一拖就会把半截数据钉成「本会话的最终结果」。
    ///
    /// ponytail: 串行三个请求，不引入 `async let` 的并发编排 —— 一次会话只跑一遍。
    func load() async {
        guard let appState else { return }

        var favoritedByCount = 0
        var nextBadge: VolunteerNextBadgeDto?
        var streak: PartnerStreakDisplay?
        var streakPartnerName: String?
        var allSucceeded = true

        do {
            favoritedByCount = try await appState.incentive.volunteerFavoritedBy().count
        } catch {
            allSucceeded = false
            ClientFlowDiagnostics.record(event: "failed", operation: "home-incentive-favorites")
        }
        if Task.isCancelled { return }

        do {
            nextBadge = try await appState.incentive.volunteerAchievements().nextBadge
        } catch {
            allSucceeded = false
            ClientFlowDiagnostics.record(event: "failed", operation: "home-incentive-achievements")
        }
        if Task.isCancelled { return }

        // 🚩 开关关着时**不发这个请求**。后端此时返空数组，打它只是白费一次往返；
        // 而 `nil`（拿不到开关）要照常发 —— 落到 false 就是替后端断言「功能没开」，
        // 那是 `FeatureFlagsResponse` 顶部点名不许做的事。
        await appState.loadFeatureFlagsIfNeeded()
        if appState.featureFlags?.partnerStreakEnabled != false {
            do {
                // 后端已按 `currentWeeks` 倒序，取第一条就是最强的那对，**不要自己重排**。
                if let strongest = try await appState.incentive.volunteerPartnerStreaks().first {
                    streak = PartnerStreakDisplay(
                        currentWeeks: strongest.currentWeeks,
                        bestWeeks: strongest.bestWeeks
                    )
                    streakPartnerName = strongest.partnerName
                }
            } catch {
                allSucceeded = false
                ClientFlowDiagnostics.record(event: "failed", operation: "home-incentive-streaks")
            }
        }
        if Task.isCancelled { return }

        // 失败的那几条留空，成功的照常显示 —— 一条失败只少显示一行。
        summary = VolunteerHomeIncentiveSummary(
            favoritedByCount: favoritedByCount,
            nextBadge: nextBadge,
            streak: streak,
            streakPartnerName: streakPartnerName
        )
        loadFailed = !allSucceeded
        // 有任何一条没成时保持未置位，下次进首页重试（理由见函数头两条 🚩）。
        hasLoaded = allSucceeded
    }
}

// MARK: - View

/// 首页派单面板里的「我的贡献」卡。
///
/// **它属于「普通信息卡片」那一档** —— 非高优、不紧急、用户关注时可见
/// （滴滴车主端 5.0 的三档信息分级，见 `docs/research/volunteer-home-incentive-layer-20260914.md` §1）。
/// 同屏另外两档是 `VolunteerDispatchOverlay`（模态，不可跳过）与
/// `VolunteerScheduledOrdersSection`（非模态，带临期确认动作）。
/// 🚩 **这张卡不许升档**：不做全屏、不做倒计时、不抢焦点、不挡住任何操作。
struct VolunteerHomeIncentiveCard: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = VolunteerHomeIncentiveViewModel()

    var body: some View {
        // 🔴 **这个视图必须永远渲染出真实内容，哪怕只是一行占位。**
        //
        // 原来写的是 `Group { if let summary = ..., summary.isRenderable { content } }`
        // —— 条件不成立时整个 Group 解析成空，而 **`.task` 挂在一棵空子树上不会触发**。
        // 于是 `summary` 永远是 nil ⇒ 永远渲染空 ⇒ 永远不加载，自己把自己锁死。
        // 2026-09-14 真机实测：加一个 `else` 分支之后卡片立刻出现，`volunteerHomeIncentiveCard`
        // 从 false 变 true。回归钉子 `testVolunteerHomeShowsTheIncentiveCard`（已验红）。
        //
        // 顺带修掉的是同一个根因的另一半：失败此前完全静默，
        // 「加载失败 / 数据为空 / 视图没加载」三种情况在屏幕上一模一样。
        VStack(alignment: .leading, spacing: 8) {
            stateContent
        }
        .task {
            viewModel.configure(appState: appState)
            await viewModel.loadIfNeeded()
        }
    }

    @ViewBuilder
    private var stateContent: some View {
        if let summary = viewModel.summary, summary.isRenderable {
            content(summary)
        } else if viewModel.summary == nil {
            placeholder(VolunteerHomeIncentiveCopy.loading, identifier: "volunteerHomeIncentiveLoading")
        } else if viewModel.loadFailed {
            // 失败要给去处，不能只少一张卡 —— 见本文件顶部那条根因注释。
            VStack(alignment: .leading, spacing: 10) {
                placeholder(VolunteerHomeIncentiveCopy.loadFailure, identifier: "volunteerHomeIncentiveFailure")
                Button(VolunteerHomeIncentiveCopy.retry) {
                    Task { await viewModel.load() }
                }
                .font(AppFonts.body().weight(.semibold))
                .foregroundColor(AppColors.primary)
                .buttonShapeOutlineIfNeeded(color: AppColors.primary)
                .frame(minHeight: 44)  // guard:allow small-touch-target
                .accessibilityIdentifier("volunteerHomeIncentiveRetryButton")
            }
        } else {
            // 真的没东西可显示（七枚勋章全解锁 + 没人收藏 + 没有火花）。
            placeholder(VolunteerHomeIncentiveCopy.empty, identifier: "volunteerHomeIncentiveEmpty")
        }
    }

    /// 加载中 / 失败 / 空 三态共用的外观：与正式卡片同一个容器，避免内容到位时整块跳一下。
    private func placeholder(_ text: String, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(VolunteerHomeIncentiveCopy.sectionTitle)
                .font(AppFonts.caption())
                .foregroundColor(AppColors.textSecondary)
            Text(text)
                .font(AppFonts.body())
                .foregroundColor(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppColors.secondaryBackground)
        .clipShape(
            RoundedRectangle(cornerRadius: VolunteerHomeRadius.card, style: .continuous)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(VolunteerHomeIncentiveCopy.sectionTitle)。\(text)")
        .accessibilityIdentifier(identifier)
    }

    /// 外层 `VStack` 的存在理由与 `VolunteerDispatchSummaryCard` 同：卡片本体要
    /// `.combine` 成一个可听的整体，而「查看服务成就」必须留在那个整体**之外**才点得到。
    /// 两者是兄弟节点，不是父子。
    private func content(_ summary: VolunteerHomeIncentiveSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 14) {
                Text(VolunteerHomeIncentiveCopy.sectionTitle)
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                hero(summary)

                if let streak = summary.streak {
                    StreakStrip(
                        // 只念不显示，所以去掉掩码星号（见 `StreakStrip.partnerName`）。
                        partnerName: summary.streakPartnerName?.unmaskedForSpeech.nilIfBlank
                            ?? PartnerStreakCopy.unknownBlindName,
                        streak: streak
                    )
                }

                if summary.showsBadgeRow, let next = summary.nextBadge {
                    badgeRow(next)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(AppColors.secondaryBackground)
            .clipShape(
                RoundedRectangle(cornerRadius: VolunteerHomeRadius.card, style: .continuous)
            )
            .accessibilityElement(children: .combine)
            .accessibilityLabel(VolunteerHomeIncentiveCopy.accessibilityLabel(summary))
            .accessibilityIdentifier("volunteerHomeIncentiveCard")

            achievementsLink
        }
    }

    @ViewBuilder
    private func hero(_ summary: VolunteerHomeIncentiveSummary) -> some View {
        switch summary.hero {
        case .partners(let count):
            VStack(alignment: .leading, spacing: 6) {
                // 🔴 走 `AppFonts.largeTitle()` 而不是 `.system(size:)` 固定磅值 ——
                // 这张卡最大的那个数字恰恰是低视力用户最需要放大的东西，
                // 固定磅值不跟 Dynamic Type 走。本仓库为这条栽过一次（成就页头部原本写死 48pt）。
                Text("\(count)")
                    .font(AppFonts.largeTitle())
                    .foregroundColor(AppColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(VolunteerHomeIncentiveCopy.partnersCaption)
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case .badgeProgress(let current, let target, let suffix, let badgeName):
            VStack(alignment: .leading, spacing: 6) {
                Text("\(current) / \(target) \(suffix)")
                    .font(AppFonts.largeTitle())
                    .foregroundColor(AppColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(VolunteerHomeIncentiveCopy.nextBadgePrefix)：\(badgeName)")
                    .font(AppFonts.body())
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

        case nil:
            EmptyView()
        }
    }

    private func badgeRow(_ next: VolunteerNextBadgeDto) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(VolunteerHomeIncentiveCopy.nextBadgePrefix)：\(next.displayName)")
                .font(AppFonts.body().weight(.semibold))
                .foregroundColor(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let fraction = next.progressFraction, let progressText = next.progressText {
                ProgressView(value: fraction)
                    .tint(AppColors.primary)
                    .accessibilityHidden(true)

                // 进度条对 VoiceOver 是空的，所以这一行不是冗余 —— 它是这一段
                // 唯一能被念出来的进度信息。两者顺序不能倒，也不能只留进度条。
                Text(progressText)
                    .font(AppFonts.caption())
                    .foregroundColor(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 去成就页。这张卡只给一个去处，**不给积分入口** —— 理由见
    /// `VolunteerHomeIncentiveSummary` 顶部（积分与服务时长不同屏）。
    private var achievementsLink: some View {
        NavigationLink {
            VolunteerServiceRecognitionView()
        } label: {
            HStack(spacing: 6) {
                Text(VolunteerHomeIncentiveCopy.achievementsLinkTitle)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .accessibilityHidden(true)
            }
            .font(AppFonts.body().weight(.semibold))
            .foregroundColor(AppColors.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            // 44pt 是系统触达下限。志愿者端不受盲人端 64pt 线约束
            // （`guard.mjs` 的 `small-touch-target` 显式排除 /blindRun/Volunteer/）。
            .frame(minHeight: 44)  // guard:allow small-touch-target
            .padding(.horizontal, 14)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(VolunteerHomeIncentiveCopy.achievementsLinkTitle)
        .accessibilityHint(VolunteerHomeIncentiveCopy.achievementsLinkHint)
        .accessibilityIdentifier("volunteerHomeIncentiveAchievementsLink")
    }
}
