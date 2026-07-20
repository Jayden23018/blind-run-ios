//
//  blindRunApp.swift
//  blindRun
//
//  Created by Jerry on 5/18/26.
//

import SwiftUI
import UIKit

@main
struct blindRunApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var appState = AppState()
    @StateObject private var speechService = SpeechService()
    @StateObject private var speechInputService = SpeechInputService()
    @StateObject private var locationService = LocationService()
    @StateObject private var amapGeocodingService: AMapGeocodingService

    init() {
        AMapManager.configure()
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
                    Task { await appState.restoreSession() }
                }
                .onChange(of: scenePhase) { phase in
                    if phase != .active {
                        speechInputService.cancelRecognitionForLifecycle()
                    }
                }
        }
    }

    #if DEBUG || DEMO
    private func applyUITestLaunchConfigurationIfNeeded() {
        let environment = ProcessInfo.processInfo.environment
        guard environment["AIDRUN_UI_TEST_RESET_STATE"] == "1" else { return }

        let defaults = UserDefaults.standard
        let resetToken = environment["AIDRUN_UI_TEST_RESET_TOKEN"] ?? "legacy-reset-token"
        let resetTokenKey = "com.aidrun.mvp.uiTestLastResetToken"
        guard defaults.string(forKey: resetTokenKey) != resetToken else { return }

        defaults.set(resetToken, forKey: resetTokenKey)
        defaults.removeObject(forKey: AppConstants.UserDefaultsKeys.accessToken)
        defaults.removeObject(forKey: AppConstants.UserDefaultsKeys.activeRole)
        defaults.removeObject(forKey: "com.aidrun.mvp.mockAPIStore.snapshot")
        appState.clearSession()

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
            defaults.set(accessToken, forKey: AppConstants.UserDefaultsKeys.accessToken)
            appState.accessToken = accessToken
        }
        if let activeRole = resolvedUITestRoleRaw(from: environment["AIDRUN_UI_TEST_ACTIVE_ROLE"]) {
            defaults.set(activeRole, forKey: AppConstants.UserDefaultsKeys.activeRole)
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
