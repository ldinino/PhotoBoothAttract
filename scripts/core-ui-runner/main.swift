// Offline CORE UI runner. Built on the development Mac together with the unmodified production
// views/managers (see scripts/build-core-ui-runner.sh); the target needs only this executable.
// Tiers: NATIVE = real SwiftUI views hosted in this process with stub print/Messages sinks;
//        APP = a launched, isolated copy of the supplied app driven through Accessibility.
import AppKit
import SwiftUI
import CryptoKit
import ImageIO
import UniformTypeIdentifiers
import ApplicationServices
import Darwin

final class ErrorLog: ObservableObject {
    static let shared = ErrorLog()
    func log(_ message: String) {}
}

// MARK: - Reporting

struct Skip: Error { let reason: String }
enum Outcome { case pass, fail([String]), skip(String) }

var failures: [String] = []
var outcomes: [(id: String, tier: String, title: String, outcome: Outcome)] = []
var reportLines: [String] = []

func say(_ line: String) {
    let clean = sanitize(line)
    print(clean)
    reportLines.append(clean)
    fflush(stdout)
}

func sanitize(_ text: String) -> String {
    var out = text
    out = out.replacingOccurrences(of: ownedRoot.path, with: "<fixtures>")
    out = out.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    out = out.replacingOccurrences(of: NSUserName(), with: "<user>")
    return out
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() { failures.append(message) }
}

func spin(_ seconds: Double) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }

/// Polls `condition` on the main run loop; a timeout is recorded as a failure that names what never happened.
@discardableResult
func waitFor(_ what: String, _ timeout: Double = 6, _ condition: () -> Bool) -> Bool {
    let end = Date().addingTimeInterval(timeout)
    while Date() < end {
        if condition() { return true }
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.02))
    }
    if condition() { return true }
    failures.append("timed out after \(timeout)s waiting for: \(what)")
    return false
}

func runCase(_ id: String, _ tier: String, _ title: String, _ body: () throws -> Void) {
    if let only = option("--only"), !only.split(separator: ",").contains(Substring(id)) { return }
    failures = []
    var outcome = Outcome.pass
    do { try body() } catch let skip as Skip { outcome = .skip(skip.reason) } catch { failures.append("threw \(error)") }
    if case .pass = outcome, !failures.isEmpty { outcome = .fail(failures) }
    outcomes.append((id, tier, title, outcome))
    switch outcome {
    case .pass: say("PASS \(id) [\(tier)] \(title)")
    case .fail(let reasons): say("FAIL \(id) [\(tier)] \(title)"); reasons.forEach { say("     - \($0)") }
    case .skip(let reason): say("SKIP \(id) [\(tier)] \(title)\n     - \(reason)")
    }
}

// MARK: - Options and owned fixture root

let args = Array(CommandLine.arguments.dropFirst())
func option(_ name: String) -> String? { args.firstIndex(of: name).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } }
if let target = option("--accessibility-worker").flatMap(Int32.init) {
    serveAccessibility(target: target)
    exit(0)
}
let appPath = option("--app")
let reportPath = option("--report")
let selfTest = args.contains("--self-test")
let dumpAX = args.contains("--dump-ax")
let promptAX = args.contains("--prompt-accessibility")
let simulateNoAX = args.contains("--simulate-no-accessibility")

let ownedRoot: URL = {
    let temp = NSTemporaryDirectory()
    let base = URL(fileURLWithPath: realpath(temp, nil).map { String(cString: $0) } ?? temp)
    let root = base.appendingPathComponent("PBA-CoreUI-\(UUID().uuidString.prefix(8))", isDirectory: true)
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}()
var ownedProcess: Process?
var ownedPrefsDomains: [String] = []

/// Restores permissions and removes only what lives beneath the owned root; also stops the app instance this run launched.
func cleanup() {
    stopAccessibilityWorker()
    UserDefaults.standard.removePersistentDomain(forName: ProcessInfo.processInfo.processName)
    if let process = ownedProcess, process.isRunning { process.terminate(); usleep(300_000); if process.isRunning { kill(process.processIdentifier, SIGKILL) } }
    ownedProcess = nil
    for domain in ownedPrefsDomains { UserDefaults.standard.removePersistentDomain(forName: domain) }
    if !ownedPrefsDomains.isEmpty {
        usleep(1_500_000)
        for domain in ownedPrefsDomains {
            try? FileManager.default.removeItem(at: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Preferences/\(domain).plist"))
        }
        ownedPrefsDomains = []
    }
    guard ownedRoot.path.contains("/PBA-CoreUI-") else { return }
    if let walker = FileManager.default.enumerator(at: ownedRoot, includingPropertiesForKeys: nil) {
        for case let url as URL in walker {
            try? FileManager.default.setAttributes([.immutable: false, .posixPermissions: 0o755], ofItemAtPath: url.path)
        }
    }
    try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ownedRoot.path)
    try? FileManager.default.removeItem(at: ownedRoot)
}

