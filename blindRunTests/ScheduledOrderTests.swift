import XCTest
@testable import blindRun

/// 跨天预约单（`SCHEDULED_CONFIRMED`，后端迁移 `0041`）。
///
/// 这一组钉的是**漏了不会红、只会静默出错**的那几处：手写的 `allCases`、
/// 对账图的边、query 有没有被拼进路径、志愿者那对动作还在不在。
/// 「12 处穷举 switch 有没有覆盖新 case」不在这里 —— 那个由编译器管，写用例是重复劳动。
final class ScheduledOrderTests: XCTestCase {

    // MARK: - 端点

    /// `confirm-departure` 与 `en-route` 是**两条**端点。
    ///
    /// 后端契约逐字点了这一条：合并会让位置互推提前几小时打开，而那期间双方并不需要找到对方。
    /// 这里只钉「没被合并、路径没写错」，路径本身与契约的对撞由
    /// `scripts/validate-spec-coverage.mjs` 负责。
    func testConfirmDepartureIsItsOwnEndpointAndNotEnRoute() {
        let confirm = OrderEndpoint.confirmDeparture(orderId: 42).request
        let enRoute = OrderEndpoint.enRoute(orderId: 42).request

        XCTAssertEqual(confirm.method, .post)
        XCTAssertEqual(confirm.path, "/api/orders/42/confirm-departure")
        XCTAssertNotEqual(confirm.path, enRoute.path, "两条端点合并会让位置互推提前几小时打开")
    }

    /// 🚩 预约单列表的 query **必须走 `query:` 参数，不能拼进路径**。
    ///
    /// 拼进去有两个各自致命的后果：`APIClient.request` 用 `appendingPathComponent`，
    /// `?` 会被编码成 `%3F` ⇒ 打出一条 404，而客户端只看到「请求的资源不存在」；
    /// 且 `validate-spec-coverage.mjs` 扫引号里的整串、不剥 query ⇒ 契约门禁当场红。
    func testScheduledOrdersSendsFiltersAsQueryNotInThePath() async throws {
        let transport = RecordingTransport()
        transport.nextResponse = PagedOrderResponse(
            content: [], totalElements: 0, totalPages: 0,
            number: 0, size: 20, first: true, last: true, empty: true
        )
        let service = OrderService(transport: transport)

        _ = try await service.scheduledOrders()

        let recorded = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(recorded.method, .get)
        XCTAssertEqual(recorded.path, "/api/orders/mine", "query 一个字符都不许出现在 path 里")
        XCTAssertFalse(recorded.path.contains("?"), "拼进 path 的 `?` 会被编码成 %3F，打出一条静默 404")
        XCTAssertEqual(recorded.query?["role"], "VOLUNTEER")
        XCTAssertEqual(recorded.query?["status"], "SCHEDULED_CONFIRMED")
    }

    // MARK: - 状态机

    /// 三条入边、三条出边，逐字取自后端 `OrderStatus.canTransitionTo`。
    ///
    /// 走 `reconcileRealtime` 而不是那张私有的后继表：这里要保证的是**一条真实的 WS 迁移
    /// 会被放行**，不是那张表长什么样。放行不了的症状是订单页停在旧状态且不报错。
    func testScheduledConfirmedSitsOnTheEdgesTheBackendDeclares() {
        var orderID: Int64 = 100

        for entry in [RunOrderStatus.pendingMatch, .pendingIntroCall, .rematching] {
            orderID += 1
            var reconciler = OrderStatusReconciler()
            reconciler.register(orderID: orderID, status: entry)
            XCTAssertEqual(
                reconciler.reconcileRealtime(orderID: orderID, fromStatus: entry, toStatus: .scheduledConfirmed),
                .applied(.scheduledConfirmed),
                "\(entry.rawValue) → SCHEDULED_CONFIRMED 是后端明写的迁移，对账拒了它订单页就停在旧状态"
            )
        }

        for exit in [RunOrderStatus.pendingAccept, .rematching, .cancelled] {
            orderID += 1
            var reconciler = OrderStatusReconciler()
            reconciler.register(orderID: orderID, status: .scheduledConfirmed)
            XCTAssertEqual(
                reconciler.reconcileRealtime(orderID: orderID, fromStatus: .scheduledConfirmed, toStatus: exit),
                .applied(exit),
                "SCHEDULED_CONFIRMED → \(exit.rawValue) 是后端明写的迁移"
            )
        }
    }

    /// 🚩 `SCHEDULED_CONFIRMED` **没有** `→ NO_VOLUNTEER` 这条直接边。
    ///
    /// 后端注释逐字写着：人已经定下来了，「无人接单」在这一态不是可能的结局；
    /// 真没人了要先退回 `REMATCHING` 再由派单窗口判。
    ///
    /// ⚠️ 走 `reconcileRealtime` 而不是 `canReach` —— 前者判的是**直接后继**
    /// （WS 推来的那条 `fromStatus → toStatus` 合不合法），后者判可达性，
    /// 而 `NO_VOLUNTEER` 经 `REMATCHING` 中转是可达的。用 `canReach` 写这条会得到一个
    /// 必然失败的用例，而失败的原因和它想说的事没关系。
    func testScheduledConfirmedNeverGoesStraightToNoVolunteer() {
        var reconciler = OrderStatusReconciler()
        reconciler.register(orderID: 1, status: .scheduledConfirmed)

        let bogus = reconciler.reconcileRealtime(
            orderID: 1, fromStatus: .scheduledConfirmed, toStatus: .noVolunteer
        )
        XCTAssertEqual(
            bogus,
            .rejectedInvalid(current: .scheduledConfirmed, candidate: .noVolunteer),
            "这一态人已经定了，`无人接单` 不是可能的结局"
        )

        var other = OrderStatusReconciler()
        other.register(orderID: 2, status: .scheduledConfirmed)
        XCTAssertEqual(
            other.reconcileRealtime(orderID: 2, fromStatus: .scheduledConfirmed, toStatus: .rematching),
            .applied(.rematching),
            "闸门错过 / 志愿者取消走的是这条"
        )
    }

