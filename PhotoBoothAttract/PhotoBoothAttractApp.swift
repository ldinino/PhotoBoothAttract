//
//  PhotoBoothAttractApp.swift
//  PhotoBoothAttract
//
//  Created by Luciano DiNino on 2/28/26.
//

import SwiftUI
import AppKit

@main
struct PhotoBoothAttractApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
        .commands {
            HelpMenuCommands()
            WindowCommands()
        }

        Window("Error Log", id: "error-log") {
            ErrorLogView()
        }
        .defaultSize(width: 600, height: 400)
        .commandsRemoved()
    }
}

struct HelpMenuCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .help) {
            Button("Check for Updates...") {
                UpdateManager.shared.checkForUpdates()
            }

            Divider()

            Button("Error Log") {
                openWindow(id: "error-log")
            }
            .keyboardShortcut("L", modifiers: [.command, .option])

            Divider()

            Button("Refresh Displays") {
                NotificationCenter.default.post(name: .refreshDisplaysRequested, object: nil)
            }
        }
    }
}

/// Replaces the default Window arrangement group to remove "Show Tab Bar" and "Show All Tabs".
struct WindowCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .windowArrangement) {
            Button("Minimize") {
                NSApp.keyWindow?.miniaturize(nil)
            }
            .keyboardShortcut("m", modifiers: .command)

            Button("Zoom") {
                NSApp.keyWindow?.zoom(nil)
            }

            Divider()

            Button("Enter Full Screen") {
                NSApp.keyWindow?.toggleFullScreen(nil)
            }
            .keyboardShortcut("f", modifiers: [.command, .control])
        }
    }
}
