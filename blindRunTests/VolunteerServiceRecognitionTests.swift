import XCTest
@testable import blindRun

/// 志愿者服务成就的分层规则。
///
/// 这一组用例守的是一条产品诚信约束：**页面上每个数字都要能追溯到后端字段**。
/// 此前志愿者首页显示的「积分」是 `totalCompleted * 100` —— 后端从来没有 `pointsBalance`
/// 字段（契约与 `src/` 里 `points` 零命中，核于 2026-08-13），那个数字只是「完成 N 单」
/// 换了个说法，却被命名成一种可累积、可兑换的东西，还配了一整页永远兑换不了的商城。
@MainActor
final class VolunteerServiceRecognitionTests: XCTestCase {

    // MARK: - 分层边界

    /// 边界值逐个钉。分档是纯算术，但错一档的后果是志愿者看到一个自己没达到的称号 ——
    /// 那比不显示更伤信任。
    func testTierBoundariesUnlockExactlyAtTheThreshold() {
        let expectations: [(completed: Int, unlockedCount: Int, currentName: String?)] = [
            (0, 0, nil),
            (1, 1, "首次陪跑"),
            (9, 1, "首次陪跑"),
            (10, 2, "熟练陪跑员"),
            (24, 2, "熟练陪跑员"),
            (25, 3, "资深陪跑员"),
            (49, 3, "资深陪跑员"),
            (50, 4, "金牌陪跑员"),
            (99, 4, "金牌陪跑员"),
            (100, 5, "荣誉陪跑员"),
            (101, 5, "荣誉陪跑员")
        ]

        for expected in expectations {
            let progress = VolunteerServiceRecognition.progress(completedCount: expected.completed)
            XCTAssertEqual(
                progress.filter(\.isUnlocked).count,
                expected.unlockedCount,
                "完成 \(expected.completed) 单时解锁档数不符"
            )
            XCTAssertEqual(
                VolunteerServiceRecognition.currentTier(completedCount: expected.completed)?.name,
                expected.currentName,
                "完成 \(expected.completed) 单时的当前称号不符"
            )
        }
    }

    /// 一单都没完成时全部未解锁，且第一档明确说「还差 1 单」——
    /// 新用户一眼看到全部层级，才知道路有多长（调研 §2 的「视觉差异承担留存作用」）。
    func testZeroCompletedShowsEveryTierLockedWithDistance() {
        let progress = VolunteerServiceRecognition.progress(completedCount: 0)

        XCTAssertEqual(progress.count, 5)
        XCTAssertTrue(progress.allSatisfy { !$0.isUnlocked })
        XCTAssertEqual(progress.first?.remaining, 1)
        XCTAssertEqual(progress.first?.statusText, "还差 1 单")
        XCTAssertEqual(VolunteerServiceRecognition.headlineText(completedCount: 0), "还没有完成的服务")
    }

    /// 已解锁的档位 `remaining` 必须是 0，不能是负数 —— 它会被念进 accessibility label。
    func testUnlockedTiersReportZeroRemaining() {
        for item in VolunteerServiceRecognition.progress(completedCount: 200) {
            XCTAssertTrue(item.isUnlocked)
            XCTAssertEqual(item.remaining, 0, "\(item.tier.name) 的 remaining 应为 0")
        }
    }

    /// 负数完成数按 0 处理，不崩也不产生负的 remaining。
    func testNegativeCompletedCountIsTreatedAsZero() {
        let progress = VolunteerServiceRecognition.progress(completedCount: -5)
        XCTAssertTrue(progress.allSatisfy { !$0.isUnlocked })
        XCTAssertTrue(progress.allSatisfy { $0.remaining > 0 })
    }

    func testNextTierRemainingIsNilAtTheTop() {
        XCTAssertEqual(VolunteerServiceRecognition.nextTierRemaining(completedCount: 0)?.remaining, 1)
        XCTAssertEqual(VolunteerServiceRecognition.nextTierRemaining(completedCount: 10)?.tier.name, "资深陪跑员")
        XCTAssertEqual(VolunteerServiceRecognition.nextTierRemaining(completedCount: 10)?.remaining, 15)
        XCTAssertNil(VolunteerServiceRecognition.nextTierRemaining(completedCount: 100))
    }

    // MARK: - 无障碍与文案

