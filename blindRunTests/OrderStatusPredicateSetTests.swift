import XCTest
@testable import blindRun

/// `RunOrderStatus` 上那批判定的**状态集合**本身。
///
/// 为什么单独立一个文件：2026-09-21 量过全仓，69 处订单状态判定有三种写法，
/// 而只有穷举 switch 那一种会在后端加状态时说话（另两种静默答 false）。
/// `scripts/hooks/guard.mjs` 的 `status-set-literal` 从此拦住新的字面量写法，
/// 这个文件管的是另一半 —— **已经写成穷举 switch 的那些，集合内容对不对**。
/// 守卫保证「加状态时编译器会问你」，用例保证「你当时答对了」。
///
/// ⚠️ 断言一律写成**逐态比对整个集合**，不是挑几个态点名。
/// 挑几个态的写法分辨不出「多了一个态」——而后端往状态机加值恰恰是这个仓库
/// 已经发生过两次的事（迁移 `0031` 通话磨合、`0041` 跨天预约）。
final class OrderStatusPredicateSetTests: XCTestCase {

    /// 把一条判定在**全部** case 上跑一遍，返回判 true 的那些。
    /// 用 `allCases` 而不是手写列表：手写列表会和枚举一起腐烂，而它腐烂时不会红。
    private func statuses(where predicate: (RunOrderStatus) -> Bool) -> Set<RunOrderStatus> {
        Set(RunOrderStatus.allCases.filter(predicate))
    }

    // MARK: - 陪跑会话（本轮新增的三条判定）

    /// 推我方位置 / 收对方位置 / 算走散告警，三件事共用的闸。
    ///
    /// 这一条判错的代价是全仓最高的一档：答 false = 陪跑途中不推实时位置，
    /// 而实时位置是走散告警与求助定位的唯一来源。
    func testLiveEscortSessionRunsOnlyWhileTheVolunteerIsOnTheMove() {
        XCTAssertEqual(
            statuses { $0.runsLiveEscortSession },
            [.driverEnRoute, .driverArrived, .inProgress]
        )
    }

    /// `.scheduledConfirmed` 必须**不在**内，且理由不在客户端 ——
    /// `OrderModels.swift` 那条 case 的注释逐字：「实时位置**不推**
    /// （后端 `sharesLiveLocation()` 判 false）：距开跑还有几天，
    /// 推位置既无意义又是持续的位置泄露」。
    ///
    /// 单独钉一条而不是靠上面那个集合断言兜住：跨天预约是最近加的状态，
    /// 「顺手把它加进陪跑窗口」是一个看起来很合理、而且真的有人会做的改动。
    func testScheduledConfirmedNeverSharesLocationBecauseTheRunIsStillDaysAway() {
        XCTAssertFalse(RunOrderStatus.scheduledConfirmed.runsLiveEscortSession)
    }

    func testLiveEscortSessionEndsWhenTheVolunteerStopsBeingAParticipant() {
        XCTAssertEqual(
            statuses { $0.endsLiveEscortSession },
            [.completed, .cancelled, .rematching, .noVolunteer]
        )
    }

    /// 「该结束」**不是**「不该跑」的反面 —— 两者中间隔着一段「人已接单但还没出发」。
    ///
    /// 这条是设计决定本身的守卫：有人把两条合成 `!runsLiveEscortSession` 时，
    /// `.pendingAccept` / `.scheduledConfirmed` 等态会被当成「会话结束」就地拆掉，
    /// 而那几态本来只是还没开始。
    func testEndingTheSessionIsNotSimplyTheOppositeOfRunningIt() {
        let neither = RunOrderStatus.allCases.filter {
            !$0.runsLiveEscortSession && !$0.endsLiveEscortSession
        }
        XCTAssertEqual(
            Set(neither),
            [.pendingMatch, .pendingIntroCall, .scheduledConfirmed, .pendingAccept, .unknown]
        )
    }

