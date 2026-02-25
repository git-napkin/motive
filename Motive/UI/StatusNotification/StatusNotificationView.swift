//
//  StatusNotificationView.swift
//  Motive
//
//  Aurora Design System - Status Notification Popup
//

import SwiftUI

enum StatusNotificationType {
    case success
    case error

    var icon: String {
        switch self {
        case .success: "checkmark.circle.fill"
        case .error: "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .success: Color.Aurora.success
        case .error: Color.Aurora.error
        }
    }

    var gradientColors: [Color] {
        [color, color.opacity(0.75)]
    }

    var title: String {
        switch self {
        case .success: L10n.Drawer.completed
        case .error: L10n.Drawer.failed
        }
    }
}

struct StatusNotificationView: View {
    let type: StatusNotificationType
    let onDismiss: () -> Void
    var glassMode: ConfigManager.LiquidGlassMode = .clear

    @Environment(\.colorScheme) private var colorScheme
    @State private var showContent = false

    private var isDark: Bool {
        colorScheme == .dark
    }

    var body: some View {
        HStack(spacing: AuroraSpacing.space4) {
            // High-end icon layout
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: type.gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ).opacity(isDark ? 0.2 : 0.15)
                    )
                    .frame(width: 32, height: 32)

                Image(systemName: type.icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: type.gradientColors,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(type.title)
                    .font(.Aurora.bodySmall.weight(.bold))
                    .foregroundColor(Color.Aurora.textPrimary)

                Text(type == .success ? L10n.Drawer.taskFinished : L10n.Drawer.checkLogs)
                    .font(.Aurora.micro)
                    .foregroundColor(Color.Aurora.textMuted)
            }
        }
        .padding(.leading, AuroraSpacing.space4)
        .padding(.trailing, AuroraSpacing.space6)
        .padding(.vertical, AuroraSpacing.space3)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: AuroraRadius.xl, style: .continuous)
                    .fill(.regularMaterial)
                RoundedRectangle(cornerRadius: AuroraRadius.xl, style: .continuous)
                    .fill(Color.black.opacity(0.15))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.xl, style: .continuous))
        .scaleEffect(showContent ? 1.0 : 0.95)
        .opacity(showContent ? 1.0 : 0)
        .onAppear {
            withAnimation(.auroraSpring) {
                showContent = true
            }
        }
        .onTapGesture { onDismiss() }
    }
}
