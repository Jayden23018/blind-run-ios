import XCTest
@testable import blindRun

/// 陪跑员端订单页那一屏的内容判定（设计交付文档 v3 §5 的前三态）。
///
/// 这一屏的错误形态**全是静默的**：文案说错一态、按钮在不该出现的态出现、
/// 接单前漏出盲人的自由文本 —— 屏幕上都不会报错，跑起来也不崩。
/// 所以断言全部打在纯函数上，而且每条都挑**能区分正确实现与错误实现**的取值。
final class VolunteerOrderFlowPresentationTests: XCTestCase {

    // MARK: - 状态 → 哪一格

    /// 12 个状态逐个断言，不用集合字面量。
    ///
    /// 这条挡的是「用 `Set` 判归属」那种写法：集合会把后端新加的状态默默判成 `nil`，
    /// 而那表现为志愿者的订单页整屏空白 —— 他看不到任何可做的事，而盲人正在等他。
    func testEveryStatusLandsInExactlyOneStepOrNowhere() {
        let expected: [RunOrderStatus: VolunteerOrderFlowStep?] = [
            .pendingMatch: .invited,
            // 通话磨合藏在「邀请」这一格内部：这一态 `order.volunteer` 仍为 null，
            // 志愿者**还没接单**，画成「约好」是告诉他一件没发生的事。
            .pendingIntroCall: .invited,
            .rematching: .invited,
            .scheduledConfirmed: .booked,
            .pendingAccept: .booked,
            .driverEnRoute: .departed,
            .driverArrived: .metUp,
            .inProgress: .metUp,
            .completed: nil,
            .cancelled: nil,
            .noVolunteer: nil,
            // 认不出的状态不落进任何一格 —— 画成「邀请」会让志愿者以为有单要接。
            .unknown: nil
        ]

        // ⚠️ `RunOrderStatus.allCases` **刻意不含 `.unknown`**（那不是一个真实状态，
        // 不该进状态机遍历，见该属性上的注释）。所以这里要显式把它并回来 ——
        // 少了它，「未知态落在哪一格」这个判断就没有任何东西看着，
        // 而把未知态画成「邀请」会让志愿者以为有单要接。
        XCTAssertEqual(
            Set(expected.keys),
            Set(RunOrderStatus.allCases).union([.unknown]),
            "后端加了状态而这张表没跟：新状态会被默默判成 nil，订单页整屏空白"
        )
        for (status, step) in expected {
            XCTAssertEqual(status.volunteerOrderFlowStep, step, "\(status.rawValue) 落错格")
        }
    }

    /// 汇合与跑步中**本轮还没搬过来**，`make(order:)` 必须回 `nil` 让调用方退回旧面板。
    ///
    /// 不回 `nil` 的后果不是编译错，是渲染出半页没有结束按钮的骨架 ——
    /// 而志愿者是唯一能结束服务的人。
    func testMetUpAndTerminalStatusesDoNotRenderTheFirstThreeSteps() {
        for status in [RunOrderStatus.driverArrived, .inProgress, .completed, .cancelled, .noVolunteer, .unknown] {
            XCTAssertNil(
                VolunteerOrderFlowPresentation.make(
                    order: .preview(status: status),
                    distanceText: nil
                ),
                "\(status.rawValue) 本轮不该走四步骨架"
            )
        }
    }

    // MARK: - 主按钮

    /// 🔴 **这一条是本文件里最要紧的一条。**
    ///
    /// `SCHEDULED_CONFIRMED` 与 `PENDING_ACCEPT` 落在**同一格**（约好），但主按钮不同：
    /// 前者要先回答「你还去吗」（`confirm-departure`），后者才是「我出发了」（`en-route`）。
    /// 后端刻意把这两件事分开 —— 合并会让双向位置互推提前几小时打开（`AGENTS.md` §5）。
    ///
    /// 「按格子发按钮」是写这一屏时最自然的错误实现，而它在屏幕上完全看不出来：
    /// 跨天预约单照样显示一枚黄按钮，只是按下去后端回 409。这条用例在那种实现下必红。
    func testTwoStatusesShareTheBookedStepButNotThePrimaryAction() {
        let scheduled = VolunteerOrderFlowPresentation.make(
            order: .preview(status: .scheduledConfirmed),
            distanceText: nil
        )
        let pendingAccept = VolunteerOrderFlowPresentation.make(
            order: .preview(status: .pendingAccept),
            distanceText: nil
        )

        XCTAssertEqual(scheduled?.step, .booked)
        XCTAssertEqual(pendingAccept?.step, .booked, "两态必须同格 —— 否则这条用例就不再是它要验的那件事")
        XCTAssertEqual(scheduled?.primaryAction, .confirmDeparture)
        XCTAssertEqual(pendingAccept?.primaryAction, .enRoute)
        XCTAssertNotEqual(
            scheduled?.primaryAction,
            pendingAccept?.primaryAction,
            "同一格里两态的主按钮被写成了同一个 —— 按格子发按钮的实现就是这个样子"
        )
    }

