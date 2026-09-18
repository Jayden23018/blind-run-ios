import XCTest
@testable import blindRun

/// 汇合 → 倒计时 → 跑步中这三幕的**原地变形**判据。
///
/// 与 `BlindOrderFlowPresentationTests` 的分工：那个文件验前四格（匹配 / 约好 / 出发 / 汇合）
/// 的状态映射与文案，本文件只验**相位**这个新维度 —— 它是设计交接 2026-09-16 的核心结论
/// 「跑步中不是新页面，而是订单页原地变形」在代码里的承载。
///
/// 这一屏的错误形态仍然全是**静默**的：相位落错、主按钮版位空掉、倒计时演在错的状态上，
/// 屏幕上都不会报任何错，而盲人只会觉得「刚才那一下按了没反应」。
final class BlindRunPhaseTests: XCTestCase {

    // MARK: - 相位 = 订单状态 + 本地倒计时

    /// 🔴 **两个输入缺一不可。**
    ///
    /// 这条用例的取值是挑过的：第一组（`DRIVER_ARRIVED` + 倒计时 3）就是用来分辨
    /// 「相位只看 `countdown`」这种实现的 —— 那种写法会在**正在匹配 / 已约好**那几屏上
    /// 凭空倒数三秒，也就是向盲人承诺一件不会发生的事。只验后两组分辨不出它。
    func testPhaseNeedsBothTheStatusAndTheLocalCountdown() {
        XCTAssertEqual(
            make(.driverArrived, countdown: 3).phase, .beforeRun,
            "还没开跑就倒数：相位只看了 countdown，没看订单状态"
        )
        XCTAssertEqual(make(.inProgress, countdown: 3).phase, .countdown(3))
        XCTAssertEqual(make(.inProgress, countdown: nil).phase, .running)
        // 前三格恒为 `.beforeRun`，与 countdown 无关。
        for status in [RunOrderStatus.pendingMatch, .scheduledConfirmed, .driverEnRoute] {
            XCTAssertEqual(make(status, countdown: 2).phase, .beforeRun, "\(status) 不该有倒计时")
        }
    }

    /// `IN_PROGRESS` 与汇合**同一格**，走同一个骨架。
    ///
    /// 2026-09-16 之前它落 `nil`、由一个独立的深底执行屏接管 —— 而 iOS 切页时 VoiceOver
    /// 会把焦点移回第一个元素，读屏用户每次都要从头找。这条是那次跳页被消掉的守卫。
    func testRunningStaysOnTheSameSkeletonStepAsMetUp() {
        XCTAssertEqual(RunOrderStatus.inProgress.blindOrderFlowStep, .metUp)
        XCTAssertEqual(make(.inProgress).step, make(.driverArrived).step)
    }

    // MARK: - ② 倒计时

    /// 倒计时那一幕**只换四样东西**：视觉区、标题、副标题、主按钮。
    /// 进度条、信息卡、按钮位置全部不动（设计稿 §2 第一句）。
    func testCountdownOnlySwapsFourThingsAndKeepsTheRest() {
        let countdown = make(.inProgress, countdown: 3)
        let metUp = make(.driverArrived)

        XCTAssertEqual(countdown.visual, .countdown(3))
        XCTAssertEqual(countdown.title, "准备开始")
        XCTAssertEqual(countdown.subtitle, "握好引导绳")
        XCTAssertEqual(countdown.primaryAction, .preparing)

        // 没换的那两样。信息列表最后一行跟着汇合那一屏走 —— 倒计时中途被打断退回去时
        // 不该闪一下别的字。
        XCTAssertEqual(countdown.step, metUp.step)
        XCTAssertEqual(countdown.lastRowTitle, metUp.lastRowTitle)
    }

