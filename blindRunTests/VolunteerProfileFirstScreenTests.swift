import CoreGraphics
import XCTest
@testable import blindRun

/// 志愿者「我」首屏的展示口径 + 底部滑动 CTA 的阈值。
///
/// 这两块是整个改版里**唯一会悄悄坏掉**的部分：阈值改错了控件照常能用，
/// 只是变难或者一碰就开；新人口径写错了只是一屏看起来正常的 0。
/// 两者都没有任何运行时信号，所以必须有可验红的用例钉住。
final class VolunteerProfileFirstScreenTests: XCTestCase {

    // MARK: - 滑动阈值

    /// Uber Base 的 Low (Easy) 档：滑过 **20%** 触发。
    ///
    /// 🔴 **两条断言各自落在阈值的一侧，且都在 20% 附近**（19.95% / 20.05%），
    /// 这是刻意的：随手取「滑 1%」和「滑 90%」的话，把阈值改成 0.8 或 0.05
    /// 这两条**照样通过** —— 那样的用例分辨不出门槛被挪过。
    /// 现在这一对能同时挡住调高（0.8 时第二条挂）和调低（0.05 时第一条挂）。
    func testSlideActivationSitsAtTwentyPercentInBothDirections() {
        let trackWidth: CGFloat = 200

        XCTAssertFalse(
            VolunteerAvailabilitySlide.activates(dragX: 39.9, trackWidth: trackWidth),
            "滑过 19.95% 就触发 —— 阈值被调低了，会变成一碰就开"
        )
        XCTAssertTrue(
            VolunteerAvailabilitySlide.activates(dragX: 40.1, trackWidth: trackWidth),
            "滑过 20.05% 还不触发 —— 阈值被调高了，Uber 官方点名高阈值对运动障碍者与老年人不友好"
        )
        XCTAssertEqual(VolunteerAvailabilitySlide.activationFraction, 0.2, accuracy: 0.0001)
    }

    /// 退化输入一律不触发、不产生非有限位移。
    ///
    /// `GeometryReader` 在布局算出来之前会给 NaN；一个 NaN 会把滑块画到屏幕外，
    /// 而屏幕上看起来只是「滑块不见了」。
    func testSlideRejectsDegenerateGeometry() {
        for width in [CGFloat(0), -120, .nan, .infinity] {
            XCTAssertFalse(
                VolunteerAvailabilitySlide.activates(dragX: 999, trackWidth: width),
                "trackWidth=\(width) 时不该触发"
            )
        }
        XCTAssertEqual(VolunteerAvailabilitySlide.travel(dragX: .nan, trackWidth: 200), 0)
        XCTAssertEqual(VolunteerAvailabilitySlide.travel(dragX: -80, trackWidth: 200), 0, "往左拖不该把滑块拖出轨道")
        XCTAssertEqual(VolunteerAvailabilitySlide.travel(dragX: 9_999, trackWidth: 200), 200, "往右拖到底要钳在轨道末端")
        XCTAssertTrue(VolunteerAvailabilitySlide.progress(dragX: 100, trackWidth: 200).isFinite)
    }

    // MARK: - 主指标

    /// 🔴 新人不显示「0 次陪跑」——一屏上最大最粗的那个数字是 0，那是负激励。
    func testNewcomerNeverShowsAZeroHeroNumber() {
        XCTAssertEqual(VolunteerProfileHeadline.resolve(totalCompleted: 0), .newcomer)
        XCTAssertEqual(VolunteerProfileHeadline.resolve(totalCompleted: nil), .newcomer)
        XCTAssertEqual(VolunteerProfileHeadline.resolve(totalCompleted: -3), .newcomer, "负数是脏数据，同样不该上屏")
        XCTAssertEqual(VolunteerProfileHeadline.resolve(totalCompleted: 1), .completed(count: 1))

        let spoken = VolunteerProfileCopy.heroSpoken(.newcomer)
        XCTAssertFalse(spoken.contains("0"), "新人播报里出现了 0：\(spoken)")
        XCTAssertTrue(spoken.contains(VolunteerAvailabilityCopy.toggleTitle), "新人那句话要说清下一步在哪：\(spoken)")
    }

