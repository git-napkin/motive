//
//  ConfigManager+Provider.swift
//  Motive
//
//  Created by geezerrrr on 2026/1/19.
//

import Foundation

extension ConfigManager {
    // MARK: - Per-Provider Configuration Accessors
    
    /// Base URL for current provider (stored in Keychain per-provider)
    var baseURL: String {
        get {
            if let cached = cachedBaseURLs[provider] {
                return cached
            }
            let account = "opencode.base.url.\(provider.rawValue)"
            let value = KeychainStore.read(service: keychainService, account: account)
                ?? providerConfigStore.defaultBaseURL(for: provider)
            cachedBaseURLs[provider] = value
            return value
        }
        set {
            cachedBaseURLs[provider] = newValue
            let account = "opencode.base.url.\(provider.rawValue)"
            if newValue.isEmpty {
                KeychainStore.delete(service: keychainService, account: account)
            } else {
                KeychainStore.write(service: keychainService, account: account, value: newValue)
            }
        }
    }

    /// Model name for current provider
    var modelName: String {
        get { providerConfigStore.modelName(for: provider) }
        set { providerConfigStore.setModelName(newValue, for: provider) }
    }
    
    /// API Key for current provider (stored in Keychain per-provider)
    var apiKey: String {
        get {
            if let cached = cachedAPIKeys[provider] {
                return cached
            }
            let account = "opencode.api.key.\(provider.rawValue)"
            let value = KeychainStore.read(service: keychainService, account: account) ?? ""
            cachedAPIKeys[provider] = value
            return value
        }
        set {
            cachedAPIKeys[provider] = newValue
            let account = "opencode.api.key.\(provider.rawValue)"
            if newValue.isEmpty {
                KeychainStore.delete(service: keychainService, account: account)
            } else {
                KeychainStore.write(service: keychainService, account: account, value: newValue)
            }
        }
    }

    var hasAPIKey: Bool {
        // Check if provider requires API key
        if !provider.requiresAPIKey { return true }
        // Check cache first to avoid Keychain prompt
        if let cached = cachedAPIKeys[provider] {
            return !cached.isEmpty
        }
        // Fall back to full check (will trigger Keychain if needed)
        return !apiKey.isEmpty
    }
    
    /// Check if current provider is properly configured
    var isProviderConfigured: Bool {
        switch provider {
        case .ollama:
            return !baseURL.isEmpty
        case .lmstudio:
            // LM Studio only needs local base URL
            return !baseURL.isEmpty
        default:
            return hasAPIKey
        }
    }
    
    /// Get configuration error message for current provider
    var providerConfigurationError: String? {
        if let urlError = validateBaseURLFormat() {
            return urlError
        }

        switch provider {
        case .ollama:
            if baseURL.isEmpty { return "Ollama Base URL not configured" }
        case .lmstudio:
            if baseURL.isEmpty { return "LM Studio Base URL not configured" }
        default:
            if provider.requiresAPIKey && apiKey.isEmpty {
                return "\(provider.displayName) API Key not configured"
            }
        }
        return nil
    }
    
    /// Get user-specified model override for OpenCode.
    /// - Returns: Raw user input if provided; otherwise `nil` so OpenCode can choose defaults.
    func getModelString() -> String? {
        let modelValue = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !modelValue.isEmpty else { return nil }
        return modelValue
    }

    /// Validate only URL syntax; never rewrite user input.
    private func validateBaseURLFormat() -> String? {
        let raw = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }

        guard let components = URLComponents(string: raw),
              let scheme = components.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"),
              components.host != nil else {
            return "Invalid Base URL format. Use a full URL like https://api.example.com/v1"
        }

        return nil
    }
}
