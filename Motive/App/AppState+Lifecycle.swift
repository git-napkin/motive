//
//  AppState+Lifecycle.swift
//  Motive
//
//  Created by geezerrrr on 2026/1/19.
//

import AppKit
import Combine
import SwiftData
import SwiftUI

extension AppState {
    func attachModelContext(_ context: ModelContext) {
        modelContext = context
        createCommandBarIfNeeded()
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        // Ensure default project directory exists
        configManager.ensureDefaultProjectDirectory()
        configManager.ensureCurrentProjectInRecents()

        // Preload API keys early to trigger Keychain prompts at startup
        // This avoids scattered prompts during usage
        configManager.preloadAPIKeys()

        // Initialize SkillManager with ConfigManager to enable browser automation skill
        SkillManager.shared.setConfigManager(configManager)

        PermissionManager.shared.startServers()
        observePermissionRequests()
        observeMenuBarState()
        Task {
            await configureBridge()
            await bridge.startIfNeeded()
        }
        ensureStatusBar()
        drawerWindowController = DrawerWindowController(
            rootView: DrawerView()
                .environmentObject(self)
                .environmentObject(configManager)
        )
        // Configure settings window controller
        SettingsWindowController.shared.configure(configManager: configManager, appState: self)
        updateStatusBar()
    }

    func ensureStatusBar() {
        if statusBarController == nil {
            statusBarController = StatusBarController(delegate: self)
            statusBarController?.configure(configManager: configManager)
        }
        updateStatusBar()
    }

    func updateStatusBar() {
        let isWaiting = PermissionManager.shared.isShowingRequest
        let inputType = PermissionManager.shared.currentRequest?.type == .question ? "Question" : "Permission"
        statusBarController?.update(
            state: menuBarState,
            toolName: currentToolName,
            isWaitingForInput: isWaiting,
            inputType: inputType
        )
    }

    private func observeMenuBarState() {
        // Debounce menu bar state updates to avoid "multiple times per frame" warning
        $menuBarState
            .debounce(for: .milliseconds(16), scheduler: RunLoop.main) // ~1 frame at 60fps
            .sink { [weak self] state in
                guard let self else { return }
                let isWaiting = PermissionManager.shared.isShowingRequest
                let inputType = PermissionManager.shared.currentRequest?.type == .question ? "Question" : "Permission"
                self.statusBarController?.update(
                    state: state,
                    toolName: self.currentToolName,
                    isWaitingForInput: isWaiting,
                    inputType: inputType
                )
            }
            .store(in: &cancellables)
    }

    private func observePermissionRequests() {
        PermissionManager.shared.$currentRequest
            .receive(on: RunLoop.main)
            .sink { [weak self] request in
                guard let self else { return }

                if let request = request {
                    // If drawer is visible, let it handle the request
                    // Otherwise show quick confirm panel
                    if self.drawerWindowController?.isVisible == true {
                        // Drawer will handle it via its own UI
                    } else {
                        self.showQuickConfirm(for: request)
                    }
                } else {
                    // Dismiss quick confirm if request is cleared
                    self.quickConfirmController?.dismiss()
                }

                // Update status bar to show waiting state
                self.updateStatusBar()
            }
            .store(in: &cancellables)
    }

    private func showQuickConfirm(for request: PermissionRequest) {
        if quickConfirmController == nil {
            quickConfirmController = QuickConfirmWindowController()
        }

        // Get status bar button frame for positioning
        let anchorFrame = statusBarController?.buttonFrame

        quickConfirmController?.show(
            request: request,
            anchorFrame: anchorFrame,
            onResponse: { [weak self] response in
                // Handle the response
                let permResponse: PermissionResponse
                if request.type == .question {
                    permResponse = PermissionResponse(
                        requestId: request.id,
                        taskId: request.taskId,
                        decision: .allow,
                        selectedOptions: [response],
                        customText: response
                    )
                } else {
                    let approved = response == "approved"
                    permResponse = PermissionResponse(
                        requestId: request.id,
                        taskId: request.taskId,
                        decision: approved ? .allow : .deny
                    )
                }
                PermissionManager.shared.respond(with: permResponse)
                self?.updateStatusBar()
            },
            onCancel: { [weak self] in
                // Cancel/deny the request
                let permResponse = PermissionResponse(
                    requestId: request.id,
                    taskId: request.taskId,
                    decision: .deny
                )
                PermissionManager.shared.respond(with: permResponse)
                self?.updateStatusBar()
            }
        )
    }

    private func createCommandBarIfNeeded() {
        guard commandBarController == nil, let modelContext else { return }
        let rootView = CommandBarView()
            .environmentObject(self)
            .environmentObject(configManager)
            .environment(\.modelContext, modelContext)
        commandBarController = CommandBarWindowController(rootView: rootView)

        // Pre-warm the window to avoid first-show delay
        // Show briefly off-screen then hide
        if let controller = commandBarController {
            let window = controller.getWindow()
            window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
            window.orderFrontRegardless()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                window.orderOut(nil)
            }
        }
    }
}
