//
//  RemoteCloudKitManager.swift
//  MotiveRemote
//
//  CloudKit manager for iOS - sends commands and receives status updates
//

import CloudKit
import Combine
import Foundation

final class RemoteCloudKitManager: ObservableObject {
    
    @Published var isConnected: Bool = false
    @Published var isSending: Bool = false
    @Published var activeCommand: RemoteCommand?
    @Published var recentCommands: [RemoteCommand] = []
    @Published var pendingPermissionRequest: RemotePermissionRequest?
    
    private var refreshTimer: Timer?
    
    init() {
        checkConnection()
        startRefreshTimer()
    }
    
    deinit {
        refreshTimer?.invalidate()
    }
    
    // MARK: - Public Methods
    
    /// Send a command to Mac via CloudKit
    @MainActor
    func sendCommand(_ instruction: String, targetDeviceId: String? = nil) async throws -> RemoteCommand {
        isSending = true
        defer { isSending = false }
        
        let record = RemoteCommand.createRecord(instruction: instruction, targetDeviceId: targetDeviceId)
        
        let savedRecord = try await motivePrivateDatabase.save(record)
        let command = RemoteCommand(record: savedRecord)
        
        activeCommand = command
        
        // Add to recent commands
        recentCommands.insert(command, at: 0)
        if recentCommands.count > 20 {
            recentCommands = Array(recentCommands.prefix(20))
        }
        
        return command
    }
    
    /// Static method for App Intents (which don't have access to the shared instance)
    static func sendCommandFromIntent(_ instruction: String) async throws -> RemoteCommand {
        let record = RemoteCommand.createRecord(instruction: instruction)
        let savedRecord = try await motivePrivateDatabase.save(record)
        return RemoteCommand(record: savedRecord)
    }
    
    /// Load recent commands from CloudKit
    @MainActor
    func loadRecentCommands() async {
        let predicate = NSPredicate(value: true)
        let query = CKQuery(recordType: RemoteCommand.recordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        
        do {
            let (matchResults, _) = try await motivePrivateDatabase.records(matching: query, resultsLimit: 20)
            
            var commands: [RemoteCommand] = []
            for (_, result) in matchResults {
                if case .success(let record) = result {
                    commands.append(RemoteCommand(record: record))
                }
            }
            
            // Sort by date (newest first)
            recentCommands = commands.sorted { $0.createdAt > $1.createdAt }
            
            // Update active command if there's one that's pending or running
            activeCommand = recentCommands.first { $0.status == .pending || $0.status == .running }
            
            isConnected = true
        } catch {
            print("Failed to load recent commands: \(error)")
            isConnected = false
        }
    }
    
    /// Refresh the active command status
    @MainActor
    func refreshActiveCommand() async {
        guard let command = activeCommand else { return }
        
        let recordID = CKRecord.ID(recordName: command.id)
        
        do {
            let record = try await motivePrivateDatabase.record(for: recordID)
            let updatedCommand = RemoteCommand(record: record)
            activeCommand = updatedCommand
            
            // Update in recent commands list too
            if let index = recentCommands.firstIndex(where: { $0.id == updatedCommand.id }) {
                recentCommands[index] = updatedCommand
            }
            
            // Clear active command if it's completed or failed
            if updatedCommand.status == .completed || updatedCommand.status == .failed {
                // Keep it visible for a few seconds
                Task {
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    if activeCommand?.id == updatedCommand.id {
                        activeCommand = nil
                    }
                }
            }
            
            isConnected = true
        } catch {
            print("Failed to refresh command: \(error)")
        }
    }
    
    /// Check for pending permission requests
    @MainActor
    func checkForPermissionRequests() async {
        guard let command = activeCommand else { return }
        
        // CloudKit doesn't support "== nil", use commandId only and filter in code
        let predicate = NSPredicate(format: "commandId == %@", command.id)
        let query = CKQuery(recordType: RemotePermissionRequest.recordType, predicate: predicate)
        
        do {
            let (matchResults, _) = try await motivePrivateDatabase.records(matching: query, resultsLimit: 10)
            
            for (_, result) in matchResults {
                if case .success(let record) = result {
                    let request = RemotePermissionRequest(record: record)
                    // Filter: only show requests without a response
                    if request.response == nil {
                        pendingPermissionRequest = request
                        return
                    }
                }
            }
            
            pendingPermissionRequest = nil
        } catch {
            print("Failed to check permission requests: \(error)")
        }
    }
    
    /// Respond to a permission request
    @MainActor
    func respondToPermissionRequest(requestId: String, response: String) async {
        let recordID = CKRecord.ID(recordName: requestId)
        
        do {
            let record = try await motivePrivateDatabase.record(for: recordID)
            record[RemotePermissionRequest.FieldKey.response.rawValue] = response
            record[RemotePermissionRequest.FieldKey.respondedAt.rawValue] = Date()
            
            try await motivePrivateDatabase.save(record)
            pendingPermissionRequest = nil
        } catch {
            print("Failed to respond to permission request: \(error)")
        }
    }
    
    /// Clear command history (local only, doesn't delete from CloudKit)
    @MainActor
    func clearHistory() async {
        recentCommands = []
        activeCommand = nil
    }
    
    // MARK: - Private Methods
    
    private func checkConnection() {
        CKContainer(identifier: motiveCloudKitContainerID).accountStatus { [weak self] status, error in
            Task { @MainActor in
                self?.isConnected = (status == .available)
            }
        }
    }
    
    private func startRefreshTimer() {
        // Refresh every 3 seconds when there's an active command
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.activeCommand != nil else { return }
                await self.refreshActiveCommand()
                await self.checkForPermissionRequests()
            }
        }
    }
}
