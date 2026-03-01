//
//  AppDelegate.swift
//  PhotoBoothAttract
//
//  Created by Luciano DiNino on 2/28/26.
//

import Cocoa
import SwiftUI


class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var assistantWindow: NSWindow!
    var guestWindow: NSWindow?
    var photoManager: PhotoManager!

    func applicationWillFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        for window in NSApp.windows {
            window.close()
        }

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
        assistantWindow.minSize = NSSize(width: 480, height: 400)
        assistantWindow.contentMinSize = NSSize(width: 480, height: 400)
        assistantWindow.center()
        assistantWindow.setFrameAutosaveName("AssistantWindow")
        assistantWindow.delegate = self
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
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === assistantWindow else { return true }
        
        let alert = NSAlert()
        alert.messageText = "Are you sure you want to quit?"
        alert.informativeText = "Closing this window will also close the Guest TV and quit the application."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSApp.terminate(nil)
        }
        return false
    }
}
