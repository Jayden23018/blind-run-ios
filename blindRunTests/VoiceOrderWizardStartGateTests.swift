import CoreLocation
import XCTest
@testable import blindRun

@MainActor
final class VoiceOrderWizardStartGateTests: XCTestCase, VoiceOrderWizardTestSupport {

    // MARK: - 等 TTS 播完再开麦的上限
    //
    // 2026-08-06 真机手测：读回念到一半被切掉，麦克风当场打开。根因是这个上限写死 8 秒，
    // 而读回整单要 15~25 秒 —— 上限一到就开麦，开麦切换音频分类会把正在播的合成器掐断。
    // 上限必须跟着要念的字数走，这一组把这件事钉住。

    /// 读回整单的实际长度量级（原话 + 三个槽位 + 两条出路，约 120 字）必须等得住。
    /// 这条直接对应报障：120 字在旧的 8 秒上限下必被截断。
    func testSettleTimeoutOutlastsAFullReadback() {
        let readback = String(repeating: "字", count: 120)

        let timeout = VoiceOrderWizard.settleTimeout(forCharacterCount: readback.count)

        XCTAssertGreaterThan(
            timeout,
            20,
            "约 120 字的读回念不完就开麦，音频分类切换会把合成器掐断 —— 盲人听到的是一句被切一半的预约"
        )
    }

    /// 短提示的行为不变：下限仍是 8 秒，不因为这次改动被拖长。
    func testSettleTimeoutKeepsTheOldFloorForShortPrompts() {
        XCTAssertEqual(VoiceOrderWizard.settleTimeout(forCharacterCount: 0), 8)
        XCTAssertEqual(VoiceOrderWizard.settleTimeout(forCharacterCount: 5), 8)
    }

    /// 上限存在的理由是合成器代理丢事件时不能无限等 —— 异常长的文本也必须夹住。
    func testSettleTimeoutIsCappedSoALostDelegateCannotHangTheMicrophone() {
        XCTAssertEqual(VoiceOrderWizard.settleTimeout(forCharacterCount: 100_000), 45)
    }

    // MARK: - start() 的门槛接线
    //
    // 上面 28 条用例全部走 `startForTesting(at:)`，**绕过了 `start()`**，所以门槛那三道分支
    // 一条都没被验过 —— 和「兜底坐标让 `.startPoint` 恒真」是同一类：逻辑写对了，但没人证明
    // 它真的被接上。（openspec tasks 3.4 / 3.5）


    /// 四道「本页填不了」的门槛缺任意一道，`start()` 都不得开麦，并且必须把原因说出来。
    ///
    /// 门槛的唯一真源是后端 `OrderCreationService.createOrder`，客户端这份只是把同样的顺序提前。
    /// 让盲人说完一整句才被服务端 403 拒掉是最坏的顺序。
    func testStartIsBlockedByGatesThatVoiceCannotFill() {
        let appState = AppState(persistence: AppStatePersistenceFactory.makeIsolatedTest())
        // 昵称未填 ⇒ basicProfile 缺失，这一道只能去个人资料页补。
        let viewModel = BlindBookingViewModel()
        viewModel.configureForTesting(speechService: SpeechService(), locationService: nil, appState: appState)
        let wizard = makeUnstartedWizard(bookingViewModel: viewModel)

        XCTAssertFalse(wizard.start(), "门槛没过就不该起步")
        XCTAssertFalse(wizard.isRunning)
        XCTAssertEqual(wizard.fallbackMessage, BlindBookingGate.basicProfile.message, "拦住了就必须说得出原因")
    }

    /// 从「约跑前还差 N 项」补完回来（#781）：顶上那句改成还差的下一项，都齐了就撤掉，且不开麦。
    /// 撤不掉的话，屏幕在卡片消失后还说「还要填昵称」，零输入下单的大按钮也会被它误放出来。
    func testRefreshAfterFillingSetupItemsUpdatesThenClearsTheFallback() {
        let appState = AppState(persistence: AppStatePersistenceFactory.makeIsolatedTest())
        let viewModel = BlindBookingViewModel()
        viewModel.configureForTesting(speechService: SpeechService(), locationService: nil, appState: appState)
        let wizard = makeUnstartedWizard(bookingViewModel: viewModel)
        XCTAssertFalse(wizard.start(), "前提：缺昵称被拦下")

        appState.updateBlindProfile(BlindProfileResponse(name: "测试用户"))
        wizard.refreshSetupGateFallback()
        XCTAssertEqual(wizard.fallbackMessage, BlindBookingGate.emergencyContacts.message, "补了昵称，改说还差的那一项")

        appState.updateEmergencyContacts([
            EmergencyContactResponse(id: 1, name: "联系人1", phone: "13900139001", relationship: "家人", isPrimary: true)
        ])
        wizard.refreshSetupGateFallback()
        XCTAssertNil(wizard.fallbackMessage, "都齐了就撤掉")
        XCTAssertFalse(wizard.isRunning, "回来时不自动开麦")

        wizard.fallbackMessage = "语音输入当前不可用"
        wizard.refreshSetupGateFallback()
        XCTAssertEqual(wizard.fallbackMessage, "语音输入当前不可用", "别的降级原因不归这里管")
    }

