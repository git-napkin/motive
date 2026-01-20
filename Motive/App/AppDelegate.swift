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
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var permissionCheckTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon - we're a menu bar app
        NSApp.setActivationPolicy(.accessory)
        
        // Apply saved appearance mode
        appState?.configManagerRef.applyAppearance()
        
        // Start the app state (creates status bar, etc.)
        appState?.start()
        // Retry status bar creation after launch (safety)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.appState?.ensureStatusBar()
        }
        
        // Request accessibility permission
        requestAccessibilityAndRegisterHotkey()
        
        // Hide command bar initially - user can invoke via hotkey
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.appState?.hideCommandBar()
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        unregisterHotkey()
        permissionCheckTimer?.invalidate()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Check if permission was granted while app was in background
        if globalMonitor == nil && AccessibilityHelper.hasPermission {
            registerHotkey()
        }
        appState?.ensureStatusBar()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        appState?.showCommandBar()
        return true
    }
    
    // MARK: - Accessibility Permission
    
    private func requestAccessibilityAndRegisterHotkey() {
        if AccessibilityHelper.hasPermission {
            // Already have permission
            registerHotkey()
            return
        }
        
        // Try to trigger system prompt (only works first time)
        let prompted = AccessibilityHelper.requestPermission()
        
        if !prompted {
            // System didn't show prompt (already asked before), show our own guide
            showAccessibilityGuide()
        }
        
        // Start polling for permission grant
        startPermissionCheckTimer()
    }
    
    private func showAccessibilityGuide() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let alert = NSAlert()
            alert.messageText = "Enable Accessibility for Hotkey"
            alert.informativeText = """
            To use the ⌥Space hotkey, please enable Motive in:
            
            System Settings → Privacy & Security → Accessibility
            
            Find "Motive" in the list and turn it ON.
            
            (If Motive is not in the list, you may need to click '+' and add it manually from Applications folder)
            """
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "I'll do it later")
            
            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                AccessibilityHelper.openAccessibilitySettings()
            }
        }
    }
    
    private func startPermissionCheckTimer() {
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                if AccessibilityHelper.hasPermission {
                    self?.permissionCheckTimer?.invalidate()
                    self?.permissionCheckTimer = nil
                    self?.registerHotkey()
                }
            }
        }
    }
    
    // MARK: - Global Hotkey (⌥Space - Option+Space)
    
    private func registerHotkey() {
        guard globalMonitor == nil else { return }  // Already registered
        
        // Global monitor for when app is not active
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyEvent(event)
        }
        
        // Local monitor for when app is active
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handleKeyEvent(event) == true {
                return nil  // Consume the event
            }
            return event
        }
        
        Log.debug("Hotkey ⌥Space registered successfully")
    }
    
    private func unregisterHotkey() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }
    
    @discardableResult
    private func handleKeyEvent(_ event: NSEvent) -> Bool {
        // Check for ⌥Space (Option + Space)
        let optionPressed = event.modifierFlags.contains(.option)
        let noOtherModifiers = !event.modifierFlags.contains(.command) 
            && !event.modifierFlags.contains(.control)
            && !event.modifierFlags.contains(.shift)
        let isSpace = event.keyCode == 49  // Space key
        
        if optionPressed && noOtherModifiers && isSpace {
            Task { @MainActor [weak self] in
                self?.toggleCommandBar()
            }
            return true
        }
        return false
    }
    
    private func toggleCommandBar() {
        guard let appState else { return }
        
        if let window = appState.commandBarWindowRef, window.isVisible {
            appState.hideCommandBar()
        } else {
            appState.showCommandBar()
        }
    }
}
