import SwiftUI
import UIKit
import XCTest
@testable import blindRun

/// #866：培训列表、课程正文、紧急联系人列表迁到 `AsyncLoadState` + `RemoteContent`。
///
/// 守三件事：状态转换对；刷新失败保留已显示的内容（页面规则）；失败会念出来，且紧急联系人页只念一遍。
/// 念不念只能挂进真窗口验：`.task` 只在视图真的出现在层级里时才跑（记忆 `task-on-empty-view-never-fires`）。
@MainActor
final class TrainingAndContactsRemoteContentTests: XCTestCase {

    /// 比 `FailureAnnouncement.settleDelayNanoseconds`（0.3 秒）长出一截，另给 `.task` 里的请求留时间。
    private static let waitBeyondSettle: TimeInterval = 1.2

    // MARK: - 培训列表

    func testTrainingListLoadsIntoLoadedState() async {
        let appState = Self.trainingAppState(client: SwitchableTrainingClient())
        let viewModel = VolunteerTrainingViewModel()
        viewModel.configure(appState: appState)
        XCTAssertEqual(viewModel.state.isLoading, false)
        XCTAssertNil(viewModel.state.value)

        await viewModel.load()

        XCTAssertNotNil(viewModel.state.value, "Mock 课表应当读到")
        XCTAssertTrue(viewModel.hasLoadedOnce)
        XCTAssertFalse(viewModel.courses.isEmpty)
    }

    func testTrainingListFirstLoadFailureBecomesFailedWithTheFallbackCopy() async {
        let client = SwitchableTrainingClient()
        client.fails = true
        let appState = Self.trainingAppState(client: client)
        let viewModel = VolunteerTrainingViewModel()
        viewModel.configure(appState: appState)

        await viewModel.load()

        guard case .failed(let message) = viewModel.state else {
            return XCTFail("首次读取失败要落到 failed，实际 \(viewModel.state)")
        }
        XCTAssertEqual(message, VolunteerTrainingCopy.loadFailure)
        XCTAssertFalse(viewModel.hasLoadedOnce)
    }

    /// 从课程详情返回时刷新列表；这次失败不能把已显示的进度卡和课表换成失败页。
    func testTrainingListRefreshFailureKeepsTheLoadedList() async {
        let client = SwitchableTrainingClient()
        let appState = Self.trainingAppState(client: client)
        let viewModel = VolunteerTrainingViewModel()
        viewModel.configure(appState: appState)
        await viewModel.load()
        let loaded = viewModel.courses.map(\.id)

        client.fails = true
        await viewModel.load()

        XCTAssertNotNil(viewModel.state.value, "刷新失败要停在 loaded，实际 \(viewModel.state)")
        XCTAssertEqual(viewModel.courses.map(\.id), loaded)
    }

    func testTrainingListFailureIsSpoken() {
        let client = SwitchableTrainingClient()
        client.fails = true
        let appState = Self.trainingAppState(client: client)
        let speech = SpeechService()
        let host = Self.host(AnyView(NavigationStack { VolunteerTrainingView() }), appState: appState, speech: speech)
        defer { host.window.isHidden = true }

        Self.spin(upTo: 10) { speech.spokenHistoryForTesting.contains(VolunteerTrainingCopy.loadFailure) }
        Self.spin(Self.waitBeyondSettle)

        XCTAssertEqual(
            speech.spokenHistoryForTesting.filter { $0 == VolunteerTrainingCopy.loadFailure }.count, 1,
            "培训列表读取失败要念出来。实际念过：\(speech.spokenHistoryForTesting)"
        )
        _ = appState
    }

    // MARK: - 课程正文

    func testCourseDetailLoadsAndFailsIntoTheRightStates() async throws {
        let client = SwitchableTrainingClient()
        let appState = Self.trainingAppState(client: client)
        let courseId = try XCTUnwrap(MockAPIClient.mockTrainingCourses.first?.id)

        let loading = VolunteerTrainingCourseViewModel(courseId: courseId)
        loading.configure(appState: appState)
        await loading.load()
        XCTAssertEqual(loading.detail?.id, courseId)
        XCTAssertNil(loading.errorMessage, "读正文成功不该留下交卷失败文案")

        client.fails = true
        let failing = VolunteerTrainingCourseViewModel(courseId: courseId)
        failing.configure(appState: appState)
        await failing.load()
        guard case .failed(let message) = failing.state else {
            return XCTFail("读正文失败要落到 failed，实际 \(failing.state)")
        }
        XCTAssertEqual(message, VolunteerTrainingCourseViewModel.loadFailure)
        XCTAssertNil(failing.errorMessage, "读正文失败不进交卷失败那一格，否则答题页会把它当交卷失败念")
    }

    func testCourseDetailFailureIsSpoken() throws {
        let client = SwitchableTrainingClient()
        client.fails = true
        let appState = Self.trainingAppState(client: client)
        let courseId = try XCTUnwrap(MockAPIClient.mockTrainingCourses.first?.id)
        let speech = SpeechService()
        let host = Self.host(
            AnyView(NavigationStack { VolunteerTrainingCourseView(courseId: courseId, onCompletionChanged: {}) }),
            appState: appState,
            speech: speech
        )
        defer { host.window.isHidden = true }

        Self.spin(upTo: 10) { speech.spokenHistoryForTesting.contains(VolunteerTrainingCourseViewModel.loadFailure) }

        XCTAssertTrue(
            speech.spokenHistoryForTesting.contains(VolunteerTrainingCourseViewModel.loadFailure),
            "课程正文读取失败要念出来。实际念过：\(speech.spokenHistoryForTesting)"
        )
        _ = appState
    }

    // MARK: - 紧急联系人

