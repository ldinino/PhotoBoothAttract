import AppKit
import CryptoKit
import ImageIO
import ApplicationServices
import Darwin

// MARK: - Native: attachments, orientation, responsiveness, displays

let cornerOrder = ["TL", "TR", "BL", "BR"]
/// Where raw corners TL, TR, BL, BR land for EXIF orientation 1...8.
let orientationMap: [Int: [String]] = [
    1: ["TL", "TR", "BL", "BR"], 2: ["TR", "TL", "BR", "BL"], 3: ["BR", "BL", "TR", "TL"], 4: ["BL", "BR", "TL", "TR"],
    5: ["TL", "BL", "TR", "BR"], 6: ["TR", "BR", "TL", "BL"], 7: ["BR", "TR", "BL", "TL"], 8: ["BL", "TL", "BR", "TR"],
]
let markerColors: [RGB] = [(255, 255, 255), (0, 0, 0), (255, 0, 0), gray]
let markerNames = ["white", "black", "red", "gray"]

func cornerClasses(_ image: CGImage) -> [String: String] {
    let p = Pixels(image)
    let inset = Int(Double(min(p.w, p.h)) * 0.05)
    let spots = ["TL": (inset, inset), "TR": (p.w - inset - 1, inset), "BL": (inset, p.h - inset - 1), "BR": (p.w - inset - 1, p.h - inset - 1)]
    return spots.mapValues { spot in
        let c = p.at(spot.0, spot.1)
        return markerNames[(0..<4).min { distance(markerColors[$0], c) < distance(markerColors[$1], c) }!]
    }
}

func expectedCorners(orientation: Int) -> [String: String] {
    var result: [String: String] = [:]
    for (raw, display) in orientationMap[orientation]!.enumerated() { result[display] = markerNames[raw] }
    return result
}

