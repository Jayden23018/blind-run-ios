import XCTest
@testable import blindRun

/// 实时行程分享（`POST` / `DELETE /api/orders/{id}/share`）。
///
/// 这些用例钉的是四件在代码里看不出来、但错了就静默伤人的东西：
/// **链接原样带出去**（令牌在 fragment 里，改写等于把免登录凭据交给第三方脚本和日志）、
/// **停止分享的入口不能丢**（告知页逐字承诺了「随时可以停止」）、
/// **换账号不继承分享状态**、**文案不宣称送达**。
@MainActor
final class RunPlanLiveShareTests: XCTestCase {

    private let sampleUrl = "https://example.com/share.html#7cV3nQ8pR2sT5uW9xY0zA1bC4dE6fG8hJ0kL2mN4oP6"

    // MARK: - 链接原样带出去

    /// 后端把令牌放在 fragment 而不是 query，是为了让它不进 `Referer`、不上服务端访问日志
    /// —— 那个分享页要加载高德 JS SDK 这个第三方脚本。任何「把链接拼规整一点」的改写
    /// 都会把一个 43 字符的免登录凭据泄给第三方。
    func testShareTextCarriesTheUrlVerbatim() {
        let text = RunPlanLiveShareMessage.compose(shareUrl: sampleUrl)

        XCTAssertTrue(text.contains(sampleUrl), "shareUrl 必须原样出现在分享正文里")
        XCTAssertTrue(text.contains("#7cV3nQ8pR2sT5uW9xY0zA1bC4dE6fG8hJ0kL2mN4oP6"), "令牌必须仍在 fragment 里")
        XCTAssertFalse(text.contains("?"), "令牌一旦被挪进 query 就会进 Referer 与服务端日志")
    }

    /// 家属收到的不能是一条光秃秃的链接：不知道是谁发的、是什么，多数人不会点。
    func testShareTextSaysWhoAndWhatBeforeTheLink() {
        let text = RunPlanLiveShareMessage.compose(shareUrl: sampleUrl)
        XCTAssertTrue(text.hasPrefix(RunPlanLiveShareMessage.intro))
        XCTAssertTrue(text.contains("助盲跑"))
        XCTAssertTrue(text.contains("实时位置"))
    }

    // MARK: - 文案红线

    /// 与 `AGENTS.md` §6 同源：分享面板的完成回调只说明用户选了个目标应用，不代表对方收到了。
    /// `scripts/hooks/guard.mjs` 的 `sos-copy` 规则拦同一批措辞，这条是它的运行时同位素 ——
    /// 守卫只看改动的行，这里看的是最终值。
    func testNoCopyClaimsTheFamilyWasNotified() {
        let everything = [
            RunPlanLiveShareCopy.buttonTitle,
            RunPlanLiveShareCopy.accessibilityHint,
            RunPlanLiveShareCopy.stopButtonTitle,
            RunPlanLiveShareCopy.stopAccessibilityHint,
            RunPlanLiveShareCopy.preparing,
            RunPlanLiveShareCopy.ready,
            RunPlanLiveShareCopy.sharing,
            RunPlanLiveShareCopy.panelDismissed,
            RunPlanLiveShareCopy.stopping,
            RunPlanLiveShareCopy.stopped,
            RunPlanLiveShareCopy.stopFailed,
            RunPlanLiveShareCopy.alreadyFinished,
            RunPlanLiveShareCopy.smsFallbackButtonTitle,
            RunPlanLiveShareCopy.smsFallbackHint,
            RunPlanLiveShareMessage.intro,
            RunPlanLiveShareCopy.failed("测试原因。", offersSMSFallback: true)
        ]

        for phrase in ["已通知", "已送达", "已收到", "已知晓", "家人已"] {
            for copy in everything {
                XCTAssertFalse(copy.contains(phrase), "「\(phrase)」不得出现在分享文案里：\(copy)")
            }
        }
    }

    /// 「已停止分享」是**服务端确认过的 204** 之后才播的，可以用完成时；
    /// 而生成链接之后只能说到「链接已生成」为止 —— 后面选发给谁、发没发出去，App 不掌控。
    func testReadyCopyStopsAtLinkGeneratedAndDoesNotPromiseSending() {
        XCTAssertTrue(RunPlanLiveShareCopy.ready.contains("链接已生成"))
        XCTAssertFalse(RunPlanLiveShareCopy.ready.contains("已发"))
    }

    /// 停止失败时**不能**说「已停止」：链接可能还有效，说停了会让人以为位置不再外发。
    func testStopFailureDoesNotClaimSharingEnded() {
        XCTAssertTrue(RunPlanLiveShareCopy.stopFailed.contains("可能仍然有效"))
        XCTAssertFalse(RunPlanLiveShareCopy.stopFailed.contains("已停止"))
    }

    /// 发不了短信的设备上不许提「可以改用短信」—— 那是把用户支上一条同样走不通的路。
    func testFailureCopyOnlyOffersSMSWhenItIsActuallyAvailable() {
        XCTAssertTrue(RunPlanLiveShareCopy.failed("网络不通。", offersSMSFallback: true).contains("短信"))
        XCTAssertFalse(RunPlanLiveShareCopy.failed("网络不通。", offersSMSFallback: false).contains("短信"))
    }

    // MARK: - 契约解码

    func testShareLinkResponseDecodesTheContractShape() throws {
        let json = Data("""
        {"shareUrl":"\(sampleUrl)","expiresAt":"2026-08-13T12:30:00"}
        """.utf8)
        let decoded = try JSONDecoder().decode(ShareLinkResponse.self, from: json)

        XCTAssertEqual(decoded.shareUrl, sampleUrl)
        XCTAssertEqual(decoded.expiresAt, "2026-08-13T12:30:00")
    }

