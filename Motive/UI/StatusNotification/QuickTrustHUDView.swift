//
//  QuickTrustHUDView.swift
//  Motive
//
//  Floating trust-level switcher that surfaces near the menu bar icon
//  whenever a session is active. Lets users switch trust levels without
//  opening Settings.
//

import SwiftUI

struct QuickTrustHUDView: View {
    let currentLevel: TrustLevel
    let onSelect: (TrustLevel) -> Void

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Color.Aurora.textSecondary)
                .padding(.top, 4)

            VStack(spacing: 2) {
                ForEach(TrustLevel.allCases, id: \.rawValue) { level in
                    Button(action: { onSelect(level) }) {
                        VStack(spacing: 0) {
                            ForEach(Array(level.displayName.enumerated()), id: \.offset) { _, char in
                                Text(String(char))
                                    .font(.system(size: 11, weight: currentLevel == level ? .semibold : .regular))
                                    .foregroundColor(currentLevel == level ? Color.white : Color.Aurora.textSecondary)
                            }
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 3)
                    }
                    .buttonStyle(.plain)
                    .help(level.description)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: AuroraRadius.xl, style: .continuous)
                    .fill(.regularMaterial)
                RoundedRectangle(cornerRadius: AuroraRadius.xl, style: .continuous)
                    .fill(Color.black.opacity(0.15))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.xl, style: .continuous))
    }

    @ViewBuilder
    private var glassBackground: some View {
        RoundedRectangle(cornerRadius: AuroraRadius.xl, style: .continuous)
            .fill(.ultraThinMaterial)
    }

    private func chipColor(_ level: TrustLevel) -> Color {
        switch level {
        case .careful:  Color.Aurora.info
        case .balanced: Color.Aurora.warning
        case .yolo:     Color.Aurora.error
        }
    }
}
