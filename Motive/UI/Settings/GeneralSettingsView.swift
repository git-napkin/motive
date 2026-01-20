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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                // Header
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("General")
                        .font(.Velvet.displayMedium)
                        .foregroundColor(Color.Velvet.textPrimary)
                    
                    Text("Configure startup behavior and keyboard shortcuts")
                        .font(.Velvet.body)
                        .foregroundColor(Color.Velvet.textSecondary)
                }
                
                // Startup Section
                SettingsSection(title: "Startup", icon: "power") {
                    SettingsRow(label: "Launch at Login", description: "Automatically start Motive when you log in") {
                        Toggle("", isOn: $configManager.launchAtLogin)
                            .toggleStyle(.switch)
                            .tint(Color.Velvet.primary)
                    }
                }
                
                // Keyboard Section
                SettingsSection(title: "Keyboard", icon: "keyboard") {
                    SettingsRow(label: "Global Hotkey", description: "Shortcut to open Command Bar") {
                        HotkeyRecorderView(hotkey: $configManager.hotkey)
                            .frame(width: 140, height: 28)
                    }
                }

                // Appearance Section
                SettingsSection(title: "Appearance", icon: "circle.lefthalf.filled") {
                    SettingsRow(label: "Theme", description: "Follow system or force Light/Dark") {
                        Picker("", selection: Binding(
                            get: { configManager.appearanceMode },
                            set: { configManager.appearanceMode = $0 }
                        )) {
                            ForEach(ConfigManager.AppearanceMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .frame(width: 140)
                    }
                }
                
                Spacer()
            }
            .padding(Spacing.xl)
        }
    }
}

// MARK: - Hotkey Recorder

struct HotkeyRecorderView: NSViewRepresentable {
    @Binding var hotkey: String

    func makeNSView(context: Context) -> HotkeyRecorderField {
        let field = HotkeyRecorderField()
        field.onHotkeyChange = { hotkey = $0 }
        field.stringValue = hotkey
        return field
    }

    func updateNSView(_ nsView: HotkeyRecorderField, context: Context) {
        nsView.stringValue = hotkey
    }
}

final class HotkeyRecorderField: NSTextField {
    var onHotkeyChange: ((String) -> Void)?
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupAppearance()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupAppearance()
    }
    
    private func setupAppearance() {
        isBordered = false
        isEditable = false  // Only respond to key events, not text input
        isSelectable = false
        backgroundColor = NSColor.black.withAlphaComponent(0.05)
        font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        alignment = .center
        wantsLayer = true
        layer?.cornerRadius = 6
        focusRingType = .none
        placeholderString = "Click to record"
    }

    override func keyDown(with event: NSEvent) {
        let symbols = modifierSymbols(for: event.modifierFlags)
        let key = keyName(for: event)
        let value = symbols + key
        stringValue = value
        onHotkeyChange?(value)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        keyDown(with: event)
        return true
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
        // Handle special keys
        switch event.keyCode {
        case 49: return "Space"      // Space bar
        case 36: return "Return"     // Return/Enter
        case 48: return "Tab"        // Tab
        case 51: return "Delete"     // Delete/Backspace
        case 53: return "Escape"     // Escape
        case 123: return "←"         // Left arrow
        case 124: return "→"         // Right arrow
        case 125: return "↓"         // Down arrow
        case 126: return "↑"         // Up arrow
        default:
            return event.charactersIgnoringModifiers?.uppercased() ?? ""
        }
    }
}
