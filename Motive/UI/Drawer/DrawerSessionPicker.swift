//
//  DrawerSessionPicker.swift
//  Motive
//
//  Aurora Design System - Session picker overlay for drawer
//

import SwiftUI

struct DrawerSessionPicker: View {
    @EnvironmentObject private var appState: AppState
    let sessions: [Session]
    @Binding var showSessionPicker: Bool
    let onLoadSessions: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Dismiss area
            Color.black.opacity(0.01)
                .onTapGesture {
                    withAnimation(.auroraFast) {
                        showSessionPicker = false
                    }
                }

            // Dropdown menu
            VStack(spacing: 0) {
                if sessions.isEmpty {
                    Text(L10n.Drawer.noHistory)
                        .font(.Aurora.caption)
                        .foregroundColor(Color.Aurora.textMuted)
                        .padding(AuroraSpacing.space4)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(sessions.prefix(15)) { session in
                                SessionPickerItem(session: session) {
                                    appState.switchToSession(session)
                                    withAnimation(.auroraFast) {
                                        showSessionPicker = false
                                    }
                                } onDelete: {
                                    appState.deleteSession(session)
                                    onLoadSessions()
                                }
                            }
                        }
                        .padding(AuroraSpacing.space2)
                    }
                    .frame(maxHeight: 300)
                }
            }
            .frame(width: 280)
            .background(
                RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                    .fill(Color.Aurora.surface)
                    .shadow(color: Color.black.opacity(0.15), radius: 16, y: 8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                    .strokeBorder(Color.Aurora.border.opacity(0.4), lineWidth: 0.5)
            )
            .padding(.top, 52) // Below header
            .padding(.leading, AuroraSpacing.space4)
        }
        .transition(.opacity)
    }
}

// MARK: - Session Picker Item

struct SessionPickerItem: View {
    let session: Session
    let onSelect: () -> Void
    let onDelete: () -> Void
    @EnvironmentObject private var appState: AppState

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: AuroraSpacing.space3) {
            // Status dot
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)

            // Session info
            VStack(alignment: .leading, spacing: 2) {
                Text(session.intent)
                    .font(.Aurora.bodySmall.weight(.medium))
                    .foregroundColor(Color.Aurora.textPrimary)
                    .lineLimit(1)

                Text(timeAgo)
                    .font(.Aurora.caption)
                    .foregroundColor(Color.Aurora.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Delete button (separate hit target, only on hover)
            if isHovering {
                Button(action: {
                    showDeleteConfirmation()
                }) {
                    Image(systemName: "trash")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color.Aurora.textMuted)
                        .frame(width: 20, height: 20)
                        .background(Color.Aurora.glassOverlay.opacity(0.08))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.CommandBar.delete)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, AuroraSpacing.space3)
        .padding(.vertical, AuroraSpacing.space2)
        .contentShape(Rectangle())  // Entire row is hit-testable
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.sm, style: .continuous)
                .fill(isHovering ? Color.Aurora.surfaceElevated : Color.clear)
        )
        .onTapGesture(perform: onSelect)
        .onHover { isHovering = $0 }
        .animation(.auroraFast, value: isHovering)
    }

    private func showDeleteConfirmation() {
        guard let window = appState.drawerWindowRef else { return }

        // Suppress auto-hide while alert is shown
        appState.setDrawerAutoHideSuppressed(true)

        let alert = NSAlert()
        alert.messageText = L10n.Alert.deleteSessionTitle
        let sessionName = String(session.intent.prefix(50))
        alert.informativeText = String(format: L10n.Alert.deleteSessionMessage, sessionName)
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.CommandBar.delete)
        alert.addButton(withTitle: L10n.CommandBar.cancel)

        // Show as sheet attached to Drawer window
        alert.beginSheetModal(for: window) { [onDelete] response in
            if response == .alertFirstButtonReturn {
                onDelete()
            }
            // Re-enable auto-hide and refocus
            appState.setDrawerAutoHideSuppressed(false)
            window.makeKeyAndOrderFront(nil)
        }
    }

    private var statusColor: Color {
        switch session.status {
        case "running": return Color.Aurora.primary
        case "completed": return Color.Aurora.accent
        case "failed": return Color.Aurora.error
        default: return Color.Aurora.textMuted
        }
    }

    private var timeAgo: String {
        let now = Date()
        let diff = now.timeIntervalSince(session.createdAt)

        if diff < 60 { return L10n.Time.justNow }
        if diff < 3600 { return String(format: L10n.Time.minutesAgo, Int(diff / 60)) }
        if diff < 86400 { return String(format: L10n.Time.hoursAgo, Int(diff / 3600)) }
        if diff < 604800 { return String(format: L10n.Time.daysAgo, Int(diff / 86400)) }

        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter.string(from: session.createdAt)
    }
}
