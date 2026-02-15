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
                    ForEach(Array(displayEntries.enumerated()), id: \.element.id) { index, entry in
                        MessageBubble(message: entry.message)
                            .id(entry.id)
                            .opacity(showContent ? 1 : 0)
                            .offset(y: showContent ? 0 : 8)
                            .animation(
                                .auroraSpring.delay(Double(index) * 0.02),
                                value: showContent
                            )
                    }

                    // Transient reasoning bubble — shows live thinking process,
                    // disappears when thinking ends (tool call / assistant text / finish).
                    if let reasoningText = appState.currentReasoningText {
                        TransientReasoningBubble(text: reasoningText)
                            .id("transient-reasoning")
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    // Thinking indicator — only show when genuinely waiting for OpenCode
                    // with no active output (not during assistant text streaming).
                    else if appState.sessionStatus == .running
                                && appState.currentToolName == nil
                                && appState.menuBarState != .responding {
                        ThinkingIndicator()
                            .id("thinking-indicator")
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
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
                scrollToBottom(proxy: proxy, animated: false)
            }
            .onChange(of: appState.messages.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: appState.messages.last?.content) { _, _ in
                // Scroll when message content updates (streaming)
                // Throttled to avoid animation conflicts from rapid delta updates
                scheduleStreamingScroll(proxy: proxy)
            }
            .onChange(of: appState.currentReasoningText) { _, _ in
                // Scroll when reasoning text streams in
                scheduleStreamingScroll(proxy: proxy)
            }
            .onChange(of: appState.sessionStatus) { _, newStatus in
                // Scroll when status changes (e.g., starts running)
                if newStatus == .running {
                    scrollToBottom(proxy: proxy)
                }
            }
        }
    }

    /// Throttle streaming scroll to avoid rapid-fire animation conflicts
    private func scheduleStreamingScroll(proxy: ScrollViewProxy) {
        // Cancel any pending scroll to avoid stacking animations
        streamingScrollTask?.cancel()
        streamingScrollTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            scrollToBottom(proxy: proxy)
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool = true) {
        if animated {
            // Use a non-bouncing animation to prevent the "scroll back up" effect
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo("bottom-anchor", anchor: .bottom)
            }
        } else {
            proxy.scrollTo("bottom-anchor", anchor: .bottom)
        }
    }
}
