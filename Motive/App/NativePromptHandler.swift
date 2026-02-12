//
//  NativePromptHandler.swift
//  Motive
//

import Foundation
import AppKit

@MainActor
final class NativePromptHandler {
    weak var appState: AppState?

    /// Queue for prompts that arrive while one is already showing
    private var promptQueue: [() -> Void] = []

    init(appState: AppState) {
        self.appState = appState
    }

    /// Show immediately or enqueue if another prompt is visible
    private func showOrEnqueue(_ showBlock: @escaping () -> Void) {
        guard let appState else { return }
        if appState.quickConfirmController?.isVisible == true {
            promptQueue.append(showBlock)
            return
        }
        showBlock()
    }

    /// Show next prompt from queue after current completes
    private func showNextFromQueue() {
        guard !promptQueue.isEmpty else { return }
        let next = promptQueue.removeFirst()
        next()
    }

    // MARK: - Native Question Handling

    /// Handle a native question from OpenCode's question tool (via SSE).
    func handleNativeQuestion(inputDict: [String: Any], event: OpenCodeEvent) {
        let questionID = inputDict["_nativeQuestionID"] as? String ?? UUID().uuidString
        let questionText = inputDict["question"] as? String ?? "Question from AI"
        let custom = inputDict["custom"] as? Bool ?? true
        let multiple = inputDict["multiple"] as? Bool ?? false

        // Parse options
        var options: [PermissionRequest.QuestionOption] = []
        var optionLabels: [String] = []
        if let rawOptions = inputDict["options"] as? [[String: Any]] {
            for opt in rawOptions {
                let label = opt["label"] as? String ?? ""
                let description = opt["description"] as? String
                options.append(PermissionRequest.QuestionOption(label: label, description: description))
                optionLabels.append(label)
            }
        }

        // Add custom "Other" option if custom input is enabled and not already present
        if custom && !options.contains(where: { $0.label.lowercased() == "other" }) {
            options.append(PermissionRequest.QuestionOption(label: "Other", description: "Type your own answer"))
            optionLabels.append("Other")
        }

        // Default options if none provided
        if options.isEmpty {
            options = [
                PermissionRequest.QuestionOption(label: "Yes"),
                PermissionRequest.QuestionOption(label: "No"),
                PermissionRequest.QuestionOption(label: "Other", description: "Custom response"),
            ]
            optionLabels = ["Yes", "No", "Other"]
        }

        // Detect plan_exit tool context
        let toolContext = inputDict["_toolContext"] as? String
        let isPlanExit = toolContext == "plan_exit"
        let planFilePath = inputDict["_planFilePath"] as? String

        Log.debug("Native question: \(questionText) options=\(optionLabels) isPlanExit=\(isPlanExit)")

        // Add question to conversation as a tool message (waiting for user response)
        let questionMessageId = UUID()
        appState?.pendingQuestionMessageId = questionMessageId
        let optionsSummary = " [\(optionLabels.joined(separator: " / "))]"
        let questionMsg = ConversationMessage(
            id: questionMessageId,
            type: .tool,
            content: isPlanExit ? planReadyContent(planFilePath: planFilePath) : questionText,
            toolName: isPlanExit ? "Plan Ready" : "Question",
            toolInput: questionText + optionsSummary,
            toolCallId: event.toolCallId,
            status: .running
        )
        if let sid = event.sessionId, let appState, appState.currentSession?.openCodeSessionId != sid {
            appState.messageStore.appendMessageIfNeeded(questionMsg, to: &appState.runningSessionMessages[sid, default: []])
        } else {
            appState?.messageStore.appendMessageIfNeeded(questionMsg)
        }

        // If this is a remote command, send question to iOS via CloudKit
        if let commandId = appState?.currentRemoteCommandId {
            sendQuestionToRemote(
                commandId: commandId,
                questionID: questionID,
                question: questionText,
                options: optionLabels,
                sessionID: event.sessionId
            )
            return
        }

        // Show local QuickConfirm (or enqueue if one is already showing)
        let sessionId = event.sessionId
        let sessionIntent = sessionId.flatMap { appState?.runningSessions[$0]?.intent }
            ?? appState?.currentSession?.intent
        showOrEnqueue { [weak self] in
            self?.showNativeQuestionPrompt(
                questionID: questionID,
                question: isPlanExit ? "Plan is ready. Would you like to execute it?" : questionText,
                options: isPlanExit
                    ? [
                        PermissionRequest.QuestionOption(label: "Execute Plan", description: "Start executing the plan"),
                        PermissionRequest.QuestionOption(label: "Refine", description: "Continue refining the plan"),
                    ]
                    : options,
                multiSelect: multiple,
                messageId: questionMessageId,
                sessionId: sessionId,
                sessionIntent: sessionIntent,
                isPlanExit: isPlanExit,
                planFilePath: planFilePath
            )
        }
    }

