//
//  AdvancedSettingsView.swift
//  Motive
//
//  Created by geezerrrr on 2026/1/19.
//

import SwiftUI
import UniformTypeIdentifiers

struct AdvancedSettingsView: View {
    @EnvironmentObject private var configManager: ConfigManager
    @EnvironmentObject private var appState: AppState
    @State private var showFileImporter = false
    @State private var isImporting = false
    @State private var importError: String?
    @FocusState private var isFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                // Header
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Advanced")
                        .font(.Velvet.displayMedium)
                        .foregroundColor(Color.Velvet.textPrimary)
                    
                    Text("Developer options and diagnostics")
                        .font(.Velvet.body)
                        .foregroundColor(Color.Velvet.textSecondary)
                }
                
                // Binary Section
                SettingsSection(title: "OpenCode Binary", icon: "terminal") {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Text("Select the OpenCode binary to use. It will be copied and signed for execution.")
                            .font(.Velvet.caption)
                            .foregroundColor(Color.Velvet.textMuted)
                        
                        // Source path display
                        if !configManager.openCodeBinarySourcePath.isEmpty {
                            HStack(spacing: Spacing.xs) {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color.Velvet.textMuted)
                                Text("Source: \(configManager.openCodeBinarySourcePath)")
                                    .font(.Velvet.caption)
                                    .foregroundColor(Color.Velvet.textMuted)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        
                        // Status indicator
                        HStack(spacing: Spacing.xs) {
                            switch configManager.binaryStatus {
                            case .notConfigured:
                                Image(systemName: "questionmark.circle")
                                    .font(.system(size: 11))
                                     .foregroundColor(Color.Velvet.warning)
                                Text("No binary configured")
                                    .font(.Velvet.caption)
                                    .foregroundColor(Color.Velvet.textMuted)
                                
                            case .ready(let path):
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color.Velvet.success)
                                Text("Ready: \(path)")
                                    .font(.Velvet.caption)
                                    .foregroundColor(Color.Velvet.textMuted)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                
                            case .error(let error):
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color.Velvet.error)
                                Text(error)
                                    .font(.Velvet.caption)
                                    .foregroundColor(Color.Velvet.textMuted)
                            }
                        }
                        
                        // Import error
                        if let error = importError {
                            HStack(spacing: Spacing.xs) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color.Velvet.error)
                                Text(error)
                                    .font(.Velvet.caption)
                                    .foregroundColor(Color.Velvet.error)
                            }
                        }
                        
                        // Action buttons
                        HStack(spacing: Spacing.md) {
                            Button {
                                showFileImporter = true
                            } label: {
                                HStack(spacing: Spacing.xs) {
                                    if isImporting {
                                        ProgressView()
                                            .scaleEffect(0.7)
                                    } else {
                                        Image(systemName: "folder")
                                    }
                                    Text(isImporting ? "Importing..." : "Select Binary")
                                }
                            }
                            .buttonStyle(VelvetButtonStyle())
                            .disabled(isImporting)
                            
                            if case .ready = configManager.binaryStatus {
                                Button("Restart Agent") {
                                    appState.restartAgent()
                                }
                                .buttonStyle(VelvetSecondaryButtonStyle())
                            }
                            
                            // Auto-detect button
                            Button("Auto-Detect") {
                                autoDetectAndImport()
                            }
                            .buttonStyle(VelvetSecondaryButtonStyle())
                            .disabled(isImporting)
                        }
                    }
                }
                
                // Debug Section
                SettingsSection(title: "Diagnostics", icon: "ant") {
                    SettingsRow(label: "Debug Mode", description: "Enable verbose logging for troubleshooting") {
                        Toggle("", isOn: $configManager.debugMode)
                            .toggleStyle(.switch)
                            .tint(Color.Velvet.primary)
                    }
                    
                    if configManager.debugMode {
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("Debug mode is enabled. OpenCode will produce verbose output.")
                                .font(.Velvet.caption)
                                .foregroundColor(Color.Velvet.warning)
                        }
                        .padding(Spacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.Velvet.warning.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small, style: .continuous))
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                
                // About Section
                SettingsSection(title: "About", icon: "info.circle") {
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        aboutRow("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                        aboutRow("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                        aboutRow("macOS", value: ProcessInfo.processInfo.operatingSystemVersionString)
                    }
                }
                
                Spacer()
            }
            .padding(Spacing.xl)
        }
        .animation(.velvetSpring, value: configManager.debugMode)
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.unixExecutable, .item],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                importBinary(from: url)
            }
        }
        .onAppear {
            // Check current status
            _ = configManager.resolveBinary()
        }
    }
    
    private func importBinary(from url: URL) {
        isImporting = true
        importError = nil
        
        Task {
            do {
                try await configManager.importBinary(from: url)
                appState.restartAgent()
            } catch {
                importError = error.localizedDescription
            }
            isImporting = false
        }
    }
    
    private func autoDetectAndImport() {
        isImporting = true
        importError = nil
        
        Task {
            let result = await configManager.getSignedBinaryURL()
            if let error = result.error {
                importError = error
            } else {
                appState.restartAgent()
            }
            isImporting = false
        }
    }
    
    private func aboutRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.Velvet.body)
                .foregroundColor(Color.Velvet.textSecondary)
            Spacer()
            Text(value)
                .font(.Velvet.mono)
                .foregroundColor(Color.Velvet.textMuted)
        }
    }
}