    /// 「准备中」必须是**不可点**的。
    ///
    /// 🔴 判据落在 `isEnabled` 上而不是「按下去什么都不发生」：视图据它走 `.disabled()`，
    /// 而 `.disabled()` 除了阻断点击还会给无障碍元素打上「不可用」—— VoiceOver 念「变暗」。
    /// 只在回调里 `guard ... return` 的话，读屏里它仍是一个完全正常的按钮，
    /// 盲人双击之后什么都不发生、什么都不念。
    func testPreparingButtonIsDisabledAndCarriesNoIcon() {
        let action = BlindOrderFlowPresentation.PrimaryAction.preparing
        XCTAssertFalse(action.isEnabled)
        XCTAssertEqual(action.title, "准备中")
        // 换图标会让按钮内容宽度变一次，而这一屏的全部承诺是「主按钮位置一格不动」。
        XCTAssertNil(action.systemImage)
    }

    /// 节拍参数是行为规格，不是装饰。散进视图之后只能靠真机掐秒表才能核对。
    func testCountdownRunsThreeBeatsOfOneSecond() {
        XCTAssertEqual(BlindRunCountdown.beats, [3, 2, 1])
        XCTAssertEqual(BlindRunCountdown.beatInterval, 1)
        XCTAssertEqual(BlindRunCountdown.totalDuration, 3)
        XCTAssertEqual(BlindRunCountdown.bounceScale, 1.25)
    }

    // MARK: - ③ 跑步中

    func testRunningSwapsTheHeaderAndTheMainButton() {
        let running = make(.inProgress)

        XCTAssertEqual(running.visual, .runMetrics)
        XCTAssertEqual(running.primaryAction, .announceStats)
        XCTAssertEqual(running.primaryAction?.title, "播报当前数据")
        // SF Symbols，不是 HTML 原型里那些手绘 SVG 占位。
        XCTAssertEqual(running.primaryAction?.systemImage, "speaker.wave.2.fill")
    }

    /// 顶行用「陪跑中」而不是 `RunOrderStatus.displayName`（那是「进行中」），
    /// 且**姓名去掉掩码星号** —— 读屏是外放的，`张*` 会被念成「张星号」。
    func testPartnerHeadlineUsesTheDesignWordAndStripsTheMask() {
        let running = make(.inProgress, volunteerName: "张*")
        XCTAssertEqual(running.title, "陪跑中 · 张")
        XCTAssertFalse(running.title.contains("*"), "顶行留着掩码星号")
        XCTAssertNotEqual(
            running.title, "\(RunOrderStatus.inProgress.displayName) · 张",
            "顶行不该复用 displayName —— 那是「进行中」，而设计要的是「陪跑中」"
        )
    }

    /// 副标题是**空串**，而读屏标签不许因此多出一个句号。
    ///
    /// 这条盯的是 `BlindOrderFlowView.statusAccessibilityLabel` 里那个 `filter`：
    /// 漏掉它的写法（直接 `joined(separator: "。")`）会让 VoiceOver 在这一屏的
    /// 第一个焦点上念出一次多余的停顿，而屏幕上看不出任何异常。
    func testRunningHasNoSubtitleSoTheSpokenLabelStaysClean() {
        let running = make(.inProgress)
        XCTAssertEqual(running.subtitle, "")

        let parts = [running.title, running.subtitle].filter { !$0.isEmpty }
        XCTAssertEqual(parts.joined(separator: "。"), "陪跑中 · 张")
    }

    // MARK: - ④ 已完成

    /// 已完成与跑步中**同一张卡**：进度条仍然折叠、内容区仍然是三个数字，
    /// 换的只有顶行那句话、配速标签、多出来的陪跑员行与主按钮（设计稿 §4）。
    func testFinishedKeepsTheRunCardAndOnlySwapsTheHeaderAndTheButton() {
        let finished = make(.completed)

        XCTAssertEqual(finished.phase, .finished)
        XCTAssertEqual(finished.visual, .runMetrics)
        XCTAssertEqual(finished.title, "已完成 · 张")
        XCTAssertFalse(finished.title.contains("*"), "顶行留着掩码星号")
        XCTAssertEqual(finished.subtitle, "", "这一屏的信息全在三个数字里，没有第二行状态文字")
        XCTAssertEqual(finished.primaryAction, .done)
        XCTAssertEqual(finished.primaryAction?.title, "完成")
        // 稿上这一枚是纯文字。换图标会让按钮内容宽度再变一次，而从 ① 到 ④ 的承诺是
        // 「主按钮位置一格不动」。
        XCTAssertNil(finished.primaryAction?.systemImage)
        XCTAssertTrue(finished.primaryAction?.isEnabled == true)
        // 跑完之后不再显示定位新鲜度：那一刻「定位信号弱」没有任何可执行的动作。
        XCTAssertNil(finished.warning)
    }

