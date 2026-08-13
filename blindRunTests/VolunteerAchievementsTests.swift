import XCTest
@testable import blindRun

/// 志愿者成就页（`GET /api/volunteer/achievements`，后端 SPEC-D D1）。
///
/// 这一组守三件事，一件比一件难在 UI 里发现：
///
/// 1. **`badges` 的语义**。契约里它**只含已解锁的勋章**。后端 SPEC-D §D1.2 把「顺手改成
///    全量 + `unlocked` 布尔」列为整份 SPEC 最容易出事的地方：已发版客户端不认识
///    `unlocked`，会把七枚一律当已解锁渲染，而 `openapi-diff` 只看到「加了两个可选字段」，
///    判绿。客户端这边能做的就是钉死「不读 `unlocked`、列表里的每一条都是已解锁」。
/// 2. **国标星级与平台勋章的门槛不是一回事**。平台最高的时长勋章是 50 小时，
///    国标一星要 100 小时。算错一边，志愿者会拿着我们的页面去学校申报然后被退回。
/// 3. **文案不得把展示说成凭据**（民政部令第 67 号）。守卫规则
///    `volunteer-hours-credential` 拦生产代码里的措辞，这里再钉一遍常量本身。
@MainActor
final class VolunteerAchievementsTests: XCTestCase {

    // MARK: - 国标星级：GB/T 40143—2021

    /// 门槛逐条对国标。写死在用例里而不是引用 `hourThresholds` ——
    /// 引用常量的用例在常量被改错时同样绿。
    func testStarThresholdsMatchTheNationalStandard() {
        XCTAssertEqual(VolunteerStarLevel.hourThresholds, [100, 300, 600, 1000, 1500])
    }

    func testNinetyNineHoursIsStillBelowOneStar() {
        let level = VolunteerStarLevel.derive(totalServiceMinutes: 99 * 60)
        XCTAssertEqual(level.current, 0)
        XCTAssertEqual(level.currentHours, 99)
        XCTAssertEqual(level.nextTarget, 100)
    }

    func testOneHundredHoursReachesOneStar() {
        let level = VolunteerStarLevel.derive(totalServiceMinutes: 100 * 60)
        XCTAssertEqual(level.current, 1)
        XCTAssertEqual(level.nextTarget, 300)
    }

    func testFifteenHundredHoursIsTheTopAndHasNoNextTarget() {
        let level = VolunteerStarLevel.derive(totalServiceMinutes: 1500 * 60)
        XCTAssertEqual(level.current, 5)
        XCTAssertNil(level.nextTarget)
    }

    /// 向下取整：99 小时 59 分不是 100 小时。少算而不是多算 ——
    /// 多算的后果是志愿者以为够了、去申报、被退回。
    func testPartialHoursRoundDown() {
        let level = VolunteerStarLevel.derive(totalServiceMinutes: 100 * 60 - 1)
        XCTAssertEqual(level.currentHours, 99)
        XCTAssertEqual(level.current, 0)
    }

    func testNegativeMinutesDoNotProduceNegativeHours() {
        let level = VolunteerStarLevel.derive(totalServiceMinutes: -30)
        XCTAssertEqual(level.currentHours, 0)
        XCTAssertEqual(level.current, 0)
    }

    // MARK: - 服务端值优先于本地推算

    /// 本地推算只是后端 `starLevel` 发布前的过渡。后端一旦给值，就以后端为准 ——
    /// 否则两边算法哪天分叉，界面显示的是客户端那份，而志愿者申报按的是后端那份。
    func testServerStarLevelWinsOverLocalDerivation() throws {
        let json = """
        {"totalCompleted": 3, "totalServiceMinutes": 6000,
         "starLevel": {"current": 2, "currentHours": 301, "nextTarget": 600}}
        """
        let response = try JSONDecoder().decode(
            VolunteerAchievementsResponse.self,
            from: Data(json.utf8)
        )
        XCTAssertEqual(response.resolvedStarLevel.current, 2)
        XCTAssertEqual(response.resolvedStarLevel.currentHours, 301)
    }

    /// 后端尚未发布 `starLevel`（核于 2026-08-13）时必须能落到本地推算，
    /// 而不是让整栏空着 —— 那一栏空着等于这次改版没做。
    func testMissingStarLevelFallsBackToLocalDerivation() throws {
        let json = #"{"totalCompleted": 42, "totalServiceMinutes": 2520}"#
        let response = try JSONDecoder().decode(
            VolunteerAchievementsResponse.self,
            from: Data(json.utf8)
        )
        XCTAssertNil(response.starLevel)
        XCTAssertEqual(response.resolvedStarLevel.currentHours, 42)
        XCTAssertEqual(response.resolvedStarLevel.nextTarget, 100)
    }

