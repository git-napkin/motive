//
//  CommandBarMessageRow.swift
//  Motive
//
//  Compact message row for inline display in command bar
//

import SwiftUI

struct CommandBarMessageRow: View {
    let message: ConversationMessage
    let isLatest: Bool

    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Role icon
            Image(systemName: roleIcon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(roleColor)
                .frame(width: 20)

            // Message content
            VStack(alignment: .leading, spacing: 2) {
                Text(roleLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color.Aurora.textMuted)

                let content = message.content
                if !content.isEmpty {
                    Text(content)
                        .font(.system(size: 12))
                        .foregroundColor(Color.Aurora.textPrimary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let toolName = message.toolName, message.type == .tool {
                    HStack(spacing: 4) {
                        Image(systemName: "wrench.and.screwdriver")
                            .font(.system(size: 9))
                        Text(toolName)
                            .font(.system(size: 10))
                    }
                    .foregroundColor(Color.Aurora.textMuted)
                }
            }

            Spacer()

            // Loading indicator for latest message
            if isLatest && message.status == .running {
                ProgressView()
                    .scaleEffect(0.5)
            }
        }
        .padding(.vertical, 4)
    }

    private var roleIcon: String {
        switch message.type {
        case .user:
            return "person.fill"
        case .assistant:
            return "sparkles"
        case .tool:
            return "wrench.and.screwdriver"
        case .system:
            return "gear"
        case .todo:
            return "checklist"
        case .reasoning:
            return "brain"
        @unknown default:
            return "questionmark.circle"
        }
    }

    private var roleColor: Color {
        switch message.type {
        case .user:
            return Color.blue
        case .assistant:
            return Color.purple
        case .tool:
            return Color.orange
        case .system:
            return Color.gray
        case .todo:
            return Color.green
        case .reasoning:
            return Color.gray
        @unknown default:
            return Color.gray
        }
    }

    private var roleLabel: String {
        switch message.type {
        case .user:
            return "You"
        case .assistant:
            return "Motive"
        case .tool:
            return "Tool"
        case .system:
            return "System"
        case .todo:
            return "Todo"
        case .reasoning:
            return "Thinking"
        @unknown default:
            return "Unknown"
        }
    }
}
