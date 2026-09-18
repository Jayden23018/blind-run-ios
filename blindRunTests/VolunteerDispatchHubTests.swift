import CoreGraphics
import XCTest
@testable import blindRun

/// 接单主页（设计交付文档 v3 的 S3/S4）与双向滑块的判据。
///
/// 这里的每一条守的都是「**坏了也看不出来**」的那一类：
/// 取错一张单，屏幕上照样是一张正常的深蓝卡；阈值改错，滑块照常能滑；
/// 时间段格式写错，`PUT` 照样返回 200。
final class VolunteerDispatchHubTests: XCTestCase {

    // MARK: - 左滑阈值

    /// 向左停止接单取 **35%**，比向右开启的 20% 高。
    ///
    /// 🔴 **关键的是中间那个取值 0.25**：它在右滑下成立、在左滑下不成立。
    /// 随手取「滑 5%」和「滑 90%」的话，把 `deactivationFraction` 改回 0.2
    /// 这两条**照样通过** —— 那样的用例分辨不出两侧阈值被拉平，
    /// 而拉平的真实后果是一次边缘返回手势就把接单关掉（左滑正是系统返回手势的方向）。
    func testStopThresholdSitsHigherThanTheStartThreshold() {
        let trackWidth: CGFloat = 200
        let quarter: CGFloat = 50 // 25%

        XCTAssertTrue(
            VolunteerAvailabilitySlide.activates(dragX: quarter, trackWidth: trackWidth),
            "右滑 25% 应当开启（阈值 20%）"
        )
        XCTAssertFalse(
            VolunteerAvailabilitySlide.deactivates(dragX: -quarter, trackWidth: trackWidth),
            "左滑 25% 就停止 —— 停止阈值被拉到和开启一样低了，边缘返回手势会误关"
        )
        XCTAssertTrue(
            VolunteerAvailabilitySlide.deactivates(dragX: -71, trackWidth: trackWidth),
            "左滑 35.5% 还不停止 —— 停止阈值被调得更高了"
        )
        XCTAssertGreaterThan(
            VolunteerAvailabilitySlide.deactivationFraction,
            VolunteerAvailabilitySlide.activationFraction,
            "停止那一侧必须比开启更难触发"
        )
    }

    /// 方向不能串：右滑不触发停止，左滑不触发开启。
    func testDirectionsDoNotLeakIntoEachOther() {
        let trackWidth: CGFloat = 200
        XCTAssertFalse(
            VolunteerAvailabilitySlide.deactivates(dragX: 190, trackWidth: trackWidth),
            "一路向右拖不该被当成停止接单"
        )
        XCTAssertFalse(
            VolunteerAvailabilitySlide.activates(dragX: -190, trackWidth: trackWidth),
            "一路向左拖不该被当成开启接单"
        )
        XCTAssertEqual(VolunteerAvailabilitySlide.leftTravel(dragX: 80, trackWidth: 200), 0)
        XCTAssertEqual(VolunteerAvailabilitySlide.leftTravel(dragX: -9_999, trackWidth: 200), 200)
        XCTAssertEqual(VolunteerAvailabilitySlide.leftTravel(dragX: .nan, trackWidth: 200), 0)
        for width in [CGFloat(0), -120, .nan, .infinity] {
            XCTAssertFalse(VolunteerAvailabilitySlide.deactivates(dragX: -999, trackWidth: width))
        }
    }

    // MARK: - 这一屏显示哪一张单

    /// 正在进行的那一单永远排在预约单前面。
    ///
    /// 判 false 的后果不是「顺序不好看」：陪跑已经开始了，而屏幕最上面顶着一张三天后的预约单。
    func testActiveOrderOutranksScheduledOnes() {
        let active = OrderDetailResponse.preview(orderId: 77, status: .inProgress)
        let scheduled = [
            OrderDetailResponse.preview(orderId: 1, status: .scheduledConfirmed),
            OrderDetailResponse.preview(orderId: 2, status: .scheduledConfirmed)
        ]

        let content = VolunteerDispatchHubContent.resolve(activeOrder: active, scheduledOrders: scheduled)

        XCTAssertEqual(content.next?.orderId, 77)
        XCTAssertEqual(content.laterCount, 2, "进行中那一单不占预约列表的名额，两张都算「之后」")
        XCTAssertEqual(
            VolunteerDispatchHubContent.later(activeOrder: active, scheduledOrders: scheduled).map(\.orderId),
            [1, 2]
        )
    }

