//
//  blindRunApp.swift
//  blindRun
//
//  Created by Jerry on 5/18/26.
//

import SwiftUI
import UIKit
import MetricKit
import OSLog

@main
struct blindRunApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var appState = AppState()
    @StateObject private var pushNotificationsManager = PushNotificationsManager()
    @StateObject private var speechService = SpeechService()
    @StateObject private var speechInputService = SpeechInputService()
    @StateObject private var locationService = LocationService()
    @StateObject private var amapGeocodingService: AMapGeocodingService

    init() {
        AMapManager.configure()
        RuntimeDiagnosticMonitor.shared.start()
        MainRunLoopWatchdog.shared.start()
        _amapGeocodingService = StateObject(wrappedValue: AMapGeocodingService())
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(speechService)
                .environmentObject(speechInputService)
                .environmentObject(locationService)
                .environmentObject(amapGeocodingService)
                .scrollDismissesKeyboard(.interactively)
                .background(KeyboardDismissTapInstaller().allowsHitTesting(false))
                .onAppear {
                    #if DEBUG || DEMO
                    applyUITestLaunchConfigurationIfNeeded()
                    injectUITestRealtimeNotificationsIfNeeded()
                    #endif
                    // 在任何一句播报之前把音频分类定下来。不做的话冷启动到第一次录音之间
                    // 会话一直是系统默认的 `.soloAmbient`，合成器得自己去协商，第一句话
                    // 因此有一段能听出来的延迟（2026-08-06 真机报的「点开始约跑之后要等一下」）。
                    speechInputService.prepareForPlaybackAtLaunch()
                    configurePushNotifications()
                    Task { await appState.restoreSession() }
                }
                .onChange(of: scenePhase) { phase in
                    if phase != .active {
                        speechInputService.cancelRecognitionForLifecycle()
                    } else {
                        // device token 会被 Apple 轮换：每次回前台重新注册并上报最新值。
                        pushNotificationsManager.refreshRegistrationIfReady()
                    }
                }
        }
    }

    /// APNs 只是 WS 离线时的 HIGH 优先级兜底通道，注册失败不影响任何主流程。
    private func configurePushNotifications() {
        pushNotificationsManager.configure(appState: appState, speechService: speechService)
        appDelegate.pushNotificationsManager = pushNotificationsManager
        pushNotificationsManager.requestAuthorizationAndRegister()
    }

    #if DEBUG || DEMO
    private func applyUITestLaunchConfigurationIfNeeded() {
        let environment = ProcessInfo.processInfo.environment
        guard environment["AIDRUN_UI_TEST_RESET_STATE"] == "1" else { return }

        let resetToken = environment["AIDRUN_UI_TEST_RESET_TOKEN"] ?? "legacy-reset-token"
        guard appState.persistence.string(forKey: AppStatePersistenceKeys.uiTestLastResetToken) != resetToken else { return }

        appState.resetUITestPersistence()
        appState.persistence.set(resetToken, forKey: AppStatePersistenceKeys.uiTestLastResetToken)

        #if DEBUG
        switch environment["AIDRUN_UI_TEST_API_ENV"] {
        case "demoCloud":
            appState.currentEnvironment = .demoCloud
        case "mock":
            appState.currentEnvironment = .mock
        default:
            break
        }
        #else
        appState.currentEnvironment = .demoCloud
        #endif

        if let accessToken = environment["AIDRUN_UI_TEST_ACCESS_TOKEN"], !accessToken.isEmpty {
            appState.accessToken = accessToken
        }
        if let activeRole = resolvedUITestRoleRaw(from: environment["AIDRUN_UI_TEST_ACTIVE_ROLE"]) {
            appState.activeRole = UserRole(rawValue: activeRole)
        }
        if environment["AIDRUN_UI_TEST_PRESEEDED_BLIND_PROFILE"] == "1" {
            appState.updateBlindProfile(
                BlindProfileResponse(
                    name: "UITestBlind",
                    runningPace: "MODERATE",
                    specialNeeds: nil,
                    verifyStatus: "VERIFIED",
                    visionLevel: "TOTAL_BLIND",
                    hasGuideDog: false,
                    tetherPreference: "TETHER_ROPE",
                    chatPreference: "PREFER_CHAT",
                    defaultPace: .moderate
                )
            )
            appState.updateEmergencyContacts([
                EmergencyContactResponse(id: 1, name: "UITestContact", phone: "13800001111", relationship: "家人", isPrimary: true)
            ])
        }
        if environment["AIDRUN_UI_TEST_PRESEEDED_VOLUNTEER_PROFILE"] == "1" {
            let isAvailable = environment["AIDRUN_UI_TEST_PRESEEDED_VOLUNTEER_AVAILABLE"] == "1"
            appState.updateVolunteerProfile(
                VolunteerProfileResponse(
                    name: "UITestVolunteer",
                    verificationStatus: "approved",
                    adminReviewStatus: "approved",
                    isAvailable: isAvailable,
                    availableTimeSlots: [
                        VolunteerAvailableTimeSlot(dayOfWeek: "SATURDAY", startTime: "09:00:00", endTime: "12:00:00"),
                        VolunteerAvailableTimeSlot(dayOfWeek: "SUNDAY", startTime: "09:00:00", endTime: "12:00:00")
                    ],
                    acceptsGuideDog: true,
                    paceRange: .moderate
                )
            )
        }
    }

    private func resolvedUITestRoleRaw(from value: String?) -> String? {
        switch value {
        case UserRole.blind.rawValue, "blind_runner":
            return UserRole.blind.rawValue
        case UserRole.volunteer.rawValue, "volunteer":
            return UserRole.volunteer.rawValue
        default:
            return nil
        }
    }

    private func injectUITestRealtimeNotificationsIfNeeded() {
        guard ProcessInfo.processInfo.environment["AIDRUN_UI_TEST_REALTIME_PRIORITY"] == "1" else { return }
        #if DEBUG
        appState.realtimeCoordinator.simulateIncomingEventForTesting(
            .notification(WSAppNotification(
                type: WSMessageType.appNotification.rawValue,
                eventId: 9001,
                eventType: "UI_TEST_NORMAL",
                title: "普通通知",
                body: "普通前台通知",
                ttsText: "普通前台通知",
                priority: "NORMAL",
                timestamp: "2026-07-19T12:00:00Z"
            ))
        )
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            appState.realtimeCoordinator.simulateIncomingEventForTesting(
                .notification(WSAppNotification(
                    type: WSMessageType.appNotification.rawValue,
                    eventId: 9002,
                    eventType: "UI_TEST_HIGH",
                    title: "重要通知",
                    body: "高优先级前台通知",
                    ttsText: "高优先级前台通知",
                    priority: "HIGH",
                    timestamp: "2026-07-19T12:00:01Z"
                ))
            )
        }
        #endif
    }
    #endif
}

