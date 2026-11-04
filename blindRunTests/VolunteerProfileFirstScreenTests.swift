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

    /// 🔴 **资质没通过时开不了，但接单中任何时候都必须能停。**
    ///
    /// 双向滑块改版前这是两个控件、两套闸：开启侧 `guard isEnabled, !isUpdating`，
    /// 关闭侧只有 `guard !isUpdating`。合并成一条轨道后两个方向共用同一批 `guard`，
    /// `isEnabled` 顺势把停止也堵上了 —— 而且是**三条路一起堵死**：拖拽 `onEnded`、
    /// 「停止接单」那个 `accessibilityAction` 所在按钮的 `.disabled`、以及 `close()` 自己。
    /// 表现是资质在接单期间被撤销后，志愿者三条路都停不下来。
    ///
    /// 🚩 **关键的那一行是 `isAvailable: true, isEnabled: false` ⇒ `true`。**
    /// 少了它，把实现写回对称的 `isEnabled && !isUpdating` 时本用例**照样全绿** ——
    /// 其余三组输入在两种实现下结果完全相同，分辨不出闸被悄悄加严。
    /// （已在 2026-09-17 实测验红：只有这一条断言会挂。）
    func testStoppingIsNeverGatedByApprovalButStartingAlwaysIs() {
        // 停止方向（接单中）：资质没通过也必须放行。
        XCTAssertTrue(
            VolunteerAvailabilitySlide.acceptsGesture(isAvailable: true, isEnabled: false, isUpdating: false),
            "资质被撤销后停不了接单 —— 人被锁在一个他已经不该待的状态里"
        )
        // 开始方向（未接单）：资质没通过一律不准开。
        XCTAssertFalse(
            VolunteerAvailabilitySlide.acceptsGesture(isAvailable: false, isEnabled: false, isUpdating: false),
            "资质没通过却能开始接单"
        )
        XCTAssertTrue(
            VolunteerAvailabilitySlide.acceptsGesture(isAvailable: false, isEnabled: true, isUpdating: false)
        )
        // 请求在途时两个方向都停手，否则会连发两次 setAvailability。
        for isAvailable in [true, false] {
            XCTAssertFalse(
                VolunteerAvailabilitySlide.acceptsGesture(
                    isAvailable: isAvailable, isEnabled: true, isUpdating: true
                ),
                "isAvailable=\(isAvailable) 时请求在途仍接受手势"
            )
        }
    }

    // MARK: - 主指标

    /// 🔴 新人不显示「0 次陪跑」——一屏上最大最粗的那个数字是 0，那是负激励。
    func testNewcomerNeverShowsAZeroHeroNumber() {
        XCTAssertEqual(VolunteerProfileHeadline.resolve(totalCompleted: 0, totalServiceMinutes: nil), .newcomer)
        XCTAssertEqual(VolunteerProfileHeadline.resolve(totalCompleted: nil, totalServiceMinutes: nil), .newcomer)
        XCTAssertEqual(VolunteerProfileHeadline.resolve(totalCompleted: -3, totalServiceMinutes: nil), .newcomer, "负数是脏数据，同样不该上屏")
        XCTAssertEqual(VolunteerProfileHeadline.resolve(totalCompleted: 1, totalServiceMinutes: nil), .completed(count: 1, minutes: nil))

        let spoken = VolunteerProfileCopy.heroSpoken(.newcomer)
        XCTAssertFalse(spoken.contains("0"), "新人播报里出现了 0：\(spoken)")
        XCTAssertTrue(spoken.contains(VolunteerAvailabilityCopy.toggleTitle), "新人那句话要说清下一步在哪：\(spoken)")
    }

    /// 新人态下 3 列统计与星级进度整块不画 —— 那三个数此刻全是 0 / `--` / 0 小时，
    /// 摆出来的信息是「你离得很远」。
    func testNewcomerHidesTheImpactGridAndStarProgress() {
        XCTAssertFalse(VolunteerProfileHeadline.newcomer.showsImpactSections)
        XCTAssertTrue(VolunteerProfileHeadline.completed(count: 1, minutes: nil).showsImpactSections)
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
        XCTAssertEqual(VolunteerProfileHeadline.resolve(totalCompleted: realNewcomer.totalCompleted, totalServiceMinutes: realNewcomer.totalServiceMinutes), .newcomer)

        // 老志愿者：同样读到了，数字非 0。
        let veteran = Self.achievements(
            totalCompleted: 200, minutes: 60_000, avgRating: 4.9, totalRatings: 180
        )
        XCTAssertEqual(
            VolunteerProfileHeadline.resolve(totalCompleted: veteran.totalCompleted, totalServiceMinutes: veteran.totalServiceMinutes),
            .completed(count: 200, minutes: 60_000)
        )

        // 🚩 这一条是本用例的重点：**光看 `summary` 非空分不出上面两种人**。
        // 视图如果按 `summary != nil` 判，`achievementsFailed` 这一档就会走进
        // `impactContent`，然后 `resolve(totalCompleted: nil, totalServiceMinutes: nil)` 把它变成新人。
        XCTAssertEqual(
            VolunteerProfileHeadline.resolve(totalCompleted: nil, totalServiceMinutes: nil),
            .newcomer,
            "nil 落进 .newcomer 是 resolve 的既有行为 —— 正因如此，调用方必须先保证 achievements 非空"
        )
    }

    // MARK: - 主指标：陪伴时长（2026-10-03 替代 #269 的公里）

    /// #351：不再按整小时向下取整。4 分钟就是 4 分钟（旧实现回落到次数），119 分钟是「1 小时 59 分钟」（旧实现是「1 小时」）。
    func testHeroKeepsTheMinutesInsteadOfFlooringToWholeHours() {
        XCTAssertEqual(
            VolunteerProfileHeadline.resolve(totalCompleted: 1, totalServiceMinutes: 4),
            .completed(count: 1, minutes: 4)
        )
        XCTAssertEqual(
            VolunteerProfileHeadline.resolve(totalCompleted: 16, totalServiceMinutes: 119),
            .completed(count: 16, minutes: 119)
        )
        XCTAssertEqual(VolunteerProfileCopy.heroDurationParts(4).map(\.value), ["4"])
        XCTAssertEqual(VolunteerProfileCopy.heroDurationParts(4).map(\.unit), ["分钟"])
        XCTAssertEqual(VolunteerProfileCopy.heroDurationParts(119).map(\.value), ["1", "59"])
        XCTAssertEqual(VolunteerProfileCopy.heroDurationParts(120).map(\.unit), ["小时"], "整点只写小时")
    }

    /// 🔴 时长为 0 / 缺字段 / 脏数据才回落到次数，**不显示「0 分钟」/「0 小时」**。
    func testHeroFallsBackToRunCountOnlyWhenThereIsNoServiceTime() {
        for minutes: Int64? in [nil, 0, -600] {
            XCTAssertEqual(
                VolunteerProfileHeadline.resolve(totalCompleted: 24, totalServiceMinutes: minutes),
                .completed(count: 24, minutes: nil),
                "minutes=\(String(describing: minutes)) 时不该有时长"
            )
        }
    }

    /// 新人态只看完成次数：时长再大也不能把新人变成老志愿者。
    func testNewcomerIgnoresServiceMinutes() {
        XCTAssertEqual(
            VolunteerProfileHeadline.resolve(totalCompleted: 0, totalServiceMinutes: 6_000),
            .newcomer
        )
    }

    func testHeroSpokenNamesHoursAndKeepsTheRunCount() {
        XCTAssertEqual(
            VolunteerProfileCopy.heroSpoken(.completed(count: 16, minutes: 185)),
            "我的陪伴。累计陪伴 3 小时 5 分钟，共 16 次陪跑。"
        )
        XCTAssertEqual(
            VolunteerProfileCopy.heroSpoken(.completed(count: 1, minutes: 4)),
            "我的陪伴。累计陪伴 4 分钟，共 1 次陪跑。"
        )
        // 时长为 0 时与改动前逐字相同。
        XCTAssertEqual(
            VolunteerProfileCopy.heroSpoken(.completed(count: 24, minutes: nil)),
            "我的陪伴。已完成 24 次陪跑。"
        )
    }

    /// 解码回归：有值 / 字段缺失。缺字段时整条响应仍要解出来，其余字段不受影响。
    func testAchievementsDecodeDistanceWhenPresentAndTolerateItWhenMissing() {
        let present = Self.achievements(
            totalCompleted: 24, minutes: 1_440, avgRating: 4.9, totalRatings: 10, distanceMeters: 128_400
        )
        XCTAssertEqual(present.totalDistanceMeters, 128_400)

        let missing = Self.achievements(
            totalCompleted: 24, minutes: 1_440, avgRating: 4.9, totalRatings: 10
        )
        XCTAssertNil(missing.totalDistanceMeters)
        XCTAssertEqual(missing.totalCompleted, 24, "少一个字段不该拖垮其余字段")
    }

    // MARK: - 三列统计

    /// 🔴 0 位固定搭档不上屏（同 `VolunteerHomeIncentiveSummary.hero` 的判据）。
    func testZeroPartnersShowsAPlaceholderInsteadOfZero() {
        let none = VolunteerProfileStats.partners(0)
        XCTAssertEqual(none.value, "--")
        XCTAssertNil(none.unit, "「-- 位」读起来像缺数据")
        XCTAssertFalse(none.spoken.contains("0"), none.spoken)
        XCTAssertFalse(none.spoken.contains("-"), none.spoken)
        XCTAssertEqual(VolunteerProfileStats.partners(-2).value, "--", "负数是脏数据")
        XCTAssertEqual(VolunteerProfileStats.partners(1).value, "1")
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
        XCTAssertEqual(VolunteerProfileBadgeRow.nextBadgeCaption(hours), .init(title: "十小时陪伴", detail: "3/10"))

        let runs = VolunteerNextBadgeDto(code: "RUNS_10", name: "夜跑守护", current: 3, target: 5)
        XCTAssertEqual(VolunteerProfileBadgeRow.nextBadgeCaption(runs), .init(title: "夜跑守护", detail: "3/5"))

        // 未知 code 拿不到量词 ⇒ 只给名字，不拼一个猜的分母。
        let unknown = VolunteerNextBadgeDto(code: "MOONWALK", name: "月球漫步", current: 1, target: 9)
        XCTAssertEqual(VolunteerProfileBadgeRow.nextBadgeCaption(unknown), .init(title: "月球漫步", detail: nil))

        for caption in [VolunteerProfileBadgeRow.nextBadgeCaption(hours), VolunteerProfileBadgeRow.nextBadgeCaption(runs)] {
            XCTAssertFalse("\(caption.title)\(caption.detail ?? "")".contains("解锁"), "徽章进度不得承诺解锁：\(caption)")
        }
    }

    /// 后端名字「陪跑达人 · 10 次」拆成两行：上名字、下「10 次」；带进度时下行是进度。
    /// 2026-10-03 试用反馈：挤在一行时窄格把它断成「陪跑达人 ·」「10 次」。
    func testBadgeCaptionSplitsTheQualifierOntoItsOwnLine() {
        XCTAssertEqual(
            VolunteerProfileBadgeRow.caption(name: "陪跑达人 · 10 次"),
            .init(title: "陪跑达人", detail: "10 次")
        )
        let next = VolunteerNextBadgeDto(code: "RUNS_50", name: "陪跑达人 · 50 次", current: 16, target: 50)
        XCTAssertEqual(
            VolunteerProfileBadgeRow.nextBadgeCaption(next),
            .init(title: "陪跑达人", detail: "16/50")
        )
        XCTAssertEqual(VolunteerProfileBadgeRow.caption(name: "首次陪跑"), .init(title: "首次陪跑", detail: nil))
    }

    // MARK: - 星级卡

    /// 还没到一星时标题直接说还差多少，进度行不重复「还差」；到了一星以后与成就页同一套文案。
    func testStarCardTitleSaysHowFarToTheFirstStar() {
        let none = VolunteerStarLevel.derive(totalServiceMinutes: 239)
        XCTAssertEqual(VolunteerProfileCopy.starCardTitle(none), "距离一星还差 97 小时")
        XCTAssertEqual(VolunteerProfileCopy.starCardProgress(none), "已累计 3 / 100 小时")

        let oneStar = VolunteerStarLevel.derive(totalServiceMinutes: 120 * 60)
        XCTAssertEqual(VolunteerProfileCopy.starCardTitle(oneStar), VolunteerAchievementsCopy.starTitle(current: 1))
        XCTAssertEqual(VolunteerProfileCopy.starCardProgress(oneStar), VolunteerAchievementsCopy.starProgressText(oneStar))

        // 读屏念的必须和屏幕一致，不能再是成就页那句「尚未达到一星」。
        let spoken = VolunteerProfileCopy.starCardAccessibilityLabel(none)
        XCTAssertEqual(spoken, "国标星级，距离一星还差 97 小时，已累计 3 小时。")
        XCTAssertEqual(
            VolunteerProfileCopy.starCardAccessibilityLabel(oneStar),
            VolunteerAchievementsCopy.starAccessibilityLabel(oneStar)
        )
        for text in [VolunteerProfileCopy.starCardTitle(none), spoken] {
            for word in ["证明", "证书", "已认证", "尚未"] {
                XCTAssertFalse(text.contains(word), "「\(text)」含「\(word)」")
            }
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

    // MARK: - 文案红线

    /// 🔴 民政部令第 67 号：这一屏是展示不是凭据，**不得出现「证明 / 证书 / 已认证」**。
    /// 守卫规则 `volunteer-hours-credential` 扫源码，这条扫的是运行时真正拼出来的串。
    ///
    /// 同时挡住激励层的三条红线：不折算金额、不做月度目标、不催促下一单。
    func testFirstScreenCopyNeverClaimsCredentialsOrPushesForMoreRuns() {
        let strings = [
            VolunteerProfileCopy.pageTitle,
            VolunteerProfileCopy.impactSectionTitle,
            VolunteerProfileCopy.heroUnit,
            VolunteerProfileCopy.newcomerHeadline,
            VolunteerProfileCopy.newcomerDetail,
            VolunteerProfileCopy.heroSpoken(.newcomer),
            VolunteerProfileCopy.heroSpoken(.completed(count: 24, minutes: nil)),
            VolunteerProfileCopy.heroSpoken(.completed(count: 24, minutes: 725)),
            // 星级卡标题「距离一星还差 N 小时」刻意不进这张表：门槛是国标定的固定值，
            // 「还差」在这里不是压力句式（同下面那条注释）。它的红线在 `testStarCardTitleSaysHowFarToTheFirstStar`。
            VolunteerProfileCopy.starCardProgress(VolunteerStarLevel.derive(totalServiceMinutes: 180)),
            VolunteerProfileCopy.partnersSpokenWhenEmpty,
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
            VolunteerProfileCopy.settingsTitle,
            VolunteerProfileCopy.settingsHint,
            VolunteerAvailabilityCopy.slideToOpenTitle,
            VolunteerAvailabilityCopy.slideReleaseToOpenTitle,
            VolunteerAvailabilityCopy.availableStatusTitle,
            VolunteerAvailabilityCopy.closeTitle,
            VolunteerAvailabilityCopy.slideHint,
            VolunteerAvailabilityCopy.closeHint,
            // 接单主页那一屏。首页 v3（#694）新增的文案在 `VolunteerHomeSummaryCardsTests` 里过同一张禁用词表。
            VolunteerAvailabilityCopy.enterHubTitle,
            VolunteerAvailabilityCopy.enterHubHint,
            VolunteerDispatchHubCopy.acceptingPill,
            VolunteerDispatchHubCopy.emptyTitle,
            VolunteerDispatchHubCopy.emptySubtitle,
            VolunteerDispatchHubCopy.scheduleRowLabel,
            VolunteerDispatchHubCopy.scheduleRowEmptyValue,
            VolunteerDispatchHubCopy.pauseTitle,
            VolunteerDispatchHubCopy.pauseConfirmMessage,
            VolunteerDispatchHubCopy.pauseConfirmPrimary,
            VolunteerDispatchHubCopy.introCallCardTitle,
            VolunteerDispatchHubCopy.introCallCardSubtitle,
            VolunteerDispatchHubCopy.laterRowTitle(2)
        ]

        // 「证明 / 证书」：民政部令第 67 号。
        // 「元 / ￥」：中央网信办 2026-06-19 通知第 2 条，服务时长不得折算金额。
        // 「本月 / 本周」：Moving Target —— 自己跟自己比的门槛会漂移（印度 CCPA dark pattern 分类法点名项）。
        // 「还差 / 再跑 / 就能」：压力句式。国标星级那条「还差 N 小时」不在这张表里，
        //   它来自 `VolunteerAchievementsCopy`，门槛由 GB/T 40143—2021 定、不随用户表现漂移。
        for text in strings {
            for word in Self.bannedCopyWords {
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

    /// 首页与接单页文案的禁用词。理由逐条写在 `testFirstScreenCopyNeverClaimsCredentialsOrPushesForMoreRuns` 里。
    static let bannedCopyWords = ["证明", "证书", "已认证", "元", "￥", "本月", "本周", "还差", "再跑", "就能", "敬请期待"]

    // MARK: - Fixtures

    /// 只填闸门用得到的两个字段，其余走解码的默认 null —— 手写 24 个 `nil` 会让
    /// 下次后端加字段时这里跟着改一遍，而它们与本用例无关。
    static func summary(
        reasons: [VolunteerDispatchNotAvailableReason]
    ) -> VolunteerDispatchSummaryResponse {
        let list = reasons.map { "\"\($0.rawValue)\"" }.joined(separator: ", ")
        let json = """
        { "canDispatch": \(reasons.isEmpty), "notAvailableReasons": [\(list)] }
        """
        // swiftlint:disable:next force_try
        return try! JSONDecoder().decode(VolunteerDispatchSummaryResponse.self, from: Data(json.utf8))
    }

    private static func achievements(
        totalCompleted: Int?,
        minutes: Int64?,
        avgRating: Double?,
        totalRatings: Int?,
        distanceMeters: Int64? = nil
    ) -> VolunteerAchievementsResponse {
        // 不传 = 整个键都不出现（模拟后端没发这个字段），不是 `null`。
        let distance = distanceMeters.map { "\"totalDistanceMeters\": \($0)," } ?? ""
        let json = """
        {
          "totalCompleted": \(totalCompleted.map { "\($0)" } ?? "null"),
          "totalServiceMinutes": \(minutes.map { "\($0)" } ?? "null"),
          \(distance)
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