    /// `expiresAt` 在契约里是必填，这里仍收成 optional：少一个只用来展示的字段，
    /// 不该让整条分享链路解码失败 —— 对盲人「点了没反应」就是事故（`AGENTS.md` 硬约束）。
    func testMissingExpiresAtDoesNotKillTheWholeShare() throws {
        let json = Data("{\"shareUrl\":\"\(sampleUrl)\"}".utf8)
        let decoded = try JSONDecoder().decode(ShareLinkResponse.self, from: json)

        XCTAssertEqual(decoded.shareUrl, sampleUrl)
        XCTAssertNil(decoded.expiresAt)
    }

    /// 409 有确切含义，不该被念成「未知错误 (409)」。raw value 与后端
    /// `ErrorCode.java:119` 逐字对齐（`scripts/validate-error-codes.mjs` 会对撞）。
    func testTerminalRaceHasItsOwnSpokenMessage() {
        XCTAssertEqual(ErrorCode.shareOrderAlreadyFinished.rawValue, "SHARE_ORDER_ALREADY_FINISHED")
        XCTAssertEqual(ErrorCode.shareOrderAlreadyFinished.localizedMessage, RunPlanLiveShareCopy.alreadyFinished)
        XCTAssertTrue(ErrorCode.shareOrderAlreadyFinished.localizedMessage.contains("已经结束"))
    }

    // MARK: - 本地分享状态

    /// 后端没有查询分享状态的端点，「停止分享」的入口只能靠本地记录活下来。
    /// 只存一个订单号：盲人同一时刻只有一个进行中的订单，按单存会在 `UserDefaults` 里
    /// 堆下无上限、没人清的历史 key。
    func testOnlyTheMostRecentlySharedOrderOffersStopSharing() {
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        defer { persistence.reset() }
        let store = RunPlanLiveShareStore(persistence: persistence)

        XCTAssertFalse(store.isSharing(orderID: 7001))

        store.markSharing(orderID: 7001)
        XCTAssertTrue(store.isSharing(orderID: 7001))
        XCTAssertFalse(store.isSharing(orderID: 7002), "别的订单不该显示「停止分享」")

        store.markSharing(orderID: 7002)
        XCTAssertFalse(store.isSharing(orderID: 7001), "换了订单，旧订单的分享入口应当让位")
        XCTAssertTrue(store.isSharing(orderID: 7002))

        store.clear()
        XCTAssertFalse(store.isSharing(orderID: 7002))
    }

    /// **杀 App 再回来仍要能停止分享。** 告知页逐字承诺了这一条，而链接在服务端还活着 ——
    /// 状态只存在内存里的话，这个承诺会静默失效，用户再也找不到停止的入口。
    func testStopSharingSurvivesAppRestart() {
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        defer { persistence.reset() }
        RunPlanLiveShareStore(persistence: persistence).markSharing(orderID: 7001)

        // 新建一个 store 等价于「App 重启后重新读一遍」。
        XCTAssertTrue(RunPlanLiveShareStore(persistence: persistence).isSharing(orderID: 7001))
    }

    /// 登出会跑 `persistence.reset()`。这个 key 漏进 `all` 的话，下一个登录的人会在自己的
    /// 订单页上看到「停止分享」—— 那条链接是上一个账号的，他既停不掉也不该知道它存在。
    func testLogoutClearsTheShareStateSoTheNextAccountDoesNotInheritIt() {
        XCTAssertTrue(
            AppStatePersistenceKeys.all.contains(RunPlanLiveShareStore.storageKey),
            "分享状态必须进 AppStatePersistenceKeys.all，否则登出清不掉"
        )
    }

    // MARK: - 端点行为（Mock）

    /// 幂等：重复调返回同一条链接。换令牌会让已经发出去的那条失效，
    /// 家属只看到「分享已结束」，分不清是跑完了还是链接被换了。
    func testCreatingTheLinkTwiceReturnsTheSameLink() async throws {
        let client = MockAPIClient()
        let first: ShareLinkResponse = try await client.post("/api/orders/1/share")
        let second: ShareLinkResponse = try await client.post("/api/orders/1/share")

        XCTAssertEqual(first.shareUrl, second.shareUrl)
        XCTAssertTrue(first.shareUrl.contains("#"), "令牌必须在 fragment 里")
    }

    /// 停止后再开是一条**新**链接：旧的已经失效，复用同一个令牌等于停止分享没生效。
    func testRevokingInvalidatesTheLinkSoTheNextOneIsDifferent() async throws {
        let client = MockAPIClient()
        let first: ShareLinkResponse = try await client.post("/api/orders/1/share")
        let _: EmptyResponse = try await client.delete("/api/orders/1/share")
        let second: ShareLinkResponse = try await client.post("/api/orders/1/share")

        XCTAssertNotEqual(first.shareUrl, second.shareUrl)
    }

    /// 幂等：没有可撤销的链接时同样成功（后端返 204）。
    func testRevokingWithoutAnActiveLinkStillSucceeds() async throws {
        let client = MockAPIClient()
        let _: EmptyResponse = try await client.delete("/api/orders/1/share")
    }

    /// 终态返 409。客户端在终态隐藏入口，所以这条只在轮询窗口的竞态里走到 ——
    /// 但走到时必须是这个码，不是通用 400。
    func testTerminalOrderRejectsANewLinkWithTheDedicatedCode() async throws {
        let client = MockAPIClient()
        do {
            let _: ShareLinkResponse = try await client.post("/api/orders/2/share")
            XCTFail("已完成的订单不该能开新的分享链接")
        } catch let error as APIError {
            XCTAssertEqual(error.errorCode, .shareOrderAlreadyFinished)
        }
    }
}
