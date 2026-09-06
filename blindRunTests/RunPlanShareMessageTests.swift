import XCTest
@testable import blindRun

/// 「把这次行程告诉家人」——出发前把行程要素交给系统短信。
///
/// 这些用例钉的是三件事：**该给的状态给了、不该给的没给**；**终点为空时一个字都不提终点**；
/// **文案不宣称送达**。第三条与 `AGENTS.md` §6 的 SOS 文案红线同源：
/// `MFMessageComposeViewController` 的 `.sent` 不保证消息到达收件人，用户还能改收件人和正文。
@MainActor
final class RunPlanShareMessageTests: XCTestCase {

    // MARK: - 状态门控

    /// 穷举所有状态。用 `allCases` 而不是逐个写：后端加状态时这条会连同编译器一起提醒。
    ///
    /// 非终态全给，与后端 `POST /share` 一致；终态隐藏（后端对终态返 409
    /// `SHARE_ORDER_ALREADY_FINISHED`，摆一个必然报错的按钮对读屏用户是纯噪音）。
    func testShareIsOfferedOnlyWhenThereIsAnActualRunToDescribe() {
        // `.pendingIntroCall` 在列：它是非终态，后端 `POST /share` 照常受理。
        // 通话没聊成也不影响家属那条链接 —— 链接是幂等的，行程要素本身没变。
        // `.scheduledConfirmed` 在列：非终态，后端 `POST /share` 照常受理。
        // 而且跨天单恰恰是最该提前告诉家人的一种 —— 那是一件几天后要发生的事。
        let allowed: Set<RunOrderStatus> = [
            .pendingMatch, .pendingIntroCall, .scheduledConfirmed, .pendingAccept,
            .driverEnRoute, .driverArrived, .inProgress, .rematching
        ]

        for status in RunOrderStatus.allCases {
            let shouldOffer = allowed.contains(status)
            XCTAssertEqual(
                status.offersRunPlanShare,
                shouldOffer,
                "状态 \(status.rawValue) 的行程告知开关与预期不符"
            )
            XCTAssertEqual(
                RunPlanShareMessage.compose(order: Self.makeOrder(status: status)) != nil,
                shouldOffer,
                "状态 \(status.rawValue) 的正文生成与状态门控不一致"
            )
        }
    }

    /// 终态单独钉一条：这三个状态下后端会返 409 `SHARE_ORDER_ALREADY_FINISHED`，
    /// 客户端要**隐藏**入口而不是禁用后报错。
    func testTerminalStatusesHideTheEntryInsteadOfFailingLater() {
        for status in [RunOrderStatus.completed, .cancelled, .noVolunteer] {
            XCTAssertFalse(status.offersRunPlanShare, "终态 \(status.rawValue) 不该给分享入口")
            XCTAssertNil(RunPlanShareMessage.compose(order: Self.makeOrder(status: status)))
        }
    }

    /// F12：入口是隐藏了，但**按下与处理之间那一瞬**订单可能刚被 5 秒轮询推到终态。
    /// `shareRunPlanBySMS` 的第三道 guard 命中的就是这一瞬，此前它静默 `return` ——
    /// 对盲人端「点了没反应」就是事故。这条钉住兜底文案：说清行程已结束，
    /// 而不是泛泛地说失败（用户下一步不该是重试）。
    func testTerminalRaceHasSomethingToSayInsteadOfReturningSilently() {
        XCTAssertFalse(RunPlanShareCopy.notShareable.isEmpty)
        XCTAssertTrue(RunPlanShareCopy.notShareable.contains("已经结束"))
        XCTAssertNotEqual(RunPlanShareCopy.notShareable, RunPlanShareCopy.failed)
        XCTAssertFalse(
            RunPlanShareCopy.notShareable.contains("重试"),
            "终态不是可重试的失败，不该把人引向重试"
        )
    }

    /// `PENDING_MATCH` 给 —— 与后端口径一致（家属看到「正在找志愿者」也是有意义的）。
    /// 订单若被自动取消，家属看到的是 `410`（曾经有效但已结束），不是一条无限期的坏链接。
    func testPendingMatchIsShareableSoFamilyKnowsTheRunIsBeingArranged() throws {
        let body = try XCTUnwrap(RunPlanShareMessage.compose(order: Self.makeOrder(status: .pendingMatch)))
        XCTAssertTrue(body.contains("订单号：7001"))
    }

    // MARK: - 正文内容

    func testMessageCarriesTheLogisticsAFamilyMemberNeeds() throws {
        let body = try XCTUnwrap(RunPlanShareMessage.compose(order: Self.makeOrder(
            status: .inProgress,
            endAddress: "城东体育场北门"
        )))

        XCTAssertTrue(body.contains("出发时间："), "缺出发时间")
        XCTAssertTrue(body.contains("出发地点：测试出发点"), "缺出发地点")
        XCTAssertTrue(body.contains("结束地点：城东体育场北门"), "缺结束地点")
        XCTAssertTrue(body.contains("预计结束："), "缺预计结束时间")
        XCTAssertTrue(body.contains("订单号：7001"), "缺订单号")
    }

