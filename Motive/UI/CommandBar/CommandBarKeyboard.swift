//
//  CommandBarKeyboard.swift
//  Motive
//
//  Created by geezerrrr on 2026/1/19.
//

import SwiftUI

extension CommandBarView {
    // MARK: - Keyboard Navigation

    func handleUpArrow() {
        // File completion takes priority
        if showFileCompletion, !fileCompletion.items.isEmpty {
            if selectedFileIndex > 0 {
                selectedFileIndex -= 1
            }
            return
        }

        if mode.isCommand {
            if selectedCommandIndex > 0 {
                selectedCommandIndex -= 1
            }
        } else if mode.isHistory {
            if selectedHistoryIndex > 0 {
                selectedHistoryIndex -= 1
            }
            if selectedHistoryIndex < filteredHistorySessions.count {
                selectedHistoryId = filteredHistorySessions[selectedHistoryIndex].id
            }
        } else if mode.isProjects {
            if selectedProjectIndex > 0 {
                selectedProjectIndex -= 1
            }
        } else if mode.isModes {
            if selectedModeIndex > 0 {
                selectedModeIndex -= 1
            }
        } else if mode.isModels {
            if selectedModelIndex > 0 {
                selectedModelIndex -= 1
            }
        }
    }

    func handleDownArrow() {
        // File completion takes priority
        if showFileCompletion, !fileCompletion.items.isEmpty {
            if selectedFileIndex < fileCompletion.items.count - 1 {
                selectedFileIndex += 1
            }
            return
        }

        if mode.isCommand {
            if selectedCommandIndex < filteredCommands.count - 1 {
                selectedCommandIndex += 1
            }
        } else if mode.isHistory {
            if selectedHistoryIndex < filteredHistorySessions.count - 1 {
                selectedHistoryIndex += 1
            }
            if selectedHistoryIndex < filteredHistorySessions.count {
                selectedHistoryId = filteredHistorySessions[selectedHistoryIndex].id
            }
        } else if mode.isProjects {
            // 2 fixed items (Choose folder + Default) + recent projects
            let totalItems = 2 + configManager.recentProjects.count
            if selectedProjectIndex < totalItems - 1 {
                selectedProjectIndex += 1
            }
        } else if mode.isModes {
            let maxIndex = max(availableModeChoices.count - 1, 0)
            if selectedModeIndex < maxIndex {
                selectedModeIndex += 1
            }
        } else if mode.isModels {
            let maxIndex = max(availableModels.count - 1, 0)
            if selectedModelIndex < maxIndex {
                selectedModelIndex += 1
            }
        }
    }

    func handleTab() {
        // File completion takes priority
        if showFileCompletion, !fileCompletion.items.isEmpty {
            if selectedFileIndex < fileCompletion.items.count {
                selectFileCompletion(fileCompletion.items[selectedFileIndex])
            }
            return
        }

        // Tab completion: complete the autocomplete hint
        if let hint = autocompleteHint {
            inputText = hint
        }
    }

    func handleCmdN() {
        // Cmd+N to create new session (works in any mode)
        appState.startNewEmptySession()
        inputText = ""
        mode = .completed // Show "New Task" status
    }

    func handleCmdDelete() {
        // Cmd+Delete to delete selected session in history mode
        if mode.isHistory, selectedHistoryIndex < filteredHistorySessions.count {
            deleteCandidateIndex = selectedHistoryIndex
            deleteCandidateId = filteredHistorySessions[selectedHistoryIndex].id
            selectedHistoryId = filteredHistorySessions[selectedHistoryIndex].id
            showDeleteConfirmation = true
        }
    }

    func handleEscape() {
        // File completion: ESC closes it first
        if showFileCompletion {
            hideFileCompletion()
            return
        }

        // In any menu mode (command list, history, projects, modes, models), ESC goes back to idle
        if mode.isCommand || mode.isHistory || mode.isProjects || mode.isModes || mode.isModels {
            // Return to idle/input state (What should I do? prompt)
            if appState.sessionStatus == .running {
                mode = .running
            } else if !appState.messages.isEmpty {
                mode = .completed
            } else {
                mode = .idle
            }
            inputText = ""
        } else if mode == .idle || mode == .input {
            // ESC in idle/input mode = hide CommandBar (task continues running in background)
            appState.hideCommandBar()
        } else {
            // For any other mode (running, completed, error, etc), just hide the command bar
            appState.hideCommandBar()
        }
    }
}
