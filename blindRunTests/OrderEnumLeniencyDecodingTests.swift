import XCTest
@testable import blindRun

/// 「后端新增一个枚举值」不得让整条响应解不出。
///
/// 这条崩法不直观，值得写死：Swift 合成的 `decodeIfPresent` 只对**字段缺失 / 值为 null**宽容，
/// 对「值存在但本客户端不认识」会抛 `DecodingError.dataCorrupted`，
/// 而 `KeyedDecodingContainer` 的错误会一路冒泡，把**同一个对象里其它所有字段**一起带走。
/// 也就是说后端往订单状态机里加一个 `PAUSED`，iOS 这边不是「状态显示不出来」，
/// 而是**整张订单详情页空白**。
///
/// 修法是在枚举层给 `RunOrderStatus` / `PacePreference` / `RoutePreference` 加 `.unknown`
/// 兜底 + 自定义 `init(from:)`，而不是逐个字段改成 `String` + 映射 ——
/// 这三个枚举一共有 8 处解码点，改枚举一次全覆盖。
///
/// 用例走 `APIPayloadDecoder.decodePayload`，与线上同一条解码策略。
///
/// 文件末尾还钉着这条宽容的**边界**：认不出的取值降级，没给的必填字段必须抛。
/// 两个方向放在一起，是因为分开写的结果已经出现过 —— 见
/// `testPagedOrderResponseRejectsABareArrayInsteadOfSilentlyReturningAnEmptyPage`。
final class OrderEnumLeniencyDecodingTests: XCTestCase {

