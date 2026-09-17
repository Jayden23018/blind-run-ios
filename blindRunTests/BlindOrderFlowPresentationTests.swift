import XCTest
@testable import blindRun

/// 订单页四步骨架的状态映射与文案。
///
/// 这一屏的错误形态**全是静默的**：某一态落错格、文案说错、按钮在不该出现的态出现，
/// 屏幕上都不会报任何错。而它是盲人在等人期间唯一的信息来源。
final class BlindOrderFlowPresentationTests: XCTestCase {

    // MARK: - 状态 → 第几格

    /// 穷举全部状态。**这条是覆盖面自检**：漏一个状态不会让任何断言变红，
    /// 它只是不再被检查，而绿灯照常亮。
    func testEveryOrderStatusMakesAnExplicitStepDecision() {
        let expected: [RunOrderStatus: BlindOrderFlowStep?] = [
            // `PENDING_INTRO_CALL` 归匹配格：这一态后端 `order.volunteer` 恒为 null，
            // 还没有志愿者接单。画成「约好」是假信息。
            .pendingMatch: .matching,
            .pendingIntroCall: .matching,
            .rematching: .matching,
            .scheduledConfirmed: .booked,
            .pendingAccept: .booked,
            .driverEnRoute: .departed,
            .driverArrived: .metUp,
            // 🔴 与汇合**同一格**。跑起来之后进度条整条折叠收起，所以屏幕上并不显示
            // 「第 4 步」—— 但它必须走同一个骨架：跳页会让 VoiceOver 焦点回到屏幕顶部。
            // 2026-09-16 之前这里是 `nil`（独立执行屏），那正是这次消掉的跳页。
            .inProgress: .metUp,
            // 🔴 `COMPLETED` 2026-09-17 起也落这一格（设计稿 ④）：陪跑员结束之后同一张卡
            // 原地换成总结状态。落 `nil` 的写法会在那一刻整屏重建成只读列表，
            // 而 iOS 切页会把 VoiceOver 焦点打回顶部 —— 阶段 1 消掉的那次跳页又发生一次。
            .completed: .metUp,
            // 其余终态：只读终态卡。
            .cancelled: nil,
            .noVolunteer: nil,
            // 🔴 **落 nil，不许落进 `.matching`**：「我不认识后端给的状态」和
            // 「正在匹配」是两件事，把未知态画成匹配中会让盲人以为系统在替他找人。
            .unknown: nil,
        ]

        let allStatuses = RunOrderStatus.allCases + [.unknown]
        XCTAssertEqual(
            Set(expected.keys), Set(allStatuses),
            "预期表与真实状态集不一致：漏掉的状态不会被断言，多出来的说明表过期了"
        )
        for status in allStatuses {
            XCTAssertEqual(
                status.blindOrderFlowStep, expected[status] ?? nil,
                "\(status) 落错了格"
            )
        }
    }

    /// 四格的顺序与文字就是设计稿那四个字。进度条的读屏标签直接拼它们。
    func testStepTitlesMatchTheDesign() {
        XCTAssertEqual(BlindOrderFlowStep.allTitles, ["匹配", "约好", "出发", "汇合"])
        XCTAssertEqual(BlindOrderFlowStep.allCases.map(\.rawValue), [0, 1, 2, 3])
    }

    // MARK: - 视觉区

    func testEachStepGetsItsOwnVisual() {
        let cases: [(RunOrderStatus, BlindOrderFlowPresentation.Visual)] = [
            (.pendingMatch, .radar),
            (.scheduledConfirmed, .avatar),
            (.driverEnRoute, .avatarWithProgressRing),
            (.driverArrived, .avatarWithSuccessBadge),
        ]
        for (status, visual) in cases {
            XCTAssertEqual(make(status).visual, visual, "\(status) 的视觉区不对")
        }
    }

    // MARK: - 标题

