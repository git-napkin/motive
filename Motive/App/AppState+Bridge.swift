//
//  AppState+Bridge.swift
//  Motive
//
//  Created by geezerrrr on 2026/1/19.
//

import Combine
import Foundation
import SwiftData

extension AppState {
    func restartAgent() {
        Task {
            await configureBridge()
            await bridge.restart()
        }
    }

    func configureBridge() async {
        // Get signed binary (will auto-import and sign if needed)
        let resolution = await configManager.getSignedBinaryURL()
        guard let binaryURL = resolution.url else {
            lastErrorMessage = resolution.error ?? "OpenCode binary not found. Check Settings."
            menuBarState = .idle
            return
        }
        let config = OpenCodeBridge.Configuration(
            binaryURL: binaryURL,
            environment: configManager.makeEnvironment(),
            model: configManager.getModelString(),
            debugMode: configManager.debugMode
        )
        await bridge.updateConfiguration(config)

        // Sync browser agent API configuration
        BrowserUseBridge.shared.configureAgentAPIKey(
            envName: configManager.browserAgentProvider.envKeyName,
            apiKey: configManager.browserAgentAPIKey,
            baseUrlEnvName: configManager.browserAgentProvider.baseUrlEnvName,
            baseUrl: configManager.browserAgentBaseUrl
        )
    }

    func handle(event: OpenCodeEvent) {
        // Update UI state based on event kind
        switch event.kind {
        case .thought:
            menuBarState = .reasoning
            currentToolName = nil
        case .call, .tool:
            menuBarState = .executing
            currentToolName = event.toolName ?? "Processing"

            // Intercept AskUserQuestion tool calls
            if event.toolName == "AskUserQuestion", let inputDict = event.toolInputDict {
                handleAskUserQuestion(input: inputDict)
                return  // Don't add to message list
            }
        case .diff:
            menuBarState = .executing
            currentToolName = "Editing file"
        case .finish:
            menuBarState = .idle
            sessionStatus = .completed
            currentToolName = nil
            // Update session status
            if let session = currentSession {
                session.status = "completed"
            }
            // Show completion in status bar
            statusBarController?.showCompleted()
        case .assistant:
            menuBarState = .reasoning
            currentToolName = nil
        case .user:
            // User messages are added directly in submitIntent
            return
        case .unknown:
            // Check for various error patterns
            let errorText = detectError(in: event.text, rawJson: event.rawJson)
            if let error = errorText {
                lastErrorMessage = error
                sessionStatus = .failed
                if let session = currentSession {
                    session.status = "failed"
                }
                // Show error in status bar
                statusBarController?.showError()
            }
        }

        // Process event content (save session ID, add messages)
        processEventContent(event)
    }

    /// Handle AskUserQuestion tool call - show popup and send response via PTY
    private func handleAskUserQuestion(input: [String: Any]) {
        Log.debug("Intercepted AskUserQuestion tool call")

        // Parse questions from input
        guard let questions = input["questions"] as? [[String: Any]],
              let firstQuestion = questions.first else {
            Log.debug("AskUserQuestion: no questions found in input")
            return
        }

        let questionText = firstQuestion["question"] as? String ?? "Question from AI"
        let header = firstQuestion["header"] as? String ?? "Question"
        let multiSelect = firstQuestion["multiSelect"] as? Bool ?? false

        // Parse options
        var options: [PermissionRequest.QuestionOption] = []
        if let rawOptions = firstQuestion["options"] as? [[String: Any]] {
            options = rawOptions.map { opt in
                PermissionRequest.QuestionOption(
                    label: opt["label"] as? String ?? "",
                    description: opt["description"] as? String
                )
            }
        }

        // If no options provided, add default Yes/No/Other
        if options.isEmpty {
            options = [
                PermissionRequest.QuestionOption(label: "Yes"),
                PermissionRequest.QuestionOption(label: "No"),
                PermissionRequest.QuestionOption(label: "Other", description: "Custom response")
            ]
        }

        let requestId = "askuser_\(UUID().uuidString)"
        let request = PermissionRequest(
            id: requestId,
            taskId: requestId,
            type: .question,
            question: questionText,
            header: header,
            options: options,
            multiSelect: multiSelect
        )

        // Show quick confirm with custom handlers for AskUserQuestion
        if quickConfirmController == nil {
            quickConfirmController = QuickConfirmWindowController()
        }

        let anchorFrame = statusBarController?.buttonFrame

        quickConfirmController?.show(
            request: request,
            anchorFrame: anchorFrame,
            onResponse: { [weak self] (response: String) in
                // Send response to OpenCode via PTY stdin
                Log.debug("AskUserQuestion response: \(response)")
                Task { [weak self] in
                    await self?.bridge.sendResponse(response)
                }
                self?.updateStatusBar()
            },
            onCancel: { [weak self] in
                // User cancelled - send empty response
                Log.debug("AskUserQuestion cancelled")
                Task { [weak self] in
                    await self?.bridge.sendResponse("")
                }
                self?.updateStatusBar()
            }
        )
    }

