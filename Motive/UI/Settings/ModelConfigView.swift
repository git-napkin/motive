//
//  ModelConfigView.swift
//  Motive
//
//  Created by geezerrrr on 2026/1/19.
//

import SwiftUI

struct ModelConfigView: View {
    @EnvironmentObject private var configManager: ConfigManager
    @EnvironmentObject private var appState: AppState

    @State private var showSavedFeedback = false
    @FocusState private var focusedField: Field?
    
    enum Field: Hashable {
        case baseURL, apiKey, modelName
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                // Header
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text("Model Configuration")
                        .font(.Velvet.displayMedium)
                        .foregroundColor(Color.Velvet.textPrimary)
                    
                    Text("Configure the AI model provider and credentials")
                        .font(.Velvet.body)
                        .foregroundColor(Color.Velvet.textSecondary)
                }
                
                // Provider Section
                SettingsSection(title: "Provider", icon: "cpu") {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        providerPicker
                    }
                }
                
                // Connection Section - per provider
                SettingsSection(title: "\(configManager.provider.displayName) Configuration", icon: "network") {
                    VStack(spacing: Spacing.md) {
                        // API Key (not for Ollama)
                        if configManager.provider != .ollama {
                            VStack(alignment: .leading, spacing: Spacing.xs) {
                                HStack {
                                    Text("API Key")
                                        .font(.Velvet.label)
                                        .foregroundColor(Color.Velvet.textSecondary)
                                    
                                    if configManager.hasAPIKey {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 10))
                                            .foregroundColor(Color.Velvet.success)
                                    }
                                }
                                
                                SecureField(apiKeyPlaceholder, text: Binding(
                                    get: { configManager.apiKey },
                                    set: { configManager.apiKey = $0 }
                                ))
                                .textFieldStyle(VelvetTextFieldStyle(isFocused: focusedField == .apiKey))
                                .focused($focusedField, equals: .apiKey)
                            }
                        }
                        
                        // Base URL
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text(configManager.provider == .ollama ? "Ollama Host" : "Base URL (Optional)")
                                .font(.Velvet.label)
                                .foregroundColor(Color.Velvet.textSecondary)
                            
                            TextField(baseURLPlaceholder, text: $configManager.baseURL)
                                .textFieldStyle(VelvetTextFieldStyle(isFocused: focusedField == .baseURL))
                                .focused($focusedField, equals: .baseURL)
                        }
                        
                        // Model Name
                        VStack(alignment: .leading, spacing: Spacing.xs) {
                            Text("Model Name")
                                .font(.Velvet.label)
                                .foregroundColor(Color.Velvet.textSecondary)
                            
                            TextField(modelPlaceholder, text: $configManager.modelName)
                                .textFieldStyle(VelvetTextFieldStyle(isFocused: focusedField == .modelName))
                                .focused($focusedField, equals: .modelName)
                        }
                        
                        // Configuration status
                        if let error = configManager.providerConfigurationError {
                            HStack(spacing: Spacing.xs) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color.Velvet.warning)
                                Text(error)
                                    .font(.Velvet.caption)
                                    .foregroundColor(Color.Velvet.warning)
                            }
                            .padding(Spacing.sm)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.Velvet.warning.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
                        }
                    }
                }
                
                // Action Button
            HStack {
                    Spacer()
                    
                    if showSavedFeedback {
                        HStack(spacing: Spacing.xs) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(Color.Velvet.success)
                            Text("Agent restarted")
                                .font(.Velvet.caption)
                                .foregroundColor(Color.Velvet.textSecondary)
                        }
                        .transition(.opacity.combined(with: .scale))
                    }
                    
                    Button(action: saveAndRestart) {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Save & Restart Agent")
                        }
                    }
                    .buttonStyle(VelvetButtonStyle())
                }
                
                Spacer()
            }
            .padding(Spacing.xl)
        }
        .animation(.quickSpring, value: showSavedFeedback)
    }
    
    // MARK: - Provider Picker
    
    private var providerPicker: some View {
        HStack(spacing: Spacing.sm) {
            ForEach(ConfigManager.Provider.allCases) { provider in
                ProviderCard(
                    provider: provider,
                    isSelected: configManager.provider == provider
                ) {
                    withAnimation(.quickSpring) {
                        configManager.provider = provider
                    }
                }
            }
        }
    }
    
    private var modelPlaceholder: String {
        switch configManager.provider {
        case .claude: return "claude-sonnet-4-20250514"
        case .openai: return "gpt-4o"
        case .ollama: return "llama3"
        }
    }
    
    private var apiKeyPlaceholder: String {
        switch configManager.provider {
        case .claude: return "sk-ant-..."
        case .openai: return "sk-..."
        case .ollama: return ""
        }
    }
    
    private var baseURLPlaceholder: String {
        switch configManager.provider {
        case .claude: return "https://api.anthropic.com (optional)"
        case .openai: return "https://api.openai.com (optional)"
        case .ollama: return "http://localhost:11434"
        }
    }
    
    private func saveAndRestart() {
                    appState.restartAgent()
        showSavedFeedback = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                showSavedFeedback = false
            }
        }
    }
}

// MARK: - Provider Card

struct ProviderCard: View {
    let provider: ConfigManager.Provider
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: Spacing.sm) {
                Image(systemName: provider.icon)
                    .font(.system(size: 24, weight: .light))
                    .foregroundColor(isSelected ? Color.Velvet.primary : Color.Velvet.textSecondary)
                
                Text(provider.displayName)
                    .font(.Velvet.label)
                    .foregroundColor(isSelected ? Color.Velvet.textPrimary : Color.Velvet.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.medium, style: .continuous)
                    .fill(isSelected ? Color.Velvet.primary.opacity(0.1) : (isHovering ? Color.black.opacity(0.04) : Color.black.opacity(0.02)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: CornerRadius.medium, style: .continuous)
                    .stroke(isSelected ? Color.Velvet.primary.opacity(0.4) : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.15), value: isHovering)
    }
}

// MARK: - Provider Extension

extension ConfigManager.Provider {
    var icon: String {
        switch self {
        case .claude: return "sparkles.rectangle.stack"
        case .openai: return "brain.head.profile"
        case .ollama: return "desktopcomputer"
        }
    }
}
