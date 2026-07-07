//
//  blindRunApp.swift
//  blindRun
//
//  Created by Jerry on 5/18/26.
//

import SwiftUI

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
                .onAppear {
                    #if DEBUG || DEMO
                    applyUITestLaunchConfigurationIfNeeded()
                    #endif
                    appState.restoreSession()
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
    #endif
}