    /// Detect errors from OpenCode output
    private func detectError(in text: String, rawJson: String) -> String? {
        let lowerText = text.lowercased()
        let lowerJson = rawJson.lowercased()

        // Check for API authentication errors
        if lowerText.contains("authentication") || lowerText.contains("unauthorized") ||
            lowerText.contains("invalid api key") || lowerText.contains("401") {
            return "API authentication failed. Check your API key in Settings."
        }

        // Check for rate limiting
        if lowerText.contains("rate limit") || lowerText.contains("429") || lowerText.contains("too many requests") {
            return "Rate limit exceeded. Please wait and try again."
        }

        // Check for model not found
        if lowerText.contains("model not found") || lowerText.contains("does not exist") ||
            lowerText.contains("invalid model") {
            return "Model not found. Check your model name in Settings."
        }

        // Check for connection errors
        if lowerText.contains("connection") && (lowerText.contains("refused") || lowerText.contains("failed")) {
            return "Connection failed. Check your Base URL or network."
        }

        if lowerText.contains("econnrefused") || lowerText.contains("network error") {
            return "Network error. Check your internet connection."
        }

        // Check for Ollama specific errors
        if lowerText.contains("ollama") && (lowerText.contains("not running") || lowerText.contains("not found")) {
            return "Ollama is not running. Start Ollama and try again."
        }

        // Check for encrypted content verification errors (session/project mismatch)
        if lowerText.contains("encrypted content") && (lowerText.contains("could not be verified") || lowerText.contains("invalid_encrypted_content")) {
            // Clear session ID and retry as new session
            if let session = currentSession {
                Log.debug("Encrypted content verification failed - clearing session ID (likely project mismatch)")
                session.openCodeSessionId = nil
            }
            Task { await bridge.setSessionId(nil) }
            return "Session context mismatch. Please try again - a new session will be started."
        }

        // Generic error detection
        if lowerText.contains("error") || lowerJson.contains("\"error\"") {
            // Extract a meaningful error message if possible
            if text.count < 200 {
                return text
            }
            return "An error occurred. Check the console for details."
        }

        return nil
    }

    private func processEventContent(_ event: OpenCodeEvent) {
        // Save OpenCode session ID to our session for resume capability
        if let sessionId = event.sessionId, let session = currentSession, session.openCodeSessionId == nil {
            session.openCodeSessionId = sessionId
            Log.debug("Saved OpenCode session ID to session: \(sessionId)")
        }

        // Convert event to conversation message and add to list
        guard let message = event.toMessage() else {
            // Log the event but don't add to UI
            if let session = currentSession {
                let entry = LogEntry(rawJson: event.rawJson, kind: event.kind.rawValue)
                modelContext?.insert(entry)
                session.logs.append(entry)
            }
            return
        }

        // Merge consecutive assistant messages (streaming text)
        if message.type == .assistant,
           let lastIndex = messages.lastIndex(where: { $0.type == .assistant }),
           lastIndex == messages.count - 1 {
            // Append to last assistant message
            let lastMessage = messages[lastIndex]
            let mergedContent = lastMessage.content + message.content
            messages[lastIndex] = ConversationMessage(
                id: lastMessage.id,
                type: .assistant,
                content: mergedContent,
                timestamp: lastMessage.timestamp
            )
        } else {
            messages.append(message)
        }

        // Force SwiftUI to update (NSHostingView may not auto-refresh)
        objectWillChange.send()

        if let session = currentSession {
            let entry = LogEntry(rawJson: event.rawJson, kind: event.kind.rawValue)
            modelContext?.insert(entry)
            session.logs.append(entry)
        }
    }
}
