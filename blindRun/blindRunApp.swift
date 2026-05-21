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

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(speechService)
                .onAppear {
                    appState.restoreSession()
                }
        }
    }
}