    /// 没有进行中的单时取预约列表第一张，剩下的算「之后还有 N 次」。
    ///
    /// `laterCount` **不是** `scheduledOrders.count` —— 少减这个 1，界面上会同时出现
    /// 「下一次陪跑：周六 7:00」和「之后还有 1 次陪跑」，而那 1 次就是同一张单。
    func testNextComesFromScheduledWhenNothingIsUnderway() {
        let scheduled = [
            OrderDetailResponse.preview(orderId: 10, status: .scheduledConfirmed),
            OrderDetailResponse.preview(orderId: 11, status: .scheduledConfirmed),
            OrderDetailResponse.preview(orderId: 12, status: .scheduledConfirmed)
        ]

        let content = VolunteerDispatchHubContent.resolve(activeOrder: nil, scheduledOrders: scheduled)

        XCTAssertEqual(content.next?.orderId, 10)
        XCTAssertEqual(content.laterCount, 2)
        XCTAssertEqual(
            VolunteerDispatchHubContent.later(activeOrder: nil, scheduledOrders: scheduled).map(\.orderId),
            [11, 12]
        )
    }

    /// 两边都空 ⇒ 空状态，且「之后还有 N 次」不显示。
    func testEmptyStateWhenThereIsNothingAtAll() {
        let content = VolunteerDispatchHubContent.resolve(activeOrder: nil, scheduledOrders: [])
        XCTAssertNil(content.next)
        XCTAssertEqual(content.laterCount, 0)
    }

    /// 只有一张预约单时不显示「之后还有 0 次陪跑」。
    func testSingleScheduledOrderDoesNotAnnounceZeroLaterRuns() {
        let content = VolunteerDispatchHubContent.resolve(
            activeOrder: nil,
            scheduledOrders: [.preview(orderId: 5, status: .scheduledConfirmed)]
        )
        XCTAssertEqual(content.next?.orderId, 5)
        XCTAssertEqual(content.laterCount, 0)
    }

    // MARK: - 空闲时间那一行

    func testSlotSummaryCompressesWeekdayAndPeriod() {
        let slots = [
            VolunteerAvailableTimeSlot(dayOfWeek: "WEDNESDAY", startTime: "19:30:00", endTime: "21:00:00"),
            VolunteerAvailableTimeSlot(dayOfWeek: "SATURDAY", startTime: "06:30:00", endTime: "09:00:00")
        ]
        XCTAssertEqual(VolunteerAvailabilitySlotSummary.text(for: slots), "周三晚、周六早")
    }

    /// 超过两段并成「等 N 段」，而不是把整行挤成三行。
    func testSlotSummaryFoldsBeyondTwoEntries() {
        let slots = (0..<4).map { index in
            VolunteerAvailableTimeSlot(
                dayOfWeek: VolunteerAvailabilityScheduleEditing.weekdays[index],
                startTime: "08:00:00",
                endTime: "10:00:00"
            )
        }
        XCTAssertEqual(VolunteerAvailabilitySlotSummary.text(for: slots), "周一早、周二早 等 4 段")
    }

    /// 认不出的取值**整段跳过**，不落到某个默认档。
    ///
    /// 落默认档的后果是：后端换了时间格式之后，所有时段都被说成「凌晨」，
    /// 而志愿者看到的是一行语法完全正常的字。
    func testSlotSummarySkipsUnparseableEntriesInsteadOfGuessing() {
        XCTAssertNil(VolunteerAvailabilitySlotSummary.phrase(
            for: VolunteerAvailableTimeSlot(dayOfWeek: "FUNDAY", startTime: "08:00:00", endTime: "09:00:00")
        ))
        XCTAssertNil(VolunteerAvailabilitySlotSummary.phrase(
            for: VolunteerAvailableTimeSlot(dayOfWeek: "MONDAY", startTime: nil, endTime: "09:00:00")
        ))
        XCTAssertNil(VolunteerAvailabilitySlotSummary.text(for: []))
        XCTAssertEqual(
            VolunteerAvailabilitySlotSummary.text(for: [
                VolunteerAvailableTimeSlot(dayOfWeek: "FUNDAY", startTime: "08:00:00", endTime: "09:00:00"),
                VolunteerAvailableTimeSlot(dayOfWeek: "SUNDAY", startTime: "14:00:00", endTime: "16:00:00")
            ]),
            "周日下午",
            "认不出的那一段应当被跳过，剩下的照常显示"
        )
    }