    private let decoder = JSONDecoder()

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try APIPayloadDecoder.decodePayload(type, from: Data(json.utf8), decoder: decoder)
    }

    // MARK: - RunOrderStatus（订单主干，非可选字段）

    /// `OrderDetailResponse.status` 是**非可选**的 `RunOrderStatus`，
    /// 不认识的状态过去会让整页数据（地址、坐标、电话、计划时间）一起丢掉。
    func testOrderDetailSurvivesAnUnknownBackendStatus() throws {
        let detail = try decode(OrderDetailResponse.self, """
        {
          "orderId": 4201,
          "status": "PAUSED_BY_BACKEND",
          "startAddress": "北京市海淀区中关村大街1号",
          "startLatitude": 39.98,
          "startLongitude": 116.31,
          "plannedStart": "2026-08-01T09:00:00",
          "blindPhone": "13800000000",
          "pacePreference": "MODERATE"
        }
        """)

        XCTAssertEqual(detail.status, .unknown)
        // 真正要守的是这几行：兄弟字段必须完好，否则页面整块空白。
        XCTAssertEqual(detail.orderId, 4201)
        XCTAssertEqual(detail.startAddress, "北京市海淀区中关村大街1号")
        XCTAssertEqual(detail.startLatitude, 39.98)
        XCTAssertEqual(detail.blindPhone, "13800000000")
        XCTAssertEqual(detail.pacePreference, .moderate)
    }

    /// 「打电话给志愿者」是接单后唯一的主动作，它的开放范围要逐状态钉住。
    ///
    /// 陪跑没有车牌 / 车型 / 颜色，这通电话是视障者确认「眼前这人是不是我的志愿者」的唯一手段
    /// （`docs/research/blind-ui-visual-benchmark-20260808.md` §3.2）。给少了盲人找不到人；
    /// 给多了会在订单已结束、或那个志愿者已不是本单参与者时，诱导一通没有理由的外呼。
    func testVolunteerCallOpensOnlyWhenMeetingUpIsStillAhead() {
        for status in [RunOrderStatus.pendingAccept, .driverEnRoute, .driverArrived, .inProgress] {
            XCTAssertTrue(
                status.offersVolunteerCall,
                "\(status.rawValue) 需要当面汇合，必须给出拨号入口"
            )
        }

        for status in [RunOrderStatus.pendingMatch, .rematching, .noVolunteer, .completed, .cancelled, .unknown] {
            XCTAssertFalse(
                status.offersVolunteerCall,
                "\(status.rawValue) 下不存在「本单的志愿者」或订单已结束，不得给拨号入口"
            )
        }

        XCTAssertEqual(
            RunOrderStatus.allCases.filter(\.offersVolunteerCall).count,
            4,
            "枚举加了新状态就要在这里做一次决策，不能默默落到 false"
        )
    }

    /// 未知状态**不得**被当成已结束，也不得触发任何破坏性操作入口。
    func testUnknownStatusIsNotTerminalAndUnlocksNothing() {
        let status = RunOrderStatus.unknown

        XCTAssertFalse(status.isTerminal, "认不出的状态不等于订单结束")
        XCTAssertTrue(status.shouldPoll, "继续轮询才能在状态推进到认识的值时自愈")
        XCTAssertEqual(status.blindRunnerRoute, .tracking, "落到只读跟踪页，不给破坏性操作")
        XCTAssertFalse(status.canBlindRunnerCancel)
        XCTAssertFalse(status.canVolunteerCancel)
        XCTAssertFalse(status.canStartService)
        XCTAssertFalse(status.canFinishService)
        XCTAssertFalse(status.canBlindRunnerTriggerEmergency)
        XCTAssertFalse(status.canVolunteerTriggerEmergency)
        XCTAssertFalse(
            status.disclosesBlindRunnerNotesToVolunteer,
            "隐私边界对未知值要**关**，方向与本文件其他兜底相反：那些取「当作进行中」是为了不让订单从界面消失"
        )
    }

    /// 盲人填的自由文本（`specialNotes` 特殊说明 / `routeNotes` 路线备注）
    /// 只在接单后对志愿者可见（`AGENTS.md §8`；`routeNotes` 于 2026-08-07 一并收进同一条闸）。
    ///
    /// 逐个状态钉死而不是只测两三个，是因为这条闸的漏法就是「新加一个状态忘了归类」。
    /// `PENDING_MATCH` 是派单弹窗与「可接订单」列表那一刻的状态 —— 全 App 最该关的一处；
    /// `REMATCHING` 是原志愿者取消后，他已经不是这一单的参与者了。
    func testBlindRunnerNotesAreDisclosedOnlyAfterAVolunteerHasAccepted() {
        let hidden: [RunOrderStatus] = [.pendingMatch, .rematching, .noVolunteer]
        let disclosed: [RunOrderStatus] = [.pendingAccept, .driverEnRoute, .driverArrived, .inProgress, .completed, .cancelled]

        for status in hidden {
            XCTAssertFalse(
                status.disclosesBlindRunnerNotesToVolunteer,
                "\(status.rawValue) 是接单前（或志愿者已退出），不得展示盲人自由文本"
            )
        }
        for status in disclosed {
            XCTAssertTrue(
                status.disclosesBlindRunnerNotesToVolunteer,
                "\(status.rawValue) 时志愿者已是参与者，藏起备注反而让他执行不了盲人交代的事"
            )
        }
        // 加了新状态就必须回来把它归进上面两组之一，别让它悄悄跟着 `.unknown` 走。
        XCTAssertEqual(hidden.count + disclosed.count, RunOrderStatus.allCases.count)
    }

    /// `.unknown` 不是真实状态，不得混进状态机遍历或任何选项列表。
    func testUnknownIsExcludedFromAllCases() {
        XCTAssertFalse(RunOrderStatus.allCases.contains(.unknown))
        XCTAssertFalse(PacePreference.allCases.contains(.unknown))
        XCTAssertFalse(RoutePreference.allCases.contains(.unknown))
        XCTAssertEqual(RunOrderStatus.allCases.count, 9)
    }

    /// `OrderResponse.status` 是**可选**的 —— 可选并不带来宽容，这正是这一整类问题的由来。
    func testOrderCreateResponseSurvivesAnUnknownStatus() throws {
        let response = try decode(OrderResponse.self, #"{"id":77,"status":"QUEUED_V2","success":true}"#)

        XCTAssertEqual(response.id, 77, "下单返回的 orderId 丢了等于这一单彻底跟丢")
        XCTAssertEqual(response.status, .unknown)
        XCTAssertEqual(response.success, true)
    }

    /// 缺失 / null 的行为不能被改动带偏：仍然是 nil，不是 `.unknown`。
    func testAbsentAndNullStatusStayNil() throws {
        XCTAssertNil(try decode(OrderResponse.self, #"{"id":78,"success":true}"#).status)
        XCTAssertNil(try decode(OrderResponse.self, #"{"id":79,"status":null}"#).status)
    }

    /// 志愿者实时位置：状态解不出会让盲人侧地图上的志愿者整个消失。
    func testVolunteerLocationSurvivesAnUnknownStatus() throws {
        let payload = try decode(VolunteerLocationResponse.self, """
        {"success":true,"data":{"orderId":42,"status":"EN_ROUTE_V2","lat":39.9,"lng":116.4}}
        """)

        let data = try XCTUnwrap(payload.data)
        XCTAssertEqual(data.status, .unknown)
        XCTAssertTrue(data.coordinateIsValid, "坐标必须还在，否则地图上志愿者直接不见")
    }

    /// 派单概览是志愿者首页的主干列表，一条订单的新状态不得让整个列表解不出。
    func testDispatchSummaryActiveOrderSurvivesAnUnknownStatus() throws {
        let order = try decode(VolunteerDispatchSummaryActiveOrder.self, """
        {"orderId":301,"status":"HANDOVER","startAddress":"朝阳公园南门","blindName":"李四"}
        """)

        XCTAssertEqual(order.status, .unknown)
        XCTAssertEqual(order.orderId, 301)
        XCTAssertEqual(order.blindName, "李四")
    }

    // MARK: - Pace / Route（跨端共享词表，进出双向）

    /// 偏好词表是安卓/后台共用的：别的端下单时用了 iOS 不认识的取值，
    /// iOS 志愿者读订单详情就会整页解不出。
    func testOrderDetailSurvivesUnknownPreferenceValues() throws {
        let detail = try decode(OrderDetailResponse.self, """
        {
          "orderId": 4202,
          "status": "IN_PROGRESS",
          "pacePreference": "SPRINT",
          "routePreference": "BEACH",
          "routeNotes": "沿河道跑"
        }
        """)

        XCTAssertEqual(detail.status, .inProgress)
        XCTAssertEqual(detail.pacePreference, .unknown)
        XCTAssertEqual(detail.routePreference, .unknown)
        XCTAssertEqual(detail.routeNotes, "沿河道跑")
    }

    func testBlindProfileSurvivesAnUnknownDefaultPace() throws {
        let profile = try decode(BlindProfileResponse.self, """
        {"name":"王五","defaultPace":"ULTRA","verifyStatus":"VERIFIED"}
        """)

        XCTAssertEqual(profile.name, "王五")
        XCTAssertEqual(profile.defaultPace, .unknown)
        XCTAssertEqual(profile.identityStatus, .verified, "实名门槛不能被一个配速取值带崩")
    }

    /// `.unknown` **绝不能被原样发回后端** —— 这三个枚举是双向的，
    /// 读到的未知值会经由资料更新/下单请求再发出去。编码成 null 等价于「没填」。
    func testUnknownPreferenceEncodesAsNullNotAsABogusString() throws {
        let request = CreateOrderRequest(
            startLatitude: 39.9,
            startLongitude: 116.4,
            startAddress: "测试地址",
            plannedStartTime: "2026-08-01T09:00:00",
            plannedEndTime: "2026-08-01T10:00:00",
            expectedDurationMinutes: 60,
            pacePreference: .unknown,
            routePreference: .unknown,
            routeNotes: nil,
            hasGuideDogThisRun: nil,
            specialNotes: nil
        )

        let encoded = String(data: try JSONEncoder().encode(request), encoding: .utf8) ?? ""

        XCTAssertFalse(encoded.contains("UNKNOWN"), "把认不出的取值发回后端只会换来一个 400")
        XCTAssertTrue(encoded.contains("\"pacePreference\":null"))
        XCTAssertTrue(encoded.contains("\"routePreference\":null"))
    }

    /// 已知取值的编码不能被兜底逻辑改坏。
    func testKnownPreferenceStillEncodesItsRawValue() throws {
        let encoded = String(data: try JSONEncoder().encode([PacePreference.moderate]), encoding: .utf8)
        XCTAssertEqual(encoded, #"["MODERATE"]"#)
    }

    /// 绑定选择器时未知取值回落到「无偏好」：否则 SwiftUI 找不到匹配 tag 会渲染空白项，
    /// VoiceOver 什么都读不出来 —— 在一个盲人应用里这比显示错误更糟。
    func testUnknownPreferenceFallsBackToNoPreferenceForPickers() {
        XCTAssertEqual(PacePreference.unknown.selectable, .noPreference)
        XCTAssertEqual(RoutePreference.unknown.selectable, .noPreference)
        XCTAssertEqual(PacePreference.fast.selectable, .fast)
    }

    // MARK: - 宽容的边界：认不出的**取值**降级，没给的**字段**必须抛

    /// 这两条和上面所有用例的方向相反，放在同一个文件里就是为了让边界看得见。
    ///
    /// `PagedOrderResponse` 曾有一个「宽容解码器」：先试对象、再试裸数组、
    /// 最后无条件返空页且不抛。于是 `GET /api/orders/available` 的真实响应
    /// （`AvailableOrderResponse` 裸数组，元素没有 `status`，而 `OrderDetailResponse.status`
    /// 是非可选的）被静默解成空列表 —— 屏幕上写着「暂无可用订单」，
    /// 谁也看不出错，从 2026-05-24 一直挂着。
    ///
    /// 所以这里钉的不是「解不出」，是「解不出时必须**吵**」。

    /// 裸数组（即旧 `/api/orders/available` 的形状）不得被吞成空页。
    func testPagedOrderResponseRejectsABareArrayInsteadOfSilentlyReturningAnEmptyPage() {
        let bareArray = """
        [{"orderId": 4201, "startAddress": "北京市海淀区中关村大街1号", "distanceKm": 1.2}]
        """

        XCTAssertThrowsError(try decode(PagedOrderResponse.self, bareArray)) { error in
            XCTAssertTrue(
                error is DecodingError,
                "形状不符必须抛 DecodingError，让调用方走到「加载失败」而不是「暂无订单」，实收 \(error)"
            )
        }
    }

    /// 元素缺非可选的 `status` 时整条要抛，不得把那一条悄悄丢掉后返回一个短列表 ——
    /// 「少了几单」比「一单都没有」更难被发现。
    func testPagedOrderResponseRejectsAnElementMissingItsRequiredStatus() {
        let missingStatus = """
        {"content": [{"orderId": 4201, "startAddress": "北京市海淀区中关村大街1号"}]}
        """

        XCTAssertThrowsError(try decode(PagedOrderResponse.self, missingStatus))
    }

    /// 反向锁：合法的分页响应仍要正常解出，且**可选**字段缺失依旧宽容 ——
    /// 收紧的只是必填字段，别把整条策略收成一刀切。
    func testPagedOrderResponseStillDecodesAValidPageWithOptionalFieldsAbsent() throws {
        let page = try decode(PagedOrderResponse.self, """
        {"content": [{"orderId": 4201, "status": "PENDING_MATCH"}]}
        """)

        XCTAssertEqual(page.content.count, 1)
        XCTAssertEqual(page.content.first?.status, .pendingMatch)
        XCTAssertNil(page.totalElements)
        XCTAssertNil(page.empty)
    }
}
