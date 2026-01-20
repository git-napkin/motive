//
//  CommandBarWindowController.swift
//  Motive
//
//  Created by geezerrrr on 2026/1/19.
//

import AppKit
import SwiftUI

@MainActor
final class CommandBarWindowController {
    private let window: KeyablePanel
    private let hostingView: NSHostingView<AnyView>
    private var resignKeyObserver: Any?

    init<Content: View>(rootView: Content) {
        hostingView = NSHostingView(rootView: AnyView(rootView))
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 103),  // 64 + 1 + 38
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false  // Shadow is handled by SwiftUI
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = true  // Hide when app loses focus
        panel.becomesKeyOnlyIfNeeded = false
        panel.worksWhenModal = true
        panel.contentView = hostingView
        window = panel
        
        // Hide when window loses key status (clicks outside)
        resignKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            self?.hide()
        }
    }
    
    deinit {
        if let observer = resignKeyObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func show() {
        // Activate app first to ensure proper window handling
        NSApp.activate(ignoringOtherApps: true)
        
        // Position and show window
        centerWindow()
        window.makeKeyAndOrderFront(nil)
        
        // Ensure text field gets focus after a brief delay
        DispatchQueue.main.async { [weak self] in
            self?.focusFirstResponder()
        }
    }

    func hide() {
        window.orderOut(nil)
    }

    func focusFirstResponder() {
        if let textField = window.contentView?.findFirstTextField() {
            window.makeFirstResponder(textField)
        }
    }

    func getWindow() -> NSWindow {
        window
    }

    private func centerWindow() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        
        // Fixed size for consistent appearance
        let fittingSize = hostingView.fittingSize
        let windowSize = NSSize(width: 640, height: max(103, fittingSize.height))
        
        let x = screenFrame.midX - windowSize.width / 2
        let y = screenFrame.minY + screenFrame.height * 0.55  // Slightly above center
        window.setFrame(NSRect(x: x, y: y, width: windowSize.width, height: windowSize.height), display: true)
    }
}

final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
