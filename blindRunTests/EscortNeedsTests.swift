import XCTest
@testable import blindRun

/// 志愿者侧「本单为视障跑者」提示位的内容判定（`OrderDetailResponse.escortNeeds`）。
///
/// 这块的价值全在**逐字段的可见性**上，所以断言都打在「哪一行在、哪一行不在」：
/// - 导盲犬不走接单闸（契约里本来就下发给未接单志愿者）
/// - 视力情况 / 引导方式走闸（`AGENTS.md §8` 的敏感健康信息）
/// - 认不出的取值不许静默丢掉，也不许把 rawValue 念出来
final class EscortNeedsTests: XCTestCase {

    // MARK: - 接单后：三项齐全

    func testShowsVisionTetherAndGuideDogAfterAccept() {
        let needs = makeOrder(
            status: .inProgress,
            visionLevel: "TOTAL_BLIND",
            tetherPreference: "TETHER_ROPE",
            hasGuideDog: true
        ).escortNeeds

        XCTAssertEqual(needs.map(\.kind), [.guideDog, .vision, .tether])
        XCTAssertEqual(needs.first { $0.kind == .vision }?.value, "全盲")
        XCTAssertEqual(needs.first { $0.kind == .tether }?.value, "牵引绳")
        XCTAssertTrue(needs.contains { $0.value.contains("本次携带") })
    }

    /// 引导方式是这块唯一会改变志愿者身体动作的一行，三个取值都要能落到中文。
    func testEveryTetherPreferenceResolvesToACopyAVolunteerCanActOn() {
        let expected: [String: String] = [
            "TETHER_ROPE": "牵引绳",
            "ARM_HOLD": "搀扶",
            "VERBAL_ONLY": "仅语言引导"
        ]
        for (raw, copy) in expected {
            let order = makeOrder(status: .driverArrived, tetherPreference: raw)
            XCTAssertEqual(
                order.escortNeeds.first { $0.kind == .tether }?.value,
                copy,
                "\(raw) 没落到可执行的中文"
            )
        }
    }

    // MARK: - 接单前：健康信息必须关着

    /// `PENDING_MATCH` 是派单弹窗那一刻的状态 —— 视力情况与引导方式一律不给。
    func testHidesHealthFieldsBeforeAccept() {
        let needs = makeOrder(
            status: .pendingMatch,
            visionLevel: "LOW_VISION",
            tetherPreference: "ARM_HOLD",
            hasGuideDog: true
        ).escortNeeds

        XCTAssertEqual(needs.map(\.kind), [.guideDog], "接单前只该剩导盲犬")
        XCTAssertFalse(needs.contains { $0.value.contains("低视力") })
        XCTAssertFalse(needs.contains { $0.value.contains("搀扶") })
    }

    /// `REMATCHING` 是原志愿者取消后回到重新派单 —— 那个人**已经不是参与者了**，
    /// 简写成 `!= .pendingMatch` 会把他判成可见。
    func testHidesHealthFieldsAfterTheVolunteerDroppedOut() {
        let needs = makeOrder(
            status: .rematching,
            visionLevel: "TOTAL_BLIND",
            tetherPreference: "TETHER_ROPE"
        ).escortNeeds

        XCTAssertTrue(needs.isEmpty, "重新匹配中不该向已退出的志愿者展示任何陪跑要求")
    }

    /// 后端新增状态时隐私边界必须**默认关**。
    func testHidesHealthFieldsForAnUnknownStatus() {
        let needs = makeOrder(
            status: .unknown,
            visionLevel: "TOTAL_BLIND",
            tetherPreference: "TETHER_ROPE"
        ).escortNeeds

        XCTAssertTrue(needs.isEmpty)
    }

    /// 导盲犬**不**走那道闸：它在 `AvailableOrderResponse` / `WSNewOrder` 里本来就下发给
    /// 还没接单的志愿者。误把它一起关掉会让志愿者盲接、到场才发现带不了狗。
    func testGuideDogStaysVisibleBeforeAccept() {
        let needs = makeOrder(status: .pendingMatch, hasGuideDog: true).escortNeeds
        XCTAssertEqual(needs.map(\.kind), [.guideDog])
    }

