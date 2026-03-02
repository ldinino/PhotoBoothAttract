//
//  AppDelegate.swift
//  PhotoBoothAttract
//
//  Created by Luciano DiNino on 2/28/26.
//

import Cocoa
import SwiftUI

extension Notification.Name {
    static let refreshDisplaysRequested = Notification.Name("RefreshDisplaysRequested")
}

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var assistantWindow: NSWindow!
    var guestWindow: NSWindow?
    var photoManager: PhotoManager!
    private var screenChangeObserver: NSObjectProtocol?
    private var refreshDisplaysRequestedObserver: NSObjectProtocol?
    private var pendingScreenChangeWorkItem: DispatchWorkItem?
    private var isRefreshingDisplays = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        for window in NSApp.windows {
            window.close()
        }

        setupWindows()

        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            ErrorLog.shared.log("Display configuration changed.")
            self.pendingScreenChangeWorkItem?.cancel()
            let item = DispatchWorkItem { [weak self] in
                self?.refreshDisplayLayout()
            }
            self.pendingScreenChangeWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: item)
        }

        refreshDisplaysRequestedObserver = NotificationCenter.default.addObserver(
            forName: .refreshDisplaysRequested,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshDisplayLayout()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        pendingScreenChangeWorkItem?.cancel()
        pendingScreenChangeWorkItem = nil
        if let observer = screenChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            screenChangeObserver = nil
        }
        if let observer = refreshDisplaysRequestedObserver {
            NotificationCenter.default.removeObserver(observer)
            refreshDisplaysRequestedObserver = nil
        }
    }

    func setupWindows() {
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
        assistantWindow.tabbingMode = .disallowed
        assistantWindow.makeKeyAndOrderFront(nil)

        // 2. Guest View (Secondary Screen) — created/updated by refreshDisplayLayout()
        refreshDisplayLayout()
    }

    /// Updates guest window based on current screens. Call on main thread. Re-centers assistant on main screen.
    /// Reuses the guest window instead of closing/recreating to avoid NSHostingView teardown crash (objc_release).
    func refreshDisplayLayout() {
        if isRefreshingDisplays { return }
        isRefreshingDisplays = true
        defer { isRefreshingDisplays = false }

        let screens = NSScreen.screens
        ErrorLog.shared.log("Displays refreshed: \(screens.count) screen(s) detected.")

        assistantWindow.center()

        if screens.count > 1 {
            let secondaryScreen = screens[1]
            if let existing = guestWindow {
                existing.setFrame(secondaryScreen.frame, display: true)
                existing.orderFront(nil)
                ErrorLog.shared.log("Guest TV window shown on secondary display.")
            } else {
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
                    ErrorLog.shared.log("Guest TV window shown on secondary display.")
                }
            }
        } else {
            guestWindow?.orderOut(nil)
            ErrorLog.shared.log("No secondary display present. Guest TV window not shown.")
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
