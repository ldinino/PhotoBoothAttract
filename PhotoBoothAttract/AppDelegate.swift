//
//  AppDelegate.swift
//  PhotoBoothAttract
//
//  Created by Luciano DiNino on 2/28/26.
//

import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var assistantWindow: NSWindow!
    var guestWindow: NSWindow?
    var photoManager: PhotoManager!

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        setupWindows()
    }

    func setupWindows() {
        let screens = NSScreen.screens
        photoManager = PhotoManager()
        
        // 1. Setup Assistant View (Primary Screen)
        let assistantView = AssistantView().environmentObject(photoManager)
        
        assistantWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1024, height: 768),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        assistantWindow.title = "PhotoBooth Assistant"
        assistantWindow.contentView = NSHostingView(rootView: assistantView)
        assistantWindow.center()
        assistantWindow.setFrameAutosaveName("AssistantWindow")
        assistantWindow.makeKeyAndOrderFront(nil)
        
        // 2. Setup Guest View (Secondary Screen)
        if screens.count > 1 {
            let secondaryScreen = screens[1]
            let guestView = GuestView().environmentObject(photoManager)
            
            guestWindow = NSWindow(
                contentRect: secondaryScreen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            
            if let guestWindow = guestWindow {
                guestWindow.title = "Guest TV"
                guestWindow.contentView = NSHostingView(rootView: guestView)
                guestWindow.setFrame(secondaryScreen.frame, display: true)
                guestWindow.level = .screenSaver
                guestWindow.backgroundColor = .black
                guestWindow.orderFront(nil)
            }
        } else {
            ErrorLog.shared.log("No secondary display detected. Guest TV View will not be launched.")
        }
    }
    
    // Terminate the app when the main assistant window is closed
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