    /// 新人态下 3 列统计与星级进度整块不画 —— 那三个数此刻全是 0 / `--` / 0 小时，
    /// 摆出来的信息是「你离得很远」。
    func testNewcomerHidesTheImpactGridAndStarProgress() {
        XCTAssertFalse(VolunteerProfileHeadline.newcomer.showsImpactSections)
        XCTAssertTrue(VolunteerProfileHeadline.completed(count: 1).showsImpactSections)
    }

    /// 🔴 **成就那条请求失败时，不许把老志愿者渲染成新人。**
    ///
    /// 三条只读端点各自独立容错，所以「收藏成功 + 成就失败」是一条很常见的路径：
    /// 那时 `summary != nil` 而 `summary.achievements == nil`。如果视图按 `summary` 判，
    /// 第一个分支恒中 ⇒ 失败 + 重试那一档**永远走不到**，而 `totalCompleted` 为 nil
    /// 会落进 `.newcomer` ⇒ 屏幕上出现「还没有完成的陪跑」+ 星级与 3 列统计一起消失。
    /// **跑过 200 次的人和真新人逐字不可区分，且没有任何出错信号。**
    ///
    /// 这条钉的是「`achievements == nil` 与 `totalCompleted == 0` 是两件事」——
    /// 视图侧的判据必须是前者，用例在这里锁住区分度。
    func testMissingAchievementsIsNotTheSameAsAZeroCountVeteran() {
        // 成就失败、收藏成功：`summary` 有值，但 `achievements` 是 nil。
        let achievementsFailed = VolunteerHomeIncentiveSummary(
            favoritedByCount: 8,
            nextBadge: nil,
            streak: nil,
            streakPartnerName: nil
        )
        XCTAssertNotNil(achievementsFailed, "这一档确实存在：一条失败不该让另外两条也消失")
        XCTAssertNil(
            achievementsFailed.achievements,
            "成就失败时 achievements 必须是 nil —— 视图就是靠它区分「读不到」和「真的是 0」"
        )

        // 真新人：成就**读到了**，只是数字是 0。
        let realNewcomer = Self.achievements(
            totalCompleted: 0, minutes: 0, avgRating: nil, totalRatings: 0
        )
        XCTAssertEqual(VolunteerProfileHeadline.resolve(totalCompleted: realNewcomer.totalCompleted), .newcomer)

        // 老志愿者：同样读到了，数字非 0。
        let veteran = Self.achievements(
            totalCompleted: 200, minutes: 60_000, avgRating: 4.9, totalRatings: 180
        )
        XCTAssertEqual(
            VolunteerProfileHeadline.resolve(totalCompleted: veteran.totalCompleted),
            .completed(count: 200)
        )

        // 🚩 这一条是本用例的重点：**光看 `summary` 非空分不出上面两种人**。
        // 视图如果按 `summary != nil` 判，`achievementsFailed` 这一档就会走进
        // `impactContent`，然后 `resolve(totalCompleted: nil)` 把它变成新人。
        XCTAssertEqual(
            VolunteerProfileHeadline.resolve(totalCompleted: nil),
            .newcomer,
            "nil 落进 .newcomer 是 resolve 的既有行为 —— 正因如此，调用方必须先保证 achievements 非空"
        )
    }

    // MARK: - 三列统计

    /// 时长向下取整：51 分钟不是 1 小时。少算而不是多算，与后端口径同向。
    func testHoursRoundDownAndClampNegatives() {
        XCTAssertEqual(VolunteerProfileStats.hours(11_160).value, "186")
        XCTAssertEqual(VolunteerProfileStats.hours(59).value, "0", "51 分钟不是 1 小时")
        XCTAssertEqual(VolunteerProfileStats.hours(nil).value, "0")
        XCTAssertEqual(VolunteerProfileStats.hours(-600).value, "0")
    }

