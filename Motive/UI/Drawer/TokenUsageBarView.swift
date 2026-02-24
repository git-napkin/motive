//
//  TokenUsageBarView.swift
//  Motive
//
//  Aurora Design System — compact context-window progress bar + session cost strip.
//  Appears beneath the DrawerHeader when token data is available.
//

import SwiftUI

// MARK: - TokenUsageBarView

/// A thin strip that visualises context-window fill and session cost.
/// Shown only when `currentContextTokens` is non-nil.
struct TokenUsageBarView: View {
    let contextTokens: Int
    let outputTokens: Int
    let sessionCost: Double

    /// Model context-window size. 200k for Claude 3.x / 4.x.
    var contextLimit: Int = 200_000

    @Environment(\.colorScheme) private var colorScheme
    private var isDark: Bool { colorScheme == .dark }

    // Fill fraction clamped to [0, 1]
    private var fill: Double {
        min(Double(contextTokens) / Double(contextLimit), 1.0)
    }

    // Color transitions: green → amber → red
    private var barColor: Color {
        switch fill {
        case ..<0.6:  Color.Aurora.success
        case ..<0.85: Color(hue: 0.10, saturation: 0.85, brightness: 0.85)
        default:      Color.Aurora.error
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Thin progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Track
                    Rectangle()
                        .fill(Color.Aurora.glassOverlay.opacity(isDark ? 0.08 : 0.06))

                    // Fill
                    Rectangle()
                        .fill(barColor.opacity(0.72))
                        .frame(width: geo.size.width * fill)
                        .animation(.auroraNormal, value: fill)
                }
            }
            .frame(height: 2)

            // Stats row — context tokens left, output tokens, cost
            HStack(spacing: 10) {
                // Context fill label
                HStack(spacing: 3) {
                    Image(systemName: "doc.badge.clock")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(barColor.opacity(0.85))
                    Text("\(TokenUsageFormatter.formatTokens(contextTokens)) ctx")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(barColor.opacity(isDark ? 0.80 : 0.72))
                }

                // Output tokens
                if outputTokens > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.up.circle")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(Color.Aurora.textMuted)
                        Text("\(TokenUsageFormatter.formatTokens(outputTokens)) out")
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .foregroundColor(Color.Aurora.textMuted)
                    }
                }

                Spacer()

                // Cost
                if sessionCost > 0 {
                    Text(TokenUsageFormatter.formatCost(sessionCost))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(Color.Aurora.textMuted)
                        .help("Session cost")
                }

                // % of context window
                Text(String(format: "%.0f%%", fill * 100))
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundColor(barColor.opacity(isDark ? 0.65 : 0.55))
                    .help("Context window used")
            }
            .padding(.horizontal, AuroraSpacing.space4)
            .padding(.top, 4)
            .padding(.bottom, 5)
        }
        .background(Color.Aurora.glassOverlay.opacity(isDark ? 0.025 : 0.015))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}
