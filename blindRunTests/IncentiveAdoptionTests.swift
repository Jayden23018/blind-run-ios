import XCTest
@testable import blindRun

/// SPEC-E 激励体系（积分 / 双人火花 / 固定搭档 opt-out / 拉新邀请）的客户端接入。
///
/// 这一组守的是**四类会静默出错的地方**，每一类后端都在 handoff 里点过名：
///
/// 1. `delta == 0` 的流水是「这一单为什么没加分」的唯一答案，过滤掉就等于把解释藏起来。
/// 2. `reason` 是开放枚举，产成封闭 enum 会让**整条响应**解不出来 —— 对盲人端是一整页空白。
/// 3. `streakWeeks == nil` 与 `== 0` 含义不同：`nil` 是「没点亮」，显示「连续 0 周」是错的。
/// 4. 三条监管红线是文案层面的，编译器不管，只能靠断言钉住常量本身。
final class IncentiveAdoptionTests: XCTestCase {

    // MARK: - 1. delta = 0 的流水不许消失

    func testZeroDeltaTransactionIsKeptAndReadsItsNote() throws {
        let json = """
        {
          "balance": 20,
          "transactions": [
            {"id": 1, "delta": 0, "reason": "ORDER_COMPLETED", "orderId": 7,
             "note": "已达同一对每周上限 30 分，本单不加分", "createdAt": "2026-08-21T10:00:00"},
            {"id": 2, "delta": 20, "reason": "INVITE_REWARD", "orderId": null,
             "note": null, "createdAt": "2026-08-20T10:00:00"}
          ],
          "page": 0, "size": 20, "totalElements": 2, "totalPages": 1
        }
        """
        let response = try JSONDecoder().decode(VolunteerPointsResponse.self, from: Data(json.utf8))

        // 解出来就是两条，`resolvedTransactions` 不做任何过滤。
        XCTAssertEqual(response.resolvedTransactions.count, 2)

        let capped = try XCTUnwrap(response.resolvedTransactions.first)
        XCTAssertEqual(capped.resolvedDelta, 0)
        XCTAssertEqual(capped.deltaText, "0 分")
        XCTAssertEqual(capped.kind, .noChange)
        // 🔴 note 非空时它**取代** reasonText 被念出来，而不是拼在后面 ——
        // 「本单不加分」和「完成陪跑服务」念在一起是自相矛盾的。
        XCTAssertTrue(capped.accessibilityLabel.contains("已达同一对每周上限 30 分，本单不加分"))
        XCTAssertFalse(capped.accessibilityLabel.contains("完成陪跑服务"))
        XCTAssertTrue(capped.accessibilityLabel.contains("加 0 分"))
    }

    func testPositiveAndNegativeDeltaText() {
        XCTAssertEqual(makeTransaction(delta: 10).deltaText, "+10 分")
        XCTAssertEqual(makeTransaction(delta: -10).deltaText, "-10 分")
        XCTAssertEqual(makeTransaction(delta: 10).kind, .credited)
        XCTAssertEqual(makeTransaction(delta: -10).kind, .deducted)
        // 0 不写成「+0 分」：那读起来像加了分。
        XCTAssertEqual(makeTransaction(delta: 0).deltaText, "0 分")
    }

    // MARK: - 2. reason 是开放枚举

    func testUnknownReasonDegradesToOtherInsteadOfFailingTheWholeResponse() throws {
        // 后端下一次加值时长这样。整条响应必须照常解出来。
        let json = """
        {"balance": 5, "transactions": [
          {"id": 1, "delta": 5, "reason": "SOMETHING_THE_APP_HAS_NEVER_SEEN",
           "orderId": null, "note": null, "createdAt": "2026-08-23T10:00:00"}
        ], "page": 0, "size": 20, "totalElements": 1, "totalPages": 1}
        """
        let response = try JSONDecoder().decode(VolunteerPointsResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response.resolvedTransactions.count, 1)
        XCTAssertEqual(response.resolvedTransactions[0].reasonText, "其他")
    }

    func testKnownReasonsHaveChineseNames() {
        XCTAssertEqual(makeTransaction(reason: "ORDER_COMPLETED").reasonText, "完成陪跑服务")
        XCTAssertEqual(makeTransaction(reason: "ORDER_AUTO_COMPLETED").reasonText, "服务超时自动完成")
        XCTAssertEqual(makeTransaction(reason: "INVITE_REWARD").reasonText, "邀请奖励")
        XCTAssertEqual(makeTransaction(reason: "REVERSAL").reasonText, "人工冲正")
        XCTAssertEqual(makeTransaction(reason: nil).reasonText, "其他")
    }