    /// `endsLiveEscortSession` 不能退化成 `isTerminal`：后者不含 `.rematching`。
    ///
    /// AGENTS.md 第 5 节逐字：「`REMATCHING` 是已接单志愿者取消后进入的状态……
    /// 那个志愿者已不是订单参与者」。用 `isTerminal` 会把一个**已经退出的人**的
    /// 陪跑会话留在原地继续推位置 —— 那是在向一个不再相关的人广播盲人的实时位置。
    func testRematchingEndsTheSessionEvenThoughItIsNotATerminalStatus() {
        XCTAssertFalse(RunOrderStatus.rematching.isTerminal)
        XCTAssertTrue(RunOrderStatus.rematching.endsLiveEscortSession)
        XCTAssertEqual(
            statuses { $0.endsLiveEscortSession },
            statuses { $0.isTerminal }.union([.rematching])
        )
    }

    /// 服务记录只收他确实接下来、并且走完了的单。
    ///
    /// `.noVolunteer` 不在内：那是**没人接**的单，从来就不属于任何一个陪跑员；
    /// 它会出现在 `myOrders()` 的返回里只是因为后端按盲人视角分页。
    func testVolunteerServiceRecordHoldsOnlyOrdersThatPersonActuallyRan() {
        XCTAssertEqual(
            statuses { $0.appearsInVolunteerServiceRecord },
            [.completed, .cancelled]
        )
        XCTAssertFalse(RunOrderStatus.noVolunteer.appearsInVolunteerServiceRecord)
        XCTAssertFalse(RunOrderStatus.rematching.appearsInVolunteerServiceRecord)
    }

    // MARK: - 此前零覆盖的四条判定
    //
    // 下面这几条在 2026-09-21 之前**全仓测试目录零命中**，而其中
    // `isActiveForVolunteer` 有 10 个调用点。它们不是新写的代码，
    // 补用例是为了让后端加状态时那一次编译失败有个对照答案。

    /// 陪跑员端的「这一单还活着吗」。
    ///
    /// 与盲人端的 `isActiveForBlindRunner` 是一对镜像判定，而两端同名判定的集合
    /// 悄悄错开是这个仓库栽过的事（`.pendingMatch` 在这边判 false：那一态还没有
    /// 任何志愿者，它对陪跑员不存在）。
    func testVolunteerSideActiveSetStartsAtTheIntroCallNotAtDispatch() {
        XCTAssertEqual(
            statuses { $0.isActiveForVolunteer },
            [.pendingIntroCall, .scheduledConfirmed, .pendingAccept,
             .driverEnRoute, .driverArrived, .inProgress, .unknown]
        )
        XCTAssertFalse(RunOrderStatus.pendingMatch.isActiveForVolunteer)
    }

    /// `.unknown` 判 **true** 是刻意的，不是漏写。
    ///
    /// 与 `MockAPIClient+Order.swift` 里那段注释同源：判 true 是为了
    /// 「不让订单从界面上消失」—— 后端加了个我们不认识的状态时，宁可把这一单
    /// 继续显示出来，也不要让它从陪跑员的列表里静默蒸发。
    /// 单独钉一条，因为它看起来**很像**一个该改成 false 的疏忽。
    func testUnknownStatusKeepsTheOrderVisibleRatherThanVanishingIt() {
        XCTAssertTrue(RunOrderStatus.unknown.isActiveForVolunteer)
    }

    /// 每个状态一个图标，且**两两不同**。
    ///
    /// 重复是真实的缺陷形态：这是个逐 case 返回字符串的长 switch，
    /// 复制粘贴漏改一行不会有任何东西报警，而屏幕上的表现是两个不同状态长得一模一样。
    func testEveryStatusHasItsOwnDistinctSymbol() {
        let symbols = RunOrderStatus.allCases.map(\.statusSymbolName)
        XCTAssertEqual(symbols.count, RunOrderStatus.allCases.count)
        XCTAssertEqual(
            Set(symbols).count,
            symbols.count,
            "有状态共用了同一个图标：\(symbols.sorted())"
        )
        XCTAssertFalse(symbols.contains { $0.trimmed.isEmpty })
    }

