//
//  AppDelegate.swift
//  PhotoBoothAttract
//
//  Created by Luciano DiNino on 2/28/26.
//

import Cocoa
import SwiftUI
import Combine
import ImageCaptureCore
import Darwin

extension Notification.Name {
    static let refreshDisplaysRequested = Notification.Name("RefreshDisplaysRequested")
}

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var assistantWindow: NSWindow!
    var guestWindow: NSWindow?
    var photoManager: PhotoManager!
    var sonyCameraManager: SonyCameraManager!
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

        sonyCameraManager = SonyCameraManager()
        setupWindows()
        sonyCameraManager.start()

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
        sonyCameraManager?.stop()
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
        let assistantView = AssistantView()
            .environmentObject(photoManager)
            .environmentObject(sonyCameraManager)

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

enum CameraMode: String, CaseIterable, Identifiable {
    case cooperative
    case native

    static let key = "cameraMode"
    /// Mode chosen at process start; changes saved later apply on the next launch.
    static let launched = resolve()

    var id: String { rawValue }
    var title: String { self == .cooperative ? "Cooperative" : "Native" }

    static func resolve(_ defaults: UserDefaults = .standard) -> CameraMode {
        defaults.string(forKey: key).flatMap(CameraMode.init(rawValue:)) ?? .cooperative
    }
}

enum CameraConnectionStatus: Equatable {
    case notConnected
    case connected(model: String)
    case failed(reason: String)
}

final class SonyCameraManager: NSObject, ObservableObject {
    @Published private(set) var connectionStatus: CameraConnectionStatus = .notConnected

    struct Backend {
        let load: () -> String?
        let startDiscovery: () -> Void
        let stopDiscovery: () -> Void
    }

    let mode: CameraMode
    private let makeBackend: (SonyCameraManager) -> Backend
    private var backend: Backend?
    private var activeUSBDeviceUUID: String?
    private var started = false

    init(mode: CameraMode = .launched, makeBackend: ((SonyCameraManager) -> Backend)? = nil) {
        self.mode = mode
        self.makeBackend = makeBackend ?? { SonyCameraManager.liveBackend(for: $0) }
        super.init()
    }

    private static func liveBackend(for manager: SonyCameraManager) -> Backend {
        let loader = SonySDKLoader()
        let browser = ICDeviceBrowser()
        browser.delegate = manager
        return Backend(
            load: { loader.load() ? nil : (loader.lastErrorDescription ?? "Sony SDK failed to load.") },
            startDiscovery: { browser.start() },
            stopDiscovery: { browser.stop() }
        )
    }

    func start() {
        guard mode == .native, !started else { return }
        started = true

        let backend = self.backend ?? makeBackend(self)
        self.backend = backend
        if let reason = backend.load() {
            connectionStatus = .failed(reason: reason)
            ErrorLog.shared.log(reason)
        } else {
            ErrorLog.shared.log("Sony SDK loaded successfully.")
            connectionStatus = .notConnected
        }
        // Keep USB discovery active even when SDK binaries are missing.
        backend.startDiscovery()
    }

    func stop() {
        guard started else { return }
        started = false
        backend?.stopDiscovery()
    }
}

extension SonyCameraManager: ICDeviceBrowserDelegate {
    func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        let model = device.name ?? ""
        let loweredModel = model.lowercased()
        let isUSB = device.transportType == ICDeviceTransport.transportTypeUSB.rawValue
        let modelLooksSony = isSonyModelName(loweredModel)
        let passesFilter = isUSB && modelLooksSony && !model.isEmpty

        guard passesFilter else { return }
        guard activeUSBDeviceUUID == nil else { return }

        activeUSBDeviceUUID = device.uuidString
        connectionStatus = .connected(model: model)
        ErrorLog.shared.log("Sony USB camera connected: \(model)")
    }

    func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
        guard isSonyUSBDevice(device) else { return }
        guard device.uuidString == activeUSBDeviceUUID else { return }

        let model = device.name ?? "Unknown camera"
        activeUSBDeviceUUID = nil
        connectionStatus = .notConnected
        ErrorLog.shared.log("Sony USB camera disconnected: \(model)")
    }

    func deviceBrowserDidEnumerateLocalDevices(_ browser: ICDeviceBrowser) {}

    func deviceBrowser(_ browser: ICDeviceBrowser, didEncounterError error: Error?) {
        if let error {
            ErrorLog.shared.log("ICDeviceBrowser error: \(error.localizedDescription)")
        }
    }

    private func isSonyUSBDevice(_ device: ICDevice) -> Bool {
        guard device.transportType == ICDeviceTransport.transportTypeUSB.rawValue else { return false }
        guard let model = device.name?.lowercased() else { return false }
        return isSonyModelName(model)
    }

    private func isSonyModelName(_ loweredModel: String) -> Bool {
        if loweredModel.contains("sony") || loweredModel.contains("alpha") {
            return true
        }
        let sonyPrefixes = ["ilce-", "ilca-", "zv-", "dsc-", "nex-", "slt-"]
        return sonyPrefixes.contains { loweredModel.hasPrefix($0) }
    }
}

