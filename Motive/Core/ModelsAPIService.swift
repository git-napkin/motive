//
//  ModelsAPIService.swift
//  Motive
//
//  Service to fetch available models from different AI providers
//

import Foundation
import Combine
import SwiftUI

struct ModelInfo: Identifiable, Hashable {
    let id: String
    let name: String
    let displayName: String
    
    init(id: String, name: String) {
        self.id = id
        self.name = name
        self.displayName = name
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}

enum ModelsAPIError: Error, LocalizedError {
    case noAPIKey
    case invalidURL
    case networkError(Error)
    case invalidResponse
    case authenticationError
    case rateLimited
    case noEndpoint
    
    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No API key configured"
        case .invalidURL:
            return "Invalid API endpoint"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from API"
        case .authenticationError:
            return "Authentication failed - check your API key"
        case .rateLimited:
            return "Rate limited - try again later"
        case .noEndpoint:
            return "This provider does not support model listing"
        }
    }
}

@MainActor
final class ModelsAPIService: ObservableObject {
    static let shared = ModelsAPIService()
    
    @Published var isLoading = false
    @Published var lastError: ModelsAPIError?
    
    private let session = URLSession.shared
    var configManager: ConfigManager?
    
    private init() {}
    
    func fetchModels(for provider: ConfigManager.Provider) async -> [ModelInfo] {
        NSLog("[ModelsAPI] fetchModels called for: \(provider.rawValue)")
        guard let configManager = configManager else {
            NSLog("[ModelsAPI] configManager is nil!")
            lastError = .noAPIKey
            return []
        }
        
        NSLog("[ModelsAPI] configManager exists")
        NSLog("[ModelsAPI] baseURL: '\(configManager.baseURL)'")
        NSLog("[ModelsAPI] apiKey present: \(!configManager.apiKey.isEmpty)")
        
        isLoading = true
        lastError = nil
        
        let baseURL = configManager.baseURL
        let apiKey = configManager.apiKey
        
        let result: [ModelInfo]
        
        switch provider {
        case .claude:
            result = await fetchFromURL(baseURL: baseURL, path: "/v1/models", apiKey: apiKey, style: .anthropic)
        case .openai:
            result = await fetchFromURL(baseURL: baseURL, path: "/v1/models", apiKey: apiKey, style: .openAI)
        case .gemini:
            result = await fetchFromURL(baseURL: baseURL, path: "/v1/models", apiKey: apiKey, style: .google)
        case .ollama:
            result = await fetchFromURL(baseURL: baseURL, path: "/api/tags", apiKey: nil, style: .ollama)
        case .openrouter:
            result = await fetchFromURL(baseURL: baseURL, path: "/v1/models", apiKey: apiKey, style: .openAI)
        case .mistral:
            result = await fetchFromURL(baseURL: baseURL, path: "/v1/models", apiKey: apiKey, style: .openAI)
        case .groq:
            result = await fetchFromURL(baseURL: baseURL, path: "/openai/v1/models", apiKey: apiKey, style: .openAI)
        case .cohere:
            result = await fetchFromURL(baseURL: baseURL, path: "/v2/models", apiKey: apiKey, style: .cohere)
        case .deepseek:
            result = await fetchFromURL(baseURL: baseURL, path: "/v1/models", apiKey: apiKey, style: .openAI)
        case .deepinfra:
            result = await fetchFromURL(baseURL: baseURL, path: "/v1/models", apiKey: apiKey, style: .deepinfra)
        case .xai:
            result = fetchKnownModels()
        case .minimax:
            result = fetchKnownModels()
        case .alibaba:
            result = await fetchFromURL(baseURL: baseURL, path: "/compatible-mode/v1/models", apiKey: apiKey, style: .openAI)
        case .moonshotai:
            result = await fetchFromURL(baseURL: baseURL, path: "/v1/models", apiKey: apiKey, style: .openAI)
        case .zhipuai:
            result = await fetchFromURL(baseURL: baseURL, path: "/api/paas/v4/models", apiKey: apiKey, style: .openAI)
        case .perplexity:
            result = fetchKnownModels()
        case .bedrock:
            result = fetchKnownModels()
        case .lmstudio:
            result = await fetchFromURL(baseURL: baseURL, path: "/v1/models", apiKey: nil, style: .openAI)
        }
        
        isLoading = false
        return result
    }
    
    private enum FetchStyle {
        case openAI        // Standard OpenAI: {"data": [{"id": "..."}]}
        case anthropic    // Anthropic: {"data": [{"id": "..."}]}
        case google       // Google: {"models": [{"name": "models/..."}]}
        case ollama       // Ollama: {"models": [{"name": "..."}]}
        case cohere       // Cohere v2: {"models": [{"id": "..."}]}
        case deepinfra    // DeepInfra: {"models": [{"model_id": "..."}]}
    }
    