var signalSources: [DispatchSourceSignal] = []
for sig in [SIGINT, SIGTERM] {
    signal(sig, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    source.setEventHandler { cleanup(); print("Interrupted; fixtures removed."); exit(130) }
    source.resume()
    signalSources.append(source)
}

// MARK: - Fixtures (CoreGraphics + ImageIO only)

typealias RGB = (r: UInt8, g: UInt8, b: UInt8)
let palette: [RGB] = [(220, 40, 40), (40, 170, 40), (40, 70, 220), (230, 210, 40), (150, 40, 170)]
let colorNames = ["red", "green", "blue", "yellow", "purple"]
let gray: RGB = (128, 128, 128)

func fillRect(_ ctx: CGContext, _ x: Int, _ y: Int, _ w: Int, _ h: Int, _ c: RGB, canvasHeight: Int) {
    ctx.setFillColor(red: CGFloat(c.r) / 255, green: CGFloat(c.g) / 255, blue: CGFloat(c.b) / 255, alpha: 1)
    ctx.fill(CGRect(x: x, y: canvasHeight - y - h, width: w, height: h))
}

/// Top-left white (large), top-right black, bottom-left red, bottom-right bare, so every rotation or mirror is distinguishable.
func draw(_ ctx: CGContext, width w: Int, height h: Int, background: RGB, label: String?) {
    fillRect(ctx, 0, 0, w, h, background, canvasHeight: h)
    let m = Int(Double(min(w, h)) * 0.18)
    fillRect(ctx, 0, 0, m, m, (255, 255, 255), canvasHeight: h)
    fillRect(ctx, w - m * 6 / 10, 0, m * 6 / 10, m * 6 / 10, (0, 0, 0), canvasHeight: h)
    fillRect(ctx, 0, h - m * 6 / 10, m * 6 / 10, m * 6 / 10, (255, 0, 0), canvasHeight: h)
    if let label {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: CGFloat(min(w, h)) * 0.2), .foregroundColor: NSColor.white]
        (label as NSString).draw(at: CGPoint(x: CGFloat(w) * 0.4, y: CGFloat(h) * 0.4), withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()
    }
}

func makeContext(_ w: Int, _ h: Int) -> CGContext {
    CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
}

func writeImage(_ image: CGImage, to url: URL, type: UTType, orientation: Int? = nil, quality: Double = 0.8) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil)!
    var props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
    if let orientation { props[kCGImagePropertyOrientation] = orientation }
    CGImageDestinationAddImage(dest, image, props as CFDictionary)
    precondition(CGImageDestinationFinalize(dest), "fixture write failed")
}

func stamp(_ url: URL, _ date: Date) {
    try? FileManager.default.setAttributes([.creationDate: date, .modificationDate: date], ofItemAtPath: url.path)
}

