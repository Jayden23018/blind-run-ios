import XCTest
@testable import blindRun

/// #552：连续拒绝次数与「问过时的次数」按账号记，登出时清掉。
///
/// 原来两个数存在全局 `UserDefaults`，登出不清、也不分账号：陪跑员 A 登出、B 在同一台手机登录后，
/// B 的第一份待回复快照到之前，会被 A 的次数问一句「要不要调整空闲时间」。
@MainActor
final class VolunteerDeclineStreakAccountTests: XCTestCase {
    private let accountA: Int64 = 41
    private let accountB: Int64 = 42

    /// 问题单原样：A 连拒 3 次（后端数到 3）→ A 登出 → B 登录，B 的次数从 0 开始，不问。
    func testNextAccountAfterLogoutStartsFromZero() async {
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        defer { persistence.reset() }
        let (viewModel, appState, _, _) = InviteLockScreenFixture.makeHome(persistence: persistence)
        appState.userId = accountA
        appState.realtimeCoordinator.reconcilePendingInvites([], requestedAt: Date(), consecutiveDeclineCount: 3)
        await InviteLockScreenFixture.waitUntil { viewModel.shouldAskAboutAvailability }
        XCTAssertTrue(viewModel.shouldAskAboutAvailability, "前提：A 的次数到 3 了")

        appState.clearSession()
        appState.userId = accountB

        XCTAssertEqual(VolunteerDeclineStreak(persistence: persistence, userID: accountB).count, 0)
        XCTAssertFalse(viewModel.shouldAskAboutAvailability, "B 一次都没拒绝过，却被 A 的次数问了「要不要调整空闲时间」")
    }

    /// 不经登出直接换账号（`userId` 非空换非空）：两个账号各算各的，「问过时的次数」也一样。
    func testSwitchingAccountsKeepsEachAccountsOwnCountAndAskedMark() {
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        defer { persistence.reset() }
        let (viewModel, appState, _, _) = InviteLockScreenFixture.makeHome(persistence: persistence)
        appState.userId = accountA
        VolunteerDeclineStreak(persistence: persistence, userID: accountA).adoptServerCount(3)
        viewModel.acknowledgeAvailabilityPrompt()
        XCTAssertFalse(viewModel.shouldAskAboutAvailability, "前提：A 在 3 次时被问过了")

        appState.userId = accountB
        XCTAssertFalse(viewModel.shouldAskAboutAvailability, "B 读到了 A 的次数")
        VolunteerDeclineStreak(persistence: persistence, userID: accountB).adoptServerCount(3)
        XCTAssertTrue(viewModel.shouldAskAboutAvailability, "B 自己到 3 了却不问：A 问过的记号串到了 B 名下")

        appState.userId = accountA
        XCTAssertFalse(viewModel.shouldAskAboutAvailability, "换回 A：A 问过的记号要还在，不能被 B 改掉")
        XCTAssertEqual(VolunteerDeclineStreak(persistence: persistence, userID: accountA).count, 3)
    }

    /// 登出后这台手机上不留 A 的两个数；全局计数时代那两个不带 userId 的旧键也一并删掉。
    func testLogoutLeavesNoDeclineCountOnThePhone() {
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        defer { persistence.reset() }
        let appState = AppState(persistence: persistence)
        appState.userId = accountA
        let streak = VolunteerDeclineStreak(persistence: persistence, userID: accountA)
        streak.adoptServerCount(4)
        streak.acknowledgeAsked()
        let legacyKeys = ["aidrun.volunteer.consecutiveDeclineCount", "aidrun.volunteer.consecutiveDeclineCountAskedAt"]
        legacyKeys.forEach { persistence.set(5, forKey: $0) }

        appState.clearSession()

        XCTAssertEqual(streak.count, 0, "A 的次数还留在手机上")
        XCTAssertEqual(streak.askedAt, 0, "A 问过的记号还留在手机上")
        for key in legacyKeys {
            XCTAssertNil(persistence.object(forKey: key), "不带 userId 的旧键 \(key) 没删")
        }
    }

    /// 没有账号（未登录、会话还没恢复）时不落盘：记不到任何人名下的数不该留下。
    func testNoAccountMeansNothingIsStored() {
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        defer { persistence.reset() }
        let streak = VolunteerDeclineStreak(persistence: persistence, userID: nil)

        streak.recordDecline()
        streak.adoptServerCount(3)

        XCTAssertEqual(streak.count, 0)
        XCTAssertFalse(streak.shouldAskAboutAvailability)
        XCTAssertEqual(VolunteerDeclineStreak(persistence: persistence, userID: accountA).count, 0, "没账号时的数落到了别人名下")
    }
}