    /// `COMPLETED` 与汇合 / 跑步中**同一格**，走同一个骨架。
    ///
    /// 2026-09-17 之前它落 `nil`、由改版前那条只读滚动列表接管 —— 也就是说
    /// 陪跑员结束那一刻整屏重建一次，VoiceOver 焦点被打回顶部。
    /// 这条是那次跳页被消掉的守卫。
    func testFinishedStaysOnTheSameSkeletonStepAsTheRun() {
        XCTAssertEqual(RunOrderStatus.completed.blindOrderFlowStep, .metUp)
        XCTAssertEqual(make(.completed).step, make(.inProgress).step)
        XCTAssertEqual(make(.completed).step, make(.driverArrived).step)
    }

    /// 🔴 **`isRunning` 与 `showsRunCard` 不是一回事，合并会让 ④ 丢掉导航栏那枚图标。**
    ///
    /// 「重复当前状态」按项目负责人 2026-09-16 决策 2 出现在 ①②④、只在 ③ 收起
    /// （③ 由主按钮「播报当前数据」承担），而视图那一处的判据就是 `isRunning`。
    /// 把已完成并进 `isRunning` 的写法在别的断言下全绿 —— 只有这条分辨得出来。
    func testFinishedUsesTheRunCardButIsNotTheRunItself() {
        XCTAssertTrue(BlindRunPhase.finished.showsRunCard)
        XCTAssertTrue(BlindRunPhase.running.showsRunCard)
        XCTAssertFalse(BlindRunPhase.beforeRun.showsRunCard)
        XCTAssertFalse(BlindRunPhase.countdown(3).showsRunCard)

        XCTAssertFalse(
            BlindRunPhase.finished.isRunning,
            "已完成被当成了跑步中 —— 导航栏那枚「重复当前状态」会在 ④ 被收起，而它是那一屏唯一能听全数据的入口"
        )
    }

    /// 已完成那一屏配速标签是「平均配速」，跑步中仍是「配速」（设计稿 §4 逐字）。
    ///
    /// 判据只有一份（`BlindRunCopy.metricPaceLabel`），因为屏幕上写「配速」而
    /// 「重复当前状态」念「平均配速」这种漂移只有拿耳朵对着屏幕才听得出来。
    func testFinishedRenamesThePaceLabelToAveragePace() {
        XCTAssertEqual(BlindRunCopy.metricPaceLabel(isFinished: true), "平均配速")
        XCTAssertEqual(BlindRunCopy.metricPaceLabel(isFinished: false), "配速")
    }

    /// 已完成不倒数，**即使外面还攥着一个没清掉的 `countdown`**。
    ///
    /// 时序上真会撞：志愿者点开始、三秒内就长按结束，此时倒计时 Task 还没走完。
    /// 对一件已经结束的事倒数，在屏幕上看着只是「数字闪了一下」。
    func testFinishedIgnoresALeftoverCountdown() {
        XCTAssertEqual(make(.completed, countdown: 2).phase, .finished)
    }

    // MARK: - ④ 完成那一句播报

