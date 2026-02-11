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

    /// Last reported agent per session (deduplication for message.updated floods)
    private var lastReportedAgent: [String: String] = [:]

    /// Health check task: after SSE reconnects, checks if running sessions receive events.
    private var reconnectHealthTask: Task<Void, Never>?

    /// Non-blocking event channel to AppState.
    /// `yield()` never blocks the bridge actor; AppState consumes on MainActor.
    /// AsyncStream preserves FIFO ordering, so events arrive in correct sequence.
    private let eventContinuation: AsyncStream<OpenCodeEvent>.Continuation

    // MARK: - Init

    init(eventContinuation: AsyncStream<OpenCodeEvent>.Continuation) {
        self.eventContinuation = eventContinuation
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
            eventContinuation.yield(OpenCodeEvent(
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

    /// Set the current session ID (for switching sessions / interrupt targeting).
    /// Does NOT remove the old session from activeSessions — background sessions
    /// must remain tracked so their SSE events continue to flow through isTrackedSession.
    func setSessionId(_ sessionId: String?) {
        currentSessionId = sessionId
        if let sessionId {
            activeSessions.insert(sessionId)
        }
        Log.bridge("Session ID set to: \(sessionId ?? "nil"), active sessions: \(activeSessions.count)")
    }

    /// Remove a completed/failed session from active tracking.
    /// Called by AppState when a session finishes or errors out.
    /// This stops the bridge from forwarding further events for this session.
    func removeActiveSession(_ sessionId: String) {
        activeSessions.remove(sessionId)
        lastReportedAgent.removeValue(forKey: sessionId)
        if currentSessionId == sessionId {
            currentSessionId = nil
        }
        Log.bridge("Removed active session: \(sessionId), remaining: \(activeSessions.count)")
    }

    // MARK: - Intent Submission

    /// Submit a new intent (run a task).
    /// - Parameter forceNewSession: If true, clears `currentSessionId` atomically before creating
    ///   a new session. This prevents the race condition where multiple concurrent Tasks
    ///   interleave their setSessionId(nil) + submitIntent calls on the bridge actor.
    func submitIntent(text: String, cwd: String, agent: String? = nil, forceNewSession: Bool = false) async {
        if forceNewSession {
            currentSessionId = nil
        }
        guard configuration != nil else {
            eventContinuation.yield(OpenCodeEvent(
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

        // Ensure SSE is connected. Only reconnect if:
        //  1. SSE stream task died (connection lost, all retries exhausted)
        //  2. SSE was never started (first intent after app launch)
        //
        // We do NOT reconnect when only the directory changes. The OpenCode server
        // is a single process, and the SSE stream delivers events for ALL sessions
        // regardless of the directory header. The API client sends x-opencode-directory
        // with each REST call (createSession, sendPrompt), so new sessions in new
        // directories are correctly handled. Reconnecting SSE on directory change
        // would briefly disconnect the stream, losing in-flight events for background
        // sessions in the previous directory.
        if let url = await server.serverURL {
            let sseAlive = await sseClient.hasActiveStream

            if !sseAlive {
                Log.bridge("SSE stream not alive, connecting for \(cwd)...")
                sseDirectory = cwd
                await sseClient.disconnect()
                startEventLoop(baseURL: url, directory: cwd)
            } else if cwd != sseDirectory {
                // Track directory change but don't reconnect — SSE is global
                Log.bridge("Directory changed to \(cwd) (SSE stays connected via \(sseDirectory ?? "nil"))")
                sseDirectory = cwd
            }
        }

        do {
            try await submitPrompt(text: text, agentOverride: agent)
        } catch {
            Log.error("Failed to submit intent: \(error.localizedDescription)")
            eventContinuation.yield(OpenCodeEvent(
                kind: .error,
                rawJson: "",
                text: "Failed to submit task: \(error.localizedDescription)"
            ))
        }
    }

    /// Resume an existing session with a new message.
    func resumeSession(sessionId: String, text: String, cwd: String, agent: String? = nil) async {
        currentSessionId = sessionId
        activeSessions.insert(sessionId)
        await submitIntent(text: text, cwd: cwd, agent: agent)
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
                // await is for actor isolation hop only — handleSSEEvent itself
                // returns instantly (non-blocking yield to AsyncStream).
                await self.handleSSEEvent(sseEvent)
            }

            Log.bridge("SSE event loop ended")
        }
    }

    /// Route an SSE event to the appropriate handler.
    /// Most handlers are now synchronous (non-blocking yield to AsyncStream).
    private func handleSSEEvent(_ event: SSEClient.SSEEvent) {
        switch event {
        case .connected:
            Log.bridge("SSE connected")
            startReconnectHealthCheck()

        case .heartbeat:
            break

        case .textDelta(let info):
            handleTextDelta(info)

        case .textComplete(let info):
            handleTextComplete(info)

        case .reasoningDelta(let info):
            handleReasoningDelta(info)

        case .toolRunning(let info):
            handleToolRunning(info)

        case .toolCompleted(let info):
            handleToolCompleted(info)

        case .toolError(let info):
            handleToolError(info)

        case .usageUpdated(let info):
            handleUsageUpdate(info)

        case .sessionIdle(let sessionID):
            handleSessionIdle(sessionID)

        case .sessionStatus(let info):
            guard isTrackedSession(info.sessionID) else { return }
            break

        case .sessionError(let info):
            handleSessionError(info)

        case .questionAsked(let request):
            handleQuestionSSEEvent(request)

        case .permissionAsked(let request):
            handlePermissionSSEEvent(request)

        case .agentChanged(let info):
            handleAgentChanged(info)
        }
    }

    // MARK: - Text Event Handlers

    private func handleTextDelta(_ info: SSEClient.TextDeltaInfo) {
        guard isTrackedSession(info.sessionID) else { return }
        eventContinuation.yield(OpenCodeEvent(
            kind: .assistant,
            rawJson: "",
            text: info.delta,
            sessionId: info.sessionID
        ))
    }

    private func handleTextComplete(_ info: SSEClient.TextCompleteInfo) {
        guard isTrackedSession(info.sessionID) else { return }
        // Text completion is a lifecycle marker; no state to update.
    }

    private func handleReasoningDelta(_ info: SSEClient.ReasoningDeltaInfo) {
        guard isTrackedSession(info.sessionID) else { return }
        eventContinuation.yield(OpenCodeEvent(
            kind: .thought,
            rawJson: "",
            text: info.delta,
            sessionId: info.sessionID
        ))
    }

    // MARK: - Tool Event Handlers

    private func handleToolRunning(_ info: SSEClient.ToolInfo) {
        guard isTrackedSession(info.sessionID) else { return }
        let inputDict = deserializeInputJSON(info.inputJSON)
        eventContinuation.yield(OpenCodeEvent(
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

    private func handleToolCompleted(_ info: SSEClient.ToolCompletedInfo) {
        guard isTrackedSession(info.sessionID) else { return }
        let inputDict = deserializeInputJSON(info.inputJSON)
        eventContinuation.yield(OpenCodeEvent(
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

    private func handleToolError(_ info: SSEClient.ToolErrorInfo) {
        guard isTrackedSession(info.sessionID) else { return }
        eventContinuation.yield(OpenCodeEvent(
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

    private func handleUsageUpdate(_ info: SSEClient.UsageInfo) {
        guard isTrackedSession(info.sessionID) else { return }
        eventContinuation.yield(OpenCodeEvent(
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

    private func handleSessionIdle(_ sessionID: String) {
        guard isTrackedSession(sessionID) else { return }
        lastReportedAgent.removeValue(forKey: sessionID)
        eventContinuation.yield(OpenCodeEvent(
            kind: .finish,
            rawJson: "",
            text: "Completed",
            sessionId: sessionID
        ))
    }

    private func handleSessionError(_ info: SSEClient.SessionErrorInfo) {
        guard isTrackedSession(info.sessionID) else { return }
        lastReportedAgent.removeValue(forKey: info.sessionID)
        eventContinuation.yield(OpenCodeEvent(
            kind: .error,
            rawJson: "",
            text: info.error,
            sessionId: info.sessionID
        ))
    }

    // MARK: - Agent Change Handler

    private func handleAgentChanged(_ info: SSEClient.AgentChangeInfo) {
        guard isTrackedSession(info.sessionID) else { return }

        // Deduplicate: message.updated fires frequently with the same agent
        let key = info.sessionID
        if lastReportedAgent[key] == info.agent { return }
        lastReportedAgent[key] = info.agent

        eventContinuation.yield(OpenCodeEvent(
            kind: .assistant,
            rawJson: "",
            text: "",
            sessionId: info.sessionID,
            agent: info.agent
        ))
    }

    // MARK: - Native Prompt Handlers

    private func handleQuestionSSEEvent(_ request: SSEClient.QuestionRequest) {
        guard isTrackedSession(request.sessionID) else { return }
        eventContinuation.yield(OpenCodeEvent(
            kind: .tool,
            rawJson: encodeQuestionAsJSON(request),
            text: request.questions.first?.question ?? "Question",
            toolName: "Question",
            toolInput: request.questions.first?.question,
            toolInputDict: buildQuestionInputDict(request),
            sessionId: request.sessionID
        ))
    }

    private func handlePermissionSSEEvent(_ request: SSEClient.NativePermissionRequest) {
        guard isTrackedSession(request.sessionID) else { return }
        eventContinuation.yield(OpenCodeEvent(
            kind: .tool,
            rawJson: encodePermissionAsJSON(request),
            text: "Permission: \(request.permission) for \(request.patterns.joined(separator: ", "))",
            toolName: "Permission",
            toolInput: request.patterns.joined(separator: ", "),
            toolInputDict: buildPermissionInputDict(request),
            sessionId: request.sessionID
        ))
    }

    // MARK: - Reconnection Health Check

    /// After SSE reconnects, check that running sessions receive events within 15s.
    /// If not, log a warning so operators / users are aware that events may have been lost.
    private func startReconnectHealthCheck() {
        reconnectHealthTask?.cancel()
        guard !activeSessions.isEmpty else { return }

        // Snapshot the set of active sessions at reconnection time
        let sessionsAtReconnect = activeSessions

        reconnectHealthTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard !Task.isCancelled, let self else { return }
            // If any sessions from the snapshot are still tracked (not completed/removed),
            // they're alive. If all were removed, nothing is stuck.
            let currentActive = await self.getActiveSessions()
            let stillTracked = sessionsAtReconnect.filter { currentActive.contains($0) }
            if !stillTracked.isEmpty {
                Log.warning("SSE reconnect health: \(stillTracked.count) session(s) still active after reconnect — events may have been lost during reconnection window")
            }
        }
    }

    /// Accessor for active sessions (used by reconnect health check Task).
    private func getActiveSessions() -> Set<String> {
        activeSessions
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

    private func submitPrompt(text: String, agentOverride: String? = nil) async throws {
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

            // Notify AppState of the new session ID BEFORE sending the prompt.
            // The `await` ensures the MainActor processes this binding before any
            // SSE events can arrive, preventing stale events from corrupting the ID.
            eventContinuation.yield(OpenCodeEvent(
                kind: .unknown,
                rawJson: "__session_bind__",
                text: "",
                sessionId: sessionID
            ))
        }

        let sessionCount = activeSessions.count
        let sseAlive = await sseClient.hasActiveStream
        let sseConnected = await sseClient.connected
        Log.bridge("Active sessions: \(sessionCount), SSE alive: \(sseAlive), SSE connected: \(sseConnected)")

        // Send prompt asynchronously (results via SSE)
        // Use explicit agent override if provided, otherwise fall back to configuration
        let agent = agentOverride ?? configuration?.agent
        try await apiClient.sendPromptAsync(
            sessionID: sessionID,
            text: text,
            model: configuration?.model,
            agent: agent
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

        // Pass tool context for plan_exit detection
        if let toolContext = request.toolContext {
            dict["_toolContext"] = toolContext
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
