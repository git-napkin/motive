//
//  StartAgentIntent.swift
//  MotiveRemote
//
//  App Intents for Siri and Shortcuts integration
//

import AppIntents
import CloudKit

// MARK: - Main Intent: Start Motive Agent

struct StartAgentIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Motive Agent"
    static var description = IntentDescription("Send an instruction to your Mac's Motive agent")
    
    @Parameter(title: "Instruction", requestValueDialog: "What should Motive do?")
    var instruction: String
    
    static var parameterSummary: some ParameterSummary {
        Summary("Have Motive do \(\.$instruction)")
    }
    
    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            let command = try await RemoteCloudKitManager.sendCommandFromIntent(instruction)
            return .result(dialog: "Command sent: \(command.instruction)")
        } catch {
            return .result(dialog: "Failed to send command: \(error.localizedDescription)")
        }
    }
}

// MARK: - Quick Action Intents

struct RefactorCodeIntent: AppIntent {
    static var title: LocalizedStringResource = "Refactor Code"
    static var description = IntentDescription("Ask Motive to refactor the current file")
    
    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            _ = try await RemoteCloudKitManager.sendCommandFromIntent("Refactor the current file to improve code quality")
            return .result(dialog: "Refactoring request sent to Mac")
        } catch {
            return .result(dialog: "Failed: \(error.localizedDescription)")
        }
    }
}

struct RunTestsIntent: AppIntent {
    static var title: LocalizedStringResource = "Run Tests"
    static var description = IntentDescription("Ask Motive to run the test suite")
    
    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            _ = try await RemoteCloudKitManager.sendCommandFromIntent("Run the test suite")
            return .result(dialog: "Test run request sent to Mac")
        } catch {
            return .result(dialog: "Failed: \(error.localizedDescription)")
        }
    }
}

struct GitCommitIntent: AppIntent {
    static var title: LocalizedStringResource = "Git Commit"
    static var description = IntentDescription("Ask Motive to commit pending changes")
    
    func perform() async throws -> some IntentResult & ProvidesDialog {
        do {
            _ = try await RemoteCloudKitManager.sendCommandFromIntent("Commit the pending changes with a descriptive message")
            return .result(dialog: "Commit request sent to Mac")
        } catch {
            return .result(dialog: "Failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - App Shortcuts Provider

struct MotiveShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartAgentIntent(),
            phrases: [
                "Start \(.applicationName)",
                "Ask \(.applicationName)"
            ],
            shortTitle: "Start Agent",
            systemImageName: "bolt.fill"
        )
        
        AppShortcut(
            intent: RefactorCodeIntent(),
            phrases: [
                "Refactor with \(.applicationName)",
                "\(.applicationName) refactor code"
            ],
            shortTitle: "Refactor",
            systemImageName: "arrow.triangle.2.circlepath"
        )
        
        AppShortcut(
            intent: RunTestsIntent(),
            phrases: [
                "Run tests with \(.applicationName)",
                "\(.applicationName) run tests"
            ],
            shortTitle: "Run Tests",
            systemImageName: "checkmark.circle"
        )
        
        AppShortcut(
            intent: GitCommitIntent(),
            phrases: [
                "Commit with \(.applicationName)",
                "\(.applicationName) git commit"
            ],
            shortTitle: "Git Commit",
            systemImageName: "arrow.up.circle"
        )
    }
}