    /// 匹配格里三个状态说三句不同的话 —— 否则通话磨合态会念「正在匹配陪跑员」，
    /// 而状态卡副标题同时在说「有位志愿者想陪你跑」，自相矛盾。
    func testMatchingStepDistinguishesItsThreeStatuses() {
        XCTAssertEqual(make(.pendingMatch, volunteerName: nil).title, "正在匹配陪跑员")
        XCTAssertEqual(make(.rematching, volunteerName: nil).title, "正在重新匹配陪跑员")
        XCTAssertEqual(make(.pendingIntroCall, volunteerName: nil).title, "有位志愿者想陪你跑")
    }

    /// 已出发之后标题用姓名，且**姓名去掉掩码星号**（读屏是外放的）。
    func testUnderwayTitlesUseTheSpokenNameWithoutTheMask() {
        XCTAssertEqual(make(.driverEnRoute).title, "张正在赶来")
        XCTAssertEqual(make(.driverArrived).title, "张已到达")
        for status in [RunOrderStatus.driverEnRoute, .driverArrived] {
            XCTAssertFalse(make(status).title.contains("*"), "标题里留着掩码星号")
        }
    }

    /// 🔴 **设计稿的「8 分钟后到」做不出来，这条钉住「不许编」。**
    ///
    /// 全仓与后端契约都没有 ETA（`etaMinutes` / `estimatedArrival` 在 `api_spec.yaml`
    /// 命中 0），而 `VoiceStatusQuery.swift:21` 逐字写着「只念直线距离，不做 ETA / 路线规划」。
    /// 给正在集合点等人的盲人编一个到达时间，比不给更糟。
    func testDepartedTitleNeverInventsAnEtaEvenWhenDistanceIsKnown() {
        let presentation = make(.driverEnRoute, distanceText: "距出发地点约 600 米")
        XCTAssertFalse(presentation.title.contains("分钟"), "标题里出现了编出来的到达时间")
        // 距离进副标题，不进标题（34pt 放不下一整句）。
        XCTAssertTrue(presentation.subtitle.contains("距出发地点约 600 米"))
    }

    /// 没有陪跑员姓名时退回中性称谓，**不念「这位志愿者正在赶来」那种拗口的拼接**。
    func testUnderwayTitlesFallBackWhenThereIsNoName() {
        XCTAssertEqual(make(.driverEnRoute, volunteerName: nil).title, "陪跑员正在赶来")
        XCTAssertEqual(make(.driverArrived, volunteerName: nil).title, "陪跑员已到达")
    }

    // MARK: - 副标题

    /// 副标题**复用既有的 `blindRunnerDescription`**，不新造文案。
    ///
    /// 那些串上记着一串不许说的东西：通话态不提「第几位」（无声拒绝）、远期预约不提
    /// 临期闸门、**不写具体提前量**（那是后端配置，写死就是编一个数字念给盲人听）。
    /// 设计稿的副标题恰好违反最后一条 —— 它写「请提前 10 分钟到达」。
    func testSubtitleReusesTheExistingStatusCopyInsteadOfInventingOne() {
        for status in [RunOrderStatus.pendingMatch, .pendingIntroCall, .scheduledConfirmed,
                       .pendingAccept, .driverEnRoute, .driverArrived, .rematching] {
            XCTAssertTrue(
                make(status).subtitle.hasPrefix(status.blindRunnerDescription),
                "\(status) 的副标题没有以既有状态说明开头"
            )
        }
    }

    /// 🔴 验红：副标题里**不许出现写死的提前量**。
    /// 这条挡的是「照设计稿把「请提前 10 分钟到达」抄进来」那一步。
    func testSubtitleNeverHardcodesALeadTime() {
        for status in [RunOrderStatus.scheduledConfirmed, .pendingAccept] {
            let subtitle = make(status).subtitle
            XCTAssertFalse(
                subtitle.contains("提前 10 分钟"),
                "副标题写死了提前量，而那是后端配置（\(subtitle)）"
            )
        }
    }

