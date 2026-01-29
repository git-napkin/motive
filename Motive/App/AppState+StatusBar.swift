//
//  AppState+StatusBar.swift
//  Motive
//
//  Created by geezerrrr on 2026/1/19.
//

import AppKit

extension AppState: StatusBarControllerDelegate {
    func statusBarDidRequestSettings() {
        SettingsWindowController.shared.show()
    }

    func statusBarDidRequestQuit() {
        NSApp.terminate(nil)
    }

    func statusBarDidRequestToggleDrawer() {
        toggleDrawer()
    }

    func statusBarDidRequestCommandBar() {
        showCommandBar()
    }
}