    func testGuideDogRowIsAbsentWhenNotBroughtAlong() {
        for value in [false, nil] as [Bool?] {
            let needs = makeOrder(status: .pendingMatch, hasGuideDog: value).escortNeeds
            XCTAssertTrue(needs.isEmpty, "hasGuideDogThisRun=\(String(describing: value)) 不该渲染导盲犬行")
        }
    }

    // MARK: - 认不出的取值

    /// 后端加一个 `TetherPreference` 取值时：不许念 rawValue（内部标识符），
    /// 也**不许静默丢掉这一行** —— 丢掉等于告诉志愿者「跑者没有偏好」，
    /// 而真实情况是「填了，只是这版 App 不认识」，抓错方式对盲人是身体风险。
    func testUnknownRawValueFallsBackToConfirmInPersonInsteadOfDisappearing() {
        let needs = makeOrder(
            status: .inProgress,
            visionLevel: "SOME_NEW_LEVEL",
            tetherPreference: "SOME_NEW_TETHER"
        ).escortNeeds

        XCTAssertEqual(needs.first { $0.kind == .vision }?.value, EscortNeed.confirmInPerson)
        XCTAssertEqual(needs.first { $0.kind == .tether }?.value, EscortNeed.confirmInPerson)
        XCTAssertFalse(
            needs.contains { $0.value.contains("SOME_NEW") },
            "内部标识符不能出现在志愿者看到的文案里"
        )
    }

    // MARK: - 档案不全

    /// 两项都没填 ≠ 没有要求。空白会让志愿者自己猜一种带法，所以要明确让他去问。
    func testMissingProfileAsksTheVolunteerToConfirmInsteadOfShowingNothing() {
        let needs = makeOrder(status: .pendingAccept).escortNeeds

        XCTAssertEqual(needs.map(\.kind), [.unstated])
        XCTAssertTrue(needs[0].value.contains("当面"))
    }

    /// 空字符串与 null 同等对待（后端档案缺失时两种都出现过）。
    func testBlankStringsAreTreatedAsUnstated() {
        let needs = makeOrder(status: .pendingAccept, visionLevel: "  ", tetherPreference: "").escortNeeds
        XCTAssertEqual(needs.map(\.kind), [.unstated])
    }

    /// 只填了其中一项时不再追加「没填」那一行 —— 已经有可执行信息了。
    func testNoUnstatedRowWhenAtLeastOneFieldIsPresent() {
        let needs = makeOrder(status: .pendingAccept, visionLevel: "LOW_VISION").escortNeeds
        XCTAssertEqual(needs.map(\.kind), [.vision])
    }

    // MARK: - 读屏

    /// 整块合成一个焦点，朗读文本写死。逐行分开会让读屏用户滑过其中一条而不自知，
    /// 而这几行的意义恰恰是「一条都不能漏」。
    func testAnnouncementCarriesEveryVisibleRow() {
        let announcement = makeOrder(
            status: .inProgress,
            visionLevel: "TOTAL_BLIND",
            tetherPreference: "ARM_HOLD",
            hasGuideDog: true
        ).escortNeedsAnnouncement

        XCTAssertTrue(announcement.hasPrefix("本单为视障跑者"))
        XCTAssertTrue(announcement.contains("全盲"))
        XCTAssertTrue(announcement.contains("搀扶"))
        XCTAssertTrue(announcement.contains("本次携带"))
    }

    // MARK: - Helpers

    private func makeOrder(
        status: RunOrderStatus,
        visionLevel: String? = nil,
        tetherPreference: String? = nil,
        hasGuideDog: Bool? = nil
    ) -> OrderDetailResponse {
        OrderDetailResponse(
            orderId: 1,
            status: status,
            startAddress: "朝阳公园南门",
            startLatitude: 39.9342,
            startLongitude: 116.4740,
            endAddress: nil,
            endLatitude: nil,
            endLongitude: nil,
            plannedStart: "2026-08-13T09:00:00",
            plannedEnd: nil,
            blindName: "李*",
            blindPhone: nil,
            volunteerPhone: nil,
            acceptedAt: nil,
            createdAt: "2026-08-13T08:00:00",
            expectedDurationMinutes: 60,
            pacePreference: .moderate,
            routePreference: .parkTrail,
            routeNotes: nil,
            hasGuideDogThisRun: hasGuideDog,
            specialNotes: nil,
            visionLevel: visionLevel,
            tetherPreference: tetherPreference,
            chatPreference: nil
        )
    }
}