    // MARK: - badges 的语义（回归门）

    /// 🔴 **这条红了说明有人把 `badges` 当成了「全量 + unlocked」。**
    /// 契约里它只含已解锁的，客户端不读也不该读 `unlocked` 字段。
    func testEveryBadgeInTheListIsTreatedAsUnlocked() throws {
        let json = """
        {"badges": [{"code": "FIRST_RUN", "name": "首次陪跑"},
                    {"code": "RUNS_10", "name": "陪跑达人 · 10 次"}]}
        """
        let response = try JSONDecoder().decode(
            VolunteerAchievementsResponse.self,
            from: Data(json.utf8)
        )
        XCTAssertEqual(response.unlockedBadges.count, 2)
        for badge in response.unlockedBadges {
            XCTAssertTrue(
                VolunteerAchievementsCopy.badgeAccessibilityLabel(badge).hasSuffix("已解锁"),
                "列表里的每一条都必须被当成已解锁；出现「未解锁」说明语义被改了"
            )
        }
    }

    /// 后端往枚举加值而 spec 没跟上时，未知 `code` 不许让整条响应炸掉 ——
    /// 对志愿者是少一个图标，对同一套解码习惯下的盲人端是整页空白。
    func testUnknownBadgeCodeStillRendersWithAFallbackIcon() throws {
        let json = #"{"badges": [{"code": "NIGHT_OWL", "name": "夜跑之星"}]}"#
        let response = try JSONDecoder().decode(
            VolunteerAchievementsResponse.self,
            from: Data(json.utf8)
        )
        let badge = try XCTUnwrap(response.unlockedBadges.first)
        XCTAssertEqual(badge.displayName, "夜跑之星")
        XCTAssertFalse(badge.symbolName.isEmpty)
    }

    /// 既没有 `code` 也没有 `name` 的条目渲染出来是一个空格子，
    /// 对读屏用户则是一个没有内容却可聚焦的元素。丢掉它。
    func testBadgesWithoutCodeOrNameAreDropped() throws {
        let json = #"{"badges": [{"code": null, "name": "  "}, {"code": "FIRST_RUN", "name": "首次陪跑"}]}"#
        let response = try JSONDecoder().decode(
            VolunteerAchievementsResponse.self,
            from: Data(json.utf8)
        )
        XCTAssertEqual(response.unlockedBadges.count, 1)
    }

    /// 今天后端真实返回的形状：没有 `nextBadge`、没有 `starLevel`。必须解得出来。
    func testTodaysBackendShapeDecodes() throws {
        let json = """
        {"totalCompleted": 37, "totalServiceMinutes": 2520, "avgRating": 4.9,
         "totalRatings": 30, "badges": [{"code": "FIRST_RUN", "name": "首次陪跑"}]}
        """
        let response = try JSONDecoder().decode(
            VolunteerAchievementsResponse.self,
            from: Data(json.utf8)
        )
        XCTAssertEqual(response.completedCount, 37)
        XCTAssertNil(response.nextBadge)
        XCTAssertNil(response.starLevel)
    }

    // MARK: - nextBadge 进度

    func testNextBadgeProgressIsAUnitFreeFraction() throws {
        let json = #"{"nextBadge": {"code": "RUNS_50", "name": "陪跑达人 · 50 次", "current": 37, "target": 50}}"#
        let response = try JSONDecoder().decode(
            VolunteerAchievementsResponse.self,
            from: Data(json.utf8)
        )
        let next = try XCTUnwrap(response.nextBadge)
        XCTAssertEqual(next.progressText, "已完成 37 / 50")
        // 不拼「次」「小时」：`HOURS_10` 的 target 是 10 还是 600 契约没写，已投 handoff。
        // 分数形式在三种答案下都对。
        XCTAssertFalse(next.progressText?.contains("次") ?? true)
        XCTAssertFalse(next.progressText?.contains("小时") ?? true)
    }

    func testNextBadgeWithZeroTargetShowsNoProgressBar() throws {
        let json = #"{"nextBadge": {"code": "X", "name": "X", "current": 0, "target": 0}}"#
        let response = try JSONDecoder().decode(
            VolunteerAchievementsResponse.self,
            from: Data(json.utf8)
        )
        let next = try XCTUnwrap(response.nextBadge)
        XCTAssertNil(next.progressFraction, "分母为 0 时不画进度条，也不显示 0/0")
        XCTAssertNil(next.progressText)
    }

