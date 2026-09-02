//
//  MockAPIClient+Incentive.swift
//  blindRun
//
//  从 MockAPIClient.swift 原样搬出的 激励体系 分段。行为零改动，只改文件位置。
//

import Foundation

extension MockAPIClient {

    // MARK: - SPEC-E 激励体系

    /// ⚠️ **Mock 演的是「三个开关都打开之后」的行为。**
    ///
    /// 真实后端上，火花（`app.incentive.streak.enabled`）、派单优先轮、邀请奖励三个开关
    /// **默认全关**，所以联调时火花端点会返回空数组、邀请关系建立了但积分不动 ——
    /// 那不是接错了。Mock 如果也演成空的，这几屏 UI 在开发期永远走不到，
    /// 而「空数组」那条分支本来就有单测钉着（`IncentiveAdoptionTests`）。
    ///
    /// **积分没有开关**（`PointService` 只有数值参数），它从第一天就在记 —— 这一条 Mock 与真实一致。
    ///
    /// 搭档数据是**写死的种子**，不是从订单推的：`OrderDetailResponse` 里没有志愿者 id 与姓名，
    /// 推不出「哪两个人是一对」。种子刻意覆盖三种真实存在、且 UI 必须分别处理的形态：
    /// 有火花 / 没点亮火花（`streakWeeks == nil`）/ 对方已退出。
    private enum MockIncentiveSeed {
        static let partnerWithStreakId: Int64 = 9001
        static let partnerWithoutStreakId: Int64 = 9002
        static let partnerOptedOutId: Int64 = 9003
        /// 只有火花、没有收藏关系的一对 —— 用来验合并逻辑的第二段。
        static let streakOnlyPartnerId: Int64 = 9004

        /// 8 位大写字母数字，且**逐字排除了 `0 O 1 I L`**，与后端字符集一致。
        static let inviteCode = "AK37PQR9"
    }

    func handleGetVolunteerPoints(query: [String: String]?) -> VolunteerPointsResponse {
        let completed = orders.filter { $0.status == .completed }
        let size = query?["size"].flatMap(Int.init) ?? 20
        let page = query?["page"].flatMap(Int.init) ?? 0

        var transactions: [PointTransactionResponse] = []
        var nextId: Int64 = 7000
        for (index, order) in completed.enumerated() {
            // 后端每人每日上限 20 分、每单 10 分 ⇒ 同一天的第 3 单起写一条 delta = 0 的流水。
            // 这条**不是**装饰：它是「我这单怎么没加分」的唯一答案，UI 必须能显示它。
            let cappedByDailyLimit = index >= 2
            transactions.append(
                PointTransactionResponse(
                    id: nextId,
                    delta: cappedByDailyLimit ? 0 : 10,
                    reason: "ORDER_COMPLETED",
                    orderId: order.orderId,
                    note: cappedByDailyLimit ? "已达每人每日上限 20 分，本单不加分" : nil,
                    createdAt: order.createdAt
                )
            )
            nextId += 1
        }

        // 拉新奖励。`INVITE_REWARD` 是后端 SPEC-E 第 4 步新增的取值，
        // 放一条进来正是为了让「开放枚举新增取值」这条路在开发期走得到。
        if !completed.isEmpty {
            transactions.append(
                PointTransactionResponse(
                    id: nextId,
                    delta: 20,
                    reason: "INVITE_REWARD",
                    orderId: nil,
                    note: nil,
                    createdAt: DateFormatter.aidRunBackendLocalDateTime.string(
                        from: Date().addingTimeInterval(-86_400)
                    )
                )
            )
        }

        let balance = transactions.reduce(Int64(0)) { $0 + Int64($1.resolvedDelta) }
        let start = min(page * size, transactions.count)
        let end = min(start + size, transactions.count)
        return VolunteerPointsResponse(
            balance: balance,
            transactions: Array(transactions[start..<end]),
            page: page,
            size: size,
            totalElements: Int64(transactions.count),
            totalPages: max(1, Int(ceil(Double(transactions.count) / Double(size))))
        )
    }

    /// 契约：**只返回已点亮的**（默认门槛连续 2 周），按 `currentWeeks` 倒序。
    /// 未点亮的一对根本不在数组里 —— 所以这里也不放 `currentWeeks == 1` 的条目。
    func handleGetPartnerStreaks(asBlind: Bool) -> [PartnerStreakResponse] {
        guard !orders.filter({ $0.status == .completed }).isEmpty else { return [] }
        return [
            PartnerStreakResponse(
                id: 8001,
                partnerUserId: MockIncentiveSeed.partnerWithStreakId,
                partnerName: asBlind ? "张*" : "李*",
                currentWeeks: 3,
                bestWeeks: 7,
                lastCreditedWeek: "2026-W34"
            ),
            PartnerStreakResponse(
                id: 8002,
                partnerUserId: MockIncentiveSeed.streakOnlyPartnerId,
                partnerName: asBlind ? "王*" : "赵*",
                currentWeeks: 2,
                bestWeeks: 2,
                lastCreditedWeek: "2026-W34"
            )
        ]
    }