    /// `REMATCHING → SCHEDULED_CONFIRMED` 不能被「倒退即陈旧」那条规则丢掉。
    ///
    /// 这是给 `lifecycleRank` 的钉子：给 `SCHEDULED_CONFIRMED` 排 0（与 `pendingMatch` 同档）
    /// 看起来很自然，但 `rematching` 是 1，于是这条**真实**迁移（重新派单后被一张远期单接走）
    /// 会被判成陈旧结果丢掉，订单页永远停在「重新匹配中」。
    /// 与 `pendingIntroCall` 那条注释踩过的是同一个坑。
    func testARematchedOrderCanBeTakenByAFarFutureBooking() {
        var reconciler = OrderStatusReconciler()
        let orderID: Int64 = 7
        reconciler.register(orderID: orderID, status: .rematching)

        let token = reconciler.requestToken(orderID: orderID)
        let result = reconciler.reconcileREST(orderID: orderID, candidate: .scheduledConfirmed, token: token)

        XCTAssertEqual(
            result,
            .applied(.scheduledConfirmed),
            "REMATCHING → SCHEDULED_CONFIRMED 被拒了，多半是 lifecycleRank 给低了"
        )
    }

    // MARK: - 志愿者端动作

    /// 确认与释放**并置**，且不给导航。
    ///
    /// 并置的依据是志愿者排班软件的 confirm-or-release：释放做得难只会把 no-show 从
    /// 「提前告知」变成「当天失联」（`docs/research/volunteer-scheduled-order-confirm-ui-20260906.md`）。
    /// 不给导航是因为距开跑还有 1–7 天，它会和确认抢同一块视觉重量。
    func testVolunteerGetsConfirmAndReleaseSideBySideWithNoNavigation() {
        let kinds = VolunteerServiceActions.actionKinds(for: .scheduledConfirmed)

        XCTAssertEqual(kinds, [.confirmDeparture, .releaseScheduled])
        XCTAssertFalse(kinds.contains(.navigateToStart), "距开跑 1–7 天，导航是噪音")
        XCTAssertFalse(kinds.isEmpty, "空数组 = 收到确认通知却没有入口，这一单 60 分钟后会被转走")
    }

    /// 「我去不了」与「取消订单」是**两个文案**。
    ///
    /// 对志愿者，「取消订单」读起来像在替盲人取消这一单，而实际后果是「回派单池换个人」。
    ///
    /// ⚠️ **这条只覆盖按钮标题，覆盖不到确认对话框。** 对话框那四句在
    /// `VolunteerInServiceView.cancelDialogCopy`（View 的 private 计算属性，测试够不着），
    /// 而它才是志愿者真正下决心的那一屏 —— 那里曾经仍写着「确认取消本次预约？」，
    /// 让这次改名等于没做，而本条用例当时是绿的。改按钮文案时请连着人眼看一遍对话框。
    func testReleaseAndCancelDoNotShareCopy() {
        XCTAssertNotEqual(
            VolunteerServiceActionKind.releaseScheduled.title,
            VolunteerServiceActionKind.cancelOrder.title
        )
    }

    // MARK: - 夜间禁跑窗口（后端 N134）

    /// 判据是**整段**行程，不是开始时刻。四个边界逐字取自后端契约的例子。
    func testNightWindowIsJudgedOnTheWholeTripNotTheStartInstant() {
        func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            var components = DateComponents()
            components.year = 2026
            components.month = 9
            components.day = day
            components.hour = hour
            components.minute = minute
            return Calendar.current.date(from: components)!
        }

        // 21:00–22:30 拒：尾巴进了夜间。
        XCTAssertTrue(BlindBookingViewModel.overlapsNightWindow(start: at(10, 21), end: at(10, 22, 30)))
        // 21:00–22:00 放行：恰好 22:00 结束不算重叠。
        XCTAssertFalse(BlindBookingViewModel.overlapsNightWindow(start: at(10, 21), end: at(10, 22)))
        // 05:00–06:00 放行：恰好 05:00 开始不算重叠。
        XCTAssertFalse(BlindBookingViewModel.overlapsNightWindow(start: at(10, 5), end: at(10, 6)))
        // 次日 04:00–06:00 拒：凌晨 4 点属于**前一天**那扇窗口 —— 这条正是只扫当天会漏的。
        XCTAssertTrue(BlindBookingViewModel.overlapsNightWindow(start: at(10, 4), end: at(10, 6)))
        // 完全在白天。
        XCTAssertFalse(BlindBookingViewModel.overlapsNightWindow(start: at(10, 9), end: at(10, 10)))
    }

}