func moreCases() {
    runCase("N08", "NATIVE", "Attachment isolation and orientation (EXIF 1-8 JPEG, portrait/landscape JPEG+PNG); no Messages draft") {
        let folder = makeFolder("attach")
        var created: [URL] = []
        defer { created.forEach { try? FileManager.default.removeItem(at: $0.deletingLastPathComponent()) } }

        let first = writeNumbered(1, in: folder, name: "same-name.jpg")
        let firstBytes = try! Data(contentsOf: first), firstHash = sha(first)
        let second = writeNumbered(2, in: makeFolder("attach2"), name: "same-name.jpg")
        let a = MessageManager.shared.attachmentURL(for: firstBytes, name: "same-name.jpg")
        let b = MessageManager.shared.attachmentURL(for: try! Data(contentsOf: second), name: "same-name.jpg")
        created += [a, b].compactMap { $0 }
        expect(a != nil && b != nil && a!.deletingLastPathComponent() != b!.deletingLastPathComponent(), "same-named requests share a directory")
        expect(a.flatMap { try? Data(contentsOf: $0) } != b.flatMap { try? Data(contentsOf: $0) }, "same-named requests share bytes")
        expect(sha(first) == firstHash, "original changed by attachment preparation")

        for (name, png, portrait) in [("landscape.jpg", false, false), ("portrait.jpg", false, true), ("landscape.png", true, false), ("portrait.png", true, true)] {
            let url = writeNumbered(3, in: folder, name: name, png: png, portrait: portrait)
            guard let out = MessageManager.shared.attachmentURL(for: try! Data(contentsOf: url), name: name) else { failures.append("\(name): no attachment"); continue }
            created.append(out)
            let size = CGImageSourceCreateWithURL(out as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }.map { ($0.width, $0.height) }
            expect(size.map { portrait ? $0.1 > $0.0 : $0.0 > $0.1 } == true, "\(name): attachment aspect \(String(describing: size))")
        }

        for orientation in 1...8 {
            let ctx = makeContext(600, 400)
            draw(ctx, width: 600, height: 400, background: gray, label: nil)
            let url = folder.appendingPathComponent("exif-\(orientation).jpg")
            writeImage(ctx.makeImage()!, to: url, type: .jpeg, orientation: orientation, quality: 0.95)
            let want = expectedCorners(orientation: orientation)

            if let out = MessageManager.shared.attachmentURL(for: try! Data(contentsOf: url), name: url.lastPathComponent),
               let image = CGImageSourceCreateWithURL(out as CFURL, nil).flatMap({ CGImageSourceCreateImageAtIndex($0, 0, nil) }) {
                created.append(out)
                expect(cornerClasses(image) == want, "EXIF \(orientation) attachment corners \(cornerClasses(image)), want \(want)")
                expect((orientation >= 5) == (image.height > image.width), "EXIF \(orientation) attachment orientation not applied to dimensions")
            } else { failures.append("EXIF \(orientation): no attachment") }

            if let thumbnail = PhotoModel(url: url)?.thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                expect(cornerClasses(thumbnail) == want, "EXIF \(orientation) guest/assistant thumbnail corners \(cornerClasses(thumbnail)), want \(want)")
            } else { failures.append("EXIF \(orientation): no thumbnail") }
        }
    }

    runCase("N09", "NATIVE", "Populated folder: 40 large JPEGs stay responsive, newest first, originals untouched") {
        let folder = makeFolder("large")
        let started = Date()
        writeLargeSet(count: 40, in: folder)
        say("     generated 40 x ~5000x3500 JPEGs in \(String(format: "%.1f", Date().timeIntervalSince(started)))s")
        let sample = (1...40).filter { $0 % 13 == 1 }.map { folder.appendingPathComponent(String(format: "large-%02d.jpg", $0)) }
        let hashes = sample.map(sha)

        let host = Host(folder: nil)
        let window = host.showAssistant()
        var gaps: [Double] = []
        var last = Date()
        let timer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { _ in gaps.append(Date().timeIntervalSince(last)); last = Date() }
        host.manager.setWatchedFolder(folder)
        waitFor("40 photos listed and scan finished", 180) { host.manager.photos.count == 40 && !host.manager.isRefreshing }
        timer.invalidate()
        let stallLimit = 0.75
        let worst = gaps.max() ?? 0
        say("     worst main-thread stall during scan: \(String(format: "%.3f", worst))s (limit \(stallLimit)s)")
        expect(worst < stallLimit, "main thread stalled \(String(format: "%.2f", worst))s during the scan")
        expect(names(host.manager) == (1...40).reversed().map { String(format: "large-%02d.jpg", $0) }, "order is not newest first")
        expect(!axActive || hasText(window, "large-40.jpg"), "newest large photo not shown in the assistant")
        expect(zip(sample, hashes).allSatisfy { sha($0) == $1 }, "a large original changed")
        var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
        let peakMB = Int(usage.ru_maxrss) / 1_048_576
        say("     peak resident memory: \(peakMB) MB")
        expect(peakMB < 2_500, "peak memory \(peakMB) MB")
        host.close()
    }

    runCase("N10", "NATIVE", "Single-display fallback (real AppDelegate window setup)") {
        guard NSScreen.screens.count == 1 else { throw Skip(reason: "\(NSScreen.screens.count) displays attached; needs exactly one. Run with only the built-in display to qualify.") }
        let delegate = AppDelegate()
        delegate.sonyCameraManager = SonyCameraManager()
        delegate.setupWindows()
        expect(delegate.assistantWindow.isVisible, "assistant window not visible")
        expect(delegate.guestWindow == nil || delegate.guestWindow?.isVisible == false, "guest window shown with one display")
        delegate.assistantWindow.orderOut(nil)
    }

    runCase("N11", "NATIVE", "Dual-display placement (real AppDelegate window setup)") {
        guard NSScreen.screens.count > 1 else { throw Skip(reason: "only one display attached; connect the TV and rerun") }
        let delegate = AppDelegate()
        delegate.sonyCameraManager = SonyCameraManager()
        delegate.setupWindows()
        defer { delegate.guestWindow?.orderOut(nil); delegate.assistantWindow.orderOut(nil) }
        let secondary = NSScreen.screens[1].frame
        expect(delegate.guestWindow?.frame == secondary, "guest frame \(String(describing: delegate.guestWindow?.frame)) != secondary \(secondary)")
        expect(delegate.guestWindow?.isVisible == true, "guest window hidden")
        expect(NSScreen.screens[0].frame.intersects(delegate.assistantWindow.frame), "assistant window not on the primary display")
        let guestFrame = delegate.guestWindow?.frame
        delegate.refreshDisplayLayout()
        expect(delegate.guestWindow?.frame == guestFrame, "second refresh moved or recreated the guest window")
    }
}

