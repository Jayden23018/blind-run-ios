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

    /// 🚨 `invitationRewardEnabled` 的语义与另外两个**相反**：它只关奖励、不关关系建立。
    /// 契约 description 逐字写着「不要因为它是 false 就把邀请码输入框藏掉 —— 那会让开关
    /// 打开之后这批用户永久拿不到奖励，而他们当时根本没机会填」。
    ///
    /// 本条守的是**将来**：现在邀请码输入框根本没读这个开关（这是对的）。
    /// 哪天有人把它接上去当显示条件，这条会红。
    func testInvitationRewardFlagIsNotWiredIntoAnyVisibilityDecision() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()   // blindRunTests/
                .deletingLastPathComponent()   // 仓库根
                .appendingPathComponent("blindRun/Shared/InviteCodeView.swift"),
            encoding: .utf8
        )
        XCTAssertFalse(
            source.contains("invitationRewardEnabled"),
            "邀请码输入框不得随奖励开关隐藏：关着时邀请关系照样落库，藏掉会让这批用户永久拿不到奖励"
        )
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
