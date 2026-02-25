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
    @State private var lastScrollTask: Task<Void, Never>?

    private struct DisplayEntry: Identifiable {
        let id: UUID
        let message: ConversationMessage
    }

    private var displayEntries: [DisplayEntry] {
        let allMessages = appState.messages
        return allMessages.enumerated().map { index, message in
            if shouldDemoteAssistantToProcessThought(index: index, in: allMessages) {
                let synthetic = ConversationMessage(
                    id: message.id,
                    type: .reasoning,
                    content: message.content,
                    timestamp: message.timestamp,
                    status: .completed
                )
                return DisplayEntry(id: message.id, message: synthetic)
            }
            return DisplayEntry(id: message.id, message: message)
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

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: AuroraSpacing.space3) {
                    ForEach(displayEntries, id: \.id) { entry in
                        MessageBubble(message: entry.message, onEditResend: onEditResend)
                            .id(entry.id)
                    }

                    // Transient reasoning bubble — shows live thinking process,
                    // disappears when thinking ends (tool call / assistant text / finish).
                    if let reasoningText = appState.currentReasoningText {
                        TransientReasoningBubble(text: reasoningText)
                            .id("transient-reasoning")
                    }
                    // Thinking indicator — only show when genuinely waiting for OpenCode
                    // with no active output (not during assistant text streaming).
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

                // Cancel any pending scroll task and create a new throttled one
                lastScrollTask?.cancel()
                lastScrollTask = Task { @MainActor in
                    // Throttle: wait 100ms before scrolling to batch rapid updates
                    try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        proxy.scrollTo("bottom-anchor", anchor: .bottom)
                    }
                }
            }
        }
    }
}
