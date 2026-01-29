//
//  AppState+CommandBar.swift
//  Motive
//
//  Created by geezerrrr on 2026/1/19.
//

import SwiftUI

extension AppState {
    func showCommandBar() {
        guard let commandBarController else {
            Log.debug("commandBarController is nil!")
            return
        }
        Log.debug("Showing command bar window")
        // Trigger SwiftUI state reset
        commandBarResetTrigger += 1
        commandBarController.show()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak commandBarController] in
            commandBarController?.focusFirstResponder()
        }
    }

    func hideCommandBar() {
        Log.debug("Hiding command bar window")
        commandBarController?.hide()
    }

    func updateCommandBarHeight(for modeName: String) {
        // Disable window animation to prevent height jitter
        commandBarController?.updateHeightForMode(modeName, animated: false)
    }

    func updateCommandBarHeight(to height: CGFloat) {
        // Disable window animation to prevent height jitter
        commandBarController?.updateHeight(to: height, animated: false)
    }

    /// Suppress or allow auto-hide when command bar loses focus
    func setCommandBarAutoHideSuppressed(_ suppressed: Bool) {
        commandBarController?.suppressAutoHide = suppressed
    }

    /// Refocus the command bar input field
    func refocusCommandBar() {
        commandBarController?.focusFirstResponder()
    }
}