    // MARK: - 按天分组只分节，不改顺序、不丢条目

    func testGroupingKeepsOrderAndKeepsEveryTransaction() {
        let transactions = [
            makeTransaction(delta: 10, createdAt: "2026-08-22T20:00:00"),
            makeTransaction(delta: 0, createdAt: "2026-08-22T09:00:00"),
            makeTransaction(delta: 10, createdAt: "2026-08-21T09:00:00")
        ]
        let days = PointTransactionGrouping.group(transactions)

        XCTAssertEqual(days.count, 2)
        XCTAssertEqual(days[0].title, "2026年8月22日")
        XCTAssertEqual(days[0].transactions.count, 2)
        XCTAssertEqual(days[1].title, "2026年8月21日")
        XCTAssertEqual(days.reduce(0) { $0 + $1.transactions.count }, transactions.count)
    }

    func testUnparsableTimestampIsGroupedNotDropped() {
        let days = PointTransactionGrouping.group([makeTransaction(createdAt: "不是时间")])
        XCTAssertEqual(days.count, 1)
        XCTAssertEqual(days[0].title, PointTransactionGrouping.unknownDayTitle)
        XCTAssertEqual(days[0].transactions.count, 1)
    }

    // MARK: - 3. streakWeeks 的 nil 与 0

    func testNilStreakWeeksMeansNoStreakAtAllNotZeroWeeks() {
        XCTAssertNil(PartnerStreakDisplay(currentWeeks: nil, bestWeeks: 7))
        XCTAssertNil(PartnerStreakDisplay(currentWeeks: 0, bestWeeks: 7))
        XCTAssertNotNil(PartnerStreakDisplay(currentWeeks: 1, bestWeeks: nil))
    }

    func testStreakProgressTextTellsHowFarFromPersonalBest() throws {
        let behind = try XCTUnwrap(PartnerStreakDisplay(currentWeeks: 3, bestWeeks: 7))
        XCTAssertFalse(behind.isPersonalBest)
        XCTAssertEqual(behind.progressText, "距离你们最好的 7 周还差 4 周")
        XCTAssertEqual(behind.headline(partner: "张*"), "张*，已经连续 3 周一起跑步")

        let best = try XCTUnwrap(PartnerStreakDisplay(currentWeeks: 7, bestWeeks: 7))
        XCTAssertTrue(best.isPersonalBest)
        XCTAssertEqual(best.progressText, "这是你们最好的成绩")
    }

    /// `bestWeeks` 缺失或小于 `currentWeeks` 时不能算出负数进度。
    func testBestWeeksNeverBelowCurrent() throws {
        let display = try XCTUnwrap(PartnerStreakDisplay(currentWeeks: 5, bestWeeks: 2))
        XCTAssertEqual(display.bestWeeks, 5)
        XCTAssertTrue(display.isPersonalBest)
        XCTAssertEqual(display.progressFraction, 1, accuracy: 0.0001)
    }

    /// 文案里**不许**出现暂停周（每季度 2 个、自动消耗）。用户感知不到它，
    /// 说出来会变成新的压力源。
    func testStreakCopyNeverMentionsPauseWeeks() throws {
        let display = try XCTUnwrap(PartnerStreakDisplay(currentWeeks: 3, bestWeeks: 7))
        for text in [display.progressText, display.headline(partner: "张*")] {
            XCTAssertFalse(text.contains("暂停"))
            XCTAssertFalse(text.contains("机会"))
        }
    }

    // MARK: - 两个端点的合并

