//
//  DrawerConversationContent.swift
//  Motive
//
//  Aurora Design System - Drawer conversation content area
//

import SwiftUI

struct DrawerConversationContent: View {
    @EnvironmentObject private var appState: AppState
    let showContent: Bool
    @Binding var streamingScrollTask: Task<Void, Never>?
    var onEditResend: ((String) -> Void)? = nil

    @State private var lastMessageCount: Int = 0

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: AuroraSpacing.space3) {
                    ForEach(Array(appState.messages.enumerated()), id: \.element.id) { index, message in
                        let processedMessage = shouldDemoteAssistantToProcessThought(index: index, in: appState.messages)
                            ? demotedMessage(from: message)
                            : message
                        MessageBubble(message: processedMessage, onEditResend: onEditResend)
                            .id(message.id)
                    }

                    // Transient reasoning bubble — shows live thinking process
                    if let reasoningText = appState.currentReasoningText {
                        TransientReasoningBubble(text: reasoningText)
                            .id("transient-reasoning")
                    }
                    // Thinking indicator — only show when genuinely waiting for OpenCode
                    else if appState.sessionStatus == .running,
                            appState.currentToolName == nil,
                            appState.menuBarState != .responding
                    {
                        ThinkingIndicator()
                            .id("thinking-indicator")
                    }

                    // Invisible anchor at bottom for reliable scrolling
                    Color.clear
                        .frame(height: 1)
                        .id("bottom-anchor")
                }
                .padding(.horizontal, AuroraSpacing.space4)
                .padding(.vertical, AuroraSpacing.space4)
            }
            .onAppear {
                lastMessageCount = appState.messages.count
                proxy.scrollTo("bottom-anchor", anchor: .bottom)
            }
            .onChange(of: appState.messages.count) { _, newCount in
                guard newCount > lastMessageCount else {
                    lastMessageCount = newCount
                    return
                }
                lastMessageCount = newCount
                // Direct scroll without Task delay to prevent freeze
                proxy.scrollTo("bottom-anchor", anchor: .bottom)
            }
        }
    }

    private func shouldDemoteAssistantToProcessThought(index: Int, in messages: [ConversationMessage]) -> Bool {
        guard messages[index].type == .assistant else { return false }
        var cursor = index + 1
        var hasToolBetween = false
        while cursor < messages.count {
            let next = messages[cursor]
            if next.type == .tool {
                hasToolBetween = true
                cursor += 1
                continue
            }
            if next.type == .assistant {
                return hasToolBetween
            }
            return false
        }
        return false
    }

    private func demotedMessage(from message: ConversationMessage) -> ConversationMessage {
        ConversationMessage(
            id: message.id,
            type: .reasoning,
            content: message.content,
            timestamp: message.timestamp,
            status: .completed
        )
    }
}