    /// 一次状态推进只播一句，且**冷启动与「刚刚结束」不是同一句**。
    func testCompletionAnnouncementFiresOncePerTransition() {
        XCTAssertEqual(
            BlindOrderStatusViewModel.completionAnnouncement(from: .inProgress, to: .completed),
            .justFinished
        )
        // 每 5 秒轮询一次。漏掉这条的症状是每 5 秒念一遍「张伟结束了本次陪跑」。
        XCTAssertNil(
            BlindOrderStatusViewModel.completionAnnouncement(from: .completed, to: .completed),
            "同一态的重复刷新又播了一遍"
        )
        // 从历史记录点进一张三天前的单。
        XCTAssertEqual(
            BlindOrderStatusViewModel.completionAnnouncement(from: nil, to: .completed),
            .coldStart
        )
        // 别的状态一律不走这条路（它们照旧走 `speakStatusChange` 那条通用路径）。
        for status in RunOrderStatus.allCases + [.unknown] where status != .completed {
            XCTAssertNil(
                BlindOrderStatusViewModel.completionAnnouncement(from: .inProgress, to: status),
                "\(status) 不该播完成那一句"
            )
        }
    }

    /// 「刚刚结束」那句 = 设计稿文案 + 里程；**拿不到里程就把那半句整个去掉**。
    ///
    /// ⚠️ 里程这一半是这条用例的全部价值：不带它的实现（只念「张伟结束了本次陪跑」）
    /// 在屏幕上、在别的断言里都看不出区别，而设计稿 §4 的文案逐字带着它。
    func testJustFinishedAnnouncementCarriesTheDistanceAndNeverInventsIt() {
        let order = OrderDetailResponse.preview(status: .completed, volunteerName: "张*")

        XCTAssertEqual(
            BlindOrderStatusViewModel.completionAnnouncementText(
                .justFinished, order: order, stats: .previewFinished
            ),
            "张结束了本次陪跑，共跑 5.20 公里。"
        )
        XCTAssertEqual(
            BlindOrderStatusViewModel.completionAnnouncementText(
                .justFinished, order: order, stats: nil
            ),
            "张结束了本次陪跑。",
            "拿不到里程时不许留「共跑 -- 公里」，也不许念「正在获取」—— 这一句是通知，不是数据面"
        )
    }

    /// 冷启动那句 = 既有状态句 + 三个数字，**合成一句**。
    ///
    /// 改版前这里是两句（状态句 + 轨迹总结），而两句同档 ⇒ 后到的把先到的从半句切断
    /// （记忆 `later-speak-silently-cuts-the-earlier-one`）。所以这条断言的关键是
    /// **一个字符串里同时有状态和三个数字**。
    func testColdStartAnnouncementMergesTheStatusAndTheNumbersIntoOneUtterance() {
        let order = OrderDetailResponse.preview(status: .completed, volunteerName: "张*")
        let text = BlindOrderStatusViewModel.completionAnnouncementText(
            .coldStart, order: order, stats: .previewFinished
        )

        XCTAssertTrue(text.contains("服务已完成"), "状态那一半丢了")
        XCTAssertTrue(text.contains("已跑 5.20 公里"), "数字那一半丢了 —— 它原先由被删掉的那句轨迹总结承担")
        XCTAssertTrue(text.contains("用时 33 分 41 秒"))
        XCTAssertTrue(text.contains("平均配速 6 分 28 秒每公里"))
        XCTAssertFalse(text.contains("张结束了本次陪跑"), "三天前的事不该说成刚刚发生")
    }

    // MARK: - ④ 那三个数字的来源

    /// 🔴 **完成态必须拉一次终值、并且把数字留在屏幕上。**
    ///
    /// 2026-09-17 之前这里对任何非 `IN_PROGRESS` 一律清空 —— 而 ④ 那一屏的全部内容
    /// 就是那三个数字，清空之后它们是 `--`。
    func testFinalTrackIsFetchedOnceAndTheNumbersSurviveCompletion() {
        let now = Date()
        // 完成那一刻：上一次跑动中的拉取往往还在 10 秒节流窗内，但终值必须拉。
        XCTAssertEqual(
            BlindOrderStatusViewModel.trackFetchDecision(
                status: .completed,
                didFetchFinalTrack: false,
                lastFetchAt: now.addingTimeInterval(-1),
                now: now
            ),
            .fetch(isFinal: true),
            "完成那一次被节流挡掉了 —— 屏幕会停在最后一个中途值"
        )
        // 拉过就不再拉，但**不清空**：已完成的轨迹不会再变。
        XCTAssertEqual(
            BlindOrderStatusViewModel.trackFetchDecision(
                status: .completed, didFetchFinalTrack: true, lastFetchAt: now, now: now
            ),
            .skip,
            "完成态第二轮把数字清了 —— ④ 那一屏会变成三个杠"
        )
    }

