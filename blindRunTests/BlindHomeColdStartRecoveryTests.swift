import XCTest
import AMapSearchKit
import AVFAudio
import CoreLocation
import SwiftUI
@testable import blindRun

@MainActor
final class BlindHomeColdStartRecoveryTests: XCTestCase, BlindRunTestSupport {
    // MARK: - 盲人冷启动恢复（GET /api/orders/active）

    /// 恢复路径走 `GET /api/orders/active`，**不是**分页历史 `/api/orders/mine`。
    ///
    /// 换端点是为了把「哪些状态算活着」交回服务端。`mine` 那条要客户端自己 filter + sort，
    /// 而挑得出来靠的是两条**没写进契约**的性质：盲人同时只能有一条活跃订单、
    /// 且它一定落在 `createdAt` 倒序的前 10 条里（`size` 默认就是 10）。
    func testBlindRunnerHomeRecoversFromTheActiveOrderEndpoint() async {
        let order = makeOrder(orderId: 801, status: .driverEnRoute)
        let client = ActiveOrderStubClient(envelope: ActiveOrderEnvelope(success: true, data: order))
        let appState = AppState(apiClient: client)
        let viewModel = BlindRunnerHomeViewModel()
        viewModel.configure(with: appState, speechService: SpeechService())

        await viewModel.loadActiveOrder()

        XCTAssertEqual(client.paths, ["/api/orders/active"])
        XCTAssertFalse(client.paths.contains("/api/orders/mine"), "还在打分页历史列表")
        XCTAssertEqual(viewModel.activeOrder?.orderId, 801)
        XCTAssertNil(viewModel.errorMessage)
    }

    /// 没有活跃订单时后端给的是 `data: null`（不是 404、不是空对象）。
    /// 解不出来的话首页会把「当前没有进行中的预约」渲染成一条加载失败。
    func testNoActiveOrderIsAnEmptyResultNotAnError() async {
        let client = ActiveOrderStubClient(envelope: ActiveOrderEnvelope(success: true, data: nil))
        let appState = AppState(apiClient: client)
        let viewModel = BlindRunnerHomeViewModel()
        viewModel.configure(with: appState, speechService: SpeechService())

        await viewModel.loadActiveOrder()

        XCTAssertNil(viewModel.activeOrder)
        XCTAssertNil(viewModel.errorMessage, "「没有进行中的预约」被当成了加载失败")
        XCTAssertTrue(viewModel.canStartNewBooking)
    }

    /// 首启引导页在场时，首页加载完**不许播报**。
    ///
    /// 两个页面共用一个 `AVSpeechSynthesizer`，而 `SpeechService.speak` 的第一件事是
    /// `stopSpeaking(at: .immediate)` —— 谁后说谁赢。首页这一句要等一次网络往返，
    /// 比引导页的 `.task` 晚，于是把引导念到一半的三条说明当场切断。两句又都以
    /// 「欢迎…助盲跑」开头（引导「欢迎使用助盲跑」/ 首页「欢迎来到助盲跑」），
    /// 听感就是「只念了标题就没了」—— 2026-09-07 真机报的正是这个，而且**读代码看不出来**：
    /// 引导页的自动播报和「再听一遍」调的是同一个函数，代码上没有任何分叉。
    func testFirstRunHelpKeepsTheHomeStatusAnnouncementSilent() async {
        let speechService = SpeechService()
        let client = ActiveOrderStubClient(envelope: ActiveOrderEnvelope(success: true, data: nil))
        let appState = AppState(apiClient: client)
        let viewModel = BlindRunnerHomeViewModel()
        viewModel.configure(with: appState, speechService: speechService)

        await viewModel.loadActiveOrder(announcesStatus: false)

        XCTAssertNil(
            speechService.lastSpokenText,
            "引导页正压在首页上，首页却播报了 —— 它会 stopSpeaking 掉引导念到一半的说明"
        )
        XCTAssertNil(viewModel.errorMessage, "静音只该关掉播报，不该把加载本身弄坏")
        XCTAssertTrue(
            viewModel.owesStatusAnnouncement,
            "静音了却没欠账 —— 用返回键退出引导的人整次启动一个字都听不到"
        )
    }

    /// 还账：首页重新露头时把推迟的那次播报补上，且**只补一次**。
    func testDeferredHomeAnnouncementIsSettledOnceWhenHomeComesBack() async {
        let speechService = SpeechService()
        let client = ActiveOrderStubClient(envelope: ActiveOrderEnvelope(success: true, data: nil))
        let appState = AppState(apiClient: client)
        let viewModel = BlindRunnerHomeViewModel()
        viewModel.configure(with: appState, speechService: speechService)

        await viewModel.loadActiveOrder(announcesStatus: false)
        viewModel.announceStatusIfOwed()

        XCTAssertEqual(speechService.lastSpokenText, "欢迎来到助盲跑。可以点击预约新的陪跑。")
        XCTAssertFalse(viewModel.owesStatusAnnouncement, "账没清，下次从设置页返回还会再播一次")
    }