    func testPeriodBucketsCoverTheWholeDay() {
        XCTAssertEqual(VolunteerAvailabilitySlotSummary.period("05:59:00"), "凌晨")
        XCTAssertEqual(VolunteerAvailabilitySlotSummary.period("06:00:00"), "早")
        XCTAssertEqual(VolunteerAvailabilitySlotSummary.period("10:59:00"), "早")
        XCTAssertEqual(VolunteerAvailabilitySlotSummary.period("11:00:00"), "中午")
        XCTAssertEqual(VolunteerAvailabilitySlotSummary.period("13:00:00"), "下午")
        XCTAssertEqual(VolunteerAvailabilitySlotSummary.period("18:00:00"), "晚")
        XCTAssertEqual(VolunteerAvailabilitySlotSummary.period("23:59:00"), "晚")
        XCTAssertNil(VolunteerAvailabilitySlotSummary.period("24:00:00"))
        XCTAssertNil(VolunteerAvailabilitySlotSummary.period("下午三点"))
    }

    // MARK: - 时间段编辑

    /// 分钟数 ↔ 后端字符串来回一趟不变形，**且秒位必须带**（契约的 example 是 `14:30:00`）。
    func testMinutesRoundTripThroughTheBackendFormat() {
        for minutes in [0, 7 * 60, 19 * 60 + 30, 23 * 60 + 45] {
            let raw = VolunteerAvailabilityScheduleEditing.raw(fromMinutes: minutes)
            XCTAssertEqual(raw.split(separator: ":").count, 3, "秒位丢了：\(raw)")
            XCTAssertEqual(VolunteerAvailabilityScheduleEditing.minutes(from: raw), minutes)
        }
        XCTAssertEqual(VolunteerAvailabilityScheduleEditing.raw(fromMinutes: 19 * 60 + 30), "19:30:00")
        XCTAssertEqual(VolunteerAvailabilityScheduleEditing.raw(fromMinutes: 6 * 60), "06:00:00")
    }

    /// 解析不出来返回 `nil`，**不回退到 0**。
    ///
    /// 回退的后果是把一个读不懂的时段静默改成「00:00」，而它会在下一次保存时被写回后端。
    func testUnparseableTimesReturnNilInsteadOfMidnight() {
        for raw in [nil, "", "abc", "25:00:00", "12:61:00", "12"] {
            XCTAssertNil(
                VolunteerAvailabilityScheduleEditing.minutes(from: raw),
                "\(raw ?? "nil") 不该被解析成某个具体时刻"
            )
        }
    }

    /// 结束必须晚于开始；相等与跨午夜都不合法。
    ///
    /// 跨午夜（22:00–02:00）在契约里无法表达 —— 只有一个 `dayOfWeek`。放行的后果是
    /// 后端拿到一个长度为负的窗口，这一段**永不命中**，而界面上一切正常。
    func testRangeValidationRejectsEqualAndOvernightWindows() {
        XCTAssertTrue(VolunteerAvailabilityScheduleEditing.isValid(startMinutes: 7 * 60, endMinutes: 9 * 60))
        XCTAssertFalse(
            VolunteerAvailabilityScheduleEditing.isValid(startMinutes: 7 * 60, endMinutes: 7 * 60),
            "零长度的时段等于没设，但界面上看起来是设了"
        )
        XCTAssertFalse(
            VolunteerAvailabilityScheduleEditing.isValid(startMinutes: 22 * 60, endMinutes: 2 * 60),
            "跨午夜在契约里表达不了，必须拆成两段"
        )
    }

    /// 后端那段读不出时间时**整段丢掉**，不显示成「00:00 – 00:00」。
    func testDraftSlotRejectsRowsItCannotRenderFaithfully() {
        XCTAssertNil(VolunteerAvailabilityDraftSlot(
            VolunteerAvailableTimeSlot(dayOfWeek: "MONDAY", startTime: "bad", endTime: "09:00:00")
        ))
        XCTAssertNil(VolunteerAvailabilityDraftSlot(
            VolunteerAvailableTimeSlot(dayOfWeek: "FUNDAY", startTime: "08:00:00", endTime: "09:00:00")
        ))

        let good = VolunteerAvailabilityDraftSlot(
            VolunteerAvailableTimeSlot(dayOfWeek: "saturday", startTime: "06:30:00", endTime: "09:00:00")
        )
        XCTAssertEqual(good?.weekday, "SATURDAY", "后端大小写不一致时不该整段丢掉")
        XCTAssertEqual(good?.startMinutes, 6 * 60 + 30)
        XCTAssertEqual(good?.payload.endTime, "09:00:00")
    }

    // MARK: - 暂停接单的文案

