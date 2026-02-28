//
//  PhotoBoothAttractApp.swift
//  PhotoBoothAttract
//
//  Created by Luciano DiNino on 2/28/26.
//

import SwiftUI

@main
struct PhotoBoothAttractApp: App {
    // Inject the AppKit AppDelegate into the SwiftUI lifecycle
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // We leave this empty because AppDelegate handles window creation.
        // Settings acts as a dummy scene to satisfy the compiler.
        Settings {
            EmptyView()
        }
    }
}
