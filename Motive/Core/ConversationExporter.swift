//
//  ConversationExporter.swift
//  Motive
//
//  Converts ConversationMessage arrays to exportable Markdown.
//

import Foundation
import AppKit

enum ConversationExporter {
    /// Serializes a conversation to Markdown suitable for export.
    /// - User messages:     `**You:** …`
    /// - Assistant messages:`**Motive:** …`
    /// - Tool messages:     fenced code block labeled with tool type
    /// - System messages:   italicised note
    static func toMarkdown(_ messages: [ConversationMessage]) -> String {
        var lines: [String] = []
        lines.append("# Motive Conversation Export")
        lines.append("")
        lines.append("*Exported \(DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .short))*")
        lines.append("")
        lines.append("---")
        lines.append("")

        for message in messages {
            switch message.type {
            case .user:
                lines.append("**You:** \(message.content)")
                lines.append("")
            case .assistant:
                lines.append("**Motive:** \(message.content)")
                lines.append("")
            case .tool:
                lines.append("```")
                lines.append(message.content)
                lines.append("```")
                lines.append("")
            case .system:
                lines.append("*\(message.content)*")
                lines.append("")
            case .reasoning:
                // Omit transient reasoning from exports
                break
            case .todo:
                lines.append("**Todo:** \(message.content)")
                lines.append("")
            }
        }

        return lines.joined(separator: "\n")
    }

    /// Copies the conversation as Markdown to the system clipboard.
    static func copyToClipboard(_ messages: [ConversationMessage]) {
        let md = toMarkdown(messages)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(md, forType: .string)
    }
}
