//
//  SettingsView.swift
//  Motive
//
//  Created by geezerrrr on 2026/1/19.
//

import SwiftUI

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .general
    
    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            VStack(spacing: Spacing.xs) {
                ForEach(SettingsTab.allCases) { tab in
                    SettingsTabButton(
                        tab: tab,
                        isSelected: selectedTab == tab
                    ) {
                        withAnimation(.quickSpring) {
                            selectedTab = tab
                        }
                    }
                }
                Spacer()
            }
            .padding(Spacing.md)
            .frame(width: 180)
            .background(Color.black.opacity(0.03))
            
            // Content
            VStack(spacing: 0) {
                selectedTab.contentView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 640, height: 440)
    }
}

// MARK: - Settings Tab

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case model
    case advanced
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .general: return "General"
        case .model: return "Model"
        case .advanced: return "Advanced"
        }
    }
    
    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .model: return "cpu"
        case .advanced: return "wrench.and.screwdriver"
        }
    }
    
    @ViewBuilder
    var contentView: some View {
        switch self {
        case .general:
            GeneralSettingsView()
        case .model:
            ModelConfigView()
        case .advanced:
            AdvancedSettingsView()
        }
    }
}

// MARK: - Tab Button

struct SettingsTabButton: View {
    let tab: SettingsTab
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: Spacing.sm) {
                Image(systemName: tab.icon)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? Color.Velvet.primary : Color.Velvet.textSecondary)
                    .frame(width: 20)
                
                Text(tab.title)
                    .font(.Velvet.bodyMedium)
                    .foregroundColor(isSelected ? Color.Velvet.textPrimary : Color.Velvet.textSecondary)
                
                Spacer()
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: CornerRadius.medium, style: .continuous)
                    .fill(isSelected ? Color.Velvet.primary.opacity(0.1) : (isHovering ? Color.black.opacity(0.04) : Color.clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

// MARK: - Settings Section

struct SettingsSection<Content: View>: View {
    let title: String
    var icon: String? = nil
    let content: Content
    
    init(title: String, icon: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            SectionHeader(title: title, icon: icon)
            
            VStack(spacing: Spacing.sm) {
                content
            }
            .padding(Spacing.lg)
            .background(Color.black.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.medium, style: .continuous))
        }
    }
}

// MARK: - Settings Row

struct SettingsRow<Content: View>: View {
    let label: String
    var description: String? = nil
    let content: Content
    
    init(label: String, description: String? = nil, @ViewBuilder content: () -> Content) {
        self.label = label
        self.description = description
        self.content = content()
    }
    
    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.Velvet.body)
                    .foregroundColor(Color.Velvet.textPrimary)
                
                if let description {
                    Text(description)
                        .font(.Velvet.caption)
                        .foregroundColor(Color.Velvet.textMuted)
                }
            }
            
            Spacer()
            
            content
        }
    }
}
