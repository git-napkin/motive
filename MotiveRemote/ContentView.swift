//
//  ContentView.swift
//  MotiveRemote
//
//  Clean & Practical iOS Remote Control
//

import SwiftUI

// MARK: - Main View

struct ContentView: View {
    @EnvironmentObject var cloudKitManager: RemoteCloudKitManager
    @State private var inputText = ""
    @State private var showingPermission = false
    @FocusState private var isInputFocused: Bool
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Status Card
                    StatusCard(
                        isConnected: cloudKitManager.isConnected,
                        activeCommand: cloudKitManager.activeCommand
                    )
                    
                    // Input Card
                    InputCard(
                        text: $inputText,
                        isFocused: $isInputFocused,
                        isLoading: cloudKitManager.isSending,
                        onSend: sendCommand
                    )
                    
                    // Quick Actions
                    QuickActionsCard(onAction: sendQuickAction)
                    
                    // History
                    if !cloudKitManager.recentCommands.isEmpty {
                        HistoryCard(
                            commands: cloudKitManager.recentCommands,
                            onClear: { Task { await cloudKitManager.clearHistory() } }
                        )
                    }
                }
                .padding(16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Motive Remote")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable {
                await cloudKitManager.refreshActiveCommand()
                await cloudKitManager.loadRecentCommands()
            }
        }
        .onAppear {
            Task { await cloudKitManager.loadRecentCommands() }
        }
        .sheet(isPresented: $showingPermission) {
            if let request = cloudKitManager.pendingPermissionRequest {
                PermissionSheet(request: request) { response in
                    Task {
                        await cloudKitManager.respondToPermissionRequest(
                            requestId: request.id,
                            response: response
                        )
                    }
                    showingPermission = false
                }
            }
        }
        .onChange(of: cloudKitManager.pendingPermissionRequest) { _, new in
            showingPermission = new != nil
        }
    }
    
    private func sendCommand() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        Task {
            try? await cloudKitManager.sendCommand(text)
            inputText = ""
            isInputFocused = false
        }
    }
    
    private func sendQuickAction(_ prompt: String) {
        Task { try? await cloudKitManager.sendCommand(prompt) }
    }
}

// MARK: - Status Card

struct StatusCard: View {
    let isConnected: Bool
    let activeCommand: RemoteCommand?
    
    var body: some View {
        VStack(spacing: 0) {
            // Connection header
            HStack {
                Circle()
                    .fill(isConnected ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                
                Text(isConnected ? "Connected to Mac" : "Connecting...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                if let command = activeCommand, command.status == .running {
                    LiveBadge()
                }
            }
            .padding(16)
            
            Divider()
            
            // Status content
            if let command = activeCommand {
                ActiveCommandContent(command: command)
            } else {
                IdleContent()
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct LiveBadge: View {
    @State private var isOn = true
    
    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color.red)
                .frame(width: 6, height: 6)
                .opacity(isOn ? 1 : 0.3)
            
            Text("LIVE")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.red)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.6).repeatForever()) {
                isOn.toggle()
            }
        }
    }
}

struct IdleContent: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 32))
                .foregroundStyle(.blue)
            
            Text("Ready for tasks")
                .font(.headline)
            
            Text("Send a command to your Mac")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}