    func testBlindMergePrefersStreakEndpointForBestWeeksAndKeepsOptedOutRows() throws {
        let favorites = [
            FavoriteVolunteerResponse(
                volunteerId: 1, volunteerName: "张*", completedRunsTogether: 12,
                favoritedAt: "2026-07-03T09:15:00", streakWeeks: 3, partnerOptedOut: false
            ),
            FavoriteVolunteerResponse(
                volunteerId: 2, volunteerName: "李*", completedRunsTogether: 3,
                favoritedAt: "2026-08-01T18:40:00", streakWeeks: nil, partnerOptedOut: true
            )
        ]
        let streaks = [
            PartnerStreakResponse(id: 10, partnerUserId: 1, partnerName: "张*",
                                  currentWeeks: 3, bestWeeks: 7, lastCreditedWeek: "2026-W34"),
            PartnerStreakResponse(id: 11, partnerUserId: 99, partnerName: "王*",
                                  currentWeeks: 2, bestWeeks: 2, lastCreditedWeek: "2026-W34")
        ]

        let rows = PartnerRowMerge.blindRows(favorites: favorites, streaks: streaks)

        // 收藏两条 + 只有火花一条，一条都不丢。
        XCTAssertEqual(rows.count, 3)

        // 同一个人只出现一次，且 bestWeeks 取自 /partners/streaks（收藏列表里没有这个数）。
        XCTAssertEqual(rows[0].userId, 1)
        XCTAssertEqual(rows[0].streak?.bestWeeks, 7)
        XCTAssertTrue(rows[0].isFavorite)

        // 🔴 对方已退出的条目仍在列表里。
        XCTAssertEqual(rows[1].userId, 2)
        XCTAssertTrue(rows[1].hasOptedOut)
        XCTAssertNil(rows[1].streak)

        // 有火花但没被收藏的那一对落在后面，且标成非收藏。
        XCTAssertEqual(rows[2].userId, 99)
        XCTAssertFalse(rows[2].isFavorite)
        XCTAssertEqual(rows[2].streak?.currentWeeks, 2)
    }

    func testVolunteerMergeKeepsMyOwnOptOutVisible() {
        let rows = PartnerRowMerge.volunteerRows(
            favorites: [
                VolunteerFavoritedByResponse(blindUserId: 5, blindName: "李*",
                                             favoritedAt: "2026-07-03T09:15:00", optedOut: true)
            ],
            streaks: []
        )
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(rows[0].hasOptedOut)
        XCTAssertTrue(rows[0].isFavorite)
    }

