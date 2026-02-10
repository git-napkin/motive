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
    }

    private var currentSessionTitle: String {
        if appState.messages.isEmpty {
            return L10n.Drawer.newChat
        }
        if let firstUser = appState.messages.first(where: { $0.type == .user }) {
            let text = firstUser.content
            return String(text.prefix(24)) + (text.count > 24 ? "…" : "")
        }
        return L10n.Drawer.conversation
    }
}
