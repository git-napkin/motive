//
//  DrawerView.swift
//  Motive
//
//  Aurora Design System - Drawer (Conversation Panel)
//  Session management via dropdown menu in header
//

import SwiftUI

struct DrawerView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var configManager: ConfigManager
    @StateObject private var permissionManager = PermissionManager.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var showContent = false
    @State private var inputText = ""
    @State private var showSessionPicker = false
    @State private var sessions: [Session] = []
    @FocusState private var isInputFocused: Bool

    // @ file completion state
    @StateObject private var fileCompletion = FileCompletionManager()
    @State private var showFileCompletion: Bool = false
    @State private var selectedFileIndex: Int = 0
    @State private var atQueryRange: Range<String.Index>? = nil
    @State private var streamingScrollTask: Task<Void, Never>?

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        ZStack {
            // Premium glass background
            drawerBackground

            VStack(spacing: 0) {
                // Header with session dropdown
                DrawerHeader(showSessionPicker: $showSessionPicker, onLoadSessions: loadSessions)
                    .padding(.horizontal, AuroraSpacing.space4)
                    .padding(.top, AuroraSpacing.space4)
                    .padding(.bottom, AuroraSpacing.space3)

                // Subtle glass separator
                Rectangle()
                    .fill(Color.Aurora.glassOverlay.opacity(isDark ? 0.06 : 0.12))
                    .frame(height: 0.5)

                // Background sessions indicator
                if !appState.backgroundSessions.isEmpty {
                    BackgroundSessionsBar(
                        sessions: appState.backgroundSessions,
                        onDismiss: { id in appState.dismissBackgroundSession(id: id) }
                    )
                }

                // Content
                if appState.messages.isEmpty {
                    emptyState
                } else if !appState.messages.isEmpty {
                    DrawerConversationContent(showContent: showContent, streamingScrollTask: $streamingScrollTask)
                } else {
                    Spacer()
                }

                // Input area (always visible)
                DrawerChatInput(
                    inputText: $inputText,
                    isInputFocused: $isInputFocused,
                    onSubmit: handleInputSubmit,
                    onTextChange: checkForAtCompletion
                )
            }

            // Session picker overlay
            if showSessionPicker {
                DrawerSessionPicker(
                    sessions: sessions,
                    showSessionPicker: $showSessionPicker,
                    onLoadSessions: loadSessions
                )
            }

            // File completion overlay
            if showFileCompletion && !fileCompletion.items.isEmpty {
                fileCompletionView
            }

            // Permission request overlay
            if permissionManager.isShowingRequest, let request = permissionManager.currentRequest {
                PermissionRequestView(request: request) { response in
                    permissionManager.respond(with: response)
                }
                .transition(.opacity)
            }
        }
        .frame(width: 400, height: 600)
        .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AuroraRadius.xl, style: .continuous)
                .strokeBorder(Color.Aurora.glassOverlay.opacity(isDark ? 0.10 : 0.15), lineWidth: 0.5)
        )
        .onAppear {
            withAnimation(.auroraSpring.delay(0.1)) {
                showContent = true
            }
            loadSessions()
        }
        .onKeyPress(.upArrow) {
            if showFileCompletion && !fileCompletion.items.isEmpty {
                if selectedFileIndex > 0 {
                    selectedFileIndex -= 1
                }
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.downArrow) {
            if showFileCompletion && !fileCompletion.items.isEmpty {
                if selectedFileIndex < fileCompletion.items.count - 1 {
                    selectedFileIndex += 1
                }
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.tab) {
            if showFileCompletion && !fileCompletion.items.isEmpty {
                if selectedFileIndex < fileCompletion.items.count {
                    selectFileCompletion(fileCompletion.items[selectedFileIndex])
                }
                return .handled
            }
            return .ignored
        }
        .onKeyPress(.escape) {
            if showFileCompletion {
                hideFileCompletion()
                return .handled
            }
            return .ignored
        }
    }

    private func loadSessions() {
        sessions = appState.getAllSessions()
    }

    // MARK: - Background

    private var drawerBackground: some View {
        ZStack {
            // Layer 1: System vibrancy blur (primary translucency)
            VisualEffectView(
                material: .popover,
                blendingMode: .behindWindow,
                state: .active,
                cornerRadius: AuroraRadius.xl,
                masksToBounds: true
            )

            // Layer 2: Tint overlay — translucent to let the glass show through
            RoundedRectangle(cornerRadius: AuroraRadius.xl, style: .continuous)
                .fill(Color.Aurora.background.opacity(isDark ? 0.6 : 0.7))
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: AuroraSpacing.space5) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.Aurora.glassOverlay.opacity(isDark ? 0.06 : 0.08))
                    .frame(width: 80, height: 80)

                Image(systemName: "sparkles")
                    .font(.system(size: 32, weight: .light))
                    .foregroundColor(Color.Aurora.primary)
            }

            VStack(spacing: AuroraSpacing.space2) {
                Text(L10n.Drawer.startConversation)
                    .font(.Aurora.headline)
                    .foregroundColor(Color.Aurora.textPrimary)

                Text(L10n.Drawer.startHint)
                    .font(.Aurora.bodySmall)
                    .foregroundColor(Color.Aurora.textMuted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }

            // Hint about session dropdown
            Text(L10n.Drawer.tip)
                .font(.Aurora.caption)
                .foregroundColor(Color.Aurora.textMuted)

            Spacer()
        }
        .padding(AuroraSpacing.space6)
    }

    // MARK: - File Completion Overlay

    private var fileCompletionView: some View {
        ZStack(alignment: .bottom) {
            // Dismiss area
            Color.black.opacity(0.01)
                .onTapGesture {
                    hideFileCompletion()
                }

            // File completion popup
            VStack(spacing: 0) {
                FileCompletionView(
                    items: fileCompletion.items,
                    selectedIndex: selectedFileIndex,
                    currentPath: fileCompletion.currentPath,
                    onSelect: selectFileCompletion,
                    maxHeight: 240
                )
                .id("fileCompletion-\(fileCompletion.currentPath)-\(fileCompletion.items.count)")
            }
            .frame(width: 360)
            .background(
                RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                    .fill(Color.Aurora.surface)
                    .shadow(color: Color.black.opacity(0.15), radius: 16, y: -6)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                    .strokeBorder(Color.Aurora.border.opacity(0.4), lineWidth: 0.5)
            )
            .padding(.bottom, 80) // Position above input area
        }
        .transition(.opacity)
    }

    // MARK: - Input Handling

    private func handleInputSubmit() {
        // File completion: select item on Enter
        if showFileCompletion && !fileCompletion.items.isEmpty {
            if selectedFileIndex < fileCompletion.items.count {
                selectFileCompletion(fileCompletion.items[selectedFileIndex])
            }
            return
        }

        sendMessage()
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        hideFileCompletion()

        if appState.messages.isEmpty {
            appState.submitIntent(text)
        } else {
            appState.resumeSession(with: text)
        }
    }

    // MARK: - @ File Completion

    private func checkForAtCompletion(_ text: String) {
        guard let token = DrawerFileCompletion.currentAtToken(in: text) else {
            hideFileCompletion()
            return
        }

        let query = token.query
        let newRange = token.range

        // Skip if range and query haven't changed (avoid re-loading after manual selection)
        if showFileCompletion, let oldRange = atQueryRange, oldRange == newRange {
            return
        }

        atQueryRange = newRange

        let baseDir = fileCompletion.getBaseDirectory(for: configManager)
        fileCompletion.loadItems(query: query, baseDir: baseDir)

        showFileCompletion = true
        selectedFileIndex = 0
    }

    private func hideFileCompletion() {
        showFileCompletion = false
        atQueryRange = nil
        fileCompletion.clear()
    }

    private func selectFileCompletion(_ item: FileCompletionItem) {
        guard let range = atQueryRange else { return }

        let replacement: String
        if item.isDirectory {
            replacement = "@\(item.path)/"
        } else {
            replacement = "@\(item.path) "
        }

        // Calculate the new @ range after replacement
        let startIndex = range.lowerBound
        inputText.replaceSubrange(range, with: replacement)

        // Reset selection index
        selectedFileIndex = 0

        // If it's a directory, reload completions for the new path
        if item.isDirectory {
            // Update atQueryRange to point to the new @ token
            if let newEndIndex = inputText.index(startIndex, offsetBy: replacement.count, limitedBy: inputText.endIndex) {
                atQueryRange = startIndex..<newEndIndex

                // Directly load items for the new directory
                let baseDir = fileCompletion.getBaseDirectory(for: configManager)
                fileCompletion.loadItems(query: replacement, baseDir: baseDir)

                // Keep completion visible
                showFileCompletion = true
            } else {
                hideFileCompletion()
            }
        } else {
            // File selected - hide completion (space already added)
            hideFileCompletion()
        }
    }
}