    func testDepartedGivesTheArrivedButton() {
        let presentation = VolunteerOrderFlowPresentation.make(
            order: .preview(status: .driverEnRoute),
            distanceText: nil
        )
        XCTAssertEqual(presentation?.step, .departed)
        XCTAssertEqual(presentation?.primaryAction, .arrived)
        XCTAssertEqual(presentation?.primaryAction?.title, VolunteerOrderFlowCopy.arrived)
    }

    /// 发 `ACCEPT` 还是 `INTERESTED` **只认推送里的 `requiresIntroCall`**，客户端不许自己算。
    ///
    /// 两条断言方向相反，缺一条都拦不住真正的错误实现：
    /// - 按钮文案**必须相同** —— 志愿者要做的决定是同一个，「先聊聊还是直接接」是后端机制；
    /// - 带的 action **必须不同** —— 发错会被后端 409，而志愿者看到的是「点了没反应」。
    ///
    /// 「按文案反推 action」或者「一律发 ACCEPT」这两种写法各会被其中一条打红。
    func testAcceptInviteKeepsOneTitleWhileTheRespondActionFollowsThePush() {
        let strangers = VolunteerOrderFlowPresentation.make(
            dispatch: OrderDetailResponse.previewDispatch(requiresIntroCall: true),
            remainingSeconds: 30
        )
        let acquaintances = VolunteerOrderFlowPresentation.make(
            dispatch: OrderDetailResponse.previewDispatch(requiresIntroCall: false),
            remainingSeconds: 30
        )

        XCTAssertEqual(strangers.primaryAction?.title, VolunteerOrderFlowCopy.acceptInvite)
        XCTAssertEqual(
            acquaintances.primaryAction?.title,
            strangers.primaryAction?.title,
            "两种情况下按钮上的字必须一样 —— 后端机制不该变成志愿者要理解的两个按钮"
        )
        XCTAssertEqual(strangers.primaryAction, .acceptInvite(respond: .interested))
        XCTAssertEqual(acquaintances.primaryAction, .acceptInvite(respond: .accept))
    }

    // MARK: - 接单前的隐私闸

    /// 自由文本在接单**前**一律不可见（`AGENTS.md` §8）。
    ///
    /// 用例同时给 `routeNotes` 与 `specialNotes` 赋值，然后断言**两个都没出现在任何一行里**。
    /// 挑 `PENDING_INTRO_CALL` 是因为它最像「已经接单了」——订单锁给了这位候选人，
    /// 但一单最多聊 3 位，展示等于交给这一单碰到的每一个人。
    ///
    /// 把 `disclosesBlindRunnerNotesToVolunteer` 那道闸删掉，这条立刻红。
    func testFreeTextStaysHiddenUntilTheVolunteerIsActuallyOnTheOrder() {
        let notes = "我有低血糖，如果我说头晕请马上停下来"
        let route = "沿湖边跑道，不要走机动车道"

        for status in [RunOrderStatus.pendingMatch, .pendingIntroCall, .rematching] {
            XCTAssertFalse(
                status.disclosesBlindRunnerNotesToVolunteer,
                "\(status.rawValue) 是接单前，自由文本不该可见"
            )
        }

        let booked = VolunteerOrderFlowPresentation.make(
            order: .preview(status: .pendingAccept, routeNotes: route, specialNotes: notes),
            distanceText: nil
        )
        let joined = booked?.rows.map { [$0.value, $0.detail ?? ""].joined() }.joined() ?? ""
        XCTAssertTrue(joined.contains(notes), "接单后这两行本该出现 —— 不出现说明这条用例验的不是闸")
        XCTAssertTrue(joined.contains(route))
    }