    /// 「已等待」与距离的状态集互不相交，所以任何时刻最多追加一个数。
    func testSubtitleAppendsAtMostOneChangingNumber() {
        // 等待态：有「已等待」，没有距离（`offersVolunteerDistanceToStart` 为假）。
        let waiting = make(
            .pendingMatch,
            volunteerName: nil,
            distanceText: "距出发地点约 600 米",
            createdAt: "2026-09-16T09:00:00",
            now: date("2026-09-16 09:30:00")
        )
        XCTAssertTrue(waiting.subtitle.contains("已等待"))
        XCTAssertFalse(waiting.subtitle.contains("600 米"), "等待态不该念距离")

        // 出发态：有距离，没有「已等待」（`offersWaitedDuration` 为假）。
        let departed = make(.driverEnRoute, distanceText: "距出发地点约 600 米")
        XCTAssertTrue(departed.subtitle.contains("600 米"))
        XCTAssertFalse(departed.subtitle.contains("已等待"), "出发态不该念已等待")
    }

    // MARK: - 信息列表最后一行

    /// 🔴 **设计稿在出发态写的是「修改或取消预约」，两处都不成立。**
    ///
    /// ① 盲人在 `DRIVER_EN_ROUTE` / `DRIVER_ARRIVED` **不能取消**（`AGENTS.md` §5
    ///    的可取消状态集合里没有这两态，后端会拒）；
    /// ② 后端**没有任何改单端点**（`/api/orders` 下 `put`/`patch` 命中 0）——
    ///    「修改」这个词承诺了一个不存在的功能。
    func testLastRowNeverPromisesAnEditEndpointThatDoesNotExist() {
        for status in [RunOrderStatus.pendingMatch, .pendingIntroCall, .scheduledConfirmed,
                       .pendingAccept, .driverEnRoute, .driverArrived, .rematching] {
            XCTAssertFalse(
                make(status).lastRowTitle.contains("修改"),
                "\(status) 的最后一行承诺了「修改」，而后端没有改单端点"
            )
        }
    }

    /// 能取消的态说「取消」，不能取消的态说「遇到问题」。
    /// 判据直接读 `canBlindRunnerCancel` —— 与后端会不会拒是同一个判据。
    func testLastRowOffersCancelOnlyWhereTheBackendAcceptsIt() {
        XCTAssertEqual(make(.pendingMatch, volunteerName: nil).lastRowTitle, "取消匹配")
        XCTAssertEqual(make(.rematching, volunteerName: nil).lastRowTitle, "取消匹配")
        XCTAssertEqual(make(.scheduledConfirmed).lastRowTitle, "取消预约")
        XCTAssertEqual(make(.pendingAccept).lastRowTitle, "取消预约")
        // 这两态盲人取消不了。
        XCTAssertEqual(make(.driverEnRoute).lastRowTitle, "遇到问题")
        XCTAssertEqual(make(.driverArrived).lastRowTitle, "遇到问题")

        // 🔴 验红：上面四条「取消」必须真的落在后端接受的状态上。
        for status in [RunOrderStatus.pendingMatch, .rematching, .scheduledConfirmed, .pendingAccept] {
            XCTAssertTrue(status.canBlindRunnerCancel, "\(status) 给了取消入口而后端不接受")
        }
        for status in [RunOrderStatus.driverEnRoute, .driverArrived] {
            XCTAssertFalse(status.canBlindRunnerCancel, "\(status) 若可取消，这条用例的前提就变了")
        }
    }

    // MARK: - 主按钮