    /// Show a local QuickConfirm prompt for a native question.
    private func showNativeQuestionPrompt(
        questionID: String,
        question: String,
        options: [PermissionRequest.QuestionOption],
        multiSelect: Bool,
        messageId: UUID,
        sessionId: String? = nil,
        sessionIntent: String? = nil,
        isPlanExit: Bool = false,
        planFilePath: String? = nil
    ) {
        var request = PermissionRequest(
            id: questionID, taskId: questionID, type: .question,
            question: question,
            header: isPlanExit ? "Plan Complete" : "Question",
            options: options, multiSelect: multiSelect
        )
        request.sessionIntent = sessionIntent
        request.isPlanExitConfirmation = isPlanExit

        if appState?.quickConfirmController == nil {
            appState?.quickConfirmController = QuickConfirmWindowController()
        }

        appState?.quickConfirmController?.show(
            request: request,
            anchorFrame: appState?.statusBarController?.buttonFrame,
            onResponse: { [weak self] (response: String) in
                Log.debug("Native question response: \(response)")

                // Map plan_exit UI labels to what OpenCode expects
                let apiResponse: String
                if isPlanExit {
                    apiResponse = response == "Execute Plan" ? "Yes" : "No"
                } else {
                    apiResponse = response
                }

                self?.appState?.updateQuestionMessage(messageId: messageId, response: response, sessionId: sessionId)
                self?.appState?.pendingQuestionMessageId = nil

                if isPlanExit {
                    self?.appendPlanTransitionMessage(
                        response: response,
                        sessionId: sessionId,
                        planFilePath: planFilePath
                    )
                }

                Task { [weak self] in
                    await self?.appState?.bridge.replyToQuestion(
                        requestID: questionID,
                        answers: [[apiResponse]],
                        sessionID: sessionId
                    )
                }
                self?.appState?.updateStatusBar()
                self?.showNextFromQueue()
            },
            onCancel: { [weak self] in
                Log.debug("Native question cancelled")
                self?.appState?.updateQuestionMessage(messageId: messageId, response: "User declined to answer.", sessionId: sessionId)
                self?.appState?.pendingQuestionMessageId = nil
                Task { [weak self] in
                    await self?.appState?.bridge.rejectQuestion(requestID: questionID, sessionID: sessionId)
                }
                self?.appState?.updateStatusBar()
                self?.showNextFromQueue()
            }
        )
    }

    private func planReadyContent(planFilePath: String?) -> String {
        guard let planFilePath, !planFilePath.isEmpty else {
            return "Plan is ready. Execute?"
        }
        return "Plan is ready at \(planFilePath). Execute?"
    }

    private func appendPlanTransitionMessage(
        response: String,
        sessionId: String?,
        planFilePath: String?
    ) {
        let content: String
        if response == "Execute Plan" {
            if let planFilePath, !planFilePath.isEmpty, !resolvedPlanFileExists(path: planFilePath) {
                content = "Approved. Switching to build mode, but plan file was not found at \(planFilePath)."
            } else {
                content = "Approved. Switching to build mode and executing the plan."
            }
        } else {
            content = "Plan execution postponed. Continuing in plan mode to refine the plan."
        }

        let notice = ConversationMessage(type: .system, content: content)
        if let sid = sessionId, let appState, appState.currentSession?.openCodeSessionId != sid {
            appState.messageStore.appendMessageIfNeeded(notice, to: &appState.runningSessionMessages[sid, default: []])
        } else {
            appState?.messageStore.appendMessageIfNeeded(notice)
        }
    }