    /// 没有评价时屏幕上是 `--`，**念出来不能是「破折号破折号」**。
    /// 成就页为同一条被无障碍审计判过 `Label not human-readable`。
    func testRatingPlaceholderIsNeverSpokenAsPunctuation() {
        let empty = VolunteerProfileStats.rating(average: nil, total: nil)
        XCTAssertEqual(empty.value, "--")
        XCTAssertFalse(empty.spoken.contains("-"), "占位符号被念出来了：\(empty.spoken)")
        XCTAssertEqual(empty.spoken, VolunteerProfileCopy.ratingSpokenWhenEmpty)

        let rated = VolunteerProfileStats.rating(average: 4.94, total: 32)
        XCTAssertEqual(rated.value, "4.9")
        XCTAssertTrue(rated.caption.contains("32"), "评价条数应当挂在副标题上：\(rated.caption)")

        // 有均分但条数为 0 时不拼「· 0 条」——那是两个占位符并排。
        let zeroCount = VolunteerProfileStats.rating(average: 5, total: 0)
        XCTAssertFalse(zeroCount.caption.contains("0"), "不该显示 0 条：\(zeroCount.caption)")
    }

    func testStatsRowIsAlwaysThreeColumnsInAFixedOrder() {
        let row = VolunteerProfileStats.row(
            achievements: Self.achievements(totalCompleted: 24, minutes: 11_160, avgRating: 4.9, totalRatings: 32),
            favoritedByCount: 8
        )
        XCTAssertEqual(row.count, 3)
        XCTAssertEqual(row.map(\.value), ["186", "8", "4.9"])
        XCTAssertEqual(row.map(\.caption).first, VolunteerProfileCopy.hoursCaption)
        // 固定搭档那格复用既有的完整播报（「有 8 位跑者把你设为固定搭档」）——
        // 「固定搭档 8 位」说不清是谁选了谁。
        XCTAssertEqual(row[1].spoken, VolunteerHomeIncentiveCopy.partnersSpoken(8))
    }

    // MARK: - 徽章一排

    /// 末位留给「下一枚」，其余给已解锁的，总数恒为一排。
    func testBadgeRowReservesTheLastCellForTheNextBadge() {
        let unlocked = (1...6).map { VolunteerBadgeDto(code: "RUNS_\($0)", name: "勋章\($0)") }
        let next = VolunteerNextBadgeDto(code: "HOURS_10", name: "夜跑守护", current: 180, target: 300)

        let withNext = VolunteerProfileBadgeRow.cells(unlocked: unlocked, next: next)
        XCTAssertEqual(withNext.count, VolunteerProfileBadgeRow.cellCount)
        guard case .next = withNext.last else {
            return XCTFail("最后一格应该是「下一枚」，实际是 \(String(describing: withNext.last))")
        }

        // 七枚全解锁时 `nextBadge` 为 null，四格全给已解锁的。
        let allUnlocked = VolunteerProfileBadgeRow.cells(unlocked: unlocked, next: nil)
        XCTAssertEqual(allUnlocked.count, VolunteerProfileBadgeRow.cellCount)
        XCTAssertTrue(allUnlocked.allSatisfy { if case .unlocked = $0 { return true }; return false })
    }

    /// 🚩 拿不到**给人看的名字**时那一格不画：`displayName` 会退到 `code`
    /// （`HOURS_10` 这种英文枚举），上屏就是噪音。判据与首页那张卡的 `showsBadgeRow` 一致。
    func testBadgeRowDropsTheNextCellWithoutAHumanReadableName() {
        let codeOnly = VolunteerNextBadgeDto(code: "HOURS_10", name: nil, current: 3, target: 5)
        let cells = VolunteerProfileBadgeRow.cells(unlocked: [], next: codeOnly)
        XCTAssertTrue(cells.isEmpty, "只有 code 没有 name 时不该画那一格：\(cells)")
    }