    /// 🔴 **暂停确认里不许有挽留。**
    ///
    /// 设计稿把「保持接单」做成黄色主按钮、「暂停」做成灰字，那正是 Uber 在司机点下线时
    /// 弹当日收入目标劝其继续的形状（被 NYT 点名）。这里主按钮就是「暂停接单」。
    /// 说明文案本身保留 —— 它消除的是「会不会连已约好的单一起取消」这个真实担心。
    func testPauseConfirmationDoesNotBargain() {
        XCTAssertEqual(VolunteerDispatchHubCopy.pauseConfirmPrimary, VolunteerDispatchHubCopy.pauseTitle)
        let copy = VolunteerDispatchHubCopy.pauseConfirmMessage + VolunteerDispatchHubCopy.pauseConfirmPrimary
        for word in ["保持接单", "再想想", "坚持", "确定要", "真的", "有人在等", "？"] {
            XCTAssertFalse(copy.contains(word), "暂停确认里出现挽留话术「\(word)」：\(copy)")
        }
    }

    // MARK: - 新邀请该怎么出现（设计交付 v3 §4.4.1）

    /// 🔴 **关键的是「陪跑中 **且** 在接单主页」这一组输入。**
    ///
    /// 只测「陪跑中 + 不在接单主页」的话，把两个判断的顺序写反的实现**照样通过**
    /// （那种输入下两种实现都落 `.stashedDuringRun`）。而顺序写反的真实后果是：
    /// 他跑完上一单还没退出订单页、人却已经站在接单主页上时，屏幕会在跑步途中
    /// 弹出一张压暗全屏的卡 —— 那一刻他一只手牵着引导绳。
    func testEscortUnderwayOutranksBeingOnTheDispatchHub() {
        XCTAssertEqual(
            VolunteerInvitePresentation.resolve(isEscortUnderway: true, isOnDispatchHub: true),
            .stashedDuringRun,
            "陪跑中必须压过「在接单主页」—— 两个判断的先后被写反了"
        )
        XCTAssertEqual(
            VolunteerInvitePresentation.resolve(isEscortUnderway: true, isOnDispatchHub: false),
            .stashedDuringRun
        )
    }

    /// 不在陪跑里时，只有接单主页那一档顶卡片，其余一律横幅。
    func testTheCardOnlyPopsOnTheDispatchHub() {
        XCTAssertEqual(
            VolunteerInvitePresentation.resolve(isEscortUnderway: false, isOnDispatchHub: true),
            .inviteCard
        )
        XCTAssertEqual(
            VolunteerInvitePresentation.resolve(isEscortUnderway: false, isOnDispatchHub: false),
            .banner,
            "不在接单主页就该只给横幅 —— 弹卡会盖住他正在做的事"
        )
    }

    /// 三档各自的副作用。**横幅那一档震但不响**（设计稿逐字「轻震一次，无声音」），
    /// 陪跑中那一档三样都不要。
    ///
    /// 这三条断言分别能打回一种偷懒实现：把 `makesSound` 写成 `!= .stashedDuringRun`
    /// 会让他在开会 / 在图书馆时被一声提示音出卖；把 `vibrates` 写成 `== .inviteCard`
    /// 会让横幅那一档在他没看屏幕时完全无感。
    func testOnlyTheInviteCardMakesASound() {
        XCTAssertTrue(VolunteerInvitePresentation.inviteCard.makesSound)
        XCTAssertFalse(VolunteerInvitePresentation.banner.makesSound, "横幅那一行写的是「轻震一次，无声音」")
        XCTAssertFalse(VolunteerInvitePresentation.stashedDuringRun.makesSound)

        XCTAssertTrue(VolunteerInvitePresentation.inviteCard.vibrates)
        XCTAssertTrue(VolunteerInvitePresentation.banner.vibrates, "横幅那一档要轻震一次")
        XCTAssertFalse(VolunteerInvitePresentation.stashedDuringRun.vibrates, "陪跑中不震动")

        XCTAssertTrue(VolunteerInvitePresentation.inviteCard.presentsInviteSheet)
        XCTAssertFalse(VolunteerInvitePresentation.banner.presentsInviteSheet)
        XCTAssertFalse(VolunteerInvitePresentation.stashedDuringRun.presentsInviteSheet)
    }

