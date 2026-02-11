//
//  AppState+Bridge.swift
//  Motive
//
//  Created by geezerrrr on 2026/1/19.
//
//  Handles OpenCode SSE events routed through OpenCodeBridge.
//  Uses native question/permission system (no MCP sidecar).
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
            agent: configManager.currentAgent,
            debugMode: configManager.debugMode,
            projectDirectory: configManager.currentProjectURL.path
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

    /// Reset the UI-level session timeout whenever we receive an event
    func resetSessionTimeout() {
        sessionTimeoutTask?.cancel()
        
        guard sessionStatus == .running else { return }
        
        sessionTimeoutTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(Self.sessionTimeoutSeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            
            // Still running after timeout — warn the user
            if sessionStatus == .running {
                Log.debug("Session timeout: no events for \(Int(Self.sessionTimeoutSeconds))s while still running")
                lastErrorMessage = "No response from OpenCode for \(Int(Self.sessionTimeoutSeconds)) seconds. The process may be stalled. You can interrupt or wait."
                statusBarController?.showError()
            }
        }
    }

    func handle(event: OpenCodeEvent) {
        // Log every event arrival for diagnostics — full text, no truncation
        Log.bridge("⬇︎ Event: kind=\(event.kind.rawValue) tool=\(event.toolName ?? "-") session=\(event.sessionId ?? "-") text=«\(event.text)»")

        // Once the user has manually interrupted, ignore all subsequent events.
        if sessionStatus == .interrupted {
            Log.debug("Ignoring post-interrupt event: \(event.kind.rawValue)")
            logEvent(event)
            return
        }

        // Route background session events away from foreground UI
        if let eventSessionId = event.sessionId,
           backgroundSessions.contains(where: { $0.id == eventSessionId && $0.status == .running }) {
            handleBackgroundSessionEvent(event, sessionId: eventSessionId)
            return
        }

        // Reset session timeout on every event
        resetSessionTimeout()

        // Update UI state based on event kind
        switch event.kind {
        case .usage:
            applyUsageUpdate(event)
        case .thought:
            handleThoughtEvent(event)
            return
        case .call, .tool:
            if handleToolEvent(event) { return }
        case .diff:
            handleDiffEvent(event)
        case .finish:
            handleFinishEvent(event)
        case .assistant:
            handleAssistantEvent(event)
        case .user:
            return
        case .error:
            handleErrorEvent(event)
        case .unknown:
            handleUnknownEvent(event)
        }

        // Process event content (save session ID, add messages)
        processEventContent(event)
    }

    // MARK: - Event Handlers

    /// Reset shared event state (timers, reasoning)
    private func resetEventState() {
        sessionTimeoutTask?.cancel()
        sessionTimeoutTask = nil
        reasoningDismissTask?.cancel()
        reasoningDismissTask = nil
        currentReasoningText = nil
    }

    /// Transition the current session to a new status
    private func transitionSession(to status: SessionStatus) {
        currentSession?.sessionStatus = status
    }

    private func handleThoughtEvent(_ event: OpenCodeEvent) {
        menuBarState = .reasoning
        currentToolName = nil
        currentToolInput = nil
        reasoningDismissTask?.cancel()
        reasoningDismissTask = nil
        if !event.text.isEmpty {
            currentReasoningText = (currentReasoningText ?? "") + event.text
        }
        nativePromptHandler.updateRemoteCommandStatus(toolName: "Thinking...")
        logEvent(event)
    }

    /// Handle tool/call events. Returns true if the event was intercepted and should not flow to processEventContent.
    private func handleToolEvent(_ event: OpenCodeEvent) -> Bool {
        dismissReasoningAfterDelay()
        menuBarState = .executing
        currentToolName = event.toolName ?? "Processing"
        currentToolInput = event.toolInput

        // Intercept native question events from SSE
        if let inputDict = event.toolInputDict,
           inputDict["_isNativeQuestion"] as? Bool == true {
            nativePromptHandler.handleNativeQuestion(inputDict: inputDict, event: event)
            logEvent(event)
            return true
        }

        // Intercept native permission events from SSE
        if let inputDict = event.toolInputDict,
           inputDict["_isNativePermission"] as? Bool == true {
            nativePromptHandler.handleNativePermission(inputDict: inputDict, event: event)
            logEvent(event)
            return true
        }

        nativePromptHandler.updateRemoteCommandStatus(toolName: event.toolName)
        return false
    }

    private func handleDiffEvent(_ event: OpenCodeEvent) {
        dismissReasoningAfterDelay()
        menuBarState = .executing
        currentToolName = "Editing file"
        nativePromptHandler.updateRemoteCommandStatus(toolName: "Editing file")
    }

    private func handleFinishEvent(_ event: OpenCodeEvent) {
        resetEventState()

        // Finish deduplication
        if event.isSecondaryFinish && sessionStatus == .completed {
            Log.debug("Ignoring secondary finish event (already completed)")
            return
        }

        menuBarState = .idle
        sessionStatus = .completed
        currentToolName = nil
        currentToolInput = nil

        messageStore.finalizeRunningMessages()

        if let session = currentSession {
            transitionSession(to: .completed)
            session.messagesData = ConversationMessage.serializeMessages(messages)
        }
        statusBarController?.showCompleted()
        if let commandId = currentRemoteCommandId {
            let resultMessage = messages.last(where: { $0.type == .assistant })?.content ?? "Task completed"
            cloudKitManager.completeCommand(commandId: commandId, result: resultMessage)
            currentRemoteCommandId = nil
        }
    }

    private func handleAssistantEvent(_ event: OpenCodeEvent) {
        dismissReasoningAfterDelay()
        menuBarState = .responding
        currentToolName = nil
    }

    private func handleErrorEvent(_ event: OpenCodeEvent) {
        resetEventState()
        lastErrorMessage = event.text
        sessionStatus = .failed
        menuBarState = .idle
        currentToolName = nil
        currentToolInput = nil
        messageStore.finalizeRunningMessages()
        transitionSession(to: .failed)
        statusBarController?.showError()
        if let commandId = currentRemoteCommandId {
            cloudKitManager.failCommand(commandId: commandId, error: event.text)
            currentRemoteCommandId = nil
        }
    }

    private func handleUnknownEvent(_ event: OpenCodeEvent) {
        if !event.text.isEmpty {
            Log.debug("Unknown event: \(event.text.prefix(200))")
        }
    }

    // MARK: - Reasoning Lifecycle

    /// Dismiss transient reasoning text after a short delay, giving the user time to see it.
    /// If new reasoning arrives before the delay, the task is cancelled and reasoning stays.
    private func dismissReasoningAfterDelay() {
        guard currentReasoningText != nil else { return }
        reasoningDismissTask?.cancel()
        reasoningDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(MotiveConstants.Timeouts.reasoningDismiss))
            guard !Task.isCancelled else { return }
            self?.currentReasoningText = nil
        }
    }

    // MARK: - Event Content Processing

    private func processEventContent(_ event: OpenCodeEvent) {
        if event.kind == .usage {
            return
        }
        // Save OpenCode session ID to our session for resume capability
        if let sessionId = event.sessionId, let session = currentSession, session.openCodeSessionId == nil {
            session.openCodeSessionId = sessionId
            Log.debug("Saved OpenCode session ID to session: \(sessionId)")
        }

        // --- Tool event lifecycle logging ---
        if event.kind == .tool || event.kind == .call {
            let hasOutput = event.toolOutput != nil
            let phase = hasOutput ? "result" : "call"
            Log.debug("Tool event [\(phase)]: \(event.toolName ?? "?") callId=\(event.toolCallId ?? "nil") hasOutput=\(hasOutput)")
        }

        // --- Question / Permission result interception ---
        // The call events are intercepted in handle(event:) via _isNativeQuestion/_isNativePermission.
        // The result events (with toolOutput) arrive separately without those flags.
        // Skip them here — the Question/Permission message lifecycle is fully managed
        // by handleNativeQuestion/handleNativePermission and updateQuestionMessage.
        if event.kind == .tool || event.kind == .call,
           let toolName = event.toolName?.lowercased(),
           toolName == "question" || toolName == "permission" {
            logEvent(event)
            return
        }

        // --- TodoWrite interception (live has special UI handling) ---
        // Intercept both .call (running) and .tool (completed) to avoid duplicate bubbles.
        if (event.kind == .tool || event.kind == .call),
           let toolName = event.toolName, toolName.isTodoWriteTool {
            // Only process completed events; skip the running call event entirely
            if event.kind == .tool {
                messageStore.handleTodoWriteEvent(event)
            }
            logEvent(event)
            return
        }

        // Insert into live messages array
        messageStore.insertEventMessage(event)
        logEvent(event)
    }

    private func applyUsageUpdate(_ event: OpenCodeEvent) {
        guard let usage = event.usage else {
            Log.debug("[Usage] applyUsageUpdate: no usage data in event")
            return
        }

        Log.debug("[Usage] applyUsageUpdate: model=\(event.model ?? "nil") in=\(usage.input) out=\(usage.output) reason=\(usage.reasoning) msgId=\(event.messageId ?? "nil")")

        if let messageId = event.messageId,
           let sessionId = event.sessionId {
            if !recordUsageMessageId(sessionId: sessionId, messageId: messageId) {
                Log.debug("[Usage] Deduplicated messageId=\(messageId)")
                return
            }
        }

        // Model comes from the SSE event (message.updated has modelID).
        // If model is nil, fall back to the currently selected model from settings
        // so that usage is never silently dropped.
        let model: String
        if let m = event.model, !m.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            model = m
        } else if let fallback = configManager.getModelString() {
            Log.debug("[Usage] Model nil in event, using settings fallback: \(fallback)")
            model = fallback
        } else {
            Log.debug("[Usage] No model available, skipping usage recording")
            return
        }

        configManager.recordTokenUsage(model: model, usage: usage, cost: event.cost)

        if usage.input > 0 {
            currentContextTokens = usage.input
            currentSession?.contextTokens = usage.input
        }
    }

    // MARK: - Background Session Events

    /// Handle events belonging to a background session.
    /// Routes question/permission to the native prompt handler so the user
    /// can still approve actions. Accumulates assistant text for result display.
    /// All other events are silently discarded to prevent foreground pollution.
    private func handleBackgroundSessionEvent(_ event: OpenCodeEvent, sessionId: String) {
        switch event.kind {
        case .call, .tool:
            // Route question/permission events to native handler — background tasks
            // must still be able to ask the user for input, otherwise they hang.
            if let inputDict = event.toolInputDict,
               inputDict["_isNativeQuestion"] as? Bool == true {
                nativePromptHandler.handleNativeQuestion(inputDict: inputDict, event: event)
                return
            }
            if let inputDict = event.toolInputDict,
               inputDict["_isNativePermission"] as? Bool == true {
                nativePromptHandler.handleNativePermission(inputDict: inputDict, event: event)
                return
            }
            Log.bridge("Discarding background tool event: \(event.toolName ?? "?") session=\(sessionId)")

        case .assistant:
            // Accumulate assistant text so we can show the result on completion
            if !event.text.isEmpty,
               let idx = backgroundSessions.firstIndex(where: { $0.id == sessionId }) {
                let existing = backgroundSessions[idx].resultText ?? ""
                backgroundSessions[idx].resultText = existing + event.text
            }

        case .usage:
            // Token usage should still be tracked for billing accuracy
            applyUsageUpdate(event)

        case .finish:
            Log.debug("Background session finished: \(sessionId)")
            completeBackgroundSession(sessionId: sessionId)
            updateStatusBar()

        case .error:
            Log.debug("Background session error: \(sessionId) — \(event.text.prefix(200))")
            if let idx = backgroundSessions.firstIndex(where: { $0.id == sessionId }) {
                backgroundSessions[idx].status = .failed
                backgroundSessions[idx].errorText = event.text
            }
            updateStatusBar()

        default:
            Log.bridge("Discarding background event: kind=\(event.kind.rawValue) session=\(sessionId)")
        }
    }

    // MARK: - Log Persistence

    func logEvent(_ event: OpenCodeEvent) {
        if let session = currentSession {
            // Use toReplayJSON() to ensure bridge-created events (which have empty rawJson)
            // are serialized into parseable JSON for session replay.
            let json = event.toReplayJSON()
            let entry = LogEntry(rawJson: json, kind: event.kind.rawValue)
            modelContext?.insert(entry)
            session.logs.append(entry)
        }
    }
}