    /// 状态色的两组「刻意同档」配对 —— 它们是注释里写明的产品决定，不是巧合。
    ///
    /// 断言写成「这两个相等」而不是「这个等于 AppColors.primary」：
    /// 后者在调色板改名时会红得毫无信息量，而前者钉住的是**配对关系**本身。
    func testStatusColorKeepsTheTwoDeliberatePairings() {
        // 「人已经定了，在等一个约定的时刻到来」—— 用户此刻什么都不用做
        XCTAssertEqual(
            RunOrderStatus.scheduledConfirmed.statusColor,
            RunOrderStatus.pendingAccept.statusColor
        )
        // 「等着用户做一件事」—— 不是等系统
        XCTAssertEqual(
            RunOrderStatus.pendingIntroCall.statusColor,
            RunOrderStatus.driverArrived.statusColor
        )
        // 这两档必须**不同**，否则上面两条相等断言可以靠「全部同色」蒙混过关
        XCTAssertNotEqual(
            RunOrderStatus.pendingAccept.statusColor,
            RunOrderStatus.driverArrived.statusColor
        )
    }
}

/// `OrderDetailResponse` 上那两条此前零覆盖的取值。
final class OrderDetailResponseSpeechAndSortTests: XCTestCase {

    /// 排序键优先取创建时间，没有才退到计划开始时间。
    ///
    /// 两个字段都缺时给空串而不是 `nil` —— 调用方是 `sorted { $0.sortKey > $1.sortKey }`，
    /// 可选值会把整条排序逻辑变成另一回事。
    func testSortKeyPrefersCreatedAtAndFallsBackToPlannedStart() {
        XCTAssertEqual(
            Self.makeOrder(createdAt: "2026-09-20T08:00:00", plannedStart: "2026-09-21T07:00:00").sortKey,
            "2026-09-20T08:00:00"
        )
        XCTAssertEqual(
            Self.makeOrder(createdAt: nil, plannedStart: "2026-09-21T07:00:00").sortKey,
            "2026-09-21T07:00:00"
        )
        XCTAssertEqual(Self.makeOrder(createdAt: nil, plannedStart: nil).sortKey, "")
    }

    /// 播报用的盲人姓名要把掩码星号去掉 —— 念出「王星轩」比念出「王星星轩」强，
    /// 而后者正是把上屏字符串直接交给 TTS 的结果。全角 `＊` 一并覆盖。
    func testBlindNameForSpeechStripsMaskCharactersInBothWidths() {
        XCTAssertEqual(Self.makeOrder(blindName: "王*轩").blindNameForSpeech, "王轩")
        XCTAssertEqual(Self.makeOrder(blindName: "王＊轩").blindNameForSpeech, "王轩")
    }

    /// 名字为空、或掩码去完只剩空白时，退回既有常量而不是念出一个空字符串。
    ///
    /// 「全是星号」这个输入是关键：它在「只判 nil」的实现下会得到空串，
    /// 在正确实现下得到回退文案 —— 两种实现在这个输入上结果不同，所以它分辨得出来。
    func testBlindNameForSpeechFallsBackWhenNothingIsLeftAfterUnmasking() {
        XCTAssertEqual(
            Self.makeOrder(blindName: nil).blindNameForSpeech,
            PartnerStreakCopy.unknownBlindName
        )
        XCTAssertEqual(
            Self.makeOrder(blindName: "***").blindNameForSpeech,
            PartnerStreakCopy.unknownBlindName
        )
    }

    private static func makeOrder(
        blindName: String? = nil,
        createdAt: String? = nil,
        plannedStart: String? = nil
    ) -> OrderDetailResponse {
        OrderDetailResponse(
            orderId: 4242,
            status: .inProgress,
            startAddress: "测试出发点",
            startLatitude: nil,
            startLongitude: nil,
            endAddress: nil,
            endLatitude: nil,
            endLongitude: nil,
            plannedStart: plannedStart,
            plannedEnd: nil,
            blindName: blindName,
            blindPhone: nil,
            volunteerPhone: nil,
            acceptedAt: nil,
            createdAt: createdAt,
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
}