    /// 派单载荷里**本来就没有**自由文本、姓名、视力程度与引导方式。
    ///
    /// 这条钉的是「不编、不占位」：拿不到的东西整行不渲染，而不是印一个猜的值。
    /// 给还没见面的志愿者印一个猜的视力程度，见面第一下就会抓错人。
    func testInviteScreenOnlyShowsWhatThePushActuallyCarries() {
        let presentation = VolunteerOrderFlowPresentation.make(
            dispatch: OrderDetailResponse.previewDispatch(hasGuideDog: true),
            remainingSeconds: 30
        )
        let ids = presentation.rows.map(\.id)

        XCTAssertFalse(ids.contains("runner"), "派单载荷没有跑者姓名，不该有跑者行")
        XCTAssertFalse(ids.contains("phone"), "接单前不下发号码")
        XCTAssertFalse(ids.contains("routeNotes"))
        XCTAssertFalse(ids.contains("specialNotes"))
        XCTAssertFalse(
            ids.contains("escort-vision"),
            "`visionLevel` 不在派单载荷里 —— 出现就说明有人给它填了默认值"
        )
        XCTAssertTrue(ids.contains("escort-guideDog"), "导盲犬是派单载荷里唯一能给的一条")
        XCTAssertTrue(ids.contains("plannedDistance"))
        XCTAssertTrue(ids.contains("decline"))
    }

    // MARK: - 姓名与号码

    /// 姓名**屏幕上带星号、读屏里不带**。
    ///
    /// 后端的 `blindName` 始终掩码（契约逐字「不存在明文版本」），原样交给 VoiceOver
    /// 会念成「李星号」，而陪跑员端的读屏同样是外放的。
    /// 两个方向一起断：只断读屏的话，把屏幕上的星号也去掉不会有人发现，
    /// 而那会让人以为拿到了全名。
    func testRunnerNameKeepsTheMaskOnScreenAndDropsItForSpeech() {
        let presentation = VolunteerOrderFlowPresentation.make(
            order: .preview(status: .pendingAccept, blindName: "李*"),
            distanceText: nil
        )
        let runner = presentation?.rows.first { $0.id == "runner" }

        XCTAssertEqual(runner?.value, "李*", "屏幕上必须保留掩码")
        XCTAssertFalse(runner?.accessibilityLabel.contains("*") ?? true, "读屏会把星号念成「星号」")
        XCTAssertTrue(runner?.accessibilityLabel.contains("李") ?? false)
    }

    /// 号码：屏幕上掩码、读屏里**一个数字都没有**、行本身可点（拨号）。
    ///
    /// `AGENTS.md` §8 的硬规则是「接单后展示掩码号码**并给出拨号入口**」——
    /// 两半都要，只做掩码等于把志愿者唯一能联系上跑者的出口删掉。
    func testPhoneRowShowsAMaskedNumberAndNeverSpeaksDigits() {
        let presentation = VolunteerOrderFlowPresentation.make(
            order: .preview(status: .pendingAccept, blindPhone: "13800001001"),
            distanceText: nil
        )
        let phone = presentation?.rows.first { $0.id == "phone" }

        XCTAssertEqual(phone?.value, "138****1001")
        XCTAssertEqual(phone?.action, .callRunner)
        XCTAssertFalse(
            phone?.accessibilityLabel.contains("1") ?? true,
            "读屏外放，念号码等于把跑者的电话广播给周围所有人"
        )
    }

    /// 掩码串拿不出可拨的 URL ⇒ **整行不渲染**，而不是渲染一个按下去拨错人的按钮。
    ///
    /// 判据走 `EmergencyDialer.telURL` 而不是「字符串非空」：`138****1001` 会被拼成
    /// `tel://1381001`，一个七位的、可能真打给别人的号码。
    func testAMaskedPhoneFromTheBackendProducesNoDialRow() {
        let presentation = VolunteerOrderFlowPresentation.make(
            order: .preview(status: .pendingAccept, blindPhone: "138****1001"),
            distanceText: nil
        )
        XCTAssertNil(
            presentation?.rows.first { $0.id == "phone" },
            "契约说号码要么明文可拨要么 null；真收到掩码串时宁可不给拨号入口"
        )
    }

    // MARK: - hero

    /// 出发态副标题**只有距离，没有 ETA**。
    ///
    /// 设计稿那句「8 分钟后到」做不出来（后端没有出发地、交通方式与 ETA 字段）。
    /// 断言挑两种取值对比：传距离时它出现、不传时副标题为空 ——
    /// 「随便填个数字顶上」的实现会让第二条红。
    func testDepartedSubtitleCarriesTheDistanceAndNothingElse() {
        let withDistance = VolunteerOrderFlowPresentation.make(
            order: .preview(status: .driverEnRoute),
            distanceText: "距出发地点约 600 米"
        )
        let withoutDistance = VolunteerOrderFlowPresentation.make(
            order: .preview(status: .driverEnRoute),
            distanceText: nil
        )

        XCTAssertEqual(withDistance?.title, VolunteerOrderFlowCopy.departedTitle)
        XCTAssertEqual(withDistance?.subtitle, "距出发地点约 600 米")
        XCTAssertEqual(withoutDistance?.subtitle, "", "拿不到距离就什么都不说，不摆一个编出来的到达时间")
        XCTAssertFalse(withDistance?.title.contains("分钟后到") ?? true)
    }

