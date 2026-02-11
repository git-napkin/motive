//
//  OpenCodeBridge.swift
//  Motive
//
//  Coordinator for the OpenCode HTTP server, SSE client, and REST API client.
//  Replaces the previous PTY-based approach with structured SSE events and REST APIs.
//

import Foundation

actor OpenCodeBridge {

    // MARK: - Configuration

    struct Configuration: Sendable {
        let binaryURL: URL
        let environment: [String: String]
        let model: String?  // e.g., "openai/gpt-4o" or "anthropic/claude-sonnet-4-5-20250929"
        let agent: String?  // e.g., "motive", "plan" — per-message agent override
        let debugMode: Bool
        let projectDirectory: String  // Current project directory for server CWD
    }

    // MARK: - Properties

    private var configuration: Configuration?
    private let server = OpenCodeServer()
    private let sseClient = SSEClient()
    private let apiClient = OpenCodeAPIClient()

    private var eventTask: Task<Void, Never>?
    private var currentSessionId: String?
    private var activeSessions: Set<String> = []  // Multi-session ready

    /// The directory currently used for SSE and API calls.
    /// Must be kept in sync so that SSE subscribes to the same
    /// OpenCode instance that handles prompts.
    private var sseDirectory: String?

    /// Text delta accumulation buffer (per session)
    private var textBuffer: [String: String] = [:]

    private let eventHandler: @Sendable (OpenCodeEvent) async -> Void

    // MARK: - Init

    init(eventHandler: @escaping @Sendable (OpenCodeEvent) async -> Void) {
        self.eventHandler = eventHandler
    }

    // MARK: - Configuration

    func updateConfiguration(_ configuration: Configuration) {
        self.configuration = configuration
    }

    // MARK: - Server Lifecycle

    /// Start the HTTP server and connect SSE if not already running.
    func startIfNeeded() async {
        guard let configuration else {
            Log.error("Cannot start: no configuration")
            return
        }

        guard await !server.isRunning else {
            Log.bridge("Server already running")
            return
        }

        do {
            let serverConfig = OpenCodeServer.Configuration(
                binaryURL: configuration.binaryURL,
                environment: configuration.environment,
                workingDirectory: currentWorkingDirectory()
            )

            // Register restart handler BEFORE starting so it's ready
            // if the server crashes immediately after start
            await server.setRestartHandler { [weak self] newURL in
                await self?.handleServerRestart(newURL)
            }

            let url = try await server.start(configuration: serverConfig)
            await apiClient.updateBaseURL(url)
            await apiClient.updateDirectory(currentWorkingDirectory())

            // Don't start SSE here — submitIntent will start it with the
            // correct working directory. Starting without a directory causes
            // a wasted connection that gets cancelled immediately when
            // submitIntent detects the directory mismatch and reconnects.

            Log.bridge("Bridge started with server at \(url.absoluteString)")
        } catch {
            Log.error("Failed to start server: \(error.localizedDescription)")
            await eventHandler(OpenCodeEvent(
                kind: .error,
                rawJson: "",
                text: "Failed to start OpenCode: \(error.localizedDescription)"
            ))
        }
    }

    /// Called by OpenCodeServer when the server auto-restarts on a new URL.
    /// Reconnects SSE and updates the API client to point at the new port.
    private func handleServerRestart(_ newURL: URL) async {
        Log.bridge("Server restarted at \(newURL.absoluteString), reconnecting SSE...")

        // Update API client to the new URL
        await apiClient.updateBaseURL(newURL)

        // Disconnect old SSE and reconnect to new URL with the same directory
        await sseClient.disconnect()
        startEventLoop(baseURL: newURL, directory: sseDirectory)

        Log.bridge("Reconnected to restarted server at \(newURL.absoluteString)")
    }

    /// Stop the server and SSE.
    func stop() async {
        eventTask?.cancel()
        eventTask = nil
        await sseClient.disconnect()
        await server.stop()
        activeSessions.removeAll()
        textBuffer.removeAll()
        Log.bridge("Bridge stopped")
    }

    /// Restart: stop everything and start fresh.
    func restart() async {
        await stop()
        await startIfNeeded()
    }

    // MARK: - Session Management

    /// Get the current OpenCode session ID.
    func getSessionId() -> String? {
        return currentSessionId
    }

    /// Set the session ID (for switching sessions).
    func setSessionId(_ sessionId: String?) {
        if let old = currentSessionId {
            activeSessions.remove(old)
        }
        currentSessionId = sessionId
        if let sessionId {
            activeSessions.insert(sessionId)
        }
        Log.bridge("Session ID set to: \(sessionId ?? "nil")")
    }

    // MARK: - Intent Submission

    /// Submit a new intent (run a task).
    func submitIntent(text: String, cwd: String) async {
        guard configuration != nil else {
            await eventHandler(OpenCodeEvent(
                kind: .error,
                rawJson: "",
                text: "OpenCode not configured"
            ))
            return
        }

        // Ensure server is running
        if await !server.isRunning {
            await startIfNeeded()
            guard await server.isRunning else { return }
        }

        // Update working directory
        await apiClient.updateDirectory(cwd)

        // Ensure SSE is connected. Reconnect if:
        //  1. Working directory changed (different OpenCode instance)
        //  2. SSE stream task died (connection lost, all retries exhausted)
        //  3. SSE was never started (first intent after app launch)
        if let url = await server.serverURL {
            let sseAlive = await sseClient.hasActiveStream
            let needsReconnect = cwd != sseDirectory || !sseAlive

            if needsReconnect {
                if cwd != sseDirectory {
                    Log.bridge("Directory changed to \(cwd), reconnecting SSE...")
                } else if !sseAlive {
                    Log.bridge("SSE stream dead, reconnecting for \(cwd)...")
                } else {
                    Log.bridge("Starting SSE for directory: \(cwd)")
                }
                sseDirectory = cwd
                await sseClient.disconnect()
                startEventLoop(baseURL: url, directory: cwd)
            }
        }

        do {
            try await submitPrompt(text: text)
        } catch {
            Log.error("Failed to submit intent: \(error.localizedDescription)")
            await eventHandler(OpenCodeEvent(
                kind: .error,
                rawJson: "",
                text: "Failed to submit task: \(error.localizedDescription)"
            ))
        }
    }

    /// Resume an existing session with a new message.
    func resumeSession(sessionId: String, text: String, cwd: String) async {
        currentSessionId = sessionId
        activeSessions.insert(sessionId)
        await submitIntent(text: text, cwd: cwd)
    }

    // MARK: - Background Sessions

    /// Create a new session in the background without switching focus.
    /// Returns the session ID if successful.
    func createBackgroundSession(text: String, cwd: String) async -> String? {
        guard configuration != nil else { return nil }

        // Ensure server is running
        if await !server.isRunning {
            await startIfNeeded()
            guard await server.isRunning else { return nil }
        }

        await apiClient.updateDirectory(cwd)

        // Ensure SSE is connected
        if let url = await server.serverURL {
            let sseAlive = await sseClient.hasActiveStream
            if !sseAlive || cwd != sseDirectory {
                sseDirectory = cwd
                await sseClient.disconnect()
                startEventLoop(baseURL: url, directory: cwd)
            }
        }

        do {
            let session = try await apiClient.createSession()
            let sessionID = session.id
            activeSessions.insert(sessionID)
            Log.bridge("Created background session: \(sessionID)")

            try await apiClient.sendPromptAsync(
                sessionID: sessionID,
                text: text,
                model: configuration?.model,
                agent: configuration?.agent
            )
            return sessionID
        } catch {
            Log.error("Failed to create background session: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Interruption

    /// Interrupt/abort the current session.
    func interrupt() async {
        guard let sessionId = currentSessionId else {
            Log.warning("No active session to interrupt")
            return
        }

        do {
            try await apiClient.abortSession(id: sessionId)
            Log.bridge("Aborted session: \(sessionId)")
        } catch {
            Log.error("Failed to abort session: \(error.localizedDescription)")
        }
    }

    // MARK: - Native Question/Permission Replies

    /// Reply to a native question from OpenCode.
    func replyToQuestion(requestID: String, answers: [[String]]) async {
        do {
            try await apiClient.replyToQuestion(requestID: requestID, answers: answers)
        } catch {
            Log.error("Failed to reply to question \(requestID): \(error.localizedDescription)")
        }
    }

    /// Reject a native question (user cancelled).
    func rejectQuestion(requestID: String) async {
        do {
            try await apiClient.rejectQuestion(requestID: requestID)
        } catch {
            Log.error("Failed to reject question \(requestID): \(error.localizedDescription)")
        }
    }

    /// Reply to a native permission request.
    func replyToPermission(requestID: String, reply: OpenCodeAPIClient.PermissionReply) async {
        do {
            try await apiClient.replyToPermission(requestID: requestID, reply: reply)
        } catch {
            Log.error("Failed to reply to permission \(requestID): \(error.localizedDescription)")
        }
    }

    // MARK: - SSE Event Loop

    private func startEventLoop(baseURL: URL, directory: String? = nil) {
        eventTask?.cancel()

        eventTask = Task { [weak self] in
            guard let self else { return }

            let stream = await self.sseClient.connect(to: baseURL, directory: directory)

            for await sseEvent in stream {
                guard !Task.isCancelled else { break }
                await self.handleSSEEvent(sseEvent)
            }

            Log.bridge("SSE event loop ended")
        }
    }

    /// Route an SSE event to the appropriate handler.
    private func handleSSEEvent(_ event: SSEClient.SSEEvent) async {
        switch event {
        case .connected:
            Log.bridge("SSE connected")

        case .heartbeat:
            break

        case .textDelta(let info):
            await handleTextDelta(info)

        case .textComplete(let info):
            handleTextComplete(info)

        case .reasoningDelta(let info):
            await handleReasoningDelta(info)

        case .toolRunning(let info):
            await handleToolRunning(info)

        case .toolCompleted(let info):
            await handleToolCompleted(info)

        case .toolError(let info):
            await handleToolError(info)

        case .usageUpdated(let info):
            await handleUsageUpdate(info)

        case .sessionIdle(let sessionID):
            await handleSessionIdle(sessionID)

        case .sessionStatus(let info):
            guard isTrackedSession(info.sessionID) else { return }
            break

        case .sessionError(let info):
            await handleSessionError(info)

        case .questionAsked(let request):
            await handleQuestionSSEEvent(request)

        case .permissionAsked(let request):
            await handlePermissionSSEEvent(request)
        }
    }

    // MARK: - Text Event Handlers

    private func handleTextDelta(_ info: SSEClient.TextDeltaInfo) async {
        guard isTrackedSession(info.sessionID) else { return }
        textBuffer[info.sessionID, default: ""] += info.delta
        await eventHandler(OpenCodeEvent(
            kind: .assistant,
            rawJson: "",
            text: info.delta,
            sessionId: info.sessionID
        ))
    }

    private func handleTextComplete(_ info: SSEClient.TextCompleteInfo) {
        guard isTrackedSession(info.sessionID) else { return }
        textBuffer.removeValue(forKey: info.sessionID)
    }

    private func handleReasoningDelta(_ info: SSEClient.ReasoningDeltaInfo) async {
        guard isTrackedSession(info.sessionID) else { return }
        await eventHandler(OpenCodeEvent(
            kind: .thought,
            rawJson: "",
            text: info.delta,
            sessionId: info.sessionID
        ))
    }

    // MARK: - Tool Event Handlers

    private func handleToolRunning(_ info: SSEClient.ToolInfo) async {
        guard isTrackedSession(info.sessionID) else { return }
        let inputDict = deserializeInputJSON(info.inputJSON)
        await eventHandler(OpenCodeEvent(
            kind: .tool,
            rawJson: "",
            text: info.inputSummary ?? "",
            toolName: info.toolName,
            toolInput: info.inputSummary,
            toolInputDict: inputDict,
            toolCallId: info.toolCallID,
            sessionId: info.sessionID
        ))
    }

    private func handleToolCompleted(_ info: SSEClient.ToolCompletedInfo) async {
        guard isTrackedSession(info.sessionID) else { return }
        let inputDict = deserializeInputJSON(info.inputJSON)
        await eventHandler(OpenCodeEvent(
            kind: .tool,
            rawJson: "",
            text: info.inputSummary ?? "",
            toolName: info.toolName,
            toolInput: info.inputSummary,
            toolInputDict: inputDict,
            toolOutput: info.output,
            toolCallId: info.toolCallID,
            sessionId: info.sessionID,
            diff: info.diff
        ))
    }

    private func handleToolError(_ info: SSEClient.ToolErrorInfo) async {
        guard isTrackedSession(info.sessionID) else { return }
        await eventHandler(OpenCodeEvent(
            kind: .tool,
            rawJson: "",
            text: info.error,
            toolName: info.toolName,
            toolOutput: "Error: \(info.error)",
            toolCallId: info.toolCallID,
            sessionId: info.sessionID
        ))
    }

    // MARK: - Usage Event Handler

    private func handleUsageUpdate(_ info: SSEClient.UsageInfo) async {
        guard isTrackedSession(info.sessionID) else { return }
        await eventHandler(OpenCodeEvent(
            kind: .usage,
            rawJson: "",
            text: "",
            sessionId: info.sessionID,
            model: info.model,
            usage: info.usage,
            cost: info.cost,
            messageId: info.messageID
        ))
    }

    // MARK: - Session Lifecycle Handlers

    private func handleSessionIdle(_ sessionID: String) async {
        guard isTrackedSession(sessionID) else { return }
        textBuffer.removeValue(forKey: sessionID)
        await eventHandler(OpenCodeEvent(
            kind: .finish,
            rawJson: "",
            text: "Completed",
            sessionId: sessionID
        ))
    }

    private func handleSessionError(_ info: SSEClient.SessionErrorInfo) async {
        guard isTrackedSession(info.sessionID) else { return }
        textBuffer.removeValue(forKey: info.sessionID)
        await eventHandler(OpenCodeEvent(
            kind: .error,
            rawJson: "",
            text: info.error,
            sessionId: info.sessionID
        ))
    }

    // MARK: - Native Prompt Handlers

    private func handleQuestionSSEEvent(_ request: SSEClient.QuestionRequest) async {
        guard isTrackedSession(request.sessionID) else { return }
        await eventHandler(OpenCodeEvent(
            kind: .tool,
            rawJson: encodeQuestionAsJSON(request),
            text: request.questions.first?.question ?? "Question",
            toolName: "Question",
            toolInput: request.questions.first?.question,
            toolInputDict: buildQuestionInputDict(request),
            sessionId: request.sessionID
        ))
    }

    private func handlePermissionSSEEvent(_ request: SSEClient.NativePermissionRequest) async {
        guard isTrackedSession(request.sessionID) else { return }
        await eventHandler(OpenCodeEvent(
            kind: .tool,
            rawJson: encodePermissionAsJSON(request),
            text: "Permission: \(request.permission) for \(request.patterns.joined(separator: ", "))",
            toolName: "Permission",
            toolInput: request.patterns.joined(separator: ", "),
            toolInputDict: buildPermissionInputDict(request),
            sessionId: request.sessionID
        ))
    }

    // MARK: - Helpers

    private func isTrackedSession(_ sessionID: String) -> Bool {
        // If no sessions are actively tracked, accept all events
        // This handles the case before a session is created
        if activeSessions.isEmpty { return true }
        return activeSessions.contains(sessionID)
    }

    private func currentWorkingDirectory() -> String {
        if let dir = configuration?.projectDirectory, !dir.isEmpty {
            return dir
        }
        return FileManager.default.homeDirectoryForCurrentUser.path
    }

    private func submitPrompt(text: String) async throws {
        // Create or reuse session
        let sessionID: String
        if let existing = currentSessionId {
            sessionID = existing
            Log.bridge("Reusing existing session: \(sessionID)")
        } else {
            let session = try await apiClient.createSession()
            sessionID = session.id
            currentSessionId = sessionID
            activeSessions.insert(sessionID)
            Log.bridge("Created new session: \(sessionID)")
        }

        let sessionCount = activeSessions.count
        let sseAlive = await sseClient.hasActiveStream
        let sseConnected = await sseClient.connected
        Log.bridge("Active sessions: \(sessionCount), SSE alive: \(sseAlive), SSE connected: \(sseConnected)")

        // Send prompt asynchronously (results via SSE)
        try await apiClient.sendPromptAsync(
            sessionID: sessionID,
            text: text,
            model: configuration?.model,
            agent: configuration?.agent
        )
        Log.bridge("Submitted intent to session \(sessionID)")
    }

    // MARK: - JSON Encoding Helpers

    private func encodeQuestionAsJSON(_ request: SSEClient.QuestionRequest) -> String {
        var dict: [String: Any] = [
            "type": "question.asked",
            "id": request.id,
            "sessionID": request.sessionID,
        ]

        let questions = request.questions.map { q -> [String: Any] in
            var qDict: [String: Any] = [
                "question": q.question,
                "multiple": q.multiple,
                "custom": q.custom,
            ]
            qDict["options"] = q.options.map { opt -> [String: Any] in
                var optDict: [String: Any] = ["label": opt.label]
                if let desc = opt.description {
                    optDict["description"] = desc
                }
                return optDict
            }
            return qDict
        }
        dict["questions"] = questions

        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return str
    }

    private func encodePermissionAsJSON(_ request: SSEClient.NativePermissionRequest) -> String {
        let dict: [String: Any] = [
            "type": "permission.asked",
            "id": request.id,
            "sessionID": request.sessionID,
            "permission": request.permission,
            "patterns": request.patterns,
            "metadata": request.metadata,
            "always": request.always,
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return str
    }

    private func buildQuestionInputDict(_ request: SSEClient.QuestionRequest) -> [String: Any] {
        var dict: [String: Any] = [
            "_nativeQuestionID": request.id,
            "_isNativeQuestion": true,
        ]

        if let first = request.questions.first {
            dict["question"] = first.question
            dict["custom"] = first.custom
            dict["multiple"] = first.multiple
            dict["options"] = first.options.map { opt -> [String: Any] in
                var d: [String: Any] = ["label": opt.label]
                if let desc = opt.description {
                    d["description"] = desc
                }
                return d
            }
        }

        return dict
    }

    private func buildPermissionInputDict(_ request: SSEClient.NativePermissionRequest) -> [String: Any] {
        [
            "_nativePermissionID": request.id,
            "_isNativePermission": true,
            "permission": request.permission,
            "patterns": request.patterns,
            "metadata": request.metadata,
            "always": request.always,
        ]
    }

    /// Deserialize JSON string back to [String: Any] for tool input dict.
    /// Used to pass full input through Sendable boundary (SSEClient → Bridge → AppState).
    private func deserializeInputJSON(_ json: String?) -> [String: Any]? {
        guard let json, let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return dict
    }
}
