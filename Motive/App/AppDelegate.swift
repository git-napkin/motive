//
//  AppDelegate.swift
//  Motive
//
//  Created by geezerrrr on 2026/1/19.
//

import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var appState: AppState?
    private let hotkeyManager = CarbonHotkeyManager()
    private var hotkeyObserver: NSObjectProtocol?
    private var onboardingController: OnboardingWindowController?
    private var onboardingObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon - we're a menu bar app
        NSApp.setActivationPolicy(.accessory)

        // Create the status bar icon immediately — before anything else.
        // This guarantees it is visible from the very first frame, regardless
        // of whether onboarding is shown or skipped.
        appState?.ensureStatusBar()

        // Clean up stale child processes from previous runs
        OpenCodeServer.terminateStaleProcess()
        cleanupBrowserSidecar()

        // Apply saved appearance mode
        appState?.configManagerRef.applyAppearance()

        // Check if onboarding is needed
        if let configManager = appState?.configManagerRef, !configManager.hasCompletedOnboarding {
            showOnboarding()
            return
        }

        // Normal startup
        startNormalFlow()
    }

    /// Show onboarding window for first-time users
    private func showOnboarding() {
        guard let appState else { return }

        // Show dock icon during onboarding for better UX
        NSApp.setActivationPolicy(.regular)

        onboardingController = OnboardingWindowController()
        onboardingController?.show(configManager: appState.configManagerRef, appState: appState)

        // Observe when onboarding completes - store reference for cleanup
        onboardingObserver = NotificationCenter.default.addObserver(
            forName: .onboardingCompleted,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { [weak self] in
                await MainActor.run {
                    self?.onboardingDidComplete()
                }
            }
        }
    }

    /// Called when onboarding is completed
    private func onboardingDidComplete() {
        // Clean up the observer
        if let observer = onboardingObserver {
            NotificationCenter.default.removeObserver(observer)
            onboardingObserver = nil
        }
        
        onboardingController?.close()
        onboardingController = nil

        // Switch back to accessory app (menu bar only)
        NSApp.setActivationPolicy(.accessory)

        // Start normal flow (status bar already exists from applicationDidFinishLaunching)
        startNormalFlow()
    }

    /// Start the normal app flow (after onboarding or on subsequent launches)
    private func startNormalFlow() {
        appState?.start()

        // Observe hotkey changes from settings
        observeHotkeyChanges()

        // Command bar starts hidden — user invokes via hotkey
        appState?.hideCommandBar()
    }


    // MARK: - URL Scheme Handler (motive://)
    //
    // Supported URLs:
    //   motive://run?intent=<text>              → submit intent in current project
    //   motive://run?intent=<text>&dir=<path>   → submit intent in given directory
    //   motive://new                             → open CommandBar (same as hotkey)
    //   motive://settings[?tab=<tab>]            → open Settings, optionally to a tab
    //
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            handleMotiveURL(url)
        }
    }

    private func handleMotiveURL(_ url: URL) {
        guard url.scheme?.lowercased() == "motive" else { return }
        let host = url.host?.lowercased() ?? ""
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let params = Dictionary(
            uniqueKeysWithValues: (components?.queryItems ?? []).compactMap { item -> (String, String)? in
                guard let value = item.value else { return nil }
                return (item.name, value)
            }
        )

        switch host {
        case "run":
            guard let intent = params["intent"], !intent.isEmpty else {
                appState?.showCommandBar()
                return
            }
            let dir = params["dir"]
            Task { @MainActor [weak self] in
                if let dir {
                    self?.appState?.submitIntent(intent, workingDirectory: dir)
                } else {
                    self?.appState?.submitIntent(intent)
                }
                self?.appState?.showDrawer()
            }

        case "new":
            appState?.showCommandBar()

        case "settings":
            let tabName = params["tab"] ?? "general"
            let tab = SettingsTab(rawValue: tabName) ?? .general
            SettingsWindowController.shared.show(tab: tab)

        default:
            // Unknown host — just bring up the CommandBar
            appState?.showCommandBar()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState?.stopScheduledTaskSystem()
        appState?.cleanupObservers()
        unregisterHotkey()
        if let observer = hotkeyObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = onboardingObserver {
            NotificationCenter.default.removeObserver(observer)
            onboardingObserver = nil
        }

        appState?.bridge.terminateServerImmediately()
        cleanupBrowserSidecar()
    }

    /// Kill any browser-use-sidecar processes when app terminates
    private func cleanupBrowserSidecar() {
        // Method 1: Try to send close command via CLI
        // Supports both --onedir and --onefile builds
        if let dirURL = Bundle.main.url(forResource: "browser-use-sidecar", withExtension: nil) {
            var sidecarPath = dirURL.appendingPathComponent("browser-use-sidecar").path
            if !FileManager.default.isExecutableFile(atPath: sidecarPath) {
                sidecarPath = dirURL.path
            }
            if FileManager.default.isExecutableFile(atPath: sidecarPath) {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: sidecarPath)
                process.arguments = ["close"]
                process.standardOutput = nil
                process.standardError = nil
                do { try process.run() } catch { Log.debug("Sidecar close command failed: \(error)") }
            }
        }

        // Method 2: Kill by PID file (backup)
        let pidPath = FileManager.default.temporaryDirectory.appendingPathComponent("browser-use-sidecar.pid")
        if let pidString = try? String(contentsOf: pidPath, encoding: .utf8),
           let pid = Int32(pidString.trimmingCharacters(in: .whitespacesAndNewlines))
        {
            kill(pid, SIGTERM)
        }

        // Clean up temp files — ignore errors (files may not exist)
        let tempDir = FileManager.default.temporaryDirectory
        for file in ["browser-use-sidecar.sock", "browser-use-sidecar.pid", "browser-use-sidecar.lock"] {
            try? FileManager.default.removeItem(at: tempDir.appendingPathComponent(file))
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Skip during onboarding
        guard onboardingController == nil else { return }

        registerHotkey()
        appState?.ensureStatusBar()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Skip during onboarding
        guard onboardingController == nil else { return true }

        // Dock icon click opens Settings (not the command bar)
        SettingsWindowController.shared.show()
        return true
    }

    // MARK: - Global Hotkey

    private func observeHotkeyChanges() {
        // Observe UserDefaults changes for hotkey
        hotkeyObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { [weak self] in
                await MainActor.run {
                    self?.reregisterHotkey()
                }
            }
        }
    }

    private func reregisterHotkey() {
        // Only re-parse if the hotkey string changed
        registerHotkey()
    }

    private func registerHotkey() {
        guard let configManager = appState?.configManagerRef else { return }
        let (modifiers, keyCode) = HotkeyParser.parseToKeyCode(configManager.hotkey)

        hotkeyManager.onKeyDown = { [weak self] in
            self?.toggleCommandBar()
        }

        if hotkeyManager.register(modifiers: modifiers, keyCode: keyCode) {
            Log.debug("Hotkey \(configManager.hotkey) registered successfully via Carbon")
        } else {
            Log.error("Failed to register hotkey \(configManager.hotkey)")
        }
    }

    private func unregisterHotkey() {
        hotkeyManager.unregister()
    }

    private func toggleCommandBar() {
        guard let appState else { return }

        if appState.isCommandBarVisible {
            appState.hideCommandBar()
        } else {
            appState.showCommandBar()
        }
    }
}
