//
//  blindRunApp.swift
//  blindRun
//
//  Created by Jerry on 5/18/26.
//

import SwiftUI

@main
struct blindRunApp: App {
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
                    applyUITestLaunchConfigurationIfNeeded()
                    appState.restoreSession()
                }
        }
    }

    #if DEBUG
    private func applyUITestLaunchConfigurationIfNeeded() {
        let environment = ProcessInfo.processInfo.environment
        guard environment["AIDRUN_UI_TEST_RESET_STATE"] == "1" else { return }

        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: AppConstants.UserDefaultsKeys.accessToken)
        defaults.removeObject(forKey: AppConstants.UserDefaultsKeys.activeRole)
        defaults.removeObject(forKey: "com.aidrun.mvp.mockAPIStore.snapshot")
        appState.clearSession()

        switch environment["AIDRUN_UI_TEST_API_ENV"] {
        case "localBackend":
            appState.currentEnvironment = .localBackend
            AppConstants.LocalBackend.save(environment["AIDRUN_UI_TEST_LOCAL_BACKEND_URL"] ?? "http://127.0.0.1:8080")
        case "mock":
            appState.currentEnvironment = .mock
        default:
            break
        }

        if let accessToken = environment["AIDRUN_UI_TEST_ACCESS_TOKEN"], !accessToken.isEmpty {
            defaults.set(accessToken, forKey: AppConstants.UserDefaultsKeys.accessToken)
        }
        if let activeRole = environment["AIDRUN_UI_TEST_ACTIVE_ROLE"], !activeRole.isEmpty {
            defaults.set(activeRole, forKey: AppConstants.UserDefaultsKeys.activeRole)
        }
    }
    #endif
}