    /// 跑动中照旧按 10 秒节流，其余状态照旧清空。
    func testTrackFetchStillThrottlesDuringTheRunAndClearsElsewhere() {
        let now = Date()
        XCTAssertEqual(
            BlindOrderStatusViewModel.trackFetchDecision(
                status: .inProgress, didFetchFinalTrack: false, lastFetchAt: nil, now: now
            ),
            .fetch(isFinal: false)
        )
        XCTAssertEqual(
            BlindOrderStatusViewModel.trackFetchDecision(
                status: .inProgress,
                didFetchFinalTrack: false,
                lastFetchAt: now.addingTimeInterval(-3),
                now: now
            ),
            .skip,
            "跑动中漏了节流 —— 每 5 秒多发一个 /track"
        )
        for status in RunOrderStatus.allCases + [.unknown]
        where status != .inProgress && status != .completed {
            XCTAssertEqual(
                BlindOrderStatusViewModel.trackFetchDecision(
                    status: status, didFetchFinalTrack: false, lastFetchAt: nil, now: now
                ),
                .clear,
                "\(status) 不该留着上一段的数字"
            )
        }
    }

    // MARK: - 不变量：主按钮位置永不变化

    /// ①②③④ 四幕的主按钮版位**都是满的**。
    ///
    /// 位置本身只有真机能量，但「版位空不空」正是它唯一会出错的方式：任何一幕落 `nil`，
    /// 那一幕的底部就从两个按钮变成一个，「求助与安全」整块上移约 76pt ——
    /// 而视障用户靠的就是那块的物理位置。
    ///
    /// ⚠️ 已知缺口（**不是这次改出来的**）：① 汇合的主按钮是「打电话给张伟」，
    /// 拿不到可拨号码时这一格是空的。后端契约保证 `volunteerPhone`
    /// 「要么能直接拨通，要么是 `null`，永远不会是掩码串」，而 `DRIVER_ARRIVED`
    /// 在 `allowsCounterpartCall()` 里判 true ⇒ 实际路径上恒有号码。真为 null 时
    /// 版位会空 —— 记在这里，等 §2-H（后端放开盲人 token 调 `/start-service`）
    /// 一并解决：那时 ① 的主按钮变成恒存在的「开始跑步」，缺口自然消失。
    func testTheMainButtonSlotIsFilledInAllThreeScenes() {
        let scenes: [(String, BlindOrderFlowPresentation)] = [
            ("① 汇合", make(.driverArrived)),
            ("② 倒计时", make(.inProgress, countdown: 3)),
            ("③ 跑步中", make(.inProgress)),
            ("④ 已完成", make(.completed)),
        ]
        for (name, presentation) in scenes {
            XCTAssertNotNil(
                presentation.primaryAction,
                "\(name) 的主按钮版位空了 —— 底部会少一个按钮，求助与安全整块位移"
            )
        }
    }

    // MARK: - 倒计时的触发边界

    /// 🔴 **冷启动进来时已经在跑了，不倒数。**
    ///
    /// 中途进页面（切回 App、点推送、重启）听一遍「准备开始」，说的是一件三公里以前
    /// 发生过的事。判据是 `previousStatus == nil` —— 第一次 `loadOrder` 时订单还是 nil。
    func testColdStartIntoARunningOrderDoesNotReplayTheCountdown() {
        XCTAssertFalse(
            BlindOrderStatusViewModel.shouldStartRunCountdown(from: nil, to: .inProgress),
            "冷启动进到一张已经在跑的单上不该倒数"
        )
    }