    /// 加载**失败**时不许欠账。
    ///
    /// 欠了的话，用户按「知道了」回到首页会听见「可以点击预约新的陪跑」，而那一刻界面上是
    /// 守卫版按钮（`canStartNewBooking == false`），按下去只会说「订单状态尚未确认」。
    /// 失败那条路由没有加闸的 `speakError` 负责，两条不该互相盖。
    func testAFailedSilentLoadOwesNothingSoItCannotContradictTheErrorAnnouncement() async {
        let speechService = SpeechService()
        let appState = AppState(apiClient: CancellationSuspendingAPIClient())
        let viewModel = BlindRunnerHomeViewModel(loadTimeout: 0.05)
        viewModel.configure(with: appState, speechService: speechService)

        await viewModel.loadActiveOrder(announcesStatus: false)

        XCTAssertEqual(viewModel.errorMessage, "加载超过 20 秒，请重试。")
        XCTAssertFalse(
            viewModel.owesStatusAnnouncement,
            "加载失败却欠下一次「可以点击预约新的陪跑」—— 它会和界面上的守卫按钮直接矛盾"
        )
        XCTAssertEqual(
            speechService.lastSpokenText,
            "加载超过 20 秒，请重试。",
            "错误播报被静音闸误伤了"
        )
    }

    /// 没欠账就不许播 —— 否则从设置页 / 订单详情页返回时会多出一次本来没有的播报。
    func testHomeDoesNotAnnounceWhenNothingIsOwed() async {
        let speechService = SpeechService()
        let client = ActiveOrderStubClient(envelope: ActiveOrderEnvelope(success: true, data: nil))
        let appState = AppState(apiClient: client)
        let viewModel = BlindRunnerHomeViewModel()
        viewModel.configure(with: appState, speechService: speechService)

        await viewModel.loadActiveOrder()
        XCTAssertFalse(viewModel.owesStatusAnnouncement)

        // 换一句别的当哨兵：还账若真的播了，它会被覆盖掉。
        speechService.speak("哨兵")
        viewModel.announceStatusIfOwed()
        viewModel.announceStatusIfOwed()

        XCTAssertEqual(
            speechService.lastSpokenText,
            "哨兵",
            "没欠账也播了 —— 从设置页 / 订单详情页返回时会多出一次本来没有的播报"
        )
    }

    /// 上一条的对照组。少了它，把 `speakCurrentStatus()` 整个删掉也一样绿。
    func testHomeStillAnnouncesItsStatusWhenNoHelpIsInTheWay() async {
        let speechService = SpeechService()
        let client = ActiveOrderStubClient(envelope: ActiveOrderEnvelope(success: true, data: nil))
        let appState = AppState(apiClient: client)
        let viewModel = BlindRunnerHomeViewModel()
        viewModel.configure(with: appState, speechService: speechService)

        await viewModel.loadActiveOrder()

        XCTAssertEqual(
            speechService.lastSpokenText,
            "欢迎来到助盲跑。可以点击预约新的陪跑。",
            "常规路径的首页播报被一起关掉了"
        )
    }

    /// 🚩 **这条是换端点换来的东西**：服务端说它还没走完，客户端就恢复得回来 ——
    /// 哪怕这个版本的 App 根本不认识那个状态。
    ///
    /// 从前由客户端 `isActiveForBlindRunner` 判，后端加一个非终态就得改客户端才认得；
    /// 现在那个判断在服务端做完了，我们只负责把它渲染成「状态未知」而不是从界面上抹掉。
    func testAStatusThisClientDoesNotRecogniseStillRecovers() async throws {
        let json = #"{"orderId":802,"status":"AWAITING_SOMETHING_NEW"}"#
        let order = try JSONDecoder().decode(OrderDetailResponse.self, from: Data(json.utf8))
        XCTAssertEqual(order.status, .unknown, "解码宽容度本身坏了，后面的断言就没有意义")

        let client = ActiveOrderStubClient(envelope: ActiveOrderEnvelope(success: true, data: order))
        let appState = AppState(apiClient: client)
        let viewModel = BlindRunnerHomeViewModel()
        viewModel.configure(with: appState, speechService: SpeechService())

        await viewModel.loadActiveOrder()

        XCTAssertEqual(viewModel.activeOrder?.orderId, 802)
        XCTAssertEqual(viewModel.activeOrder?.status.displayName, "状态未知")
    }

    /// 只回 `GET /api/orders/active`，并**记下每一条请求路径** ——
    /// 「换没换端点」这件事只有靠路径序列才看得出来，断言恢复结果会被「两条端点都能恢复」蒙混过去。
    private final class ActiveOrderStubClient: APIClientProtocol, @unchecked Sendable {
        enum StubError: Error { case unexpectedPath, unexpectedType }

        private let lock = NSLock()
        private var recorded: [String] = []
        private let envelope: ActiveOrderEnvelope

        init(envelope: ActiveOrderEnvelope) {
            self.envelope = envelope
        }

        var paths: [String] { lock.withLock { recorded } }

        func request<T: Decodable>(
            method: HTTPMethod,
            path: String,
            query: [String: String]?,
            body: (any Encodable & Sendable)?,
            requiresAuth: Bool
        ) async throws -> T {
            lock.withLock { recorded.append(path) }
            guard path == "/api/orders/active", method == .get else { throw StubError.unexpectedPath }
            guard let typed = envelope as? T else { throw StubError.unexpectedType }
            return typed
        }

        func upload<T: Decodable>(
            path: String,
            query: [String: String]?,
            fields: [String: String]?,
            files: [MultipartFile],
            requiresAuth: Bool
        ) async throws -> T {
            throw StubError.unexpectedPath
        }
    }
}
