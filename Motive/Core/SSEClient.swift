//
//  SSEClient.swift
//  Motive
//
//  Connects to OpenCode's SSE endpoint and parses events into typed enums.
//  Supports text delta throttling, auto-reconnect, and sessionID filtering.
//

import Foundation
import os

/// Client for OpenCode's Server-Sent Events stream.
///
/// Connects to `GET /event` and emits typed `SSEEvent` values via `AsyncStream`.
/// Text deltas are throttled to ~30Hz to prevent excessive UI updates.
actor SSEClient {

    // MARK: - Event Types

    /// Structured events parsed from OpenCode's SSE stream.
    enum SSEEvent: Sendable {
        // Text streaming
        case textDelta(TextDeltaInfo)
        case textComplete(TextCompleteInfo)

        // Reasoning streaming
        case reasoningDelta(ReasoningDeltaInfo)

        // Tool lifecycle
        case toolRunning(ToolInfo)
        case toolCompleted(ToolCompletedInfo)
        case toolError(ToolErrorInfo)

        // Session lifecycle
        case sessionIdle(sessionID: String)
        case sessionStatus(SessionStatusInfo)
        case sessionError(SessionErrorInfo)

        // Native question/permission
        case questionAsked(QuestionRequest)
        case permissionAsked(NativePermissionRequest)

        // Connection
        case connected
        case heartbeat
    }

    // MARK: - Info Types

    struct TextDeltaInfo: Sendable {
        let sessionID: String
        let messageID: String
        let delta: String
    }

    struct TextCompleteInfo: Sendable {
        let sessionID: String
        let messageID: String
        let text: String
    }

    struct ReasoningDeltaInfo: Sendable {
        let sessionID: String
        let delta: String
    }

    struct ToolInfo: Sendable {
        let sessionID: String
        let toolName: String
        let toolCallID: String?
        let inputSummary: String?
        /// Serialized JSON of the full tool input dict (Sendable workaround for [String: Any]).
        let inputJSON: String?

        init(sessionID: String, toolName: String, toolCallID: String?, input: [String: Any]?, inputSummary: String?) {
            self.sessionID = sessionID
            self.toolName = toolName
            self.toolCallID = toolCallID
            self.inputSummary = inputSummary
            if let input {
                let isValid = JSONSerialization.isValidJSONObject(input)
                if isValid, let data = try? JSONSerialization.data(withJSONObject: input) {
                    self.inputJSON = String(data: data, encoding: .utf8)
                } else {
                    Log.bridge("⚠️ ToolInfo inputJSON serialization failed: tool=\(toolName) keys=\(input.keys.sorted()) isValid=\(isValid)")
                    self.inputJSON = nil
                }
            } else {
                self.inputJSON = nil
            }
        }
    }

    struct ToolCompletedInfo: Sendable {
        let sessionID: String
        let toolName: String
        let toolCallID: String?
        let output: String?
        let inputSummary: String?
        /// Serialized JSON of the full tool input dict (Sendable workaround for [String: Any]).
        let inputJSON: String?

        init(sessionID: String, toolName: String, toolCallID: String?, output: String?, input: [String: Any]?, inputSummary: String?) {
            self.sessionID = sessionID
            self.toolName = toolName
            self.toolCallID = toolCallID
            self.output = output
            self.inputSummary = inputSummary
            if let input, let data = try? JSONSerialization.data(withJSONObject: input) {
                self.inputJSON = String(data: data, encoding: .utf8)
            } else {
                self.inputJSON = nil
            }
        }
    }

    struct ToolErrorInfo: Sendable {
        let sessionID: String
        let toolName: String
        let toolCallID: String?
        let error: String
    }

    struct SessionStatusInfo: Sendable {
        let sessionID: String
        let status: String // "idle", "busy", "retry"
    }

    struct SessionErrorInfo: Sendable {
        let sessionID: String
        let error: String
    }

    /// A question asked by OpenCode's native question tool.
    struct QuestionRequest: Sendable {
        let id: String
        let sessionID: String
        let questions: [QuestionItem]

        struct QuestionItem: Sendable {
            let question: String
            let options: [QuestionOption]
            let multiple: Bool
            let custom: Bool
        }

        struct QuestionOption: Sendable {
            let label: String
            let description: String?
        }
    }

    /// A permission request from OpenCode's native permission system.
    struct NativePermissionRequest: Sendable {
        let id: String
        let sessionID: String
        let permission: String   // "edit", "bash", "read", etc.
        let patterns: [String]   // File paths or command patterns
        let metadata: [String: String] // "filepath", "diff", etc.
        let always: [String]     // Patterns to remember if "always" is chosen
    }

    // MARK: - Properties

    private var streamTask: Task<Void, Never>?
    private var isConnected = false
    private static let reconnectMaxDelay: TimeInterval = 30
    private static let throttleIntervalNanos: UInt64 = 33_000_000 // ~30Hz

    private let logger = Logger(subsystem: "com.velvet.motive", category: "SSEClient")

    // MARK: - Public API

    /// Connect to the SSE endpoint and return an async stream of events.
    ///
    /// - Parameters:
    ///   - baseURL: The base URL of the OpenCode server (e.g., `http://127.0.0.1:4096`).
    ///   - directory: The working directory to pass via `x-opencode-directory` header.
    ///     **Critical**: This must match the directory used by `OpenCodeAPIClient` so that
    ///     the SSE stream subscribes to the same OpenCode instance that handles prompts.
    /// - Returns: An `AsyncStream` of typed SSE events.
    func connect(to baseURL: URL, directory: String? = nil) -> AsyncStream<SSEEvent> {
        disconnect()

        let (stream, continuation) = AsyncStream.makeStream(of: SSEEvent.self)

        streamTask = Task { [weak self] in
            guard let self else {
                continuation.finish()
                return
            }

            var reconnectDelay: TimeInterval = 1.0

            while !Task.isCancelled {
                do {
                    await self.logger.info("SSE connecting to \(baseURL.absoluteString)...")
                    try await self.consumeEventStream(
                        baseURL: baseURL,
                        directory: directory,
                        continuation: continuation
                    )
                    // Stream ended normally (server shutdown)
                    if !Task.isCancelled {
                        await self.logger.info("SSE stream ended normally, reconnecting in \(reconnectDelay)s...")
                    }
                } catch {
                    if !Task.isCancelled {
                        await self.logger.error("SSE stream error: \(error.localizedDescription), reconnecting in \(reconnectDelay)s...")
                    }
                }

                guard !Task.isCancelled else { break }

                // Exponential backoff
                try? await Task.sleep(nanoseconds: UInt64(reconnectDelay * 1_000_000_000))
                reconnectDelay = min(reconnectDelay * 2, Self.reconnectMaxDelay)
            }

            continuation.finish()
        }

        return stream
    }

    /// Whether the SSE stream is currently connected and receiving events.
    var connected: Bool { isConnected }

    /// Whether the SSE event loop task is alive (may be in reconnect backoff).
    var hasActiveStream: Bool { streamTask != nil && !streamTask!.isCancelled }

    /// Disconnect from the SSE stream.
    func disconnect() {
        streamTask?.cancel()
        streamTask = nil
        isConnected = false
    }

    // MARK: - Stream Consumption

    private func consumeEventStream(
        baseURL: URL,
        directory: String?,
        continuation: AsyncStream<SSEEvent>.Continuation
    ) async throws {
        let eventURL = baseURL.appendingPathComponent("event")
        var request = URLRequest(url: eventURL)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.timeoutInterval = .infinity

        // Must match the directory used by OpenCodeAPIClient so that
        // events from the prompt endpoint reach this SSE stream.
        if let directory, !directory.isEmpty {
            request.setValue(directory, forHTTPHeaderField: "x-opencode-directory")
        }

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw SSEError.badStatus(status)
        }

        isConnected = true
        logger.info("Connected to SSE endpoint: \(eventURL.absoluteString)")

        // Text delta throttle state
        var deltaBuffer: [String: String] = [:] // sessionID -> accumulated delta
        var lastFlushTime = ContinuousClock.now

        var dataBuffer = ""

        for try await line in bytes.lines {
            guard !Task.isCancelled else { break }

            if line.hasPrefix("data: ") {
                // URLSession.AsyncBytes.lines may skip empty lines,
                // so we flush the previous event whenever a new data: line arrives.
                if !dataBuffer.isEmpty {
                    flushEvent(
                        dataBuffer, continuation: continuation,
                        deltaBuffer: &deltaBuffer, lastFlushTime: &lastFlushTime
                    )
                    dataBuffer = ""
                }
                dataBuffer = String(line.dropFirst(6))
            } else if line.isEmpty && !dataBuffer.isEmpty {
                // Standard SSE: empty line = end of event
                flushEvent(
                    dataBuffer, continuation: continuation,
                    deltaBuffer: &deltaBuffer, lastFlushTime: &lastFlushTime
                )
                dataBuffer = ""
            }
            // Ignore other lines (event:, id:, comments, etc.)
        }

        // Flush any remaining data in buffer
        if !dataBuffer.isEmpty {
            flushEvent(
                dataBuffer, continuation: continuation,
                deltaBuffer: &deltaBuffer, lastFlushTime: &lastFlushTime
            )
        }

        // Flush remaining deltas
        if !deltaBuffer.isEmpty {
            for (sid, text) in deltaBuffer {
                continuation.yield(.textDelta(TextDeltaInfo(
                    sessionID: sid,
                    messageID: "",
                    delta: text
                )))
            }
        }

        isConnected = false
    }

    // MARK: - Event Flushing

    /// Parse a buffered SSE data string and yield the result to the stream.
    /// Handles text delta throttling internally.
    private func flushEvent(
        _ dataBuffer: String,
        continuation: AsyncStream<SSEEvent>.Continuation,
        deltaBuffer: inout [String: String],
        lastFlushTime: inout ContinuousClock.Instant
    ) {
        let event = parseSSEData(dataBuffer)

        guard let event else { return }

        // Handle text delta throttling
        if case .textDelta(let info) = event {
            deltaBuffer[info.sessionID, default: ""] += info.delta

            let now = ContinuousClock.now
            let elapsed = now - lastFlushTime
            if elapsed >= .nanoseconds(Int64(Self.throttleIntervalNanos)) {
                for (sid, text) in deltaBuffer {
                    continuation.yield(.textDelta(TextDeltaInfo(
                        sessionID: sid,
                        messageID: info.messageID,
                        delta: text
                    )))
                }
                deltaBuffer.removeAll()
                lastFlushTime = now
            }
        } else {
            // Flush any pending deltas before non-delta events
            if !deltaBuffer.isEmpty {
                for (sid, text) in deltaBuffer {
                    continuation.yield(.textDelta(TextDeltaInfo(
                        sessionID: sid,
                        messageID: "",
                        delta: text
                    )))
                }
                deltaBuffer.removeAll()
                lastFlushTime = ContinuousClock.now
            }
            continuation.yield(event)
        }
    }

    // MARK: - SSE Parsing

    /// Parse a JSON SSE data payload into a typed event.
    func parseSSEData(_ dataString: String) -> SSEEvent? {
        guard let data = dataString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let eventType = json["type"] as? String else {
            return nil
        }

        let properties = json["properties"] as? [String: Any] ?? [:]

        switch eventType {
        case "server.connected":
            return .connected

        case "server.heartbeat":
            return .heartbeat

        case "message.part.updated":
            return parseMessagePartUpdated(properties)

        case "message.updated":
            // Full message update — typically used for initial load, not streaming
            return nil

        case "message.removed":
            return nil

        case "session.status":
            return parseSessionStatus(properties)

        case "session.error":
            return parseSessionError(properties)

        case "session.idle":
            // Top-level session.idle event (in addition to session.status with idle type)
            let sessionID = properties["sessionID"] as? String ?? ""
            return .sessionIdle(sessionID: sessionID)

        case "session.created", "session.updated", "session.deleted", "session.diff":
            return nil // Not needed for runtime

        case "question.asked":
            return parseQuestionAsked(properties)

        case "permission.asked":
            return parsePermissionAsked(properties)

        case "permission.replied":
            return nil // We don't need to handle our own replies

        default:
            logger.debug("Unhandled SSE event type: \(eventType)")
            return nil
        }
    }

    // MARK: - Event Parsers

    private func parseMessagePartUpdated(_ properties: [String: Any]) -> SSEEvent? {
        let part = properties["part"] as? [String: Any] ?? properties
        let delta = properties["delta"] as? String

        let sessionID = part["sessionID"] as? String ?? ""
        let messageID = part["messageID"] as? String ?? ""
        let partType = part["type"] as? String ?? ""

        switch partType {
        case "text":
            if let delta, !delta.isEmpty {
                return .textDelta(TextDeltaInfo(
                    sessionID: sessionID,
                    messageID: messageID,
                    delta: delta
                ))
            }
            // Check if text is complete (has end time)
            if let time = part["time"] as? [String: Any], time["end"] != nil {
                let text = part["text"] as? String ?? ""
                return .textComplete(TextCompleteInfo(
                    sessionID: sessionID,
                    messageID: messageID,
                    text: text
                ))
            }
            return nil

        case "reasoning":
            if let delta, !delta.isEmpty {
                return .reasoningDelta(ReasoningDeltaInfo(
                    sessionID: sessionID,
                    delta: delta
                ))
            }
            return nil

        case "tool":
            return parseToolPart(part, sessionID: sessionID)

        default:
            return nil
        }
    }

    private func parseToolPart(_ part: [String: Any], sessionID: String) -> SSEEvent? {
        let state = part["state"] as? [String: Any] ?? [:]
        let toolName = state["tool"] as? String ?? part["tool"] as? String ?? "Tool"
        let status = state["status"] as? String ?? ""
        let toolCallID = state["id"] as? String ?? part["id"] as? String

        // Input may be a dictionary or a raw string (e.g., apply_patch sends the patch as a string).
        // Wrap string inputs so they survive serialization through the bridge.
        // Also check part-level "input" as a fallback (some tools put it outside state).
        let inputDict: [String: Any]?
        if let dict = state["input"] as? [String: Any] {
            inputDict = dict
        } else if let str = state["input"] as? String, !str.isEmpty {
            inputDict = ["_rawInput": str]
        } else if let dict = part["input"] as? [String: Any] {
            inputDict = dict
        } else if let str = part["input"] as? String, !str.isEmpty {
            inputDict = ["_rawInput": str]
        } else {
            inputDict = nil
        }

        // Diagnostic: log raw tool data for file-editing tools
        let isEditTool = toolName.lowercased().contains("patch") || toolName.lowercased().contains("edit") || toolName.lowercased().contains("write")
        if isEditTool {
            let stateKeys = state.keys.sorted().joined(separator: ",")
            let partKeys = part.keys.sorted().joined(separator: ",")
            let inputType: String
            if state["input"] is [String: Any] { inputType = "dict" }
            else if state["input"] is String { inputType = "string(\((state["input"] as? String)?.count ?? 0))" }
            else if state["input"] != nil { inputType = "other(\(type(of: state["input"]!)))" }
            else { inputType = "nil" }
            logger.info("🔍 Tool SSE: \(toolName) status=\(status) stateKeys=[\(stateKeys)] partKeys=[\(partKeys)] inputType=\(inputType) hasInputDict=\(inputDict != nil)")
        }

        switch status {
        case "running", "pending":
            let inputSummary = extractPrimaryInput(from: inputDict)
            return .toolRunning(ToolInfo(
                sessionID: sessionID,
                toolName: toolName,
                toolCallID: toolCallID,
                input: inputDict,
                inputSummary: inputSummary
            ))

        case "completed":
            let output = state["output"] as? String
            let inputSummary = extractPrimaryInput(from: inputDict)
            return .toolCompleted(ToolCompletedInfo(
                sessionID: sessionID,
                toolName: toolName,
                toolCallID: toolCallID,
                output: output,
                input: inputDict,
                inputSummary: inputSummary
            ))

        case "error":
            let error = state["error"] as? String ?? "Unknown tool error"
            return .toolError(ToolErrorInfo(
                sessionID: sessionID,
                toolName: toolName,
                toolCallID: toolCallID,
                error: error
            ))

        default:
            return nil
        }
    }

    private func parseSessionStatus(_ properties: [String: Any]) -> SSEEvent? {
        let sessionID = properties["sessionID"] as? String ?? ""
        let status = properties["status"] as? [String: Any] ?? [:]
        let statusType = status["type"] as? String ?? ""

        if statusType == "idle" {
            return .sessionIdle(sessionID: sessionID)
        }

        return .sessionStatus(SessionStatusInfo(
            sessionID: sessionID,
            status: statusType
        ))
    }

    private func parseSessionError(_ properties: [String: Any]) -> SSEEvent? {
        let sessionID = properties["sessionID"] as? String ?? ""

        // The error can be a string or an object with nested data
        let errorMessage: String
        if let errorStr = properties["error"] as? String {
            errorMessage = errorStr
        } else if let errorObj = properties["error"] as? [String: Any] {
            // Nested error object: { name, data: { message, statusCode, ... } }
            if let data = errorObj["data"] as? [String: Any],
               let message = data["message"] as? String {
                let name = errorObj["name"] as? String ?? "Error"
                let statusCode = data["statusCode"] as? Int
                if let statusCode {
                    errorMessage = "\(name): \(message) (HTTP \(statusCode))"
                } else {
                    errorMessage = "\(name): \(message)"
                }
            } else if let name = errorObj["name"] as? String {
                errorMessage = name
            } else {
                errorMessage = "Unknown error"
            }
        } else {
            errorMessage = "Unknown error"
        }

        return .sessionError(SessionErrorInfo(
            sessionID: sessionID,
            error: errorMessage
        ))
    }

    private func parseQuestionAsked(_ properties: [String: Any]) -> SSEEvent? {
        let id = properties["id"] as? String ?? ""
        let sessionID = properties["sessionID"] as? String ?? ""
        let rawQuestions = properties["questions"] as? [[String: Any]] ?? []

        let questions = rawQuestions.map { q -> QuestionRequest.QuestionItem in
            let question = q["question"] as? String ?? ""
            let multiple = q["multiple"] as? Bool ?? false
            let custom = q["custom"] as? Bool ?? true

            var options: [QuestionRequest.QuestionOption] = []
            if let rawOptions = q["options"] as? [[String: Any]] {
                options = rawOptions.map { opt in
                    QuestionRequest.QuestionOption(
                        label: opt["label"] as? String ?? "",
                        description: opt["description"] as? String
                    )
                }
            }

            return QuestionRequest.QuestionItem(
                question: question,
                options: options,
                multiple: multiple,
                custom: custom
            )
        }

        return .questionAsked(QuestionRequest(
            id: id,
            sessionID: sessionID,
            questions: questions
        ))
    }

    private func parsePermissionAsked(_ properties: [String: Any]) -> SSEEvent? {
        let id = properties["id"] as? String ?? ""
        let sessionID = properties["sessionID"] as? String ?? ""
        let permission = properties["permission"] as? String ?? ""
        let patterns = properties["patterns"] as? [String] ?? []
        let always = properties["always"] as? [String] ?? []

        var metadata: [String: String] = [:]
        if let rawMeta = properties["metadata"] as? [String: Any] {
            for (key, value) in rawMeta {
                if let str = value as? String {
                    metadata[key] = str
                }
            }
        }

        return .permissionAsked(NativePermissionRequest(
            id: id,
            sessionID: sessionID,
            permission: permission,
            patterns: patterns,
            metadata: metadata,
            always: always
        ))
    }

    // MARK: - Helpers

    private func extractPrimaryInput(from dict: [String: Any]?) -> String? {
        guard let dict else { return nil }
        let keys = ["filePath", "path", "command", "description"]
        return keys.lazy.compactMap { dict[$0] as? String }.first
    }

    // MARK: - Errors

    enum SSEError: Error {
        case badStatus(Int)
    }
}
