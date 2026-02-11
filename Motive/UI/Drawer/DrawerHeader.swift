//
//  DrawerHeader.swift
//  Motive
//
//  Aurora Design System - Drawer header with session dropdown
//

import SwiftUI

struct DrawerHeader: View {
    @EnvironmentObject private var appState: AppState
    @Binding var showSessionPicker: Bool
    let onLoadSessions: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                // Session dropdown button
                Button(action: {
                    onLoadSessions()
                    withAnimation(.auroraFast) {
                        showSessionPicker.toggle()
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color.Aurora.textSecondary)

                        Text(currentSessionTitle)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Color.Aurora.textPrimary)
                            .lineLimit(1)

                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
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

                Spacer()

                // Status badge
                SessionStatusBadge(
                    status: appState.sessionStatus,
                    currentTool: appState.currentToolName,
                    isThinking: appState.menuBarState == .reasoning
                )

                // New chat button
                Button(action: {
                    appState.startNewEmptySession()
                    onLoadSessions()
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color.Aurora.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(Color.Aurora.glassOverlay.opacity(isDark ? 0.08 : 0.10))
                        .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.sm, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(L10n.Drawer.newChat)
                .accessibilityLabel(L10n.Drawer.newChat)

                // Close button
                Button(action: { appState.hideDrawer() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color.Aurora.textMuted)
                        .frame(width: 28, height: 28)
                        .background(Color.Aurora.glassOverlay.opacity(isDark ? 0.08 : 0.10))
                        .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.sm, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(L10n.Drawer.close)
                .accessibilityLabel(L10n.Drawer.close)
            }

            // Context usage progress bar
            if let tokens = appState.currentContextTokens, tokens > 0 {
                ContextProgressBar(currentTokens: tokens)
                    .padding(.top, 6)
            }
        }
    }

    private var currentSessionTitle: String {
        if appState.messages.isEmpty {
            return L10n.Drawer.newChat
        }
        if let firstUser = appState.messages.first(where: { $0.type == .user }) {
            let text = firstUser.content
            return String(text.prefix(24)) + (text.count > 24 ? "..." : "")
        }
        return L10n.Drawer.conversation
    }
}

// MARK: - Context Progress Bar

private struct ContextProgressBar: View {
    let currentTokens: Int

    // Common model context limits (approximate)
    private var estimatedLimit: Int {
        if currentTokens > 150_000 { return 200_000 }  // 200k models
        if currentTokens > 100_000 { return 128_000 }  // 128k models
        return 128_000  // Default assumption
    }

    private var progress: Double {
        min(1.0, Double(currentTokens) / Double(estimatedLimit))
    }

    private var progressColor: Color {
        if progress > 0.85 { return Color.Aurora.error }
        if progress > 0.65 { return Color.Aurora.warning }
        return Color.Aurora.primary
    }

    private var tokenLabel: String {
        if currentTokens >= 1000 {
            return "\(currentTokens / 1000)k"
        }
        return "\(currentTokens)"
    }

    var body: some View {
        HStack(spacing: 6) {
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.Aurora.glassOverlay.opacity(0.08))
                        .frame(height: 3)

                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(progressColor.opacity(0.7))
                        .frame(width: geometry.size.width * progress, height: 3)
                        .animation(.easeInOut(duration: 0.3), value: progress)
                }
            }
            .frame(height: 3)

            // Token count label
            Text(tokenLabel)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(Color.Aurora.textMuted)
                .frame(width: 28, alignment: .trailing)
        }
    }
}