    private func resolvedPlanFileExists(path: String) -> Bool {
        if path.hasPrefix("/") {
            return FileManager.default.fileExists(atPath: path)
        }
        guard let appState else { return false }
        let cwdPath = appState.configManager.currentProjectURL.path
        let absolute = URL(fileURLWithPath: cwdPath).appendingPathComponent(path).path
        return FileManager.default.fileExists(atPath: absolute)
    }

    // MARK: - Native Permission Handling

    /// Handle a native permission request from OpenCode (via SSE).
    func handleNativePermission(inputDict: [String: Any], event: OpenCodeEvent) {
        let permissionID = inputDict["_nativePermissionID"] as? String ?? UUID().uuidString
        let permission = inputDict["permission"] as? String ?? "unknown"
        let patterns = inputDict["patterns"] as? [String] ?? []
        let metadata = inputDict["metadata"] as? [String: String] ?? [:]
        let diff = metadata["diff"]

        Log.debug("Native permission: \(permission) patterns=\(patterns)")

        // Add permission to conversation
        let permMessageId = UUID()
        appState?.pendingQuestionMessageId = permMessageId
        let patternsStr = patterns.joined(separator: ", ")
        let permMsg = ConversationMessage(
            id: permMessageId,
            type: .tool,
            content: "\(permission): \(patternsStr)",
            toolName: "Permission",
            toolInput: patternsStr,
            toolCallId: event.toolCallId,
            status: .running
        )
        if let sid = event.sessionId, let appState, appState.currentSession?.openCodeSessionId != sid {
            appState.messageStore.appendMessageIfNeeded(permMsg, to: &appState.runningSessionMessages[sid, default: []])
        } else {
            appState?.messageStore.appendMessageIfNeeded(permMsg)
        }

        // Build options for the permission dialog
        var options: [PermissionRequest.QuestionOption] = [
            PermissionRequest.QuestionOption(label: "Allow Once", description: "Allow this specific action"),
            PermissionRequest.QuestionOption(label: "Always Allow", description: "Allow and remember for this pattern"),
            PermissionRequest.QuestionOption(label: "Reject", description: "Deny this action"),
        ]

        // Include diff preview in the question text if available
        var questionText = "Allow \(permission) for \(patternsStr)?"
        if let diff, !diff.isEmpty {
            questionText += "\n\n```diff\n\(diff)\n```"
        }

        // If remote command, handle via CloudKit
        if let commandId = appState?.currentRemoteCommandId {
            sendPermissionToRemote(
                commandId: commandId,
                permissionID: permissionID,
                question: questionText,
                options: options.map(\.label),
                sessionID: event.sessionId
            )
            return
        }

        let sessionId = event.sessionId
        let sessionIntent = sessionId.flatMap { appState?.runningSessions[$0]?.intent }
            ?? appState?.currentSession?.intent
        showOrEnqueue { [weak self] in
            self?.showNativePermissionPrompt(
                permissionID: permissionID,
                questionText: questionText,
                options: options,
                patterns: patterns,
                diff: diff,
                permission: permission,
                messageId: permMessageId,
                sessionId: sessionId,
                sessionIntent: sessionIntent
            )
        }
    }