    /// 每一档必须能靠**名称和图标**区分，不能只靠颜色（WCAG 1.4.1）。
    /// 志愿者端同样有低视力用户。
    func testEveryTierIsDistinguishableWithoutColour() {
        let tiers = VolunteerServiceRecognition.tiers

        XCTAssertEqual(Set(tiers.map(\.name)).count, tiers.count, "档位名称不能重复")
        XCTAssertEqual(Set(tiers.map(\.symbolName)).count, tiers.count, "档位图标不能重复")
        XCTAssertEqual(Set(tiers.map(\.threshold)).count, tiers.count, "档位门槛不能重复")
        XCTAssertEqual(tiers.map(\.threshold), tiers.map(\.threshold).sorted(), "档位必须按门槛递增")
    }

    /// 未解锁的档位要说清还差几单，而不是只置灰 ——
    /// 置灰对读屏用户不存在，对低视力用户也只是「看不清的那个」。
    func testLockedTierLabelStatesHowManyRunsRemain() throws {
        let progress = VolunteerServiceRecognition.progress(completedCount: 57)
        let gold = try XCTUnwrap(progress.first { $0.tier.name == "金牌陪跑员" })
        let honour = try XCTUnwrap(progress.first { $0.tier.name == "荣誉陪跑员" })

        XCTAssertEqual(gold.accessibilityLabel, "金牌陪跑员，已解锁")
        XCTAssertEqual(honour.accessibilityLabel, "荣誉陪跑员，还差 43 单解锁")
    }

    /// 播报里**不许出现「积分」二字**：页面上每个数字都要能追溯到后端字段，
    /// 而后端没有积分。
    func testSummarySpeechNeverMentionsPoints() {
        for count in [0, 1, 10, 57, 100, 250] {
            let speech = VolunteerServiceRecognition.summarySpeech(completedCount: count)
            XCTAssertFalse(speech.contains("积分"), "完成 \(count) 单的播报出现了「积分」：\(speech)")
            XCTAssertFalse(speech.contains("兑换"), "完成 \(count) 单的播报出现了「兑换」：\(speech)")
        }
    }

    func testSummarySpeechTellsHowFarToTheNextTier() {
        XCTAssertTrue(VolunteerServiceRecognition.summarySpeech(completedCount: 10).contains("再完成 15 单"))
        XCTAssertTrue(VolunteerServiceRecognition.summarySpeech(completedCount: 100).contains("最高一档"))
        XCTAssertTrue(VolunteerServiceRecognition.summarySpeech(completedCount: 0).contains("还没有完成的服务"))
    }

    // MARK: - 不再合成后端没有的数字

    /// 后端不发 `pointsDelta` 时整行不显示，而不是编一个「+100」。
    ///
    /// 这一条是回归：`resolvedPointsDelta` 此前在 `nil` 时返回 100，于是每张完成的
    /// 订单卡都印着一个凭空生成的数。
    func testRecentOrderShowsNoPointsWhenBackendSendsNone() throws {
        let json = """
        {
          "orderId": 1,
          "status": "COMPLETED",
          "plannedStartTime": null,
          "completedAt": null,
          "startAddress": "测试地点",
          "blindName": "测试盲人",
          "rating": 5,
          "pointsDelta": null
        }
        """
        let order = try JSONDecoder().decode(
            VolunteerDispatchSummaryRecentOrder.self,
            from: Data(json.utf8)
        )

        XCTAssertNil(order.pointsDelta)
        XCTAssertNil(order.pointsText, "后端没发积分时不该显示任何积分文字")
    }

    /// 后端**真的**发了积分时如实显示 —— 字段保留就是为了这一天。
    func testRecentOrderShowsRealPointsWhenBackendSendsThem() throws {
        let json = """
        {
          "orderId": 2,
          "status": "COMPLETED",
          "plannedStartTime": null,
          "completedAt": null,
          "startAddress": "测试地点",
          "blindName": "测试盲人",
          "rating": 5,
          "pointsDelta": 30
        }
        """
        let order = try JSONDecoder().decode(
            VolunteerDispatchSummaryRecentOrder.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(order.pointsText, "+30")
    }

    /// 派单摘要里**没有** `pointsBalance` 字段了；后端若把它加回来，
    /// 多余的 JSON 键会被忽略，不影响解码 —— 但也不会被误当成积分显示出来。
    func testDispatchSummaryDecodesWithoutAnyPointsField() throws {
        let json = """
        {
          "totalCompleted": 7,
          "totalAccepted": 9,
          "acceptanceRate": 0.75,
          "pointsBalance": 700
        }
        """
        let summary = try JSONDecoder().decode(
            VolunteerDispatchSummaryResponse.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(summary.completedCount, 7)
        XCTAssertEqual(summary.acceptanceRateText, "75%")
        // 成就页用的是 completedCount，与那个被忽略的 700 无关。
        XCTAssertEqual(VolunteerServiceRecognition.currentTier(completedCount: summary.completedCount)?.name, "首次陪跑")
    }
}
