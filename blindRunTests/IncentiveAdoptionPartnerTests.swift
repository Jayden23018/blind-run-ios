import XCTest
@testable import blindRun

/// SPEC-E 固定搭档：取消收藏 / 退出的二次确认、空态文案、收藏端点与订单详情上的收藏入口。
///
/// 从 `IncentiveAdoptionTests` 按主题拆出（#508），用例与断言原样搬过来。
final class IncentiveAdoptionPartnerTests: XCTestCase {

    // MARK: - 取消收藏与退出的二次确认、空态

    /// 🔴 **取消收藏对「已退出」的搭档不可逆，而不可逆的后果落在对方身上。**
    ///
    /// 后端 `optOut()` 是打标记不删行（注释逐字写着防的就是「盲人重新收藏一次把退出撤销掉」），
    /// 但同一个 service 的 `remove()` 硬删整行连同 `volunteer_opted_out_at`，
    /// `add()` 随后建一条 `optedOut = null` 的新行 —— 那道防线被取消收藏按钮自己绕过了。
    ///
    /// 断言挑的取值能区分四种破法：
    /// - 「恒不弹窗」（现状）→ 第二组红
    /// - 「所有取消收藏都弹窗」→ 第一组红（把一个真可逆的动作做成了负担）
    /// - 「弹了但只写确定/取消」→ 后果那几条红
    /// - 「次要按钮写成『取消』」→ 最后一条红（在讲「取消收藏」的弹窗里有两种读法）
    func testRemovingAnOptedOutPartnerWarnsThatItSilentlyUndoesTheirOptOut() throws {
        // 没退出过 ⇒ 确实可逆，不该拦。
        XCTAssertNil(PartnerStreakCopy.removeFavoriteConfirmation(name: "张*", hasOptedOut: false))

        let confirmation = try XCTUnwrap(
            PartnerStreakCopy.removeFavoriteConfirmation(name: "张*", hasOptedOut: true)
        )
        XCTAssertEqual(confirmation.title, "取消收藏张*？")
        // 后果三件事，缺一件这个弹窗就退化成一次无声点击：
        XCTAssertTrue(confirmation.message.contains("已经退出了你们的固定搭档"), "①对方退出过")
        XCTAssertTrue(confirmation.message.contains("不作数"), "②再收藏会撤销他的退出")
        XCTAssertTrue(confirmation.message.contains("不会收到任何提示"), "③他不会被告知")
        // 次要按钮不许写「取消」—— 在讲「取消收藏」的弹窗里那两个字有两种读法。
        XCTAssertNotEqual(confirmation.cancel, "取消")
        XCTAssertEqual(confirmation.cancel, "保留收藏")
    }

    /// 退出的二次确认必须把后果写进正文 —— 后端点名要求不要只做「确定 / 取消」。
    /// 退出本轮不可撤销（契约），#327 之前的正文承诺「重新一起跑一单才能恢复」，后端从没实现。
    func testOptOutConfirmationSpellsOutTheConsequenceAndNeverPromisesAWayBack() {
        let message = PartnerStreakCopy.optOutConfirmMessage
        XCTAssertTrue(message.contains("无法撤销"))
        XCTAssertTrue(message.contains("固定搭档"), "后果①：不进固定搭档那一轮")
        XCTAssertTrue(message.contains("加分"), "后果②：不再获得派单加分")
        XCTAssertTrue(message.contains("停止累积"), "后果③：连续记录停止")
        XCTAssertFalse(message.contains("恢复"), message)
        XCTAssertFalse(message.contains("重新一起跑"), message)
        XCTAssertNotEqual(PartnerStreakCopy.optOutCancel, "取消")
    }

    /// 开关**开着**时，空态说的是火花怎么来的（一起跑完订单就会结算），
    /// **不是**「去点某个按钮收藏他」—— 火花与收藏是两条独立的路。
    func testBlindEmptyStateExplainsHowStreaksAppear() {
        let copy = PartnerStreakCopy.blindEmpty(streakEnabled: true)
        XCTAssertTrue(copy.contains("连续两周"))
        XCTAssertFalse(copy.contains("按钮"))
    }