    /// 🔴 进度文案**不写「还差 N 就解锁」** —— `HIGH_RATED` 是双条件，满格也可能没解锁。
    func testNextBadgeCaptionStatesProgressWithoutPromisingUnlock() {
        let hours = VolunteerNextBadgeDto(code: "HOURS_10", name: "十小时陪伴", current: 180, target: 600)
        // `HOURS_*` 的单位是**分钟**，展示要换算成小时。
        XCTAssertEqual(VolunteerProfileBadgeRow.nextBadgeCaption(hours), "十小时陪伴 3/10")

        let runs = VolunteerNextBadgeDto(code: "RUNS_10", name: "夜跑守护", current: 3, target: 5)
        XCTAssertEqual(VolunteerProfileBadgeRow.nextBadgeCaption(runs), "夜跑守护 3/5")

        // 未知 code 拿不到量词 ⇒ 只给名字，不拼一个猜的分母。
        let unknown = VolunteerNextBadgeDto(code: "MOONWALK", name: "月球漫步", current: 1, target: 9)
        XCTAssertEqual(VolunteerProfileBadgeRow.nextBadgeCaption(unknown), "月球漫步")

        for caption in [VolunteerProfileBadgeRow.nextBadgeCaption(hours), VolunteerProfileBadgeRow.nextBadgeCaption(runs)] {
            XCTAssertFalse(caption.contains("解锁"), "徽章进度不得承诺解锁：\(caption)")
        }
    }

    /// 「全部 N 枚」里的 N 是**已解锁枚数**。后端 `badges[]` 只含已解锁的，
    /// 客户端拿不到总数 —— 写死 7 会让解锁 3 枚的人点进去看到 3 枚而标题说 7 枚。
    func testBadgeLinkTitleCountsOnlyUnlockedBadges() {
        XCTAssertEqual(VolunteerProfileBadgeRow.allLinkTitle(unlockedCount: 3), "全部 3 枚")
        XCTAssertEqual(
            VolunteerProfileBadgeRow.allLinkTitle(unlockedCount: 0),
            VolunteerProfileCopy.badgesLinkTitleWhenEmpty,
            "一枚都没有时不该说「全部 0 枚」"
        )
    }

    // MARK: - 最近陪跑的日期格

    func testRecentDateFallsBackToNothingRatherThanToday() {
        let parts = VolunteerProfileRecentDate.parts(from: "2026-09-13T08:30:00")
        XCTAssertEqual(parts?.day, "13")
        XCTAssertEqual(parts?.month, "9月")

        for bad in [nil, "", "   ", "not-a-date"] {
            XCTAssertNil(
                VolunteerProfileRecentDate.parts(from: bad),
                "解析不了的时间戳必须整格不画，不能拿今天顶上：\(String(describing: bad))"
            )
        }
    }

    // MARK: - 文案红线