    // MARK: - 无障碍：进度必须是可读的文本，不能只画在进度条里

    /// 进度条对 VoiceOver 是空的。「还差 58 小时」如果只存在于进度条的几何里，
    /// 对看不见屏幕的人这一栏就等于没有内容。
    func testStarProgressIsReadableText() {
        let level = VolunteerStarLevel.derive(totalServiceMinutes: 42 * 60)
        let text = VolunteerAchievementsCopy.starProgressText(level)
        XCTAssertTrue(text.contains("42"))
        XCTAssertTrue(text.contains("100"))
        XCTAssertTrue(text.contains("还差 58 小时"))
    }

    /// 星级栏合成一个焦点后，朗读文本必须仍然包含「还差多少」——
    /// 合并焦点是为了不让用户听三遍同一个数，不是为了少说话。
    func testStarAccessibilityLabelKeepsTheRemainingHours() {
        let level = VolunteerStarLevel.derive(totalServiceMinutes: 42 * 60)
        let label = VolunteerAchievementsCopy.starAccessibilityLabel(level)
        XCTAssertTrue(label.contains("还差 58 小时"))
        XCTAssertTrue(label.contains("一星"))
    }

    func testTopStarAccessibilityLabelDoesNotPromiseAFurtherStar() {
        let level = VolunteerStarLevel.derive(totalServiceMinutes: 2000 * 60)
        let label = VolunteerAchievementsCopy.starAccessibilityLabel(level)
        XCTAssertTrue(label.contains("五星"))
        XCTAssertFalse(label.contains("还差"))
    }

    // MARK: - 文案红线（民政部令第 67 号）

    /// 「证明」「证书」「已认证」在这一页是违规措辞，不是措辞偏好：可查验的志愿服务记录
    /// 证明须经志愿服务信息系统出具，我们没有对接。守卫规则 `volunteer-hours-credential`
    /// 拦生产代码，这条钉常量本身 —— 两道都要有，守卫只看改动的文件。
    func testCopyNeverClaimsToBeACredential() {
        let banned = ["证明", "证书", "已认证"]
        let copy = [
            VolunteerAchievementsCopy.navigationTitle,
            VolunteerAchievementsCopy.starSectionTitle,
            VolunteerAchievementsCopy.starSectionStandard,
            VolunteerAchievementsCopy.badgeSectionTitle,
            VolunteerAchievementsCopy.badgeSectionEmpty,
            VolunteerAchievementsCopy.nextBadgeSectionTitle,
            VolunteerAchievementsCopy.disclaimer,
            VolunteerAchievementsCopy.starTitle(current: 0),
            VolunteerAchievementsCopy.starTitle(current: 3),
            VolunteerAchievementsCopy.starProgressText(
                VolunteerStarLevel.derive(totalServiceMinutes: 42 * 60)
            )
        ]
        for text in copy {
            for word in banned {
                XCTAssertFalse(text.contains(word), "「\(word)」出现在成就页文案里：\(text)")
            }
        }
    }

    /// 免责那句必须指出对外申报走哪条路。只说「本页不是凭据」而不说去哪儿办，
    /// 志愿者仍然会拿着这一页去学校。
    func testDisclaimerPointsToTheRealChannel() {
        XCTAssertTrue(VolunteerAchievementsCopy.disclaimer.contains("全国志愿服务信息系统"))
    }

    // MARK: - 勋章墙：主页只露 4 枚

    func testHomeShowsAtMostFourBadges() {
        let badges = (1...7).map { VolunteerBadgeDto(code: "B\($0)", name: "勋章\($0)") }
        XCTAssertEqual(VolunteerBadgeWall.preview(badges).count, 4)
        XCTAssertTrue(VolunteerBadgeWall.hasMore(badges))
        XCTAssertEqual(VolunteerBadgeWall.moreLinkTitle(badges), "查看全部 7 枚勋章")
    }

    func testFourOrFewerBadgesNeedNoSecondaryPage() {
        let badges = (1...4).map { VolunteerBadgeDto(code: "B\($0)", name: "勋章\($0)") }
        XCTAssertEqual(VolunteerBadgeWall.preview(badges).count, 4)
        XCTAssertFalse(VolunteerBadgeWall.hasMore(badges))
    }
}