    /// 火花条目的 `partnerUserId` 为 `nil` 时对不上任何收藏，但**不能丢** ——
    /// 丢一条就是让一段真实的关系从用户眼前消失。
    func testStreakWithoutPartnerIdStillProducesARow() {
        let rows = PartnerRowMerge.volunteerRows(
            favorites: [],
            streaks: [PartnerStreakResponse(id: 1, partnerUserId: nil, partnerName: nil,
                                            currentWeeks: 4, bestWeeks: 4, lastCreditedWeek: nil)]
        )
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].streak?.currentWeeks, 4)
    }

    // MARK: - 邀请码

    func testInviteCodeSanitizeDropsAnythingTheContractWouldReject() {
        XCTAssertNil(InviteCodeEntryCopy.sanitize(""))
        XCTAssertNil(InviteCodeEntryCopy.sanitize("   "))
        // 契约 maxLength 16
        XCTAssertNil(InviteCodeEntryCopy.sanitize(String(repeating: "A", count: 17)))
        // 契约 pattern ^[A-Za-z0-9]*$
        XCTAssertNil(InviteCodeEntryCopy.sanitize("AK37-PQR9"))
        XCTAssertNil(InviteCodeEntryCopy.sanitize("邀请码"))
        // 首尾空白忽略；大小写不敏感（后端做，客户端不自己转大写）
        XCTAssertEqual(InviteCodeEntryCopy.sanitize("  ak37pqr9 "), "ak37pqr9")
        XCTAssertEqual(InviteCodeEntryCopy.sanitize("AK37PQR9"), "AK37PQR9")
    }

    /// 🔴 不传邀请码时请求体必须与老客户端**逐字节一致** —— 合成的 `Encodable`
    /// 对 Optional 走 `encodeIfPresent`，所以键根本不该出现。
    func testSetRoleRequestOmitsInviteCodeWhenAbsent() throws {
        let data = try JSONEncoder().encode(SetRoleRequest(role: .volunteer))
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(json.contains("inviteCode"))

        let withCode = try JSONEncoder().encode(SetRoleRequest(role: .volunteer, inviteCode: "AK37PQR9"))
        let object = try JSONSerialization.jsonObject(with: withCode) as? [String: Any]
        XCTAssertEqual(object?["inviteCode"] as? String, "AK37PQR9")
        XCTAssertEqual(object?["role"] as? String, "VOLUNTEER")
    }

    func testInviteCodeCountsCopySwitchesToEmptyWhenNobodyUsedIt() {
        let none = InviteCodeResponse(inviteCode: "AK37PQR9", invitedCount: 0, rewardedCount: 0)
        XCTAssertEqual(InviteCodeCopy.countsText(none), InviteCodeCopy.empty)

        let some = InviteCodeResponse(inviteCode: "AK37PQR9", invitedCount: 3, rewardedCount: 1)
        XCTAssertEqual(InviteCodeCopy.countsText(some), "已经有 3 人使用了你的邀请码，其中 1 人已发放奖励。")
    }

    /// 展示不改内容，复制拿到的是原样的码 —— 字距靠 `tracking` 给，
    /// 在字符串里插空格会让用户复制出一个坏掉的码。
    func testInviteCodeFormattingNeverInjectsSeparators() {
        XCTAssertEqual(InviteCodeFormatting.display("ak37pqr9"), "AK37PQR9")
        XCTAssertEqual(InviteCodeFormatting.copyable(" AK37PQR9 "), "AK37PQR9")
        XCTAssertFalse(InviteCodeFormatting.display("AK37PQR9")?.contains(" ") ?? true)
    }

    // MARK: - 4. 三条监管红线（文案层）

    /// 依据：中央网信办秘书局 + 中央社会工作部《关于开展网络平台涉志愿服务违规信息专项整治的通知》
    /// （2026-06-19 发文）第 2 条点名整治「宣传可以获得志愿服务时长」；
    /// 央行等八部门银发〔2026〕42 号禁止现实世界资产代币化（被禁特征是可发行、可交易）。
    func testPointsCopyNeverPromisesRedemptionOrTransfer() {
        let copies = [
            VolunteerPointsCopy.disclaimer,
            VolunteerPointsCopy.separateFromServiceHours,
            VolunteerPointsCopy.empty,
            VolunteerPointsCopy.loadFailure,
            InviteCodeCopy.rewardRule,
            InviteCodeCopy.pointsDisclaimer,
            InviteCodeCopy.oneShotWarning
        ]
        // 「不能兑换现金」这类**否定式**表述是允许的，被禁的是承诺可兑换。
        let forbidden = ["可兑换", "可提现", "可转让", "转赠", "积分商城已上线", "敬请期待", "折算"]
        for copy in copies {
            for word in forbidden {
                XCTAssertFalse(copy.contains(word), "「\(word)」不该出现在：\(copy)")
            }
        }
    }

    func testNoOfficialHonorificTitlesAnywhere() {
        let copies = [
            VolunteerPointsCopy.navigationTitle,
            VolunteerPointsCopy.balanceCaption,
            VolunteerPointsCopy.disclaimer,
            PartnerStreakCopy.blindNavigationTitle,
            PartnerStreakCopy.volunteerNavigationTitle,
            InviteCodeCopy.navigationTitle,
            InviteCodeCopy.rewardRule
        ]
        // 「四个 100」是中宣部/中央文明办/民政部/团中央联合评选的官方称号。
        for copy in copies {
            XCTAssertFalse(copy.contains("最美志愿者"))
            XCTAssertFalse(copy.contains("星级志愿者"))
        }
    }

    /// 积分页必须显式指出时长在别处，而不是把两个数混着说。
    func testPointsPageKeepsServiceHoursInAnotherPlace() {
        XCTAssertTrue(VolunteerPointsCopy.separateFromServiceHours.contains("志愿服务时长"))
        XCTAssertTrue(VolunteerPointsCopy.separateFromServiceHours.contains("服务成就"))
        XCTAssertFalse(VolunteerPointsCopy.disclaimer.contains("时长"))
    }

    /// 🔴 邀请文案必须分角色。写成「邀请好友双方得积分」是错的：
    /// 邀请盲人只记录关系、不发任何积分（后端决策 14）。
    func testInviteCopyDistinguishesVolunteerFromBlindRunner() {
        XCTAssertTrue(InviteCodeCopy.rewardRule.contains("邀请志愿者"))
        XCTAssertTrue(InviteCodeCopy.rewardRule.contains("不发积分"))
        XCTAssertFalse(InviteCodeCopy.rewardRule.contains("好友"))
    }

    /// 🔴 填错不会让 `POST /api/user/role` 失败，而且没有任何端点能回查邀请码是否生效
    /// ⇒ 界面必须在**填之前**说清楚，事后我们什么都说不了。
    func testInviteCodeEntryTellsUserItCannotBeVerified() {
        XCTAssertTrue(InviteCodeEntryCopy.oneShotNotice.contains("只能"))
        XCTAssertTrue(InviteCodeEntryCopy.oneShotNotice.contains("无法补填"))
        XCTAssertTrue(InviteCodeEntryCopy.oneShotNotice.contains("填错"))
        // 折叠态下这句播报是读屏用户知道有这个格子的唯一途径。
        XCTAssertTrue(InviteCodeEntryCopy.speechHint.contains("邀请码"))
    }

    /// 退出的二次确认必须把后果写进正文 —— 后端点名要求不要只做「确定 / 取消」。
    func testOptOutConfirmationSpellsOutTheConsequence() {
        XCTAssertTrue(PartnerStreakCopy.optOutConfirmMessage.contains("不再被优先派给"))
        XCTAssertTrue(PartnerStreakCopy.optOutConfirmMessage.contains("重新一起跑一单"))
    }

    /// 空态说的是火花怎么来的（一起跑完订单就会结算），**不是**「去点某个按钮收藏他」——
    /// 收藏入口只在已经一起跑过的搭档那一行上，空列表时根本没有可点的对象。
    func testBlindEmptyStateExplainsHowStreaksAppear() {
        XCTAssertTrue(PartnerStreakCopy.blindEmpty.contains("连续两周"))
        XCTAssertFalse(PartnerStreakCopy.blindEmpty.contains("按钮"))
    }

    // MARK: - 收藏固定搭档

    /// 🔴 契约逐字：收藏只影响派单**排序**、不影响资格，加分加在满分 100 的五维加权和之外，
    /// 不是压倒一切 —— 附近有个不错的陌生人时，很远的固定搭档仍然会输。
    /// ⇒ 文案只能说「更可能」，**说「优先」就是承诺一件系统做不到的事**。
    func testFavoriteCopyNeverPromisesPriorityDispatch() {
        let copies = [
            PartnerStreakCopy.favoriteExplanation,
            PartnerStreakCopy.favoriteAdded("张*"),
            PartnerStreakCopy.addFavoriteTitle("张*")
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
    }

    /// 收藏 / 取消收藏两个端点都幂等且恒 204，Mock 必须照这个演：
    /// 重复收藏不报错，没收藏过也能取消。
    func testMockFavoriteEndpointsAreIdempotent() async throws {
        let client = MockAPIClient()
        let before: [FavoriteVolunteerResponse] = try await client.get("/api/blind/favorite-volunteers")

        // 只有火花、还没收藏的那一位。
        let newPartner: Int64 = 9004
        XCTAssertFalse(before.contains { $0.volunteerId == newPartner })

        for _ in 0..<2 {
            let _: EmptyResponse = try await client.request(
                method: .put, path: "/api/blind/favorite-volunteers/\(newPartner)",
                query: nil, body: nil, requiresAuth: true
            )
        }
        let added: [FavoriteVolunteerResponse] = try await client.get("/api/blind/favorite-volunteers")
        XCTAssertEqual(added.filter { $0.volunteerId == newPartner }.count, 1)

        for _ in 0..<2 {
            let _: EmptyResponse = try await client.request(
                method: .delete, path: "/api/blind/favorite-volunteers/\(newPartner)",
                query: nil, body: nil, requiresAuth: true
            )
        }
        let removed: [FavoriteVolunteerResponse] = try await client.get("/api/blind/favorite-volunteers")
        XCTAssertFalse(removed.contains { $0.volunteerId == newPartner })
    }

    /// 没一起跑完过的 id 必须走 400 那条路，而不是静默成功 ——
    /// 静默成功会让「门槛」这条分支在开发期永远走不到。
    func testMockRejectsFavoritingSomeoneYouNeverRanWith() async {
        let client = MockAPIClient()
        do {
            let _: EmptyResponse = try await client.request(
                method: .put, path: "/api/blind/favorite-volunteers/424242",
                query: nil, body: nil, requiresAuth: true
            )
            XCTFail("不该成功")
        } catch let error as APIError {
            XCTAssertEqual(error.errorCode, .favoriteVolunteerNotEligible)
            XCTAssertEqual(error.localizedMessage, PartnerStreakCopy.favoriteNotEligible)
        } catch {
            XCTFail("错误类型不对：\(error)")
        }
    }

    // MARK: - Helpers

    private func makeTransaction(
        delta: Int = 10,
        reason: String? = "ORDER_COMPLETED",
        note: String? = nil,
        createdAt: String? = "2026-08-22T10:00:00"
    ) -> PointTransactionResponse {
        PointTransactionResponse(
            id: 1, delta: delta, reason: reason, orderId: nil, note: note, createdAt: createdAt
        )
    }
}