    /// 🔴 **开关关着时不许再说「连续两周一起跑步就会显示」** —— 那是在教用户去做一件
    /// 做了也不会有结果的事。对读屏用户尤其糟：他会照着做两周，回来发现还是空的。
    ///
    /// 后端 `app.incentive.streak.enabled` 默认 `false`，也就是说这句话从上线起一直是错的。
    ///
    /// 断言挑的是**能区分三种实现**的取值：
    /// - 正确实现：三档各说各的
    /// - 「没接开关」的旧实现：三档同一句，`false` 档会撞上第一条断言
    /// - 「`nil` 退回开着那句」的实现：会撞上最后一条断言
    func testEmptyStateDoesNotPromiseStreaksWhileTheFeatureIsOff() {
        let off = PartnerStreakCopy.blindEmpty(streakEnabled: false)
        XCTAssertFalse(
            off.contains("连续两周"),
            "开关关着还教用户去连跑两周，等于让他白跑两周：\(off)"
        )
        XCTAssertTrue(off.contains("还没有开放"), "要让用户知道这不是他自己的问题：\(off)")

        // 拿不到开关时**不做任何承诺**，而不是退回「开着」那一句：
        // 一次网络抖动不该让用户听到一个关于产品状态的断言。
        let unknown = PartnerStreakCopy.blindEmpty(streakEnabled: nil)
        XCTAssertFalse(unknown.contains("连续两周"), "拿不到开关时不许承诺连跑两周会有结果：\(unknown)")
        XCTAssertFalse(unknown.contains("还没有开放"), "拿不到开关时也不许断言功能没开：\(unknown)")

        // 志愿者侧同构，一并钉住 —— 两侧文案分开写就一定会漂移。
        let volunteerOff = PartnerStreakCopy.volunteerEmpty(streakEnabled: false)
        XCTAssertTrue(volunteerOff.contains("还没有开放"))
        let volunteerUnknown = PartnerStreakCopy.volunteerEmpty(streakEnabled: nil)
        XCTAssertFalse(volunteerUnknown.contains("还没有开放"))
    }

    // MARK: - 收藏固定搭档

    /// 🔴 契约逐字：收藏只影响派单**排序**、不影响资格，加分加在满分 100 的五维加权和之外，
    /// 不是压倒一切 —— 附近有个不错的陌生人时，很远的固定搭档仍然会输。
    /// ⇒ 文案只能说「更可能」，**说「优先」就是承诺一件系统做不到的事**。
    func testFavoriteCopyNeverPromisesPriorityDispatch() {
        let copies = [
            PartnerStreakCopy.favoriteExplanation,
            PartnerStreakCopy.favoriteAdded("张*"),
            PartnerStreakCopy.addFavoriteTitle("张*"),
            PartnerStreakCopy.optOutConfirmMessage
        ]
        for copy in copies {
            XCTAssertFalse(copy.contains("优先派"), "不得承诺优先派单：\(copy)")
            XCTAssertFalse(copy.contains("一定派"), "不得承诺一定派给他：\(copy)")
        }
        XCTAssertTrue(PartnerStreakCopy.favoriteExplanation.contains("更可能"))
        XCTAssertTrue(PartnerStreakCopy.favoriteExplanation.contains("不保证"))
    }

    /// 🚨 「没一起跑完过」与「这个 id 根本不是志愿者」后端同码同文案，客户端不得区分 ——
    /// 区分开就等于确认了这个 id 是个志愿者，端点变成枚举接口。
    func testNotEligibleCopyDoesNotLeakWhetherTheAccountExists() {
        let copy = PartnerStreakCopy.favoriteNotEligible
        XCTAssertTrue(copy.contains("一起跑完"))
        XCTAssertFalse(copy.contains("不存在"))
        XCTAssertFalse(copy.contains("不是志愿者"))
        XCTAssertFalse(copy.contains("找不到"))
    }