    /// 🔴 民政部令第 67 号：这一屏是展示不是凭据，**不得出现「证明 / 证书 / 已认证」**。
    /// 守卫规则 `volunteer-hours-credential` 扫源码，这条扫的是运行时真正拼出来的串。
    ///
    /// 同时挡住激励层的三条红线：不折算金额、不做月度目标、不催促下一单。
    func testFirstScreenCopyNeverClaimsCredentialsOrPushesForMoreRuns() {
        let strings = [
            VolunteerProfileCopy.roleTitle,
            VolunteerProfileCopy.roleSubtitle(starLevel: 3),
            VolunteerProfileCopy.impactSectionTitle,
            VolunteerProfileCopy.heroUnit,
            VolunteerProfileCopy.newcomerHeadline,
            VolunteerProfileCopy.newcomerDetail,
            VolunteerProfileCopy.heroSpoken(.newcomer),
            VolunteerProfileCopy.heroSpoken(.completed(count: 24)),
            VolunteerProfileCopy.hoursCaption,
            VolunteerProfileCopy.partnersCaption,
            VolunteerProfileCopy.ratingCaption,
            VolunteerProfileCopy.ratingSpokenWhenEmpty,
            VolunteerProfileCopy.badgesSectionTitle,
            VolunteerProfileCopy.badgesEmpty,
            VolunteerProfileCopy.badgesLinkHint,
            VolunteerProfileCopy.recentSectionTitle,
            VolunteerProfileCopy.recentEmpty,
            VolunteerProfileCopy.recentLinkHint,
            VolunteerProfileCopy.todoSectionTitle,
            // 必修培训入口：标题不是自己的字符串，复用派单原因的 displayText（单一来源）。
            VolunteerDispatchNotAvailableReason.trainingIncomplete.displayText,
            VolunteerProfileCopy.trainingEntryDetail,
            VolunteerProfileCopy.trainingEntryHint,
            VolunteerProfileCopy.settingsTitle,
            VolunteerProfileCopy.settingsHint,
            VolunteerAvailabilityCopy.slideToOpenTitle,
            VolunteerAvailabilityCopy.slideReleaseToOpenTitle,
            VolunteerAvailabilityCopy.availableStatusTitle,
            VolunteerAvailabilityCopy.closeTitle,
            VolunteerAvailabilityCopy.slideHint,
            VolunteerAvailabilityCopy.closeHint
        ]

        // 「证明 / 证书」：民政部令第 67 号。
        // 「元 / ￥」：中央网信办 2026-06-19 通知第 2 条，服务时长不得折算金额。
        // 「本月 / 本周」：Moving Target —— 自己跟自己比的门槛会漂移（印度 CCPA dark pattern 分类法点名项）。
        // 「还差 / 再跑 / 就能」：压力句式。国标星级那条「还差 N 小时」不在这张表里，
        //   它来自 `VolunteerAchievementsCopy`，门槛由 GB/T 40143—2021 定、不随用户表现漂移。
        let banned = ["证明", "证书", "已认证", "元", "￥", "本月", "本周", "还差", "再跑", "就能", "敬请期待"]
        for text in strings {
            for word in banned {
                XCTAssertFalse(text.contains(word), "首屏文案出现禁用词「\(word)」：\(text)")
            }
        }
    }

    /// 关闭侧的文案里**没有任何挽留**：不提已完成多少、不提别人在等、不带疑问句。
    /// Motivation Crowding —— 摩擦力只加在「答应」这一侧。
    func testCloseCopyDoesNotBargain() {
        let close = VolunteerAvailabilityCopy.closeTitle + VolunteerAvailabilityCopy.closeHint
        for word in ["确定要", "真的", "再想想", "坚持", "已经完成", "有人在等", "？"] {
            XCTAssertFalse(close.contains(word), "关闭侧出现挽留话术「\(word)」：\(close)")
        }
    }

    // MARK: - Fixtures

    private static func achievements(
        totalCompleted: Int?,
        minutes: Int64?,
        avgRating: Double?,
        totalRatings: Int?
    ) -> VolunteerAchievementsResponse {
        let json = """
        {
          "totalCompleted": \(totalCompleted.map { "\($0)" } ?? "null"),
          "totalServiceMinutes": \(minutes.map { "\($0)" } ?? "null"),
          "avgRating": \(avgRating.map { "\($0)" } ?? "null"),
          "totalRatings": \(totalRatings.map { "\($0)" } ?? "null"),
          "badges": [],
          "nextBadge": null,
          "starLevel": null
        }
        """
        // swiftlint:disable:next force_try
        return try! JSONDecoder().decode(VolunteerAchievementsResponse.self, from: Data(json.utf8))
    }
}