// MARK: - Runtime Diagnostics

/// MetricKit delivers prior-run crash and hang summaries on a later launch.
/// Only aggregate counts are logged; payloads and user data are never persisted.
@MainActor
final class RuntimeDiagnosticMonitor: NSObject, MXMetricManagerSubscriber {
    static let shared = RuntimeDiagnosticMonitor()

    private let logger = Logger(subsystem: "com.jerry.aidrun", category: "runtime")
    private var isStarted = false

    func start() {
        guard !isStarted else { return }
        isStarted = true
        MXMetricManager.shared.add(self)
    }

    nonisolated func didReceive(_ payloads: [MXMetricPayload]) {
        Task { @MainActor in
            RuntimeDiagnosticMonitor.shared.logger.info(
                "metricPayloadCount=\(payloads.count, privacy: .public)"
            )
        }
    }

    nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let crashCount = payloads.reduce(0) { $0 + ($1.crashDiagnostics?.count ?? 0) }
        let hangCount = payloads.reduce(0) { $0 + ($1.hangDiagnostics?.count ?? 0) }
        Task { @MainActor in
            RuntimeDiagnosticMonitor.shared.logger.error(
                "diagnosticPayloadCount=\(payloads.count, privacy: .public) crashCount=\(crashCount, privacy: .public) hangCount=\(hangCount, privacy: .public)"
            )
        }
    }
}