    /// 盲人侧固定搭档的种子行。哪几行**当前在列表里**由 `blindFavoritedVolunteerIds` 决定，
    /// 所以 Mock 里收藏 / 取消收藏是真的会改变这一屏的。
    private static let blindFavoriteSeeds: [Int64: FavoriteVolunteerResponse] = [
        MockIncentiveSeed.partnerWithStreakId: FavoriteVolunteerResponse(
            volunteerId: MockIncentiveSeed.partnerWithStreakId,
            volunteerName: "张*",
            completedRunsTogether: 12,
            favoritedAt: "2026-07-03T09:15:00",
            // 与 `/partners/streaks` 里那条同一个数（契约明说两处口径一致）。
            streakWeeks: 3,
            partnerOptedOut: false
        ),
        MockIncentiveSeed.partnerWithoutStreakId: FavoriteVolunteerResponse(
            volunteerId: MockIncentiveSeed.partnerWithoutStreakId,
            volunteerName: "李*",
            completedRunsTogether: 3,
            favoritedAt: "2026-08-01T18:40:00",
            // 🔴 未点亮是 `null` 不是 0 —— 这一行存在的意义就是让「那一行不念」被验到。
            streakWeeks: nil,
            partnerOptedOut: false
        ),
        MockIncentiveSeed.partnerOptedOutId: FavoriteVolunteerResponse(
            volunteerId: MockIncentiveSeed.partnerOptedOutId,
            volunteerName: "王*",
            completedRunsTogether: 5,
            favoritedAt: "2026-06-20T07:05:00",
            streakWeeks: nil,
            // 🔴 退出的条目**仍然留在列表里**，不是从列表消失。
            partnerOptedOut: true
        ),
        // 只有火花、初始未收藏 —— 「设为固定搭档」那个按钮在 Mock 里点的就是它。
        MockIncentiveSeed.streakOnlyPartnerId: FavoriteVolunteerResponse(
            volunteerId: MockIncentiveSeed.streakOnlyPartnerId,
            volunteerName: "赵*",
            completedRunsTogether: 2,
            favoritedAt: "2026-08-23T08:00:00",
            streakWeeks: 2,
            partnerOptedOut: false
        )
    ]

    func handleGetBlindFavoriteVolunteers() -> [FavoriteVolunteerResponse] {
        // 契约：收藏时间倒序。
        blindFavoritedVolunteerIds
            .compactMap { Self.blindFavoriteSeeds[$0] }
            .sorted { ($0.favoritedAt ?? "") > ($1.favoritedAt ?? "") }
    }

    /// `PUT /api/blind/favorite-volunteers/{volunteerId}` —— **幂等，恒 204**。
    ///
    /// 🚨 门槛：必须一起跑完过至少一单，否则 400 `FAVORITE_VOLUNTEER_NOT_ELIGIBLE`。
    /// Mock 用「这个 id 在不在种子表里」当门槛的替身 —— 不在表里就是没一起跑过。
    /// 「没一起跑完过」与「这个 id 根本不是志愿者」**同码同文案**，这里也不区分，
    /// 否则 Mock 会诱导客户端写出一段真实后端不支持的分支。
    func handleAddBlindFavoriteVolunteer(volunteerId: Int64) throws -> EmptyResponse {
        guard Self.blindFavoriteSeeds[volunteerId] != nil else {
            throw APIError.serverError(ErrorResponse(
                code: "FAVORITE_VOLUNTEER_NOT_ELIGIBLE",
                message: "需要先和这位志愿者一起跑完至少一次"
            ))
        }
        guard blindFavoritedVolunteerIds.count < Self.mockFavoriteVolunteerLimit
                || blindFavoritedVolunteerIds.contains(volunteerId) else {
            throw APIError.serverError(ErrorResponse(
                code: "FAVORITE_VOLUNTEER_LIMIT_EXCEEDED",
                message: "固定搭档数量已达上限"
            ))
        }
        blindFavoritedVolunteerIds.insert(volunteerId)
        return EmptyResponse()
    }

    /// `DELETE` —— 同样幂等，没收藏过也返 204。
    func handleRemoveBlindFavoriteVolunteer(volunteerId: Int64) -> EmptyResponse {
        blindFavoritedVolunteerIds.remove(volunteerId)
        return EmptyResponse()
    }

    func handleGetVolunteerFavoritedBy() -> [VolunteerFavoritedByResponse] {
        [
            VolunteerFavoritedByResponse(
                blindUserId: MockIncentiveSeed.partnerWithStreakId,
                blindName: "李*",
                favoritedAt: "2026-07-03T09:15:00",
                optedOut: volunteerOptedOutPartnerIds.contains(MockIncentiveSeed.partnerWithStreakId)
            ),
            VolunteerFavoritedByResponse(
                blindUserId: MockIncentiveSeed.partnerWithoutStreakId,
                blindName: "王*",
                favoritedAt: "2026-08-01T18:40:00",
                optedOut: volunteerOptedOutPartnerIds.contains(MockIncentiveSeed.partnerWithoutStreakId)
            )
        ]
    }

    /// **恒 204，不区分「改到了」与「没这一行」** —— 区分开这个端点就成了
    /// 「拿任意 userId 试一下看响应差异」的探测器。重复点也是 204（幂等）。
    func handleVolunteerOptOutOfFavorite(blindUserId: Int64) -> EmptyResponse {
        volunteerOptedOutPartnerIds.insert(blindUserId)
        return EmptyResponse()
    }

    func handleGetInviteCode() -> InviteCodeResponse {
        InviteCodeResponse(
            inviteCode: MockIncentiveSeed.inviteCode,
            invitedCount: 3,
            // 只有被邀请的**志愿者**跑完首单才发奖，所以这个数天然小于 invitedCount。
            rewardedCount: 1
        )
    }
}
