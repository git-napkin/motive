//
//  GeneralSettingsView.swift
//  Motive
//
//  Created by geezerrrr on 2026/1/19.
//

import AppKit
import SwiftUI

struct GeneralSettingsView: View {
    @EnvironmentObject private var configManager: ConfigManager
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var showRestartAlert = false
    
    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Startup
            SettingsCard(title: L10n.Settings.startup, icon: "power") {
                SettingsRow(label: L10n.Settings.launchAtLogin, description: L10n.Settings.launchAtLoginDesc, showDivider: false) {
                    Toggle("", isOn: $configManager.launchAtLogin)
                        .toggleStyle(.switch)
                        .tint(Color.Velvet.primary)
                }
            }
            
            // Keyboard
            SettingsCard(title: L10n.Settings.keyboard, icon: "keyboard") {
                SettingsRow(label: L10n.Settings.globalHotkey, description: L10n.Settings.globalHotkeyDesc, showDivider: false) {
                    HotkeyRecorderView(hotkey: $configManager.hotkey)
                        .frame(width: 120, height: 28)
                }
            }

            // Appearance
            SettingsCard(title: L10n.Settings.appearance, icon: "circle.lefthalf.filled") {
                VStack(spacing: 0) {
                    SettingsRow(label: L10n.Settings.theme, description: L10n.Settings.themeDesc, showDivider: true) {
                        Picker("", selection: Binding(
                            get: { configManager.appearanceMode },
                            set: { configManager.appearanceMode = $0 }
                        )) {
                            ForEach(ConfigManager.AppearanceMode.allCases) { mode in
                                Text(mode.localizedName).tag(mode)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 120)
                    }
                    
                    SettingsRow(label: L10n.Settings.language, description: L10n.Settings.languageDesc, showDivider: false) {
                        Picker("", selection: Binding(
                            get: { configManager.language },
                            set: { newValue in
                                let oldValue = configManager.language
                                configManager.language = newValue
                                if oldValue != newValue {
                                    showRestartAlert = true
                                }
                            }
                        )) {
                            ForEach(ConfigManager.Language.allCases) { lang in
                                Text(lang.displayName).tag(lang)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 120)
                    }
                }
            }
        }
        .alert(L10n.Settings.language, isPresented: $showRestartAlert) {
            Button(L10n.cancel) { }
            Button(L10n.Settings.restartNow) {
                restartApp()
            }
        } message: {
            Text(L10n.Settings.languageRestartRequired)
        }
    }
    
    private func restartApp() {
        guard let bundlePath = Bundle.main.bundlePath as String? else { return }
        
        // Use shell script to wait and relaunch
        let script = """
        sleep 0.5
        open "\(bundlePath)"
        """
        
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", script]
        
        do {
            try task.run()
        } catch {
            Log.error("Failed to restart: \(error)")
        }
        
        // Force quit the app
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApplication.shared.terminate(nil)
        }
    }
}

// MARK: - Hotkey Recorder

struct HotkeyRecorderView: NSViewRepresentable {
    @Binding var hotkey: String

    func makeNSView(context: Context) -> HotkeyRecorderButton {
        let button = HotkeyRecorderButton()
        button.onHotkeyChange = { hotkey = $0 }
        button.currentHotkey = hotkey
        return button
    }

    func updateNSView(_ nsView: HotkeyRecorderButton, context: Context) {
        nsView.currentHotkey = hotkey
    }
}

final class HotkeyRecorderButton: NSButton {
    var onHotkeyChange: ((String) -> Void)?
    var currentHotkey: String = "" {
        didSet {
            updateTitle()
        }
    }
    private var isRecording = false
    private var localMonitor: Any?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupAppearance()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupAppearance()
    }
    
    private func setupAppearance() {
        bezelStyle = .rounded
        isBordered = true
        font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        wantsLayer = true
        target = self
        action = #selector(buttonClicked)
        updateTitle()
    }
    
    private func updateTitle() {
        if isRecording {
            title = L10n.Settings.pressKeys
        } else if currentHotkey.isEmpty {
            title = L10n.Settings.clickToRecord
        } else {
            title = currentHotkey
        }
    }
    
    @objc private func buttonClicked() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    private func startRecording() {
        isRecording = true
        updateTitle()
        
        // Listen for key events
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self = self, self.isRecording else { return event }
            
            if event.type == .keyDown {
                let symbols = self.modifierSymbols(for: event.modifierFlags)
                let key = self.keyName(for: event)
                
                // Only record if there's a modifier or it's a special key
                if !symbols.isEmpty || self.isSpecialKey(event.keyCode) {
                    let value = symbols + key
                    self.currentHotkey = value
                    self.onHotkeyChange?(value)
                    self.stopRecording()
                    return nil // Consume the event
                }
            }
            return event
        }
        
        // Stop recording when clicking elsewhere
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.stopRecording()
        }
    }
    
    private func stopRecording() {
        isRecording = false
        updateTitle()
        
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }
    
    private func isSpecialKey(_ keyCode: UInt16) -> Bool {
        // Function keys, arrows, etc.
        return [49, 36, 48, 51, 53, 123, 124, 125, 126].contains(keyCode) ||
               (keyCode >= 122 && keyCode <= 126) // F keys start around here
    }

    private func modifierSymbols(for flags: NSEvent.ModifierFlags) -> String {
        var symbols = ""
        if flags.contains(.control) { symbols += "⌃" }
        if flags.contains(.option) { symbols += "⌥" }
        if flags.contains(.shift) { symbols += "⇧" }
        if flags.contains(.command) { symbols += "⌘" }
        return symbols
    }
    
    private func keyName(for event: NSEvent) -> String {
        switch event.keyCode {
        case 49: return "Space"
        case 36: return "Return"
        case 48: return "Tab"
        case 51: return "Delete"
        case 53: return "Escape"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default:
            return event.charactersIgnoringModifiers?.uppercased() ?? ""
        }
    }
    
    deinit {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