func makeFolder(_ name: String) -> URL {
    let url = ownedRoot.appendingPathComponent("\(name)-\(UUID().uuidString.prefix(6))", isDirectory: true)
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

let epoch = Date().addingTimeInterval(-3_600)

/// Writes numbered fixture `n` (1...5) so its creation date orders it after every lower number.
@discardableResult
func writeNumbered(_ n: Int, in folder: URL, name: String? = nil, color: Int? = nil, png: Bool = false, portrait: Bool = false) -> URL {
    let w = portrait ? 480 : 640, h = portrait ? 640 : 480
    let ctx = makeContext(w, h)
    draw(ctx, width: w, height: h, background: palette[(color ?? n - 1) % 5], label: "\(n)")
    let url = folder.appendingPathComponent(name ?? "photo-\(n)-\(colorNames[(n - 1) % 5]).\(png ? "png" : "jpg")")
    writeImage(ctx.makeImage()!, to: url, type: png ? .png : .jpeg)
    stamp(url, epoch.addingTimeInterval(Double(n) * 10))
    return url
}

/// Sequential, one reused 5000x3500 bitmap, so memory stays near one frame.
func writeLargeSet(count: Int, in folder: URL) {
    let w = 5000, h = 3500
    let ctx = makeContext(w, h)
    for i in 1...count {
        autoreleasepool {
            draw(ctx, width: w, height: h, background: palette[i % 5], label: "\(i)")
            let url = folder.appendingPathComponent(String(format: "large-%02d.jpg", i))
            writeImage(ctx.makeImage()!, to: url, type: .jpeg, quality: 0.5)
            stamp(url, epoch.addingTimeInterval(Double(i)))
        }
    }
}

func sha(_ url: URL) -> String { SHA256.hash(data: (try? Data(contentsOf: url)) ?? Data()).map { String(format: "%02x", $0) }.joined() }

// MARK: - Pixels and classification

struct Pixels {
    let w: Int, h: Int, data: [UInt8]
    init(_ image: CGImage) {
        w = image.width; h = image.height
        var buffer = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &buffer, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        data = buffer
    }
    func at(_ x: Int, _ y: Int) -> RGB { let i = (min(max(y, 0), h - 1) * w + min(max(x, 0), w - 1)) * 4; return (data[i], data[i + 1], data[i + 2]) }
}

func distance(_ a: RGB, _ b: RGB) -> Int { abs(Int(a.r) - Int(b.r)) + abs(Int(a.g) - Int(b.g)) + abs(Int(a.b) - Int(b.b)) }

/// Nearest fixture colour, or "black"; guest watermark tints and number overlays stay closer to their own colour than to the others.
func classify(_ c: RGB) -> String {
    if Int(c.r) + Int(c.g) + Int(c.b) < 45 { return "black" }
    return colorNames[(0..<5).min { distance(palette[$0], c) < distance(palette[$1], c) }!]
}

func rep(of view: NSView) -> NSBitmapImageRep {
    view.layoutSubtreeIfNeeded()
    let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    view.cacheDisplay(in: view.bounds, to: rep)
    return rep
}

/// Samples a 3x3 grid in the middle of `rect` (top-left origin view points) and returns the majority class.
func sampleClass(_ rep: NSBitmapImageRep, view: NSView, rect: CGRect) -> String {
    let scale = CGFloat(rep.pixelsWide) / view.bounds.width
    var votes: [String: Int] = [:]
    for fx in [0.4, 0.5, 0.6] {
        for fy in [0.4, 0.5, 0.6] {
            let px = Int((rect.minX + rect.width * fx) * scale), py = Int((rect.minY + rect.height * fy) * scale)
            guard let c = rep.colorAt(x: px, y: py)?.usingColorSpace(.deviceRGB) else { continue }
            votes[classify((UInt8(c.redComponent * 255), UInt8(c.greenComponent * 255), UInt8(c.blueComponent * 255))), default: 0] += 1
        }
    }
    return votes.max { $0.value < $1.value }?.key ?? "none"
}

// MARK: - Accessibility of hosted windows (external client, never self-process AX)

struct AXNode: Codable {
    let object: Int
    let role: String, label: String, frame: CGRect, enabled: Bool, inSheet: Bool
}

enum AXOperation: String, Codable { case tree, press, enabled }
struct AXRequest: Codable {
    let operation: AXOperation
    var title: String? = nil
    var object: Int? = nil
}
struct AXReply: Codable {
    var nodes: [AXNode] = []
    var accepted = false
    var enabled: Bool? = nil
    var error: String? = nil
}

func serveAccessibility(target: pid_t) {
    precondition(target != getpid())
    signal(SIGTERM, SIG_DFL)
    signal(SIGINT, SIG_DFL)
    let app = AXUIElementCreateApplication(target)
    AXUIElementSetMessagingTimeout(app, 5)
    var objects: [AXUIElement] = []
    while let line = readLine(), let data = line.data(using: .utf8) {
        var reply = AXReply()
        do {
            let request = try JSONDecoder().decode(AXRequest.self, from: data)
            switch request.operation {
            case .tree:
                if let window = (axValue(app, kAXWindowsAttribute) as? [AXUIElement])?.first(where: { (axValue($0, kAXTitleAttribute) as? String) == request.title }) {
                    axCollect(window, 0, false, &reply.nodes, &objects)
                }
            case .press, .enabled:
                if let index = request.object, objects.indices.contains(index) {
                    if request.operation == .press {
                        let element = objects[index]
                        DispatchQueue.global().async {
                            AXUIElementPerformAction(element, kAXPressAction as CFString)
                        }
                        reply.accepted = true
                    } else {
                        reply.enabled = axValue(objects[index], kAXEnabledAttribute) as? Bool
                    }
                } else { reply.error = "Accessibility element is no longer available" }
            }
        } catch { reply.error = "Accessibility request could not be decoded: \(error.localizedDescription)" }
        guard let response = try? JSONEncoder().encode(reply) else { exit(3) }
        FileHandle.standardOutput.write(response + Data([10]))
    }
}

let accessibilityIO = DispatchQueue(label: "core-ui-accessibility")
var accessibilityProcess: Process?
var accessibilityInput: FileHandle?
var accessibilityOutput: FileHandle?

func stopAccessibilityWorker() {
    try? accessibilityInput?.close()
    if let process = accessibilityProcess {
        if process.isRunning { process.terminate() }
        process.waitUntilExit()
    }
    try? accessibilityOutput?.close()
    accessibilityProcess = nil
    accessibilityInput = nil
    accessibilityOutput = nil
}

func accessibilityRequest(_ request: AXRequest) -> AXReply? {
    if accessibilityProcess?.isRunning != true {
        stopAccessibilityWorker()
        let process = Process(), input = Pipe(), output = Pipe()
        process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        process.arguments = ["--accessibility-worker", String(getpid())]
        process.standardInput = input
        process.standardOutput = output
        do { try process.run() } catch {
            failures.append("could not start Accessibility worker: \(error.localizedDescription)")
            return nil
        }
        accessibilityProcess = process
        accessibilityInput = input.fileHandleForWriting
        accessibilityOutput = output.fileHandleForReading
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
    }
    guard let input = accessibilityInput, let output = accessibilityOutput else { return nil }
    let reply: AXReply? = onBackground(nil) {
        accessibilityIO.sync {
            do {
                try input.write(contentsOf: JSONEncoder().encode(request) + Data([10]))
                var response = Data()
                while !response.contains(10) {
                    let chunk = output.availableData
                    guard !chunk.isEmpty else { return AXReply(error: "Accessibility worker exited before replying") }
                    response.append(chunk)
                }
                return try JSONDecoder().decode(AXReply.self, from: response.prefix { $0 != 10 })
            } catch { return AXReply(error: "Accessibility worker communication failed: \(error.localizedDescription)") }
        }
    }
    if reply == nil {
        failures.append("Accessibility worker timed out during \(request.operation.rawValue)")
        stopAccessibilityWorker()
    }
    if let error = reply?.error { failures.append(error) }
    return reply
}

/// Only pipe I/O runs in the background; the hosted UI keeps serving external AX requests on main.
func onBackground<T>(_ fallback: T, _ work: @escaping () -> T) -> T {
    var result: T?
    let completed = DispatchSemaphore(value: 0)
    DispatchQueue.global().async { result = work(); completed.signal() }
    let end = Date().addingTimeInterval(15)
    while Date() < end {
        if completed.wait(timeout: .now()) == .success { return result ?? fallback }
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
    }
    return fallback
}

func axCollect(_ e: AXUIElement, _ depth: Int, _ inSheet: Bool, _ out: inout [AXNode], _ objects: inout [AXUIElement]) {
    guard depth < 40 else { return }
    let role = (axValue(e, kAXRoleAttribute) as? String) ?? ""
    let label = [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXHelpAttribute]
        .compactMap { axValue(e, $0) as? String }.filter { !$0.isEmpty }.joined(separator: " | ")
    let enabled = (axValue(e, kAXEnabledAttribute) as? Bool) ?? true
    let index = objects.count
    objects.append(e)
    out.append(AXNode(object: index, role: role, label: label, frame: axFrame(e) ?? .zero, enabled: enabled, inSheet: inSheet))
    for child in (axValue(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] { axCollect(child, depth + 1, inSheet || role == kAXSheetRole, &out, &objects) }
}

func tree(_ window: NSWindow, sheetsOnly: Bool = false) -> [AXNode] {
    let all = accessibilityRequest(AXRequest(operation: .tree, title: window.title))?.nodes ?? []
    return sheetsOnly ? all.filter { $0.inSheet } : all
}

func nodes(_ window: NSWindow, _ needle: String, role: String? = nil, sheetsOnly: Bool = false) -> [AXNode] {
    tree(window, sheetsOnly: sheetsOnly).filter { $0.label.contains(needle) && (role == nil || $0.role == role) }
}

func hasText(_ window: NSWindow, _ needle: String) -> Bool { !nodes(window, needle).isEmpty }

/// Presses the `index`th button (top to bottom) whose label contains `needle`.
@discardableResult
func press(_ window: NSWindow, _ needle: String, index: Int = 0, sheetsOnly: Bool = false) -> Bool {
    let buttons = nodes(window, needle, role: kAXButtonRole, sheetsOnly: sheetsOnly).sorted { $0.frame.minY < $1.frame.minY }
    guard index < buttons.count else { failures.append("no button containing '\(needle)'\(index > 0 ? " #\(index)" : "")"); return false }
    return accessibilityRequest(AXRequest(operation: .press, object: buttons[index].object))?.accepted == true
}

func dumpTree(_ window: NSWindow) {
    for n in tree(window) { print("  [\(n.role)] '\(n.label)' en=\(n.enabled) sheet=\(n.inSheet) \(n.frame)") }
}


final class StubSinks {
    var prints: [(data: Data, name: String)] = []
    var shares: [(data: Data, name: String, recipient: String?)] = []
    var order: [String] = []
    var printResults: [Bool] = []
    var during: (() -> Void)?
    var sinks: ActionSinks {
        ActionSinks(
            print: { [self] data, name in
                prints.append((data, name)); order.append("print")
                during?()
                return printResults.isEmpty ? true : printResults.removeFirst()
            },
            share: { [self] data, name, recipient in during?(); shares.append((data, name, recipient)); order.append("share") })
    }
    func reset() { prints = []; shares = []; order = []; printResults = []; during = nil }
}
let stub = StubSinks()

// MARK: - Hosting

final class Host {
    let manager: PhotoManager
    let camera = SonyCameraManager()
    var assistant: NSWindow?
    var guest: NSWindow?

    init(folder: URL?) {
        manager = PhotoManager()
        if let folder { manager.setWatchedFolder(folder) }
    }

    func showAssistant(width: CGFloat = 1024, height: CGFloat = 768) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 40, y: 80, width: width, height: height), styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "CoreUI Assistant"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: AssistantView().environmentObject(manager).environmentObject(camera))
        window.makeKeyAndOrderFront(nil)
        assistant = window
        spin(0.4)
        if dumpAX { dumpTree(window) }
        return window
    }

    func showGuest(width: CGFloat, height: CGFloat) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 60, y: 60, width: width, height: height), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "CoreUI Guest"
        window.contentView = NSHostingView(rootView: GuestView().environmentObject(manager))
        window.orderFront(nil)
        guest = window
        spin(0.3)
        return window
    }

    func close() {
        for window in [assistant, guest].compactMap({ $0 }) {
            window.attachedSheet.map { window.endSheet($0) }
            window.orderOut(nil)
        }
        stopAccessibilityWorker()
        manager.setWatchedFolder(makeFolder("parked"))
        spin(0.2)
    }
}

