import Combine
import SwiftUI

// MARK: - Service Recognition

/// 志愿者服务成就页。**取代了此前的「积分商城」占位页。**
///
/// 那一页的积分数字写死 `--`，4 个商品（运动腰包 / 水壶 / 毛巾 / 腰灯）硬编码在数组里
/// 全标「敬请期待」，`VolunteerPointsViewModel` 只有一个从不被赋值的 `errorMessage`。
/// 一个永远兑换不了的商城比没有激励更伤：它每次都在提醒志愿者，平台承诺过什么、
/// 又没有兑现 —— 调研里「没有实质的表彰」正是激励设计的首要陷阱
/// （`docs/research/live-trip-sharing-and-volunteer-incentives-20260813.md` §2）。
///
/// 现在页面上的**每个数字都来自后端真有的字段**：`totalCompleted` / `totalServiceMinutes` /
/// `avgRating` / `badges`，志愿者可以自己核对。此前那版还有一套**客户端自己编的**五档称号
/// （熟练 / 资深 / 金牌 / 荣誉陪跑员，阈值 1/10/25/50/100 单），后端没有这些名字 ——
/// 一页上并排放两套勋章体系，比少一套更让人看不懂自己到底拿到了什么。已随本次改版删除。
///
/// 🔴 **国标星级与平台勋章分两栏，不合并。** 平台最高的时长勋章是 50 小时，
/// 而国标一星要 100 小时（GB/T 40143—2021）。合并展示会让志愿者以为拿了最高勋章就能评星，
/// 去学校申报时才发现一星都评不上。理由与阈值见 `VolunteerStarLevel`。
///
/// 页面数据来自 `GET /api/volunteer/achievements`，**不再由首页的 `dispatchSummary` 喂**。
/// 后端刻意把它和 dispatch-summary 分开：`totalServiceMinutes` 要扫该志愿者的全部已完成订单，
/// 而 dispatch-summary 是首页、每次打开都调，不该让低频页面的代价压在最热的端点上
/// （`api_spec.yaml` 那条 description）。所以这一页有自己的一次加载。
///
/// 并发只用 async/await：一个 `.task`，没有 `AnyCancellable`（AGENTS.md 硬约束）。
@MainActor
final class VolunteerAchievementsViewModel: ObservableObject {
    @Published private(set) var achievements: VolunteerAchievementsResponse?
    @Published private(set) var errorMessage: String?
    @Published private(set) var isLoading = true

    private weak var appState: AppState?

    /// ⚠️ `appState` 是 `weak`：传临时对象等于传 nil，用例要自己持有它。
    func configure(appState: AppState) {
        self.appState = appState
    }

    /// 拉服务成就。**失败一定要留下东西**：`errorMessage` 驱动 `errorSection`
    /// （一行原因 + 一个「重新加载」）。这段原来住在 view body 里，
    /// 三个 `@State` 之间没有任何测试面。
    func load() async {
        guard let appState else {
            isLoading = false
            errorMessage = "服务成就加载失败，请稍后重试。"
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            // 成就属于激励片（`IncentiveService`），不是订单片 —— 两片并行开发时
            // 各自实现了一遍 `GET /api/volunteer/achievements`，合并时以先落 main 的激励片为准。
            achievements = try await appState.incentive.volunteerAchievements()
            errorMessage = nil
        } catch let error as APIError {
            errorMessage = error.localizedMessage
        } catch {
            errorMessage = "服务成就加载失败，请稍后重试。"
        }
    }
}

// 页面本体在 `VolunteerServiceRecognitionView.swift`，徽章页在 `VolunteerBadgeWallView.swift`（#697 起）。

// 「我的」（`VolunteerSettingsView`）在 `VolunteerSettingsView.swift`，账户页在 `VolunteerAccountView.swift`（#700 起）。
