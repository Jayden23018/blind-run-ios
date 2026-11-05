import SwiftUI

extension VolunteerHomeViewModel {
    /// UI 测试用的「预置几条待回复邀请」。与 `AIDRUN_UI_TEST_SEED_ORDER_STATUS` 同一套做法。
    ///
    /// 🚩 **必须有这个种子，否则邀请卡在 UI 测试里根本到不了。** 派单只从 WebSocket 来，
    /// 而 UI 测试默认 `disableWebSocket` —— 没有种子的话这一屏的无障碍形状永远没人验。
    ///
    /// `#if DEBUG` 包住：Release 产物里不存在这条路径，一个环境变量骗不出一张假邀请。
    func seedInvitesForUITestsIfNeeded() {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        guard environment["AIDRUN_UI_TEST_RESET_STATE"] == "1",
              let raw = environment["AIDRUN_UI_TEST_SEED_INVITES"],
              let count = Int(raw), count > 0 else { return }
        let now = Date()
        for index in 0..<count {
            enqueue(
                order: Self.uiTestSeedInvite(orderId: Int64(9_000 + index), now: now),
                receivedAt: now,
                // 每条差 30 秒，好让「按回复期限升序」和分页点在 UI 上真的分得开。
                expiresAt: now.addingTimeInterval(TimeInterval(120 + index * 30)),
                // 🚩 真实路径上这三项由 `GET /api/orders/available` 补，而 mock 对那条路径恒返空数组
                // （它没有这些客户端注入的 id）。直接种进来，否则跑者行在 UI 测试里永远不可达 ——
                // 而「整行不渲染」恰恰是它出问题时的样子，没人分得出是渲染坏了还是数据没来。
                // 匹配逻辑本身由 `VolunteerInviteState.merge` 的单测验。
                supplement: VolunteerInviteSupplement(
                    visionLevel: VisionLevel.totalBlind.rawValue,
                    tetherPreference: TetherPreference.tetherRope.rawValue,
                    expectedDurationMinutes: 60
                ),
                // 🚩 **显式钉死 `.inviteCard`，不许现算。** 种子在 `configure` 里跑，
                // 那一刻接单主页还没打开 ⇒ `resolve` 会落到 `.banner`，而这一整组 UI 用例
                // （`blindRunUITests` 的邀请卡无障碍形状）验的就是那张卡自动弹出来。
                presentation: .inviteCard,
                // 种下 N 条就响 N 声，而那台真机正拿在跑测的人手里。
                announces: false
            )
        }
        #endif
    }

    #if DEBUG
    /// 非 private：Mock 的待回复列表要返回同样的几张（`MockAPIClient.uiTestSeededPendingInvites`），
    /// 否则首页一对账就会把种下的邀请判成失效。
    static func uiTestSeedInvite(orderId: Int64, now: Date) -> WSNewOrder {
        WSNewOrder(
            type: "NEW_ORDER",
            timestamp: nil,
            orderId: orderId,
            startAddress: "深圳湾公园 3 号入口",
            startLatitude: nil,
            startLongitude: nil,
            distanceKm: 3.2,
            // 🔴 **不能是 nil。** `RunPlanFormat.shortStart(nil)` 返回 nil ⇒ 那行大字退回
            // fallback「新的陪跑邀请」，于是调试预置永远看不到真实版式（28pt 的「明天 7:00」），
            // 而那正是这张卡的主角。2026-09-18 项目负责人的截图就是这么来的。
            plannedStart: Self.uiTestSeedPlannedStart(now: now),
            plannedEnd: nil,
            dispatchTimeoutSeconds: 120,
            priority: "HIGH",
            pacePreference: "MODERATE",
            hasGuideDog: false,
            requiresIntroCall: true,
            paceMinSecondsPerKm: 390,
            paceMaxSecondsPerKm: 450,
            plannedDistanceMeters: 5_000,
            blindName: "李*"  // 后端恒下发掩码名（#357）；种子带上它，UI 用例才验得到读屏去星号（#339）
        )
    }

    /// 明天 07:00，写成后端那种**无时区的 `LocalDateTime`** 串（`String.backendLocalDate` 认的形状）。
    ///
    /// 用「明天」而不是写死某一天：`RunPlanFormat.shortStart` 只对今天 / 明天 / 后天给相对日期，
    /// 写死的日期过几天就退化成「9月18日 7:00」，而调试预置要看的恰恰是「明天 7:00」那一版。
    private static func uiTestSeedPlannedStart(now: Date) -> String {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let at7 = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        return DateFormatter.aidRunBackendLocalDateTime.string(from: at7)
    }
    #endif
}
