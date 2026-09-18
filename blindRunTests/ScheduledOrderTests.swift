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

        _ = try await service.volunteerOrders(status: .scheduledConfirmed)

        let recorded = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(recorded.method, .get)
        XCTAssertEqual(recorded.path, "/api/orders/mine", "query 一个字符都不许出现在 path 里")
        XCTAssertFalse(recorded.path.contains("?"), "拼进 path 的 `?` 会被编码成 %3F，打出一条静默 404")
        XCTAssertEqual(recorded.query?["role"], "VOLUNTEER")
        XCTAssertEqual(recorded.query?["status"], "SCHEDULED_CONFIRMED")

        // 第二档走的是**同一条路径、同一组 query 键**，只有 status 取值不同 ——
        // 这正是「一次只能问一个状态」（后端 `parseOrderStatus` 只收单值）的形状。
        _ = try await service.volunteerOrders(status: .pendingAccept)
        let second = try XCTUnwrap(transport.requests.last)
        XCTAssertEqual(second.path, "/api/orders/mine")
        XCTAssertEqual(second.query?["status"], "PENDING_ACCEPT")
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
    /// ⚠️ **这条只覆盖按钮标题。** 确认层那几句已经搬到
    /// `VolunteerOrderFlowCopy.cancelSheet(for:plannedStart:)`，由
    /// `VolunteerOrderFlowPresentationTests.testReleaseRowAndItsConfirmationSheetShareTheConsequence`
    /// 与 `testCancelSheetNeverAnnouncesAPenaltyTheBackendDoesNotHave` 两条钉住 ——
    /// 它此前是 View 的 private 计算属性、测试够不着，于是按钮改了词而弹层里
    /// 仍写着「确认取消本次预约？」，本条用例当时是绿的。
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

    // MARK: - 打开 App 的三岔路（设计交付 v3 §4.1）

    /// 在途订单优先于任何预约单。
    ///
    /// 两个来源各管一半、**不能合并成一个列表**：`activeOrder` 来自
    /// `dispatch-summary.activeOrders`（后端白名单只有陪跑中那三态），跨天预约单只在
    /// `GET /api/orders/mine` 里。合并的话，志愿者正在陪跑、而三天后还有一张预约单时，
    /// 打开 App 进的是哪一张就取决于两条请求谁先回来。
    func testLaunchOpensTheActiveOrderBeforeAnyScheduledOne() {
        let now = Date()
        let picked = VolunteerHomeViewModel.launchOrderToOpen(
            activeOrder: Self.makeOrder(id: 1, status: .inProgress, startingIn: nil, now: now),
            scheduledOrders: [Self.makeOrder(id: 2, status: .scheduledConfirmed, startingIn: 30 * 60, now: now)],
            now: now
        )

        XCTAssertEqual(picked?.orderId, 1, "人正在陪跑，打开 App 该回到那一单")
    }

    /// 2 小时这条线的**两侧各一条**。
    ///
    /// 🚩 少了任何一条，这组用例都分辨不出阈值被改成了别的数：只验 1 小时 59 分的话，
    /// 把提前量偷偷放宽到一整天照样全绿。所以取的是恰好落在两种实现之间的那对值。
    func testLaunchOpensAScheduledRunJustInsideTheLeadWindowButNotJustOutside() {
        let now = Date()
        let inside = Self.makeOrder(id: 11, status: .scheduledConfirmed, startingIn: 119 * 60, now: now)
        let outside = Self.makeOrder(id: 12, status: .scheduledConfirmed, startingIn: 121 * 60, now: now)

        XCTAssertEqual(
            VolunteerHomeViewModel.launchOrderToOpen(activeOrder: nil, scheduledOrders: [inside], now: now)?.orderId,
            11,
            "距开跑 1 小时 59 分，打开 App 该直接进订单页"
        )
        XCTAssertNil(
            VolunteerHomeViewModel.launchOrderToOpen(activeOrder: nil, scheduledOrders: [outside], now: now),
            "距开跑 2 小时 01 分还早，把人直接推进订单页等于抢走了主页"
        )
    }

    /// 已经过点还没走的**算在内**。
    ///
    /// 写成 `0..<lead` 的区间判定会把它漏掉，而那正是最该打开订单页的一刻 ——
    /// 盲人已经在集合点等着了。
    func testLaunchStillOpensAScheduledRunThatShouldHaveStartedAlready() {
        let now = Date()
        let overdue = Self.makeOrder(id: 13, status: .scheduledConfirmed, startingIn: -20 * 60, now: now)

        XCTAssertEqual(
            VolunteerHomeViewModel.launchOrderToOpen(activeOrder: nil, scheduledOrders: [overdue], now: now)?.orderId,
            13,
            "开跑时间已经过了 20 分钟，这一单比任何还没到点的都更该打开"
        )
    }

    /// 解析不出开跑时间的不猜。
    ///
    /// 宁可让他自己从首页点进去，也不要凭空把人推进一张可能几天后才开始的单 ——
    /// 而「时间串解析不了」时两种可能都存在，客户端分不出是哪一种。
    func testLaunchSkipsAScheduledRunWhoseStartTimeCannotBeParsed() {
        let broken = Self.makeOrder(id: 14, status: .scheduledConfirmed, startingIn: nil, now: Date())

        XCTAssertNil(
            VolunteerHomeViewModel.launchOrderToOpen(activeOrder: nil, scheduledOrders: [broken]),
            "开跑时间是 nil 还照样打开，等于凭时间以外的东西猜"
        )
    }

    /// 🚨 **这道闸不是优化，没有它就是一个出不来的导航循环。**
    ///
    /// 判据读的 `activeOrder` 每 10 秒刷新一次都还在 —— 志愿者从订单页返回首页，
    /// 下一次刷新立刻把他推回去。和 `autoOpenedIntroCallOrderId` 防的是同一件事。
    @MainActor
    func testLaunchRouteIsResolvedOnlyOnceSoBackingOutOfTheOrderPageSticks() {
        let viewModel = VolunteerHomeViewModel()
        let summary = Self.makeSummaryWithActiveOrder(orderId: 21)

        viewModel.apply(summary: summary)
        XCTAssertEqual(viewModel.acceptedDispatchOrderId, 21, "冷启动没有直接打开在途订单")

        // 用户按返回键退出订单页 —— 首页那条 `navigationDestination` 的 setter 做的就是这个。
        viewModel.acceptedDispatchOrderId = nil
        viewModel.acceptedDispatchInitialOrder = nil

        viewModel.apply(summary: summary)
        XCTAssertNil(
            viewModel.acceptedDispatchOrderId,
            "第二次刷新又把他推回订单页了 —— 这样他在订单走完之前回不到主页"
        )
    }

    // MARK: - Fixtures

    private static func makeOrder(
        id: Int64,
        status: RunOrderStatus,
        startingIn: TimeInterval?,
        now: Date = Date()
    ) -> OrderDetailResponse {
        OrderDetailResponse(
            orderId: id,
            status: status,
            startAddress: "深圳湾公园 3 号入口",
            startLatitude: nil,
            startLongitude: nil,
            endAddress: nil,
            endLatitude: nil,
            endLongitude: nil,
            plannedStart: startingIn.map {
                DateFormatter.aidRunBackendLocalDateTime.string(from: now.addingTimeInterval($0))
            },
            plannedEnd: nil,
            blindName: nil,
            blindPhone: nil,
            volunteerPhone: nil,
            acceptedAt: nil,
            createdAt: nil,
            expectedDurationMinutes: nil,
            pacePreference: nil,
            routePreference: nil,
            routeNotes: nil,
            hasGuideDogThisRun: nil,
            specialNotes: nil,
            visionLevel: nil,
            tetherPreference: nil,
            chatPreference: nil
        )
    }

    private static func makeSummaryWithActiveOrder(orderId: Int64) -> VolunteerDispatchSummaryResponse {
        VolunteerDispatchSummaryResponse(
            canDispatch: true,
            notAvailableReasons: [],
            wantsDispatch: true,
            isOnline: true,
            lastLat: nil,
            lastLng: nil,
            lastLocationAt: nil,
            coverageRadiusKm: nil,
            isWithinServiceTime: true,
            availableTimeSlots: nil,
            avgRating: nil,
            totalRatings: nil,
            totalDispatched: nil,
            totalAccepted: nil,
            totalDeclined: nil,
            totalTimeout: nil,
            totalCompleted: nil,
            totalCancelled: nil,
            acceptanceRate: nil,
            activeOrders: [
                VolunteerDispatchSummaryActiveOrder(
                    orderId: orderId,
                    status: .inProgress,
                    plannedStartTime: nil,
                    plannedEndTime: nil,
                    startAddress: "深圳湾公园 3 号入口",
                    startLatitude: nil,
                    startLongitude: nil,
                    blindName: nil,
                    blindPhoneMasked: nil,
                    acceptedAt: nil
                )
            ],
            recentOrders: nil,
            introCallOrderId: nil
        )
    }
}