    /// 没缓存、读取失败：状态是 failed，不弹窗（失败由 `RemoteContent` 显示并念，弹窗会让它念两遍）。
    func testContactsFailureWithNothingOnScreenIsFailedStateNotAnAlert() async {
        let (viewModel, appState, _) = Self.contactsViewModel(cached: [], failsRefresh: true)

        await viewModel.load()

        guard case .failed = viewModel.listState else {
            return XCTFail("屏幕上一位都没有时读取失败要落到 failed，实际 \(viewModel.listState)")
        }
        XCTAssertNil(viewModel.errorMessage, "这时不弹窗，免得同一句念两遍")
        XCTAssertFalse(viewModel.isKnownToHaveNoContacts, "读取失败不能断定一位都没有（#807）")
        _ = appState
    }

    /// 有缓存、读取失败：缓存照常显示，失败走弹窗 + 朗读（既有行为）。
    func testContactsFailureWithCachedContactsKeepsThemAndAlerts() async {
        let cached = [Self.contact(id: 1, isPrimary: true)]
        let (viewModel, appState, _) = Self.contactsViewModel(cached: cached, failsRefresh: true)

        await viewModel.load()

        XCTAssertEqual(viewModel.contacts.map(\.id), [1])
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.hasLoadedFromServer)
        _ = appState
    }

    /// 读到过之后下拉刷新失败：停在 loaded，列表不变，弹窗说明。
    func testContactsRefreshFailureAfterLoadKeepsTheLoadedList() async {
        let contacts = [Self.contact(id: 1, isPrimary: true), Self.contact(id: 2)]
        let (viewModel, appState, client) = Self.contactsViewModel(cached: contacts, failsRefresh: false)
        await viewModel.load()
        XCTAssertTrue(viewModel.hasLoadedFromServer)

        client.failNextRefresh = true
        await viewModel.load()

        XCTAssertEqual(viewModel.listState.value?.map(\.id), [1, 2], "刷新失败要停在 loaded，实际 \(viewModel.listState)")
        XCTAssertNotNil(viewModel.errorMessage)
        _ = appState
    }

    func testContactsFailureWithNothingOnScreenIsSpokenOnce() {
        let client = ContactsAPIClientStub(contacts: [])
        client.failNextRefresh = true
        let appState = AppState(apiClient: client, tokenStore: ContactsInMemoryTokenStore())
        appState.userId = 7
        let speech = SpeechService()
        let host = Self.host(AnyView(NavigationStack { EmergencyContactsView() }), appState: appState, speech: speech)
        defer { host.window.isHidden = true }

        // 进页概览和失败句同档，失败句要排在概览后面才进历史：等它出现，再多等一截看有没有第二遍。
        let message = EmergencyContactsViewModel.displayMessage(for: .invalidURL)
        Self.spin(upTo: 10) { speech.spokenHistoryForTesting.contains(message) }
        Self.spin(Self.waitBeyondSettle)
        XCTAssertEqual(
            speech.spokenHistoryForTesting.filter { $0 == message }.count, 1,
            "失败要念出来，且只念一遍。实际念过：\(speech.spokenHistoryForTesting)"
        )
        _ = appState
    }

    // MARK: - 辅助

    private static func trainingAppState(client: SwitchableTrainingClient) -> AppState {
        let appState = AppState(apiClient: client)
        appState.currentEnvironment = .mock
        return appState
    }

    private static func contactsViewModel(
        cached: [EmergencyContactResponse],
        failsRefresh: Bool
    ) -> (EmergencyContactsViewModel, AppState, ContactsAPIClientStub) {
        let client = ContactsAPIClientStub(contacts: cached)
        client.failNextRefresh = failsRefresh
        let appState = AppState(apiClient: client, tokenStore: ContactsInMemoryTokenStore())
        appState.userId = 7
        appState.updateEmergencyContacts(cached)
        let viewModel = EmergencyContactsViewModel()
        viewModel.configure(with: appState, speechService: SpeechService())
        return (viewModel, appState, client)
    }

    private static func contact(id: Int64, isPrimary: Bool = false) -> EmergencyContactResponse {
        EmergencyContactResponse(id: id, name: "联系人\(id)", phone: "13800138000", relationship: nil, isPrimary: isPrimary)
    }

    private static func host(
        _ view: AnyView,
        appState: AppState,
        speech: SpeechService
    ) -> (controller: UIHostingController<AnyView>, window: UIWindow) {
        let controller = UIHostingController(rootView: AnyView(view.environmentObject(appState).environmentObject(speech)))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 393, height: 852))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        return (controller, window)
    }

    private static func spin(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    private static func spin(upTo seconds: TimeInterval, until condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition(), Date() < deadline { spin(0.1) }
    }
}

/// 平时转给 `MockAPIClient`（真实的 Mock 课表）；`fails` 打开后一律断网失败。
private final class SwitchableTrainingClient: APIClientProtocol, @unchecked Sendable {
    private let inner = MockAPIClient()
    var fails = false

    func request<T: Decodable>(
        method: HTTPMethod,
        path: String,
        query: [String: String]?,
        body: (any Encodable & Sendable)?,
        requiresAuth: Bool
    ) async throws -> T {
        if fails { throw URLError(.notConnectedToInternet) }
        return try await inner.request(method: method, path: path, query: query, body: body, requiresAuth: requiresAuth)
    }

    func upload<T: Decodable>(
        path: String,
        query: [String: String]?,
        fields: [String: String]?,
        files: [MultipartFile],
        requiresAuth: Bool
    ) async throws -> T {
        if fails { throw URLError(.notConnectedToInternet) }
        return try await inner.upload(path: path, query: query, fields: fields, files: files, requiresAuth: requiresAuth)
    }
}
