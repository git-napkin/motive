//
//  ToolBubble.swift
//  Motive
//
//  Aurora Design System - Tool call message bubble component
//

import SwiftUI

struct ToolBubble: View {
    let message: ConversationMessage
    let isDark: Bool
    @Binding var isDetailExpanded: Bool
    /// Collapse to header-only. Independent from output expand/collapse.
    @State private var isCollapsed = false

    var body: some View {
        VStack(alignment: .leading, spacing: AuroraSpacing.space1) {
            HStack(spacing: AuroraSpacing.space2) {
                // Status-aware icon
                toolStatusIcon

                Text(message.toolName?.simplifiedToolName ?? L10n.Drawer.tool)
                    .font(.Aurora.caption.weight(.medium))
                    .foregroundColor(Color.Aurora.textSecondary)

                Spacer()

                // Output detail expand/collapse (only meaningful when not fully collapsed)
                if !isCollapsed, message.toolOutput != nil {
                    Button(action: { withAnimation(.auroraFast) { isDetailExpanded.toggle() } }) {
                        Text(isDetailExpanded ? L10n.hide : L10n.show)
                            .font(.Aurora.micro.weight(.medium))
                            .foregroundColor(Color.Aurora.textMuted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isDetailExpanded ? L10n.Drawer.hideOutput : L10n.Drawer.showOutput)
                }

                // Full bubble collapse — shows header only
                Button(action: { withAnimation(.auroraFast) { isCollapsed.toggle() } }) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(Color.Aurora.textMuted)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .help(isCollapsed ? "Expand" : "Collapse")
            }

            if !isCollapsed {
                // Tool input label (path, command, description — never raw output)
                if let toolInput = message.toolInput, !toolInput.isEmpty {
                    Text(toolInput)
                        .font(.Aurora.monoSmall)
                        .foregroundColor(Color.Aurora.textMuted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                // Inline diff preview for file-editing tools (always visible, no click needed)
                if let diff = message.diffContent, !diff.isEmpty {
                    DiffPreviewView(diff: diff, isDark: isDark, isDetailExpanded: $isDetailExpanded)
                }

                // Uniform output summary: always "Output · N lines", click Show for details
                if let outputSummary = message.toolOutputSummary {
                    Text(outputSummary)
                        .font(.Aurora.micro)
                        .foregroundColor(Color.Aurora.textMuted)
                } else if message.status == .running {
                    // Tool is still executing — show processing hint
                    Text(L10n.Drawer.processing)
                        .font(.Aurora.micro)
                        .foregroundColor(Color.Aurora.textMuted)
                }

                if isDetailExpanded, let output = message.toolOutput, !output.isEmpty {
                    ScrollView {
                        OutputFormatter.formattedOutput(output, toolName: message.toolName, isDark: isDark)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 300)
                    .padding(.top, AuroraSpacing.space2)
                }
            }
        }
        .padding(.horizontal, AuroraSpacing.space3)
        .padding(.vertical, AuroraSpacing.space2)
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                .fill(Color.Aurora.glassOverlay.opacity(isDark ? 0.04 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                .strokeBorder(toolBorderColor.opacity(0.3), lineWidth: 0.5)
        )
        .contextMenu { toolContextMenu }
    }

    /// Right-click context menu for quick permission overrides.
    @ViewBuilder
    private var toolContextMenu: some View {
        // Pattern-based "Always Allow" for bash commands
        if let input = message.toolInput, !input.isEmpty,
           let perm = toolPermission, perm == .bash {
            let prefix = bashCommandPrefix(from: input)
            Button {
                let rule = ToolPermissionRule(
                    pattern: prefix,
                    action: .allow,
                    description: "Added from ToolBubble"
                )
                ToolPermissionPolicy.shared.addRule(rule, to: .bash)
            } label: {
                Label("Always Allow: \(prefix)", systemImage: "checkmark.shield")
            }
            Divider()
        }

        // Always Allow the entire tool category
        if let perm = toolPermission {
            Button {
                ToolPermissionPolicy.shared.setDefaultAction(.allow, for: perm)
            } label: {
                Label("Always Allow \(perm.displayName) tool", systemImage: "shield.fill")
            }
        }

        Divider()

        Button {
            NotificationCenter.default.post(name: .openPermissionSettings, object: nil)
        } label: {
            Label("Manage Permissions…", systemImage: "gearshape")
        }
    }

    /// Maps the message's tool name to a `ToolPermission` case.
    private var toolPermission: ToolPermission? {
        guard let name = message.toolName else { return nil }
        let n = name.lowercased()
        if n.contains("bash") || n.contains("shell") || n.contains("execute") { return .bash }
        if n.contains("edit") || n.contains("write") || n.contains("create") { return .edit }
        if n.contains("read") { return .read }
        if n.contains("glob") { return .glob }
        if n.contains("grep") || n.contains("search") { return .grep }
        if n.contains("list") { return .list }
        if n.contains("task") { return .task }
        if n.contains("fetch") { return .webfetch }
        return nil
    }

    /// Extracts a glob pattern from a bash command: "git status -s" → "git *"
    private func bashCommandPrefix(from input: String) -> String {
        let first = input.split(separator: " ", maxSplits: 1).first.map(String.init) ?? input
        return "\(first) *"
    }

    /// Status-aware icon for tool bubble: spinner when running, checkmark when done
    @ViewBuilder
    private var toolStatusIcon: some View {
        switch message.status {
        case .running:
            ToolRunningIndicator()
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color.Aurora.success)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color.Aurora.error)
        case .pending:
            Image(systemName: "circle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color.Aurora.textMuted)
        }
    }

    /// Border color that reflects tool status
    private var toolBorderColor: Color {
        switch message.status {
        case .running: Color.Aurora.primary
        case .completed: Color.Aurora.border
        case .failed: Color.Aurora.error
        case .pending: Color.Aurora.border
        }
    }
}
