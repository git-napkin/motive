//
//  StatusBarController.swift
//  Motive
//
//  Created by geezerrrr on 2026/1/19.
//

import AppKit

@MainActor
protocol StatusBarControllerDelegate: AnyObject {
    func statusBarDidRequestToggleDrawer()
    func statusBarDidRequestSettings()
    func statusBarDidRequestQuit()
    func statusBarDidRequestCommandBar()
}

/// Extended status for status bar display
enum StatusBarDisplayState {
    case idle
    case thinking
    case executing(tool: String?)
    case waitingForInput(type: String)  // "Permission", "Question", etc.
    case completed
    case error
    
    var icon: String {
        switch self {
        case .idle: return "sparkle"
        case .thinking: return "brain.head.profile"
        case .executing: return "bolt.fill"
        case .waitingForInput: return "hand.raised.fill"
        case .completed: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }
    
    var text: String {
        switch self {
        case .idle: return ""
        case .thinking: return "Thinking…"
        case .executing(let tool): return tool ?? "Running…"
        case .waitingForInput(let type): return type
        case .completed: return "Done"
        case .error: return "Error"
        }
    }
    
    var showText: Bool {
        switch self {
        case .idle: return false
        default: return true
        }
    }
}

@MainActor
final class StatusBarController {
    private let statusItem: NSStatusItem
    private let menu: NSMenu
    private weak var delegate: StatusBarControllerDelegate?
    private var animationTimer: Timer?
    private var animationDots = 0

    init(delegate: StatusBarControllerDelegate) {
        self.delegate = delegate
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        menu = NSMenu()
        configureStatusButton()
        configureMenu()
        // Initial state
        updateDisplay(state: .idle)
    }
    
    /// Get the frame of the status bar button in screen coordinates
    var buttonFrame: NSRect? {
        guard let button = statusItem.button,
              let window = button.window else { return nil }
        let buttonRect = button.convert(button.bounds, to: nil)
        return window.convertToScreen(buttonRect)
    }

    func update(state: AppState.MenuBarState, toolName: String? = nil, isWaitingForInput: Bool = false, inputType: String? = nil) {
        let displayState: StatusBarDisplayState
        
        if isWaitingForInput {
            displayState = .waitingForInput(type: inputType ?? "Input Required")
        } else {
            switch state {
            case .idle:
                displayState = .idle
            case .reasoning:
                displayState = .thinking
            case .executing:
                displayState = .executing(tool: toolName)
            }
        }
        
        updateDisplay(state: displayState)
    }
    
    func showCompleted() {
        updateDisplay(state: .completed)
        // Auto-revert to idle after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.updateDisplay(state: .idle)
        }
    }
    
    func showError() {
        updateDisplay(state: .error)
        // Auto-revert to idle after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.updateDisplay(state: .idle)
        }
    }
    
    private func updateDisplay(state: StatusBarDisplayState) {
        guard let button = statusItem.button else { return }
        
        // Stop any existing animation
        animationTimer?.invalidate()
        animationTimer = nil
        
        // Configure icon - use template mode for automatic dark/light adaptation
        let image = NSImage(systemSymbolName: state.icon, accessibilityDescription: "Motive")
        let configured = image?.withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
        configured?.isTemplate = true  // System will auto-tint: white in dark mode, black in light mode
        
        button.image = configured
        button.imagePosition = state.showText ? .imageLeading : .imageOnly
        button.contentTintColor = nil  // Let system handle color
        
        // Configure text
        if state.showText {
            let baseText = state.text
            
            // Start animation for active states
            switch state {
            case .thinking, .executing, .waitingForInput:
                startTextAnimation(baseText: baseText, button: button)
            default:
                setButtonTitle(baseText, button: button)
            }
            
            // Variable width for text
            statusItem.length = NSStatusItem.variableLength
        } else {
            button.title = ""
            statusItem.length = NSStatusItem.squareLength
        }
        
        statusItem.isVisible = true
    }
    
    private func startTextAnimation(baseText: String, button: NSStatusBarButton) {
        animationDots = 0
        setButtonTitle(baseText, button: button)
        
        animationTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self, weak button] _ in
            guard let self, let button else { return }
            self.animationDots = (self.animationDots + 1) % 4
            
            // Animate dots
            let dots = String(repeating: ".", count: self.animationDots)
            let text = baseText.replacingOccurrences(of: "…", with: dots)
            
            Task { @MainActor in
                self.setButtonTitle(text, button: button)
            }
        }
    }
    
    private func setButtonTitle(_ title: String, button: NSStatusBarButton) {
        // Use controlTextColor which adapts to system appearance automatically
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.controlTextColor
        ]
        button.attributedTitle = NSAttributedString(string: " \(title)", attributes: attributes)
    }

    private func configureStatusButton() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(handleStatusButton)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func configureMenu() {
        let commandItem = NSMenuItem(title: "Command Bar", action: #selector(openCommandBar), keyEquivalent: "")
        commandItem.target = self
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self

        menu.addItem(commandItem)
        menu.addItem(settingsItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)
    }

    @objc private func handleStatusButton() {
        let eventType = NSApp.currentEvent?.type
        if eventType == .rightMouseUp {
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            delegate?.statusBarDidRequestToggleDrawer()
        }
    }

    @objc private func openSettings() {
        delegate?.statusBarDidRequestSettings()
    }

    @objc private func quitApp() {
        delegate?.statusBarDidRequestQuit()
    }

    @objc private func openCommandBar() {
        delegate?.statusBarDidRequestCommandBar()
    }
}
