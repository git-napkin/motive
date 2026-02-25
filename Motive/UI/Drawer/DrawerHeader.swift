//
//  DrawerHeader.swift
//  Motive
//
//  Aurora Design System - Drawer header with session dropdown
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DrawerHeader: View {
    @EnvironmentObject private var appState: AppState
    @Binding var showSessionPicker: Bool
    let onLoadSessions: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        VStack(spacing: 0) {
            headerChrome
            statusInfoRows
        }
    }

    // MARK: - Header Chrome

    /// Top row: session picker button, status badges, action buttons.
    private var headerChrome: some View {
        HStack(spacing: 10) {
            sessionPickerButton

            Spacer()

            if runningOtherCount > 0 {
                RunningCountBadge(count: runningOtherCount) {
                    onLoadSessions()
                    withAnimation(.auroraFast) { showSessionPicker = true }
                }
            }

            SessionStatusBadge(
                status: appState.sessionStatus,
                currentTool: appState.currentToolName,
                isThinking: appState.menuBarState == .reasoning,
                agent: appState.currentSessionAgent
            )

            yoloToggleButton
            exportButton
            newChatButton
            closeButton
        }
    }

    // MARK: - Session Picker Button

    private var sessionPickerButton: some View {
        Button(action: {
            onLoadSessions()
            withAnimation(.auroraFast) { showSessionPicker.toggle() }
        }) {
            HStack(spacing: 6) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.Aurora.textSecondary)

                Text(currentSessionTitle)
                    .font(.Aurora.bodySmall.weight(.semibold))
                    .foregroundColor(Color.Aurora.textPrimary)
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.Aurora.micro.weight(.bold))
                    .foregroundColor(Color.Aurora.textMuted)
                    .rotationEffect(.degrees(showSessionPicker ? 180 : 0))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: AuroraRadius.sm, style: .continuous)
                    .fill(Color.Aurora.glassOverlay.opacity(showSessionPicker ? 0.10 : 0.06))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Action Buttons

    private var yoloToggleButton: some View {
        Button { appState.sessionAllowsAll.toggle() } label: {
            Image(systemName: appState.sessionAllowsAll ? "bolt.fill" : "bolt")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(appState.sessionAllowsAll ? Color.orange : Color.Aurora.textMuted)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(appState.sessionAllowsAll ? Color.orange.opacity(0.15) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .help("Auto-allow all permission requests for this session")
    }

    private var exportButton: some View {
        Button(action: exportConversation) {
            Image(systemName: "square.and.arrow.up")
                .font(.Aurora.micro.weight(.bold))
                .foregroundColor(Color.Aurora.textMuted)
                .frame(width: 28, height: 28)
                .background(Color.Aurora.glassOverlay.opacity(isDark ? 0.08 : 0.10))
                .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.sm, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AuroraRadius.sm, style: .continuous)
                        .strokeBorder(Color.Aurora.glassOverlay.opacity(0.1), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .disabled(appState.messages.isEmpty)
        .opacity(appState.messages.isEmpty ? 0.4 : 1)
        .help(L10n.Drawer.exportConversation)
        .accessibilityLabel(L10n.Drawer.exportConversationA11y)
    }

    private var newChatButton: some View {
        Button(action: {
            appState.startNewEmptySession()
            onLoadSessions()
        }) {
            Image(systemName: "plus")
                .font(.Aurora.micro.weight(.bold))
                .foregroundColor(Color.Aurora.textSecondary)
                .frame(width: 28, height: 28)
                .background(Color.Aurora.glassOverlay.opacity(isDark ? 0.08 : 0.10))
                .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.sm, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AuroraRadius.sm, style: .continuous)
                        .strokeBorder(Color.Aurora.glassOverlay.opacity(0.1), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .help(L10n.Drawer.newChat)
        .accessibilityLabel(L10n.Drawer.newChat)
    }

    private var closeButton: some View {
        Button(action: { appState.hideDrawer() }) {
            Image(systemName: "xmark")
                .font(.Aurora.micro.weight(.bold))
                .foregroundColor(Color.Aurora.textMuted)
                .frame(width: 28, height: 28)
                .background(Color.Aurora.glassOverlay.opacity(isDark ? 0.08 : 0.10))
                .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.sm, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AuroraRadius.sm, style: .continuous)
                        .strokeBorder(Color.Aurora.glassOverlay.opacity(0.1), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .help(L10n.Drawer.close)
        .accessibilityLabel(L10n.Drawer.close)
    }

    // MARK: - Status Info Rows

    /// Secondary rows shown below the chrome: queue strip, plan path, token bar.
    @ViewBuilder
    private var statusInfoRows: some View {
        if runningOtherCount > 0 {
            SessionQueueStrip(sessions: appState.getRunningSessions().filter { $0.id != appState.currentSession?.id })
                .padding(.top, 6)
                .transition(.opacity.combined(with: .move(edge: .top)))
        }

        if let planPath = appState.currentPlanFilePath, !planPath.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "doc.text")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color.Aurora.textMuted)
                Text("Plan file: \(displayPlanPath(planPath))")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundColor(Color.Aurora.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
            }
            .padding(.top, 6)
        }

        if let ctxTokens = appState.currentContextTokens {
            TokenUsageBarView(
                contextTokens: ctxTokens,
                outputTokens: appState.currentSessionOutputTokens,
                sessionCost: appState.currentSessionCost
            )
            .padding(.top, 4)
        }
    }

    // MARK: - Helpers

    private var runningOtherCount: Int {
        let running = appState.getRunningSessions()
        let currentId = appState.currentSession?.id
        return running.count(where: { $0.id != currentId })
    }

    private var currentSessionTitle: String {
        if appState.messages.isEmpty { return L10n.Drawer.newChat }
        if let firstUser = appState.messages.first(where: { $0.type == .user }) {
            let text = firstUser.content
            return String(text.prefix(24)) + (text.count > 24 ? "..." : "")
        }
        return L10n.Drawer.conversation
    }

    private func displayPlanPath(_ path: String) -> String {
        if path.hasPrefix("/") {
            let cwd = appState.configManager.currentProjectURL.path
            if path.hasPrefix(cwd + "/") {
                return String(path.dropFirst(cwd.count + 1))
            }
        }
        return path
    }

    // MARK: - Export

    private func exportConversation() {
        let markdown = ConversationExporter.toMarkdown(appState.messages)

        let panel = NSSavePanel()
        panel.title = L10n.Drawer.exportConversation
        panel.allowedContentTypes = [.init(filenameExtension: "md")!]
        let dateStr = ISO8601DateFormatter().string(from: Date()).prefix(10)
        panel.nameFieldStringValue = "motive-session-\(dateStr).md"
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop")

        guard panel.runModal() == .OK, let url = panel.url else { return }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try markdown.write(to: url, atomically: true, encoding: .utf8)
                DispatchQueue.main.async {
                    appState.showExportSuccessToast()
                }
            } catch {
                Log.error("Failed to export conversation: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Running Count Badge

/// Compact pill showing the count of other running sessions with a pulsing dot.
private struct RunningCountBadge: View {
    let count: Int
    let onTap: () -> Void

    @State private var isPulsing = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.Aurora.success)
                    .frame(width: 6, height: 6)
                    .opacity(isPulsing ? 0.4 : 1.0)
                    .animation(
                        .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                        value: isPulsing
                    )

                Text("\(count)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(Color.Aurora.success)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.Aurora.success.opacity(0.12))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.Aurora.success.opacity(0.25), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .help("\(count) other session\(count == 1 ? "" : "s") running")
        .accessibilityLabel("\(count) other session\(count == 1 ? "" : "s") running. Tap to view.")
        .onAppear { isPulsing = true }
    }
}

// MARK: - Session Queue Strip

/// Horizontal scroll of session chips for concurrent running sessions.
struct SessionQueueStrip: View {
    let sessions: [Session]
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(sessions) { session in
                    SessionQueueChip(session: session) {
                        appState.switchToSession(session)
                    }
                }
            }
        }
    }
}

/// Individual chip for a running session in the queue strip.
private struct SessionQueueChip: View {
    let session: Session
    let onTap: () -> Void

    @State private var isPulsing = false
    @State private var isHovering = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Circle()
                    .fill(Color.Aurora.success)
                    .frame(width: 5, height: 5)
                    .opacity(isPulsing ? 0.35 : 1.0)
                    .animation(
                        .easeInOut(duration: 0.75).repeatForever(autoreverses: true),
                        value: isPulsing
                    )
                    .onAppear { isPulsing = true }

                Text(session.intent)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(isHovering ? Color.Aurora.textPrimary : Color.Aurora.textSecondary)
                    .lineLimit(1)
                    .frame(maxWidth: 110)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(isHovering
                          ? Color.Aurora.success.opacity(0.15)
                          : Color.Aurora.success.opacity(0.08))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.Aurora.success.opacity(0.25), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.auroraFast, value: isHovering)
        .help(session.intent)
    }
}
