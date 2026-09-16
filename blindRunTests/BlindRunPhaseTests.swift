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

    // MARK: - 不变量：主按钮位置永不变化

    /// ①②③ 三幕的主按钮版位**都是满的**。
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