    /// 🔴 **汇合态的主按钮不是「开始跑步」。**
    ///
    /// `POST /api/orders/{id}/start-service` 在后端走
    /// `loadForVolunteer(orderId, volunteerId, "只有接单的志愿者才能操作")`
    /// （`OrderLifecycleService.java:155-156`，controller 注释逐字「志愿者确认开始服务」）——
    /// 盲人调必被拒。摆一个必然失败的按钮，对读屏用户是纯粹的死路。
    func testMetUpDoesNotOfferStartServiceBecauseOnlyTheVolunteerCanCallIt() {
        let presentation = make(.driverArrived)
        XCTAssertFalse(
            presentation.primaryAction?.title.contains("开始跑步") ?? false,
            "汇合态给了「开始跑步」，而这个端点只接受志愿者的 token"
        )
        // 这一态真正有用的动作是打电话找到人。
        XCTAssertEqual(presentation.primaryAction, .callVolunteer(title: "打电话给张"))
        // 而「等志愿者开始」这件事由副标题说（既有的 `arrivedWaitingCopy`）。
        XCTAssertTrue(presentation.subtitle.contains("请等待志愿者开始服务"))
    }

    /// 设计稿的匹配态主按钮位是空的 —— 那一态用户没有该做的事。
    func testPendingMatchHasNoPrimaryActionSoWaitingDoesNotLookLikeAChore() {
        XCTAssertNil(
            make(.pendingMatch, volunteerName: nil, canKeepWaiting: true).primaryAction,
            "PENDING_MATCH 出现了主按钮 —— 摆一个会让盲人以为等待期有一件必须完成的操作"
        )
    }

    /// `REMATCHING` **保留**延长入口。项目负责人 2026-09-16 拍板的两半，这是第二半。
    ///
    /// 后端 N62 把 `rematchNotifyAt` 计进了 `dispatchDeadline`，那一侧是**真延长**；
    /// 删了只剩一个 30 分钟窗口就转 `NO_VOLUNTEER` 终态，而重新下单又要求 ≥30 分钟提前量。
    func testRematchingKeepsKeepWaitingBecauseThatSideReallyExtendsTheDeadline() {
        XCTAssertEqual(
            make(.rematching, volunteerName: nil, canKeepWaiting: true).primaryAction,
            .keepWaiting(title: KeepWaitingCopy.buttonTitle)
        )
        // 次数用尽后整个按钮消失，不是禁用 —— 摆一个按下去必然 409 的按钮是纯噪音。
        XCTAssertNil(make(.rematching, volunteerName: nil, canKeepWaiting: false).primaryAction)
    }

    /// 通话磨合态的按钮**不复用拨号文案**：那个按下去立刻弹系统拨号确认，
    /// 这个只是打开一个页面。对看不见屏幕的人，两件事听起来一样就等于随时可能误拨。
    func testIntroCallUsesItsOwnButtonTitleSoItIsNotMistakenForDialing() {
        let action = make(.pendingIntroCall, volunteerName: nil).primaryAction
        XCTAssertEqual(action, .openIntroCall(title: IntroCallCopy.blindEntryButtonTitle))
        XCTAssertNotEqual(action?.title, "打电话给张")
    }

    /// 拿不到可拨的号码时不给拨号按钮。判据是「拼不拼得出 `tel:` URL」而不是「字符串非空」。
    ///
    /// 🔴 **2026-09-16 第一次真机执行时这条是红的，而红的是它自己。** 原注释写着
    /// 「掩码串 `138****1234` 只取数字位会拼成空号」—— 那句话**是错的**：
    /// `telURL` 当时只判「取完数字位还剩不剩」，于是它拼得出 `tel://1381234`，
    /// 一个七位的、可能真打给别人的号码。`IntroCallTests` 里早就逐字记着这件事
    /// （「掩码串**拼得出**一个合法但错误的 tel URL」），而这里的注释和它对不上。
    ///
    /// 修的是实现不是断言：`EmergencyDialer.telURL` 现在拦掩码标记（`*`），
    /// 所以第二行断言从「靠一个不成立的理由碰巧成立」变成真的成立。
    ///
    /// ⚠️ 顺带记一条口径：`OrderDetailResponse.volunteerPhone` **按契约永远不是掩码串**
    /// （`api_spec.yaml:6421` 逐字「要么是能直接拨通的号码，要么是 `null`，永远不会是掩码串」）。
    /// 所以第二行喂的是一个后端保证不会下发的值 —— 留着它是**纵深防御**，
    /// 防的是哪天有人把 `counterpartPhoneMasked` 之类的字段接到这里来。
    func testCallButtonDisappearsWhenThereIsNoDialableNumber() {
        XCTAssertNil(make(.driverArrived, volunteerPhone: nil).primaryAction)
        XCTAssertNil(make(.driverArrived, volunteerPhone: "138****1234").primaryAction)
        // 一个数字都没有的串同样不给按钮 —— 这是 `telURL` 原本就有的那道闸。
        XCTAssertNil(make(.driverArrived, volunteerPhone: "未填写").primaryAction)
        XCTAssertNotNil(make(.driverArrived, volunteerPhone: "13800000001").primaryAction)
        // 带空格/横线的明文号**必须照样能拨** —— 掩码闸不能顺手把格式化字符也拦掉。
        XCTAssertNotNil(make(.driverArrived, volunteerPhone: "138 0000 0001").primaryAction)
    }