/// Detects sustained main-run-loop stalls without retaining user, order, or location data.
/// The watchdog logs only an anonymous screen category and duration.
final class MainRunLoopWatchdog: @unchecked Sendable {
    nonisolated(unsafe) static let shared = MainRunLoopWatchdog()

    nonisolated(unsafe) private let logger = Logger(subsystem: "com.jerry.aidrun", category: "run-loop")
    nonisolated(unsafe) private let stateLock = NSLock()
    nonisolated(unsafe) private let queue = DispatchQueue(label: "com.jerry.aidrun.run-loop-watchdog", qos: .utility)
    nonisolated(unsafe) private var timer: DispatchSourceTimer?
    nonisolated(unsafe) private var lastAcknowledgedAt = ProcessInfo.processInfo.systemUptime
    nonisolated(unsafe) private var stallWasReported = false
    nonisolated(unsafe) private var pageCategory = "root"

    nonisolated func start() {
        stateLock.lock()
        guard timer == nil else {
            stateLock.unlock()
            return
        }
        let source = DispatchSource.makeTimerSource(queue: queue)
        timer = source
        stateLock.unlock()

        source.schedule(deadline: .now() + 1, repeating: 1)
        source.setEventHandler { [weak self] in
            self?.sample()
        }
        source.resume()
    }

    nonisolated func setPageCategory(_ category: String) {
        stateLock.withLock {
            pageCategory = category
        }
    }

    nonisolated private func sample() {
        DispatchQueue.main.async { [weak self] in
            self?.acknowledgeMainRunLoop()
        }

        let snapshot = stateLock.withLock {
            (
                duration: ProcessInfo.processInfo.systemUptime - lastAcknowledgedAt,
                alreadyReported: stallWasReported,
                page: pageCategory,
                phase: ClientFlowDiagnostics.currentPhase
            )
        }
        guard snapshot.duration >= 2 else { return }
        guard !snapshot.alreadyReported else { return }
        stateLock.withLock { stallWasReported = true }
        logger.error(
            "main_run_loop_stall page=\(snapshot.page, privacy: .public) phase=\(snapshot.phase, privacy: .public) duration_ms=\(Int(snapshot.duration * 1_000), privacy: .public)"
        )
    }

    nonisolated private func acknowledgeMainRunLoop() {
        stateLock.withLock {
            lastAcknowledgedAt = ProcessInfo.processInfo.systemUptime
            stallWasReported = false
        }
    }
}

// MARK: - Keyboard Dismissal

private struct KeyboardDismissTapInstaller: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        DispatchQueue.main.async {
            context.coordinator.installIfNeeded(from: view)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.installIfNeeded(from: uiView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private weak var installedWindow: UIWindow?
        private weak var tapGesture: UITapGestureRecognizer?

        deinit {
            if let tapGesture {
                installedWindow?.removeGestureRecognizer(tapGesture)
            }
        }

        func installIfNeeded(from view: UIView) {
            guard let window = view.window else { return }
            guard !(installedWindow === window && tapGesture != nil) else { return }

            if let tapGesture {
                installedWindow?.removeGestureRecognizer(tapGesture)
            }

            let gesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            gesture.cancelsTouchesInView = false
            gesture.delaysTouchesBegan = false
            gesture.delaysTouchesEnded = false
            gesture.delegate = self
            window.addGestureRecognizer(gesture)
            installedWindow = window
            tapGesture = gesture
        }

        @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, let window = installedWindow else { return }
            let location = gesture.location(in: window)
            guard let touchedView = window.hitTest(location, with: nil) else {
                window.endEditing(true)
                return
            }
            guard !touchedView.isTextInputOrDescendant else { return }
            window.endEditing(true)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

private extension UIView {
    var isTextInputOrDescendant: Bool {
        var current: UIView? = self
        while let view = current {
            if view is UITextField || view is UITextView || view is UISearchBar {
                return true
            }
            current = view.superview
        }
        return false
    }
}
