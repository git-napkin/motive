//
//  DrawerBadges.swift
//  Motive
//
//  Aurora Design System - Drawer Components
//

import SwiftUI

// MARK: - Session Status Badge

struct SessionStatusBadge: View {
    let status: SessionStatus
    let currentTool: String?
    let isThinking: Bool
    /// Current agent mode (e.g. "plan"). When in plan mode, "Completed" shows as "Planning" instead.
    var agent: String = "agent"

    /// Whether the session finished in plan mode (awaiting user input / plan review).
    private var isPlanWaiting: Bool {
        agent == "plan" && (status == .completed || status == .idle)
    }

    var body: some View {
        HStack(spacing: AuroraSpacing.space1) {
            statusIcon
                .font(.system(size: 10, weight: .bold))

            if status == .running && isThinking {
                ShimmerText(text: statusText)
            } else {
                Text(statusText)
                    .font(.Aurora.micro.weight(.semibold))
            }
        }
        .foregroundColor(foregroundColor)
        .padding(.horizontal, AuroraSpacing.space2)
        .padding(.vertical, AuroraSpacing.space1)
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.xs, style: .continuous)
                .fill(backgroundColor)
        )
    }

    @ViewBuilder
    private var statusIcon: some View {
        if isPlanWaiting {
            Image(systemName: "text.bubble")
        } else {
            switch status {
            case .idle:
                Image(systemName: "circle")
            case .running:
                Image(systemName: "circle.fill")
            case .completed:
                Image(systemName: "checkmark.circle.fill")
            case .failed:
                Image(systemName: "xmark.circle.fill")
            case .interrupted:
                Image(systemName: "pause.circle.fill")
            }
        }
    }

    private var statusText: String {
        if isPlanWaiting {
            return "Planning"
        }
        switch status {
        case .idle:
            return L10n.StatusBar.idle
        case .running:
            return currentTool?.simplifiedToolName ?? L10n.Drawer.running
        case .completed:
            return L10n.Drawer.completed
        case .failed:
            return L10n.Drawer.failed
        case .interrupted:
            return L10n.Drawer.interrupted
        }
    }

    private var foregroundColor: Color {
        if isPlanWaiting {
            return Color.Aurora.info
        }
        switch status {
        case .idle: return Color.Aurora.textMuted
        case .running: return Color.Aurora.primary
        case .completed: return Color.Aurora.success
        case .failed: return Color.Aurora.error
        case .interrupted: return Color.Aurora.warning
        }
    }

    private var backgroundColor: Color {
        foregroundColor.opacity(0.12)
    }
}

// MARK: - Agent Mode Toggle

/// Compact segmented toggle for switching between Agent and Plan modes.
struct AgentModeToggle: View {
    let currentAgent: String
    let isRunning: Bool
    let onChange: (String) -> Void

    private var isPlan: Bool { currentAgent == "plan" }

    var body: some View {
        HStack(spacing: 0) {
            modeButton(label: "Agent", icon: "bolt.fill", isActive: !isPlan, value: "agent")
            modeButton(label: "Plan", icon: "doc.text.magnifyingglass", isActive: isPlan, value: "plan")
        }
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.xs, style: .continuous)
                .fill(Color.Aurora.glassOverlay.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AuroraRadius.xs, style: .continuous)
                .strokeBorder(Color.Aurora.glassOverlay.opacity(0.12), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.xs, style: .continuous))
        .disabled(isRunning)
        .opacity(isRunning ? 0.5 : 1.0)
    }

    private func modeButton(label: String, icon: String, isActive: Bool, value: String) -> some View {
        Button(action: { onChange(value) }) {
            HStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 8, weight: .bold))
                Text(label)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
            }
            .foregroundColor(isActive ? activeColor(for: value) : Color.Aurora.textMuted)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                isActive
                    ? RoundedRectangle(cornerRadius: AuroraRadius.xs - 1, style: .continuous)
                        .fill(activeColor(for: value).opacity(0.12))
                    : nil
            )
        }
        .buttonStyle(.plain)
    }

    private func activeColor(for value: String) -> Color {
        value == "plan" ? Color.Aurora.info : Color.Aurora.primary
    }
}

// MARK: - Agent Mode Badge

/// Compact badge showing the current agent mode (e.g. "Plan").
struct AgentModeBadge: View {
    let agent: String

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 9, weight: .bold))
            Text(agent)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
        }
        .foregroundColor(Color.Aurora.info)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.xs, style: .continuous)
                .fill(Color.Aurora.info.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AuroraRadius.xs, style: .continuous)
                .strokeBorder(Color.Aurora.info.opacity(0.25), lineWidth: 0.5)
        )
    }
}

// MARK: - Context Size Badge

struct ContextSizeBadge: View {
    let tokens: Int

    var body: some View {
        HStack(spacing: AuroraSpacing.space1) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 10, weight: .bold))

            Text("CTX \(TokenUsageFormatter.formatTokens(tokens))")
                .font(.Aurora.micro.weight(.semibold))
        }
        .foregroundColor(Color.Aurora.textSecondary)
        .padding(.horizontal, AuroraSpacing.space2)
        .padding(.vertical, AuroraSpacing.space1)
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.xs, style: .continuous)
                .fill(Color.Aurora.glassOverlay.opacity(0.08))
        )
    }
}