    /// 两个新错误码要真的映射到人话，否则用户听到的是「未知错误 (400)」。
    func testFavoriteErrorCodesMapToHumanReadableMessages() throws {
        let notEligible = try XCTUnwrap(ErrorCode(rawValue: "FAVORITE_VOLUNTEER_NOT_ELIGIBLE"))
        XCTAssertEqual(notEligible.localizedMessage, PartnerStreakCopy.favoriteNotEligible)

        let limit = try XCTUnwrap(ErrorCode(rawValue: "FAVORITE_VOLUNTEER_LIMIT_EXCEEDED"))
        XCTAssertEqual(limit.localizedMessage, PartnerStreakCopy.favoriteLimitExceeded)

        // TTS 与屏幕上是同一句，不另写一套。
        XCTAssertEqual(notEligible.ttsMessage, notEligible.localizedMessage)

        // 对方退出过（handoff issue #309）：这一对恰恰一起跑完过，不许借「需要先一起跑完」那句；
        // 重试结果一模一样，也不许叫他再试。
        let optedOut = try XCTUnwrap(ErrorCode(rawValue: "FAVORITE_VOLUNTEER_OPTED_OUT"))
        XCTAssertEqual(optedOut.localizedMessage, PartnerStreakCopy.favoriteOptedOut)
        XCTAssertNotEqual(optedOut.localizedMessage, notEligible.localizedMessage)
        XCTAssertFalse(optedOut.localizedMessage.contains("一起跑完"))
        XCTAssertFalse(optedOut.localizedMessage.contains("再试"))
    }

    /// 收藏 / 取消收藏两个端点都幂等且恒 204，Mock 必须照这个演：
    /// 重复收藏不报错，没收藏过也能取消。
    ///
    /// 走 `IncentiveService` 而不是直接拿路径字面量打 Mock：顺带钉住 service 选的
    /// method / path 真的落到 Mock 对应的分支上（端点映射本身另见 `IncentiveServiceTests`）。
    func testMockFavoriteEndpointsAreIdempotent() async throws {
        let service = IncentiveService(transport: MockAPIClient())
        let before = try await service.blindFavoriteVolunteers()

        // 只有火花、还没收藏的那一位。
        let newPartner: Int64 = 9004
        XCTAssertFalse(before.contains { $0.volunteerId == newPartner })

        for _ in 0..<2 {
            try await service.addBlindFavoriteVolunteer(volunteerId: newPartner)
        }
        let added = try await service.blindFavoriteVolunteers()
        XCTAssertEqual(added.filter { $0.volunteerId == newPartner }.count, 1)

        for _ in 0..<2 {
            try await service.removeBlindFavoriteVolunteer(volunteerId: newPartner)
        }
        let removed = try await service.blindFavoriteVolunteers()
        XCTAssertFalse(removed.contains { $0.volunteerId == newPartner })
    }

    /// 没一起跑完过的 id 必须走 400 那条路，而不是静默成功 ——
    /// 静默成功会让「门槛」这条分支在开发期永远走不到。
    func testMockRejectsFavoritingSomeoneYouNeverRanWith() async {
        let service = IncentiveService(transport: MockAPIClient())
        do {
            try await service.addBlindFavoriteVolunteer(volunteerId: 424242)
            XCTFail("不该成功")
        } catch let error as APIError {
            XCTAssertEqual(error.errorCode, .favoriteVolunteerNotEligible)
            XCTAssertEqual(error.localizedMessage, PartnerStreakCopy.favoriteNotEligible)
        } catch {
            XCTFail("错误类型不对：\(error)")
        }
    }

    // MARK: - 订单详情上的收藏入口（`volunteerId`）

    /// 🔴 **这条守的是订单详情收藏入口唯一一个不会报错的失效方式。**
    ///
    /// `volunteerPhone` 只在需要当面汇合的四态下发，`COMPLETED` 时是 nil；
    /// 而 `volunteerId` 在 `COMPLETED` **仍然有值** —— 收藏入口正是开在已完成订单上的。
    /// 拿 `offersVolunteerCall`（种子订单填号码用的就是它）当 id 的判据，编译照过、
    /// 界面照常渲染，只是那个按钮在唯一该出现的地方永远不出现。
    ///
    /// 所以断言必须同时钉住两件事：**id 在、而号码不在**。只断言 id 在的话，
    /// 一个「两个字段都按 phone 的规则发」的实现也能过。
    func testCompletedOrderKeepsVolunteerIdAfterThePhoneIsGone() throws {
        let mock = MockAPIClient()
        let completed = try XCTUnwrap(
            mock.orders.first { $0.status == .completed },
            "种子数据里应当有一单已完成 —— 它是收藏入口在开发期唯一的落点"
        )

        XCTAssertEqual(completed.volunteerId, MockAPIClient.mockOrderVolunteerId)
        XCTAssertEqual(completed.volunteerName, MockAPIClient.mockOrderVolunteerName)
        // 终态不给拨号，所以这一态两个字段的取值方向是**相反**的。
        XCTAssertFalse(
            completed.status.offersVolunteerCall,
            "已完成的单不该再给拨号入口 —— 这正是不能拿它当 volunteerId 判据的理由"
        )
    }