    /// 起点与时间**缺失时反而要照常起步** —— 它们正是用户接下来要说出口的槽位。
    ///
    /// ⚠️ openspec tasks 3.4 原文写的是「默认值不可用时**不**出现首步」，那描述属于已被推翻的
    /// `.confirmDefaults` 形态（先念默认值再逐项追问）。现在首步是整句自由说，把这两道门槛
    /// 当成阻断条件会让「没有 GPS 就彻底用不了语音」—— 而语音正是拿来说出发地点的。
    /// `VoiceOrderWizard.start()` 里那两个 `gate != ...` 判断就是这条规则，本用例锁住它。
    func testStartProceedsWhenOnlyTheVoiceFilledSlotsAreMissing() {
        let appState = AppState(persistence: AppStatePersistenceFactory.makeIsolatedTest())
        appState.updateBlindProfile(BlindProfileResponse(name: "测试用户", verifyStatus: "VERIFIED"))
        appState.updateEmergencyContacts([
            EmergencyContactResponse(id: 1, name: "联系人1", phone: "13900139001", relationship: "家人", isPrimary: true)
        ])
        let viewModel = BlindBookingViewModel()
        // ⚠️ 起点缺失必须用 `locationService: nil` 构造，**不能**用裸 `LocationService()`。
        // 后者在真机上是个竞态：`resolvedStartPlace` 只要 `currentLocation != nil` 就成立
        // （`BlindBookingView.swift:358`），而真机几毫秒内就回调出真实坐标，于是起点反而有了、
        // 门槛跳到 `.appointmentTime`。本用例 2026-08-06 首次上真机就是这么红的 ——
        // 它要验的是「起点缺失时照常起步」，跟坐标是不是演示值无关，没必要引入定位的时序。
        viewModel.configureForTesting(speechService: SpeechService(), locationService: nil, appState: appState)
        XCTAssertEqual(viewModel.firstMissingGate, .startPoint, "前提：只差语音要填的槽位")

        let wizard = makeUnstartedWizard(bookingViewModel: viewModel)

        XCTAssertTrue(wizard.start(), "起点缺失恰恰是要用语音补的，不能反过来把语音关掉")
        XCTAssertTrue(wizard.isRunning)
        XCTAssertEqual(wizard.step, .freeform)
        XCTAssertNil(wizard.fallbackMessage)
    }

    /// 语音链路已经在启动阶段失败过（授权被拒 / recognizer 不可用）就直接交回表单。
    /// 明知打不开麦克风还走一遍重问循环，只会让人听三轮「我再问一次」才等到降级。
    func testStartFallsBackImmediatelyWhenTheSpeechPathIsAlreadyKnownBroken() {
        let appState = AppState(persistence: AppStatePersistenceFactory.makeIsolatedTest())
        appState.updateBlindProfile(BlindProfileResponse(name: "测试用户", verifyStatus: "VERIFIED"))
        appState.updateEmergencyContacts([
            EmergencyContactResponse(id: 1, name: "联系人1", phone: "13900139001", relationship: "家人", isPrimary: true)
        ])
        let viewModel = BlindBookingViewModel()
        // `locationService` 在 view model 里是 weak，这里原本传的临时对象当场就释放了 ——
        // 等价于 nil，写成 nil 才不误导。本用例验的是语音链路失败后的降级，与定位无关。
        viewModel.configureForTesting(
            speechService: SpeechService(), locationService: nil, appState: appState
        )
        let speech = SpeechInputService()
        speech.startPendingAuthorizationForTesting(field: .voiceOrderFreeform)
        speech.denyAuthorizationForTesting()
        XCTAssertTrue(speech.isSpeechPathUnavailable, "前提：语音这条路已知不可用")

        let wizard = makeUnstartedWizard(bookingViewModel: viewModel, speechInputService: speech)

        XCTAssertFalse(wizard.start())
        XCTAssertFalse(wizard.isRunning)
        XCTAssertEqual(
            wizard.fallbackMessage,
            "语音输入当前不可用，已切回表单填写，你可以用屏幕上的输入框继续预约。",
            "降级必须说清接下来去哪 —— 看不见屏幕的人没有别的方式发现语音已经停了"
        )
    }
}