    // MARK: - 警示行

    /// 正常状态**不显示任何反向提示**（「定位正常」之类）。
    func testWarningIsNilUnlessSomethingIsActuallyWrong() {
        for status in [RunOrderStatus.pendingMatch, .scheduledConfirmed, .driverEnRoute, .driverArrived] {
            XCTAssertNil(make(status, volunteerName: status == .pendingMatch ? nil : "张*").warning)
        }
        XCTAssertEqual(
            make(.driverEnRoute, locationWarning: "同行位置暂不可用，稍后会自动恢复。").warning,
            "同行位置暂不可用，稍后会自动恢复。"
        )
    }

    // MARK: - 不走骨架的那些态

    /// `COMPLETED` **不在这里** —— 它自 2026-09-17 起走骨架的第四幕（见
    /// `BlindRunPhaseTests.testFinishedStaysOnTheSameSkeletonStepAsTheRun`）。
    /// 剩下这三态仍然落只读退路，而 `.unknown` 那一条**不许删**：
    /// 后端加了状态时它是未知态唯一的落点，否则整屏空白。
    func testStatusesOutsideTheSkeletonProduceNoPresentation() {
        for status in [RunOrderStatus.cancelled, .noVolunteer, .unknown] {
            XCTAssertNil(
                BlindOrderFlowPresentation.make(
                    order: .preview(status: status),
                    distanceText: nil,
                    canKeepWaiting: false
                ),
                "\(status) 不该走四步骨架"
            )
        }
    }

    // MARK: - 辅助

    private func make(
        _ status: RunOrderStatus,
        volunteerName: String? = "张*",
        volunteerPhone: String? = "13800000001",
        distanceText: String? = nil,
        canKeepWaiting: Bool = false,
        locationWarning: String? = nil,
        createdAt: String? = nil,
        countdown: Int? = nil,
        now: Date = Date()
    ) -> BlindOrderFlowPresentation {
        let order = OrderDetailResponse.preview(
            status: status,
            volunteerName: volunteerName,
            volunteerTotalCompleted: volunteerName == nil ? nil : 32,
            volunteerPhone: volunteerPhone,
            createdAt: createdAt
        )
        guard let presentation = BlindOrderFlowPresentation.make(
            order: order,
            distanceText: distanceText,
            canKeepWaiting: canKeepWaiting,
            locationWarning: locationWarning,
            countdown: countdown,
            now: now
        ) else {
            XCTFail("\(status) 应该落在骨架里")
            // 这条路走不到（上面已 fail），给一个不会被断言的值让签名闭合。
            return BlindOrderFlowPresentation(
                step: .matching, phase: .beforeRun, visual: .radar, title: "", subtitle: "",
                lastRowTitle: "", primaryAction: nil, warning: nil
            )
        }
        return presentation
    }

    private func date(_ string: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.date(from: string)!
    }
}
