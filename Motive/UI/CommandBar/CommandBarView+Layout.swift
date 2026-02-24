//
//  CommandBarView+Layout.swift
//  Motive
//
//  Created by geezerrrr on 2026/1/19.
//

import SwiftUI

extension CommandBarView {
    var isDark: Bool {
        colorScheme == .dark
    }

    /// Filtered commands based on input
    var filteredCommands: [CommandDefinition] {
        let query = inputText.hasPrefix("/") ? String(inputText.dropFirst()) : ""
        return CommandDefinition.matching(query)
    }

    var mainContent: some View {
        if mode.isChat {
            // Inline chat panel — fills the entire popup
            AnyView(
                ZStack {
                    commandBarBackground
                    CommandBarChatView(
                        onPopOut: { popOutToDrawer() },
                        onDismiss: { mode = appState.messages.isEmpty ? .idle : .completed }
                    )
                }
                .frame(width: 680, height: mode.dynamicHeight)
                .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.xl, style: .continuous))
            )
        } else {
            // Standard command bar layout
            AnyView(
                VStack(spacing: 0) {
                    if showsAboveContent {
                        aboveInputContent
                        Rectangle()
                            .fill(Color.Aurora.glassOverlay.opacity(0.06))
                            .frame(height: 0.5)
                    }
                    inputAreaView
                    if showsBelowContent {
                        Rectangle()
                            .fill(Color.Aurora.glassOverlay.opacity(0.06))
                            .frame(height: 0.5)
                        belowInputContent
                    } else {
                        Spacer(minLength: 0)
                    }
                    footerView
                }
                .frame(width: 680, height: currentHeight)
                .background(commandBarBackground)
                .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.xl, style: .continuous))
                .overlay(borderOverlay)
            )
        }
    }

    /// Content ABOVE input (session status)
    var showsAboveContent: Bool {
        switch mode {
        case .running, .completed, .error:
            return true
        case let .command(fromSession), let .history(fromSession), let .modes(fromSession),
             let .models(fromSession):
            return fromSession
        default:
            return false
        }
    }

    /// Content BELOW input (lists)
    var showsBelowContent: Bool {
        !mode.isChat && (mode.isCommand || mode.isHistory || mode.isProjects || mode.isModes
            || mode.isModels || isFileCompletionActive)
    }

    /// Height to use when file completion is showing (matches command list)
    var fileCompletionHeight: CGFloat {
        showsAboveContent ? 450 : 400
    }

    /// Whether file completion should actively affect height.
    /// Guards against stale `showFileCompletion` state by cross-checking the input.
    var isFileCompletionActive: Bool {
        showFileCompletion
            && !fileCompletion.items.isEmpty
            && currentAtToken(in: inputText) != nil
    }

    /// Dynamic height for the models list — scales to fit 1–5 visible items.
    var modelsListHeight: CGFloat {
        let inputArea: CGFloat = 52
        let footerArea: CGFloat = 40
        let statusArea: CGFloat = mode.isFromSession ? 50 : 0
        if availableModels.isEmpty {
            // Empty state: icon + two text labels
            return inputArea + 120 + footerArea + statusArea
        }
        let itemHeight: CGFloat = 52  // matches row height + 2pt spacing
        let visibleCount = min(availableModels.count, 5)
        let listArea = CGFloat(visibleCount) * itemHeight + 16  // vertical padding
        return (inputArea + listArea + footerArea + statusArea + 8).rounded()
    }

    /// Current command bar height
    var currentHeight: CGFloat {
        if mode.isChat { return mode.dynamicHeight }
        if isFileCompletionActive { return fileCompletionHeight }
        if mode.isModels { return modelsListHeight }
        return mode.dynamicHeight
    }

    // MARK: - Above Input Content (Session Status)

    /// Smooth expand animation for status appearing
    private var statusTransition: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.95).combined(with: .opacity).animation(.auroraSpring),
            removal: .opacity.animation(.auroraFast)
        )
    }

    var aboveInputContent: some View {
        Group {
            switch mode {
            case .running:
                runningStatusView
            case .completed:
                completedSummaryView
            case let .error(message):
                errorStatusView(message: message)
            case let .command(fromSession) where fromSession:
                // Show completed status when command triggered from session
                completedSummaryView
            case let .history(fromSession) where fromSession:
                // Show completed status when history triggered from session
                completedSummaryView
            case let .modes(fromSession) where fromSession:
                completedSummaryView
            case let .models(fromSession) where fromSession:
                completedSummaryView
            default:
                EmptyView()
            }
        }
        .transition(statusTransition)
    }

    // MARK: - Below Input Content (Lists)

    /// Smooth expand animation for lists appearing
    private var listTransition: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 0.95).combined(with: .opacity).animation(.auroraSpring),
            removal: .opacity.animation(.auroraFast)
        )
    }

    var belowInputContent: some View {
        Group {
            if isFileCompletionActive {
                // File completion takes priority
                fileCompletionListView
            } else if mode.isCommand {
                commandListView
            } else if mode.isHistory {
                historiesListView
            } else if mode.isProjects {
                projectsListView
            } else if mode.isModes {
                modesListView
            } else if mode.isModels {
                modelsListView
            } else {
                EmptyView()
            }
        }
        .transition(listTransition)
    }

    // MARK: - File Completion List (below input)

    var fileCompletionListView: some View {
        FileCompletionView(
            items: fileCompletion.items,
            selectedIndex: selectedFileIndex,
            currentPath: fileCompletion.currentPath,
            onSelect: selectFileCompletion
        )
        .id("fileCompletion-\(fileCompletion.currentPath)-\(fileCompletion.items.count)")
    }

    /// Autocomplete hint for command input (Raycast style)
    var autocompleteHint: String? {
        // Only show hint when input starts with "/" and we have matching commands
        guard inputText.hasPrefix("/"), !filteredCommands.isEmpty else { return nil }

        let query = String(inputText.dropFirst()) // Remove "/"
        let firstMatch = filteredCommands[selectedCommandIndex]

        // Return the full command name for hint
        return "/\(firstMatch.name)"
    }

    /// The portion of hint that should be shown as completion (gray text after input)
    var autocompleteCompletion: String? {
        guard let hint = autocompleteHint else { return nil }

        // If input is shorter than hint, return the remaining part
        if inputText.count < hint.count, hint.lowercased().hasPrefix(inputText.lowercased()) {
            return String(hint.dropFirst(inputText.count))
        }
        return nil
    }
}
