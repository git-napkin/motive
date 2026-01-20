//
//  CommandBarView.swift
//  Motive
//
//  Created by geezerrrr on 2026/1/19.
//

import AppKit
import SwiftUI

struct CommandBarRootView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var appState: AppState
    @State private var didAttachContext = false

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .onAppear {
                guard !didAttachContext else { return }
                didAttachContext = true
                appState.attachModelContext(modelContext)
            }
    }
}

struct CommandBarView: View {
    @EnvironmentObject private var configManager: ConfigManager
    @EnvironmentObject private var appState: AppState
    @Environment(\.openSettings) private var openSettings
    @Environment(\.colorScheme) private var colorScheme

    @State private var inputText: String = ""
    @State private var isHovering: Bool = false
    @FocusState private var isFocused: Bool
    
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        VStack(spacing: 0) {
            // Main input area
            inputArea
            
            // Subtle divider
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: isDark
                            ? [Color.white.opacity(0.0), Color.white.opacity(0.08), Color.white.opacity(0.0)]
                            : [Color.black.opacity(0.0), Color.black.opacity(0.08), Color.black.opacity(0.0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
                .padding(.horizontal, 24)
            
            // Footer
            footerArea
        }
        .frame(width: 640)
        .background(commandBarBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: isDark
                            ? [Color.white.opacity(0.2), Color.white.opacity(0.05), Color.white.opacity(0.1)]
                            : [Color.black.opacity(0.1), Color.black.opacity(0.03), Color.black.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(isDark ? 0.4 : 0.15), radius: 60, y: 30)
        .shadow(color: .black.opacity(isDark ? 0.3 : 0.1), radius: 20, y: 10)
        .onExitCommand {
            appState.hideCommandBar()
        }
    }
    
    // MARK: - Input Area
    
    private var inputArea: some View {
        HStack(spacing: 14) {
            // Logo icon with subtle glow
            ZStack {
                // Subtle glow
                Image(systemName: "sparkle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Color.Velvet.primary)
                    .blur(radius: 6)
                    .opacity(0.5)
                
                // Icon
                Image(systemName: "sparkle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.Velvet.primary, Color.Velvet.primaryDark],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .frame(width: 24)
            
            // Input field
            TextField("", text: $inputText, prompt: Text("What should I do?")
                .foregroundColor(isDark ? Color.white.opacity(0.35) : Color.black.opacity(0.35)))
                .textFieldStyle(.plain)
                .font(.system(size: 18, weight: .regular))
                .foregroundColor(Color.Velvet.textPrimary)
                .focused($isFocused)
                .onSubmit(submit)
            
            // Action button
            actionButton
        }
        .frame(height: 64)
        .padding(.horizontal, 20)
    }
    
    // MARK: - Action Button
    
    @ViewBuilder
    private var actionButton: some View {
        if !configManager.hasAPIKey {
            ActionPill(
                icon: "gear",
                label: "Setup",
                style: .warning
            ) {
                openSettings()
            }
        } else if let error = appState.lastErrorMessage {
            ActionPill(
                icon: "exclamationmark.triangle.fill",
                label: "Error",
                style: .error
            ) {
                openSettings()
            }
            .help(error)
        } else if !inputText.isEmpty {
            ActionPill(
                icon: "arrow.right",
                label: "Run",
                style: .primary
            ) {
                submit()
            }
        } else {
            // Empty placeholder for consistent layout
            Color.clear
                .frame(width: 70, height: 32)
        }
    }
    
    // MARK: - Footer Area
    
    private var footerArea: some View {
        HStack(spacing: 0) {
            // Status indicator
            if appState.menuBarState != .idle {
                HStack(spacing: 8) {
                    PulsingDot(color: appState.menuBarState == .reasoning ? .purple : .green)
                    
                    Text(appState.menuBarState.displayText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color.Velvet.textSecondary)
                }
                .padding(.leading, 4)
            }
            
            Spacer()
            
            // Keyboard shortcuts
            HStack(spacing: 16) {
                ShortcutBadge(keys: ["↵"], label: "Run", isDark: isDark)
                ShortcutBadge(keys: ["esc"], label: "Close", isDark: isDark)
                ShortcutBadge(keys: ["⌘", ","], label: "Settings", isDark: isDark)
            }
        }
        .frame(height: 38)
        .padding(.horizontal, 20)
    }
    
    // MARK: - Background
    
    private var commandBarBackground: some View {
        ZStack {
            // Blur effect
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow, state: .active)
            
            // Base overlay
            if isDark {
                Color(hex: "0D0D0F").opacity(0.85)
            } else {
                Color.white.opacity(0.92)
            }
            
            // Subtle gradient overlay
            LinearGradient(
                colors: isDark
                    ? [Color.white.opacity(0.04), Color.clear, Color.black.opacity(0.1)]
                    : [Color.white.opacity(0.6), Color.clear, Color.black.opacity(0.02)],
                startPoint: .top,
                endPoint: .bottom
            )
            
            // Inner glow at top
            VStack {
                LinearGradient(
                    colors: isDark
                        ? [Color.white.opacity(0.06), Color.clear]
                        : [Color.white.opacity(0.8), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 80)
                
                Spacer()
            }
        }
    }
    
    private func submit() {
        let text = inputText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        inputText = ""
        appState.submitIntent(text)
    }
}

// MARK: - Action Pill

private struct ActionPill: View {
    let icon: String
    let label: String
    let style: Style
    let action: () -> Void
    
    @State private var isPressed = false
    
    enum Style {
        case primary, warning, error
        
        var backgroundColor: Color {
            switch self {
            case .primary: return Color.Velvet.primary
            case .warning: return Color.orange
            case .error: return Color.red
            }
        }
        
        var foregroundColor: Color {
            return .white
        }
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundColor(style.foregroundColor)
            .padding(.horizontal, 14)
            .frame(height: 32)
            .background(
                ZStack {
                    // Base color
                    style.backgroundColor
                    
                    // Top highlight
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.2),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .center
                    )
                }
            )
            .clipShape(Capsule())
            .shadow(color: style.backgroundColor.opacity(0.4), radius: 8, y: 4)
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

// MARK: - Scale Button Style

private struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Shortcut Badge

private struct ShortcutBadge: View {
    let keys: [String]
    let label: String
    var isDark: Bool = true
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(keys, id: \.self) { key in
                Text(key)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundColor(isDark ? Color.white.opacity(0.5) : Color.black.opacity(0.5))
                    .frame(minWidth: 16)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.1), lineWidth: 0.5)
                    )
            }
            
            Text(label)
                .font(.system(size: 10, weight: .regular))
                .foregroundColor(isDark ? Color.white.opacity(0.35) : Color.black.opacity(0.4))
        }
    }
}

// MARK: - Pulsing Dot

private struct PulsingDot: View {
    let color: Color
    @State private var isPulsing = false
    
    var body: some View {
        ZStack {
            // Outer glow
            Circle()
                .fill(color.opacity(0.3))
                .frame(width: 10, height: 10)
                .scaleEffect(isPulsing ? 1.5 : 1)
                .opacity(isPulsing ? 0 : 0.5)
            
            // Inner dot
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: false)) {
                isPulsing = true
            }
        }
    }
}

// MARK: - Menu Bar State Display Text

extension AppState.MenuBarState {
    var displayText: String {
        switch self {
        case .idle: return "Ready"
        case .reasoning: return "Thinking…"
        case .executing: return "Running…"
        }
    }
}
