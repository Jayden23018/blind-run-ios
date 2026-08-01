//
//  blindRunTests.swift
//  blindRunTests
//
//  Created by Jerry on 5/18/26.
//

import XCTest
import AMapSearchKit
import CoreLocation
@testable import blindRun

@MainActor
private final class MockSpeechAudioSession: SpeechAudioSessionManaging {
    enum FailurePoint {
        case none
        case deactivate
        case playbackCategory
        case playbackActivation
    }

    var isInputAvailable = true
    var inputNumberOfChannels = 1
    var sampleRate = 44_100.0
    var operations: [String] = []
    var failurePoint: FailurePoint = .none

    func requestRecordPermission(_ response: @escaping (Bool) -> Void) {
        response(true)
    }

    func configureRecordingCategory() throws {
        operations.append("configureRecording")
    }

    func activateRecording() throws {
        operations.append("activateRecording")
    }

    func deactivateRecording() throws {
        operations.append("deactivateRecording")
        if failurePoint == .deactivate { throw MockAudioSessionError.expected }
    }

    func configurePlaybackCategory() throws {
        operations.append("configurePlayback")
        if failurePoint == .playbackCategory { throw MockAudioSessionError.expected }
    }

    func activatePlayback() throws {
        operations.append("activatePlayback")
        if failurePoint == .playbackActivation { throw MockAudioSessionError.expected }
    }
}

private enum MockAudioSessionError: Error {
    case expected
}

@MainActor
final class blindRunTests: XCTestCase {

    func testSendCodeRequestUsesOpenAPICamelCaseKeys() throws {
        let request = SendCodeRequest(phone: "13800138000")
        let data = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(json["phone"], "13800138000")
    }

    /// 后端信封的 `code` 是数字，历史上也出现过字符串形态，两种都要能解出来。
    func testSendCodeResponseDecodesBothNumericAndStringBusinessCode() throws {
        let numeric = #"{"success":true,"message":"验证码已发送","code":0}"#.data(using: .utf8)!
        let numericResponse = try JSONDecoder().decode(SendCodeResponse.self, from: numeric)
        XCTAssertTrue(numericResponse.success == true)
        XCTAssertEqual(numericResponse.message, "验证码已发送")
        XCTAssertEqual(numericResponse.code, "0")

        let string = #"{"success":true,"message":"验证码已发送","code":"654321"}"#.data(using: .utf8)!
        let stringResponse = try JSONDecoder().decode(SendCodeResponse.self, from: string)
        XCTAssertEqual(stringResponse.code, "654321")
    }

    func testVerifyCodeRequestUsesOpenAPICamelCaseKeys() throws {
        let request = VerifyCodeRequest(phone: "13800138000", code: AppConstants.Auth.demoVerificationCode)
        let data = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(json["phone"], "13800138000")
        XCTAssertEqual(json["code"], "000000")
    }

    func testDemoVerificationCodeMatchesCloudContract() {
        XCTAssertEqual(AppConstants.Auth.demoVerificationCode, "000000")
    }

    func testOrderRespondRequestEncodesAcceptAction() throws {
        let request = OrderRespondRequest(action: .accept)
        let data = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(json["action"], "ACCEPT")
    }

    func testVolunteerLocationReporterSendsAuthorizedCloudLocation() {
        var sentCoordinates: [(Double, Double)] = []
        let didReport = VolunteerLocationReporter.reportIfNeeded(
            currentLocation: CLLocationCoordinate2D(latitude: 39.905, longitude: 116.408),
            locationAuthorized: true,
            shouldReportToCloud: true,
            send: { sentCoordinates.append(($0, $1)) }
        )

        XCTAssertTrue(didReport)
        XCTAssertEqual(sentCoordinates.count, 1)
        let expected = BackendCoordinateNormalizer.wgs84ToGCJ02(
            CLLocationCoordinate2D(latitude: 39.905, longitude: 116.408)
        )
        XCTAssertEqual(sentCoordinates[0].0, expected.latitude, accuracy: 0.000001)
        XCTAssertEqual(sentCoordinates[0].1, expected.longitude, accuracy: 0.000001)
    }

    func testVolunteerLocationReporterSkipsUnauthorizedOrMockLocation() {
        var sendCount = 0
        let coordinate = CLLocationCoordinate2D(latitude: 39.905, longitude: 116.408)

        XCTAssertFalse(VolunteerLocationReporter.reportIfNeeded(
            currentLocation: coordinate,
            locationAuthorized: false,
            shouldReportToCloud: true,
            send: { _, _ in sendCount += 1 }
        ))
        XCTAssertFalse(VolunteerLocationReporter.reportIfNeeded(
            currentLocation: coordinate,
            locationAuthorized: true,
            shouldReportToCloud: false,
            send: { _, _ in sendCount += 1 }
        ))
        XCTAssertFalse(VolunteerLocationReporter.reportIfNeeded(
            currentLocation: nil,
            locationAuthorized: true,
            shouldReportToCloud: true,
            send: { _, _ in sendCount += 1 }
        ))
        XCTAssertEqual(sendCount, 0)
    }

    func testDispatchSummaryExplainsMissingBackendReasons() throws {
        let data = #"{"canDispatch":false,"notAvailableReasons":[],"wantsDispatch":true}"#.data(using: .utf8)!
        let summary = try JSONDecoder().decode(VolunteerDispatchSummaryResponse.self, from: data)

        XCTAssertEqual(summary.reasonText, "服务端未返回不可接单原因")
        XCTAssertEqual(summary.dispatchStatusText, "服务端未返回不可接单原因")
        XCTAssertFalse(summary.canDispatch ?? true)
    }

    /// 后端 `DispatchBlockReason.java` 只有三个取值，且 `VolunteerService.getDispatchSummary`
    /// 只评估这三个独立条件。客户端刻意不再定义后端不会下发的取值。
    func testDispatchSummaryMapsEveryBackendReadinessReason() throws {
        let data = #"{"canDispatch":false,"notAvailableReasons":["DISPATCH_DISABLED","NOT_VERIFIED","OFFLINE"]}"#.data(using: .utf8)!
        let summary = try JSONDecoder().decode(VolunteerDispatchSummaryResponse.self, from: data)

        XCTAssertEqual(
            summary.notAvailableReasons,
            [.dispatchDisabled, .notVerified, .offline]
        )
        XCTAssertEqual(summary.reasonText, "已关闭接单、尚未通过资质认证、当前未在线")
    }

    /// 后端新增原因值时整份响应不能因为严格解码而丢失（曾导致志愿者首页被静默吞成全 nil）。
    func testDispatchSummaryDecodesUnknownReasonInsteadOfFailing() throws {
        let data = #"{"canDispatch":false,"notAvailableReasons":["DISPATCH_DISABLED","SOMETHING_NEW"],"totalCompleted":7}"#.data(using: .utf8)!
        let summary = try JSONDecoder().decode(VolunteerDispatchSummaryResponse.self, from: data)

        XCTAssertEqual(summary.completedCount, 7, "未知原因值不得连累同一份响应里的其他字段")
        XCTAssertEqual(summary.notAvailableReasons, [.dispatchDisabled, .unknown])
        XCTAssertEqual(summary.reasonText, "已关闭接单", "未识别的取值不参与文案拼接")
    }

    /// 全是未识别取值时不能拼出空串。
    func testDispatchSummaryFallsBackWhenEveryReasonIsUnknown() throws {
        let data = #"{"canDispatch":false,"notAvailableReasons":["SOMETHING_NEW"]}"#.data(using: .utf8)!
        let summary = try JSONDecoder().decode(VolunteerDispatchSummaryResponse.self, from: data)

        XCTAssertEqual(summary.reasonText, VolunteerDispatchNotAvailableReason.unknown.displayText)
        XCTAssertFalse(summary.reasonText.isEmpty)
    }

    func testVolunteerHomeRefreshesBackendAuthoritativeDispatchSummary() async {
        let client = DispatchSummarySequenceAPIClient()
        let appState = AppState(apiClient: client)
        let viewModel = VolunteerHomeViewModel()
        viewModel.configure(with: appState, speechService: SpeechService())

        await viewModel.refreshDispatchSummary()
        XCTAssertFalse(viewModel.dispatchSummary?.canDispatch ?? true)
        XCTAssertEqual(viewModel.statusText, "服务端未返回不可接单原因")

        await viewModel.refreshDispatchSummary()
        XCTAssertTrue(viewModel.dispatchSummary?.canDispatch ?? false)
        XCTAssertEqual(viewModel.statusText, "已上线，等待系统派单")
        XCTAssertEqual(client.dispatchSummaryRequestCount, 2)
    }

    func testVolunteerHomeSummaryRefreshPreservesActionError() async {
        let client = DispatchSummarySequenceAPIClient()
        let appState = AppState(apiClient: client)
        let viewModel = VolunteerHomeViewModel()
        viewModel.configure(with: appState, speechService: SpeechService())
        viewModel.errorMessage = "可服务状态更新失败，请重试"

        await viewModel.refreshDispatchSummary()

        XCTAssertEqual(viewModel.errorMessage, "可服务状态更新失败，请重试")
        XCTAssertNil(viewModel.dispatchSummaryErrorMessage)
        XCTAssertEqual(viewModel.displayedErrorMessage, "可服务状态更新失败，请重试")
    }

    func testVolunteerHomeSummaryRefreshErrorRecoversIndependently() async {
        let client = RecoveringDispatchSummaryAPIClient()
        let appState = AppState(apiClient: client)
        let viewModel = VolunteerHomeViewModel()
        viewModel.configure(with: appState, speechService: SpeechService())

        await viewModel.refreshDispatchSummary()
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.dispatchSummaryErrorMessage, "派单摘要暂时不可用")
        XCTAssertEqual(viewModel.displayedErrorMessage, "派单摘要暂时不可用")