    /// 同一态的重复刷新不重放。这一页每 5 秒轮一次，漏掉这条的症状是**每 5 秒倒数一次**。
    func testPollingTheSameStatusDoesNotReplayTheCountdown() {
        XCTAssertFalse(
            BlindOrderStatusViewModel.shouldStartRunCountdown(from: .inProgress, to: .inProgress)
        )
    }

    /// 志愿者按下开始 ⇒ 状态从汇合推到进行中 ⇒ 倒数。这是唯一该触发的那一次。
    func testTheVolunteerStartingTheRunTriggersTheCountdown() {
        XCTAssertTrue(
            BlindOrderStatusViewModel.shouldStartRunCountdown(from: .driverArrived, to: .inProgress)
        )
    }

    /// 🔴 **离开 `IN_PROGRESS` 时必须取消还没走完的那几拍，不能只是「不启动新的」。**
    ///
    /// 这条钉的是 `updateRunCountdown` 里那个 `else if`。写成「不该倒数就 return」时：
    /// 志愿者在开跑后三秒内取消（`IN_PROGRESS → REMATCHING`，走 WebSocket 推送），
    /// 屏幕是对的（相位落回 `.beforeRun`），而旧 Task 照常跑完剩下两拍 ——
    /// 刚听完「陪跑员取消了，正在重新为你匹配」，紧接着念「2」「1」并震两下。
    ///
    /// ⚠️ 断言分两半是有意的：`shouldStartRunCountdown` 判 false **不等于**「什么都不做」。
    /// 只验前半句的用例在两种实现下都通过，分辨不出这个缺陷。
    func testLeavingTheRunMustCancelInsteadOfMerelyNotStarting() {
        for to in [RunOrderStatus.rematching, .completed, .cancelled] {
            XCTAssertFalse(
                BlindOrderStatusViewModel.shouldStartRunCountdown(from: .inProgress, to: to),
                "\(to) 不该启动新的倒计时"
            )
            XCTAssertTrue(
                BlindOrderStatusViewModel.shouldCancelRunCountdown(on: to),
                "IN_PROGRESS → \(to) 必须取消在跑的倒计时，否则剩下两拍会在状态已经变了之后继续念"
            )
        }
        // 反向：还在 IN_PROGRESS 的重复刷新不许取消，否则每 5 秒轮询一次就把倒计时掐断。
        XCTAssertFalse(
            BlindOrderStatusViewModel.shouldCancelRunCountdown(on: .inProgress),
            "同一态刷新把倒计时掐了 —— 那三拍一拍都播不出来"
        )
    }

    /// 别的状态推进一律不倒数。**穷举而不是只挑两个** —— 漏掉的那个不会让任何断言变红，
    /// 它只是不再被检查，而绿灯照常亮。
    func testNoOtherTransitionEverStartsTheCountdown() {
        for to in RunOrderStatus.allCases + [.unknown] where to != .inProgress {
            for from in RunOrderStatus.allCases + [.unknown] {
                XCTAssertFalse(
                    BlindOrderStatusViewModel.shouldStartRunCountdown(from: from, to: to),
                    "\(from) → \(to) 不该倒数：倒计时只属于「刚刚开跑」这一刻"
                )
            }
        }
    }

    // MARK: - 辅助

    private func make(
        _ status: RunOrderStatus,
        volunteerName: String? = "张*",
        countdown: Int? = nil
    ) -> BlindOrderFlowPresentation {
        let order = OrderDetailResponse.preview(
            status: status,
            volunteerName: volunteerName,
            volunteerTotalCompleted: volunteerName == nil ? nil : 32,
            volunteerPhone: "13800000001"
        )
        guard let presentation = BlindOrderFlowPresentation.make(
            order: order,
            distanceText: nil,
            canKeepWaiting: false,
            countdown: countdown
        ) else {
            XCTFail("\(status) 应该落在骨架里")
            return BlindOrderFlowPresentation(
                step: .matching, phase: .beforeRun, visual: .radar, title: "", subtitle: "",
                lastRowTitle: "", primaryAction: nil, warning: nil
            )
        }
        return presentation
    }
}
