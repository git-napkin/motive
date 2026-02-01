//
//  MotiveRemoteApp.swift
//  MotiveRemote
//
//  iOS remote control for Motive on Mac
//

import AppIntents
import SwiftUI

@main
struct MotiveRemoteApp: App {
    @StateObject private var cloudKitManager = RemoteCloudKitManager()
    
    init() {
        // Register App Shortcuts with the system
        Task {
            try? await MotiveShortcuts.updateAppShortcutParameters()
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(cloudKitManager)
        }
    }
}