    /// 跨天预约那一态的副标题要说清**后果**（不确认会转给别人），
    /// 而且**不许出现具体提前量** —— 那是后端配置 `departure-confirm-window-minutes`，
    /// 客户端读不到，写死就是编一个数字念给志愿者听。
    func testScheduledSubtitleExplainsTheConsequenceWithoutInventingALeadTime() {
        let scheduled = VolunteerOrderFlowPresentation.make(
            order: .preview(status: .scheduledConfirmed),
            distanceText: nil
        )
        let pendingAccept = VolunteerOrderFlowPresentation.make(
            order: .preview(status: .pendingAccept),
            distanceText: nil
        )

        XCTAssertNotEqual(
            scheduled?.subtitle,
            pendingAccept?.subtitle,
            "跨天预约多一件必须做的事，副标题不能和待出发那态说同一句话"
        )
        XCTAssertTrue(scheduled?.subtitle.contains("转给其他志愿者") ?? false)
        for digit in ["小时", "分钟"] {
            XCTAssertFalse(
                scheduled?.subtitle.contains(digit) ?? true,
                "副标题里出现了时间量 —— 提前量是后端配置，客户端算它就是第二个源"
            )
        }
    }

    // MARK: - 求助与安全

    /// 前三态底部**不给**「求助与安全」。
    ///
    /// 陪跑员端没有安全中心，而这三态的云端 SOS 本来就关着（`AGENTS.md` §6：
    /// 两端入口都只在 `IN_PROGRESS` 开放）。摆一个按下去无事发生的紧急入口比没有更糟 ——
    /// 与骨架刚落地时盲人端那次「长按 3 秒之后屏幕零变化」是同一类事故。
    func testNoSafetyHubBeforeTheRunActuallyStarts() {
        let invite = VolunteerOrderFlowPresentation.make(
            dispatch: OrderDetailResponse.previewDispatch(),
            remainingSeconds: 30
        )
        XCTAssertFalse(invite.showsSafetyHub)

        for status in [RunOrderStatus.scheduledConfirmed, .pendingAccept, .driverEnRoute] {
            XCTAssertFalse(
                VolunteerOrderFlowPresentation.make(order: .preview(status: status), distanceText: nil)?
                    .showsSafetyHub ?? true,
                "\(status.rawValue) 的云端求助是关着的，底部不该有入口"
            )
            XCTAssertFalse(
                status.canVolunteerTriggerEmergency,
                "这条用例的前提变了：该状态现在能触发云端求助，底部版位要重新讨论"
            )
        }
    }

    // MARK: - 回复倒计时

    /// 邀请态的回复期限**不并进副标题**：它每秒都变，合进去会让状态卡那个合成的
    /// 无障碍元素每秒被读屏重念一遍。
    func testReplyCountdownStaysOutOfTheStatusSubtitle() {
        let presentation = VolunteerOrderFlowPresentation.make(
            dispatch: OrderDetailResponse.previewDispatch(),
            remainingSeconds: 25
        )
        XCTAssertEqual(presentation.replyNotice, "还剩 25 秒回复")
        XCTAssertFalse(presentation.subtitle.contains("25"))
        XCTAssertFalse(presentation.isReplyUrgent)
    }

    /// 紧迫阈值取在**边界两侧**，而不是随手取一个明显该红的值。
    ///
    /// 10 与 11 分别落在 `<=` 的两边：把判据写成 `< 10` 的实现在第一条上红，
    /// 写成 `<= 15` 的在第二条上红。取 3 和 30 两个值则两种错误实现都测不出来。
    func testReplyUrgencyFlipsExactlyAtTheNamedThreshold() {
        func urgent(_ seconds: Int) -> Bool {
            VolunteerOrderFlowPresentation.make(
                dispatch: OrderDetailResponse.previewDispatch(),
                remainingSeconds: seconds
            ).isReplyUrgent
        }

        XCTAssertEqual(VolunteerOrderFlowCopy.urgentCountdownSeconds, 10)
        XCTAssertTrue(urgent(10), "恰好到阈值就算紧迫")
        XCTAssertFalse(urgent(11), "阈值上面一秒还不算")
    }

    // MARK: - 「我去不了」的按钮与对话框必须同词

