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
    case idle                           // Initial state, ready for input
    case input                          // User is typing intent
    case command(fromSession: Bool)     // User typed /, showing command suggestions
    case histories(fromSession: Bool)   // Showing /histories list
    case projects(fromSession: Bool)    // Showing /project list
    case running                        // Task is running
    case completed                      // Task completed, showing summary
    case error(String)                  // Error occurred
    
    var showsFooter: Bool { true }
    
    var isCommand: Bool {
        if case .command = self { return true }
        return false
    }
    
    var isHistories: Bool {
        if case .histories = self { return true }
        return false
    }
    
    var isProjects: Bool {
        if case .projects = self { return true }
        return false
    }
    
    /// Whether this mode was triggered from a session state (completed/running)
    var isFromSession: Bool {
        switch self {
        case .command(let fromSession), .histories(let fromSession), .projects(let fromSession):
            return fromSession
        default:
            return false
        }
    }
    
    var dynamicHeight: CGFloat {
        // Layout: [status bar ~50] + input(52) + [list] + footer(40) + padding
        switch self {
        case .idle, .input: 
            return 100   // input + footer + padding
        case .command(let fromSession): 
            // Same height as histories for consistency
            return fromSession ? 450 : 400   // status(50) + input + footer + list(280) + padding
        case .histories(let fromSession): 
            return fromSession ? 450 : 400   // status(50) + input + footer + list(280) + padding
        case .projects(let fromSession):
            return fromSession ? 450 : 400   // status(50) + input + footer + list(280) + padding
        case .running, .completed, .error: 
            return 160   // status + input + footer + padding
        }
    }
    
    var modeName: String {
        switch self {
        case .idle: return "idle"
        case .input: return "input"
        case .command: return "command"
        case .histories: return "histories"
        case .projects: return "projects"
        case .running: return "running"
        case .completed: return "completed"
        case .error: return "error"
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
        CommandDefinition(id: "project", name: "project", shortcut: "p", icon: "folder", description: "Switch project directory"),
        CommandDefinition(id: "histories", name: "histories", shortcut: "h", icon: "clock.arrow.circlepath", description: "View session history"),
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
    @State var showEntrance: Bool = false
    @State var selectedCommandIndex: Int = 0
    @State var selectedHistoryIndex: Int = 0
    @State var historySessions: [Session] = []
    @State var selectedProjectIndex: Int = 0
    @State var showDeleteConfirmation: Bool = false
    @FocusState var isInputFocused: Bool

    // @ file completion state
    @StateObject var fileCompletion = FileCompletionManager()
    @State var showFileCompletion: Bool = false
    @State var selectedFileIndex: Int = 0
    @State var atQueryRange: Range<String.Index>? = nil
    
    var body: some View {
        mainContent
            .onAppear(perform: handleOnAppear)
        .onChange(of: appState.commandBarResetTrigger) { _, _ in recenterAndFocus() }
        .onChange(of: inputText) { _, newValue in handleInputChange(newValue) }
        .onChange(of: mode) { oldMode, newMode in handleModeChange(from: oldMode, to: newMode) }
        .onChange(of: appState.sessionStatus) { _, newStatus in handleSessionStatusChange(newStatus) }
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
                // Refresh session list after deletion
                historySessions = appState.getAllSessions()
                if selectedHistoryIndex >= filteredHistorySessions.count {
                    selectedHistoryIndex = max(0, filteredHistorySessions.count - 1)
                }
            }
            .onChange(of: showFileCompletion) { _, isShowing in
                // File completion doesn't change height, just shows/hides list
                // Height is controlled by mode, not file completion state
            }
            .onChange(of: fileCompletion.items) { _, newItems in
                // Items change doesn't affect height either
            }
    }
}