        await viewModel.refreshDispatchSummary()
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertNil(viewModel.dispatchSummaryErrorMessage)
        XCTAssertTrue(viewModel.dispatchSummary?.canDispatch ?? false)
    }

    func testVolunteerReconnectImmediatelyReportsLatestLocationAndRefreshesSummary() async {
        let client = DispatchSummarySequenceAPIClient()
        let appState = AppState(apiClient: client)
        appState.currentEnvironment = .demoCloud
        appState.activeRole = .volunteer
        let service = WebSocketService()
        appState.webSocketService = service
        var reportCount = 0
        let expectedLocation = CLLocationCoordinate2D(latitude: 39.905, longitude: 116.408)
        let viewModel = VolunteerHomeViewModel(
            dispatchPropagationDelay: 0,
            reportVolunteerLocation: { _, location, authorized in
                XCTAssertTrue(authorized)
                XCTAssertEqual(location?.latitude, expectedLocation.latitude)
                XCTAssertEqual(location?.longitude, expectedLocation.longitude)
                reportCount += 1
                return true
            }
        )
        viewModel.configure(
            with: appState,
            speechService: SpeechService(),
            currentLocationProvider: { expectedLocation },
            locationAuthorizedProvider: { true }
        )
        viewModel.setSceneActive(true)

        service.simulateConnectionStateForTesting(.connected)
        service.simulateConnectionStateForTesting(.reconnecting(attempt: 1))
        service.simulateConnectionStateForTesting(.connected)

        let didRecover = await waitUntil {
            reportCount == 1 && client.dispatchSummaryRequestCount == 1
        }
        XCTAssertTrue(didRecover)
        XCTAssertNil(viewModel.locationDispatchWarning)
    }

    /// 生产代码里的连续失败阈值（VolunteerHomeViewModel.locationReportFailureThreshold）。
    private static let locationReportFailureThreshold = 3

    /// 单次采样为 nil 是常见瞬态，必须完全静默：横幅不能闪，也不能播报。
    func testVolunteerSingleLocationReportFailureStaysSilent() async {
        let client = DispatchSummarySequenceAPIClient()
        let appState = AppState(apiClient: client)
        appState.currentEnvironment = .demoCloud
        let speechService = SpeechService()
        let viewModel = VolunteerHomeViewModel(
            dispatchPropagationDelay: 0,
            reportVolunteerLocation: { _, _, _ in false }
        )
        viewModel.configure(with: appState, speechService: speechService)

        await viewModel.reportLocationThenRefreshSummary(
            currentLocation: nil,
            locationAuthorized: false
        )

        XCTAssertNil(viewModel.locationDispatchWarning)
        XCTAssertNil(speechService.lastSpokenText)
    }

    /// 连续失败达到阈值才报警，且重复失败不重复播报。
    func testVolunteerMissingLocationShowsAndSpeaksDispatchWarningAfterThreshold() async {
        let client = DispatchSummarySequenceAPIClient()
        let appState = AppState(apiClient: client)
        appState.currentEnvironment = .demoCloud
        let speechService = SpeechService()
        let viewModel = VolunteerHomeViewModel(
            dispatchPropagationDelay: 0,
            reportVolunteerLocation: { _, _, _ in false }
        )
        viewModel.configure(with: appState, speechService: speechService)

        for attempt in 1..<Self.locationReportFailureThreshold {
            await viewModel.reportLocationThenRefreshSummary(
                currentLocation: nil,
                locationAuthorized: false
            )
            XCTAssertNil(viewModel.locationDispatchWarning, "第 \(attempt) 次失败仍应静默")
        }

        await viewModel.reportLocationThenRefreshSummary(
            currentLocation: nil,
            locationAuthorized: false
        )
        XCTAssertEqual(viewModel.locationDispatchWarning, "定位暂不可用，可能无法收到派单")
        XCTAssertEqual(speechService.lastSpokenText, "定位暂不可用，可能无法收到派单")

        // 已在报警状态时再失败，不得重复播报。
        speechService.speak("哨兵播报")
        await viewModel.reportLocationThenRefreshSummary(
            currentLocation: nil,
            locationAuthorized: false
        )
        XCTAssertEqual(viewModel.locationDispatchWarning, "定位暂不可用，可能无法收到派单")
        XCTAssertEqual(speechService.lastSpokenText, "哨兵播报")
    }

    /// 中途上报成功要清空横幅并复位计数，之后再来一次瞬态失败仍然不报警。
    func testVolunteerSuccessfulLocationReportResetsWarningSuppression() async {
        let client = DispatchSummarySequenceAPIClient()
        let appState = AppState(apiClient: client)
        appState.currentEnvironment = .demoCloud
        let speechService = SpeechService()
        var shouldSucceed = false
        let viewModel = VolunteerHomeViewModel(
            dispatchPropagationDelay: 0,
            reportVolunteerLocation: { _, _, _ in shouldSucceed }
        )
        viewModel.configure(with: appState, speechService: speechService)

        for _ in 0..<Self.locationReportFailureThreshold {
            await viewModel.reportLocationThenRefreshSummary(
                currentLocation: nil,
                locationAuthorized: false
            )
        }
        XCTAssertEqual(viewModel.locationDispatchWarning, "定位暂不可用，可能无法收到派单")

        shouldSucceed = true
        await viewModel.reportLocationThenRefreshSummary(
            currentLocation: CLLocationCoordinate2D(latitude: 39.905, longitude: 116.408),
            locationAuthorized: true
        )
        XCTAssertNil(viewModel.locationDispatchWarning)

        speechService.speak("哨兵播报")
        shouldSucceed = false
        await viewModel.reportLocationThenRefreshSummary(
            currentLocation: nil,
            locationAuthorized: false
        )
        XCTAssertNil(viewModel.locationDispatchWarning, "复位后单次失败必须重新回到静默")
        XCTAssertEqual(speechService.lastSpokenText, "哨兵播报")
    }

    func testVolunteerHomeCancellationClearsInitialLoadingState() async {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let viewModel = VolunteerHomeViewModel(
            dispatchPropagationDelay: 60,
            reportVolunteerLocation: { _, _, _ in true }
        )
        viewModel.configure(with: appState, speechService: SpeechService())

        let loadTask = Task {
            await viewModel.load(
                currentLocation: CLLocationCoordinate2D(latitude: 39.905, longitude: 116.408),
                locationAuthorized: true
            )
        }
        let didBeginLoading = await waitUntil { viewModel.isLoading }
        XCTAssertTrue(didBeginLoading)

        loadTask.cancel()
        await loadTask.value

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testBlindRunnerHomeCancellationClearsLoadingState() async {
        let appState = AppState(apiClient: CancellationSuspendingAPIClient())
        let viewModel = BlindRunnerHomeViewModel()
        viewModel.configure(with: appState, speechService: SpeechService())

        let loadTask = Task { await viewModel.loadActiveOrder() }
        let didBeginLoading = await waitUntil { viewModel.isLoading }
        XCTAssertTrue(didBeginLoading)

        loadTask.cancel()
        await loadTask.value

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testBlindRunnerHomeTimeoutReleasesLoadingAndOffersRetryState() async {
        let client = CancellationSuspendingAPIClient()
        let appState = AppState(apiClient: client)
        let viewModel = BlindRunnerHomeViewModel(loadTimeout: 0.05)
        viewModel.configure(with: appState, speechService: SpeechService())

        let loadTask = Task { await viewModel.loadActiveOrder() }
        let didTimeout = await waitUntil { !viewModel.isLoading && viewModel.errorMessage != nil }
        await loadTask.value

        XCTAssertTrue(didTimeout)
        XCTAssertEqual(viewModel.errorMessage, "加载超过 20 秒，请重试。")
        XCTAssertGreaterThanOrEqual(client.cancellationCount, 1)
    }

    func testHomeLoadCoordinatorCancelsSuspendedRequestAtDeadline() async {
        let client = CancellationSuspendingAPIClient()

        do {
            let _: PagedOrderResponse = try await HomeLoadCoordinator.run(timeout: 0.05) {
                try await client.get("/api/orders/mine")
            }
            XCTFail("Expected the home request to time out")
        } catch HomeLoadCoordinatorError.timedOut {
            await client.awaitCancellation()
            XCTAssertGreaterThanOrEqual(client.cancellationCount, 1)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testHomeLoadCoordinatorReturnsAtDeadlineWhenRequestIgnoresCancellation() async {
        let client = ControlledNonCooperativeAPIClient()
        let startedAt = Date()

        do {
            let _: PagedOrderResponse = try await HomeLoadCoordinator.run(
                timeout: 0.05,
                operationName: "non-cooperative-test"
            ) {
                try await client.get("/api/orders/mine")
            }
            XCTFail("Expected the home request to time out")
        } catch HomeLoadCoordinatorError.timedOut {
            XCTAssertLessThan(Date().timeIntervalSince(startedAt), 0.5)
            XCTAssertTrue(client.hasStarted)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        client.release()
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(client.didReturnLateResponse)
    }

    func testBlindRunnerHomeDiscardsResponseArrivingAfterDeadline() async {
        let client = ControlledNonCooperativeAPIClient()
        let appState = AppState(apiClient: client)
        let viewModel = BlindRunnerHomeViewModel(loadTimeout: 0.05)
        viewModel.configure(with: appState, speechService: SpeechService())

        await viewModel.loadActiveOrder()
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertEqual(viewModel.errorMessage, "加载超过 20 秒，请重试。")

        client.release()
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNil(viewModel.activeOrder)
        XCTAssertEqual(viewModel.errorMessage, "加载超过 20 秒，请重试。")
    }

    func testBlindRunnerCannotStartBookingBeforeActiveOrderIsConfirmed() {
        let appState = AppState(apiClient: CancellationSuspendingAPIClient())
        let viewModel = BlindRunnerHomeViewModel()
        viewModel.configure(with: appState, speechService: SpeechService())

        XCTAssertFalse(viewModel.canStartNewBooking)
        viewModel.explainBookingUnavailable()
        XCTAssertEqual(viewModel.errorMessage, "订单状态尚未确认，请先重试加载，避免创建重复预约。")
    }

    func testVolunteerHomeTimeoutReleasesLoadingAndOffersRetryState() async {
        let client = CancellationSuspendingAPIClient()
        let appState = AppState(apiClient: client)
        let viewModel = VolunteerHomeViewModel(dispatchPropagationDelay: 0, loadTimeout: 0.05)
        viewModel.configure(with: appState, speechService: SpeechService())

        let loadTask = Task { await viewModel.load(currentLocation: nil, locationAuthorized: false) }
        let didTimeout = await waitUntil { !viewModel.isLoading && viewModel.dispatchSummaryErrorMessage != nil }
        await loadTask.value

        XCTAssertTrue(didTimeout)
        XCTAssertEqual(viewModel.dispatchSummaryErrorMessage, "加载超过 20 秒，请重试。")
        XCTAssertGreaterThanOrEqual(client.cancellationCount, 1)
    }

    func testBlindRunnerHomeCoalescesConcurrentRefreshTriggersWithoutExtendingDeadline() async {
        let client = CancellationSuspendingAPIClient()
        let appState = AppState(apiClient: client)
        let existingOrder = makeOrder(orderId: 701, status: .driverEnRoute)
        let viewModel = BlindRunnerHomeViewModel(loadTimeout: 0.08)
        viewModel.configure(with: appState, speechService: SpeechService())
        viewModel.activeOrder = existingOrder
        let startedAt = Date()

        let lifecycleLoad = Task { await viewModel.loadActiveOrder() }
        let didStart = await waitUntil {
            client.requestCount(for: "/api/orders/mine") == 1
        }
        let reconnectLoad = Task { await viewModel.loadActiveOrder() }
        let manualLoad = Task { await viewModel.loadActiveOrder() }
        await lifecycleLoad.value
        await reconnectLoad.value
        await manualLoad.value

        XCTAssertTrue(didStart)
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 0.5)
        XCTAssertEqual(client.requestCount(for: "/api/orders/mine"), 1)
        XCTAssertEqual(viewModel.activeOrder?.orderId, existingOrder.orderId)
        XCTAssertEqual(viewModel.activeOrder?.status, .driverEnRoute)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertEqual(viewModel.errorMessage, "加载超过 20 秒，请重试。")
    }

    func testVolunteerHomeCoalescesLifecycleReconnectAndManualRefreshWhileKeepingContent() async throws {
        let client = CancellationSuspendingAPIClient()
        let appState = AppState(apiClient: client)
        let existingSummary = try JSONDecoder().decode(
            VolunteerDispatchSummaryResponse.self,
            from: Data(#"{"canDispatch":true,"notAvailableReasons":[],"wantsDispatch":true}"#.utf8)
        )
        let existingOrder = makeOrder(orderId: 702, status: .driverEnRoute)
        let viewModel = VolunteerHomeViewModel(dispatchPropagationDelay: 0, loadTimeout: 0.08)
        viewModel.configure(with: appState, speechService: SpeechService())
        viewModel.dispatchSummary = existingSummary
        viewModel.activeOrder = existingOrder
        let startedAt = Date()

        let lifecycleLoad = Task {
            await viewModel.load(currentLocation: nil, locationAuthorized: false)
        }
        let didStart = await waitUntil {
            client.requestCount(for: "/api/volunteer/dispatch-summary") == 1
        }
        let reconnectLoad = Task {
            await viewModel.load(currentLocation: nil, locationAuthorized: false)
        }
        let manualRefresh = Task { await viewModel.refreshDispatchSummary() }
        await lifecycleLoad.value
        await reconnectLoad.value
        await manualRefresh.value

        XCTAssertTrue(didStart)
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 0.5)
        XCTAssertEqual(client.requestCount(for: "/api/volunteer/dispatch-summary"), 1)
        XCTAssertEqual(viewModel.dispatchSummary?.canDispatch, true)
        XCTAssertEqual(viewModel.activeOrder?.orderId, existingOrder.orderId)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertEqual(viewModel.dispatchSummaryErrorMessage, "加载超过 20 秒，请重试。")
    }

    func testVolunteerDispatchSummaryDoesNotWaitForSlowProfileHydration() async {
        let client = SummaryFirstAPIClient()
        let appState = AppState(apiClient: client)
        let viewModel = VolunteerHomeViewModel(dispatchPropagationDelay: 0, loadTimeout: 2)
        viewModel.configure(with: appState, speechService: SpeechService())

        let loadTask = Task { await viewModel.load(currentLocation: nil, locationAuthorized: false) }
        let didLoadSummary = await waitUntil(timeout: 0.5) {
            viewModel.dispatchSummary?.canDispatch == true && !viewModel.isLoading
        }

        XCTAssertTrue(didLoadSummary)
        XCTAssertEqual(client.summaryRequestCount, 1)
        loadTask.cancel()
        await loadTask.value
    }

    func testAcceptingDispatchPublishesNavigationOrderId() async throws {
        let appState = AppState()
        appState.currentEnvironment = .mock
        appState.updateVolunteerProfile(makeApprovedVolunteerProfile())
        let speechService = SpeechService()
        let viewModel = VolunteerHomeViewModel()
        viewModel.configure(with: appState, speechService: speechService)
        viewModel.incomingOrder = makeDispatchOrder(orderId: 1)
        viewModel.dispatchCountdown = 30

        viewModel.respondToDispatch(
            accept: true,
            currentLocation: CLLocationCoordinate2D(latitude: 39.905, longitude: 116.408),
            locationAuthorized: true
        )

        let didNavigate = await waitUntil { viewModel.acceptedDispatchOrderId == 1 }
        XCTAssertTrue(didNavigate)
        XCTAssertEqual(viewModel.acceptedDispatchOrderId, 1)
        XCTAssertEqual(viewModel.acceptedDispatchInitialOrder?.orderId, 1)
        XCTAssertEqual(viewModel.acceptedDispatchInitialOrder?.status, .pendingAccept)
        XCTAssertEqual(viewModel.activeOrder?.orderId, 1)
        XCTAssertEqual(viewModel.activeOrder?.status, .pendingAccept)
        XCTAssertNil(viewModel.incomingOrder)
        XCTAssertEqual(viewModel.dispatchCountdown, 0)
        XCTAssertFalse(viewModel.isRespondingToDispatch)
        XCTAssertEqual(speechService.lastSpokenText, "已接受订单")
    }

    func testAcceptingDispatchFailureDoesNotPublishNavigationOrderId() async throws {
        let appState = AppState()
        appState.currentEnvironment = .mock
        appState.updateVolunteerProfile(makeApprovedVolunteerProfile())
        let viewModel = VolunteerHomeViewModel()
        viewModel.configure(with: appState, speechService: SpeechService())
        viewModel.incomingOrder = makeDispatchOrder(orderId: 999)
        viewModel.dispatchCountdown = 30

        viewModel.respondToDispatch(
            accept: true,
            currentLocation: CLLocationCoordinate2D(latitude: 39.905, longitude: 116.408),
            locationAuthorized: true
        )

        let didFail = await waitUntil { viewModel.errorMessage != nil }
        XCTAssertTrue(didFail)
        XCTAssertNil(viewModel.acceptedDispatchOrderId)
        XCTAssertNotNil(viewModel.incomingOrder)
        XCTAssertEqual(viewModel.dispatchCountdown, 30)
        XCTAssertFalse(viewModel.isRespondingToDispatch)
    }

    func testAcceptingDispatchRequiresReadinessAndLocation() async throws {
        let unavailableState = AppState()
        unavailableState.currentEnvironment = .mock
        unavailableState.updateVolunteerProfile(makeApprovedVolunteerProfile(isAvailable: false))
        let unavailableViewModel = VolunteerHomeViewModel()
        unavailableViewModel.configure(with: unavailableState, speechService: SpeechService())
        unavailableViewModel.incomingOrder = makeDispatchOrder(orderId: 1)

        unavailableViewModel.respondToDispatch(
            accept: true,
            currentLocation: CLLocationCoordinate2D(latitude: 39.905, longitude: 116.408),
            locationAuthorized: true
        )

        XCTAssertEqual(unavailableViewModel.errorMessage, "请先开启可服务状态")
        XCTAssertNil(unavailableViewModel.acceptedDispatchOrderId)
        XCTAssertNotNil(unavailableViewModel.incomingOrder)

        let noLocationState = AppState()
        noLocationState.currentEnvironment = .mock
        noLocationState.updateVolunteerProfile(makeApprovedVolunteerProfile())
        let noLocationViewModel = VolunteerHomeViewModel()
        noLocationViewModel.configure(with: noLocationState, speechService: SpeechService())
        noLocationViewModel.incomingOrder = makeDispatchOrder(orderId: 1)

        noLocationViewModel.respondToDispatch(
            accept: true,
            currentLocation: nil,
            locationAuthorized: false
        )

        XCTAssertEqual(noLocationViewModel.errorMessage, "需要开启定位权限才能接单")
        XCTAssertNil(noLocationViewModel.acceptedDispatchOrderId)
        XCTAssertNotNil(noLocationViewModel.incomingOrder)
    }

    func testDecliningDispatchDoesNotPublishNavigationOrderId() async throws {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let viewModel = VolunteerHomeViewModel()
        viewModel.configure(with: appState, speechService: speechService)
        viewModel.incomingOrder = makeDispatchOrder(orderId: 1)
        viewModel.dispatchCountdown = 30

        viewModel.respondToDispatch(
            accept: false,
            currentLocation: nil,
            locationAuthorized: false
        )

        let didDecline = await waitUntil { viewModel.incomingOrder == nil }
        XCTAssertTrue(didDecline)
        XCTAssertNil(viewModel.acceptedDispatchOrderId)
        XCTAssertEqual(viewModel.dispatchCountdown, 0)
        XCTAssertFalse(viewModel.isRespondingToDispatch)
        XCTAssertEqual(speechService.lastSpokenText, "已拒绝订单")
    }

    func testVolunteerHomeReceivesDispatchWhenWebSocketIsAssignedAfterConfigure() async throws {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let viewModel = VolunteerHomeViewModel()

        viewModel.configure(with: appState, speechService: speechService)

        let webSocketService = WebSocketService()
        appState.webSocketService = webSocketService
        webSocketService.simulateIncomingEventForTesting(.newOrder(makeDispatchOrder(orderId: 42)))

        let didReceive = await waitUntil { viewModel.incomingOrder?.orderId == 42 }
        XCTAssertTrue(didReceive)
        XCTAssertEqual(viewModel.dispatchCountdown, 30)
        XCTAssertEqual(speechService.lastSpokenText, "新订单到达，请在30秒内响应")
    }

    func testVolunteerHomeResubscribesWhenWebSocketServiceIsReplaced() async throws {
        let appState = AppState()
        appState.currentEnvironment = .mock
        appState.updateVolunteerProfile(makeApprovedVolunteerProfile())
        let viewModel = VolunteerHomeViewModel()

        viewModel.configure(with: appState, speechService: SpeechService())

        let firstWebSocketService = WebSocketService()
        appState.webSocketService = firstWebSocketService
        firstWebSocketService.simulateIncomingEventForTesting(.newOrder(makeDispatchOrder(orderId: 41)))

        let didReceiveInitialEvent = await waitUntil { viewModel.incomingOrder?.orderId == 41 }
        XCTAssertTrue(didReceiveInitialEvent)
        viewModel.dismissDispatch()

        let replacementWebSocketService = WebSocketService()
        appState.webSocketService = replacementWebSocketService
        firstWebSocketService.simulateIncomingEventForTesting(.newOrder(makeDispatchOrder(orderId: 40)))

        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNil(viewModel.incomingOrder)

        replacementWebSocketService.simulateIncomingEventForTesting(.newOrder(makeDispatchOrder(orderId: 43)))

        let didReceiveReplacementEvent = await waitUntil { viewModel.incomingOrder?.orderId == 43 }
        XCTAssertTrue(didReceiveReplacementEvent)
    }

    func testVolunteerHomeActiveOrderFiltersVolunteerServiceStatuses() throws {
        let activeOrder = try XCTUnwrap(VolunteerHomeViewModel.activeVolunteerOrder(from: [
            makeOrder(orderId: 1, status: .pendingMatch, createdAt: "2026-06-25T10:00:00Z"),
            makeOrder(orderId: 2, status: .pendingAccept, createdAt: "2026-06-25T11:00:00Z"),
            makeOrder(orderId: 3, status: .driverEnRoute, createdAt: "2026-06-25T12:00:00Z"),
            makeOrder(orderId: 4, status: .completed, createdAt: "2026-06-25T13:00:00Z"),
            makeOrder(orderId: 5, status: .cancelled, createdAt: "2026-06-25T14:00:00Z")
        ]))

        XCTAssertEqual(activeOrder.orderId, 3)
    }

    func testVolunteerHomeActiveOrderIgnoresTerminalOrders() {
        let activeOrder = VolunteerHomeViewModel.activeVolunteerOrder(from: [
            makeOrder(orderId: 1, status: .pendingMatch),
            makeOrder(orderId: 2, status: .completed),
            makeOrder(orderId: 3, status: .cancelled),
            makeOrder(orderId: 4, status: .noVolunteer)
        ])

        XCTAssertNil(activeOrder)
    }

    func testVolunteerHomeLoadShowsAcceptedOrderAsActiveOrder() async throws {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let viewModel = VolunteerHomeViewModel()
        viewModel.configure(with: appState, speechService: SpeechService())

        await viewModel.load(currentLocation: nil, locationAuthorized: false)
        XCTAssertNil(viewModel.activeOrder)

        appState.updateVolunteerProfile(makeApprovedVolunteerProfile())
        viewModel.incomingOrder = makeDispatchOrder(orderId: 1)
        viewModel.respondToDispatch(
            accept: true,
            currentLocation: CLLocationCoordinate2D(latitude: 39.905, longitude: 116.408),
            locationAuthorized: true
        )

        let didAccept = await waitUntil { viewModel.acceptedDispatchOrderId == 1 }
        XCTAssertTrue(didAccept)

        await viewModel.load(currentLocation: nil, locationAuthorized: false)

        XCTAssertEqual(viewModel.activeOrder?.orderId, 1)
        XCTAssertEqual(viewModel.activeOrder?.status, .pendingAccept)
    }

    func testVolunteerDemandPanelDetentHeightsAndNearestSnap() {
        let viewportHeight: CGFloat = 1_000
        let topContentBottom: CGFloat = 180
        let compactHeight = VolunteerDemandPanelDetent.compact.height(
            viewportHeight: viewportHeight,
            topContentBottom: topContentBottom
        )
        let mediumHeight = VolunteerDemandPanelDetent.medium.height(
            viewportHeight: viewportHeight,
            topContentBottom: topContentBottom
        )
        let expandedHeight = VolunteerDemandPanelDetent.expanded.height(
            viewportHeight: viewportHeight,
            topContentBottom: topContentBottom
        )

        XCTAssertLessThan(compactHeight, mediumHeight)
        XCTAssertLessThan(mediumHeight, expandedHeight)
        XCTAssertEqual(
            VolunteerDemandPanelDetent.nearest(
                to: compactHeight + 4,
                viewportHeight: viewportHeight,
                topContentBottom: topContentBottom
            ),
            .compact
        )
        XCTAssertEqual(
            VolunteerDemandPanelDetent.nearest(
                to: expandedHeight - 4,
                viewportHeight: viewportHeight,
                topContentBottom: topContentBottom
            ),
            .expanded
        )
    }

    func testVolunteerHomeTopLayoutIsDeterministicAndDoesNotDependOnChildMeasurement() {
        let withoutOrder = VolunteerHomeTopLayout.reservedBottom(
            safeAreaTop: 24,
            hasActiveOrder: false
        )
        let withOrder = VolunteerHomeTopLayout.reservedBottom(
            safeAreaTop: 24,
            hasActiveOrder: true
        )

        XCTAssertEqual(withoutOrder, 204)
        XCTAssertEqual(withOrder, 324)
        XCTAssertGreaterThan(withOrder, withoutOrder)
        XCTAssertEqual(
            VolunteerHomeTopLayout.reservedBottom(
                safeAreaTop: .nan,
                hasActiveOrder: true
            ),
            300
        )
    }

    func testCurrentValueReplayGateRejectsPublisherReplayAcrossViewRecalculation() {
        var healthGate = CurrentValueReplayGate<LiveEscortHealthState>()

        XCTAssertTrue(healthGate.accepts(.active(background: false)))
        XCTAssertFalse(healthGate.accepts(.active(background: false)))
        XCTAssertTrue(healthGate.accepts(.active(background: true)))
        XCTAssertFalse(healthGate.accepts(.active(background: true)))
        XCTAssertTrue(healthGate.accepts(.idle))
        XCTAssertTrue(healthGate.accepts(.active(background: false)))

        let notificationID = UUID()
        var notificationGate = CurrentValueReplayGate<UUID>()
        XCTAssertTrue(notificationGate.accepts(notificationID))
        XCTAssertFalse(notificationGate.accepts(notificationID))
        XCTAssertTrue(notificationGate.accepts(UUID()))
    }

    func testVolunteerHomeMapAnchorUsesVisibleAreaAndClampsExtremes() {
        let normalAnchor = VolunteerHomeMapLayout.screenAnchorY(
            viewportHeight: 1_000,
            topContentBottom: 160,
            demandPanelTop: 580
        )
        XCTAssertEqual(normalAnchor, 0.37, accuracy: 0.0001)

        let highAnchor = VolunteerHomeMapLayout.screenAnchorY(
            viewportHeight: 1_000,
            topContentBottom: -500,
            demandPanelTop: -200
        )
        XCTAssertEqual(highAnchor, 0.18, accuracy: 0.0001)

        let lowAnchor = VolunteerHomeMapLayout.screenAnchorY(
            viewportHeight: 1_000,
            topContentBottom: 1_600,
            demandPanelTop: 1_700
        )
        XCTAssertEqual(lowAnchor, 0.82, accuracy: 0.0001)
    }

    func testVolunteerHomeLayoutHelpersNeverReturnInvalidFrameDimensions() {
        let invalidValues: [CGFloat] = [
            0,
            -40,
            .nan,
            .infinity,
            -.infinity
        ]

        for viewportHeight in invalidValues {
            for topContentBottom in invalidValues {
                for detent in VolunteerDemandPanelDetent.allCases {
                    let height = detent.height(
                        viewportHeight: viewportHeight,
                        topContentBottom: topContentBottom
                    )

                    XCTAssertTrue(height.isFinite)
                    XCTAssertGreaterThan(height, 0)
                }

                let clampedHeight = VolunteerDemandPanelDetent.clampedHeight(
                    .nan,
                    viewportHeight: viewportHeight,
                    topContentBottom: topContentBottom
                )
                XCTAssertTrue(clampedHeight.isFinite)
                XCTAssertGreaterThan(clampedHeight, 0)

                let anchor = VolunteerHomeMapLayout.screenAnchorY(
                    viewportHeight: viewportHeight,
                    topContentBottom: topContentBottom,
                    demandPanelTop: .nan
                )
                XCTAssertTrue(anchor.isFinite)
                XCTAssertGreaterThanOrEqual(anchor, 0.18)
                XCTAssertLessThanOrEqual(anchor, 0.82)
            }
        }
    }

    func testFlexibleErrorEnvelopeUsesBusinessErrorCode() throws {
        let data = #"{"errorCode":"VOLUNTEER_NOT_AVAILABLE","code":403,"success":false,"message":"未开启接单"}"#.data(using: .utf8)!
        let payload = try JSONDecoder().decode(APIErrorEnvelope.self, from: data)
        let response = try XCTUnwrap(payload.resolvedErrorResponse(statusCode: 403))

        XCTAssertEqual(response.code, "VOLUNTEER_NOT_AVAILABLE")
        XCTAssertEqual(response.message, "未开启接单")
    }

    /// 裸 `{"error": ...}` 信封**刻意不再解析** —— 这不是漏了，是 2026-07-31 与后端确认后删的。
    ///
    /// 后端全仓只剩两处产出 `error` 键，客户端都够不到：
    /// - `AuthController:62` 的 401 `{"error":"未登录"}` —— `APIClient` 在 `case 401`
    ///   直接 `throw .unauthorized`，body 根本不解码
    /// - `GlobalExceptionHandler:224` 的 429 —— 那里 `error` 放的是错误码字符串不是文案，
    ///   且同一个 body 恒带 `message`，兜底分支走不到
    ///
    /// 而本用例原来喂的 `{"error":"验证码错误或已过期"}` 是**已下线的旧验证码响应形状**，
    /// 现在统一走 `{success,code,errorCode,message}`。
    func testFlexibleErrorEnvelopeIgnoresLegacyBareErrorKey() throws {
        let data = #"{"error":"验证码错误或已过期"}"#.data(using: .utf8)!
        let payload = try JSONDecoder().decode(APIErrorEnvelope.self, from: data)

        XCTAssertNil(payload.resolvedErrorResponse(statusCode: 400))
    }

    func testEmptyResponseDecodesEmptyObjectsAndEnvelopePayloads() throws {
        XCTAssertNoThrow(try JSONDecoder().decode(EmptyResponse.self, from: #"{}"#.data(using: .utf8)!))
        XCTAssertNoThrow(try JSONDecoder().decode(EmptyResponse.self, from: #"{"success":true}"#.data(using: .utf8)!))

        let envelope = try JSONDecoder().decode(
            APIEnvelopeResponse<EmptyResponse>.self,
            from: #"{"success":true,"data":{}}"#.data(using: .utf8)!
        )
        XCTAssertNotNil(envelope.data)
    }

    func testMockOrderActionsSupportEmptyResponseAndFetchDetailAfterwards() async throws {
        let client = MockAPIClient()
        let available: PagedOrderResponse = try await client.get("/api/orders/available")
        let order = try XCTUnwrap(available.content.first)

        let _: EmptyResponse = try await client.post(
            "/api/orders/\(order.orderId)/respond",
            body: OrderRespondRequest(action: .accept)
        )
        var detail: OrderDetailResponse = try await client.get("/api/orders/\(order.orderId)")
        XCTAssertEqual(detail.status, .pendingAccept)

        let _: EmptyResponse = try await client.post("/api/orders/\(order.orderId)/en-route")
        detail = try await client.get("/api/orders/\(order.orderId)")
        XCTAssertEqual(detail.status, .driverEnRoute)

        let _: EmptyResponse = try await client.post("/api/orders/\(order.orderId)/arrived")
        detail = try await client.get("/api/orders/\(order.orderId)")
        XCTAssertEqual(detail.status, .driverArrived)

        do {
            let _: EmptyResponse = try await client.post("/api/orders/\(order.orderId)/finish")
            XCTFail("Mock should reject finish before IN_PROGRESS")
        } catch let error as APIError {
            guard case .serverError(let response) = error else {
                return XCTFail("Expected serverError, got \(error)")
            }
            XCTAssertEqual(response.code, "ORDER_STATUS_NOT_ALLOWED")
        }

        let _: EmptyResponse = try await client.post("/api/orders/\(order.orderId)/start-service")
        detail = try await client.get("/api/orders/\(order.orderId)")
        XCTAssertEqual(detail.status, .inProgress)

        let _: EmptyResponse = try await client.post("/api/orders/\(order.orderId)/finish")
        detail = try await client.get("/api/orders/\(order.orderId)")
        XCTAssertEqual(detail.status, .completed)
    }

    func testMockEmergencyContactUpdateSupportsBlindProfileEditSave() async throws {
        let client = MockAPIClient()
        let contacts: [EmergencyContactResponse] = try await client.get("/api/users/1/emergency-contacts")
        let contact = try XCTUnwrap(contacts.first)

        let updated: EmergencyContactResponse = try await client.put(
            "/api/users/1/emergency-contacts/\(contact.id)",
            body: EmergencyContactRequest(
                name: "一个人",
                phone: "13888888888",
                relationship: nil,
                isPrimary: true
            )
        )

        XCTAssertEqual(updated.id, contact.id)
        XCTAssertEqual(updated.name, "一个人")
        XCTAssertEqual(updated.phone, "13888888888")
        XCTAssertEqual(updated.isPrimary, true)

        let refreshedContacts: [EmergencyContactResponse] = try await client.get("/api/users/1/emergency-contacts")
        let refreshedContact = try XCTUnwrap(refreshedContacts.first(where: { $0.id == contact.id }))
        XCTAssertEqual(refreshedContact.name, "一个人")
        XCTAssertEqual(refreshedContact.phone, "13888888888")
    }

    func testMockVolunteerDispatchSummaryReflectsDispatchStatusAndActiveOrder() async throws {
        let client = MockAPIClient()

        let initialSummary: VolunteerDispatchSummaryResponse = try await client.get("/api/volunteer/dispatch-summary")
        XCTAssertFalse(initialSummary.canDispatch ?? true)
        // Mock 只在开启接单时上报位置，所以关掉接单时 DISPATCH_DISABLED 与 OFFLINE 同时命中
        // （与后端 getDispatchSummary 的三条件独立评估一致）。
        XCTAssertEqual(initialSummary.notAvailableReasons, [.dispatchDisabled, .offline])
        XCTAssertEqual(initialSummary.completedCount, 1)
        XCTAssertEqual(initialSummary.resolvedPointsBalance, 100)

        let _: EmptyResponse = try await client.put(
            "/api/volunteer/dispatch-status",
            body: DispatchStatusRequest(wantsDispatch: true)
        )
        let enabledSummary: VolunteerDispatchSummaryResponse = try await client.get("/api/volunteer/dispatch-summary")
        XCTAssertTrue(enabledSummary.canDispatch ?? false)
        XCTAssertTrue(enabledSummary.activeOrders?.isEmpty ?? false)

        let _: EmptyResponse = try await client.post(
            "/api/orders/1/respond",
            body: OrderRespondRequest(action: .accept)
        )
        let activeSummary: VolunteerDispatchSummaryResponse = try await client.get("/api/volunteer/dispatch-summary")
        // 后端 `VolunteerService.getDispatchSummary` 只评估三个独立条件
        // （DISPATCH_DISABLED / NOT_VERIFIED / OFFLINE，见 `DispatchBlockReason.java`）。
        // 在途订单**不**产生 notAvailableReason，也不影响 canDispatch —— 派单入口另行过滤。
        XCTAssertTrue(activeSummary.canDispatch ?? false)
        XCTAssertEqual(activeSummary.notAvailableReasons, [])
        let activeOrder = try XCTUnwrap(activeSummary.activeOrders?.first)
        XCTAssertEqual(activeOrder.orderId, 1)
        XCTAssertEqual(try XCTUnwrap(activeOrder.startLatitude), 39.9342, accuracy: 0.000001)
        XCTAssertEqual(try XCTUnwrap(activeOrder.startLongitude), 116.4740, accuracy: 0.000001)
        XCTAssertEqual(try XCTUnwrap(activeOrder.orderDetail.startLatitude), 39.9342, accuracy: 0.000001)
        XCTAssertEqual(try XCTUnwrap(activeOrder.orderDetail.startLongitude), 116.4740, accuracy: 0.000001)
        XCTAssertEqual(activeSummary.recentOrders?.first?.startAddress, "朝阳公园南门")
    }

    func testVolunteerDispatchSummaryActiveOrderDecodesAndPreservesCoordinatesInOrderDetail() throws {
        let json = """
        {
          "orderId": 42,
          "status": "PENDING_ACCEPT",
          "plannedStartTime": "2026-07-02T21:10:00",
          "plannedEndTime": "2026-07-02T22:10:00",
          "startAddress": "云南省昆明市西山区福海街道庾园路五家堆湿地公园",
          "startLatitude": 25.02712,
          "startLongitude": 102.68742,
          "blindName": "盲人跑者",
          "blindPhoneMasked": "138****0002",
          "acceptedAt": "2026-07-02T20:32:00"
        }
        """.data(using: .utf8)!

        let activeOrder = try JSONDecoder().decode(VolunteerDispatchSummaryActiveOrder.self, from: json)

        XCTAssertEqual(try XCTUnwrap(activeOrder.startLatitude), 25.02712, accuracy: 0.000001)
        XCTAssertEqual(try XCTUnwrap(activeOrder.startLongitude), 102.68742, accuracy: 0.000001)
        XCTAssertEqual(activeOrder.orderDetail.startAddress, "云南省昆明市西山区福海街道庾园路五家堆湿地公园")
        XCTAssertEqual(try XCTUnwrap(activeOrder.orderDetail.startLatitude), 25.02712, accuracy: 0.000001)
        XCTAssertEqual(try XCTUnwrap(activeOrder.orderDetail.startLongitude), 102.68742, accuracy: 0.000001)
    }

    func testMockFormalTwoRoleHappyPathThroughReview() async throws {
        let client = MockAPIClient()
        let plannedStart = Date().addingTimeInterval(45 * 60)
        let plannedEnd = plannedStart.addingTimeInterval(60 * 60)
        let createResponse: OrderResponse = try await client.post(
            "/api/orders",
            body: CreateOrderRequest(
                startLatitude: 39.9342,
                startLongitude: 116.4740,
                startAddress: "朝阳公园南门",
                plannedStartTime: DateFormatter.aidRunBackendLocalDateTime.string(from: plannedStart),
                plannedEndTime: DateFormatter.aidRunBackendLocalDateTime.string(from: plannedEnd),
                expectedDurationMinutes: 60,
                pacePreference: .moderate,
                routePreference: .parkTrail,
                routeNotes: nil,
                hasGuideDogThisRun: false,
                specialNotes: nil
            )
        )
        let orderId = try XCTUnwrap(createResponse.id)
        XCTAssertEqual(createResponse.status, .pendingMatch)

        let _: EmptyResponse = try await client.put(
            "/api/volunteer/dispatch-status",
            body: DispatchStatusRequest(wantsDispatch: true)
        )
        let _: EmptyResponse = try await client.post(
            "/api/orders/\(orderId)/respond",
            body: OrderRespondRequest(action: .accept)
        )
        var detail: OrderDetailResponse = try await client.get("/api/orders/\(orderId)")
        XCTAssertEqual(detail.status, .pendingAccept)

        let _: EmptyResponse = try await client.post("/api/orders/\(orderId)/en-route")
        let _: EmptyResponse = try await client.post("/api/orders/\(orderId)/arrived")
        detail = try await client.get("/api/orders/\(orderId)")
        XCTAssertEqual(detail.status, .driverArrived)

        let _: EmptyResponse = try await client.post("/api/orders/\(orderId)/start-service")
        let _: EmptyResponse = try await client.post("/api/orders/\(orderId)/finish")
        detail = try await client.get("/api/orders/\(orderId)")
        XCTAssertEqual(detail.status, .completed)

        let _: EmptyResponse = try await client.post(
            "/api/orders/\(orderId)/review",
            body: CreateReviewRequest(rating: 5, comment: "顺利完成")
        )
    }

    func testVolunteerRegistrationCloudAuthPathsUseCloudContract() async throws {
        // 前置状态必须自己安排，不要改回裸 `MockAPIClient()`：
        // Mock 的种子志愿者 `verificationStatus` 默认是 APPROVED（大量用例依赖「种子志愿者可接单」
        // 这一人设，改默认值会连锁打红一片），而后端 `VolunteerService.submitVerification`
        // （VolunteerService.java:314）在 APPROVED 时直接 400 拒绝重传，Mock 已逐条对齐。
        // 这条用例走的是「首次提交资质证书」路径，所以先把状态压回后端枚举的 NONE，
        // 否则测到的根本不是首次上传。
        // APPROVED 重传被拒的另一面由 `testMockRejectsReuploadAfterApprovalLikeBackend` 钉死。
        setenv("AIDRUN_MOCK_VOLUNTEER_VERIFICATION_STATUS", "NONE", 1)
        defer { unsetenv("AIDRUN_MOCK_VOLUNTEER_VERIFICATION_STATUS") }

        let client = MockAPIClient()

        let submittedVerification: VolunteerVerificationStatusResponse = try await client.upload(
            "/api/volunteer/verification",
            files: [MultipartFile(fieldName: "file", fileName: "cert.jpg", mimeType: "image/jpeg", data: Data([0xFF, 0xD8]))]
        )
        XCTAssertEqual(
            VolunteerCertificateStatus.parse(submittedVerification.status),
            .pending,
            "NONE 状态下首次上传资质证书必须成功并置 PENDING"
        )

        do {
            let _: EmptyResponse = try await client.upload(
                "/api/volunteer/registration/step2/id-card",
                fields: [
                    "idCardName": "测试志愿者",
                    "idCardNumber": "110101199001011234"
                ],
                files: []
            )
            XCTFail("旧身份证照片上传路径不应继续可用")
        } catch {
            // Expected: Step2 ID photo upload was removed from the main registration flow.
        }

        let _: EmptyResponse = try await client.post(
            "/api/volunteer/registration/step1",
            body: BasicInfoRequest(
                name: "测试志愿者",
                phone: "13800000002",
                idCardName: "测试志愿者",
                idCardNumber: "110101199001011234",
                runningExperience: nil,
                hasGuidedBefore: true,
                emergencyExperience: nil
            )
        )
        let initResponse: FaceVerifyInitResponse = try await client.post(
            "/api/volunteer/registration/step3/face-verify/init",
            body: FaceVerifyInitRequest(metaInfo: #"{"mock":true}"#)
        )
        XCTAssertEqual(initResponse.certifyId, "mock-certify-id")

        let result: FaceVerifyResponse = try await client.post(
            "/api/volunteer/registration/step3/face-verify/result",
            body: FaceVerifyResultRequest(certifyId: "mock-certify-id")
        )
        XCTAssertTrue(result.isPassed)

        let status: VolunteerRegistrationStatus = try await client.get("/api/volunteer/registration/status")
        let profile: VolunteerProfileResponse = try await client.get("/api/volunteer/profile")
        XCTAssertEqual(status.registrationStep, "STEP_4_COMPLETED")
        XCTAssertTrue(status.canAcceptOrders == true)
        XCTAssertTrue(status.isRegistrationComplete)
        XCTAssertEqual(profile.registrationStep, "STEP_4_COMPLETED")
        XCTAssertTrue(profile.canAcceptOrders == true)
        XCTAssertFalse(profile.isAvailable ?? true, "Registration completion must not automatically enable availability")

        do {
            let _: EmptyResponse = try await client.get("/api/volunteer/registration/training/courses")
            XCTFail("iOS Mock must not expose removed training routes")
        } catch {
            // Expected: training remains an external deprecated contract, not an iOS Mock route.
        }
    }

    func testVolunteerRegistrationBasicInfoRequestEncodesIdCardFields() throws {
        let request = BasicInfoRequest(
            name: "赵冉杰",
            phone: "18314551097",
            idCardName: "赵冉杰",
            idCardNumber: "110101199001011234",
            runningExperience: "3年跑步经验",
            hasGuidedBefore: true,
            emergencyExperience: nil
        )

        let data = try JSONEncoder().encode(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["idCardName"] as? String, "赵冉杰")
        XCTAssertEqual(object["idCardNumber"] as? String, "110101199001011234")
    }

    func testVolunteerRegistrationStep1UsesNameAsIdCardName() async {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let client = BasicInfoStatusAPIClient(
            status: VolunteerRegistrationStatus(currentStepCode: "STEP_3_FACE_VERIFY", step1Completed: true, idVerifyStatus: "APPROVED")
        )
        let viewModel = VolunteerRegistrationViewModel(apiClient: client)
        viewModel.configure(appState: appState, speechService: speechService)
        viewModel.name = "赵冉杰"
        viewModel.phone = "13800138000"
        viewModel.idCardName = "不应提交的旧姓名"
        viewModel.idCardNumber = "110101199001011234"

        await viewModel.submitBasicInfo()

        XCTAssertEqual(client.capturedRequest?.name, "赵冉杰")
        XCTAssertEqual(client.capturedRequest?.idCardName, "赵冉杰")
        XCTAssertEqual(client.capturedRequest?.idCardNumber, "110101199001011234")
    }

    func testVolunteerRegistrationStep1AcceptsGenericSuccessResponse() async {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let viewModel = VolunteerRegistrationViewModel()
        viewModel.configure(appState: appState, speechService: speechService)
        viewModel.name = "测试志愿者"
        viewModel.phone = "13800000002"
        viewModel.idCardName = "测试志愿者"
        viewModel.idCardNumber = "110101199001011234"

        await viewModel.submitBasicInfo()

        XCTAssertEqual(viewModel.currentStep, .faceVerify)
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(speechService.lastSpokenText, "身份核验通过，请开始活体认证")
    }

    func testVolunteerRegistrationBasicInfoShowsBlockedReasonForInvalidPhone() async {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let viewModel = VolunteerRegistrationViewModel()
        viewModel.configure(appState: appState, speechService: speechService)
        viewModel.name = "赵冉杰"
        viewModel.phone = "1831455097"
        viewModel.idCardName = "赵冉杰"
        viewModel.idCardNumber = "110101199001011234"

        XCTAssertFalse(viewModel.canSubmitBasicInfo)
        XCTAssertEqual(viewModel.basicInfoValidationMessage, "请输入 11 位中国大陆手机号")

        await viewModel.submitBasicInfo()

        XCTAssertEqual(viewModel.currentStep, .basicInfo)
        XCTAssertEqual(viewModel.errorMessage, "请输入 11 位中国大陆手机号")
        XCTAssertEqual(speechService.lastSpokenText, "请输入 11 位中国大陆手机号")
    }

    func testVolunteerRegistrationPhoneDirectAssignmentKeepsOnlyFirstElevenDigits() {
        let viewModel = VolunteerRegistrationViewModel()

        viewModel.phone = "13800138000999"

        XCTAssertEqual(viewModel.phone, "13800138000")
    }

    func testVolunteerRegistrationPhoneInputDropsNonDigits() {
        let viewModel = VolunteerRegistrationViewModel()

        viewModel.phone = "abc 138-0013-8000 xyz"

        XCTAssertEqual(viewModel.phone, "13800138000")
    }

    func testVolunteerRegistrationIdCardDirectAssignmentKeepsOnlyFirstEighteenCharacters() {
        let viewModel = VolunteerRegistrationViewModel()

        viewModel.idCardNumber = "1101011990010112345678"

        XCTAssertEqual(viewModel.idCardNumber, "110101199001011234")
    }

    func testVolunteerRegistrationIdCardAllowsLowercaseXCheckDigit() {
        let viewModel = VolunteerRegistrationViewModel()

        viewModel.name = "赵冉杰"
        viewModel.phone = "13800138000"
        viewModel.idCardName = "赵冉杰"
        viewModel.idCardNumber = "11010119900101123x"

        XCTAssertNil(viewModel.identityInfoValidationMessage)
        XCTAssertTrue(viewModel.canSubmitBasicInfo)
    }

    func testVolunteerRegistrationInvalidIdCardNumberBlocksStep1Submit() async {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let viewModel = VolunteerRegistrationViewModel()
        viewModel.configure(appState: appState, speechService: speechService)
        viewModel.name = "赵冉杰"
        viewModel.phone = "13800138000"
        viewModel.idCardName = "赵冉杰"
        viewModel.idCardNumber = "123"

        XCTAssertFalse(viewModel.canSubmitBasicInfo)
        XCTAssertEqual(viewModel.basicInfoValidationMessage, "请输入18位有效身份证号码")

        await viewModel.submitBasicInfo()

        XCTAssertEqual(viewModel.currentStep, .basicInfo)
        XCTAssertEqual(viewModel.errorMessage, "请输入18位有效身份证号码")
    }

    func testVolunteerRegistrationLoadStatusUnauthorizedExpiresSession() async {
        let appState = AppState()
        appState.currentEnvironment = .mock
        appState.accessToken = "expired-token"
        appState.userId = 12
        appState.activeRole = .volunteer
        let speechService = SpeechService()
        let viewModel = VolunteerRegistrationViewModel(apiClient: FailingAPIClient(error: APIError.unauthorized))
        viewModel.currentStep = .faceVerify
        viewModel.configure(appState: appState, speechService: speechService)

        await viewModel.loadStatus()

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNil(appState.accessToken)
        XCTAssertNil(appState.userId)
        XCTAssertNil(appState.activeRole)
        XCTAssertEqual(appState.consumeSessionExpirationMessage(), "登录已过期，请重新登录。")
    }

    func testVolunteerRegistrationStatusRoutesStringStepToFaceVerify() throws {
        let data = #"{"registrationStep":"STEP_3_FACE_VERIFY","step1Completed":true}"#
            .data(using: .utf8)!
        let status = try JSONDecoder().decode(VolunteerRegistrationStatus.self, from: data)
        let viewModel = VolunteerRegistrationViewModel()

        viewModel.applyRegistrationStatus(status)

        XCTAssertEqual(viewModel.currentStep, .faceVerify)
    }

    func testVolunteerRegistrationExposesOnlyTwoUserFacingSteps() {
        XCTAssertEqual(RegistrationStep.allCases.map(\.title), ["基本信息与身份核验", "活体认证"])
        XCTAssertEqual(RegistrationStep.allCases.map(\.displayIndex), [1, 2])
    }

    /// 回归门：走完注册但没过资质审核的志愿者，必须能离开注册流程去传证书。
    /// 后端 2026-07-31 起 `canAcceptOrders` = 资质审核结果（不再是注册完成度），
    /// 若这里退回用 `canAcceptOrders` 判完成，新注册志愿者会被锁死在注册流程里，
    /// 而证书上传入口在流程之外 —— `verified` 永远翻不了真，账号报废。
    func testRegistrationCompleteWhenRegistrationDoneButNotYetVerified() {
        let status = VolunteerRegistrationStatus(
            registrationStep: "STEP_3_FACE_VERIFY",
            registrationCompleted: true,
            canAcceptOrders: false,
            faceVerifyStatus: "APPROVED"
        )

        XCTAssertTrue(status.isRegistrationComplete)
    }

    /// 回归门：`STEP_3_FACE_VERIFY` 这个步骤位在「正在做活体」时也是它
    /// （后端 step1 二要素一过就置这个值），光看步骤位会把没做活体的人判成已完成。
    /// 他随后会被资质审核以「活体认证未通过」永久拒绝。
    func testRegistrationIncompleteWhenParkedAtFaceVerifyButLivenessNotDone() {
        let notStarted = VolunteerRegistrationStatus(
            registrationStep: "STEP_3_FACE_VERIFY",
            registrationCompleted: false,
            canAcceptOrders: false,
            faceVerifyStatus: "NOT_STARTED"
        )
        XCTAssertFalse(notStarted.isRegistrationComplete)

        // 旧服务端不返回 registrationCompleted，客户端必须自己按 faceVerifyStatus 推
        let legacyServer = VolunteerRegistrationStatus(
            registrationStep: "STEP_3_FACE_VERIFY",
            canAcceptOrders: true,          // 旧服务端这里恒为 true，正是不能信它的原因
            faceVerifyStatus: "NOT_STARTED"
        )
        XCTAssertFalse(legacyServer.isRegistrationComplete)

        let legacyServerPassed = VolunteerRegistrationStatus(
            registrationStep: "STEP_3_FACE_VERIFY",
            canAcceptOrders: true,
            faceVerifyStatus: "APPROVED"
        )
        XCTAssertTrue(legacyServerPassed.isRegistrationComplete)
    }

    func testVolunteerRegistrationLegacyTrainingStatusCompletesWithoutPolling() {
        let viewModel = VolunteerRegistrationViewModel()

        viewModel.applyRegistrationStatus(VolunteerRegistrationStatus(
            currentStepCode: "STEP_4_TRAINING",
            canAcceptOrders: false,
            step3Completed: true,
            faceVerifyStatus: "APPROVED"
        ))

        XCTAssertEqual(viewModel.currentStep, .faceVerify)
        XCTAssertFalse(viewModel.isAwaitingRegistrationCompletion)
        XCTAssertTrue(viewModel.isRegistrationCompleted)
        XCTAssertFalse(viewModel.shouldPollRegistrationStatus)
        XCTAssertFalse(viewModel.canStartFaceVerify)
    }

    func testVolunteerRegistrationCompletedStatusShowsBackendAuthoritativeCompletion() {
        let viewModel = VolunteerRegistrationViewModel()

        viewModel.applyRegistrationStatus(VolunteerRegistrationStatus(
            currentStepCode: "STEP_4_COMPLETED",
            canAcceptOrders: true,
            step3Completed: true
        ))

        XCTAssertTrue(viewModel.isRegistrationCompleted)
        XCTAssertFalse(viewModel.isAwaitingRegistrationCompletion)
        XCTAssertFalse(viewModel.shouldPollRegistrationStatus)
        XCTAssertFalse(viewModel.canStartFaceVerify)
    }

    func testVolunteerRegistrationStaleStatusKeepsFaceVerificationSyncingScreen() {
        let viewModel = VolunteerRegistrationViewModel()

        viewModel.applyRegistrationStatus(VolunteerRegistrationStatus(
            currentStepCode: "STEP_3_FACE_VERIFY",
            canAcceptOrders: false,
            step3Completed: true,
            faceVerifyStatus: "APPROVED"
        ))
        viewModel.applyRegistrationStatus(VolunteerRegistrationStatus(
            currentStepCode: "STEP_1_BASIC_INFO",
            canAcceptOrders: false,
            step1Completed: true
        ))

        XCTAssertEqual(viewModel.currentStep, .faceVerify)
        XCTAssertTrue(viewModel.isAwaitingRegistrationCompletion)
        XCTAssertTrue(viewModel.shouldPollRegistrationStatus)
        XCTAssertFalse(viewModel.canStartFaceVerify)

        viewModel.applyRegistrationStatus(VolunteerRegistrationStatus(
            currentStepCode: "STEP_4_COMPLETED",
            canAcceptOrders: true,
            step3Completed: true
        ))

        XCTAssertTrue(viewModel.isRegistrationCompleted)
        XCTAssertFalse(viewModel.isAwaitingRegistrationCompletion)
        XCTAssertFalse(viewModel.shouldPollRegistrationStatus)
    }

    func testVolunteerRegistrationLegacyStep2StatusRoutesBackToBasicInfo() throws {
        let data = #"{"registrationStep":"STEP_2_ID_UPLOAD","step1Completed":true,"idVerifyStatus":"PENDING"}"#
            .data(using: .utf8)!
        let status = try JSONDecoder().decode(VolunteerRegistrationStatus.self, from: data)
        let viewModel = VolunteerRegistrationViewModel()

        viewModel.applyRegistrationStatus(status)

        XCTAssertEqual(viewModel.currentStep, .basicInfo)
    }

    func testVolunteerRegistrationStatusDecodesNestedStepDetails() throws {
        let data = """
        {
          "currentStep": "STEP_2_ID_UPLOAD",
          "canAcceptOrders": false,
          "stepDetails": {
            "idVerifyStatus": "REJECTED",
            "faceVerifyStatus": "NONE",
            "totalTrainingMinutes": 0,
            "completedCoursesCount": 0,
            "currentCourseId": null,
            "idVerifyRejectionReason": "照片不清晰"
          }
        }
        """.data(using: .utf8)!

        let status = try JSONDecoder().decode(VolunteerRegistrationStatus.self, from: data)
        let viewModel = VolunteerRegistrationViewModel()
        viewModel.applyRegistrationStatus(status)

        XCTAssertEqual(status.currentStepCode, "STEP_2_ID_UPLOAD")
        XCTAssertEqual(status.idVerifyStatus, "REJECTED")
        XCTAssertEqual(status.stepDetails?.idVerifyRejectionReason, "照片不清晰")
        XCTAssertFalse(status.isRegistrationComplete)
        XCTAssertEqual(viewModel.currentStep, .basicInfo)
    }

    func testVolunteerRegistrationStep1TwoFactorFailureStaysOnBasicInfo() async {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let client = BasicInfoFailingAPIClient(
            error: APIError.serverError(ErrorResponse(code: "ID_CARD_CHECK_FAILED", message: "身份证二要素核验未通过，请更新身份证信息"))
        )
        let viewModel = VolunteerRegistrationViewModel(apiClient: client)
        viewModel.configure(appState: appState, speechService: speechService)
        viewModel.name = "赵冉杰"
        viewModel.phone = "13800138000"
        viewModel.idCardName = "赵冉杰"
        viewModel.idCardNumber = "110101199001011234"

        await viewModel.submitBasicInfo()

        XCTAssertEqual(viewModel.currentStep, .basicInfo)
        XCTAssertEqual(viewModel.errorMessage, "身份证二要素核验未通过，请更新身份证信息")
        XCTAssertEqual(speechService.lastSpokenText, "身份证二要素核验未通过，请更新身份证信息")
    }

    func testVolunteerRegistrationStep1SuccessRefreshesToFaceVerifyStatus() async {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let client = BasicInfoStatusAPIClient(
            status: VolunteerRegistrationStatus(currentStepCode: "STEP_3_FACE_VERIFY", step1Completed: true, idVerifyStatus: "APPROVED")
        )
        let viewModel = VolunteerRegistrationViewModel(apiClient: client)
        viewModel.configure(appState: appState, speechService: speechService)
        viewModel.name = "赵冉杰"
        viewModel.phone = "13800138000"
        viewModel.idCardName = "赵冉杰"
        viewModel.idCardNumber = "110101199001011234"

        await viewModel.submitBasicInfo()

        XCTAssertEqual(client.submitCount, 1)
        XCTAssertEqual(client.statusRefreshCount, 1)
        XCTAssertEqual(viewModel.currentStep, .faceVerify)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(speechService.lastSpokenText, "身份核验通过，请开始活体认证")
    }

    func testVolunteerFaceVerifyInitPostsMetaInfoAndStartsNativeSDK() async {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let verifier = CloudAuthVerifierSpy(outcome: .cancelled)
        let client = FaceVerifyFlowAPIClient(
            initResponse: FaceVerifyInitResponse(
                certifyId: "cert-1",
                status: "PENDING",
                message: "请完成活体认证"
            ),
            resultResponses: []
        )
        let viewModel = VolunteerRegistrationViewModel(
            apiClient: client,
            metaInfoProvider: FixedCloudAuthMetaInfoProvider(metaInfo: #"{"device":"test"}"#),
            cloudAuthVerifier: verifier
        )
        viewModel.configure(appState: appState, speechService: speechService)
        viewModel.applyRegistrationStatus(VolunteerRegistrationStatus(currentStepCode: "STEP_3_FACE_VERIFY", step1Completed: true))

        await viewModel.startFaceVerify()

        XCTAssertEqual(client.initCount, 1)
        XCTAssertEqual(client.capturedMetaInfo, #"{"device":"test"}"#)
        XCTAssertEqual(verifier.receivedCertifyIds, ["cert-1"])
        XCTAssertEqual(verifier.receivedEnvironments, [.mock])
        XCTAssertNil(viewModel.activeCertifyId)
        XCTAssertEqual(viewModel.errorMessage, "已取消活体认证，可重新开始")
        XCTAssertTrue(viewModel.canStartFaceVerify)
        XCTAssertEqual(client.resultCount, 0)
    }

    func testCloudAuthMetaInfoSerializerEncodesAliyunDictionary() throws {
        let metaInfo: [AnyHashable: Any] = [
            "apdidToken": "token-123",
            "sdkVersion": "2.3.50",
            "device": [
                "platform": "ios",
                "features": ["camera", "liveness"]
            ]
        ]

        let json = try DefaultCloudAuthMetaInfoProvider.serializedMetaInfo(from: metaInfo)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let device = try XCTUnwrap(object["device"] as? [String: Any])
        let features = try XCTUnwrap(device["features"] as? [String])

        XCTAssertEqual(object["apdidToken"] as? String, "token-123")
        XCTAssertEqual(object["sdkVersion"] as? String, "2.3.50")
        XCTAssertEqual(device["platform"] as? String, "ios")
        XCTAssertEqual(features, ["camera", "liveness"])
    }

    func testCloudAuthRequiredResourcesAreBundled() throws {
        let requiredBundles = [
            "APBToygerFacade",
            "APBToygerFacadeSuitable",
            "BioAuthEngine",
            "ToygerService"
        ]

        for bundleName in requiredBundles {
            XCTAssertNotNil(
                Bundle.main.url(forResource: bundleName, withExtension: "bundle"),
                "Missing required CloudAuth resource bundle: \(bundleName).bundle"
            )
        }

        let toygerBundleURL = try XCTUnwrap(
            Bundle.main.url(forResource: "ToygerService", withExtension: "bundle")
        )
        let modelURL = toygerBundleURL.appendingPathComponent("toyger.face.dat")
        let attributes = try FileManager.default.attributesOfItem(atPath: modelURL.path)
        let modelSize = try XCTUnwrap(attributes[.size] as? NSNumber)

        XCTAssertGreaterThan(modelSize.intValue, 0, "CloudAuth face model must not be empty")
    }

    func testCloudAuthUnusedOptionalModulesAreExcluded() {
#if canImport(OCRDetectSDKForTech)
        XCTFail("OCR CloudAuth module must remain excluded from the ID_PRO-only target")
#endif
#if canImport(DTFNFCIdentityManager)
        XCTFail("NFC CloudAuth module must remain excluded from the ID_PRO-only target")
#endif
#if canImport(MultiFactorFacade)
        XCTFail("MultiFactor CloudAuth module must remain excluded from the ID_PRO-only target")
#endif
#if canImport(DTFBeauty)
        XCTFail("Beauty CloudAuth module must remain excluded from the ID_PRO-only target")
#endif
    }

    func testCloudAuthMetaInfoSerializerRejectsEmptyDictionary() {
        XCTAssertThrowsError(try DefaultCloudAuthMetaInfoProvider.serializedMetaInfo(from: [:])) { error in
            guard let metaInfoError = error as? CloudAuthMetaInfoError else {
                return XCTFail("Expected CloudAuthMetaInfoError")
            }
            XCTAssertEqual(metaInfoError.localizedDescription, "活体认证 SDK 初始化失败，请重试")
        }
    }

    func testDefaultCloudAuthVerifierMapsSDKCompletionCodes() {
        XCTAssertEqual(DefaultCloudAuthVerifier.outcome(forSDKCode: 1000), .submitted)
        XCTAssertEqual(DefaultCloudAuthVerifier.outcome(forSDKCode: 2006), .submitted)
        XCTAssertEqual(DefaultCloudAuthVerifier.outcome(forSDKCode: 1003), .cancelled)
        XCTAssertEqual(failureKind(for: DefaultCloudAuthVerifier.outcome(forSDKCode: 1001)), .internalError)
        XCTAssertEqual(failureKind(for: DefaultCloudAuthVerifier.outcome(forSDKCode: 2002)), .networkError)
        XCTAssertEqual(failureKind(for: DefaultCloudAuthVerifier.outcome(forSDKCode: 2003)), .deviceTimeError)
        XCTAssertEqual(failureKind(for: DefaultCloudAuthVerifier.outcome(forSDKCode: 9999)), .unknown(code: 9999))
    }

    func testCloudAuthDiagnosticsKeepOnlyBoundedTechnicalFields() {
        let diagnostics = CloudAuthSDKDiagnostics(
            code: 1001,
            retCode: 1001,
            retCodeSub: " z1014 ",
            retMessageSub: "raw-message-must-not-be-logged",
            sdkVersion: "2.3.50"
        )

        XCTAssertEqual(diagnostics.retCodeSub, "Z1014")
        XCTAssertTrue(diagnostics.retMessageSubPresent)
        XCTAssertEqual(diagnostics.retMessageSubLength, 30)
        XCTAssertEqual(diagnostics.sdkVersion, "2.3.50")
        XCTAssertTrue(diagnostics.debugSummary.contains("retCodeSub=Z1014"))
        XCTAssertTrue(diagnostics.debugSummary.contains("retMessageSubLength=30"))
        XCTAssertFalse(diagnostics.debugSummary.contains("raw-message"))
    }

    func testCloudAuthDiagnosticsRejectUnsafeSubcodeAndVersion() {
        let diagnostics = CloudAuthSDKDiagnostics(
            code: 1001,
            retCode: 1001,
            retCodeSub: "Z1014 certify-secret",
            retMessageSub: nil,
            sdkVersion: "2.3.50 secret"
        )

        XCTAssertNil(diagnostics.retCodeSub)
        XCTAssertNil(diagnostics.sdkVersion)
        XCTAssertFalse(diagnostics.retMessageSubPresent)
        XCTAssertEqual(diagnostics.retMessageSubLength, 0)
        XCTAssertFalse(diagnostics.debugSummary.contains("secret"))
    }

    func testDefaultCloudAuthVerifierMapsDetailedSubcodes() {
        let mappings: [(String, CloudAuthVerificationFailure.Kind)] = [
            ("Z1014", .internalError),
            ("Z1023", .internalError),
            ("I4001", .moduleIntegration),
            ("Z1010", .businessParameter),
            ("Z1037", .businessParameter),
            ("Z1001", .cameraUnavailable),
            ("Z1002", .cameraUnavailable),
            ("Z1020", .cameraUnavailable),
            ("Z1024", .duplicateFlow)
        ]

        for (subcode, expectedKind) in mappings {
            let diagnostics = CloudAuthSDKDiagnostics(
                code: 1001,
                retCode: 1001,
                retCodeSub: subcode,
                retMessageSub: "not retained",
                sdkVersion: "2.3.50"
            )
            let outcome = DefaultCloudAuthVerifier.outcome(for: diagnostics)
            XCTAssertEqual(failureKind(for: outcome), expectedKind, "Unexpected mapping for \(subcode)")
        }
    }

    func testDefaultCloudAuthVerifierTopLevelCodesTakePrecedenceOverDiagnosticSubcodes() {
        func outcome(code: Int) -> CloudAuthVerificationOutcome {
            DefaultCloudAuthVerifier.outcome(for: CloudAuthSDKDiagnostics(
                code: code,
                retCode: code,
                retCodeSub: "Z1014",
                retMessageSub: "not retained",
                sdkVersion: "2.3.50"
            ))
        }

        XCTAssertEqual(outcome(code: 1000), .submitted)
        XCTAssertEqual(outcome(code: 2006), .submitted)
        XCTAssertEqual(outcome(code: 1003), .cancelled)
        XCTAssertEqual(failureKind(for: outcome(code: 2002)), .networkError)
        XCTAssertEqual(failureKind(for: outcome(code: 2003)), .deviceTimeError)
    }

    func testCloudAuthSDKRuntimeInitializesOnlyOnce() {
        var initializeCalls = 0
        var versionCalls = 0
        let runtime = CloudAuthSDKRuntime(
            initializeSDK: { initializeCalls += 1 },
            versionProvider: {
                versionCalls += 1
                return "2.3.50"
            }
        )

        XCTAssertNil(runtime.sdkVersion)
        runtime.initializeIfNeeded()
        runtime.initializeIfNeeded()

        XCTAssertEqual(initializeCalls, 1)
        XCTAssertEqual(runtime.initializationCount, 1)
        XCTAssertEqual(runtime.sdkVersion, "2.3.50")
        XCTAssertEqual(versionCalls, 1)
    }

    func testCloudAuthOneShotGateAcceptsOnlyFirstCallback() {
        let gate = CloudAuthOneShotGate()

        XCTAssertTrue(gate.claim())
        XCTAssertFalse(gate.claim())
    }

    func testVolunteerFaceVerifyMissingCertifyIdDoesNotStartNativeSDK() async {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let verifier = CloudAuthVerifierSpy(outcome: .submitted)
        let client = FaceVerifyFlowAPIClient(
            initResponse: FaceVerifyInitResponse(certifyId: nil, status: "PENDING", message: nil),
            resultResponses: []
        )
        let viewModel = VolunteerRegistrationViewModel(
            apiClient: client,
            metaInfoProvider: FixedCloudAuthMetaInfoProvider(metaInfo: #"{"device":"test"}"#),
            cloudAuthVerifier: verifier
        )
        viewModel.configure(appState: appState, speechService: SpeechService())
        viewModel.applyRegistrationStatus(VolunteerRegistrationStatus(currentStepCode: "STEP_3_FACE_VERIFY", step1Completed: true))

        await viewModel.startFaceVerify()

        XCTAssertTrue(verifier.receivedCertifyIds.isEmpty)
        XCTAssertEqual(client.resultCount, 0)
        XCTAssertEqual(viewModel.errorMessage, "活体认证服务返回不完整，请稍后重试")
    }

    func testVolunteerFaceVerifyInitErrorDoesNotPollOrEnterTraining() async {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let client = FaceVerifyFlowAPIClient(
            initResponse: FaceVerifyInitResponse(certifyId: nil, status: "ERROR", message: "发起失败"),
            resultResponses: []
        )
        let viewModel = VolunteerRegistrationViewModel(
            apiClient: client,
            metaInfoProvider: FixedCloudAuthMetaInfoProvider(metaInfo: #"{"device":"test"}"#)
        )
        viewModel.configure(appState: appState, speechService: speechService)
        viewModel.applyRegistrationStatus(VolunteerRegistrationStatus(currentStepCode: "STEP_3_FACE_VERIFY", step1Completed: true))

        await viewModel.startFaceVerify()

        XCTAssertEqual(viewModel.currentStep, .faceVerify)
        XCTAssertNil(viewModel.activeCertifyId)
        XCTAssertEqual(client.resultCount, 0)
        XCTAssertEqual(viewModel.errorMessage, "发起失败")
    }

    func testVolunteerFaceVerifyIdentityErrorAllowsReturnToBasicInfoEdit() async {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let client = FaceVerifyFlowAPIClient(
            initResponse: FaceVerifyInitResponse(certifyId: nil, status: "ERROR", message: nil),
            initError: APIError.serverError(ErrorResponse(code: "ID_INFO_INVALID", message: "身份信息格式不正确")),
            resultResponses: [],
            status: VolunteerRegistrationStatus(currentStepCode: "STEP_3_FACE_VERIFY", step1Completed: true)
        )
        let viewModel = VolunteerRegistrationViewModel(
            apiClient: client,
            metaInfoProvider: FixedCloudAuthMetaInfoProvider(metaInfo: #"{"device":"test"}"#)
        )
        viewModel.configure(appState: appState, speechService: speechService)
        viewModel.applyRegistrationStatus(VolunteerRegistrationStatus(currentStepCode: "STEP_3_FACE_VERIFY", step1Completed: true))

        await viewModel.startFaceVerify()

        XCTAssertEqual(client.statusRefreshCount, 1)
        XCTAssertEqual(viewModel.currentStep, .faceVerify)
        XCTAssertNil(viewModel.activeCertifyId)
        XCTAssertTrue(viewModel.canReturnToBasicInfoForIdentityEdit)
        // `ID_INFO_INVALID` 现在能解析成 `ErrorCode`，因此展示的是本地稳定文案而不是回显后端
        // message —— 实名接口的 message 可能把提交的身份证信息带回来，绝不能展示或朗读。
        XCTAssertEqual(viewModel.errorMessage, ErrorCode.idInfoInvalid.localizedMessage)

        viewModel.returnToBasicInfoForIdentityEdit()

        XCTAssertEqual(viewModel.currentStep, .basicInfo)
        XCTAssertFalse(viewModel.canReturnToBasicInfoForIdentityEdit)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testVolunteerFaceVerifyPendingResultKeepsWaiting() async {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let client = FaceVerifyFlowAPIClient(
            initResponse: FaceVerifyInitResponse(certifyId: "cert-1", status: "PENDING", message: nil),
            resultResponses: [FaceVerifyResponse(passed: false, status: "PENDING", message: "结果处理中")]
        )
        let viewModel = VolunteerRegistrationViewModel(
            apiClient: client,
            metaInfoProvider: FixedCloudAuthMetaInfoProvider(metaInfo: #"{"device":"test"}"#)
        )
        viewModel.configure(appState: appState, speechService: speechService)
        viewModel.applyRegistrationStatus(VolunteerRegistrationStatus(currentStepCode: "STEP_3_FACE_VERIFY", step1Completed: true))

        viewModel.activeCertifyId = "cert-1"
        let finished = await viewModel.pollFaceVerifyResultOnce()

        XCTAssertFalse(finished)
        XCTAssertEqual(viewModel.currentStep, .faceVerify)
        XCTAssertEqual(viewModel.activeCertifyId, "cert-1")
        XCTAssertEqual(viewModel.faceVerifyMessage, "结果处理中")
    }

    func testVolunteerFaceVerifyRejectedResultAllowsRetry() async {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let client = FaceVerifyFlowAPIClient(
            initResponse: FaceVerifyInitResponse(certifyId: "cert-1", status: "PENDING", message: nil),
            resultResponses: [FaceVerifyResponse(passed: false, status: "REJECTED", message: "认证未通过")]
        )
        let viewModel = VolunteerRegistrationViewModel(
            apiClient: client,
            metaInfoProvider: FixedCloudAuthMetaInfoProvider(metaInfo: #"{"device":"test"}"#)
        )
        viewModel.configure(appState: appState, speechService: speechService)
        viewModel.applyRegistrationStatus(VolunteerRegistrationStatus(currentStepCode: "STEP_3_FACE_VERIFY", step1Completed: true))

        viewModel.activeCertifyId = "cert-1"
        let finished = await viewModel.pollFaceVerifyResultOnce()

        XCTAssertTrue(finished)
        XCTAssertEqual(viewModel.currentStep, .faceVerify)
        XCTAssertNil(viewModel.activeCertifyId)
        XCTAssertTrue(viewModel.canStartFaceVerify)
        XCTAssertEqual(viewModel.errorMessage, "认证未通过")
    }

    func testVolunteerFaceVerifySubmittedSDKPollsApprovedResultAndCompletesRegistration() async {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let verifier = CloudAuthVerifierSpy(outcome: .submitted)
        let client = FaceVerifyFlowAPIClient(
            initResponse: FaceVerifyInitResponse(certifyId: "cert-1", status: "PENDING", message: nil),
            resultResponses: [FaceVerifyResponse(passed: true, status: "APPROVED", message: "认证通过")],
            status: VolunteerRegistrationStatus(
                currentStepCode: "STEP_4_COMPLETED",
                canAcceptOrders: true,
                step1Completed: true,
                step3Completed: true
            )
        )
        let viewModel = VolunteerRegistrationViewModel(
            apiClient: client,
            metaInfoProvider: FixedCloudAuthMetaInfoProvider(metaInfo: #"{"device":"test"}"#),
            cloudAuthVerifier: verifier
        )
        viewModel.configure(appState: appState, speechService: speechService)
        viewModel.applyRegistrationStatus(VolunteerRegistrationStatus(currentStepCode: "STEP_3_FACE_VERIFY", step1Completed: true))

        await viewModel.startFaceVerify()

        XCTAssertEqual(verifier.receivedCertifyIds, ["cert-1"])
        XCTAssertEqual(client.resultCount, 1)
        XCTAssertEqual(viewModel.currentStep, .faceVerify)
        XCTAssertNil(viewModel.activeCertifyId)
        XCTAssertTrue(viewModel.isRegistrationCompleted)
        XCTAssertFalse(viewModel.isAwaitingRegistrationCompletion)
        XCTAssertEqual(client.statusRefreshCount, 1)
        XCTAssertFalse(client.requestedPaths.contains { $0.contains("/training/") })
        XCTAssertEqual(speechService.lastSpokenText, "注册完成，请返回首页开启可服务状态")
    }

    func testVolunteerFaceVerifyApprovedResultAcceptsLegacyTrainingCompletion() async {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let client = FaceVerifyFlowAPIClient(
            initResponse: FaceVerifyInitResponse(certifyId: "cert-1", status: "PENDING", message: nil),
            resultResponses: [FaceVerifyResponse(passed: true, status: "APPROVED", message: "认证通过")],
            status: VolunteerRegistrationStatus(currentStepCode: "STEP_4_TRAINING", canAcceptOrders: false, step3Completed: true)
        )
        let viewModel = VolunteerRegistrationViewModel(
            apiClient: client,
            metaInfoProvider: FixedCloudAuthMetaInfoProvider(metaInfo: #"{"device":"test"}"#),
            cloudAuthVerifier: CloudAuthVerifierSpy(outcome: .submitted)
        )
        viewModel.configure(appState: appState, speechService: SpeechService())
        viewModel.applyRegistrationStatus(VolunteerRegistrationStatus(currentStepCode: "STEP_3_FACE_VERIFY", step1Completed: true))

        await viewModel.startFaceVerify()

        XCTAssertFalse(viewModel.isAwaitingRegistrationCompletion)
        XCTAssertTrue(viewModel.isRegistrationCompleted)
        XCTAssertFalse(viewModel.shouldPollRegistrationStatus)
        XCTAssertFalse(viewModel.canStartFaceVerify)
        XCTAssertNil(viewModel.faceVerifyMessage)
        XCTAssertFalse(client.requestedPaths.contains { $0.contains("/training/") })

        // 完成态刻意不在此刻发布：一旦 AppState 认定注册完成，ContentView 的根路由会重跑并切到
        // 志愿者首页，把注册流连同「注册完成」页一起拆掉，用户只听到 TTS 却看不到确认页。
        // 未完成的中间态照常发布，AppState 这时停在进流程前的 STEP_3_FACE_VERIFY。
        XCTAssertFalse(
            appState.volunteerRegistrationStatus?.isRegistrationComplete == true,
            "注册完成态不能在用户还停留在注册流时就推给 AppState"
        )

        // 用户点「返回志愿者首页」时才发布，根路由这时切走才是对的。
        viewModel.prepareReturnToVolunteerHome()
        XCTAssertTrue(appState.volunteerRegistrationStatus?.isRegistrationComplete == true)
    }

    func testVolunteerFaceVerifySDKFailureClearsCertifyIdAndAllowsRetry() async {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let client = FaceVerifyFlowAPIClient(
            initResponse: FaceVerifyInitResponse(certifyId: "cert-1", status: "PENDING", message: nil),
            resultResponses: []
        )
        let viewModel = VolunteerRegistrationViewModel(
            apiClient: client,
            metaInfoProvider: FixedCloudAuthMetaInfoProvider(metaInfo: #"{"device":"test"}"#),
            cloudAuthVerifier: CloudAuthVerifierSpy(outcome: .failed(.networkError))
        )
        viewModel.configure(appState: appState, speechService: SpeechService())
        viewModel.applyRegistrationStatus(VolunteerRegistrationStatus(currentStepCode: "STEP_3_FACE_VERIFY", step1Completed: true))

        await viewModel.startFaceVerify()

        XCTAssertNil(viewModel.activeCertifyId)
        XCTAssertTrue(viewModel.canStartFaceVerify)
        XCTAssertEqual(client.resultCount, 0)
        XCTAssertEqual(viewModel.errorMessage, "活体认证网络连接失败，请检查网络后重试")
    }

    func testVolunteerFaceVerifyBusinessParameterSubcodeIsSafeAndRetryable() async {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let diagnostics = CloudAuthSDKDiagnostics(
            code: 1001,
            retCode: 1001,
            retCodeSub: "Z1010",
            retMessageSub: "certifyId must never be shown",
            sdkVersion: "2.3.50"
        )
        let failure = CloudAuthVerificationFailure(kind: .businessParameter, diagnostics: diagnostics)
        let client = FaceVerifyFlowAPIClient(
            initResponse: FaceVerifyInitResponse(certifyId: "cert-1", status: "PENDING", message: nil),
            resultResponses: []
        )
        let viewModel = VolunteerRegistrationViewModel(
            apiClient: client,
            metaInfoProvider: FixedCloudAuthMetaInfoProvider(metaInfo: #"{"device":"test"}"#),
            cloudAuthVerifier: CloudAuthVerifierSpy(outcome: .failed(failure))
        )
        viewModel.configure(appState: appState, speechService: SpeechService())
        viewModel.applyRegistrationStatus(VolunteerRegistrationStatus(currentStepCode: "STEP_3_FACE_VERIFY", step1Completed: true))

        await viewModel.startFaceVerify()

        XCTAssertNil(viewModel.activeCertifyId)
        XCTAssertTrue(viewModel.canStartFaceVerify)
        XCTAssertEqual(client.resultCount, 0)
        XCTAssertEqual(viewModel.errorMessage, "活体认证参数或流程配置异常，请重新发起认证（错误码 Z1010）")
        XCTAssertFalse(viewModel.errorMessage?.contains("certifyId") == true)
    }

    func testVolunteerRegistrationRefreshesStatusWhenBasicInfoAlreadyCompleted() async throws {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let _: EmptyResponse = try await appState.apiClient.post(
            "/api/volunteer/registration/step1",
            body: BasicInfoRequest(
                name: "赵冉杰",
                phone: "13800138000",
                idCardName: "赵冉杰",
                idCardNumber: "110101199001011234",
                runningExperience: nil,
                hasGuidedBefore: true,
                emergencyExperience: nil
            )
        )
        let viewModel = VolunteerRegistrationViewModel()
        viewModel.configure(appState: appState, speechService: speechService)
        viewModel.name = "赵冉杰"
        viewModel.phone = "18314555097"
        viewModel.idCardName = "赵冉杰"
        viewModel.idCardNumber = "110101199001011234"

        await viewModel.submitBasicInfo()

        XCTAssertEqual(viewModel.currentStep, .faceVerify)
        XCTAssertEqual(viewModel.errorMessage, "已同步注册进度，请继续完成活体认证")
        XCTAssertEqual(speechService.lastSpokenText, "已同步注册进度，请继续完成活体认证")
    }

    func testVolunteerFaceCameraPermissionUsageDescriptionIsConfigured() throws {
        let cameraUsageDescription = try XCTUnwrap(
            Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") as? String
        )

        XCTAssertFalse(cameraUsageDescription.trimmed.isEmpty)
    }

    func testVolunteerCertificationEntryDoesNotRequireSeparateNicknameSubmit() {
        let appState = AppState()
        appState.currentEnvironment = .demoCloud
        appState.updateVolunteerProfile(makeVolunteerProfile(name: "", verificationStatus: "not_submitted"))
        let viewModel = VolunteerProfileViewModel()

        viewModel.configure(with: appState, speechService: SpeechService())

        XCTAssertEqual(viewModel.certificationButtonTitle, "开始认证")
        XCTAssertEqual(viewModel.certificationAccessibilityHint, "点击后进入志愿者注册认证流程")
        XCTAssertFalse(viewModel.canSubmit)
    }

    // `testMaintainedDocsDoNotUseForbiddenLowercaseOrderStatusVocabulary` 已删除：
    // 它读仓库里的 .md 文件，真机测试包沙盒读不到必然 XCTSkip，而真机是本仓唯一可用的
    // XCTest 通道，所以它一次都没跑过；同一份 forbiddenFragments 清单在
    // `scripts/validate-docs.mjs` 里有可运行的等价实现（AGENTS.md §13 的必跑命令），
    // 且那份的文档清单更新（不含 2026-07-28 已归档的 07-api-contract / websocket-protocol）。

    func testLoginResponseDecodesCorrectly() throws {
        let json = """
        {
          "token": "eyJhbGciOiJIUzI1NiJ9.test",
          "userId": 1,
          "role": "BLIND"
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(LoginResponse.self, from: json)

        XCTAssertEqual(response.token, "eyJhbGciOiJIUzI1NiJ9.test")
        XCTAssertEqual(response.userId, 1)
        XCTAssertEqual(response.role, "BLIND")
    }

    func testLoginRoleResolverTreatsUnsetAndMissingRoleAsRoleSelection() {
        XCTAssertNil(AppState.resolvedLoginRole(from: nil))
        XCTAssertNil(AppState.resolvedLoginRole(from: "UNSET"))
        XCTAssertNil(AppState.resolvedLoginRole(from: "UNKNOWN"))
        XCTAssertEqual(AppState.resolvedLoginRole(from: "BLIND"), .blind)
        XCTAssertEqual(AppState.resolvedLoginRole(from: "VOLUNTEER"), .volunteer)
    }

    func testLoginSuccessClearsStaleRoleWhenBackendReturnsNoRole() {
        let appState = AppState()
        appState.currentEnvironment = .mock
        appState.activeRole = .volunteer

        appState.handleLoginSuccess(
            response: LoginResponse(
                token: "token",
                userId: 12,
                role: nil
            )
        )

        XCTAssertEqual(appState.accessToken, "token")
        XCTAssertEqual(appState.userId, 12)
        XCTAssertNil(appState.activeRole)
    }

    func testLoginSuccessClearsUnsetRoleToAvoidBlankRootRoute() {
        let appState = AppState()
        appState.currentEnvironment = .mock

        appState.handleLoginSuccess(
            response: LoginResponse(
                token: "token",
                userId: 12,
                role: "UNSET"
            )
        )

        XCTAssertNil(appState.activeRole)
    }

    func testContentRootRouterCommitsOneBlindDestinationAfterAtomicHydration() async {
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        defer { persistence.reset() }
        let client = RootHydrationAPIClient()
        let appState = AppState(apiClient: client, persistence: persistence)
        appState.currentEnvironment = .mock
        appState.handleLoginSuccess(response: LoginResponse(token: "token-1", userId: 1, role: "BLIND"))
        let router = ContentRootRouter()

        router.synchronize(with: appState)

        XCTAssertEqual(router.route, .restoringAccount)
        let didRoute = await waitUntil { router.route == .blindHome }
        XCTAssertTrue(didRoute)
        XCTAssertEqual(appState.blindProfile?.name, "账号1")
        XCTAssertEqual(appState.emergencyContacts.count, 1)
    }

    func testContentRootRouterCancelsOldAccountHydrationBeforeCommit() async {
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        defer { persistence.reset() }
        let client = RootHydrationAPIClient(firstRequestDelay: 1)
        let appState = AppState(apiClient: client, persistence: persistence)
        appState.currentEnvironment = .mock
        let router = ContentRootRouter()

        appState.handleLoginSuccess(response: LoginResponse(token: "old-token", userId: 1, role: "BLIND"))
        router.synchronize(with: appState)
        try? await Task.sleep(nanoseconds: 50_000_000)
        appState.handleLoginSuccess(response: LoginResponse(token: "new-token", userId: 2, role: "BLIND"))
        router.synchronize(with: appState)

        let didRoute = await waitUntil { router.route == .blindHome }
        XCTAssertTrue(didRoute)
        XCTAssertEqual(appState.userId, 2)
        XCTAssertEqual(appState.blindProfile?.name, "账号2")
        XCTAssertGreaterThanOrEqual(client.cancellationCount, 1)
    }

    func testExpireSessionClearsStateAndProvidesOneTimeLoginMessage() {
        let appState = AppState()
        appState.currentEnvironment = .mock
        appState.accessToken = "expired-token"
        appState.userId = 12
        appState.activeRole = .volunteer
        appState.updateVolunteerProfile(makeApprovedVolunteerProfile())

        appState.expireSession()

        XCTAssertNil(appState.accessToken)
        XCTAssertNil(appState.userId)
        XCTAssertNil(appState.activeRole)
        XCTAssertNil(appState.volunteerProfile)
        XCTAssertEqual(appState.consumeSessionExpirationMessage(), "登录已过期，请重新登录。")
        XCTAssertNil(appState.consumeSessionExpirationMessage())
    }

    func testSessionRestoreHydratesSelectedRole() async {
        let persistence = prepareStoredSession(token: "selected-token", role: .blind, userId: 99)
        let client = AuthLifecycleAPIClient(meResult: .success(CurrentUserResponse(userId: 99, phone: nil, role: "BLIND")))
        let appState = AppState(apiClient: client, persistence: persistence)

        await appState.restoreSession()

        XCTAssertEqual(appState.sessionRestorationState, .authenticated)
        XCTAssertEqual(appState.currentUser?.userId, 99)
        XCTAssertEqual(appState.activeRole, .blind)
        persistence.reset()
    }

    func testSessionRestoreKeepsRolelessSessionWithoutWebSocket() async {
        let persistence = prepareStoredSession(token: "roleless-token", role: nil, userId: 100)
        let client = AuthLifecycleAPIClient(meResult: .success(CurrentUserResponse(userId: 100, phone: nil, role: "UNSET")))
        let appState = AppState(apiClient: client, persistence: persistence)

        await appState.restoreSession()

        XCTAssertEqual(appState.sessionRestorationState, .choosingRole)
        XCTAssertEqual(appState.userId, 100)
        XCTAssertNil(appState.activeRole)
        XCTAssertNil(appState.webSocketService)
        persistence.reset()
    }

    func testSessionRestoreRejectsMalformedRole() async {
        let persistence = prepareStoredSession(token: "malformed-role-token", role: .blind, userId: 102)
        let client = AuthLifecycleAPIClient(
            meResult: .success(CurrentUserResponse(userId: 102, phone: nil, role: "ADMIN"))
        )
        let appState = AppState(apiClient: client, persistence: persistence)

        await appState.restoreSession()

        XCTAssertEqual(appState.sessionRestorationState, .unauthenticated)
        XCTAssertNil(appState.accessToken)
        XCTAssertNil(appState.currentUser)
        XCTAssertEqual(appState.consumeSessionExpirationMessage(), "登录角色信息异常，请重新登录。")
        persistence.reset()
    }

    func testRevokedSessionRestoreClearsCredentialsAndMetadata() async {
        let persistence = prepareStoredSession(token: "revoked-token", role: .volunteer, userId: 101)
        persistence.set("event-101", forKey: AppConstants.UserDefaultsKeys.emergencyRecoveryMetadata)
        let client = AuthLifecycleAPIClient(meResult: .failure(.unauthorized))
        let appState = AppState(apiClient: client, persistence: persistence)

        await appState.restoreSession()

        XCTAssertEqual(appState.sessionRestorationState, .unauthenticated)
        XCTAssertNil(appState.accessToken)
        XCTAssertNil(persistence.object(forKey: AppConstants.UserDefaultsKeys.emergencyRecoveryMetadata))
        persistence.reset()
    }

    func testLogoutSuccessAndUnauthorizedBothCleanSession() async {
        for result in [
            Result<LogoutResponse, APIError>.success(LogoutResponse(success: true, message: nil)),
            .failure(.unauthorized)
        ] {
            let persistence = AppStatePersistenceFactory.makeIsolatedTest()
            defer { persistence.reset() }
            let client = AuthLifecycleAPIClient(logoutResult: result)
            let appState = AppState(apiClient: client, persistence: persistence)
            appState.handleLoginSuccess(response: LoginResponse(token: "token", userId: 7, role: "BLIND"))
            await appState.logout()
            XCTAssertFalse(appState.isLoggedIn)
            XCTAssertEqual(appState.sessionRestorationState, .unauthenticated)
        }
    }

    func testLogoutFailurePreservesSessionUntilConfirmedLocalOnlySignOut() async {
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        defer { persistence.reset() }
        let client = AuthLifecycleAPIClient(logoutResult: .failure(.networkError(URLError(.notConnectedToInternet))))
        let appState = AppState(apiClient: client, persistence: persistence)
        appState.handleLoginSuccess(response: LoginResponse(token: "token", userId: 8, role: "VOLUNTEER"))

        await appState.logout()

        XCTAssertTrue(appState.isLoggedIn)
        guard case .revocationFailed = appState.logoutState else {
            return XCTFail("Expected retryable revocation failure")
        }
        appState.confirmLocalOnlySignOut()
        XCTAssertFalse(appState.isLoggedIn)
    }

    func testLocalCleanupIsIdempotentAndClearsUserScopedMetadata() {
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        defer { persistence.reset() }
        let appState = AppState(persistence: persistence)
        appState.handleLoginSuccess(response: LoginResponse(token: "token", userId: 9, role: "BLIND"))
        persistence.set("event-9", forKey: AppConstants.UserDefaultsKeys.emergencyRecoveryMetadata)

        appState.clearSession()
        appState.clearSession()

        XCTAssertNil(appState.accessToken)
        XCTAssertNil(appState.currentUser)
        XCTAssertNil(persistence.object(forKey: AppConstants.UserDefaultsKeys.emergencyRecoveryMetadata))
    }

    func testAccountDeletionPreflightSpeaksActiveOrderBlock() async throws {
        let data = #"{"content":[{"orderId":77,"status":"IN_PROGRESS"}]}"#.data(using: .utf8)!
        let orders = try JSONDecoder().decode(PagedOrderResponse.self, from: data)
        let client = AuthLifecycleAPIClient(mineOrders: orders)
        let appState = AppState(apiClient: client)
        let speechService = SpeechService()
        let viewModel = AccountDeletionViewModel()

        await viewModel.preflight(appState: appState, speechService: speechService)

        let expected = "当前存在进行中的服务，请处理完成后再删除账户。"
        XCTAssertEqual(viewModel.preflightMessage, expected)
        XCTAssertEqual(speechService.lastSpokenText, expected)
        XCTAssertEqual(speechService.lastVoiceOverAnnouncement, expected)
        XCTAssertFalse(viewModel.showFinalConfirmation)
    }

    func testURLSessionRateLimitPrefersRetryAfterHeader() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthLifecycleURLProtocol.self]
        AuthLifecycleURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 429,
                httpVersion: nil,
                headerFields: ["Retry-After": "7"]
            )!
            let data = #"{"code":"RATE_LIMITED","message":"注册过于频繁","retryAfterSeconds":99}"#.data(using: .utf8)!
            return (response, data)
        }
        let client = URLSessionAPIClient(baseURL: URL(string: "http://example.test")!, session: URLSession(configuration: configuration), tokenProvider: { nil })

        do {
            let _: EmptyResponse = try await client.post("/registration", requiresAuth: false)
            XCTFail("Expected rate limit")
        } catch APIError.rateLimited(let info) {
            XCTAssertEqual(info.retryAfterSeconds, 7)
            XCTAssertEqual(info.message, "注册过于频繁")
        }
        AuthLifecycleURLProtocol.handler = nil
    }

    func testNetworkDiagnosticsSanitizeIdentifiersAndSecrets() async throws {
        await NetworkDiagnosticRecorder.shared.resetForTesting()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthLifecycleURLProtocol.self]
        AuthLifecycleURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data("{}".utf8))
        }
        let secret = "secret-jwt-13800138000"
        let client = URLSessionAPIClient(
            baseURL: URL(string: "http://example.test")!,
            session: URLSession(configuration: configuration),
            tokenProvider: { secret }
        )

        let _: EmptyResponse = try await client.get("/api/orders/123/track")
        let events = await NetworkDiagnosticRecorder.shared.snapshot()
        let event = try XCTUnwrap(events.last)

        XCTAssertEqual(event.endpointCategory, "/api/orders/{id}/track")
        XCTAssertEqual(event.statusCode, 200)
        XCTAssertFalse(String(describing: event).contains(secret))
        XCTAssertFalse(String(describing: event).contains("13800138000"))
        AuthLifecycleURLProtocol.handler = nil
    }

    func testRegistrationRateLimitDisablesSubmitForAuthoritativeCountdown() async {
        let client = AuthLifecycleAPIClient(registrationRateLimitSeconds: 2)
        let appState = AppState(apiClient: client)
        let viewModel = VolunteerRegistrationViewModel(apiClient: client)
        viewModel.configure(appState: appState, speechService: SpeechService())
        viewModel.name = "测试志愿者"
        viewModel.phone = "13800138000"
        viewModel.idCardNumber = "110101199001011234"

        await viewModel.submitBasicInfo()

        XCTAssertEqual(viewModel.registrationRetryAfterSeconds, 2)
        XCTAssertFalse(viewModel.canSubmitBasicInfo)
        let expired = expectation(description: "authoritative registration cooldown expires")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { expired.fulfill() }
        await fulfillment(of: [expired], timeout: 3)
        XCTAssertNil(viewModel.registrationRetryAfterSeconds)
        XCTAssertTrue(viewModel.canSubmitBasicInfo)
    }

    private func prepareStoredSession(token: String, role: UserRole?, userId: Int64) -> UserDefaultsAppStatePersistence {
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        persistence.set(token, forKey: AppConstants.UserDefaultsKeys.accessToken)
        persistence.set(userId, forKey: AppConstants.UserDefaultsKeys.userId)
        if let role { persistence.set(role.rawValue, forKey: AppConstants.UserDefaultsKeys.activeRole) }
        else { persistence.removeObject(forKey: AppConstants.UserDefaultsKeys.activeRole) }
        return persistence
    }

    func testAuthenticatedUnauthorizedErrorExpiresSession() {
        let appState = AppState()
        appState.currentEnvironment = .mock
        appState.accessToken = "expired-token"
        appState.userId = 12
        appState.activeRole = .blind

        let didExpire = appState.handleAuthenticatedAPIError(.unauthorized)

        XCTAssertTrue(didExpire)
        XCTAssertNil(appState.accessToken)
        XCTAssertNil(appState.userId)
        XCTAssertNil(appState.activeRole)
        XCTAssertEqual(appState.consumeSessionExpirationMessage(), "登录已过期，请重新登录。")
    }

    func testAuthenticatedNonUnauthorizedErrorDoesNotExpireSession() {
        let appState = AppState()
        appState.currentEnvironment = .mock
        appState.accessToken = "valid-token"
        appState.userId = 12
        appState.activeRole = .blind

        let didExpire = appState.handleAuthenticatedAPIError(.networkError(
            NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost)
        ))

        XCTAssertFalse(didExpire)
        XCTAssertEqual(appState.accessToken, "valid-token")
        XCTAssertEqual(appState.userId, 12)
        XCTAssertEqual(appState.activeRole, .blind)
        XCTAssertNil(appState.consumeSessionExpirationMessage())
    }

    func testRoleSelectionUnauthorizedExpiresSessionAndReturnsToLogin() async {
        let appState = AppState()
        appState.currentEnvironment = .mock
        appState.accessToken = "expired-token"
        appState.userId = 12
        let viewModel = RoleSelectionViewModel(apiClient: FailingAPIClient(error: APIError.unauthorized))
        viewModel.configure(with: appState, speechService: SpeechService())

        viewModel.selectRole(.volunteer)

        let didExpire = await waitUntil {
            appState.accessToken == nil &&
            appState.activeRole == nil &&
            appState.userId == nil &&
            !viewModel.isLoading
        }

        XCTAssertTrue(didExpire)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.showBlockedAlert)
        XCTAssertEqual(appState.consumeSessionExpirationMessage(), "登录已过期，请重新登录。")
    }

    func testLoginViewModelShowsAndConsumesSessionExpirationMessage() {
        let appState = AppState()
        appState.currentEnvironment = .mock
        appState.expireSession()
        let viewModel = LoginViewModel()

        viewModel.configure(with: appState, speechService: SpeechService())

        XCTAssertEqual(viewModel.errorMessage, "登录已过期，请重新登录。")
        XCTAssertNil(appState.consumeSessionExpirationMessage())

        viewModel.sanitizePhoneInput("138")

        XCTAssertNil(viewModel.errorMessage)
    }

    func testLoginPhoneInputKeepsOnlyFirstElevenDigits() {
        let viewModel = LoginViewModel()

        viewModel.sanitizePhoneInput(" 138 0013 8000 999")

        XCTAssertEqual(viewModel.phoneNumber, "13800138000")
    }

    func testLoginPhoneInputDropsNonDigits() {
        let viewModel = LoginViewModel()

        viewModel.sanitizePhoneInput("abc138-0013-8000xyz")

        XCTAssertEqual(viewModel.phoneNumber, "13800138000")
    }

    func testLoginPhoneDirectAssignmentKeepsOnlyFirstElevenDigits() {
        let viewModel = LoginViewModel()

        viewModel.phoneNumber = "13800138000999"

        XCTAssertEqual(viewModel.phoneNumber, "13800138000")
    }

    func testLoginPhoneInputKeepsScreenshotLongValueToElevenDigits() {
        let viewModel = LoginViewModel()

        viewModel.sanitizePhoneInput("13800000001000000")

        XCTAssertEqual(viewModel.phoneNumber, "13800000001")
    }

    func testLoginPhoneSanitizeAlreadyCompleteValueKeepsElevenDigits() {
        let viewModel = LoginViewModel()
        viewModel.phoneNumber = "13800138000"

        viewModel.sanitizePhoneInput("138001380009")

        XCTAssertEqual(viewModel.phoneNumber, "13800138000")
    }

    func testLoginVerificationCodeInputKeepsOnlyFirstSixDigits() {
        let viewModel = LoginViewModel()

        viewModel.sanitizeVerificationCodeInput("000000789")

        XCTAssertEqual(viewModel.verificationCode, "000000")
    }

    func testLoginVerificationCodeInputDropsNonDigits() {
        let viewModel = LoginViewModel()

        viewModel.sanitizeVerificationCodeInput("abc 000-000 xyz")

        XCTAssertEqual(viewModel.verificationCode, "000000")
    }

    func testLoginVerificationCodeDirectAssignmentKeepsOnlyFirstSixDigits() {
        let viewModel = LoginViewModel()

        viewModel.verificationCode = "000000789"

        XCTAssertEqual(viewModel.verificationCode, "000000")
    }

    func testLoginVerificationCodeSanitizeAlreadyCompleteValueKeepsSixDigits() {
        let viewModel = LoginViewModel()
        viewModel.verificationCode = AppConstants.Auth.demoVerificationCode

        viewModel.sanitizeVerificationCodeInput("0000007")

        XCTAssertEqual(viewModel.verificationCode, "000000")
    }

    func testSubmitLoginWithCompleteInputsDoesNotReenterVerificationCodeSetter() {
        let viewModel = LoginViewModel()
        viewModel.phoneNumber = "13800138000"
        viewModel.verificationCode = AppConstants.Auth.demoVerificationCode

        viewModel.submitLogin()

        XCTAssertEqual(viewModel.phoneNumber, "13800138000")
        XCTAssertEqual(viewModel.verificationCode, "000000")
    }

    func testRequestCodeShowsInputOnlyAfterSendCodeSucceeds() async {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let viewModel = LoginViewModel()
        viewModel.configure(with: appState, speechService: SpeechService())
        viewModel.phoneNumber = "13800138000"

        viewModel.requestCode()

        XCTAssertTrue(viewModel.isSendingCode)
        XCTAssertFalse(viewModel.showCodeInput)
        XCTAssertNil(viewModel.countdown)

        let didSend = await waitUntil {
            viewModel.showCodeInput &&
            viewModel.countdown != nil &&
            !viewModel.isSendingCode
        }

        XCTAssertTrue(didSend)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testRequestCodeFailureDoesNotStartCountdownOrShowInput() async {
        let viewModel = LoginViewModel(apiClient: FailingAPIClient(error: APIError.networkError(
            NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost)
        )))
        viewModel.phoneNumber = "13800138000"

        viewModel.requestCode()

        let didFail = await waitUntil {
            viewModel.errorMessage != nil && !viewModel.isSendingCode
        }

        XCTAssertTrue(didFail)
        XCTAssertEqual(viewModel.errorMessage, "网络错误，请重试")
        XCTAssertFalse(viewModel.showCodeInput)
        XCTAssertNil(viewModel.countdown)
    }

    /// send-code 响应里没有任何验证码字段（后端 `AuthService.sendCode` 返回 void），
    /// 提交的必须永远是用户自己输入的那 6 位，不做任何替换。
    func testVerifyCodeSubmitsExactlyWhatUserTyped() async {
        let client = LoginCodeCaptureAPIClient(sendCodeResponse: SendCodeResponse(
            success: true,
            message: "验证码已发送",
            code: "654321"
        ))
        let viewModel = LoginViewModel(apiClient: client)
        viewModel.phoneNumber = "13800000001"

        viewModel.requestCode()
        let didShowInput = await waitUntil { viewModel.showCodeInput }
        XCTAssertTrue(didShowInput)
        viewModel.sanitizeVerificationCodeInput(AppConstants.Auth.demoVerificationCode)

        let didCaptureTypedCode = await waitUntil { client.capturedVerifyCodeRequest?.code == AppConstants.Auth.demoVerificationCode }
        XCTAssertTrue(didCaptureTypedCode)
        XCTAssertEqual(client.capturedVerifyCodeRequest?.phone, "13800000001")
    }

    func testDevelopmentInitialEnvironmentKeepsSupportedDebugChoices() {
        XCTAssertEqual(AppState.resolvedInitialEnvironment(.mock, channel: .development), .mock)
        XCTAssertEqual(AppState.resolvedInitialEnvironment(.demoCloud, channel: .development), .demoCloud)
    }

    func testDemoReleaseLocksInitialEnvironmentToDemoCloud() {
        XCTAssertEqual(AppState.resolvedInitialEnvironment(.mock, channel: .demo), .demoCloud)
        XCTAssertEqual(AppState.resolvedInitialEnvironment(.demoCloud, channel: .demo), .demoCloud)
    }

    func testProductionReleaseLocksInitialEnvironmentToDemoCloud() {
        XCTAssertEqual(AppState.resolvedInitialEnvironment(.mock, channel: .production), .demoCloud)
        XCTAssertEqual(AppState.resolvedInitialEnvironment(.demoCloud, channel: .production), .demoCloud)
    }

    func testUnknownStoredEnvironmentIsRejected() {
        XCTAssertNil(AppState.storedEnvironment(from: "unsupported"))
    }

    func testDemoCloudBaseURLUsesCurrentDemoIPAddress() {
        XCTAssertEqual(APIEnvironment.demoCloud.baseURL?.absoluteString, "http://47.114.113.171")
    }

    func testWebSocketUsesFixedCloudHost() throws {
        let baseURL = try XCTUnwrap(APIEnvironment.demoCloud.baseURL)
        let webSocketURL = try XCTUnwrap(WebSocketService.connectionURL(baseURL: baseURL, token: "jwt", role: .blind))

        XCTAssertEqual(webSocketURL.scheme, "ws")
        XCTAssertEqual(webSocketURL.host, "47.114.113.171")
        XCTAssertEqual(webSocketURL.path, "/ws/blind")
        XCTAssertTrue(webSocketURL.absoluteString.contains("token=jwt"))
    }

    func testDebugEnvironmentSwitcherCyclesMockAndDemoCloud() {
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        defer { persistence.reset() }
        persistence.set(APIEnvironment.mock.rawValue, forKey: AppConstants.UserDefaultsKeys.apiEnvironment)
        let appState = AppState(persistence: persistence)

        XCTAssertEqual(appState.currentEnvironment, .mock)
        appState.switchToNextEnvironmentForTesting()
        XCTAssertEqual(appState.currentEnvironment, .demoCloud)
        appState.switchToNextEnvironmentForTesting()
        XCTAssertEqual(appState.currentEnvironment, .mock)
    }

    func testInjectedTestPersistenceNeverChangesStandardAppDomain() {
        let keys = AppStatePersistenceKeys.all
        let before = Dictionary(uniqueKeysWithValues: keys.map { ($0, UserDefaults.standard.object(forKey: $0).map(String.init(describing:))) })
        let persistence = AppStatePersistenceFactory.makeIsolatedTest()
        defer { persistence.reset() }
        let appState = AppState(persistence: persistence)

        appState.currentEnvironment = .mock
        appState.accessToken = "unit-test-token"
        appState.userId = 4242
        appState.activeRole = .volunteer
        appState.clearSession()

        let after = Dictionary(uniqueKeysWithValues: keys.map { ($0, UserDefaults.standard.object(forKey: $0).map(String.init(describing:))) })
        XCTAssertEqual(before, after)
    }

    func testDefaultHostedXCTestPersistenceNeverChangesStandardAppDomain() {
        let keys = AppStatePersistenceKeys.all
        let before = Dictionary(uniqueKeysWithValues: keys.map { ($0, UserDefaults.standard.object(forKey: $0).map(String.init(describing:))) })
        let appState = AppState()

        appState.currentEnvironment = .mock
        appState.accessToken = "hosted-test-token"
        appState.userId = 4343
        appState.activeRole = .blind
        appState.clearSession()

        let after = Dictionary(uniqueKeysWithValues: keys.map { ($0, UserDefaults.standard.object(forKey: $0).map(String.init(describing:))) })
        XCTAssertEqual(before, after)
    }

    func testUITestPersistenceUsesDedicatedResettableDomain() {
        let persistence = UserDefaultsAppStatePersistence(suiteName: AppStatePersistenceFactory.uiTestSuiteName)
        defer { persistence.reset() }
        persistence.set("ui-token", forKey: AppConstants.UserDefaultsKeys.accessToken)
        XCTAssertEqual(persistence.string(forKey: AppConstants.UserDefaultsKeys.accessToken), "ui-token")
        persistence.reset()
        XCTAssertNil(persistence.string(forKey: AppConstants.UserDefaultsKeys.accessToken))
    }

    func testCreateOrderRequestUsesOpenAPIWireValues() throws {
        let request = CreateOrderRequest(
            startLatitude: 31.2304,
            startLongitude: 121.4737,
            startAddress: "人民广场",
            plannedStartTime: "2026-05-22T09:00:00Z",
            plannedEndTime: "2026-05-22T10:00:00Z",
            expectedDurationMinutes: 60,
            pacePreference: .easy,
            routePreference: .parkTrail,
            routeNotes: "公园慢跑一圈",
            hasGuideDogThisRun: false,
            specialNotes: "请在地铁口见面"
        )

        let data = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["startLatitude"] as? Double, 31.2304)
        XCTAssertEqual(json["startLongitude"] as? Double, 121.4737)
        XCTAssertEqual(json["startAddress"] as? String, "人民广场")
        XCTAssertEqual(json["routeNotes"] as? String, "公园慢跑一圈")
        XCTAssertEqual(json["specialNotes"] as? String, "请在地铁口见面")
        XCTAssertEqual(json["pacePreference"] as? String, "EASY")
        XCTAssertEqual(json["routePreference"] as? String, "PARK_TRAIL")
    }

    func testBlindBookingResolvedStartLocationKeepsCoordinatesAndAppendsManualDescription() {
        let viewModel = BlindBookingViewModel()
        viewModel.currentResolvedPlace = ResolvedPlace(
            id: "current",
            title: "当前位置",
            addressText: "上海市黄浦区人民广场",
            latitude: 31.2304,
            longitude: 121.4737,
            source: .deviceLocation
        )
        viewModel.startLocationDescription = "我在地铁口外侧"

        XCTAssertEqual(viewModel.resolvedStartPlace?.latitude, 31.2304)
        XCTAssertEqual(viewModel.resolvedStartPlace?.longitude, 121.4737)
        XCTAssertEqual(viewModel.resolvedStartPlace?.source, .deviceLocation)
        XCTAssertEqual(viewModel.resolvedStartLocationDescription, "上海市黄浦区人民广场；补充：我在地铁口外侧")
    }

    func testBlindBookingSpeechCompletionAutoSearchesStartPlaceAndAllowsRepeatedKeywordRetry() async {
        let place = ResolvedPlace(
            id: "poi-1",
            title: "大观楼",
            addressText: "大观楼，西山区 大观路284号",
            latitude: 25.024196,
            longitude: 102.673887,
            source: .manual
        )
        let provider = FakePlaceSearchProvider(results: [
            place
        ])
        let speechService = SpeechService()
        let viewModel = BlindBookingViewModel()
        viewModel.configureForTesting(placeSearchProvider: provider, speechService: speechService)

        await viewModel.handlePlaceSearchSpeechCompletion(SpeechInputCompletion(
            field: .startPlaceSearch,
            recognizedText: "大观",
            reason: .silenceTimeout(hadDetectedSound: true)
        ))
        viewModel.selectPlace(place)
        await viewModel.handlePlaceSearchSpeechCompletion(SpeechInputCompletion(
            field: .startPlaceSearch,
            recognizedText: " 大观 ",
            reason: .finalResult
        ))

        XCTAssertEqual(provider.searchKeywords, ["大观", "大观"])
        XCTAssertEqual(viewModel.placeSearchKeyword, "大观")
        XCTAssertEqual(viewModel.placeSearchResults.map(\.title), ["大观楼"])
        XCTAssertEqual(viewModel.searchResultFocusID, "poi-1")
        XCTAssertEqual(speechService.lastVoiceOverAnnouncement, "已找到 1 个地点，第一个是 大观楼。")
    }

    func testBlindBookingSpeechCompletionSkipsErrorAndNoSpeechTimeout() async {
        let provider = FakePlaceSearchProvider(results: [])
        let speechService = SpeechService()
        let viewModel = BlindBookingViewModel()
        viewModel.configureForTesting(placeSearchProvider: provider, speechService: speechService)

        await viewModel.handlePlaceSearchSpeechCompletion(SpeechInputCompletion(
            field: .startPlaceSearch,
            recognizedText: "大观",
            reason: .silenceTimeout(hadDetectedSound: false)
        ))
        await viewModel.handlePlaceSearchSpeechCompletion(SpeechInputCompletion(
            field: .startPlaceSearch,
            recognizedText: "大观",
            reason: .error
        ))

        XCTAssertTrue(provider.searchKeywords.isEmpty)
        XCTAssertTrue(viewModel.placeSearchResults.isEmpty)
    }

    func testResolvedPlaceBookingSearchAccessibilityLabelDoesNotExposeCoordinates() {
        let place = ResolvedPlace(
            id: "poi-1",
            title: "大观楼",
            addressText: "大观楼，西山区 大观路284号",
            latitude: 25.024196,
            longitude: 102.673887,
            source: .manual
        )

        XCTAssertEqual(place.bookingSearchAccessibilityLabel, "选择出发地点，大观楼，大观楼，西山区 大观路284号")
        XCTAssertFalse(place.bookingSearchAccessibilityLabel.contains("纬度"))
        XCTAssertFalse(place.bookingSearchAccessibilityLabel.contains("经度"))
        XCTAssertFalse(place.bookingSearchAccessibilityLabel.contains("25.024196"))
        XCTAssertFalse(place.bookingSearchAccessibilityLabel.contains("102.673887"))
    }

    func testBlindBookingRequiresAppointmentAtLeastThirtyMinutesLater() {
        let viewModel = BlindBookingViewModel()

        viewModel.appointmentTime = Date().addingTimeInterval(10 * 60)

        XCTAssertFalse(viewModel.isAppointmentTimeValid)

        viewModel.appointmentTime = Date().addingTimeInterval(31 * 60)

        XCTAssertTrue(viewModel.isAppointmentTimeValid)
    }

    func testBlindBookingGuidedStepValidationBlocksInvalidAppointmentAndSpeaksReason() {
        let speechService = SpeechService()
        let viewModel = BlindBookingViewModel()
        viewModel.configureForTesting(
            placeSearchProvider: FakePlaceSearchProvider(results: []),
            speechService: speechService
        )
        viewModel.currentStep = .appointmentTime
        viewModel.appointmentTime = Date().addingTimeInterval(10 * 60)

        viewModel.moveToNextStep()

        XCTAssertEqual(viewModel.currentStep, .appointmentTime)
        XCTAssertEqual(viewModel.errorMessage, "预约时间需至少在 30 分钟后。")
        XCTAssertEqual(speechService.lastSpokenText, "预约时间需至少在 30 分钟后。")
        XCTAssertFalse(viewModel.canAdvanceFromCurrentStep)
    }

    func testBlindBookingGuidedStepSummariesOmitEmptyOptionalNeeds() {
        let speechService = SpeechService()
        let viewModel = BlindBookingViewModel()
        viewModel.configureForTesting(
            placeSearchProvider: FakePlaceSearchProvider(results: []),
            speechService: speechService
        )
        viewModel.currentStep = .runningNeeds

        XCTAssertTrue(viewModel.optionalReviewItems.isEmpty)
        XCTAssertEqual(viewModel.optionalNeedsSpeechSummary, "没有填写选填跑步需求。")

        viewModel.routeNotes = "沿公园慢跑一圈"
        viewModel.pacePreference = .easy
        viewModel.specialNotes = "我会带导盲杖"
        viewModel.repeatCurrentStepStatus()

        XCTAssertEqual(viewModel.optionalReviewItems.map(\.title), ["路线备注", "配速偏好", "特殊说明"])
        XCTAssertTrue(speechService.lastSpokenText?.contains("路线备注：沿公园慢跑一圈") == true)
        XCTAssertTrue(speechService.lastSpokenText?.contains("配速偏好：轻松") == true)
        XCTAssertFalse(speechService.lastSpokenText?.contains("预计时长") == true)
        XCTAssertFalse(speechService.lastSpokenText?.contains("路线偏好") == true)
    }

    func testBlindBookingCreateOrderRequestKeepsPayloadFieldsThroughGuidedFlow() throws {
        let viewModel = BlindBookingViewModel()
        viewModel.selectedStartPlace = ResolvedPlace(
            id: "poi-1",
            title: "科技园地铁站",
            addressText: "深圳市南山区科技园地铁站 A 口",
            latitude: 22.5401,
            longitude: 113.9345,
            source: .manual
        )
        viewModel.startLocationDescription = "我在 A 口外侧"
        viewModel.appointmentTime = try XCTUnwrap(DateFormatter.aidRunBackendLocalDateTime.date(from: "2026-07-06T09:30:00"))
        viewModel.duration = .sixty
        viewModel.pacePreference = .moderate
        viewModel.routePreference = .parkTrail
        viewModel.routeNotes = "沿公园慢跑一圈"
        viewModel.hasGuideDogThisRun = true
        viewModel.specialNotes = "我会带导盲杖"

        let request = try XCTUnwrap(viewModel.makeCreateOrderRequest())

        XCTAssertEqual(request.startLatitude, 22.5401, accuracy: 0.000001)
        XCTAssertEqual(request.startLongitude, 113.9345, accuracy: 0.000001)
        XCTAssertEqual(request.startAddress, "深圳市南山区科技园地铁站 A 口；补充：我在 A 口外侧")
        XCTAssertEqual(request.plannedStartTime, "2026-07-06T09:30:00")
        XCTAssertEqual(request.plannedEndTime, "2026-07-06T10:30:00")
        XCTAssertEqual(request.expectedDurationMinutes, 60)
        XCTAssertEqual(request.pacePreference, .moderate)
        XCTAssertEqual(request.routePreference, .parkTrail)
        XCTAssertEqual(request.routeNotes, "沿公园慢跑一圈")
        XCTAssertEqual(request.hasGuideDogThisRun, true)
        XCTAssertEqual(request.specialNotes, "我会带导盲杖")
    }

    func testBlindBookingAuxiliaryMapAccessibilityLabelDoesNotExposeCoordinates() {
        let viewModel = BlindBookingViewModel()
        viewModel.selectedStartPlace = ResolvedPlace(
            id: "poi-1",
            title: "大观楼",
            addressText: "大观楼，西山区 大观路284号",
            latitude: 25.024196,
            longitude: 102.673887,
            source: .manual
        )

        XCTAssertTrue(viewModel.auxiliaryMapAccessibilityLabel.contains("辅助地图"))
        XCTAssertTrue(viewModel.auxiliaryMapAccessibilityLabel.contains("已选择高德地点"))
        XCTAssertFalse(viewModel.auxiliaryMapAccessibilityLabel.contains("25.024196"))
        XCTAssertFalse(viewModel.auxiliaryMapAccessibilityLabel.contains("102.673887"))
    }

    func testBlindBookingLocationRefreshUpdatesPayloadWhileStabilizingAuxiliaryMapMarker() async throws {
        let locationService = LocationService()
        let initialPlace = ResolvedPlace(
            id: "current-1",
            title: "当前位置",
            addressText: "深圳市南山区科技园",
            latitude: 22.5401,
            longitude: 113.9345,
            source: .deviceLocation
        )
        let smallMovePlace = ResolvedPlace(
            id: "current-2",
            title: "当前位置",
            addressText: "深圳市南山区科技园 A 口",
            latitude: 22.5402,
            longitude: 113.9345,
            source: .deviceLocation
        )
        let largeMovePlace = ResolvedPlace(
            id: "current-3",
            title: "当前位置",
            addressText: "深圳市南山区科技园 B 口",
            latitude: 22.5410,
            longitude: 113.9345,
            source: .deviceLocation
        )
        let provider = FakePlaceSearchProvider(
            results: [],
            reverseGeocodeResults: [initialPlace, smallMovePlace, largeMovePlace]
        )
        let viewModel = BlindBookingViewModel()
        viewModel.configureForTesting(
            placeSearchProvider: provider,
            speechService: SpeechService(),
            locationService: locationService
        )

        await viewModel.refreshCurrentLocation()
        let demoCenter = try XCTUnwrap(viewModel.auxiliaryMapCenter)
        XCTAssertEqual(viewModel.auxiliaryMapPlace?.source, .demoDefault)

        locationService.currentLocation = CLLocationCoordinate2D(latitude: 22.5401, longitude: 113.9345)
        await viewModel.refreshCurrentLocationIfNeeded()
        let initialCenter = try XCTUnwrap(viewModel.auxiliaryMapCenter)
        let initialMapPlace = try XCTUnwrap(viewModel.auxiliaryMapPlace)
        XCTAssertNotEqual(initialCenter.latitude, demoCenter.latitude, accuracy: 0.000001)
        XCTAssertEqual(initialMapPlace.latitude, initialPlace.latitude, accuracy: 0.000001)
        XCTAssertEqual(viewModel.resolvedStartPlace?.addressText, "深圳市南山区科技园")

        locationService.currentLocation = CLLocationCoordinate2D(latitude: 22.5402, longitude: 113.9345)
        await viewModel.refreshCurrentLocationIfNeeded()
        let smallMoveCenter = try XCTUnwrap(viewModel.auxiliaryMapCenter)
        let smallMoveMapPlace = try XCTUnwrap(viewModel.auxiliaryMapPlace)
        let smallMoveRequest = try XCTUnwrap(viewModel.makeCreateOrderRequest())

        XCTAssertEqual(smallMoveCenter.latitude, initialCenter.latitude, accuracy: 0.000001)
        XCTAssertEqual(smallMoveCenter.longitude, initialCenter.longitude, accuracy: 0.000001)
        XCTAssertEqual(smallMoveMapPlace.latitude, initialPlace.latitude, accuracy: 0.000001)
        XCTAssertEqual(smallMoveRequest.startLatitude, smallMovePlace.latitude, accuracy: 0.000001)
        XCTAssertEqual(smallMoveRequest.startAddress, "深圳市南山区科技园 A 口")

        locationService.currentLocation = CLLocationCoordinate2D(latitude: 22.5410, longitude: 113.9345)
        await viewModel.refreshCurrentLocationIfNeeded()
        let largeMoveCenter = try XCTUnwrap(viewModel.auxiliaryMapCenter)
        let largeMoveMapPlace = try XCTUnwrap(viewModel.auxiliaryMapPlace)

        XCTAssertEqual(largeMoveCenter.latitude, initialCenter.latitude, accuracy: 0.000001)
        XCTAssertEqual(largeMoveCenter.longitude, initialCenter.longitude, accuracy: 0.000001)
        XCTAssertEqual(largeMoveMapPlace.latitude, largeMovePlace.latitude, accuracy: 0.000001)
        XCTAssertEqual(viewModel.resolvedStartPlace?.addressText, "深圳市南山区科技园 B 口")

        let selectedPlace = ResolvedPlace(
            id: "poi-2",
            title: "大观楼",
            addressText: "大观楼",
            latitude: 25.024196,
            longitude: 102.673887,
            source: .manual
        )
        viewModel.selectPlace(selectedPlace)
        let selectedCenter = try XCTUnwrap(viewModel.auxiliaryMapCenter)
        let selectedMapPlace = try XCTUnwrap(viewModel.auxiliaryMapPlace)
        let selectedRequest = try XCTUnwrap(viewModel.makeCreateOrderRequest())

        XCTAssertEqual(selectedCenter.latitude, selectedPlace.latitude, accuracy: 0.000001)
        XCTAssertEqual(selectedCenter.longitude, selectedPlace.longitude, accuracy: 0.000001)
        XCTAssertEqual(selectedMapPlace.latitude, selectedPlace.latitude, accuracy: 0.000001)
        XCTAssertEqual(selectedRequest.startLatitude, selectedPlace.latitude, accuracy: 0.000001)

        locationService.currentLocation = CLLocationCoordinate2D(latitude: 22.5500, longitude: 113.9400)
        await viewModel.refreshCurrentLocationIfNeeded()

        XCTAssertEqual(viewModel.resolvedStartPlace?.id, selectedPlace.id)
        XCTAssertEqual(viewModel.auxiliaryMapPlace?.id, selectedPlace.id)
    }

    func testBlindBookingDurationOptions() {
        XCTAssertEqual(BookingDurationOption.sixty.minutes, 60)
        XCTAssertNil(BookingDurationOption.none.minutes)
    }

    func testPacePreferenceDisplayNames() {
        XCTAssertEqual(PacePreference.walkRun.displayName, "走跑结合")
        XCTAssertEqual(PacePreference.easy.displayName, "轻松")
        XCTAssertEqual(PacePreference.moderate.displayName, "中等")
        XCTAssertEqual(PacePreference.fast.displayName, "快速")
        XCTAssertEqual(PacePreference.noPreference.displayName, "无偏好")
    }

    func testRoutePreferenceDisplayNames() {
        XCTAssertEqual(RoutePreference.parkTrail.displayName, "公园步道")
        XCTAssertEqual(RoutePreference.street.displayName, "街道")
        XCTAssertEqual(RoutePreference.track.displayName, "跑道")
        XCTAssertEqual(RoutePreference.noPreference.displayName, "无偏好")
    }

    func testAMapPOIMapsToResolvedPlaceForBookingSearch() throws {
        let poi = AMapPOI()
        poi.uid = "poi-001"
        poi.name = "科技园地铁站"
        poi.district = "南山区"
        poi.address = "A口"
        poi.location = AMapGeoPoint.location(withLatitude: 22.5401, longitude: 113.9345)

        let place = try XCTUnwrap(AMapGeocodingService.resolvedPlace(from: poi))

        XCTAssertEqual(place.id, "poi-001")
        XCTAssertEqual(place.title, "科技园地铁站")
        XCTAssertEqual(place.addressText, "科技园地铁站，南山区 A口")
        XCTAssertEqual(place.latitude, 22.5401, accuracy: 0.000001)
        XCTAssertEqual(place.longitude, 113.9345, accuracy: 0.000001)
        XCTAssertEqual(place.source, .manual)
    }

    func testSpeechInputStopReasonAnnouncements() {
        XCTAssertEqual(SpeechInputStopReason.manual.announcement, "语音输入已关闭。")
        XCTAssertEqual(
            SpeechInputStopReason.silenceTimeout(hadDetectedSound: false).announcement,
            "未检测到声音，已停止语音输入。"
        )
        XCTAssertEqual(
            SpeechInputStopReason.silenceTimeout(hadDetectedSound: true).announcement,
            "语音输入已停止。"
        )
        XCTAssertEqual(SpeechInputStopReason.maxDuration.announcement, "语音输入已达到最长时间，已停止。")
    }

    func testVoiceServiceExposesRequestedAPIAndCompatibilityAlias() {
        let service = VoiceService()
        let legacyService: SpeechService = service

        service.speak(text: " 当前状态 ")
        XCTAssertEqual(service.lastSpokenText, "当前状态")
        XCTAssertEqual(service.latestRepeatableText, "当前状态")
        XCTAssertEqual(service.lastVoiceOverAnnouncement, "当前状态")

        legacyService.repeatCurrentStatus()
        XCTAssertEqual(service.lastSpokenText, "当前状态")

        service.stop()
        XCTAssertFalse(service.isSpeaking)
    }

    func testVoiceServiceCanPostVoiceOverOnlyAnnouncement() {
        let service = VoiceService()

        service.announce(" 已找到 2 个地点 ")

        XCTAssertNil(service.lastSpokenText)
        XCTAssertEqual(service.lastVoiceOverAnnouncement, "已找到 2 个地点")
    }

    func testVoiceServiceStatusAnnouncementsMatchAccessibilityGuidelinesAndDeduplicate() {
        let service = VoiceService()

        XCTAssertEqual(
            VoiceService.statusAnnouncement(for: .pendingMatch),
            "订单提交成功，系统正在为你派单。"
        )
        XCTAssertEqual(
            VoiceService.statusAnnouncement(for: .driverArrived),
            "志愿者已到达，请等待志愿者开始服务。"
        )
        XCTAssertEqual(
            VoiceService.statusAnnouncement(for: .pendingAccept),
            "志愿者已接单，请前往或等待在预约出发地点。"
        )
        XCTAssertEqual(
            VoiceService.statusAnnouncement(for: .driverEnRoute),
            "志愿者已出发，正在前往出发地点。"
        )
        XCTAssertEqual(
            VoiceService.statusAnnouncement(for: .completed),
            "服务已完成，感谢使用助盲跑。"
        )

        XCTAssertTrue(service.speakStatusChange(.pendingMatch))
        XCTAssertFalse(service.speakStatusChange(.pendingMatch))
        XCTAssertTrue(service.speakStatusChange(.pendingAccept))
        XCTAssertEqual(service.lastSpokenStatus, .pendingAccept)

        service.stop()
    }

    func testSpeechInputFieldsAreTextOnlyAllowlist() {
        XCTAssertTrue(SpeechInputField.isAllowlisted(SpeechInputField.startPlaceSearch.rawValue))
        XCTAssertTrue(SpeechInputField.isAllowlisted(SpeechInputField.startLocationDescription.rawValue))
        XCTAssertTrue(SpeechInputField.isAllowlisted(SpeechInputField.destinationRoute.rawValue))
        XCTAssertTrue(SpeechInputField.isAllowlisted(SpeechInputField.remark.rawValue))
        XCTAssertTrue(SpeechInputField.isAllowlisted(SpeechInputField.ratingFeedback.rawValue))
        XCTAssertTrue(SpeechInputField.isAllowlisted(SpeechInputField.volunteerServiceSummary.rawValue))

        XCTAssertFalse(SpeechInputField.isAllowlisted("appointmentTime"))
        XCTAssertFalse(SpeechInputField.isAllowlisted("estimatedDistance"))
        XCTAssertFalse(SpeechInputField.isAllowlisted("pacePreference"))
    }

    func testSpeechInputRejectsNonAllowlistedFieldAndKeepsKeyboardFallback() {
        let service = SpeechInputService()

        service.startRecognitionForTesting(fieldId: "appointmentTime")

        XCTAssertFalse(service.isListening)
        XCTAssertNil(service.activeFieldId)
        XCTAssertEqual(service.lastStopReason, .error)
        XCTAssertEqual(service.errorMessage, SpeechInputService.keyboardFallbackErrorMessage)
    }

    func testSpeechInputFailureShowsKeyboardFallbackError() {
        let service = SpeechInputService()

        service.simulateRecognitionFailureForTesting(field: .remark)

        XCTAssertFalse(service.isListening)
        XCTAssertNil(service.activeFieldId)
        XCTAssertEqual(service.lastStopReason, .error)
        XCTAssertEqual(service.errorMessage, SpeechInputService.keyboardFallbackErrorMessage)
    }

    func testSpeechInputStopRecognitionClearsActiveField() {
        let service = SpeechInputService()

        service.startRecognitionForTesting(fieldId: "remark")
        XCTAssertTrue(service.isListening(for: .remark))

        service.stopRecognition()

        XCTAssertFalse(service.isListening)
        XCTAssertNil(service.activeFieldId)
        XCTAssertEqual(service.lastStopReason, .manual)
    }

    func testSpeechInputRestoresPlaybackBeforeCompletionForEveryStopReason() {
        let reasons: [SpeechInputStopReason] = [
            .manual,
            .finalResult,
            .silenceTimeout(hadDetectedSound: false),
            .silenceTimeout(hadDetectedSound: true),
            .maxDuration,
            .error
        ]

        for reason in reasons {
            let audioSession = MockSpeechAudioSession()
            let service = SpeechInputService(audioSession: audioSession)
            var completionOperations: [String] = []
            service.startRecognitionForTesting(field: .startPlaceSearch) { _ in
                completionOperations = audioSession.operations + ["completion"]
            }

            service.finishRecognitionForTesting(text: "大观楼", reason: reason)

            XCTAssertEqual(
                completionOperations,
                ["deactivateRecording", "configurePlayback", "activatePlayback", "completion"],
                "Unexpected audio restoration order for \(reason)"
            )
        }
    }

    func testSpeechInputLifecycleStopRestoresPlaybackWithoutCompleting() {
        let audioSession = MockSpeechAudioSession()
        let service = SpeechInputService(audioSession: audioSession)
        var didComplete = false
        service.startRecognitionForTesting(field: .remark) { _ in didComplete = true }

        service.cancelRecognitionForLifecycle()

        XCTAssertEqual(audioSession.operations, ["deactivateRecording", "configurePlayback", "activatePlayback"])
        XCTAssertFalse(didComplete)
    }

    func testSpeechInputRepeatedStopDoesNotRepeatAudioSessionCleanup() {
        let audioSession = MockSpeechAudioSession()
        let service = SpeechInputService(audioSession: audioSession)
        service.startRecognitionForTesting(field: .remark)

        service.stopRecognition()
        service.stopRecognition()

        XCTAssertEqual(audioSession.operations, ["deactivateRecording", "configurePlayback", "activatePlayback"])
    }

    func testSpeechInputPlaybackRecoveryFailureKeepsCompletionAndDiagnostics() {
        let failurePoints: [MockSpeechAudioSession.FailurePoint] = [
            .deactivate,
            .playbackCategory,
            .playbackActivation
        ]

        for failurePoint in failurePoints {
            let audioSession = MockSpeechAudioSession()
            audioSession.failurePoint = failurePoint
            let service = SpeechInputService(audioSession: audioSession)
            var completion: SpeechInputCompletion?
            service.startRecognitionForTesting(field: .startPlaceSearch) { completion = $0 }

            service.finishRecognitionForTesting(text: "大观楼")

            XCTAssertEqual(completion?.recognizedText, "大观楼")
            XCTAssertEqual(audioSession.operations, ["deactivateRecording", "configurePlayback", "activatePlayback"])
            XCTAssertNotNil(service.audioSessionDiagnosticMessage)
            XCTAssertNil(service.errorMessage)
        }
    }

    func testSpeechInputStartupFailureRestoresPlaybackBeforeErrorAnnouncement() {
        let audioSession = MockSpeechAudioSession()
        let service = SpeechInputService(audioSession: audioSession)
        var observedOperations: [String] = []
        service.startRecognitionForTesting(field: .remark, onAnnouncement: { message in
            observedOperations = audioSession.operations + ["announce:\(message)"]
        })

        service.failRecognitionStartupForTesting("语音输入启动失败，请使用键盘输入。")

        XCTAssertEqual(
            observedOperations,
            [
                "deactivateRecording",
                "configurePlayback",
                "activatePlayback",
                "announce:语音输入启动失败，请使用键盘输入。"
            ]
        )
        XCTAssertEqual(service.lastStopReason, .error)
    }

    func testSpeechInputLifecycleCancelClearsStateWithoutCompletion() {
        let service = SpeechInputService()
        var completion: SpeechInputCompletion?

        service.startRecognitionForTesting(field: .startPlaceSearch) {
            completion = $0
        }
        service.cancelRecognitionForLifecycle()

        XCTAssertFalse(service.isListening)
        XCTAssertNil(service.activeFieldId)
        XCTAssertEqual(service.lastStopReason, .manual)
        XCTAssertNil(completion)

        service.startRecognitionForTesting(field: .startPlaceSearch) {
            completion = $0
        }
        service.finishRecognitionForTesting(text: "大观楼")

        XCTAssertEqual(completion?.field, .startPlaceSearch)
        XCTAssertEqual(completion?.recognizedText, "大观楼")
        XCTAssertEqual(completion?.reason, .finalResult)
    }

    func testSpeechInputLifecycleCancelInvalidatesPendingAuthorizationSession() {
        let service = SpeechInputService()
        var completion: SpeechInputCompletion?

        let staleSession = service.startPendingAuthorizationForTesting(field: .startPlaceSearch) {
            completion = $0
        }
        service.cancelRecognitionForLifecycle()
        service.simulateAuthorizationCompletionForTesting(sessionID: staleSession, field: .startPlaceSearch)

        XCTAssertFalse(service.isListening)
        XCTAssertNil(service.activeFieldId)
        XCTAssertEqual(service.lastStopReason, .manual)
        XCTAssertNil(completion)

        service.startRecognitionForTesting(field: .startPlaceSearch) {
            completion = $0
        }
        service.finishRecognitionForTesting(text: "大观楼")

        XCTAssertEqual(completion?.field, .startPlaceSearch)
        XCTAssertEqual(completion?.recognizedText, "大观楼")
        XCTAssertEqual(completion?.reason, .finalResult)
    }

    func testSpeechInputPendingAuthorizationOwnsRecognitionSessionBeforeListening() {
        let service = SpeechInputService()

        service.startPendingAuthorizationForTesting(field: .startPlaceSearch)

        XCTAssertFalse(service.isListening(for: .startPlaceSearch))
        XCTAssertTrue(service.hasRecognitionSession(for: .startPlaceSearch))
        XCTAssertFalse(service.hasRecognitionSession(for: .remark))

        service.cancelRecognitionForLifecycle()

        XCTAssertFalse(service.hasRecognitionSession(for: .startPlaceSearch))
    }

    func testSpeechInputCompletionIncludesFieldTextAndStopReason() {
        let service = SpeechInputService()
        var completion: SpeechInputCompletion?

        service.startRecognitionForTesting(field: .startPlaceSearch) {
            completion = $0
        }
        service.finishRecognitionForTesting(
            text: "大观",
            reason: .silenceTimeout(hadDetectedSound: true)
        )

        XCTAssertFalse(service.isListening)
        XCTAssertNil(service.activeFieldId)
        XCTAssertEqual(completion?.field, .startPlaceSearch)
        XCTAssertEqual(completion?.recognizedText, "大观")
        XCTAssertEqual(completion?.reason, .silenceTimeout(hadDetectedSound: true))
        XCTAssertTrue(completion?.reason.shouldTriggerSearchWithRecognizedText == true)
    }

    func testSpeechInputSwitchingFieldsCompletesPreviousFieldBeforeReplacingHandler() {
        let service = SpeechInputService()
        var startPlaceCompletion: SpeechInputCompletion?
        var notesCompletion: SpeechInputCompletion?

        service.startRecognitionForTesting(field: .startPlaceSearch) {
            startPlaceCompletion = $0
        }
        service.finishRecognitionForTesting(
            text: "大观",
            reason: .silenceTimeout(hadDetectedSound: true)
        )
        service.startRecognitionForTesting(field: .startPlaceSearch) {
            startPlaceCompletion = $0
        }
        service.startRecognitionForTesting(field: .startLocationDescription) {
            notesCompletion = $0
        }

        XCTAssertEqual(startPlaceCompletion?.field, .startPlaceSearch)
        XCTAssertEqual(startPlaceCompletion?.recognizedText, "")
        XCTAssertEqual(startPlaceCompletion?.reason, .manual)
        XCTAssertNil(notesCompletion)
        XCTAssertTrue(service.isListening(for: .startLocationDescription))
    }

    func testSpeechInputSilenceTimeoutClearsActiveField() {
        let service = SpeechInputService()

        service.startRecognitionForTesting(field: .startLocationDescription)
        service.triggerSilenceTimeoutForTesting(hadDetectedSound: false)

        XCTAssertFalse(service.isListening)
        XCTAssertNil(service.activeFieldId)
        XCTAssertEqual(service.lastStopReason, .silenceTimeout(hadDetectedSound: false))
    }

    func testBlindRunnerEmergencyIsAvailableOnlyInProgress() {
        for status in RunOrderStatus.allCases {
            XCTAssertEqual(
                status.canTriggerEmergency(as: .blind),
                status == .inProgress,
                "blind SOS eligibility is wrong for \(status.rawValue)"
            )
        }
    }

    func testVolunteerEmergencyStaysHiddenInEveryStatus() {
        // Not a missing screen: `EmergencyService.triggerEmergency` keys the event on the triggering
        // user, so a volunteer-initiated SOS alerts the volunteer about themselves and escalates to
        // the volunteer's own emergency contacts instead of the blind runner's. Enabling the entry
        // before the backend routes by order participant would silently strand the person at risk.
        for status in RunOrderStatus.allCases {
            XCTAssertFalse(
                status.canTriggerEmergency(as: .volunteer),
                "volunteer SOS must stay hidden in \(status.rawValue)"
            )
        }
    }

    func testUnsetRoleCannotTriggerEmergency() {
        XCTAssertFalse(RunOrderStatus.inProgress.canTriggerEmergency(as: .unset))
    }

    func testEmergencyConfirmationCopyIsFixed() {
        XCTAssertEqual(
            EmergencySafetyCopy.confirmationMessage,
            "是否确认进入求助状态？确认后，本次服务将标记为异常，系统会记录当前订单状态。"
        )
    }

    func testBlindOrderPollingUsesFiveSecondsAndStopsOnTerminalStates() {
        XCTAssertEqual(AppConstants.Timing.orderPollingInterval, 5.0)
        XCTAssertTrue(RunOrderStatus.pendingMatch.shouldPoll)
        XCTAssertTrue(RunOrderStatus.pendingAccept.shouldPoll)
        XCTAssertTrue(RunOrderStatus.driverEnRoute.shouldPoll)
        XCTAssertTrue(RunOrderStatus.driverArrived.shouldPoll)
        XCTAssertTrue(RunOrderStatus.inProgress.shouldPoll)
        XCTAssertTrue(RunOrderStatus.rematching.shouldPoll)
        XCTAssertFalse(RunOrderStatus.completed.shouldPoll)
        XCTAssertFalse(RunOrderStatus.cancelled.shouldPoll)
        XCTAssertFalse(RunOrderStatus.noVolunteer.shouldPoll)
    }

    func testRematchingCopyKeepsBlindRunnerInStableWaitingState() {
        XCTAssertEqual(
            RunOrderStatus.rematching.blindRunnerDescription,
            "正在确认志愿者状态，请稍候；如需更换志愿者，系统会继续处理。"
        )
        XCTAssertEqual(RunOrderStatus.rematching.blindRunnerAnnouncement, "正在确认志愿者状态，请稍候。")
        XCTAssertEqual(VoiceService.statusAnnouncement(for: .rematching), "正在确认志愿者状态，请稍候。")
    }

    func testOrderStatusTerminalStates() {
        XCTAssertTrue(RunOrderStatus.completed.isTerminal)
        XCTAssertTrue(RunOrderStatus.cancelled.isTerminal)
        XCTAssertTrue(RunOrderStatus.noVolunteer.isTerminal)
        XCTAssertFalse(RunOrderStatus.pendingMatch.isTerminal)
        XCTAssertFalse(RunOrderStatus.inProgress.isTerminal)
    }

    func testOrderStatusCancelability() {
        XCTAssertEqual(RunOrderStatus.pendingAccept.displayName, "待出发")

        XCTAssertTrue(RunOrderStatus.pendingMatch.canCancel)
        XCTAssertTrue(RunOrderStatus.pendingAccept.canCancel)
        XCTAssertTrue(RunOrderStatus.rematching.canCancel)
        XCTAssertFalse(RunOrderStatus.inProgress.canCancel)
        XCTAssertFalse(RunOrderStatus.completed.canCancel)
        XCTAssertFalse(RunOrderStatus.cancelled.canCancel)

        XCTAssertTrue(RunOrderStatus.pendingMatch.canBlindRunnerCancel)
        XCTAssertTrue(RunOrderStatus.pendingAccept.canBlindRunnerCancel)
        XCTAssertTrue(RunOrderStatus.rematching.canBlindRunnerCancel)
        XCTAssertFalse(RunOrderStatus.driverEnRoute.canBlindRunnerCancel)
        XCTAssertFalse(RunOrderStatus.driverArrived.canBlindRunnerCancel)
        XCTAssertFalse(RunOrderStatus.inProgress.canBlindRunnerCancel)

        XCTAssertTrue(RunOrderStatus.pendingAccept.canVolunteerCancel)
        XCTAssertTrue(RunOrderStatus.driverEnRoute.canVolunteerCancel)
        XCTAssertTrue(RunOrderStatus.driverArrived.canVolunteerCancel)
        XCTAssertTrue(RunOrderStatus.inProgress.canVolunteerCancel)
        XCTAssertFalse(RunOrderStatus.pendingMatch.canVolunteerCancel)
        XCTAssertFalse(RunOrderStatus.rematching.canVolunteerCancel)
        XCTAssertFalse(RunOrderStatus.completed.canVolunteerCancel)
        XCTAssertFalse(RunOrderStatus.cancelled.canVolunteerCancel)
        XCTAssertFalse(RunOrderStatus.noVolunteer.canVolunteerCancel)

        XCTAssertTrue(RunOrderStatus.pendingAccept.canCancel(as: .blind))
        XCTAssertTrue(RunOrderStatus.pendingAccept.canCancel(as: .volunteer))
        XCTAssertTrue(RunOrderStatus.rematching.canCancel(as: .blind))
        XCTAssertFalse(RunOrderStatus.rematching.canCancel(as: .volunteer))
        XCTAssertFalse(RunOrderStatus.inProgress.canCancel(as: .blind))
        XCTAssertTrue(RunOrderStatus.inProgress.canCancel(as: .volunteer))
        XCTAssertFalse(RunOrderStatus.pendingAccept.canCancel(as: .unset))
    }

    func testMockCancelUsesRoleSpecificBackendContract() async throws {
        do {
            let appState = AppState()
            appState.currentEnvironment = .mock
            let client = appState.apiClient
            let _: EmptyResponse = try await client.post(
                "/api/orders/1/respond",
                body: OrderRespondRequest(action: .accept)
            )
            try await setMockRole(.blind, appState: appState)

            let _: EmptyResponse = try await client.post("/api/orders/1/cancel")
            let detail: OrderDetailResponse = try await client.get("/api/orders/1")

            XCTAssertEqual(detail.status, .cancelled)
        }

        do {
            let appState = AppState()
            appState.currentEnvironment = .mock
            let client = appState.apiClient
            let _: EmptyResponse = try await client.post(
                "/api/orders/1/respond",
                body: OrderRespondRequest(action: .accept)
            )
            try await setMockRole(.volunteer, appState: appState)

            let _: EmptyResponse = try await client.post("/api/orders/1/cancel")
            let rematchingDetail: OrderDetailResponse = try await client.get("/api/orders/1")
            XCTAssertEqual(rematchingDetail.status, .rematching)

            try await setMockRole(.blind, appState: appState)
            let _: EmptyResponse = try await client.post("/api/orders/1/cancel")
            let cancelledDetail: OrderDetailResponse = try await client.get("/api/orders/1")
            XCTAssertEqual(cancelledDetail.status, .cancelled)
        }
    }

    func testMockCancelUsesAppStateRoleWithoutRoleEndpoint() async throws {
        do {
            let appState = AppState()
            appState.currentEnvironment = .mock
            appState.activeRole = .blind
            let client = appState.apiClient

            let _: EmptyResponse = try await client.post("/api/orders/1/cancel")
            let detail: OrderDetailResponse = try await client.get("/api/orders/1")

            XCTAssertEqual(detail.status, .cancelled)
        }

        do {
            let appState = AppState()
            appState.currentEnvironment = .mock
            appState.activeRole = .volunteer
            let client = appState.apiClient
            let _: EmptyResponse = try await client.post(
                "/api/orders/1/respond",
                body: OrderRespondRequest(action: .accept)
            )

            let _: EmptyResponse = try await client.post("/api/orders/1/cancel")
            let detail: OrderDetailResponse = try await client.get("/api/orders/1")

            XCTAssertEqual(detail.status, .rematching)
        }
    }

    func testMockVolunteerCancelMovesActiveServiceStatesToRematching() async throws {
        for status in [RunOrderStatus.driverEnRoute, .driverArrived, .inProgress] {
            let appState = AppState()
            appState.currentEnvironment = .mock
            let client = appState.apiClient
            try await setMockRole(.volunteer, appState: appState)
            let _: EmptyResponse = try await client.post(
                "/api/orders/1/respond",
                body: OrderRespondRequest(action: .accept)
            )
            if [.driverEnRoute, .driverArrived, .inProgress].contains(status) {
                let _: EmptyResponse = try await client.post("/api/orders/1/en-route")
            }
            if [.driverArrived, .inProgress].contains(status) {
                let _: EmptyResponse = try await client.post("/api/orders/1/arrived")
            }
            if status == .inProgress {
                let _: EmptyResponse = try await client.post("/api/orders/1/start-service")
            }

            let beforeCancel: OrderDetailResponse = try await client.get("/api/orders/1")
            XCTAssertEqual(beforeCancel.status, status)

            let _: EmptyResponse = try await client.post("/api/orders/1/cancel")
            let afterCancel: OrderDetailResponse = try await client.get("/api/orders/1")
            XCTAssertEqual(afterCancel.status, .rematching)
        }
    }

    func testPendingAcceptBlindCopyUsesDepartureLanguageAndOrderDetails() {
        let order = makeOrder(orderId: 1, status: .pendingAccept)
        let announcement = order.blindRunnerAnnouncement()

        XCTAssertEqual(RunOrderStatus.pendingAccept.blindRunnerDescription, "志愿者已接单，请按预约时间前往或等待在出发地点。")
        XCTAssertTrue(announcement.contains("志愿者已接单"))
        XCTAssertTrue(announcement.contains("朝阳公园南门"))
        XCTAssertTrue(announcement.contains("志愿者出发后会继续通知你"))
        XCTAssertFalse(announcement.contains("待确认"))
    }

    func testDisplayDateTimeFormatsBackendLocalDateTimeForSpeech() {
        XCTAssertEqual("2026-07-05T15:18:10".displayDateTime, "2026年7月5日 15:18")
    }

    func testBlindVolunteerDistanceUsesVolunteerLocationToStartPoint() {
        let order = makeOrder(orderId: 1, status: .driverEnRoute)
        let volunteerAtStart = CLLocationCoordinate2D(latitude: 39.9342, longitude: 116.4740)

        XCTAssertEqual(order.volunteerDistanceToStartText(from: volunteerAtStart), "距出发地点约 10 米")
        XCTAssertNil(order.volunteerDistanceToStartText(from: nil))

        let noCoordinateOrder = makeOrder(
            orderId: 1,
            status: .driverEnRoute,
            startLatitude: nil,
            startLongitude: nil
        )
        XCTAssertNil(noCoordinateOrder.volunteerDistanceToStartText(from: volunteerAtStart))
    }

    func testBlindRunnerAnnouncementIncludesDistanceForTrackingStates() {
        let distanceText = "距出发地点约 10 米"
        for status in [RunOrderStatus.pendingAccept, .driverEnRoute, .driverArrived] {
            let announcement = makeOrder(orderId: 1, status: status)
                .blindRunnerAnnouncement(distanceText: distanceText)

            XCTAssertTrue(
                announcement.contains(distanceText),
                "\(status.rawValue) announcement should include volunteer distance to the start point"
            )
            XCTAssertFalse(announcement.contains("距您"))
        }
    }

    func testBlindOrderStatusViewModelTracksVolunteerDistanceToStart() {
        let viewModel = BlindOrderStatusViewModel()
        viewModel.order = makeOrder(orderId: 1, status: .driverEnRoute)
        let nowMilliseconds = Int64(Date().timeIntervalSince1970 * 1_000)

        viewModel.handleVolunteerLocationUpdate(WSVolunteerLocationUpdate(
            type: WSMessageType.volunteerLocationUpdate.rawValue,
            orderId: 1,
            lat: 39.9342,
            lng: 116.4740,
            timestamp: nowMilliseconds
        ))

        XCTAssertEqual(viewModel.volunteerDistanceToStartText, "距出发地点约 10 米")

        viewModel.handleVolunteerLocationUpdate(WSVolunteerLocationUpdate(
            type: WSMessageType.volunteerLocationUpdate.rawValue,
            orderId: 2,
            lat: 39.9042,
            lng: 116.4074,
            timestamp: nowMilliseconds
        ))

        XCTAssertEqual(viewModel.volunteerDistanceToStartText, "距出发地点约 10 米")
    }

    func testBlindPeerSampleExpiryUsesLatestSampleAndIgnoresWrongOrder() async throws {
        let viewModel = BlindOrderStatusViewModel(peerFreshness: 0.12)
        viewModel.order = makeOrder(orderId: 31, status: .driverEnRoute)
        let first = RealtimePeerLocationSample(
            orderId: 31,
            ownerRole: .volunteer,
            latitude: 39.9342,
            longitude: 116.4740,
            timestampMilliseconds: Int64(Date().timeIntervalSince1970 * 1_000)
        )
        viewModel.handleVolunteerLocationUpdate(first)
        XCTAssertNotNil(viewModel.latestVolunteerSample)

        try await Task.sleep(nanoseconds: 70_000_000)
        let second = RealtimePeerLocationSample(
            orderId: 31,
            ownerRole: .volunteer,
            latitude: 39.9343,
            longitude: 116.4741,
            timestampMilliseconds: Int64(Date().timeIntervalSince1970 * 1_000)
        )
        viewModel.handleVolunteerLocationUpdate(second)
        viewModel.handleVolunteerLocationUpdate(RealtimePeerLocationSample(
            orderId: 99,
            ownerRole: .volunteer,
            latitude: 31.2,
            longitude: 121.5,
            timestampMilliseconds: Int64(Date().timeIntervalSince1970 * 1_000)
        ))

        try await Task.sleep(nanoseconds: 70_000_000)
        XCTAssertEqual(
            try XCTUnwrap(viewModel.latestVolunteerSample).coordinate.latitude,
            second.latitude,
            accuracy: 0.000_001
        )

        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertNil(viewModel.latestVolunteerSample)
        XCTAssertNil(viewModel.volunteerDistanceToStartText)
    }

    func testBlindPeerSampleStopCancelsExpiry() async throws {
        let viewModel = BlindOrderStatusViewModel(peerFreshness: 0.04)
        viewModel.order = makeOrder(orderId: 32, status: .driverArrived)
        viewModel.handleVolunteerLocationUpdate(RealtimePeerLocationSample(
            orderId: 32,
            ownerRole: .volunteer,
            latitude: 39.9342,
            longitude: 116.4740,
            timestampMilliseconds: Int64(Date().timeIntervalSince1970 * 1_000)
        ))
        viewModel.stopPolling()
        viewModel.handleVolunteerLocationUpdate(RealtimePeerLocationSample(
            orderId: 32,
            ownerRole: .volunteer,
            latitude: 31.2,
            longitude: 121.5,
            timestampMilliseconds: Int64(Date().timeIntervalSince1970 * 1_000)
        ))

        XCTAssertNil(viewModel.latestVolunteerSample)
        try await Task.sleep(nanoseconds: 60_000_000)
        XCTAssertNil(viewModel.latestVolunteerSample)
    }

    func testBlindOrderStatusSuppressesLifecycleAppNotificationSpeech() {
        XCTAssertTrue(BlindOrderStatusViewModel.shouldSuppressDirectNotificationSpeech("测试志愿者已到达，距您100米"))
        XCTAssertTrue(BlindOrderStatusViewModel.shouldSuppressDirectNotificationSpeech("志愿者已出发，距您100米"))
        XCTAssertTrue(BlindOrderStatusViewModel.shouldSuppressDirectNotificationSpeech("服务已开始"))
        XCTAssertTrue(BlindOrderStatusViewModel.shouldSuppressDirectNotificationSpeech("订单已完成"))
        XCTAssertTrue(BlindOrderStatusViewModel.shouldSuppressDirectNotificationSpeech("暂时没有可用志愿者，仍在等待"))
        XCTAssertTrue(BlindOrderStatusViewModel.shouldSuppressDirectNotificationSpeech("已为您匹配志愿者张三，他正在确认行程，请稍候"))
        XCTAssertFalse(BlindOrderStatusViewModel.shouldSuppressDirectNotificationSpeech("紧急联系人已通知"))
    }

    func testBlindRunnerRematchingOrderShowsCancelAction() {
        let statusViewModel = BlindOrderStatusViewModel()
        statusViewModel.order = makeOrder(orderId: 1, status: .rematching)

        XCTAssertTrue(statusViewModel.canShowCancel)

        let homeViewModel = BlindRunnerHomeViewModel()
        homeViewModel.activeOrder = makeOrder(orderId: 1, status: .rematching)

        XCTAssertTrue(homeViewModel.canCancelActiveOrder)
    }

    func testBlindRunnerHomeRepeatStatusIncludesOrderTimeAndLocationContext() {
        let speechService = SpeechService()
        let viewModel = BlindRunnerHomeViewModel()
        viewModel.configure(with: AppState(), speechService: speechService)
        viewModel.activeOrder = makeOrder(orderId: 1, status: .pendingAccept)

        viewModel.repeatCurrentStatus(locationDescription: "订单出发点：朝阳公园南门。当前位置：已获取设备定位。")

        XCTAssertTrue(speechService.lastSpokenText?.contains("志愿者已接单") == true)
        XCTAssertTrue(speechService.lastSpokenText?.contains("预约时间：") == true)
        XCTAssertTrue(speechService.lastSpokenText?.contains("出发地点：朝阳公园南门") == true)
        XCTAssertTrue(speechService.lastVoiceOverAnnouncement?.contains("出发地点：朝阳公园南门") == true)
    }

    func testBlindRunnerInProgressOrderDoesNotShowCancelAction() {
        let statusViewModel = BlindOrderStatusViewModel()
        statusViewModel.order = makeOrder(orderId: 1, status: .inProgress)

        XCTAssertFalse(statusViewModel.canShowCancel)

        let homeViewModel = BlindRunnerHomeViewModel()
        homeViewModel.activeOrder = makeOrder(orderId: 1, status: .inProgress)

        XCTAssertFalse(homeViewModel.canCancelActiveOrder)
    }

    func testFormalOrderStatusRoutingAndFinishEligibility() {
        XCTAssertEqual(RunOrderStatus.pendingMatch.blindRunnerRoute, .tracking)
        XCTAssertEqual(RunOrderStatus.driverArrived.blindRunnerRoute, .tracking)
        XCTAssertEqual(RunOrderStatus.inProgress.blindRunnerRoute, .inService)
        XCTAssertEqual(RunOrderStatus.completed.blindRunnerRoute, .completion)
        XCTAssertEqual(RunOrderStatus.cancelled.blindRunnerRoute, .terminal)

        XCTAssertFalse(RunOrderStatus.driverArrived.canFinishService)
        XCTAssertTrue(RunOrderStatus.inProgress.canFinishService)
        XCTAssertEqual(
            RunOrderStatus.driverArrived.finishBlockedMessage,
            RunOrderStatus.driverArrived.arrivedWaitingCopy
        )
    }

    func testVolunteerAcceptGuardRequiresCompleteProfile() {
        XCTAssertEqual(
            VolunteerOrderActionGuard.acceptBlockMessage(profile: nil),
            "请先完善志愿者资料"
        )

        XCTAssertEqual(
            VolunteerOrderActionGuard.acceptBlockMessage(profile: makeVolunteerProfile(name: "")),
            "请先完善志愿者资料"
        )
    }

    func testVolunteerAcceptGuardRequiresApproval() {
        XCTAssertEqual(
            VolunteerOrderActionGuard.acceptBlockMessage(profile: makeVolunteerProfile()),
            "请先完成志愿者注册流程"
        )

        XCTAssertNil(
            VolunteerOrderActionGuard.acceptBlockMessage(profile: makeApprovedVolunteerProfile())
        )
    }

    func testVolunteerAcceptGuardUsesMainRegistrationStatusBeforeOptionalCertificate() {
        let completedStatus = VolunteerRegistrationStatus(
            currentStepCode: "STEP_4_COMPLETED",
            canAcceptOrders: true
        )

        XCTAssertNil(
            VolunteerOrderActionGuard.acceptBlockMessage(
                profile: makeVolunteerProfile(
                    verificationStatus: "rejected",
                    adminReviewStatus: "pending",
                    isAvailable: true
                ),
                registrationStatus: completedStatus
            )
        )
    }

    func testVolunteerAcceptGuardRequiresLegacyAdminReviewOnlyWithoutRegistrationStatus() {
        XCTAssertEqual(
            VolunteerOrderActionGuard.acceptBlockMessage(
                profile: makeVolunteerProfile(
                    verificationStatus: "approved",
                    adminReviewStatus: "pending",
                    isAvailable: true
                )
            ),
            "请等待管理员审核通过"
        )

        XCTAssertNil(
            VolunteerOrderActionGuard.acceptBlockMessage(
                profile: makeVolunteerProfile(
                    verificationStatus: "approved",
                    adminReviewStatus: nil,
                    isAvailable: true
                )
            )
        )
    }

    func testVolunteerAcceptGuardRequiresAvailability() {
        XCTAssertEqual(
            VolunteerOrderActionGuard.acceptBlockMessage(
                profile: makeApprovedVolunteerProfile(isAvailable: false),
                registrationStatus: VolunteerRegistrationStatus(currentStepCode: "STEP_4_COMPLETED", canAcceptOrders: true)
            ),
            "请先开启可服务状态"
        )
    }

    func testVolunteerAcceptGuardTreatsLegacyTrainingAsCompleteButStillRequiresAvailability() {
        let legacyStatus = VolunteerRegistrationStatus(
            currentStepCode: "STEP_4_TRAINING",
            canAcceptOrders: false,
            step3Completed: true,
            faceVerifyStatus: "APPROVED"
        )

        XCTAssertEqual(
            VolunteerOrderActionGuard.acceptBlockMessage(
                profile: makeVolunteerProfile(isAvailable: false),
                registrationStatus: legacyStatus
            ),
            "请先开启可服务状态"
        )
        XCTAssertTrue(legacyStatus.isRegistrationComplete)
    }

    func testVolunteerProfileFallbackTreatsLegacyTrainingAsComplete() {
        let profile = makeVolunteerProfile(
            registrationStep: "STEP_4_TRAINING",
            canAcceptOrders: false
        )

        XCTAssertTrue(profile.isMainRegistrationCompleteWhenStatusUnavailable)
    }

    func testVolunteerRegistrationReturnHomeCreatesUnavailableProfileSnapshotWhenMissing() {
        let appState = AppState()
        let viewModel = VolunteerRegistrationViewModel()
        viewModel.configure(appState: appState, speechService: SpeechService())
        viewModel.name = "测试志愿者"
        viewModel.applyRegistrationStatus(VolunteerRegistrationStatus(
            currentStepCode: "STEP_4_TRAINING",
            canAcceptOrders: false,
            step3Completed: true,
            faceVerifyStatus: "APPROVED"
        ))

        viewModel.prepareReturnToVolunteerHome()

        XCTAssertEqual(appState.volunteerProfile?.name, "测试志愿者")
        XCTAssertEqual(appState.volunteerProfile?.registrationStep, "STEP_4_TRAINING")
        XCTAssertFalse(appState.volunteerProfile?.isAvailable ?? true)
        XCTAssertFalse(appState.volunteerProfile?.wantsDispatch ?? true)
        XCTAssertTrue(appState.isVolunteerProfileApproved)
    }

    func testAppStateVolunteerComputedPropertiesRequireCompleteApprovedProfile() {
        let appState = AppState()
        appState.volunteerProfile = nil
        XCTAssertFalse(appState.isVolunteerProfileComplete)
        XCTAssertFalse(appState.isVolunteerProfileApproved)

        appState.volunteerProfile = makeVolunteerProfile(name: "")
        XCTAssertFalse(appState.isVolunteerProfileComplete)
        XCTAssertFalse(appState.isVolunteerProfileApproved)

        appState.volunteerProfile = makeVolunteerProfile()
        XCTAssertTrue(appState.isVolunteerProfileComplete)
        XCTAssertFalse(appState.isVolunteerProfileApproved)

        appState.volunteerProfile = makeApprovedVolunteerProfile()
        XCTAssertTrue(appState.isVolunteerProfileComplete)
        XCTAssertTrue(appState.isVolunteerProfileApproved)

        appState.volunteerProfile = makeVolunteerProfile(
            verificationStatus: "approved",
            adminReviewStatus: "pending",
            isAvailable: true
        )
        XCTAssertTrue(appState.isVolunteerProfileComplete)
        XCTAssertFalse(appState.isVolunteerProfileApproved)
    }

    func testVolunteerProfileDecodesAdminReviewStatus() throws {
        let data = #"{"name":"测试志愿者","verificationStatus":"approved","adminReviewStatus":"approved","wantsDispatch":true}"#
            .data(using: .utf8)!
        let profile = try JSONDecoder().decode(VolunteerProfileResponse.self, from: data)

        XCTAssertEqual(profile.adminReviewStatus, "approved")
        XCTAssertTrue(profile.isCertificationApproved)
        XCTAssertTrue(profile.isAdminReviewApprovedWhenAvailable)
        XCTAssertTrue(profile.hasManualDispatchOptIn)
    }

    func testVolunteerInServiceBlocksFinishBeforeInProgress() async throws {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let viewModel = VolunteerInServiceViewModel()
        viewModel.configure(
            with: appState,
            speechService: speechService,
            initialOrder: makeOrder(orderId: 1, status: .driverArrived)
        )

        await viewModel.complete(summary: "")

        XCTAssertEqual(viewModel.errorMessage, RunOrderStatus.driverArrived.arrivedWaitingCopy)
        XCTAssertEqual(speechService.lastSpokenText, RunOrderStatus.driverArrived.arrivedWaitingCopy)
    }

    func testVolunteerInServiceStartsServiceFromDriverArrived() async throws {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let client = appState.apiClient
        try await setMockRole(.volunteer, appState: appState)
        let _: EmptyResponse = try await client.post(
            "/api/orders/1/respond",
            body: OrderRespondRequest(action: .accept)
        )
        let _: EmptyResponse = try await client.post("/api/orders/1/en-route")
        let _: EmptyResponse = try await client.post("/api/orders/1/arrived")
        let detail: OrderDetailResponse = try await client.get("/api/orders/1")

        let viewModel = VolunteerInServiceViewModel()
        viewModel.configure(with: appState, speechService: speechService, initialOrder: detail)

        await viewModel.startService()

        let didConfirmStart = await waitUntil {
            viewModel.order?.status == .inProgress
        }
        XCTAssertTrue(didConfirmStart)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testVolunteerEnRouteUnknownPostResultReleasesSpinnerAndAwaitsConfirmation() async {
        let client = CancellationSuspendingAPIClient()
        let appState = AppState(apiClient: client)
        let speechService = SpeechService()
        let viewModel = VolunteerInServiceViewModel(
            actionDeadlineNanoseconds: 20_000_000,
            confirmationTimeout: 0.2
        )
        viewModel.configure(
            with: appState,
            speechService: speechService,
            initialOrder: makeOrder(orderId: 94, status: .pendingAccept)
        )

        await viewModel.enRoute()

        XCTAssertFalse(viewModel.isPerformingAction)
        await client.awaitCancellation()
        XCTAssertGreaterThanOrEqual(client.cancellationCount, 1)
        XCTAssertEqual(viewModel.transitionState, .awaitingConfirmation(target: .driverEnRoute))
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(
            speechService.lastSpokenText,
            "操作结果尚未确认，正在后台同步状态。请勿重复提交同一操作。"
        )
        XCTAssertEqual(viewModel.order?.status, .pendingAccept)
    }

    func testVolunteerEnRouteSuccessDoesNotWaitForSuspendedConfirmationAndBlocksDuplicatePost() async {
        let initialOrder = makeOrder(orderId: 95, status: .pendingAccept)
        let client = TransitionConfirmationAPIClient(
            confirmation: .suspended,
            order: initialOrder
        )
        let appState = AppState(apiClient: client)
        let speechService = SpeechService()
        let viewModel = VolunteerInServiceViewModel(confirmationTimeout: 0.2)
        viewModel.configure(
            with: appState,
            speechService: speechService,
            initialOrder: initialOrder
        )
        let startedAt = Date()

        await viewModel.enRoute()

        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 0.5)
        XCTAssertFalse(viewModel.isPerformingAction)
        XCTAssertEqual(viewModel.transitionState, .awaitingConfirmation(target: .driverEnRoute))
        XCTAssertEqual(client.postRequestCount, 1)
        XCTAssertEqual(viewModel.order?.status, .pendingAccept)

        await viewModel.enRoute()
        XCTAssertEqual(client.postRequestCount, 1, "Pending conversion must not submit a duplicate POST")
        let didStartConfirmation = await waitUntil { client.getRequestCount == 1 }
        XCTAssertTrue(didStartConfirmation)
        client.releaseSuspendedRequests()
    }

    func testVolunteerEnRouteWebSocketConfirmationWinsOverSuspendedDetailQuery() async {
        let initialOrder = makeOrder(orderId: 96, status: .pendingAccept)
        let client = TransitionConfirmationAPIClient(
            confirmation: .suspended,
            order: initialOrder
        )
        let appState = AppState(apiClient: client)
        let speechService = SpeechService()
        let viewModel = VolunteerInServiceViewModel(confirmationTimeout: 0.2)
        viewModel.configure(with: appState, speechService: speechService, initialOrder: initialOrder)

        await viewModel.enRoute()
        appState.realtimeCoordinator.simulateIncomingEventForTesting(
            .orderStatusChanged(WSOrderStatusChanged(
                type: WSMessageType.orderStatusChanged.rawValue,
                orderId: 96,
                fromStatus: RunOrderStatus.pendingAccept.rawValue,
                toStatus: RunOrderStatus.driverEnRoute.rawValue,
                message: nil,
                ttsText: nil,
                priority: "NORMAL",
                timestamp: "2026-07-23T12:00:00Z"
            ))
        )
        let didConfirm = await waitUntil {
            viewModel.order?.status == .driverEnRoute && viewModel.transitionState == .idle
        }

        XCTAssertTrue(didConfirm)
        XCTAssertFalse(viewModel.isPerformingAction)
        XCTAssertEqual(
            speechService.lastSpokenText,
            SpeechService.statusAnnouncement(for: .driverEnRoute)
        )
        client.releaseSuspendedRequests()
    }

    func testVolunteerEnRoutePollingConfirmationAppliesAuthoritativeStatus() async {
        let initialOrder = makeOrder(orderId: 97, status: .pendingAccept)
        let confirmedOrder = makeOrder(orderId: 97, status: .driverEnRoute)
        let client = TransitionConfirmationAPIClient(
            confirmation: .response,
            order: confirmedOrder
        )
        let appState = AppState(apiClient: client)
        let viewModel = VolunteerInServiceViewModel(confirmationTimeout: 0.2)
        viewModel.configure(with: appState, speechService: SpeechService(), initialOrder: initialOrder)

        await viewModel.enRoute()
        let didConfirm = await waitUntil {
            viewModel.order?.status == .driverEnRoute && viewModel.transitionState == .idle
        }

        XCTAssertTrue(didConfirm)
        XCTAssertEqual(client.postRequestCount, 1)
        XCTAssertEqual(client.getRequestCount, 1)
    }

    func testVolunteerEnRouteConfirmationDelayOffersReadOnlyRetryWithoutReposting() async {
        let initialOrder = makeOrder(orderId: 98, status: .pendingAccept)
        let client = TransitionConfirmationAPIClient(
            confirmation: .suspended,
            order: initialOrder
        )
        let appState = AppState(apiClient: client)
        let viewModel = VolunteerInServiceViewModel(confirmationTimeout: 0.05)
        viewModel.configure(with: appState, speechService: SpeechService(), initialOrder: initialOrder)

        await viewModel.enRoute()
        let didDelay = await waitUntil {
            viewModel.transitionState == .confirmationDelayed(target: .driverEnRoute)
        }

        XCTAssertTrue(didDelay)
        XCTAssertTrue(viewModel.canRetryTransitionConfirmation)
        XCTAssertFalse(viewModel.isPerformingAction)
        XCTAssertEqual(client.postRequestCount, 1)

        viewModel.retryTransitionConfirmation()
        XCTAssertEqual(viewModel.transitionState, .awaitingConfirmation(target: .driverEnRoute))
        let didRetryConfirmation = await waitUntil { client.getRequestCount == 2 }
        XCTAssertTrue(didRetryConfirmation)
        XCTAssertEqual(client.postRequestCount, 1, "Read-only retry must never repeat the state-changing POST")
        client.releaseSuspendedRequests()
    }

    func testVolunteerEnRouteExplicitServerErrorRestoresRetryableAction() async {
        let client = TransitionConfirmationAPIClient(
            postError: .serverError(ErrorResponse(
                code: "ORDER_STATUS_NOT_ALLOWED",
                message: "订单状态不允许该操作"
            )),
            confirmation: .response,
            order: makeOrder(orderId: 99, status: .pendingAccept)
        )
        let appState = AppState(apiClient: client)
        let viewModel = VolunteerInServiceViewModel()
        viewModel.configure(
            with: appState,
            speechService: SpeechService(),
            initialOrder: makeOrder(orderId: 99, status: .pendingAccept)
        )

        await viewModel.enRoute()

        XCTAssertFalse(viewModel.isPerformingAction)
        XCTAssertFalse(viewModel.isTransitionPending)
        if case .failed = viewModel.transitionState {
            // Expected: an explicit backend rejection permits a deliberate retry.
        } else {
            XCTFail("Expected an explicit server error to enter failed state")
        }
        XCTAssertEqual(viewModel.errorMessage, "当前订单状态不允许此操作。")
        XCTAssertEqual(client.postRequestCount, 1)

        await viewModel.enRoute()
        XCTAssertEqual(client.postRequestCount, 2)
    }

    func testVolunteerEnRouteUnauthorizedUsesSessionExpirationFlow() async {
        let client = TransitionConfirmationAPIClient(
            postError: .unauthorized,
            confirmation: .response,
            order: makeOrder(orderId: 100, status: .pendingAccept)
        )
        let appState = AppState(apiClient: client)
        appState.accessToken = "expired-token"
        let viewModel = VolunteerInServiceViewModel()
        viewModel.configure(
            with: appState,
            speechService: SpeechService(),
            initialOrder: makeOrder(orderId: 100, status: .pendingAccept)
        )

        await viewModel.enRoute()

        XCTAssertNil(appState.accessToken)
        XCTAssertEqual(appState.sessionExpirationMessage, "登录已过期，请重新登录。")
        XCTAssertFalse(viewModel.isPerformingAction)
        XCTAssertFalse(viewModel.isTransitionPending)
    }

    func testVolunteerArrivedUnknownPostResultReleasesSpinnerAndAwaitsConfirmation() async {
        let client = CancellationSuspendingAPIClient()
        let appState = AppState(apiClient: client)
        let viewModel = VolunteerInServiceViewModel(
            actionDeadlineNanoseconds: 20_000_000,
            confirmationTimeout: 0.2
        )
        viewModel.configure(
            with: appState,
            speechService: SpeechService(),
            initialOrder: makeOrder(orderId: 104, status: .driverEnRoute)
        )

        await viewModel.arrive()

        XCTAssertFalse(viewModel.isPerformingAction)
        XCTAssertEqual(viewModel.transitionState, .awaitingConfirmation(target: .driverArrived))
        XCTAssertEqual(client.requestCount(for: "/api/orders/104/arrived"), 1)
        XCTAssertEqual(viewModel.order?.status, .driverEnRoute)
    }

    func testVolunteerArrivedSuccessDoesNotWaitForSuspendedConfirmationOrRepost() async {
        let initialOrder = makeOrder(orderId: 105, status: .driverEnRoute)
        let client = TransitionConfirmationAPIClient(
            confirmation: .suspended,
            order: initialOrder
        )
        let appState = AppState(apiClient: client)
        let viewModel = VolunteerInServiceViewModel(confirmationTimeout: 0.2)
        viewModel.configure(with: appState, speechService: SpeechService(), initialOrder: initialOrder)

        await viewModel.arrive()

        XCTAssertFalse(viewModel.isPerformingAction)
        XCTAssertEqual(viewModel.transitionState, .awaitingConfirmation(target: .driverArrived))
        XCTAssertEqual(client.postRequestCount, 1)
        await viewModel.arrive()
        XCTAssertEqual(client.postRequestCount, 1)
        client.releaseSuspendedRequests()
    }

    func testVolunteerArrivedWebSocketConfirmationWinsOverLateOldREST() async {
        let initialOrder = makeOrder(orderId: 106, status: .driverEnRoute)
        let client = TransitionConfirmationAPIClient(
            confirmation: .suspended,
            order: initialOrder
        )
        let appState = AppState(apiClient: client)
        let viewModel = VolunteerInServiceViewModel(confirmationTimeout: 0.3)
        viewModel.configure(with: appState, speechService: SpeechService(), initialOrder: initialOrder)

        await viewModel.arrive()
        appState.realtimeCoordinator.simulateIncomingEventForTesting(
            .orderStatusChanged(WSOrderStatusChanged(
                type: WSMessageType.orderStatusChanged.rawValue,
                orderId: 106,
                fromStatus: RunOrderStatus.driverEnRoute.rawValue,
                toStatus: RunOrderStatus.driverArrived.rawValue,
                message: nil,
                ttsText: nil,
                priority: "NORMAL",
                timestamp: "2026-07-28T11:00:00Z"
            ))
        )
        let didConfirmRealtimeArrival = await waitUntil {
            viewModel.order?.status == .driverArrived && viewModel.transitionState == .idle
        }
        XCTAssertTrue(didConfirmRealtimeArrival)

        client.releaseSuspendedRequests()
        try? await Task.sleep(nanoseconds: 30_000_000)
        XCTAssertEqual(viewModel.order?.status, .driverArrived)
        XCTAssertFalse(viewModel.isPerformingAction)
    }

    func testVolunteerArrivedRESTConfirmationAppliesAuthoritativeStatus() async {
        let client = TransitionConfirmationAPIClient(
            confirmation: .response,
            order: makeOrder(orderId: 107, status: .driverArrived)
        )
        let appState = AppState(apiClient: client)
        let viewModel = VolunteerInServiceViewModel(confirmationTimeout: 0.2)
        viewModel.configure(
            with: appState,
            speechService: SpeechService(),
            initialOrder: makeOrder(orderId: 107, status: .driverEnRoute)
        )

        await viewModel.arrive()

        let didConfirmRESTArrival = await waitUntil {
            viewModel.order?.status == .driverArrived && viewModel.transitionState == .idle
        }
        XCTAssertTrue(didConfirmRESTArrival)
        XCTAssertEqual(client.postRequestCount, 1)
        XCTAssertEqual(client.getRequestCount, 1)
    }

    func testVolunteerArrivedExplicitServerErrorRestoresRetryableAction() async {
        let client = TransitionConfirmationAPIClient(
            postError: .serverError(ErrorResponse(
                code: "ORDER_STATUS_NOT_ALLOWED",
                message: "订单状态不允许该操作"
            )),
            confirmation: .response,
            order: makeOrder(orderId: 108, status: .driverEnRoute)
        )
        let appState = AppState(apiClient: client)
        let viewModel = VolunteerInServiceViewModel()
        viewModel.configure(
            with: appState,
            speechService: SpeechService(),
            initialOrder: makeOrder(orderId: 108, status: .driverEnRoute)
        )

        await viewModel.arrive()

        XCTAssertFalse(viewModel.isPerformingAction)
        XCTAssertFalse(viewModel.isTransitionPending)
        XCTAssertEqual(viewModel.errorMessage, "当前订单状态不允许此操作。")
        await viewModel.arrive()
        XCTAssertEqual(client.postRequestCount, 2)
    }

    func testVolunteerBlindPeerSampleExpiresAndWrongOrderCannotClearIt() async throws {
        let viewModel = VolunteerInServiceViewModel(peerFreshness: 0.06)
        viewModel.order = makeOrder(orderId: 109, status: .driverEnRoute)
        let sample = RealtimePeerLocationSample(
            orderId: 109,
            ownerRole: .blind,
            latitude: 39.9342,
            longitude: 116.4740,
            timestampMilliseconds: Int64(Date().timeIntervalSince1970 * 1_000)
        )
        viewModel.handleBlindLocationUpdate(sample)
        viewModel.handleBlindLocationUpdate(RealtimePeerLocationSample(
            orderId: 999,
            ownerRole: .blind,
            latitude: 31.2,
            longitude: 121.5,
            timestampMilliseconds: Int64(Date().timeIntervalSince1970 * 1_000)
        ))

        XCTAssertEqual(
            try XCTUnwrap(viewModel.latestBlindSample).coordinate.latitude,
            sample.latitude,
            accuracy: 0.000_001
        )
        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertNil(viewModel.latestBlindSample)
    }

    func testVolunteerInServiceBlocksStartServiceOutsideDriverArrived() async {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let viewModel = VolunteerInServiceViewModel()
        viewModel.configure(
            with: appState,
            speechService: speechService,
            initialOrder: makeOrder(orderId: 1, status: .inProgress)
        )

        await viewModel.startService()

        XCTAssertEqual(viewModel.order?.status, .inProgress)
        XCTAssertEqual(viewModel.errorMessage, RunOrderStatus.inProgress.startServiceBlockedMessage)
        XCTAssertEqual(speechService.lastSpokenText, RunOrderStatus.inProgress.startServiceBlockedMessage)
    }

    func testVolunteerInServiceAllowsFinishFromInProgressAndRefreshesSummary() async throws {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let client = appState.apiClient
        try await setMockRole(.volunteer, appState: appState)
        let _: EmptyResponse = try await client.post(
            "/api/orders/1/respond",
            body: OrderRespondRequest(action: .accept)
        )
        let _: EmptyResponse = try await client.post("/api/orders/1/en-route")
        let _: EmptyResponse = try await client.post("/api/orders/1/arrived")
        let _: EmptyResponse = try await client.post("/api/orders/1/start-service")
        let detail: OrderDetailResponse = try await client.get("/api/orders/1")

        let viewModel = VolunteerInServiceViewModel()
        viewModel.configure(with: appState, speechService: speechService, initialOrder: detail)

        await viewModel.complete(summary: "已完成")

        let didConfirmCompletion = await waitUntil {
            viewModel.order?.status == .completed
                && viewModel.dispatchSummary?.completedCount == 2
                && viewModel.dispatchSummary?.resolvedPointsBalance == 200
        }
        XCTAssertTrue(didConfirmCompletion)
    }

    func testVolunteerInServiceCancelClearsLocalOrderWithoutDetailFetch() async throws {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let client = appState.apiClient
        try await setMockRole(.volunteer, appState: appState)
        let _: EmptyResponse = try await client.post(
            "/api/orders/1/respond",
            body: OrderRespondRequest(action: .accept)
        )
        let _: EmptyResponse = try await client.post("/api/orders/1/en-route")
        let _: EmptyResponse = try await client.post("/api/orders/1/arrived")
        let _: EmptyResponse = try await client.post("/api/orders/1/start-service")
        let detail: OrderDetailResponse = try await client.get("/api/orders/1")

        let viewModel = VolunteerInServiceViewModel()
        viewModel.configure(with: appState, speechService: speechService, initialOrder: detail)

        await viewModel.cancel()

        let didConfirmCancellation = await waitUntil {
            viewModel.didCancelOrder && viewModel.order == nil
        }
        XCTAssertTrue(didConfirmCancellation)
        XCTAssertNil(viewModel.order)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(speechService.lastSpokenText, "订单已取消，系统将为盲人重新匹配。")
    }

    func testVolunteerTravelStageUsesDepartureCopyBeforeArrival() {
        XCTAssertEqual(RunOrderStatus.pendingAccept.serviceStageTitle, "前往出发地点")
        XCTAssertEqual(RunOrderStatus.driverEnRoute.serviceStageTitle, "前往出发地点")
        XCTAssertEqual(RunOrderStatus.driverArrived.serviceStageTitle, "已到达集合地点")
        XCTAssertEqual(RunOrderStatus.inProgress.serviceStageTitle, "服务进行中")
        XCTAssertEqual(
            RunOrderStatus.pendingAccept.serviceStageSubtitle,
            "请确认当前位置和出发地点，可使用外部地图步行导航"
        )
    }

    func testVolunteerServiceActionKindsMatchFormalStateMachine() {
        XCTAssertEqual(
            VolunteerServiceActions.actionKinds(for: .pendingAccept).map(\.title),
            ["导航到出发地点", "我已出发", "取消订单"]
        )
        XCTAssertEqual(
            VolunteerServiceActions.actionKinds(for: .driverEnRoute).map(\.title),
            ["导航到出发地点", "我已到达约定地点", "取消订单"]
        )
        XCTAssertEqual(
            VolunteerServiceActions.actionKinds(for: .driverArrived).map(\.title),
            ["开始服务", "取消订单"]
        )
        XCTAssertEqual(
            VolunteerServiceActions.actionKinds(for: .inProgress).map(\.title),
            ["结束服务", "取消订单"]
        )
    }

    func testVolunteerServicePendingAcceptUsesDepartureCopy() {
        XCTAssertEqual(RunOrderStatus.pendingAccept.volunteerServiceDisplayName, "待出发")
        XCTAssertEqual(RunOrderStatus.driverEnRoute.volunteerServiceDisplayName, "志愿者出发中")
    }

    func testAMapWrappersHideCompassByDefault() {
        let coordinate = CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074)

        XCTAssertFalse(AMapContainer(centerCoordinate: coordinate).showsCompass)
        XCTAssertFalse(MapViewWrapper(centerCoordinate: coordinate).showsCompass)
    }

    func testVolunteerServiceMapAnchorUsesTopVisibleAreaAbovePanel() {
        let anchor = VolunteerServiceMapLayout.screenAnchorY(
            viewportHeight: 852,
            topSafeAreaInset: 47,
            bottomPanelMaxHeight: 852 * 0.62
        )

        XCTAssertLessThan(anchor, 0.3)
        XCTAssertGreaterThan(anchor, 0.18)
        XCTAssertEqual(anchor, 0.2170, accuracy: 0.001)
        XCTAssertEqual(
            VolunteerServiceMapLayout.screenAnchorY(
                viewportHeight: 100,
                topSafeAreaInset: 0,
                bottomPanelMaxHeight: 90
            ),
            0.18,
            accuracy: 0.0001
        )
    }

    func testVolunteerServiceMapPresentationUsesStartMarkerAsPrimaryMarker() {
        let current = CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074)
        let order = makeOrder(orderId: 1, status: .pendingAccept)

        let presentation = VolunteerServiceMapPresentation(
            order: order,
            currentLocation: current,
            locationAuthorized: true,
            fallbackCoordinate: current
        )

        XCTAssertEqual(presentation.annotations.count, 1)
        XCTAssertEqual(presentation.annotations[0].title, "出发地点")
        XCTAssertEqual(presentation.annotations[0].kind, .orderStart)
        XCTAssertTrue(presentation.isCurrentLocationAvailable)
        XCTAssertFalse(presentation.hasCurrentLocationMarker)
        XCTAssertEqual(presentation.centerCoordinate.latitude, 39.9342, accuracy: 0.000001)
        XCTAssertEqual(presentation.centerCoordinate.longitude, 116.4740, accuracy: 0.000001)
    }

    func testVolunteerServiceMapPresentationCanShowCurrentAndStartMarkers() {
        let current = CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074)
        let order = makeOrder(orderId: 1, status: .pendingAccept)

        let presentation = VolunteerServiceMapPresentation(
            order: order,
            currentLocation: current,
            locationAuthorized: true,
            fallbackCoordinate: current,
            includesCurrentLocationMarker: true,
            centersOnCurrentAndStart: true
        )

        XCTAssertEqual(presentation.annotations.count, 2)
        XCTAssertEqual(presentation.annotations[0].kind, .currentLocation)
        XCTAssertEqual(presentation.annotations[1].kind, .orderStart)
        XCTAssertTrue(presentation.hasCurrentLocationMarker)
        let normalizedCurrent = BackendCoordinateNormalizer.wgs84ToGCJ02(current)
        XCTAssertEqual(
            presentation.centerCoordinate.latitude,
            (normalizedCurrent.latitude + 39.9342) / 2,
            accuracy: 0.000001
        )
        XCTAssertEqual(
            presentation.centerCoordinate.longitude,
            (normalizedCurrent.longitude + 116.4740) / 2,
            accuracy: 0.000001
        )
    }

    func testVolunteerServiceMapPresentationCanPinCenterOnStartWithCurrentMarker() {
        let current = CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074)
        let order = makeOrder(orderId: 1, status: .pendingAccept)

        let presentation = VolunteerServiceMapPresentation(
            order: order,
            currentLocation: current,
            locationAuthorized: true,
            fallbackCoordinate: current,
            includesCurrentLocationMarker: true,
            centersOnCurrentAndStart: false
        )

        XCTAssertEqual(presentation.annotations.count, 2)
        XCTAssertEqual(presentation.annotations[0].kind, .currentLocation)
        XCTAssertEqual(presentation.annotations[1].kind, .orderStart)
        XCTAssertTrue(presentation.hasCurrentLocationMarker)
        XCTAssertEqual(presentation.centerCoordinate.latitude, 39.9342, accuracy: 0.000001)
        XCTAssertEqual(presentation.centerCoordinate.longitude, 116.4740, accuracy: 0.000001)
    }

    func testVolunteerServiceMapPresentationShowsOnlyCurrentLocationWhenOrderCoordinatesMissing() {
        let current = CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074)
        let order = makeOrder(
            orderId: 1,
            status: .pendingAccept,
            startLatitude: nil,
            startLongitude: nil
        )

        let presentation = VolunteerServiceMapPresentation(
            order: order,
            currentLocation: current,
            locationAuthorized: true,
            fallbackCoordinate: current,
            includesCurrentLocationMarker: true,
            centersOnCurrentAndStart: true
        )

        XCTAssertEqual(presentation.annotations.count, 1)
        XCTAssertEqual(presentation.annotations[0].kind, .currentLocation)
        XCTAssertFalse(presentation.annotations.contains { $0.kind == .orderStart })
        let normalizedCurrent = BackendCoordinateNormalizer.wgs84ToGCJ02(current)
        XCTAssertEqual(presentation.centerCoordinate.latitude, normalizedCurrent.latitude, accuracy: 0.000001)
        XCTAssertEqual(presentation.centerCoordinate.longitude, normalizedCurrent.longitude, accuracy: 0.000001)
    }

    func testVolunteerDispatchMapPresentationUsesSystemCurrentLocationLayerAndStartMarker() {
        let current = CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074)
        let order = makeDispatchOrder(orderId: 1)

        let presentation = VolunteerServiceMapPresentation(
            dispatchOrder: order,
            currentLocation: current,
            locationAuthorized: true,
            fallbackCoordinate: current
        )

        XCTAssertEqual(presentation.annotations.count, 1)
        XCTAssertEqual(presentation.annotations[0].title, "出发地点")
        XCTAssertEqual(presentation.annotations[0].kind, .orderStart)
        XCTAssertTrue(presentation.isCurrentLocationAvailable)
        XCTAssertFalse(presentation.hasCurrentLocationMarker)
        XCTAssertEqual(presentation.centerCoordinate.latitude, 39.9342, accuracy: 0.000001)
        XCTAssertEqual(presentation.centerCoordinate.longitude, 116.4740, accuracy: 0.000001)
    }

    func testVolunteerServiceMapPresentationFallsBackToStartMarkerWithoutLocation() {
        let fallback = CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074)
        let order = makeOrder(orderId: 1, status: .driverEnRoute)

        let presentation = VolunteerServiceMapPresentation(
            order: order,
            currentLocation: nil,
            locationAuthorized: false,
            fallbackCoordinate: fallback
        )

        XCTAssertEqual(presentation.annotations.count, 1)
        XCTAssertEqual(presentation.annotations[0].kind, .orderStart)
        XCTAssertFalse(presentation.isCurrentLocationAvailable)
        XCTAssertFalse(presentation.hasCurrentLocationMarker)
        XCTAssertEqual(presentation.centerCoordinate.latitude, 39.9342, accuracy: 0.000001)
        XCTAssertEqual(presentation.centerCoordinate.longitude, 116.4740, accuracy: 0.000001)
    }

    func testExternalMapNavigationAvailabilityFiltersThirdPartySchemes() {
        let providers = ExternalMapNavigationAvailability.availableProviders { url in
            url.scheme == "iosamap"
        }

        XCTAssertEqual(providers, [.amap, .appleMaps])
    }

    func testAMapWalkingURLIncludesOriginDestinationAndWalkingMode() throws {
        let request = makeNavigationRequest()

        let url = try XCTUnwrap(ExternalMapNavigationURLBuilder.amapWalkingURL(request: request))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = try XCTUnwrap(components.queryItems).reduce(into: [String: String]()) { result, item in
            result[item.name] = item.value
        }

        XCTAssertEqual(components.scheme, "iosamap")
        XCTAssertEqual(components.host, "path")
        XCTAssertEqual(query["slat"], "39.904200")
        XCTAssertEqual(query["slon"], "116.407400")
        XCTAssertEqual(query["sname"], "我的位置")
        XCTAssertEqual(query["dlat"], "39.934200")
        XCTAssertEqual(query["dlon"], "116.474000")
        XCTAssertEqual(query["dname"], "朝阳公园南门")
        XCTAssertEqual(query["t"], "2")
        XCTAssertEqual(query["dev"], "0")
    }

    func testBaiduWalkingURLIncludesGCJ02WalkingDirections() throws {
        let request = makeNavigationRequest()

        let url = try XCTUnwrap(ExternalMapNavigationURLBuilder.baiduWalkingURL(request: request))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query = try XCTUnwrap(components.queryItems).reduce(into: [String: String]()) { result, item in
            result[item.name] = item.value
        }

        XCTAssertEqual(components.scheme, "baidumap")
        XCTAssertEqual(components.host, "map")
        XCTAssertEqual(components.path, "/direction")
        XCTAssertEqual(query["mode"], "walking")
        XCTAssertEqual(query["coord_type"], "gcj02")
        XCTAssertEqual(query["origin"], "latlng:39.904200,116.407400|name:我的位置")
        XCTAssertEqual(query["destination"], "latlng:39.934200,116.474000|name:朝阳公园南门")
    }

    func testBlindRunnerActiveOrderPollingIntervalStaysFiveSeconds() {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let viewModel = BlindOrderStatusViewModel()
        viewModel.configure(appState: appState, speechService: SpeechService())
        viewModel.order = makeOrder(orderId: 1, status: .inProgress)

        XCTAssertEqual(viewModel.effectivePollingInterval, AppConstants.Timing.orderPollingInterval)
    }

    func testBlindRunnerCompletedOrderSubmitsReviewRequest() async throws {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let viewModel = BlindOrderStatusViewModel()
        viewModel.configure(appState: appState, speechService: speechService)
        viewModel.order = makeOrder(orderId: 2, status: .completed)
        viewModel.reviewRating = 5
        viewModel.reviewComment = "体验很好"

        await viewModel.submitReview()

        XCTAssertTrue(viewModel.didSubmitReview)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(speechService.lastSpokenText, "评价已提交，感谢反馈。")
    }

    /// 后端 2026-07-31 起把「已评价过此订单」从 `DUPLICATE_ORDER` 拆成专用码
    /// `REVIEW_ALREADY_SUBMITTED`。此前两个语义共用一个码，重复评价会被念成
    /// 「您已有进行中的订单」这句完全不相干的话（对只靠语音的用户是纯误导）。
    /// 这条用例是防退回门：重复评价必须念「已评价」，且**绝不能**出现「进行中的订单」。
    func testDuplicateReviewIsTreatedAsAlreadyReviewedNotInProgressOrderCopy() async {
        let client = FailingAPIClient(error: APIError.serverError(
            ErrorResponse(code: "REVIEW_ALREADY_SUBMITTED", message: "已评价过此订单")
        ))
        let appState = AppState(apiClient: client)
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let viewModel = BlindOrderStatusViewModel()
        viewModel.configure(appState: appState, speechService: speechService)
        viewModel.order = makeOrder(orderId: 3, status: .completed)
        viewModel.reviewRating = 5

        await viewModel.submitReview()

        // 已评价不是失败：页面切到已评价态，不显示错误。
        XCTAssertTrue(viewModel.didSubmitReview)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(speechService.lastSpokenText, "您已评价过此订单。")
        XCTAssertFalse(
            (speechService.lastSpokenText ?? "").contains("进行中的订单"),
            "重复评价被念成了下单受阻的文案"
        )
    }

    /// 拆码后两个码各说各话：`DUPLICATE_ORDER` 只剩下单场景，文案必须重新提到「进行中的订单」；
    /// 且不得再有「以后端 message 为准」的止血补丁——本地文案就是权威。
    func testDuplicateOrderAndReviewAlreadySubmittedCarryDistinctCopy() {
        XCTAssertTrue(
            ErrorCode.duplicateOrder.localizedMessage.contains("进行中的订单"),
            "DUPLICATE_ORDER 已是单义码（仅下单场景），文案不应再是场景中立的兜底"
        )
        XCTAssertTrue(ErrorCode.reviewAlreadySubmitted.localizedMessage.contains("评价"))
        XCTAssertNotEqual(
            ErrorCode.duplicateOrder.localizedMessage,
            ErrorCode.reviewAlreadySubmitted.localizedMessage
        )

        // 止血补丁撤除后，本地文案不再被后端 message 顶掉。
        let error = APIError.serverError(
            ErrorResponse(code: "DUPLICATE_ORDER", message: "您有进行中的订单，请完成后再下单")
        )
        XCTAssertEqual(error.localizedMessage, ErrorCode.duplicateOrder.localizedMessage)
    }

    func testBlindRunnerRepeatStatusSpeaksInServiceState() {
        let appState = AppState()
        appState.currentEnvironment = .mock
        let speechService = SpeechService()
        let viewModel = BlindOrderStatusViewModel()
        viewModel.configure(appState: appState, speechService: speechService)
        viewModel.order = makeOrder(orderId: 1, status: .inProgress)

        viewModel.repeatStatus()

        XCTAssertEqual(speechService.lastSpokenText, RunOrderStatus.inProgress.blindRunnerAnnouncement)
    }

    func testBlindRunnerHomeAppliesRealtimeStatusWhileBackgroundRefreshIsSuspended() async {
        let client = CancellationSuspendingAPIClient()
        let appState = AppState(apiClient: client)
        let speechService = SpeechService()
        let initialOrder = makeOrder(orderId: 703, status: .pendingAccept)
        let viewModel = BlindRunnerHomeViewModel(loadTimeout: 0.2)
        viewModel.configure(with: appState, speechService: speechService)
        viewModel.activeOrder = initialOrder
        appState.liveEscortCoordinator.updateOwnedOrder(
            orderID: initialOrder.orderId,
            status: initialOrder.status
        )
        let refresh = Task { await viewModel.loadActiveOrder() }
        _ = await waitUntil { client.requestCount(for: "/api/orders/mine") == 1 }

        appState.realtimeCoordinator.simulateIncomingEventForTesting(
            .orderStatusChanged(WSOrderStatusChanged(
                type: WSMessageType.orderStatusChanged.rawValue,
                orderId: initialOrder.orderId,
                fromStatus: RunOrderStatus.pendingAccept.rawValue,
                toStatus: RunOrderStatus.driverEnRoute.rawValue,
                message: nil,
                ttsText: nil,
                priority: "HIGH",
                timestamp: "2026-07-23T12:00:00Z"
            ))
        )
        let didApply = await waitUntil {
            viewModel.activeOrder?.status == .driverEnRoute
        }

        XCTAssertTrue(didApply)
        XCTAssertEqual(
            speechService.lastSpokenText,
            viewModel.activeOrder?.blindRunnerAnnouncement()
        )
        XCTAssertEqual(viewModel.currentStatusText.contains("志愿者出发中"), true)

        refresh.cancel()
        await refresh.value
        XCTAssertEqual(viewModel.activeOrder?.status, .driverEnRoute)
    }

    func testBlindOrderStatusAppliesRealtimeEnRouteWhileDetailQueryIsSuspended() async {
        let initialOrder = makeOrder(orderId: 704, status: .pendingAccept)
        let client = TransitionConfirmationAPIClient(
            confirmation: .suspended,
            order: initialOrder
        )
        let appState = AppState(apiClient: client)
        let speechService = SpeechService()
        let viewModel = BlindOrderStatusViewModel()
        viewModel.configure(appState: appState, speechService: speechService)
        viewModel.order = initialOrder
        viewModel.startPolling(orderId: initialOrder.orderId)
        let didStartPolling = await waitUntil { client.getRequestCount == 1 }
        XCTAssertTrue(didStartPolling)

        appState.realtimeCoordinator.simulateIncomingEventForTesting(
            .orderStatusChanged(WSOrderStatusChanged(
                type: WSMessageType.orderStatusChanged.rawValue,
                orderId: initialOrder.orderId,
                fromStatus: RunOrderStatus.pendingAccept.rawValue,
                toStatus: RunOrderStatus.driverEnRoute.rawValue,
                message: nil,
                ttsText: nil,
                priority: "HIGH",
                timestamp: "2026-07-23T12:00:00Z"
            ))
        )
        let didApply = await waitUntil {
            viewModel.order?.status == .driverEnRoute && !viewModel.isLoading
        }

        XCTAssertTrue(didApply)
        XCTAssertEqual(
            speechService.lastSpokenText,
            SpeechService.statusAnnouncement(for: .driverEnRoute)
        )

        client.releaseSuspendedRequests()
        let didDiscardLateRegression = await waitUntil {
            viewModel.order?.status == .driverEnRoute
        }
        XCTAssertTrue(didDiscardLateRegression)
        viewModel.stopPolling()
    }

    // MARK: - Helpers

    private func makeDispatchOrder(orderId: Int64) -> WSNewOrder {
        WSNewOrder(
            type: "NEW_ORDER",
            timestamp: "2026-06-25T19:30:00",
            orderId: orderId,
            startAddress: "朝阳公园南门",
            startLatitude: 39.9342,
            startLongitude: 116.4740,
            distanceKm: 0.1,
            plannedStart: "2026-06-25T20:00:00",
            plannedEnd: "2026-06-25T21:00:00",
            dispatchTimeoutSeconds: 30,
            priority: "HIGH",
            pacePreference: "MODERATE",
            hasGuideDog: false,
            specialNotes: nil
        )
    }

    private func makeOrder(
        orderId: Int64,
        status: RunOrderStatus,
        createdAt: String = "2026-06-25T10:00:00Z",
        startLatitude: Double? = 39.9342,
        startLongitude: Double? = 116.4740
    ) -> OrderDetailResponse {
        OrderDetailResponse(
            orderId: orderId,
            status: status,
            startAddress: "朝阳公园南门",
            startLatitude: startLatitude,
            startLongitude: startLongitude,
            plannedStart: "2026-06-25T20:00:00Z",
            plannedEnd: "2026-06-25T21:00:00Z",
            blindName: "李明",
            blindPhone: status == .pendingMatch ? nil : "13800001001",
            volunteerPhone: status == .pendingMatch ? nil : "13800000002",
            acceptedAt: status == .pendingMatch ? nil : "2026-06-25T19:50:00Z",
            createdAt: createdAt,
            expectedDurationMinutes: 60,
            pacePreference: .moderate,
            routePreference: .parkTrail,
            routeNotes: nil,
            hasGuideDogThisRun: false,
            specialNotes: nil,
            visionLevel: "TOTAL_BLIND",
            tetherPreference: "TETHER_ROPE",
            chatPreference: "PREFER_CHAT"
        )
    }

    private func makeNavigationRequest() -> ExternalMapNavigationRequest {
        ExternalMapNavigationRequest(
            originCoordinate: CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074),
            originName: "我的位置",
            destinationCoordinate: CLLocationCoordinate2D(latitude: 39.9342, longitude: 116.4740),
            destinationName: "朝阳公园南门"
        )
    }

    private func waitUntil(
        timeout: TimeInterval = 2,
        condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return condition()
    }

    private func setMockRole(_ role: UserRole, appState: AppState) async throws {
        appState.switchRole(to: role)
        let _: SetRoleResponse = try await appState.apiClient.post(
            "/api/user/role",
            body: SetRoleRequest(role: role)
        )
    }

    private final class RootHydrationAPIClient: APIClientProtocol, @unchecked Sendable {
        private let firstRequestDelay: TimeInterval
        private var profileRequestCount = 0
        private(set) var cancellationCount = 0

        init(firstRequestDelay: TimeInterval = 0) {
            self.firstRequestDelay = firstRequestDelay
        }

        func request<T: Decodable>(
            method: HTTPMethod,
            path: String,
            query: [String: String]?,
            body: (any Encodable & Sendable)?,
            requiresAuth: Bool
        ) async throws -> T {
            guard method == .get else { throw APIError.invalidURL }

            if path == "/api/blind/profile" {
                profileRequestCount += 1
                let account = profileRequestCount
                if account == 1, firstRequestDelay > 0 {
                    do {
                        try await Task.sleep(nanoseconds: UInt64(firstRequestDelay * 1_000_000_000))
                    } catch {
                        cancellationCount += 1
                        throw error
                    }
                }
                // 已实名：这两个用例断言的是「水合完成后只提交一个终点 .blindHome」，
                // 所以 fixture 必须是引导流全部走完的账号，否则会停在实名软提示那一步。
                let data = Data("{\"name\":\"账号\(account)\",\"verifyStatus\":\"VERIFIED\"}".utf8)
                return try JSONDecoder().decode(T.self, from: data)
            }

            if path.contains("/emergency-contacts") {
                let account = path.contains("/users/2/") ? 2 : 1
                if account == 1, firstRequestDelay > 0 {
                    do {
                        try await Task.sleep(nanoseconds: UInt64(firstRequestDelay * 1_000_000_000))
                    } catch {
                        cancellationCount += 1
                        throw error
                    }
                }
                let data = Data("[{\"id\":\(account),\"name\":\"联系人\",\"phone\":\"13800138000\",\"isPrimary\":true}]".utf8)
                return try JSONDecoder().decode(T.self, from: data)
            }

            throw APIError.invalidURL
        }

        func upload<T: Decodable>(
            path: String,
            query: [String: String]?,
            fields: [String: String]?,
            files: [MultipartFile],
            requiresAuth: Bool
        ) async throws -> T {
            throw APIError.invalidURL
        }
    }

    private final class FailingAPIClient: APIClientProtocol, @unchecked Sendable {
        private let error: Error

        init(error: Error) {
            self.error = error
        }

        func request<T: Decodable>(
            method: HTTPMethod,
            path: String,
            query: [String: String]?,
            body: (any Encodable & Sendable)?,
            requiresAuth: Bool
        ) async throws -> T {
            throw error
        }

        func upload<T: Decodable>(
            path: String,
            query: [String: String]?,
            fields: [String: String]?,
            files: [MultipartFile],
            requiresAuth: Bool
        ) async throws -> T {
            throw error
        }
    }

    private final class CancellationSuspendingAPIClient: APIClientProtocol, @unchecked Sendable {
        private let lock = NSLock()
        private var cancellations = 0
        private var requestCounts: [String: Int] = [:]
        private var cancellationWaiters: [CheckedContinuation<Void, Never>] = []

        var cancellationCount: Int {
            lock.withLock { cancellations }
        }

        func requestCount(for path: String) -> Int {
            lock.withLock { requestCounts[path, default: 0] }
        }

        /// Suspends until an in-flight request has actually observed cancellation.
        ///
        /// `HomeLoadCoordinator` intentionally resumes its caller the moment the
        /// deadline fires and never awaits the losing operation, so the cancelled
        /// request records itself on a different task. Asserting on
        /// `cancellationCount` straight after the deadline therefore races the
        /// scheduler. Awaiting this signal makes the assertion causal instead of
        /// wall-clock dependent; it resumes immediately when a cancellation has
        /// already been recorded.
        func awaitCancellation() async {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                lock.lock()
                if cancellations > 0 {
                    lock.unlock()
                    continuation.resume()
                    return
                }
                cancellationWaiters.append(continuation)
                lock.unlock()
            }
        }

        func request<T: Decodable>(
            method: HTTPMethod,
            path: String,
            query: [String: String]?,
            body: (any Encodable & Sendable)?,
            requiresAuth: Bool
        ) async throws -> T {
            lock.withLock { requestCounts[path, default: 0] += 1 }
            do {
                try await Task.sleep(nanoseconds: 60_000_000_000)
            } catch {
                lock.lock()
                cancellations += 1
                let waiters = cancellationWaiters
                cancellationWaiters.removeAll()
                lock.unlock()
                for waiter in waiters {
                    waiter.resume()
                }
                throw error
            }
            throw APIError.invalidURL
        }

        func upload<T: Decodable>(
            path: String,
            query: [String: String]?,
            fields: [String: String]?,
            files: [MultipartFile],
            requiresAuth: Bool
        ) async throws -> T {
            throw APIError.invalidURL
        }
    }

    private final class ControlledNonCooperativeAPIClient: APIClientProtocol, @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: UnsafeContinuation<Void, Never>?
        private var started = false
        private var returnedLateResponse = false

        var hasStarted: Bool {
            lock.withLock { started }
        }

        var didReturnLateResponse: Bool {
            lock.withLock { returnedLateResponse }
        }

        func release() {
            let continuation = lock.withLock { () -> UnsafeContinuation<Void, Never>? in
                defer { self.continuation = nil }
                return self.continuation
            }
            continuation?.resume()
        }

        func request<T: Decodable>(
            method: HTTPMethod,
            path: String,
            query: [String: String]?,
            body: (any Encodable & Sendable)?,
            requiresAuth: Bool
        ) async throws -> T {
            lock.withLock { started = true }
            await withUnsafeContinuation { continuation in
                lock.withLock { self.continuation = continuation }
            }
            lock.withLock { returnedLateResponse = true }
            return try JSONDecoder().decode(T.self, from: Data(#"{"content":[]}"#.utf8))
        }

        func upload<T: Decodable>(
            path: String,
            query: [String: String]?,
            fields: [String: String]?,
            files: [MultipartFile],
            requiresAuth: Bool
        ) async throws -> T {
            throw APIError.invalidURL
        }
    }

    private final class TransitionConfirmationAPIClient: APIClientProtocol, @unchecked Sendable {
        enum Confirmation {
            case response
            case suspended
            case failure(APIError)
        }

        private let lock = NSLock()
        private let postError: APIError?
        private let confirmation: Confirmation
        private let order: OrderDetailResponse
        private var postCount = 0
        private var getCount = 0
        private var releaseRequested = false
        private var continuations: [UnsafeContinuation<Void, Never>] = []

        init(
            postError: APIError? = nil,
            confirmation: Confirmation,
            order: OrderDetailResponse
        ) {
            self.postError = postError
            self.confirmation = confirmation
            self.order = order
        }

        var postRequestCount: Int {
            lock.withLock { postCount }
        }

        var getRequestCount: Int {
            lock.withLock { getCount }
        }

        func releaseSuspendedRequests() {
            let pending = lock.withLock { () -> [UnsafeContinuation<Void, Never>] in
                releaseRequested = true
                defer { continuations.removeAll() }
                return continuations
            }
            pending.forEach { $0.resume() }
        }

        func request<T: Decodable>(
            method: HTTPMethod,
            path: String,
            query: [String: String]?,
            body: (any Encodable & Sendable)?,
            requiresAuth: Bool
        ) async throws -> T {
            if method == .post,
               path.hasSuffix("/en-route") || path.hasSuffix("/arrived") {
                lock.withLock { postCount += 1 }
                if let postError { throw postError }
                guard let response = EmptyResponse() as? T else {
                    throw APIError.decodingError(TransitionTestError.typeMismatch)
                }
                return response
            }

            if method == .get, path.hasPrefix("/api/orders/") {
                lock.withLock { getCount += 1 }
                switch confirmation {
                case .response:
                    break
                case .failure(let error):
                    throw error
                case .suspended:
                    await withUnsafeContinuation { continuation in
                        let shouldResume = lock.withLock { () -> Bool in
                            if releaseRequested { return true }
                            continuations.append(continuation)
                            return false
                        }
                        if shouldResume { continuation.resume() }
                    }
                }
                guard let response = order as? T else {
                    throw APIError.decodingError(TransitionTestError.typeMismatch)
                }
                return response
            }

            throw APIError.invalidURL
        }

        func upload<T: Decodable>(
            path: String,
            query: [String: String]?,
            fields: [String: String]?,
            files: [MultipartFile],
            requiresAuth: Bool
        ) async throws -> T {
            throw APIError.invalidURL
        }

        private enum TransitionTestError: Error {
            case typeMismatch
        }
    }

    private final class SummaryFirstAPIClient: APIClientProtocol, @unchecked Sendable {
        private(set) var summaryRequestCount = 0

        func request<T: Decodable>(
            method: HTTPMethod,
            path: String,
            query: [String: String]?,
            body: (any Encodable & Sendable)?,
            requiresAuth: Bool
        ) async throws -> T {
            if method == .get, path == "/api/volunteer/dispatch-summary" {
                summaryRequestCount += 1
                let json = #"{"canDispatch":true,"notAvailableReasons":[],"wantsDispatch":true}"#
                return try JSONDecoder().decode(T.self, from: Data(json.utf8))
            }
            if method == .get,
               path == "/api/volunteer/profile" || path == "/api/volunteer/registration/status" {
                try await Task.sleep(nanoseconds: 5_000_000_000)
            }
            throw APIError.invalidURL
        }

        func upload<T: Decodable>(
            path: String,
            query: [String: String]?,
            fields: [String: String]?,
            files: [MultipartFile],
            requiresAuth: Bool
        ) async throws -> T {
            throw APIError.invalidURL
        }
    }

    private final class DispatchSummarySequenceAPIClient: APIClientProtocol, @unchecked Sendable {
        private(set) var dispatchSummaryRequestCount = 0

        func request<T: Decodable>(
            method: HTTPMethod,
            path: String,
            query: [String: String]?,
            body: (any Encodable & Sendable)?,
            requiresAuth: Bool
        ) async throws -> T {
            guard method == .get, path == "/api/volunteer/dispatch-summary" else {
                throw APIError.invalidURL
            }
            dispatchSummaryRequestCount += 1
            let json = dispatchSummaryRequestCount == 1
                ? #"{"canDispatch":false,"notAvailableReasons":[],"wantsDispatch":true}"#
                : #"{"canDispatch":true,"notAvailableReasons":[],"wantsDispatch":true,"coverageRadiusKm":10}"#
            return try JSONDecoder().decode(T.self, from: Data(json.utf8))
        }

        func upload<T: Decodable>(
            path: String,
            query: [String: String]?,
            fields: [String: String]?,
            files: [MultipartFile],
            requiresAuth: Bool
        ) async throws -> T {
            throw APIError.invalidURL
        }
    }

    private final class RecoveringDispatchSummaryAPIClient: APIClientProtocol, @unchecked Sendable {
        private var requestCount = 0

        func request<T: Decodable>(
            method: HTTPMethod,
            path: String,
            query: [String: String]?,
            body: (any Encodable & Sendable)?,
            requiresAuth: Bool
        ) async throws -> T {
            guard method == .get, path == "/api/volunteer/dispatch-summary" else {
                throw APIError.invalidURL
            }
            requestCount += 1
            if requestCount == 1 {
                throw APIError.serverError(
                    ErrorResponse(code: "DISPATCH_SUMMARY_UNAVAILABLE", message: "派单摘要暂时不可用")
                )
            }
            let json = #"{"canDispatch":true,"notAvailableReasons":[],"wantsDispatch":true,"coverageRadiusKm":10}"#
            return try JSONDecoder().decode(T.self, from: Data(json.utf8))
        }

        func upload<T: Decodable>(
            path: String,
            query: [String: String]?,
            fields: [String: String]?,
            files: [MultipartFile],
            requiresAuth: Bool
        ) async throws -> T {
            throw APIError.invalidURL
        }
    }

    private final class LoginCodeCaptureAPIClient: APIClientProtocol, @unchecked Sendable {
        private let sendCodeResponse: SendCodeResponse
        private(set) var capturedVerifyCodeRequest: VerifyCodeRequest?

        init(sendCodeResponse: SendCodeResponse) {
            self.sendCodeResponse = sendCodeResponse
        }

        func request<T: Decodable>(
            method: HTTPMethod,
            path: String,
            query: [String: String]?,
            body: (any Encodable & Sendable)?,
            requiresAuth: Bool
        ) async throws -> T {
            if method == .post, path == "/api/auth/send-code" {
                guard let response = sendCodeResponse as? T else {
                    throw APIError.decodingError(NSError(domain: "LoginCodeCaptureAPIClient", code: 1))
                }
                return response
            }

            if method == .post, path == "/api/auth/verify-code" {
                guard let request = decodeBody(VerifyCodeRequest.self, from: body) else {
                    throw APIError.decodingError(NSError(domain: "LoginCodeCaptureAPIClient", code: 2))
                }
                capturedVerifyCodeRequest = request
                guard let response = LoginResponse(token: "test-token", userId: 1, role: nil) as? T else {
                    throw APIError.decodingError(NSError(domain: "LoginCodeCaptureAPIClient", code: 3))
                }
                return response
            }

            throw APIError.invalidURL
        }

        func upload<T: Decodable>(
            path: String,
            query: [String: String]?,
            fields: [String: String]?,
            files: [MultipartFile],
            requiresAuth: Bool
        ) async throws -> T {
            throw APIError.invalidURL
        }

        private func decodeBody<T: Decodable>(_ type: T.Type, from body: (any Encodable & Sendable)?) -> T? {
            body as? T
        }
    }

    private final class BasicInfoFailingAPIClient: APIClientProtocol, @unchecked Sendable {
        private let error: APIError

        init(error: APIError) {
            self.error = error
        }

        func request<T: Decodable>(
            method: HTTPMethod,
            path: String,
            query: [String: String]?,
            body: (any Encodable & Sendable)?,
            requiresAuth: Bool
        ) async throws -> T {
            if method == .post, path == "/api/volunteer/registration/step1" {
                throw error
            }
            throw APIError.invalidURL
        }

        func upload<T: Decodable>(
            path: String,
            query: [String: String]?,
            fields: [String: String]?,
            files: [MultipartFile],
            requiresAuth: Bool
        ) async throws -> T {
            throw APIError.invalidURL
        }
    }

    private final class BasicInfoStatusAPIClient: APIClientProtocol, @unchecked Sendable {
        private let status: VolunteerRegistrationStatus
        private(set) var submitCount = 0
        private(set) var statusRefreshCount = 0
        private(set) var capturedRequest: BasicInfoRequest?

        init(status: VolunteerRegistrationStatus) {
            self.status = status
        }

        func request<T: Decodable>(
            method: HTTPMethod,
            path: String,
            query: [String: String]?,
            body: (any Encodable & Sendable)?,
            requiresAuth: Bool
        ) async throws -> T {
            if method == .post, path == "/api/volunteer/registration/step1" {
                submitCount += 1
                guard let request = body as? BasicInfoRequest else {
                    throw APIError.invalidURL
                }
                capturedRequest = request
                guard let response = EmptyResponse() as? T else {
                    throw APIError.invalidURL
                }
                return response
            }
            if method == .get, path == "/api/volunteer/registration/status" {
                statusRefreshCount += 1
                guard let response = status as? T else {
                    throw APIError.invalidURL
                }
                return response
            }
            throw APIError.invalidURL
        }

        func upload<T: Decodable>(
            path: String,
            query: [String: String]?,
            fields: [String: String]?,
            files: [MultipartFile],
            requiresAuth: Bool
        ) async throws -> T {
            throw APIError.invalidURL
        }
    }

    private func failureKind(for outcome: CloudAuthVerificationOutcome) -> CloudAuthVerificationFailure.Kind? {
        guard case .failed(let failure) = outcome else { return nil }
        return failure.kind
    }

    private final class CloudAuthVerifierSpy: CloudAuthVerifying, @unchecked Sendable {
        private let outcome: CloudAuthVerificationOutcome
        private(set) var receivedCertifyIds: [String] = []
        private(set) var receivedEnvironments: [APIEnvironment] = []

        init(outcome: CloudAuthVerificationOutcome) {
            self.outcome = outcome
        }

        func verify(certifyId: String, environment: APIEnvironment) async -> CloudAuthVerificationOutcome {
            receivedCertifyIds.append(certifyId)
            receivedEnvironments.append(environment)
            return outcome
        }
    }

    private final class FaceVerifyFlowAPIClient: APIClientProtocol, @unchecked Sendable {
        private let initResponse: FaceVerifyInitResponse
        private let initError: APIError?
        private var resultResponses: [FaceVerifyResponse]
        private let status: VolunteerRegistrationStatus
        private(set) var capturedMetaInfo: String?
        private(set) var initCount = 0
        private(set) var resultCount = 0
        private(set) var statusRefreshCount = 0
        private(set) var requestedPaths: [String] = []

        init(
            initResponse: FaceVerifyInitResponse,
            initError: APIError? = nil,
            resultResponses: [FaceVerifyResponse],
            status: VolunteerRegistrationStatus = VolunteerRegistrationStatus(currentStepCode: "STEP_3_FACE_VERIFY", step1Completed: true)
        ) {
            self.initResponse = initResponse
            self.initError = initError
            self.resultResponses = resultResponses
            self.status = status
        }

        func request<T: Decodable>(
            method: HTTPMethod,
            path: String,
            query: [String: String]?,
            body: (any Encodable & Sendable)?,
            requiresAuth: Bool
        ) async throws -> T {
            requestedPaths.append(path)
            if method == .post, path == "/api/volunteer/registration/step3/face-verify/init" {
                initCount += 1
                if let initError {
                    throw initError
                }
                guard let request = body as? FaceVerifyInitRequest,
                      let response = initResponse as? T else {
                    throw APIError.invalidURL
                }
                capturedMetaInfo = request.metaInfo
                return response
            }
            if method == .post, path == "/api/volunteer/registration/step3/face-verify/result" {
                resultCount += 1
                guard let response = (resultResponses.isEmpty ? FaceVerifyResponse(passed: false, status: "PENDING", message: nil) : resultResponses.removeFirst()) as? T else {
                    throw APIError.invalidURL
                }
                return response
            }
            if method == .get, path == "/api/volunteer/registration/status" {
                statusRefreshCount += 1
                guard let response = status as? T else {
                    throw APIError.invalidURL
                }
                return response
            }
            throw APIError.invalidURL
        }

        func upload<T: Decodable>(
            path: String,
            query: [String: String]?,
            fields: [String: String]?,
            files: [MultipartFile],
            requiresAuth: Bool
        ) async throws -> T {
            throw APIError.invalidURL
        }
    }

    @MainActor
    private final class FakePlaceSearchProvider: PlaceSearchProviding {
        var lastErrorMessage: String?
        var searchKeywords: [String] = []
        private let results: [ResolvedPlace]
        private var reverseGeocodeResults: [ResolvedPlace]

        init(
            results: [ResolvedPlace],
            lastErrorMessage: String? = nil,
            reverseGeocodeResults: [ResolvedPlace] = []
        ) {
            self.results = results
            self.lastErrorMessage = lastErrorMessage
            self.reverseGeocodeResults = reverseGeocodeResults
        }

        func reverseGeocode(coordinate: CLLocationCoordinate2D) async -> ResolvedPlace? {
            guard !reverseGeocodeResults.isEmpty else { return nil }
            return reverseGeocodeResults.removeFirst()
        }

        func searchPlaces(keyword: String, near coordinate: CLLocationCoordinate2D?) async -> [ResolvedPlace] {
            searchKeywords.append(keyword)
            return results
        }
    }

    private final class AuthLifecycleAPIClient: APIClientProtocol, @unchecked Sendable {
        let meResult: Result<CurrentUserResponse, APIError>?
        let logoutResult: Result<LogoutResponse, APIError>
        let registrationRateLimitSeconds: Int?
        let mineOrders: PagedOrderResponse?

        init(
            meResult: Result<CurrentUserResponse, APIError>? = nil,
            logoutResult: Result<LogoutResponse, APIError> = .success(LogoutResponse(success: true, message: nil)),
            registrationRateLimitSeconds: Int? = nil,
            mineOrders: PagedOrderResponse? = nil
        ) {
            self.meResult = meResult
            self.logoutResult = logoutResult
            self.registrationRateLimitSeconds = registrationRateLimitSeconds
            self.mineOrders = mineOrders
        }

        func request<T: Decodable>(
            method: HTTPMethod,
            path: String,
            query: [String: String]?,
            body: (any Encodable & Sendable)?,
            requiresAuth: Bool
        ) async throws -> T {
            if method == .get, path == "/api/auth/me", let meResult {
                let response = try meResult.get()
                guard let typed = response as? T else { throw APIError.decodingError(TestError.typeMismatch) }
                return typed
            }
            if method == .post, path == "/api/auth/logout" {
                let response = try logoutResult.get()
                guard let typed = response as? T else { throw APIError.decodingError(TestError.typeMismatch) }
                return typed
            }
            if method == .post, path == "/api/volunteer/registration/step1",
               let registrationRateLimitSeconds {
                throw APIError.rateLimited(RateLimitInfo(
                    message: "注册过于频繁",
                    retryAfterSeconds: registrationRateLimitSeconds
                ))
            }
            if method == .get, path == "/api/orders/mine", let mineOrders {
                guard let typed = mineOrders as? T else { throw APIError.decodingError(TestError.typeMismatch) }
                return typed
            }
            throw APIError.invalidURL
        }

        func upload<T: Decodable>(
            path: String,
            query: [String: String]?,
            fields: [String: String]?,
            files: [MultipartFile],
            requiresAuth: Bool
        ) async throws -> T {
            throw APIError.invalidURL
        }

        private enum TestError: Error { case typeMismatch }
    }

    private func makeVolunteerProfile(
        name: String = "测试志愿者",
        verificationStatus: String = "not_submitted",
        adminReviewStatus: String? = nil,
        isAvailable: Bool = false,
        registrationStep: String? = nil,
        canAcceptOrders: Bool? = nil
    ) -> VolunteerProfileResponse {
        VolunteerProfileResponse(
            name: name,
            verificationStatus: verificationStatus,
            adminReviewStatus: adminReviewStatus,
            registrationStep: registrationStep,
            canAcceptOrders: canAcceptOrders,
            isAvailable: isAvailable,
            availableTimeSlots: nil,
            acceptsGuideDog: nil,
            paceRange: nil
        )
    }

    private func makeApprovedVolunteerProfile(isAvailable: Bool = true) -> VolunteerProfileResponse {
        makeVolunteerProfile(
            verificationStatus: "approved",
            isAvailable: isAvailable
        )
    }

    // MARK: - 志愿者资质证书上传（POST /api/volunteer/verification）

    /// 上限来自后端 `VolunteerController.java:77`：`file.getSize() > 5 * 1024 * 1024` 才拒。
    /// 正好 5 MB 必须放行，5 MB + 1 字节必须本地拦截。
    func testCertificateFileSizeBoundaryMatchesBackend() {
        XCTAssertEqual(VolunteerCertificateFileRules.maxByteCount, 5 * 1024 * 1024)
        XCTAssertNil(
            VolunteerCertificateFileRules.validate(fileExtension: "pdf", byteCount: 5 * 1024 * 1024)
        )
        XCTAssertEqual(
            VolunteerCertificateFileRules.validate(fileExtension: "pdf", byteCount: 5 * 1024 * 1024 + 1),
            .tooLarge(byteCount: 5 * 1024 * 1024 + 1)
        )
        XCTAssertEqual(
            VolunteerCertificateFileRules.validate(fileExtension: "pdf", byteCount: 0),
            .emptyFile
        )
    }

    /// 扩展名白名单来自 `LocalFileStorageService.java:26`。
    func testCertificateExtensionWhitelistMatchesBackend() {
        XCTAssertEqual(
            Set(VolunteerCertificateFileRules.allowedExtensions),
            ["jpg", "jpeg", "png", "gif", "webp", "bmp", "pdf"]
        )
        for allowed in VolunteerCertificateFileRules.allowedExtensions {
            XCTAssertNil(VolunteerCertificateFileRules.validate(fileExtension: allowed, byteCount: 1024))
            let mime = VolunteerCertificateFileRules.mimeType(forExtension: allowed)
            // 后端只接受 image/* 或 application/pdf。
            XCTAssertTrue(mime?.hasPrefix("image/") == true || mime == "application/pdf")
        }
        XCTAssertEqual(
            VolunteerCertificateFileRules.validate(fileExtension: "heic", byteCount: 1024),
            .unsupportedType
        )
        XCTAssertNil(VolunteerCertificateFileRules.mimeType(forExtension: "heic"))
    }

    /// 魔数嗅探与后端 `LocalFileStorageService.validateMagicBytes` 对齐，
    /// 客户端据此决定扩展名，避免「改扩展名伪装」被后端 400。
    func testCertificateMagicByteDetection() {
        XCTAssertEqual(VolunteerCertificateFileRules.detectExtension(from: Data("%PDF-1.7".utf8)), "pdf")
        XCTAssertEqual(VolunteerCertificateFileRules.detectExtension(from: Data([0xFF, 0xD8, 0xFF, 0xE0])), "jpg")
        XCTAssertEqual(VolunteerCertificateFileRules.detectExtension(from: Data([0x89, 0x50, 0x4E, 0x47])), "png")
        XCTAssertNil(VolunteerCertificateFileRules.detectExtension(from: Data([0x00, 0x01, 0x02, 0x03])))
    }

    /// 构造出来的文件名不得包含来源文件名（证书属敏感材料）。
    func testCertificateFileBuildsNeutralFileName() throws {
        var pdf = Data("%PDF-1.7\n".utf8)
        pdf.append(Data(repeating: 0x20, count: 1024))

        let result = VolunteerCertificateFile.make(from: pdf)
        guard case .success(let file) = result else {
            return XCTFail("合法 PDF 应当构造成功")
        }
        XCTAssertEqual(file.fileExtension, "pdf")
        XCTAssertEqual(file.mimeType, "application/pdf")
        XCTAssertEqual(file.fileName, "certificate.pdf")
        XCTAssertTrue(file.summaryText.contains("PDF"))
    }

    func testCertificateFileRejectsOversizedPdfWithoutUpload() {
        var pdf = Data("%PDF-1.7\n".utf8)
        pdf.append(Data(repeating: 0x20, count: VolunteerCertificateFileRules.maxByteCount))

        guard case .failure(let failure) = VolunteerCertificateFile.make(from: pdf) else {
            return XCTFail("超过 5 MB 的 PDF 必须在本地被拒")
        }
        guard case .tooLarge = failure else {
            return XCTFail("应当命中大小上限，实际：\(failure)")
        }
        XCTAssertTrue(failure.message.contains("5 MB"))
    }

    func testCertificateFileRejectsUnknownBinaryWithoutUpload() {
        let junk = Data(repeating: 0x7A, count: 2048)

        guard case .failure(let failure) = VolunteerCertificateFile.make(from: junk) else {
            return XCTFail("无法识别的二进制必须在本地被拒")
        }
        XCTAssertEqual(failure, .unsupportedType)
    }

    // MARK: - 资质审核五态

    func testCertificateStatusParsingCoversBackendValues() {
        XCTAssertEqual(VolunteerCertificateStatus.parse("NONE"), VolunteerCertificateStatus.none)
        XCTAssertEqual(VolunteerCertificateStatus.parse("PENDING"), .pending)
        XCTAssertEqual(VolunteerCertificateStatus.parse("APPROVED"), .approved)
        XCTAssertEqual(VolunteerCertificateStatus.parse("REJECTED"), .rejected)
        // 历史上客户端把状态存成小写，解析必须兼容。
        XCTAssertEqual(VolunteerCertificateStatus.parse("approved"), .approved)
        XCTAssertEqual(VolunteerCertificateStatus.parse(nil), .unknown)
        XCTAssertEqual(VolunteerCertificateStatus.parse("SOMETHING_NEW"), .unknown)
    }

    /// 只有 APPROVED 能接单；PENDING 必须明说「审核中，暂时无法接单」且不引导重复上传。
    func testCertificateDisplayStatesGuideAcceptEligibility() {
        let states: [(VolunteerCertificateStatus, Bool, VolunteerCertificateDisplayState)] = [
            (VolunteerCertificateStatus.none, false, .notSubmitted),
            (.pending, false, .pending),
            (.approved, false, .approved),
            (.rejected, false, .rejected),
            (.unknown, false, .statusUnavailable),
            (.approved, true, .statusUnavailable)
        ]
        for (status, loadFailed, expected) in states {
            let state = VolunteerCertificateDisplayState.from(status: status, statusLoadFailed: loadFailed)
            XCTAssertEqual(state, expected)
            XCTAssertFalse(state.displayName.isEmpty)
            XCTAssertFalse(state.guidanceMessage.isEmpty)
        }

        XCTAssertTrue(VolunteerCertificateDisplayState.approved.canAcceptOrders)
        for state: VolunteerCertificateDisplayState in [.notSubmitted, .pending, .rejected, .statusUnavailable] {
            XCTAssertFalse(state.canAcceptOrders, "\(state) 不应被判定为可接单")
        }

        // 未提交 / 被拒可以上传；审核中、已通过、状态未知都不允许发起上传。
        XCTAssertTrue(VolunteerCertificateDisplayState.notSubmitted.allowsUpload)
        XCTAssertTrue(VolunteerCertificateDisplayState.rejected.allowsUpload)
        XCTAssertFalse(VolunteerCertificateDisplayState.pending.allowsUpload)
        XCTAssertFalse(VolunteerCertificateDisplayState.approved.allowsUpload)
        XCTAssertFalse(VolunteerCertificateDisplayState.statusUnavailable.allowsUpload)

        XCTAssertTrue(VolunteerCertificateDisplayState.pending.guidanceMessage.contains("暂时无法接单"))
        XCTAssertTrue(VolunteerCertificateDisplayState.approved.guidanceMessage.contains("可以接单"))
        XCTAssertTrue(VolunteerCertificateDisplayState.statusUnavailable.guidanceMessage.contains("重新获取状态"))
    }

    /// 后端两个接口的响应体都能解出 status。
    func testVerificationStatusResponseDecodesBothShapes() throws {
        let statusOnly = try JSONDecoder().decode(
            VolunteerVerificationStatusResponse.self,
            from: Data(#"{"status":"PENDING"}"#.utf8)
        )
        XCTAssertEqual(VolunteerCertificateStatus.parse(statusOnly.status), .pending)

        let submitResponse = try JSONDecoder().decode(
            VolunteerVerificationStatusResponse.self,
            from: Data(#"{"success":true,"status":"PENDING"}"#.utf8)
        )
        XCTAssertEqual(submitResponse.success, true)
        XCTAssertEqual(VolunteerCertificateStatus.parse(submitResponse.status), .pending)
    }

    // MARK: - 接单被 403 VOLUNTEER_NOT_VERIFIED 拒绝

    /// case 名是历史命名，rawValue 必须保持 `VOLUNTEER_NOT_VERIFIED`。
    func testVolunteerNotVerifiedErrorCodeMapsToCertificateGuidance() {
        XCTAssertEqual(ErrorCode.volunteerNotApproved.rawValue, "VOLUNTEER_NOT_VERIFIED")

        let response = ErrorResponse(code: "VOLUNTEER_NOT_VERIFIED", message: "志愿者资质未通过审核")
        XCTAssertEqual(response.errorCode, .volunteerNotApproved)

        let error = APIError.serverError(response)
        XCTAssertEqual(error.errorCode, .volunteerNotApproved)
        XCTAssertEqual(error.localizedMessage, "尚未通过资质认证，请先上传资质证书。")
    }

    /// 后端 403 的真实响应体（`{success,code,message,errorCode}`）必须能解出 errorCode，
    /// 否则界面拿不到「去上传资质证书」的触发条件。
    func testVolunteerNotVerifiedDecodesFromBackendErrorEnvelope() throws {
        let data = Data(#"""
        {"success":false,"code":403,"errorCode":"VOLUNTEER_NOT_VERIFIED","message":"资质证书未通过审核，暂时无法接单"}
        """#.utf8)

        let envelope = try JSONDecoder().decode(APIErrorEnvelope.self, from: data)
        let resolved = try XCTUnwrap(envelope.resolvedErrorResponse(statusCode: 403))

        XCTAssertEqual(resolved.errorCode, .volunteerNotApproved)
    }

    // MARK: - ROLE_ALREADY_SET 语义

    /// 该码曾被命名成 `activeOrderRoleSwitchBlocked` 并映射成「存在进行中的订单，无法切换角色」，
    /// 导致没有任何订单的用户看到假的订单拦截提示。后端 `RoleController` 的真实语义只是
    /// 「角色一次性设定，不可修改」，与订单无关，文案里不得再出现「订单」。
    func testRoleAlreadySetMessageDoesNotBlameOrders() {
        let response = ErrorResponse(code: "ROLE_ALREADY_SET", message: "身份已设定，不可修改")
        XCTAssertEqual(response.errorCode, .roleAlreadySet)

        let message = APIError.serverError(response).localizedMessage
        XCTAssertFalse(message.contains("订单"), "ROLE_ALREADY_SET 文案不得提及订单：\(message)")
    }

    // MARK: - Mock 与后端实现逐条对齐

    func testMockVerificationStatusOnlyReturnsBackendEnumValues() async throws {
        let client = MockAPIClient()
        let response: VolunteerVerificationStatusResponse = try await client.get(
            "/api/volunteer/verification/status"
        )
        let raw = try XCTUnwrap(response.status)

        XCTAssertTrue(["NONE", "PENDING", "APPROVED", "REJECTED"].contains(raw), "Mock 返回了后端不存在的取值：\(raw)")
        XCTAssertNotEqual(VolunteerCertificateStatus.parse(raw), .unknown)
    }

    /// `VolunteerController.java:77` 的大小拒绝，文案逐字一致且不带 errorCode。
    func testMockRejectsOversizedCertificateLikeBackend() async {
        let client = MockAPIClient()
        let file = MultipartFile(
            fieldName: "file",
            fileName: "certificate.jpg",
            mimeType: "image/jpeg",
            data: Data(repeating: 0xFF, count: 5 * 1024 * 1024 + 1)
        )

        do {
            let _: VolunteerVerificationStatusResponse = try await client.upload(
                "/api/volunteer/verification",
                files: [file]
            )
            XCTFail("超过 5 MB 必须被拒")
        } catch let error as APIError {
            XCTAssertNil(error.errorCode, "后端该 400 没有 errorCode")
            XCTAssertEqual(error.localizedMessage, "文件大小不能超过5MB")
        } catch {
            XCTFail("应当抛出 APIError，实际：\(error)")
        }
    }

    /// `VolunteerController.java:73` 的类型拒绝。
    func testMockRejectsUnsupportedCertificateContentTypeLikeBackend() async {
        let client = MockAPIClient()
        let file = MultipartFile(
            fieldName: "file",
            fileName: "certificate.txt",
            mimeType: "text/plain",
            data: Data("hello".utf8)
        )

        do {
            let _: VolunteerVerificationStatusResponse = try await client.upload(
                "/api/volunteer/verification",
                files: [file]
            )
            XCTFail("非图片非 PDF 必须被拒")
        } catch let error as APIError {
            XCTAssertEqual(error.localizedMessage, "文件格式仅支持图片或PDF")
        } catch {
            XCTFail("应当抛出 APIError，实际：\(error)")
        }
    }

    /// `VolunteerService.java:314`：APPROVED 状态重传抛 `IllegalArgumentException`，
    /// 经 `GlobalExceptionHandler:136` 变成 `ApiResponse.error(400, BAD_REQUEST, message)`。
    /// 与前三条 Controller 内联 400 不同，这一条**带 errorCode**，
    /// 因此 `localizedMessage` 走的是 `ErrorCode.badRequest` 的通用文案，
    /// 后端那句具体说明只留在 `ErrorResponse.message` 里。
    func testMockRejectsReuploadAfterApprovalLikeBackend() async {
        let client = MockAPIClient()
        let file = MultipartFile(
            fieldName: "file",
            fileName: "certificate.pdf",
            mimeType: "application/pdf",
            data: Data("%PDF-1.7".utf8)
        )

        do {
            let _: VolunteerVerificationStatusResponse = try await client.upload(
                "/api/volunteer/verification",
                files: [file]
            )
            XCTFail("已通过审核不允许重传")
        } catch let error as APIError {
            XCTAssertEqual(error.errorCode, .badRequest, "后端该 400 由全局异常处理器带上 BAD_REQUEST")
            guard case .serverError(let response) = error else {
                return XCTFail("应当是 serverError，实际：\(error)")
            }
            XCTAssertEqual(response.message, "资质证书已审核通过，无需重新上传")
            XCTAssertEqual(error.localizedMessage, "请求参数有误。")
        } catch {
            XCTFail("应当抛出 APIError，实际：\(error)")
        }
    }

    /// 上传成功后状态置 PENDING，且 `/api/volunteer/profile` 与状态接口保持同源。
    func testMockUploadMovesStatusToPendingAndStaysConsistent() async throws {
        setenv("AIDRUN_MOCK_VOLUNTEER_VERIFICATION_STATUS", "NONE", 1)
        defer { unsetenv("AIDRUN_MOCK_VOLUNTEER_VERIFICATION_STATUS") }

        let client = MockAPIClient()
        let before: VolunteerVerificationStatusResponse = try await client.get(
            "/api/volunteer/verification/status"
        )
        XCTAssertEqual(VolunteerCertificateStatus.parse(before.status), VolunteerCertificateStatus.none)

        let submitted: VolunteerVerificationStatusResponse = try await client.upload(
            "/api/volunteer/verification",
            files: [MultipartFile(
                fieldName: "file",
                fileName: "certificate.pdf",
                mimeType: "application/pdf",
                data: Data("%PDF-1.7".utf8)
            )]
        )
        XCTAssertEqual(submitted.success, true)
        XCTAssertEqual(VolunteerCertificateStatus.parse(submitted.status), .pending)

        let after: VolunteerVerificationStatusResponse = try await client.get(
            "/api/volunteer/verification/status"
        )
        XCTAssertEqual(VolunteerCertificateStatus.parse(after.status), .pending)

        let profile: VolunteerProfileResponse = try await client.get("/api/volunteer/profile")
        XCTAssertEqual(VolunteerCertificateStatus.parse(profile.verificationStatus), .pending)
    }

    /// `GET /api/volunteer/verification/status` 只返回 status，写回时不得抹掉其它资料字段。
    func testAppStateVerificationStatusUpdateKeepsOtherProfileFields() {
        let appState = AppState()
        appState.updateVolunteerProfile(VolunteerProfileResponse(
            name: "测试志愿者",
            verificationStatus: "NONE",
            isAvailable: true,
            acceptsGuideDog: true,
            paceRange: .moderate
        ))

        appState.updateVolunteerVerificationStatus("PENDING")

        XCTAssertEqual(appState.volunteerProfile?.verificationStatus, "PENDING")
        XCTAssertEqual(appState.volunteerProfile?.name, "测试志愿者")
        XCTAssertEqual(appState.volunteerProfile?.isAvailable, true)
        XCTAssertEqual(appState.volunteerProfile?.acceptsGuideDog, true)
        XCTAssertEqual(appState.volunteerProfile?.paceRange, .moderate)
    }
}

private final class AuthLifecycleURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override nonisolated class func canInit(with request: URLRequest) -> Bool { true }
    override nonisolated class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override nonisolated func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.badServerResponse) }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override nonisolated func stopLoading() {}
}
