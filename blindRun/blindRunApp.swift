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
    @StateObject private var locationService = LocationService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(speechService)
                .environmentObject(locationService)
                .onAppear {
                    appState.restoreSession()
                    AMapManager.configure()
                }
        }
    }
}