func names(_ manager: PhotoManager) -> [String] { manager.photos.map { $0.url.lastPathComponent } }

// MARK: - Environment report and isolation

func sysctlString(_ name: String) -> String {
    var size = 0
    sysctlbyname(name, nil, &size, nil, 0)
    var buffer = [CChar](repeating: 0, count: size)
    sysctlbyname(name, &buffer, &size, nil, 0)
    return String(cString: buffer)
}

func environmentReport(appInfo: [String: Any]?) {
    var translated: Int32 = 0
    var size = MemoryLayout<Int32>.size
    sysctlbyname("sysctl.proc_translated", &translated, &size, nil, 0)
    say("Runner: \(buildRevision) (\(buildDate))")
    say("Architecture: \(sysctlString("hw.machine"))\(translated == 1 ? " (RUNNING UNDER ROSETTA - not a native result)" : ", native")")
    say("Hardware model: \(sysctlString("hw.model"))")
    say("OS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
    say("Displays: \(NSScreen.screens.count)")
    if let appInfo {
        say("App: \(appInfo["CFBundleShortVersionString"] ?? "?") (build \(appInfo["CFBundleVersion"] ?? "?"))")
    } else {
        say("App: none supplied")
    }
}

func fingerprint(_ url: URL) -> String {
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else { return "absent" }
    return "\(attrs[.size] ?? 0)@\(attrs[.modificationDate] ?? "")"
}

let realLog = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/PhotoBoothAttract/PhotoBoothAttract.log")

// MARK: - Cases: native views

let bookmarkKey = "watchedFolderBookmark"
var axActive = false

/// Hosted-view cases read and press real controls through the Accessibility API, which needs the permission.
func requireAX() throws {
    guard accessibilityTrusted() else { throw Skip(reason: missingAccessibility) }
    axActive = true
}


func guestExpectations(_ manager: PhotoManager, _ expected: [String?], _ window: NSWindow, label: String) {
    let view = window.contentView!
    var observed: [String] = []
    let matches = {
        let rep = rep(of: view)
        let cw = view.bounds.width / 2, ch = view.bounds.height / 2
        observed = (0..<4).map { q in sampleClass(rep, view: view, rect: CGRect(x: CGFloat(q % 2) * cw, y: CGFloat(q / 2) * ch, width: cw, height: ch)) }
        return observed == (0..<4).map { expected.indices.contains($0) ? (expected[$0] ?? "black") : "black" }
    }
    if !waitFor("\(label): quadrants \((0..<4).map { expected.indices.contains($0) ? expected[$0] ?? "black" : "black" })", 4, matches) {
        failures[failures.count - 1] += " (observed \(observed))"
    }
}

func nativeCases() {
    ActionSinks.live = stub.sinks
    _ = ActionSinks.live.print(Data(), "probe")
    let stubbed = stub.prints.count == 1
    stub.reset()
    guard stubbed else { say("ABORT: live print sink was not replaced by the stub; refusing to run actions."); cleanup(); exit(3) }

    // Saved folder restoration must run before any other PhotoManager exists.
    runCase("N01", "NATIVE", "Isolated saved-folder restoration; empty state") {
        try requireAX()
        let defaults = UserDefaults.standard
        expect(defaults.data(forKey: bookmarkKey) == nil, "runner preferences domain was not clean")
        let empty = Host(folder: nil)
        let window = empty.showAssistant()
        expect(hasText(window, "No photos yet"), "empty assistant message missing")
        expect(nodes(window, "Restart file watcher", role: "AXButton").first?.enabled != true && empty.manager.watchedFolderURL == nil, "refresh enabled with no folder")
        let guest = empty.showGuest(width: 800, height: 600)
        expect(hasText(guest, "Waiting for photos"), "guest waiting message missing")
        empty.close()

        let folder = makeFolder("restore")
        writeNumbered(1, in: folder); writeNumbered(2, in: folder)
        defaults.set(try! folder.bookmarkData(), forKey: bookmarkKey)
        let restored = Host(folder: nil)
        waitFor("restored folder lists 2 photos", 6) { restored.manager.photos.count == 2 }
        expect(restored.manager.watchedFolderURL?.resolvingSymlinksInPath().path == folder.resolvingSymlinksInPath().path, "restored folder differs from saved bookmark")
        restored.close()
        defaults.removeObject(forKey: bookmarkKey)
    }

    runCase("N02", "NATIVE", "Folder switch, refresh, live arrival, incomplete write, replacement, disappearance (real filesystem)") {
        try requireAX()
        let a = makeFolder("A"), b = makeFolder("B")
        writeNumbered(1, in: a); writeNumbered(2, in: b)
        let host = Host(folder: a)
        let window = host.showAssistant()
        waitFor("A lists photo-1", 6) { names(host.manager) == ["photo-1-red.jpg"] }
        host.manager.setWatchedFolder(b)
        waitFor("switch to B lists only photo-2", 6) { names(host.manager) == ["photo-2-green.jpg"] }
        press(window, "Restart file watcher")
        waitFor("refresh finished", 6) { !host.manager.isRefreshing }
        expect(names(host.manager) == ["photo-2-green.jpg"], "refresh changed the list: \(names(host.manager))")

        writeNumbered(3, in: b)
        waitFor("live arrival", 6) { names(host.manager) == ["photo-3-blue.jpg", "photo-2-green.jpg"] }
        expect(hasText(window, "photo-3-blue.jpg"), "assistant row for the arrival is not visible")

        let partial = b.appendingPathComponent("partial.jpg")
        try! Data([1, 2, 3, 4, 5]).write(to: partial)
        spin(1.2)
        expect(!names(host.manager).contains("partial.jpg"), "incomplete write was published")
        let whole = writeNumbered(4, in: makeFolder("scratch"))
        try! FileManager.default.removeItem(at: partial)
        try! FileManager.default.copyItem(at: whole, to: partial)
        stamp(partial, epoch.addingTimeInterval(500))
        waitFor("incomplete write publishes once complete", 8) { names(host.manager).filter { $0 == "partial.jpg" }.count == 1 }

        let target = b.appendingPathComponent("photo-3-blue.jpg")
        let before = host.manager.photos.first { $0.url == target }?.digest
        try! FileManager.default.removeItem(at: target)
        writeNumbered(3, in: b, color: 4)
        waitFor("replacement changes the digest, keeping one row", 8) {
            let rows = host.manager.photos.filter { $0.url == target }
            return rows.count == 1 && rows[0].digest != before
        }
        try? FileManager.default.removeItem(at: target)
        waitFor("disappearing file leaves the list", 8) { !names(host.manager).contains("photo-3-blue.jpg") }
        host.close()
    }

    runCase("N03", "NATIVE", "Distinct actions, stable selection, stale source (stub sinks)") {
        try requireAX()
        let folder = makeFolder("actions")
        for n in 1...3 { writeNumbered(n, in: folder) }
        let originals = (1...3).map { sha(folder.appendingPathComponent("photo-\($0)-\(colorNames[$0 - 1]).jpg")) }
        let host = Host(folder: folder)
        let window = host.showAssistant()
        waitFor("3 rows", 6) { host.manager.photos.count == 3 && hasText(window, "photo-1-red.jpg") }
        stub.reset()

        press(window, "Print Only", index: 1)
        waitFor("print only reaches the print sink", 4) { stub.prints.count == 1 }
        expect(stub.prints.first?.name == "photo-2-green.jpg" && stub.shares.isEmpty, "Print only: \(stub.prints.map { $0.name }) shares \(stub.shares.count)")

        stub.reset()
        press(window, "Digital Only", index: 1)
        waitFor("digital sheet opens", 4) { window.attachedSheet != nil && hasText(window, "Send without number") }
        writeNumbered(4, in: folder)
        writeNumbered(5, in: folder)
        waitFor("two arrivals while the sheet is open", 8) { host.manager.photos.count == 5 }
        press(window, "Send without number", sheetsOnly: true)
        waitFor("digital reaches the share sink", 4) { stub.shares.count == 1 }
        expect(stub.shares.first?.name == "photo-2-green.jpg" && stub.prints.isEmpty && stub.shares.first?.recipient == nil, "Digital only target: \(stub.shares.map { $0.name })")
        expect(stub.shares.first.map { SHA256.hash(data: $0.data).map { String(format: "%02x", $0) }.joined() } == originals[1], "shared bytes differ from the selected photo")
        waitFor("sheet dismissed after success", 4) { window.attachedSheet == nil }

        stub.reset()
        press(window, "Print & Digital", index: 0)
        waitFor("print & digital sheet", 4) { window.attachedSheet != nil && hasText(window, "Send without number") }
        press(window, "Send without number", sheetsOnly: true)
        waitFor("print then share", 4) { stub.order == ["print", "share"] }
        waitFor("sheet dismissed", 4) { window.attachedSheet == nil }
        expect(stub.prints.first?.name == "photo-5-purple.jpg", "Print & Digital used \(stub.prints.first?.name ?? "nothing")")

        stub.reset()
        let target = folder.appendingPathComponent("photo-1-red.jpg")
        let before = host.manager.photos.first { $0.url == target }?.digest
        try! FileManager.default.removeItem(at: target)
        writeNumbered(1, in: folder, color: 3)
        stamp(target, epoch.addingTimeInterval(10))
        press(window, "Print Only", index: host.manager.photos.firstIndex { $0.url == target } ?? 4)
        waitFor("stale source blocks the action and explains", 6) { hasText(window, "replaced after you selected") }
        expect(stub.prints.isEmpty && stub.shares.isEmpty, "stale source still reached a sink (prints \(stub.prints.map { $0.name }), shares \(stub.shares.count))")
        expect(before != nil, "no digest recorded for the selected photo")
        press(window, "OK", sheetsOnly: true)

        for (i, original) in originals.enumerated() where i > 0 {
            expect(sha(folder.appendingPathComponent("photo-\(i + 1)-\(colorNames[i]).jpg")) == original, "original photo-\(i + 1) changed")
        }
        host.close()
    }

    runCase("N04", "NATIVE", "Print failure retention, retry, cancel; pending protection; late completion of A cannot dismiss B") {
        try requireAX()
        let folder = makeFolder("failure")
        for n in 1...3 { writeNumbered(n, in: folder) }
        let host = Host(folder: folder)
        let window = host.showAssistant()
        waitFor("3 rows", 6) { host.manager.photos.count == 3 && hasText(window, "photo-1-red.jpg") }
        stub.reset()

        press(window, "Print & Digital", index: 0)
        waitFor("sheet", 4) { window.attachedSheet != nil && hasText(window, "Send without number") }
        stub.printResults = [false]
        press(window, "Send without number", sheetsOnly: true)
        waitFor("failure message kept in the sheet", 4) { hasText(window, "could not be queued") }
        expect(window.attachedSheet != nil && stub.shares.isEmpty, "failure dismissed the sheet or shared anyway")
        press(window, "Send without number", sheetsOnly: true)
        waitFor("retry succeeds", 4) { stub.shares.count == 1 && window.attachedSheet == nil }
        expect(stub.prints.count == 2, "retry printed \(stub.prints.count) times")

        stub.reset(); stub.printResults = [false]
        press(window, "Print & Digital", index: 0)
        waitFor("sheet again", 4) { window.attachedSheet != nil && hasText(window, "Send without number") }
        press(window, "Send without number", sheetsOnly: true)
        waitFor("failure shown", 4) { hasText(window, "could not be queued") }
        press(window, "Cancel", sheetsOnly: true)
        waitFor("cancel dismisses after failure", 4) { window.attachedSheet == nil }
        expect(stub.shares.isEmpty, "cancel after failure shared")

        stub.reset()
        let rows = nodes(window, "Digital Only", role: kAXButtonRole).sorted { $0.frame.minY < $1.frame.minY }
        guard rows.count > 2 else { failures.append("expected 3 'Digital Only' buttons, found \(rows.count)"); host.close(); return }
        let rowB = rows[2].object
        press(window, "Digital Only", index: 0)
        waitFor("sheet A", 4) { window.attachedSheet != nil && hasText(window, "photo-3-blue.jpg") }
        let cancelA = nodes(window, "Cancel", role: kAXButtonRole, sheetsOnly: true).first?.object

        stub.during = {
            stub.during = nil
            spin(0.3)
            let enabled = cancelA.flatMap { accessibilityRequest(AXRequest(operation: .enabled, object: $0))?.enabled }
            if enabled != false { failures.append("Cancel enabled state while A is pending: \(String(describing: enabled))") }
            let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.attachedSheet?.windowNumber ?? 0,
                                          context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
            _ = window.attachedSheet?.performKeyEquivalent(with: escape)
            if let cancelA { _ = accessibilityRequest(AXRequest(operation: .press, object: cancelA)) }
            spin(0.3)
            if window.attachedSheet == nil { failures.append("Escape or Cancel dismissed a pending sheet") }
            _ = accessibilityRequest(AXRequest(operation: .press, object: rowB))
            spin(0.5)
        }
        press(window, "Send without number", sheetsOnly: true)
        waitFor("A's completion arrives", 6) { stub.shares.count == 1 }
        spin(0.5)
        expect(stub.shares.first?.name == "photo-3-blue.jpg", "A shared \(stub.shares.first?.name ?? "nothing")")
        let sheetNames = tree(window, sheetsOnly: true).map { $0.label }.filter { $0.contains(".jpg") }
        expect(window.attachedSheet != nil && sheetNames == ["photo-1-red.jpg"], "late completion of A dismissed request B (sheet \(window.attachedSheet != nil): \(sheetNames))")
        press(window, "Cancel", sheetsOnly: true)
        waitFor("B cancels", 4) { window.attachedSheet == nil }
        host.close()
    }

    runCase("N05", "NATIVE", "Clear: cancel, confirm, empty clear, partial failure keeps survivors") {
        try requireAX()
        let folder = makeFolder("clear")
        for n in 1...4 { writeNumbered(n, in: folder) }
        let keep = ownedRoot.appendingPathComponent("outside-sentinel.jpg")
        writeNumbered(5, in: ownedRoot, name: "outside-sentinel.jpg")
        let host = Host(folder: folder)
        let window = host.showAssistant()
        waitFor("4 rows", 6) { host.manager.photos.count == 4 && hasText(window, "photo-1-red.jpg") }

        press(window, "Clear Photo Queue")
        waitFor("confirmation", 4) { hasText(window, "Delete All") }
        press(window, "Cancel", sheetsOnly: true)
        waitFor("confirmation dismissed", 4) { window.attachedSheet == nil }
        expect(host.manager.photos.count == 4 && FileManager.default.contents(atPath: folder.path + "/photo-1-red.jpg") != nil, "cancel removed photos")

        let locked = ["photo-1-red.jpg", "photo-2-green.jpg"].map { folder.appendingPathComponent($0) }
        locked.forEach { try! FileManager.default.setAttributes([.immutable: true], ofItemAtPath: $0.path) }
        press(window, "Clear Photo Queue")
        waitFor("confirmation", 4) { hasText(window, "Delete All") }
        press(window, "Delete All", sheetsOnly: true)
        waitFor("partial result visible", 8) { hasText(window, "partly cleared") }
        expect(hasText(window, "Deleted 2, but 2 photo"), "partial message does not state 2 deleted / 2 remaining")
        press(window, "OK", sheetsOnly: true)
        waitFor("survivors keep their rows", 6) { Set(names(host.manager)) == ["photo-1-red.jpg", "photo-2-green.jpg"] && !host.manager.isClearing }
        expect(locked.allSatisfy { FileManager.default.fileExists(atPath: $0.path) }, "locked survivors vanished from disk")
        expect(!FileManager.default.fileExists(atPath: folder.path + "/photo-3-blue.jpg"), "unlocked file was not deleted")
        locked.forEach { try! FileManager.default.setAttributes([.immutable: false], ofItemAtPath: $0.path) }

        press(window, "Clear Photo Queue")
        waitFor("confirmation", 4) { hasText(window, "Delete All") }
        press(window, "Delete All", sheetsOnly: true)
        waitFor("full clear result", 8) { hasText(window, "Folder cleared") }
        press(window, "OK", sheetsOnly: true)
        waitFor("list empty", 6) { host.manager.photos.isEmpty }

        press(window, "Clear Photo Queue")
        waitFor("confirmation", 4) { hasText(window, "Delete All") }
        press(window, "Delete All", sheetsOnly: true)
        waitFor("empty clear result", 6) { hasText(window, "Deleted 0 photos") }
        press(window, "OK", sheetsOnly: true)
        expect(FileManager.default.fileExists(atPath: keep.path), "file outside the watched folder was deleted")
        host.close()
    }

    runCase("N06", "NATIVE", "Guest grid counts 0-5 at 800x600 and 1280x720: arrivals, removal, resize (sampled pixels)") {
        let folder = makeFolder("grid")
        let host = Host(folder: folder)
        let sizes: [(CGFloat, CGFloat)] = [(800, 600), (1280, 720)]
        var files: [URL] = []
        var window = host.showGuest(width: 800, height: 600)
        func check(_ label: String) {
            let expected = Array(files.reversed().prefix(4)).map { classify(palette[(Int($0.lastPathComponent.split(separator: "-")[1])! - 1) % 5]) }
            for (w, h) in sizes {
                window.setContentSize(NSSize(width: w, height: h))
                spin(0.2)
                guestExpectations(host.manager, expected, window, label: "\(label) at \(Int(w))x\(Int(h))")
            }
        }
        waitFor("empty grid", 3) { host.manager.photos.isEmpty }
        guestExpectations(host.manager, [], window, label: "0 photos")
        for n in 1...5 {
            files.append(writeNumbered(n, in: folder))
            waitFor("manager holds \(n)", 6) { host.manager.photos.count == n }
            check("\(n) photo(s)")
        }
        try! FileManager.default.removeItem(at: files.removeLast())
        waitFor("newest removed", 6) { host.manager.photos.count == 4 }
        check("after removing newest")
        try! FileManager.default.removeItem(at: files.remove(at: 1))
        waitFor("middle removed", 6) { host.manager.photos.count == 3 }
        check("after removing a middle photo")
        for url in files { try! FileManager.default.removeItem(at: url) }
        waitFor("grid emptied", 6) { host.manager.photos.isEmpty }
        window.setContentSize(NSSize(width: 800, height: 600))
        guestExpectations(host.manager, [], window, label: "emptied grid at 800x600")
        host.close()
    }

    runCase("N07", "NATIVE", "Assistant badge 1-4 sits on the same photo (pixels) as guest position 1-4") {
        try requireAX()
        let folder = makeFolder("badges")
        for n in 1...5 { writeNumbered(n, in: folder) }
        let host = Host(folder: folder)
        let window = host.showAssistant()
        waitFor("5 photos listed", 8) { host.manager.photos.count == 5 && hasText(window, "photo-5-purple.jpg") }
        let view = window.contentView!
        let bitmap = rep(of: view)
        for rank in 1...4 {
            let badge = nodes(window, "\(rank)").filter { $0.role == "AXStaticText" && $0.label == "\(rank)" }.first
            guard let badge else { failures.append("badge \(rank) not found"); continue }
            let content = window.contentRect(forFrameRect: window.frame)
            let primaryHeight = NSScreen.screens[0].frame.height
            let local = CGRect(x: badge.frame.minX - content.minX, y: badge.frame.minY - (primaryHeight - content.maxY), width: badge.frame.width, height: badge.frame.height)
            let rect = CGRect(x: local.maxX + 8, y: local.minY + 8, width: 90, height: 70)
            let seen = sampleClass(bitmap, view: view, rect: rect)
            let want = colorNames[(Int(host.manager.photos[rank - 1].url.lastPathComponent.split(separator: "-")[1])! - 1) % 5]
            expect(seen == want, "badge \(rank): thumbnail pixels are \(seen), guest position \(rank) is \(want)")
        }
        host.close()
    }
}


// MARK: - Driver

let manualChecks = [
    "Physical 4x6 print on the configured printer (separately authorized; a queued job is not a printed photo)",
    "Messages draft opens with the right image and recipient (separately authorized; never press Send)",
    "Messages drafts, addressed and recipient-free, on Intel and Apple Silicon with a synthetic photo: configured text above the photo, or photo only when the text is blank (separately authorized; never press Send)",
    "Messages attachment metadata with a synthetic photo carrying Artist, Copyright and dummy GPS: export the draft file under both GPS settings and compare sanitized fields (Artist, Copyright, orientation, dimensions, GPS present or absent) with the source",
    "Recipient-copy metadata retention through Messages and carriers (separately authorized delivery evidence; an exported file does not show it)",
    "NSOpenPanel 'Select Folder' flow",
    "Intel Mac responsiveness with the real TV and a live camera/Sony Image Desktop folder",
    "Secondary display unplug/replug and resolution change on the TV",
]

func selfTestCases() {
    runCase("S1", "SELF", "failed assertion is reported") { expect(1 == 2, "deliberate failure") }
    runCase("S2", "SELF", "timeout is reported with its cause") { waitFor("a condition that never happens", 0.3) { false } }
    runCase("S3", "SELF", "skip is reported") { throw Skip(reason: "deliberate skip") }
    runCase("S4", "SELF", "cleanup restores permissions and removes fixtures") {
        let dir = makeFolder("locked")
        let file = dir.appendingPathComponent("held.txt")
        try! Data([1]).write(to: file)
        try! FileManager.default.setAttributes([.immutable: true], ofItemAtPath: file.path)
        try! FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: dir.path)
    }
    cleanup()
    let ok = outcomes.count == 4
        && { if case .fail(let r) = outcomes[0].outcome { return r == ["deliberate failure"] } else { return false } }()
        && { if case .fail(let r) = outcomes[1].outcome { return r.first?.hasPrefix("timed out after 0.3s waiting for: a condition") == true } else { return false } }()
        && { if case .skip = outcomes[2].outcome { return true } else { return false } }()
        && !FileManager.default.fileExists(atPath: ownedRoot.path)
    say(ok ? "SELF-TEST OK: failures, timeouts and skips are reported; locked fixtures were cleaned up" : "SELF-TEST FAILED: reporting or cleanup is wrong")
    exit(ok ? 0 : 1)
}