struct ActiveCommandContent: View {
    let command: RemoteCommand
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Status badge
            HStack {
                Image(systemName: statusIcon)
                    .font(.system(size: 12, weight: .semibold))
                Text(statusText)
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(statusColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(statusColor.opacity(0.12))
            .clipShape(Capsule())
            
            // Instruction
            Text(command.instruction)
                .font(.body)
                .fontWeight(.medium)
            
            // Tool name (when running)
            if command.status == .running, let tool = command.toolName {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text(tool)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            
            // Result
            if let result = command.result, !result.isEmpty {
                Text(result)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            
            // Error
            if let error = command.errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                    Text(error)
                        .font(.subheadline)
                }
                .foregroundStyle(.red)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }
    
    private var statusIcon: String {
        switch command.status {
        case .pending: return "clock"
        case .running: return "bolt.fill"
        case .completed: return "checkmark"
        case .failed: return "xmark"
        case .cancelled: return "stop.fill"
        }
    }
    
    private var statusText: String {
        switch command.status {
        case .pending: return "Pending"
        case .running: return "Running"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }
    
    private var statusColor: Color {
        switch command.status {
        case .pending: return .orange
        case .running: return .blue
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .gray
        }
    }
}

// MARK: - Input Card

struct InputCard: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let isLoading: Bool
    let onSend: () -> Void
    
    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isLoading
    }
    
    var body: some View {
        VStack(spacing: 12) {
            // Input field
            HStack {
                TextField("Ask Motive...", text: $text, axis: .vertical)
                    .lineLimit(1...4)
                    .focused(isFocused)
                    .submitLabel(.send)
                    .onSubmit { if canSend { onSend() } }
                
                if !text.isEmpty && !isLoading {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(14)
            .background(Color(.tertiarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            
            // Send button
            Button(action: onSend) {
                HStack {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Send")
                            .fontWeight(.semibold)
                        Image(systemName: "paperplane.fill")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(canSend ? Color.blue : Color.gray.opacity(0.3))
                .foregroundStyle(canSend ? .white : .secondary)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .disabled(!canSend)
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Quick Actions Card

struct QuickActionsCard: View {
    let onAction: (String) -> Void
    
    private let actions: [(icon: String, title: String, color: Color, prompt: String)] = [
        ("arrow.triangle.2.circlepath", "Refactor", .purple, "Refactor the current file"),
        ("checkmark.shield.fill", "Test", .green, "Run tests"),
        ("arrow.up.doc.fill", "Commit", .orange, "Commit changes"),
        ("eye.fill", "Review", .blue, "Review code")
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Actions")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(actions, id: \.title) { action in
                    QuickActionButton(
                        icon: action.icon,
                        title: action.title,
                        color: action.color,
                        action: { onAction(action.prompt) }
                    )
                }
            }
        }
    }
}

struct QuickActionButton: View {
    let icon: String
    let title: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(color)
                    .frame(width: 32, height: 32)
                    .background(color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - History Card

struct HistoryCard: View {
    let commands: [RemoteCommand]
    let onClear: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("History")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Button(action: onClear) {
                    Image(systemName: "trash")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 4)
            
            VStack(spacing: 0) {
                ForEach(Array(commands.prefix(5).enumerated()), id: \.element.id) { index, command in
                    NavigationLink(destination: CommandDetailView(command: command)) {
                        HistoryRow(command: command)
                    }
                    .buttonStyle(.plain)
                    
                    if index < min(4, commands.count - 1) {
                        Divider()
                            .padding(.leading, 48)
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

struct HistoryRow: View {
    let command: RemoteCommand
    
    var body: some View {
        HStack(spacing: 12) {
            // Status dot
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .padding(.leading, 4)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(command.instruction)
                    .font(.subheadline)
                    .lineLimit(1)
                
                HStack(spacing: 4) {
                    if let result = command.result, !result.isEmpty {
                        Text(result)
                            .lineLimit(1)
                    } else {
                        Text(command.createdAt, style: .relative)
                    }
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.quaternary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
    
    private var statusColor: Color {
        switch command.status {
        case .pending: return .orange
        case .running: return .blue
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .gray
        }
    }
}

// MARK: - Permission Sheet

struct PermissionSheet: View {
    let request: RemotePermissionRequest
    let onRespond: (String) -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.blue)
                
                Text(request.question)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                VStack(spacing: 10) {
                    ForEach(request.options, id: \.self) { option in
                        Button {
                            onRespond(option)
                        } label: {
                            Text(option)
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.blue)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }
                .padding(.horizontal, 24)
                
                Spacer()
            }
            .navigationTitle("Question")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Dismiss") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Command Detail View

struct CommandDetailView: View {
    let command: RemoteCommand
    
    var body: some View {
        List {
            Section {
                HStack {
                    Text("Status")
                    Spacer()
                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 8, height: 8)
                        Text(statusText)
                            .foregroundStyle(.secondary)
                    }
                }
                
                HStack {
                    Text("Time")
                    Spacer()
                    Text(command.createdAt, format: .dateTime)
                        .foregroundStyle(.secondary)
                }
            }
            
            Section("Instruction") {
                Text(command.instruction)
            }
            
            if let tool = command.toolName {
                Section("Last Tool") {
                    Text(tool)
                        .foregroundStyle(.secondary)
                }
            }
            
            if let result = command.result, !result.isEmpty {
                Section("Result") {
                    Text(result)
                        .textSelection(.enabled)
                }
            }
            
            if let error = command.errorMessage, !error.isEmpty {
                Section("Error") {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Details")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private var statusText: String {
        switch command.status {
        case .pending: return "Pending"
        case .running: return "Running"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }
    
    private var statusColor: Color {
        switch command.status {
        case .pending: return .orange
        case .running: return .blue
        case .completed: return .green
        case .failed: return .red
        case .cancelled: return .gray
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environmentObject(RemoteCloudKitManager())
}