    /// 接单**之前**不许漏出稳定 id。
    ///
    /// `PENDING_INTRO_CALL` 是最要紧的一态：一单最多聊 3 位候选人，给出稳定 id 等于让
    /// 每一个聊崩的人都拿到一个可长期持有的标识（后端把候选人藏在 `dispatchCurrentVolunteerId`
    /// 里、刻意不从这里下发，守的就是这条）。
    func testVolunteerIdIsWithheldUntilSomebodyActuallyAccepts() {
        for status in [RunOrderStatus.pendingMatch, .pendingIntroCall, .rematching, .noVolunteer, .cancelled] {
            XCTAssertFalse(
                MockAPIClient.mockHasAcceptedVolunteer(status),
                "\(status.rawValue) 期后端 order.volunteer 恒为 null，Mock 不许自己造一个"
            )
        }
        for status in [RunOrderStatus.scheduledConfirmed, .pendingAccept, .driverEnRoute, .driverArrived, .inProgress, .completed] {
            XCTAssertTrue(
                MockAPIClient.mockHasAcceptedVolunteer(status),
                "\(status.rawValue) 期志愿者已唯一确定，不下发 id 会让收藏入口凭空消失"
            )
        }
        // 后端新增状态时的兜底方向：隐私边界一律**默认关**（同 `disclosesBlindRunnerNotesToVolunteer`）。
        XCTAssertFalse(MockAPIClient.mockHasAcceptedVolunteer(.unknown))
    }

    /// 与终点三项同一类缺陷：`replacingStatus` 漏带字段不会报错，
    /// 只会让「把他设为固定搭档」那个按钮在每一次 5 秒轮询之后静默消失。
    ///
    /// 用例走的是 `.inProgress → .completed`，也就是收藏入口**刚好开始该出现**的那一跳 ——
    /// 漏带字段的实现会在这一跳把它弄丢。
    func testReplacingStatusKeepsTheVolunteerIdentity() throws {
        let mock = MockAPIClient()
        let accepted = try XCTUnwrap(mock.orders.first { $0.volunteerId != nil })
        XCTAssertNotNil(accepted.volunteerName)

        let finished = accepted.replacingStatus(with: .completed)

        XCTAssertEqual(finished.volunteerId, accepted.volunteerId)
        XCTAssertEqual(finished.volunteerName, accepted.volunteerName)
    }

    /// Mock 的收藏门槛是「id 在不在种子表里」。种子订单那位志愿者**必须在表里**，
    /// 否则订单详情页那个新按钮在开发期点下去必然吃 `FAVORITE_VOLUNTEER_NOT_ELIGIBLE`
    /// —— 而真实后端此处会放行（门槛是「一起跑完过至少一单」，那一单就是这单）。
    ///
    /// 同时钉住「初始未收藏」：初始已收藏的话，页面只会显示「已经是你的固定搭档」，
    /// 按钮那条主路径在开发期一次也走不到。
    func testTheSeededOrdersVolunteerCanActuallyBeFavorited() async throws {
        let service = IncentiveService(transport: MockAPIClient())
        let before = try await service.blindFavoriteVolunteers()
        XCTAssertFalse(
            before.contains { $0.volunteerId == MockAPIClient.mockOrderVolunteerId },
            "初始就收藏了的话，「设为固定搭档」按钮在 Mock 下永远不出现"
        )

        try await service.addBlindFavoriteVolunteer(volunteerId: MockAPIClient.mockOrderVolunteerId)

        let after = try await service.blindFavoriteVolunteers()
        XCTAssertTrue(after.contains { $0.volunteerId == MockAPIClient.mockOrderVolunteerId })
    }
}