final class SonySDKLoader {
    private var libraryHandles: [UnsafeMutableRawPointer] = []
    private(set) var lastErrorDescription: String?

    deinit {
        for handle in libraryHandles {
            dlclose(handle)
        }
        libraryHandles.removeAll()
    }

    func load() -> Bool {
        lastErrorDescription = nil

        guard let frameworksPath = Bundle.main.privateFrameworksPath else {
            lastErrorDescription = "Missing app Frameworks directory in bundle."
            return false
        }

        let rootDylibNames = [
            "libmonitor_protocol.dylib",
            "libmonitor_protocol_pf.dylib",
            "libCr_Core.dylib"
        ]
        let adapterDylibNames = [
            "libusb-1.0.0.dylib",
            "libCr_PTP_USB.dylib"
        ]

        let rootDirs = candidateRootLibraryDirectories(frameworksPath: frameworksPath)
        let adapterDirs = candidateAdapterLibraryDirectories(frameworksPath: frameworksPath, rootDirs: rootDirs)

        var resolvedPaths: [String: String] = [:]
        var missingDylibs: [String] = []

        for dylib in rootDylibNames {
            if let path = resolveLibraryPath(named: dylib, candidates: rootDirs) {
                resolvedPaths[dylib] = path
            } else {
                missingDylibs.append(dylib)
            }
        }

        for dylib in adapterDylibNames {
            if let path = resolveLibraryPath(named: dylib, candidates: adapterDirs) {
                resolvedPaths[dylib] = path
            } else {
                missingDylibs.append(dylib)
            }
        }

        if !missingDylibs.isEmpty {
            let dirSummary = "root[\(rootDirs.joined(separator: ", "))] adapter[\(adapterDirs.joined(separator: ", "))]"
            lastErrorDescription = "Missing Sony SDK dylibs (\(missingDylibs.joined(separator: ", "))). Searched \(dirSummary)"
        }

        var loadedHandles: [UnsafeMutableRawPointer] = []
        let loadOrder = rootDylibNames + adapterDylibNames
        for dylib in loadOrder {
            guard let fullPath = resolvedPaths[dylib] else {
                for loaded in loadedHandles {
                    dlclose(loaded)
                }
                return false
            }
            _ = dlerror()
            guard let handle = dlopen(fullPath, RTLD_NOW) else {
                var dlopenError = "unknown"
                if let errPtr = dlerror() {
                    dlopenError = String(cString: errPtr)
                }
                lastErrorDescription = "dlopen failed for \(dylib): \(dlopenError)"
                for loaded in loadedHandles {
                    dlclose(loaded)
                }
                return false
            }
            loadedHandles.append(handle)
        }

        libraryHandles = loadedHandles
        return true
    }

    private func candidateRootLibraryDirectories(frameworksPath: String) -> [String] {
        var dirs: [String] = []
        dirs.append(frameworksPath)
        if let resourcesPath = Bundle.main.resourcePath {
            dirs.append((resourcesPath as NSString).appendingPathComponent("SonySDK/crsdk"))
        }
        return uniqueDirectories(dirs)
    }

    private func candidateAdapterLibraryDirectories(frameworksPath: String, rootDirs: [String]) -> [String] {
        var dirs: [String] = []
        dirs.append((frameworksPath as NSString).appendingPathComponent("CrAdapter"))
        for root in rootDirs {
            dirs.append((root as NSString).appendingPathComponent("CrAdapter"))
        }
        return uniqueDirectories(dirs)
    }

    private func uniqueDirectories(_ directories: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for dir in directories {
            let standardized = (dir as NSString).standardizingPath
            guard !seen.contains(standardized) else { continue }
            seen.insert(standardized)
            result.append(standardized)
        }
        return result
    }

    private func resolveLibraryPath(named dylib: String, candidates: [String]) -> String? {
        for dir in candidates {
            let path = (dir as NSString).appendingPathComponent(dylib)
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        return nil
    }
}
