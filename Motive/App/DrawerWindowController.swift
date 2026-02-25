//
//  DrawerWindowController.swift
//  Motive
//
//  Created by geezerrrr on 2026/1/19.
//

import AppKit
import SwiftUI

// Note: Uses KeyablePanel from CommandBarWindowController.swift

@MainActor
final class DrawerWindowController {
    private enum Layout {
        static let width: CGFloat = 400
        static let height: CGFloat = 600
    }

    private let window: KeyablePanel
    private var statusBarButtonFrame: NSRect?
    private var resignKeyObserver: Any?
    private var lastShowTime: Date = .distantPast
    var isVisible: Bool {
        window.isVisible
    }

    /// When true, the window will not hide on resign key (used during delete confirmation)
    var suppressAutoHide: Bool = false

    init(rootView: some View) {
        // Use a fixed-size container NSView to host SwiftUI, avoiding dynamic constraint updates
        let containerView = NSView(frame: NSRect(x: 0, y: 0, width: Layout.width, height: Layout.height))
        containerView.wantsLayer = true
        containerView.layerContentsRedrawPolicy = .onSetNeedsDisplay
        
        let hostingView = NSHostingView(rootView: AnyView(rootView))
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.safeAreaRegions = []
        containerView.addSubview(hostingView)
        
        // Pin hosting view to container edges with fixed constraints
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: containerView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        window = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: Layout.width, height: Layout.height),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.contentView = containerView
        window.applyFloatingPanelStyle()
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = true

        // Hide when window loses key status (clicks outside, unless suppressed)
        resignKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            // Guard: don't auto-hide if we just showed (prevents focus-race glitches)
            if !self.suppressAutoHide, Date().timeIntervalSince(self.lastShowTime) > 0.3 {
                self.hide()
            }
        }
    }

    deinit {
        resignKeyObserver.map { NotificationCenter.default.removeObserver($0) }
    }

    /// Update the position reference for the status bar button
    func updateStatusBarButtonFrame(_ frame: NSRect?) {
        self.statusBarButtonFrame = frame
    }

    func show() {
        lastShowTime = Date()
        positionBelowStatusBar()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func hide() {
        // Resign first responder to prevent cursor from lingering
        window.makeFirstResponder(nil)
        window.orderOut(nil)
    }

    func getWindow() -> NSWindow {
        window
    }

    private func positionBelowStatusBar() {
        // Build list of fallback screens
        var screens: [NSScreen] = []
        if let anchorScreen = screenForAnchor() {
            screens.append(anchorScreen)
        }
        if let windowScreen = window.screen {
            screens.append(windowScreen)
        }
        if let mainScreen = NSScreen.main {
            screens.append(mainScreen)
        }
        screens.append(contentsOf: NSScreen.screens)
        
        guard let screen = screens.first(where: { $0.visibleFrame.width > 100 }) else {
            Log.warning("No valid screen found for drawer positioning")
            // Fallback to default position
            window.setFrameOrigin(NSPoint(x: 100, y: 100))
            return
        }
        
        let width = window.frame.width
        let height = window.frame.height

        let x: CGFloat
        let y: CGFloat

        if let buttonFrame = statusBarButtonFrame {
            // Position below status bar icon, aligned to right edge
            x = buttonFrame.maxX - width
            y = buttonFrame.minY - height - 6 // 6pt gap below status bar
        } else {
            // Fallback: position at top-right of screen
            let visibleFrame = screen.visibleFrame
            x = visibleFrame.maxX - width - 12
            y = visibleFrame.maxY - height - 12
        }

        // Ensure window stays within screen bounds
        let visibleFrame = screen.visibleFrame
        let clampedX = max(visibleFrame.minX + 12, min(x, visibleFrame.maxX - width - 12))
        let clampedY = max(visibleFrame.minY + 12, min(y, visibleFrame.maxY - height - 12))

        window.setFrameOrigin(NSPoint(x: clampedX, y: clampedY))
    }

    private func screenForAnchor() -> NSScreen? {
        guard let buttonFrame = statusBarButtonFrame else { return nil }
        let anchorPoint = NSPoint(x: buttonFrame.midX, y: buttonFrame.midY)
        return NSScreen.screens.first { $0.frame.contains(anchorPoint) } ?? KeyablePanel.screenForMouse()
    }
}
