//
//  PhotoBoothAttractApp.swift
//  PhotoBoothAttract
//
//  Created by Luciano DiNino on 2/28/26.
//

import SwiftUI

@main
struct PhotoBoothAttractApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
        .commands { HelpMenuCommands() }

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
            Button("Error Log") {
                openWindow(id: "error-log")
            }
            .keyboardShortcut("L", modifiers: [.command, .option])
        }
    }
}