setenv("TMPDIR", ownedRoot.path + "/tmp/", 1)
try? FileManager.default.createDirectory(atPath: ownedRoot.path + "/tmp", withIntermediateDirectories: true)

let application = NSApplication.shared
application.setActivationPolicy(.accessory)
application.finishLaunching()
application.activate(ignoringOtherApps: true)
UserDefaults.standard.removePersistentDomain(forName: ProcessInfo.processInfo.processName)

var appURL: URL?
var appInfo: [String: Any]?
if let appPath {
    appURL = URL(fileURLWithPath: appPath)
    appInfo = NSDictionary(contentsOf: appURL!.appendingPathComponent("Contents/Info.plist")) as? [String: Any]
    if appInfo == nil { say("ABORT: \(appPath) is not an app bundle (no Contents/Info.plist)."); cleanup(); exit(3) }
}

let knownCases = selfTest ? (1...4).map { "S\($0)" } : (1...11).map { String(format: "N%02d", $0) } + (1...4).map { "A0\($0)" }
if let only = option("--only") {
    let tokens = only.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
    let bad = tokens.filter { !knownCases.contains($0) }
    if !bad.isEmpty {
        print("ABORT: invalid case id(s) [\(bad.joined(separator: ", "))]. Valid\(selfTest ? " with --self-test" : ""): \(knownCases.joined(separator: " "))")
        cleanup(); exit(3)
    }
}