// MARK: - App tier (launched, isolated copy of the supplied app; Accessibility)

func axValue(_ e: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    return AXUIElementCopyAttributeValue(e, name as CFString, &value) == .success ? value : nil
}

func axStrings(_ e: AXUIElement, depth: Int = 0, into out: inout [String]) {
    guard depth < 30 else { return }
    for name in [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute] {
        if let s = axValue(e, name) as? String, !s.isEmpty { out.append(s) }
    }
    for child in (axValue(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] { axStrings(child, depth: depth + 1, into: &out) }
}

func axFrame(_ e: AXUIElement) -> CGRect? {
    var origin = CGPoint.zero, size = CGSize.zero
    guard let p = axValue(e, kAXPositionAttribute), let s = axValue(e, kAXSizeAttribute),
          AXValueGetValue(p as! AXValue, .cgPoint, &origin), AXValueGetValue(s as! AXValue, .cgSize, &size) else { return nil }
    return CGRect(origin: origin, size: size)
}

final class AppInstance {
    let root: URL, home: URL, bundleID: String, executable: URL
    var process: Process?
    var element: AXUIElement { AXUIElementCreateApplication(process!.processIdentifier) }

    /// A throwaway copy with its own bundle identifier, so preferences and window state are separate; the supplied app is never touched.
    init?(app: URL, info: [String: Any]) {
        bundleID = "org.photoboothattract.coreui.\(UUID().uuidString.prefix(8).lowercased())"
        root = makeFolder("app-home")
        home = root.appendingPathComponent("home", isDirectory: true)
        let copy = root.appendingPathComponent("PhotoBoothAttract.app")
        executable = copy.appendingPathComponent("Contents/MacOS/\(info["CFBundleExecutable"] as! String)")
        ownedPrefsDomains.append(bundleID)
        do {
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: app, to: copy)
            let plistURL = copy.appendingPathComponent("Contents/Info.plist")
            var plist = NSDictionary(contentsOf: plistURL) as! [String: Any]
            plist["CFBundleIdentifier"] = bundleID
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: plistURL)
            let sign = Process()
            sign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
            sign.arguments = ["--force", "--deep", "--sign", "-", copy.path]
            sign.standardError = FileHandle.nullDevice
            try sign.run(); sign.waitUntilExit()
            guard sign.terminationStatus == 0 else { throw Skip(reason: "codesign of the isolated copy failed (status \(sign.terminationStatus))") }
        } catch {
            failures.append("could not prepare the isolated app copy: \(error)")
            return nil
        }
    }

    /// A bookmark in the copy's own preferences domain seeds the saved folder.
    func seed(folder: URL?) {
        guard let folder, let defaults = UserDefaults(suiteName: bundleID) else { return }
        defaults.set(try! folder.bookmarkData(), forKey: "watchedFolderBookmark")
        defaults.synchronize()
    }

    func launch() -> Bool {
        let p = Process()
        p.executableURL = executable
        p.environment = ["HOME": home.path, "CFFIXED_USER_HOME": home.path, "TMPDIR": root.path + "/tmp/", "PATH": "/usr/bin:/bin"]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        try? FileManager.default.createDirectory(at: root.appendingPathComponent("tmp"), withIntermediateDirectories: true)
        do { try p.run() } catch { failures.append("could not launch the app: \(error.localizedDescription)"); return false }
        process = p; ownedProcess = p
        if waitFor("app window appears", 20, { !windows().isEmpty }) { return true }
        quit()
        return false
    }

    func windows() -> [(title: String, frame: CGRect?)] {
        ((axValue(element, kAXWindowsAttribute) as? [AXUIElement]) ?? []).map { ((axValue($0, kAXTitleAttribute) as? String) ?? "", axFrame($0)) }
    }

    func strings() -> [String] { var out: [String] = []; axStrings(element, into: &out); return out }
    func has(_ needle: String) -> Bool { strings().contains { $0.contains(needle) } }
    func count(_ needle: String) -> Int { strings().filter { $0 == needle }.count }

    func pressButton(containing needle: String) -> Bool {
        func walk(_ e: AXUIElement, _ depth: Int) -> AXUIElement? {
            guard depth < 30 else { return nil }
            if (axValue(e, kAXRoleAttribute) as? String) == kAXButtonRole,
               [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute].contains(where: { (axValue(e, $0) as? String)?.contains(needle) == true }) { return e }
            for child in (axValue(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] { if let hit = walk(child, depth + 1) { return hit } }
            return nil
        }
        guard let button = walk(element, 0) else { return false }
        return AXUIElementPerformAction(button, kAXPressAction as CFString) == .success
    }

    func quit() {
        guard let p = process else { return }
        p.terminate()
        if !waitFor("owned app instance exits", 8, { !p.isRunning }) { kill(p.processIdentifier, SIGKILL) }
        process = nil; ownedProcess = nil
    }
}

