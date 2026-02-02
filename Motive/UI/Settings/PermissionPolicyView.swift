//
//  PermissionPolicyView.swift
//  Motive
//
//  Compact permission policy settings
//

import SwiftUI

struct PermissionPolicyView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var operationPolicies: [FileOperation: PermissionPolicy] = [:]
    
    private var isDark: Bool { colorScheme == .dark }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // File Operations Section
            SettingSection(L10n.Settings.fileOperations) {
                ForEach(Array(FileOperation.allCases.enumerated()), id: \.element) { index, operation in
                    SettingRow(
                        operation.localizedName,
                        showDivider: index < FileOperation.allCases.count - 1
                    ) {
                        HStack(spacing: 10) {
                            // Risk indicator
                            Circle()
                                .fill(riskColor(for: operation.riskLevel))
                                .frame(width: 8, height: 8)
                            
                            // Policy picker
                            Picker("", selection: Binding(
                                get: { operationPolicies[operation] ?? .alwaysAsk },
                                set: { newPolicy in
                                    operationPolicies[operation] = newPolicy
                                    FileOperationPolicy.shared.setDefaultPolicy(newPolicy, for: operation)
                                }
                            )) {
                                ForEach(PermissionPolicy.allCases, id: \.self) { policy in
                                    Text(policy.localizedName).tag(policy)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 130)
                        }
                    }
                }
            }
            
            // Risk Legend - compact inline display
            riskLegend
            
            Spacer()
            
            // Reset Button
            HStack {
                Spacer()
                Button(action: {
                    FileOperationPolicy.shared.resetToDefaults()
                    loadCurrentPolicies()
                }) {
                    Text(L10n.Settings.resetToDefaults)
                        .font(.system(size: 12))
                        .foregroundColor(Color.Aurora.textMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear {
            loadCurrentPolicies()
        }
    }
    
    private var riskLegend: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.Settings.riskLevels)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color.Aurora.textMuted)
                .textCase(.uppercase)
                .tracking(0.5)
                .padding(.leading, 4)
            
            HStack(spacing: 20) {
                legendItem(color: .green, label: L10n.Settings.riskLow)
                legendItem(color: .yellow, label: L10n.Settings.riskMedium)
                legendItem(color: .orange, label: L10n.Settings.riskHigh)
                legendItem(color: .red, label: L10n.Settings.riskCritical)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.Aurora.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.Aurora.border, lineWidth: 1)
            )
        }
    }
    
    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(Color.Aurora.textSecondary)
        }
    }
    
    private func loadCurrentPolicies() {
        for operation in FileOperation.allCases {
            let policy = FileOperationPolicy.shared.policy(for: operation, path: "")
            operationPolicies[operation] = policy
        }
    }
    
    private func riskColor(for level: RiskLevel) -> Color {
        switch level {
        case .low: return .green
        case .medium: return .yellow
        case .high: return .orange
        case .critical: return .red
        }
    }
}

// MARK: - PermissionPolicy Extensions

extension PermissionPolicy: CaseIterable {
    static var allCases: [PermissionPolicy] {
        [.alwaysAllow, .alwaysAsk, .askOnce, .alwaysDeny]
    }
}