// MARK: - Background Sessions Bar

private struct BackgroundSessionsBar: View {
    let sessions: [BackgroundSession]
    let onDismiss: (String) -> Void

    @State private var expandedSessionId: String?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(sessions) { session in
                VStack(spacing: 0) {
                    // Header row — always visible
                    HStack(spacing: 8) {
                        // Status icon
                        Group {
                            switch session.status {
                            case .running:
                                ProgressView()
                                    .scaleEffect(0.5)
                                    .frame(width: 12, height: 12)
                            case .completed:
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color.Aurora.success)
                            case .failed:
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color.Aurora.error)
                            default:
                                Image(systemName: "circle")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color.Aurora.textMuted)
                            }
                        }

                        // Intent text
                        Text(session.intent)
                            .font(.system(size: 11))
                            .foregroundColor(Color.Aurora.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        Spacer()

                        // Expand/collapse chevron (only for completed/failed with content)
                        if session.status != .running, hasContent(session) {
                            Image(systemName: expandedSessionId == session.id ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(Color.Aurora.textMuted)
                        }

                        // Dismiss button (only for completed/failed)
                        if session.status != .running {
                            Button {
                                withAnimation(.auroraFast) {
                                    onDismiss(session.id)
                                }
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(Color.Aurora.textMuted)
                                    .frame(width: 16, height: 16)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard session.status != .running, hasContent(session) else { return }
                        withAnimation(.auroraFast) {
                            expandedSessionId = expandedSessionId == session.id ? nil : session.id
                        }
                    }

                    // Expanded result/error content
                    if expandedSessionId == session.id {
                        expandedContent(for: session)
                    }

                    // Separator between sessions
                    Rectangle()
                        .fill(Color.Aurora.glassOverlay.opacity(0.06))
                        .frame(height: 0.5)
                }
            }
        }
        .background(Color.Aurora.info.opacity(0.05))
    }

    private func hasContent(_ session: BackgroundSession) -> Bool {
        (session.resultText != nil && !session.resultText!.isEmpty)
            || (session.errorText != nil && !session.errorText!.isEmpty)
    }

    @ViewBuilder
    private func expandedContent(for session: BackgroundSession) -> some View {
        let text = session.status == .failed
            ? (session.errorText ?? "Unknown error")
            : (session.resultText ?? "")

        ScrollView {
            Text(text)
                .font(.system(size: 11))
                .foregroundColor(
                    session.status == .failed
                        ? Color.Aurora.error
                        : Color.Aurora.textPrimary
                )
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .frame(maxHeight: 160)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}