    /// 「陪跑中」只包含路上的三态。
    ///
    /// 🔴 **`SCHEDULED_CONFIRMED` 与 `PENDING_ACCEPT` 必须为 false** —— 设计稿把
    /// 「订单页『约好』状态」明确列在**横幅**那一行。判成 true 的后果是：接了一张下周六的单
    /// 之后，这一整周里所有新邀请都被静默暂存，他会以为自己再也收不到单了。
    func testEscortUnderwayCoversTheThreeOnTheMoveStatusesOnly() {
        for status: RunOrderStatus in [.driverEnRoute, .driverArrived, .inProgress] {
            XCTAssertTrue(status.isEscortUnderway, "\(status.rawValue) 应当算「陪跑中」")
        }
        for status: RunOrderStatus in [
            .pendingMatch, .pendingIntroCall, .scheduledConfirmed, .pendingAccept,
            .completed, .cancelled, .rematching, .noVolunteer, .unknown
        ] {
            XCTAssertFalse(status.isEscortUnderway, "\(status.rawValue) 不该算「陪跑中」")
        }
    }

    /// 陪跑期间来的邀请：不弹卡、不上角标，而且在接单主页上换一句标题。
    ///
    /// 角标那半条是真会坏的：`inviteBadgeCount` 写成 `invitesAwaitingReply.count` 就够了
    /// 看起来也对 —— 直到他跑步时手机在臂带上亮起一枚红点，而设计稿那一行写的是
    /// 「不推送、不横幅、不震动」。
    @MainActor
    func testInvitesArrivingMidRunStayQuietAndSayWhenTheyCame() {
        let viewModel = VolunteerHomeViewModel()
        viewModel.configure(with: AppState(), speechService: SpeechService())
        viewModel.activeOrder = .preview(orderId: 77, status: .inProgress)

        viewModel.incomingOrder = Self.makeDispatch(orderId: 900)

        XCTAssertFalse(viewModel.isInviteSheetPresented, "陪跑中不该弹邀请卡")
        XCTAssertNil(viewModel.bannerInvite, "陪跑中不该有横幅")
        XCTAssertEqual(viewModel.inviteBadgeCount, 0, "陪跑中标签角标必须是 0")
        XCTAssertEqual(viewModel.invitesAwaitingReply.count, 1, "邀请本身要留在队列里，不是丢掉")
        XCTAssertTrue(viewModel.invitesAwaitingReply.allSatisfy(\.arrivedDuringEscort))
        XCTAssertEqual(
            VolunteerInviteCopy.pendingInvitesDuringRunTitle(count: 1),
            "陪跑时收到 1 个新邀请"
        )
    }

    /// 反向哨兵：不在陪跑里、也不在接单主页时，横幅与角标都要出来。
    ///
    /// 没有这一条，上一条用「什么都不做」的实现也能过。
    @MainActor
    func testInvitesArrivingElsewhereRaiseTheBannerAndTheBadge() {
        let viewModel = VolunteerHomeViewModel()
        viewModel.configure(with: AppState(), speechService: SpeechService())

        viewModel.incomingOrder = Self.makeDispatch(orderId: 901)

        XCTAssertFalse(viewModel.isInviteSheetPresented, "不在接单主页就不该自动弹卡")
        XCTAssertEqual(viewModel.bannerInvite?.id, 901)
        XCTAssertEqual(viewModel.inviteBadgeCount, 1)
        XCTAssertFalse(viewModel.invitesAwaitingReply[0].arrivedDuringEscort)

        // 点「查看」：横幅让位，卡片顶上来。收起横幅不动队列。
        viewModel.presentInviteSheetFromBanner()
        XCTAssertNil(viewModel.bannerInvite)
        XCTAssertTrue(viewModel.isInviteSheetPresented)
        XCTAssertEqual(viewModel.invitesAwaitingReply.count, 1)
    }

    /// 坐在接单主页上等单时，邀请直接顶到脸上 —— 这是这一整套判定存在的理由。
    @MainActor
    func testInvitesArrivingOnTheDispatchHubPopTheCardStraightAway() {
        let viewModel = VolunteerHomeViewModel()
        viewModel.configure(with: AppState(), speechService: SpeechService())
        viewModel.isDispatchHubVisible = true

        viewModel.incomingOrder = Self.makeDispatch(orderId: 902)

        XCTAssertTrue(viewModel.isInviteSheetPresented)
        XCTAssertNil(viewModel.bannerInvite, "卡片已经开着，头顶不该再压一条「查看」")
    }

    private static func makeDispatch(orderId: Int64) -> WSNewOrder {
        WSNewOrder(
            type: "NEW_ORDER",
            timestamp: nil,
            orderId: orderId,
            startAddress: "深圳湾公园 3 号入口",
            startLatitude: nil,
            startLongitude: nil,
            distanceKm: 3.2,
            plannedStart: nil,
            plannedEnd: nil,
            dispatchTimeoutSeconds: 30,
            priority: "HIGH",
            pacePreference: nil,
            hasGuideDog: false,
            requiresIntroCall: false
        )
    }
}