    /// 按钮上换了词、对话框里没换，等于那次改名没做 —— 而对话框才是他真正下决心的那一屏。
    ///
    /// 这条补的是 `ScheduledOrderTests.testReleaseAndCancelDoNotShareCopy` 注释里逐字记着的洞：
    /// 那条用例只覆盖按钮标题，覆盖不到对话框（它当时是 View 的 private 属性，测试够不着）。
    func testReleaseRowAndItsConfirmationDialogUseTheSameWord() {
        for status in [RunOrderStatus.scheduledConfirmed, .pendingAccept, .driverEnRoute] {
            let presentation = VolunteerOrderFlowPresentation.make(
                order: .preview(status: status),
                distanceText: nil
            )
            let row = presentation?.rows.first { $0.id == "release" }
            XCTAssertEqual(row?.value, VolunteerOrderFlowCopy.releaseOrder, "\(status.rawValue) 的退出行文案不对")
            XCTAssertEqual(row?.action, .releaseOrder)

            let dialog = VolunteerOrderFlowCopy.cancelDialog(for: status)
            XCTAssertTrue(
                dialog.title.contains("去不了"),
                "\(status.rawValue)：按钮说「去不了」而对话框说「\(dialog.title)」"
            )
            XCTAssertTrue(dialog.message.contains("转给其他志愿者"), "对话框要说清后果：这一单换个人，不是替盲人取消")
        }

        // 反向：还没搬过来的两态仍走旧词，说明这条判据真的在按状态分流。
        XCTAssertFalse(VolunteerOrderFlowCopy.cancelDialog(for: .inProgress).title.contains("去不了"))
    }

    // MARK: - 「跑多远 / 配速」的格式化

    func testPlannedDistanceDropsTheTrailingZeroAndFallsBackToMeters() {
        XCTAssertEqual(RunPlanFormat.plannedDistance(meters: 5000), "5 公里")
        XCTAssertEqual(RunPlanFormat.plannedDistance(meters: 5500), "5.5 公里")
        XCTAssertEqual(RunPlanFormat.plannedDistance(meters: 800), "800 米")
        // 1000 是「米 / 公里」那条边界本身：写成 `> 1000` 的实现会在这里输出「1000 米」。
        XCTAssertEqual(RunPlanFormat.plannedDistance(meters: 1000), "1 公里")
        XCTAssertNil(RunPlanFormat.plannedDistance(meters: nil))
        XCTAssertNil(RunPlanFormat.plannedDistance(meters: 0), "0 米不是「跑 0 公里」，是没填")
    }

    /// 区间两端**成对出现或成对缺席**（契约逐字）。只拿到一端时退回定性档位，
    /// 而不是把一端当成整个区间 —— 后者会把「最快 6 分半」显示成「配速 6 分半」，
    /// 而志愿者据此判断的是「我跟不跟得下来」。
    func testPaceUsesTheRangeWhenBothEndsArriveAndDegradesHonestlyOtherwise() {
        XCTAssertEqual(
            RunPlanFormat.pace(minSecondsPerKm: 390, maxSecondsPerKm: 450, preference: .moderate),
            "每公里 6 分 30 秒 到 7 分 30 秒"
        )
        // 两端相同时不说「到」——「每公里 6 分 30 秒 到 6 分 30 秒」是句废话。
        XCTAssertEqual(
            RunPlanFormat.pace(minSecondsPerKm: 390, maxSecondsPerKm: 390, preference: nil),
            "每公里 6 分 30 秒"
        )
        XCTAssertEqual(
            RunPlanFormat.pace(minSecondsPerKm: 390, maxSecondsPerKm: nil, preference: .moderate),
            "中等",
            "只有一端时必须退回档位 —— 拿一端当区间会让志愿者按错的数判断跟不跟得下来"
        )
        XCTAssertNil(RunPlanFormat.pace(minSecondsPerKm: 360, maxSecondsPerKm: nil, preference: nil))
        // 整分钟不念秒。
        XCTAssertEqual(
            RunPlanFormat.pace(minSecondsPerKm: 360, maxSecondsPerKm: 360, preference: nil),
            "每公里 6 分"
        )
        // 「无偏好」不是信息，一行「配速：无偏好」只会占掉读屏用户一次划动。
        XCTAssertNil(RunPlanFormat.pace(minSecondsPerKm: nil, maxSecondsPerKm: nil, preference: .noPreference))
        XCTAssertNil(RunPlanFormat.pace(minSecondsPerKm: nil, maxSecondsPerKm: nil, preference: .unknown))
    }
}