    private func fetchFromURL(baseURL: String, path: String, apiKey: String?, style: FetchStyle) async -> [ModelInfo] {
        // If no base URL is set, use defaults
        var urlString = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Apply defaults for common providers if no URL provided
        if urlString.isEmpty {
            switch style {
            case .anthropic:
                urlString = "https://api.anthropic.com"
            case .google:
                urlString = "https://generativelanguage.googleapis.com"
            case .ollama:
                urlString = "http://localhost:11434"
            default:
                lastError = .noEndpoint
                return []
            }
        }
        
        // Append path
        urlString = urlString.appending(path)
        
        guard let url = URL(string: urlString) else {
            lastError = .invalidURL
            return []
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        
        // Set auth header based on style
        if let apiKey = apiKey, !apiKey.isEmpty {
            switch style {
            case .anthropic:
                request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            case .google:
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            case .cohere:
                request.setValue(apiKey, forHTTPHeaderField: "Authorization")
            case .deepinfra:
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            default:
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
        }
        
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                lastError = .invalidResponse
                return []
            }
            
            if httpResponse.statusCode == 401 {
                lastError = .authenticationError
                return []
            }
            
            if httpResponse.statusCode == 429 {
                lastError = .rateLimited
                return []
            }
            
            guard httpResponse.statusCode == 200 else {
                lastError = .invalidResponse
                return []
            }
            
            return parseModels(from: data, style: style)
        } catch {
            lastError = .networkError(error)
        }
        
        return []
    }
    
    private func parseModels(from data: Data, style: FetchStyle) -> [ModelInfo] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }
        
        switch style {
        case .openAI, .anthropic:
            if let models = json["data"] as? [[String: Any]] {
                return models.compactMap { model in
                    guard let id = model["id"] as? String else { return nil }
                    return ModelInfo(id: id, name: id)
                }
            }
        case .google:
            if let models = json["models"] as? [[String: Any]] {
                return models.compactMap { model in
                    guard let name = model["name"] as? String else { return nil }
                    let shortName = name.replacingOccurrences(of: "models/", with: "")
                    return ModelInfo(id: shortName, name: shortName)
                }
            }
        case .ollama:
            if let models = json["models"] as? [[String: Any]] {
                return models.compactMap { model in
                    guard let name = model["name"] as? String else { return nil }
                    return ModelInfo(id: name, name: name)
                }
            }
        case .cohere:
            if let models = json["models"] as? [[String: Any]] {
                return models.compactMap { model in
                    guard let id = model["id"] as? String else { return nil }
                    return ModelInfo(id: id, name: id)
                }
            }
        case .deepinfra:
            if let models = json["models"] as? [[String: Any]] {
                return models.compactMap { model in
                    guard let id = model["model_id"] as? String else { return nil }
                    return ModelInfo(id: id, name: id)
                }
            }
        }
        
        return []
    }
    
    private func fetchKnownModels() -> [ModelInfo] {
        // Return combined known models for providers without list endpoints
        // In a real implementation, you might want to store which provider was requested
        return [
            // xAI
            ModelInfo(id: "grok-2-1212", name: "grok-2-1212"),
            ModelInfo(id: "grok-2-vision-1212", name: "grok-2-vision-1212"),
            ModelInfo(id: "grok-beta", name: "grok-beta"),
            // MiniMax
            ModelInfo(id: "MiniMax-Text-01", name: "MiniMax-Text-01"),
            // Perplexity
            ModelInfo(id: "llama-3.1-sonar-small-128k-online", name: "llama-3.1-sonar-small-128k-online"),
            ModelInfo(id: "llama-3.1-sonar-large-128k-online", name: "llama-3.1-sonar-large-128k-online"),
            ModelInfo(id: "llama-3.1-sonar-huge-128k-online", name: "llama-3.1-sonar-huge-128k-online"),
            // AWS Bedrock
            ModelInfo(id: "anthropic.claude-3-sonnet-20240229-v1:0", name: "Claude 3 Sonnet"),
            ModelInfo(id: "anthropic.claude-3-haiku-20240307-v1:0", name: "Claude 3 Haiku"),
            ModelInfo(id: "anthropic.claude-3-5-sonnet-20241022-v2:0", name: "Claude 3.5 Sonnet"),
            ModelInfo(id: "anthropic.claude-3-5-haiku-20240307-v1:0", name: "Claude 3.5 Haiku"),
            ModelInfo(id: "meta.llama3.1-8b-instruct-v1:0", name: "Llama 3.1 8B"),
            ModelInfo(id: "meta.llama3.1-70b-instruct-v1:0", name: "Llama 3.1 70B"),
        ]
    }
}