func accessibilityTrusted() -> Bool {
    if simulateNoAX { return false }
    return AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): promptAX] as CFDictionary)
}

let missingAccessibility = "Accessibility permission is not granted. In System Settings > Privacy & Security > Accessibility, switch on the app that started this runner (Terminal), then rerun; or rerun with --prompt-accessibility to show the system prompt."

func appCases(app: URL?, info: [String: Any]?) {
    guard let app, let info else {
        for (id, title) in [("A01", "Actual-app launch, empty state, display lifecycle"), ("A02", "Actual-app saved-folder restoration, live arrivals, incomplete write, replacement, disappearance, refresh"),
                            ("A03", "Actual-app folder switch (relaunch on a second saved folder)"), ("A04", "Operator preferences and log untouched")] {
            runCase(id, "APP", title) { throw Skip(reason: "no app bundle supplied (--app path/to/PhotoBoothAttract.app)") }
        }
        return
    }
    let trusted = accessibilityTrusted()
    let realPrefs = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Preferences/\(info["CFBundleIdentifier"] as! String).plist")
    let before = (fingerprint(realPrefs), fingerprint(realLog))

    runCase("A01", "APP", "Actual-app launch, empty state, display lifecycle") {
        guard trusted else { throw Skip(reason: missingAccessibility) }
        guard let instance = AppInstance(app: app, info: info) else { return }
        guard instance.launch() else { return }
        defer { instance.quit() }
        waitFor("empty-state message", 10) { instance.has("No photos yet") }
        let titles = instance.windows().map { $0.title }
        expect(titles.contains("PhotoBooth Assistant"), "assistant window missing: \(titles)")
        if NSScreen.screens.count == 1 {
            expect(!titles.contains("Guest TV") || instance.windows().first { $0.title == "Guest TV" }?.frame == nil, "guest window present on a single display")
        } else {
            waitFor("Guest TV window on the secondary display", 6) { instance.windows().contains { $0.title == "Guest TV" } }
            let guest = instance.windows().first { $0.title == "Guest TV" }?.frame
            let secondary = NSScreen.screens[1].frame
            let primaryHeight = NSScreen.screens[0].frame.height
            let expected = CGRect(x: secondary.minX, y: primaryHeight - secondary.maxY, width: secondary.width, height: secondary.height)
            expect(guest.map { abs($0.minX - expected.minX) < 2 && abs($0.minY - expected.minY) < 2 && abs($0.width - expected.width) < 2 } == true, "guest frame \(String(describing: guest)) != \(expected)")
        }
        expect(instance.process?.isRunning == true, "app exited")
    }

    runCase("A02", "APP", "Actual-app saved-folder restoration, live arrivals, incomplete write, replacement, disappearance, refresh") {
        guard trusted else { throw Skip(reason: missingAccessibility) }
        let folder = makeFolder("app-A")
        writeNumbered(1, in: folder); writeNumbered(2, in: folder)
        guard let instance = AppInstance(app: app, info: info) else { return }
        instance.seed(folder: folder)
        guard instance.launch() else { return }
        defer { instance.quit() }
        waitFor("restored folder name shown", 12) { instance.has("Watching: \(folder.lastPathComponent)") }
        waitFor("restored photos listed", 12) { instance.has("photo-1-red.jpg") && instance.has("photo-2-green.jpg") }
        writeNumbered(3, in: folder)
        waitFor("live arrival listed", 12) { instance.has("photo-3-blue.jpg") }
        let partial = folder.appendingPathComponent("partial.jpg")
        try! Data([1, 2, 3, 4, 5]).write(to: partial)
        spin(1.5)
        expect(!instance.has("partial.jpg"), "incomplete write listed")
        let whole = writeNumbered(4, in: makeFolder("app-scratch"))
        try! FileManager.default.removeItem(at: partial)
        try! FileManager.default.copyItem(at: whole, to: partial)
        waitFor("completed write listed once", 12) { instance.count("partial.jpg") == 1 }
        let target = folder.appendingPathComponent("photo-3-blue.jpg")
        try! FileManager.default.removeItem(at: target)
        writeNumbered(3, in: folder, color: 4)
        spin(2)
        expect(instance.count("photo-3-blue.jpg") == 1, "replacement left \(instance.count("photo-3-blue.jpg")) rows for one file")
        try! FileManager.default.removeItem(at: target)
        waitFor("disappearing file leaves the list", 12) { !instance.has("photo-3-blue.jpg") }
        expect(instance.pressButton(containing: "Restart file watcher"), "refresh button not found")
        spin(1)
        expect(instance.has("photo-1-red.jpg") && instance.has("partial.jpg") && !instance.has("photo-3-blue.jpg"), "refresh changed the list")
        expect(FileManager.default.fileExists(atPath: instance.home.appendingPathComponent("Library/Application Support/PhotoBoothAttract/PhotoBoothAttract.log").path),
               "app did not write its log under the isolated home")
    }

    runCase("A03", "APP", "Actual-app folder switch (relaunch on a second saved folder)") {
        guard trusted else { throw Skip(reason: missingAccessibility) }
        let folder = makeFolder("app-B")
        writeNumbered(5, in: folder)
        guard let instance = AppInstance(app: app, info: info) else { return }
        instance.seed(folder: folder)
        guard instance.launch() else { return }
        defer { instance.quit() }
        waitFor("second folder shown", 12) { instance.has("Watching: \(folder.lastPathComponent)") && instance.has("photo-5-purple.jpg") }
        expect(!instance.has("photo-1-red.jpg"), "photos from the first folder remain")
    }

    runCase("A04", "APP", "Operator preferences and log untouched") {
        guard trusted else { throw Skip(reason: missingAccessibility) }
        let after = (fingerprint(realPrefs), fingerprint(realLog))
        expect(before == after, "operator prefs/log changed: \(before) -> \(after)")
    }
}