    /// **终点为空时一个字都不提终点。** `endAddress == nil` 的语义是「用户没说终点」，
    /// 不是「原路返回起点」——摆出来家属就会去等一个盲人从没说过的地点。
    /// 这条与 `OrderDetailResponse.endAddressForDisplay` 的注释、后端
    /// `websocket-protocol.md:429` 是同一条口径。
    func testAbsentDestinationIsNeverMentionedAtAll() throws {
        let body = try XCTUnwrap(RunPlanShareMessage.compose(order: Self.makeOrder(
            status: .inProgress,
            endAddress: nil
        )))

        for word in ["结束地点", "终点", "返回"] {
            XCTAssertFalse(body.contains(word), "终点为空时正文不该出现「\(word)」")
        }
        // 其余要素照常在，不能因为没终点就整条不发。
        XCTAssertTrue(body.contains("出发地点：测试出发点"))
    }

    /// 单个要素缺失只省略该项，不整条崩 —— 后端这几个字段都是可空的。
    func testMissingFieldsDegradeItemByItemInsteadOfFailing() throws {
        let body = try XCTUnwrap(RunPlanShareMessage.compose(order: Self.makeOrder(
            status: .driverArrived,
            startAddress: nil,
            plannedStart: nil,
            plannedEnd: nil
        )))

        XCTAssertFalse(body.contains("出发时间："))
        XCTAssertFalse(body.contains("出发地点："))
        XCTAssertFalse(body.contains("预计结束："))
        // 订单号是必有字段，它保证正文永远不会退化成空串。
        XCTAssertTrue(body.contains("订单号：7001"))
        XCTAssertFalse(body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    /// 发给第三方的短信里不许出现参与者的联系方式与健康信息。
    ///
    /// 志愿者手机号尤其要盯住：志愿者没有同意把号码给盲人的家属，而隐私号至今未开通。
    func testMessageLeaksNoContactDetailsOrHealthInformation() throws {
        let body = try XCTUnwrap(RunPlanShareMessage.compose(order: Self.makeOrder(
            status: .inProgress,
            endAddress: "城东体育场北门"
        )))

        XCTAssertFalse(body.contains("13800000000"), "泄露了志愿者手机号")
        XCTAssertFalse(body.contains("13900000000"), "泄露了盲人手机号")
        XCTAssertFalse(body.contains("膝盖旧伤"), "泄露了特殊说明")
        XCTAssertFalse(body.contains("TOTAL_BLIND"), "泄露了视力等级")
    }

    // MARK: - 文案红线

    /// `.sent` 只代表用户在系统界面里点了发送，**不代表收件人收到了**；用户还可以
    /// 改掉收件人和正文。任何一句宣称送达的文案都是假的。
    func testCopyNeverClaimsTheContactWasReached() {
        let everyUserFacingString = [
            RunPlanShareCopy.buttonTitle,
            RunPlanShareCopy.accessibilityHint,
            RunPlanShareCopy.sent,
            RunPlanShareCopy.cancelled,
            RunPlanShareCopy.failed,
            RunPlanShareCopy.unavailable,
            RunPlanShareCopy.noContact,
            RunPlanShareCopy.disclaimer
        ]
        let forbidden = ["已通知", "已收到", "已送达", "已知悉", "已经收到", "通知成功"]

        for text in everyUserFacingString {
            for word in forbidden {
                XCTAssertFalse(text.contains(word), "文案「\(text)」出现了完成时态措辞「\(word)」")
            }
        }
    }

    /// 成功那句必须把「还要你自己点发送」这件事说出来 —— 盲人看不到 sheet 收起，
    /// 也看不到短信到底躺在草稿里还是发出去了。
    func testSentCopyPointsTheUserBackToTheMessagesApp() {
        XCTAssertTrue(RunPlanShareCopy.sent.contains("短信"))
        XCTAssertTrue(RunPlanShareCopy.sent.contains("确认"))
        XCTAssertTrue(RunPlanShareCopy.accessibilityHint.contains("自己点发送"))
    }

    /// 正文最后那句要让家属知道这是一次性告知，不是持续监控 ——
    /// 否则「我收到过一条短信」会被误当成「我一直看得到他在哪」。
    func testMessageTellsTheContactTheAppWillNotKeepThemUpdated() throws {
        let body = try XCTUnwrap(RunPlanShareMessage.compose(order: Self.makeOrder(status: .inProgress)))
        XCTAssertTrue(body.contains(RunPlanShareCopy.disclaimer))
        XCTAssertTrue(RunPlanShareCopy.disclaimer.contains("不会自动通知"))
    }

    // MARK: - Fixtures

    private static func makeOrder(
        status: RunOrderStatus,
        startAddress: String? = "测试出发点",
        endAddress: String? = nil,
        plannedStart: String? = "2026-08-13T15:30:00",
        plannedEnd: String? = "2026-08-13T16:30:00"
    ) -> OrderDetailResponse {
        OrderDetailResponse(
            orderId: 7_001,
            status: status,
            startAddress: startAddress,
            startLatitude: 39.9,
            startLongitude: 116.4,
            endAddress: endAddress,
            endLatitude: nil,
            endLongitude: nil,
            plannedStart: plannedStart,
            plannedEnd: plannedEnd,
            blindName: "测试盲人",
            blindPhone: "13900000000",
            volunteerPhone: "13800000000",
            acceptedAt: nil,
            createdAt: nil,
            expectedDurationMinutes: 60,
            pacePreference: nil,
            routePreference: nil,
            routeNotes: nil,
            hasGuideDogThisRun: nil,
            specialNotes: "膝盖旧伤",
            visionLevel: "TOTAL_BLIND",
            tetherPreference: nil,
            chatPreference: nil
        )
    }
}
