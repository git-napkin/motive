//
//  DrawerChatInput.swift
//  Motive
//
//  Aurora Design System - Drawer chat input area
//

import SwiftUI

struct DrawerChatInput: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var configManager: ConfigManager
    @Binding var inputText: String
    var isInputFocused: FocusState<Bool>.Binding
    let onSubmit: () -> Void
    let onTextChange: (String) -> Void

    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool {
        colorScheme == .dark
    }

    private var isRunning: Bool {
        appState.sessionStatus == .running
    }

    private var hasInput: Bool {
        !inputText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    @ViewBuilder
    private var sendButtonView: some View {
        Button(action: onSubmit) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.Aurora.title1.weight(.medium))
                .foregroundColor(hasInput ? Color.Aurora.microAccent : Color.Aurora.textMuted)
                .opacity(hasInput ? 1 : 0.3)
        }
        .buttonStyle(.plain)
        .disabled(!hasInput)
        .animation(.auroraFast, value: hasInput)
        .accessibilityLabel(L10n.CommandBar.submit)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Project directory + agent mode (compact top meta row)
            HStack(spacing: AuroraSpacing.space2) {
                Image(systemName: "folder")
                    .font(.Aurora.micro.weight(.medium))
                    .foregroundColor(Color.Aurora.textMuted)

                Text(configManager.currentProjectShortPath)
                    .font(.Aurora.micro)
                    .foregroundColor(Color.Aurora.textMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let contextTokens = appState.currentContextTokens {
                    ContextSizeBadge(tokens: contextTokens)
                        .fixedSize(horizontal: true, vertical: true)
                }

                // Agent mode toggle
                AgentModeToggle(
                    currentAgent: configManager.currentAgent,
                    isRunning: isRunning,
                    onChange: { newAgent in
                        configManager.currentAgent = newAgent
                        appState.currentSessionAgent = newAgent
                        configManager.generateOpenCodeConfig()
                        appState.reconfigureBridge()
                    }
                )
                .fixedSize(horizontal: true, vertical: true)
            }
            .padding(.horizontal, AuroraSpacing.space4)
            .padding(.vertical, AuroraSpacing.space2)

            Rectangle()
                .fill(Color.Aurora.glassOverlay.opacity(isDark ? 0.06 : 0.12))
                .frame(height: 0.5)

            HStack(spacing: AuroraSpacing.space3) {
                HStack(alignment: .bottom, spacing: AuroraSpacing.space2) {
                    // Multiline text editor with placeholder overlay
                    ZStack(alignment: .topLeading) {
                        if inputText.isEmpty {
                            Text(L10n.Drawer.messagePlaceholder)
                                .font(.Aurora.body)
                                .foregroundColor(Color.Aurora.textMuted)
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $inputText)
                            .font(.Aurora.body)
                            .foregroundColor(Color.Aurora.textPrimary)
                            .scrollContentBackground(.hidden)
                            .background(.clear)
                            .focused(isInputFocused)
                            .disabled(isRunning)
                            .frame(minHeight: 36, maxHeight: 120)
                            .fixedSize(horizontal: false, vertical: true)
                            .onChange(of: inputText) { _, newValue in
                                onTextChange(newValue)
                            }
                    }

                    // Hidden Cmd+Return submit shortcut
                    Button(action: onSubmit) { EmptyView() }
                        .keyboardShortcut(.return, modifiers: .command)
                        .frame(width: 0, height: 0)
                        .opacity(0)
                        .disabled(!hasInput || isRunning)

                    if isRunning {
                        // Stop button when running
                        Button(action: { appState.interruptSession() }) {
                            Image(systemName: "stop.fill")
                                .font(.Aurora.micro.weight(.bold))
                                .foregroundColor(.white)
                                .frame(width: 28, height: 28)
                                .background(Color.Aurora.error)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.Drawer.stop)
                    } else {
                        // Send button when not running - fades in/out based on input
                        sendButtonView
                    }
                }
                .padding(.horizontal, AuroraSpacing.space4)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            isInputFocused.wrappedValue && !isRunning
                                ? Color.Aurora.microAccentSoft.opacity(isDark ? 0.25 : 0.15)
                                : (isDark ? Color.Aurora.glassOverlay.opacity(0.04) : Color.white.opacity(0.5))
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(
                            isInputFocused.wrappedValue && !isRunning
                                ? Color.Aurora.microAccent.opacity(0.4)
                                : Color.Aurora.glassOverlay.opacity(isDark ? 0.1 : 0.15),
                            lineWidth: 0.5
                        )
                )
                .animation(.auroraFast, value: isInputFocused.wrappedValue)
            }
            .padding(.horizontal, AuroraSpacing.space4)
            .padding(.vertical, AuroraSpacing.space3)
            .background(Color.Aurora.glassOverlay.opacity(isDark ? 0.04 : 0.08))
        }
    }
}