say("PhotoBoothAttract CORE UI runner")
environmentReport(appInfo: appInfo)
say("Isolation: runner preferences domain '\(ProcessInfo.processInfo.processName)'; fixtures under an owned temporary root; app cases use a copy with its own bundle identifier and HOME")
say("")

if selfTest { selfTestCases() }

nativeCases()
moreCases()
appCases(app: appURL, info: appInfo)
cleanup()

let fails = outcomes.filter { if case .fail = $0.outcome { return true } else { return false } }.count
let skips = outcomes.filter { if case .skip = $0.outcome { return true } else { return false } }.count
say("")
say("Summary: \(outcomes.count - fails - skips) PASS, \(fails) FAIL, \(skips) SKIP")
say("Manual checks NOT performed by this runner:")
manualChecks.forEach { say("  - \($0)") }
let verdict = fails > 0 ? "FAILED" : skips > 0 ? "INCOMPLETE (skipped cases are not passes)" : "all automated cases passed; manual checks still pending"
say("Result: \(verdict)")
if let reportPath {
    do { try reportLines.joined(separator: "\n").write(toFile: reportPath, atomically: true, encoding: .utf8) } catch {
        print("ERROR: could not write the report: \(error.localizedDescription)")
        exit(3)
    }
}
exit(fails > 0 ? 1 : skips > 0 ? 2 : 0)
