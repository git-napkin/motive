//
//  CommandBarView.swift
//  Motive
//
//  Aurora Design System - CommandBar (Spotlight Enhanced)
//  State machine driven transforming command center
//

import AppKit
import SwiftUI

// MARK: - CommandBar State

enum CommandBarMode: Equatable {
    case idle // Initial state, ready for input
    case input // User is typing intent
    case command(fromSession: Bool) // User typed /, showing command suggestions
    case history(fromSession: Bool) // Showing /history list
    case projects(fromSession: Bool) // Showing /project list
    case modes(fromSession: Bool) // Showing /mode selection list
    case models(fromSession: Bool) // Showing /models selection list
    case running // Task is running
    case completed // Task completed, showing summary
    case error(String) // Error occurred
    case chat // Inline conversation panel

    var showsFooter: Bool {
        true
    }

    var isChat: Bool {
        self == .chat
    }

    var isCommand: Bool {
        if case .command = self { return true }
        return false
    }

    var isHistory: Bool {
        if case .history = self { return true }
        return false
    }

    var isProjects: Bool {
        if case .projects = self { return true }
        return false
    }

    var isModes: Bool {
        if case .modes = self { return true }
        return false
    }

    var isModels: Bool {
        if case .models = self { return true }
        return false
    }

    /// Whether this mode was triggered from a session state (completed/running)
    var isFromSession: Bool {
        switch self {
        case let .command(fromSession), let .history(fromSession),
             let .projects(fromSession), let .modes(fromSession),
             let .models(fromSession):
            fromSession
        default:
            false
        }
    }

    var dynamicHeight: CGFloat {
        // Layout: [status bar ~50] + input(52) + [list] + footer(40) + padding
        switch self {
        case .idle, .input:
            100 // input + footer + padding
        case let .command(fromSession):
            fromSession ? 450 : 400
        case let .history(fromSession):
            fromSession ? 450 : 400
        case let .projects(fromSession):
            fromSession ? 450 : 400
        case let .modes(fromSession):
            fromSession ? 280 : 230
        case let .models(fromSession):
            fromSession ? 450 : 400
        case .running, .completed, .error:
            160
        case .chat:
            520
        }
    }

    var modeName: String {
        switch self {
        case .idle: "idle"
        case .input: "input"
        case .command: "command"
        case .history: "history"
        case .projects: "projects"
        case .modes: "modes"
        case .models: "models"
        case .running: "running"
        case .completed: "completed"
        case .error: "error"
        case .chat: "chat"
        }
    }
}

// MARK: - Command Definition

struct CommandDefinition: Identifiable {
    let id: String
    let name: String
    let shortcut: String?
    let icon: String
    let description: String

    static let allCommands: [CommandDefinition] = [
        CommandDefinition(id: "mode", name: "mode", shortcut: "m", icon: "arrow.triangle.2.circlepath", description: "Switch between agent and plan modes"),
        CommandDefinition(id: "project", name: "project", shortcut: "p", icon: "folder", description: "Switch project directory"),
        CommandDefinition(id: "models", name: "models", shortcut: nil, icon: "cpu", description: "Select AI model for current provider"),
        CommandDefinition(id: "history", name: "history", shortcut: "h", icon: "clock.arrow.circlepath", description: "View session history"),
        CommandDefinition(id: "settings", name: "settings", shortcut: "s", icon: "gearshape", description: "Open settings"),
        CommandDefinition(id: "new", name: "new", shortcut: "n", icon: "plus.circle", description: "Start new session"),
        CommandDefinition(id: "clear", name: "clear", shortcut: nil, icon: "trash", description: "Clear current conversation"),
    ]

    static func matching(_ query: String) -> [CommandDefinition] {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        if q.isEmpty { return allCommands }
        return allCommands.filter { cmd in
            cmd.name.hasPrefix(q) || cmd.shortcut == q
        }
    }
}

// MARK: - Main CommandBar View

struct CommandBarView: View {
    @EnvironmentObject var configManager: ConfigManager
    @EnvironmentObject var appState: AppState
    @Environment(\.colorScheme) var colorScheme

    @State var inputText: String = ""
    @State var mode: CommandBarMode = .idle
    @State var selectedCommandIndex: Int = 0
    @State var selectedHistoryIndex: Int = 0
    @State var historySessions: [Session] = []
    @State var selectedProjectIndex: Int = 0
    @State var selectedModeIndex: Int = 0
    @State var selectedModelIndex: Int = 0
    @State var showErrorDetailsPopover: Bool = false
    @State var showDeleteConfirmation: Bool = false
    @State var deleteCandidateIndex: Int? = nil
    @State var selectedHistoryId: UUID? = nil
    @State var deleteCandidateId: UUID? = nil
    @FocusState var isInputFocused: Bool

    // @ file completion state
    @StateObject var fileCompletion = FileCompletionManager()
    @State var showFileCompletion: Bool = false
    @State var selectedFileIndex: Int = 0
    @State var atQueryRange: Range<String.Index>? = nil

    var body: some View {
        mainContent
            .onAppear(perform: handleOnAppear)
            .onChange(of: appState.commandBarResetTrigger) { _, _ in
                recenterAndFocus()
                let targetHeight = currentHeight
                DispatchQueue.main.async {
                    appState.updateCommandBarHeight(to: targetHeight)
                }
            }
            .onChange(of: inputText) { _, newValue in handleInputChange(newValue) }
            .onChange(of: mode) { oldMode, newMode in handleModeChange(from: oldMode, to: newMode) }
            .onChange(of: appState.sessionStatus) { _, newStatus in handleSessionStatusChange(newStatus) }
            .onChange(of: currentHeight, initial: true) { _, newHeight in
                DispatchQueue.main.async {
                    appState.updateCommandBarHeight(to: newHeight)
                }
            }
            .onKeyPress(.escape, action: { handleEscape(); return .handled })
            .onKeyPress(.upArrow, action: { handleUpArrow(); return .handled })
            .onKeyPress(.downArrow, action: { handleDownArrow(); return .handled })
            .onKeyPress(.tab, action: { handleTab(); return .handled })
            .onChange(of: showDeleteConfirmation) { _, shouldShow in
                if shouldShow {
                    showDeleteAlert()
                }
            }
            .onChange(of: appState.sessionListRefreshTrigger) { _, _ in
                refreshHistorySessions(preferredIndex: selectedHistoryIndex)
            }
    }
}