    private func showNativePermissionPrompt(
        permissionID: String,
        questionText: String,
        options: [PermissionRequest.QuestionOption],
        patterns: [String],
        diff: String?,
        permission: String,
        messageId: UUID,
        sessionId: String? = nil,
        sessionIntent: String? = nil
    ) {
        var request = PermissionRequest(
            id: permissionID, taskId: permissionID, type: .permission,
            question: questionText, header: "Permission Request",
            options: options, multiSelect: false
        )
        request.permissionType = permission
        request.patterns = patterns
        request.diff = diff
        request.sessionIntent = sessionIntent

        if appState?.quickConfirmController == nil {
            appState?.quickConfirmController = QuickConfirmWindowController()
        }

        appState?.quickConfirmController?.show(
            request: request,
            anchorFrame: appState?.statusBarController?.buttonFrame,
            onResponse: { [weak self] (response: String) in
                Log.debug("Native permission response: \(response)")
                self?.appState?.updateQuestionMessage(messageId: messageId, response: response, sessionId: sessionId)
                self?.appState?.pendingQuestionMessageId = nil

                let reply: OpenCodeAPIClient.PermissionReply
                switch response.lowercased() {
                case "always allow":
                    reply = .always
                case "reject":
                    reply = .reject(nil)
                default:
                    reply = .once
                }

                Task { [weak self] in
                    await self?.appState?.bridge.replyToPermission(requestID: permissionID, reply: reply, sessionID: sessionId)
                }
                self?.appState?.updateStatusBar()
                self?.showNextFromQueue()
            },
            onCancel: { [weak self] in
                Log.debug("Native permission rejected")
                self?.appState?.updateQuestionMessage(messageId: messageId, response: "Rejected", sessionId: sessionId)
                self?.appState?.pendingQuestionMessageId = nil
                Task { [weak self] in
                    await self?.appState?.bridge.replyToPermission(
                        requestID: permissionID,
                        reply: .reject("User rejected"),
                        sessionID: sessionId
                    )
                }
                self?.appState?.updateStatusBar()
                self?.showNextFromQueue()
            }
        )
    }

    // MARK: - Remote (CloudKit) Helpers

    /// Forward a native question to iOS via CloudKit (for remote commands).
    func sendQuestionToRemote(commandId: String, questionID: String, question: String, options: [String], sessionID: String?) {
        Log.debug("Sending question to iOS via CloudKit for remote command: \(commandId)")
        Task { [weak self] in
            let response = await self?.appState?.cloudKitManager.sendPermissionRequest(
                commandId: commandId,
                question: question,
                options: options
            )
            Log.debug(response != nil ? "Got response from iOS: \(response!)" : "No response from iOS, sending empty response")
            self?.appState?.messageStore.updateQuestionMessage(messageId: self?.appState?.pendingQuestionMessageId, response: response ?? "User declined to answer.")
            self?.appState?.pendingQuestionMessageId = nil
            await self?.appState?.bridge.replyToQuestion(
                requestID: questionID,
                answers: [[response ?? ""]],
                sessionID: sessionID
            )
            self?.appState?.updateStatusBar()
        }
    }

    /// Forward a native permission to iOS via CloudKit (for remote commands).
    func sendPermissionToRemote(commandId: String, permissionID: String, question: String, options: [String], sessionID: String?) {
        Log.debug("Sending permission to iOS via CloudKit for remote command: \(commandId)")
        Task { [weak self] in
            let response = await self?.appState?.cloudKitManager.sendPermissionRequest(
                commandId: commandId,
                question: question,
                options: options
            )
            let reply: OpenCodeAPIClient.PermissionReply
            if let response, response.lowercased().contains("always") {
                reply = .always
            } else if let response, (response.lowercased() == "allow" || response.lowercased() == "allow once") {
                reply = .once
            } else {
                reply = .reject(nil)
            }
            self?.appState?.messageStore.updateQuestionMessage(messageId: self?.appState?.pendingQuestionMessageId, response: response ?? "Rejected")
            self?.appState?.pendingQuestionMessageId = nil
            await self?.appState?.bridge.replyToPermission(requestID: permissionID, reply: reply, sessionID: sessionID)
            self?.appState?.updateStatusBar()
        }
    }

    /// Update remote command status in CloudKit
    func updateRemoteCommandStatus(toolName: String?) {
        guard let commandId = appState?.currentRemoteCommandId else { return }
        appState?.cloudKitManager.updateProgress(commandId: commandId, toolName: toolName)
    }
}
