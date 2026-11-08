import SwiftUI
import UIKit
import XCTest
@testable import blindRun

/// `RemoteContent`（#863）：远端内容失败时「可见且可听」。
///
/// 跑后记录两页此前用 `RunRecordFailedView`，只上屏不念，盲人端也用它 —— VoiceOver 用户只会以为「点了没反应」。
/// 参数照两页的实际传参写（`RunnerRunRecordView` / `VolunteerRunRecordView` 的 `content`），
/// 文案取 `RunRecordViewModel` 的真实失败文案。
///
/// 只能挂进真窗口验：`.task` 只在视图真的出现在层级里时才跑（记忆 `task-on-empty-view-never-fires`）。
final class RemoteContentTests: XCTestCase {

    /// 比 `FailureAnnouncement.settleDelayNanoseconds`（0.3 秒）长出一截。
    private static let waitBeyondSettle: TimeInterval = 0.8

    /// 两页共用的失败文案之一（`RunRecordViewModel.loadOnce` 的非 API 错误分支）。
    private static let runRecordFailure = "跑后记录加载失败，请检查网络后重试。"

    func testRunRecordPageFailureIsSpoken() {
        let speech = SpeechService()
        let host = Self.host(Self.runRecordContent(.failed(message: Self.runRecordFailure)), speech: speech)
        defer { host.window.isHidden = true }

        Self.spin(Self.waitBeyondSettle)

        XCTAssertEqual(
            speech.spokenHistoryForTesting.filter { $0 == Self.runRecordFailure }.count, 1,
            "跑后记录页加载失败要念出来，只上屏等于「点了没反应」"
        )
    }

    /// 真实 view model 落到的失败态，挂进同一个视图也会念 —— 钉住「VM 文案 → 视图」这一段没断。
    @MainActor
    func testRunRecordViewModelNetworkFailureIsSpokenByTheView() async {
        let service = RemoteContentFailingRecordService()
        let appState = AppState(tokenStore: RemoteContentInMemoryTokenStore())
        let viewModel = RunRecordViewModel(orderId: 7, retryNanoseconds: 1_000_000)
        viewModel.configure(with: appState, runRecord: service)
        await viewModel.loadUntilSettled()
        guard case .failed(let message) = viewModel.phase else {
            return XCTFail("应当落到 failed，实际 \(viewModel.phase)")
        }

        let speech = SpeechService()
        let host = Self.host(Self.runRecordContent(viewModel.phase), speech: speech)
        defer { host.window.isHidden = true }
        Self.spin(Self.waitBeyondSettle)

        XCTAssertTrue(speech.spokenHistoryForTesting.contains(message), "实际念过：\(speech.spokenHistoryForTesting)")
        _ = appState
    }

    /// 加载中与已加载都不念失败。
    func testLoadingAndLoadedStatesAreNotSpokenAsFailures() {
        let speech = SpeechService()
        let host = Self.host(Self.runRecordContent(.loading(requestID: UUID())), speech: speech)
        defer { host.window.isHidden = true }
        Self.spin(Self.waitBeyondSettle)

        XCTAssertTrue(speech.spokenHistoryForTesting.isEmpty, "加载中不该出声：\(speech.spokenHistoryForTesting)")
    }

    func testAsyncLoadStateValueIsOnlyPresentWhenLoaded() {
        XCTAssertEqual(AsyncLoadState<Int>.loaded(3).value, 3)
        XCTAssertNil(AsyncLoadState<Int>.idle.value)
        XCTAssertNil(AsyncLoadState<Int>.loading(requestID: UUID()).value)
        XCTAssertNil(AsyncLoadState<Int>.failed(message: "x").value)
        XCTAssertNotEqual(AsyncLoadState<Int>.failed(message: "a"), .failed(message: "b"))
    }

    // MARK: - 辅助

    private static func runRecordContent(_ state: AsyncLoadState<RunRecordResponse>) -> AnyView {
        AnyView(
            RemoteContent(
                state,
                loadingLabel: "正在加载跑步记录",
                failureIdentifier: "runRecordRetry",
                retry: {}
            ) { _ in
                Text("loaded")
            }
        )
    }

    private static func host(_ view: AnyView, speech: SpeechService) -> (controller: UIHostingController<AnyView>, window: UIWindow) {
        let controller = UIHostingController(rootView: AnyView(view.environmentObject(speech)))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        return (controller, window)
    }

    private static func spin(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }
}

/// `record` 一律断网失败。
private final class RemoteContentFailingRecordService: RunRecordServing, @unchecked Sendable {
    func record(orderId: Int64) async throws -> RunRecordResponse { throw URLError(.notConnectedToInternet) }
    func monthlyRecords(year: Int, month: Int) async throws -> RunRecordHistoryResponse { throw URLError(.notConnectedToInternet) }
    func postMessage(orderId: Int64, text: String) async throws -> RunRecordMessageResponse { throw URLError(.notConnectedToInternet) }
}

private final class RemoteContentInMemoryTokenStore: TokenStoring, @unchecked Sendable {
    private var token: String?
    func save(_ token: String) { self.token = token }
    func read() -> String? { token }
    func delete() { token = nil }
}
