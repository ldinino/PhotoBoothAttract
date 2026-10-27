#!/bin/bash
# CORE-001/CORE-002 regression checks. Compiles the real PhotoManager/PhotoModel/PrintManager/
# MessageManager with a logging stub, so no app log, printer or Messages is touched. Actions run
# against stub sinks. Synthetic images only, in disposable temp folders.
# LIFECYCLE_MUTANT=release|current|clear breaks FolderLifecycle on purpose; the checks must then fail.
# LIFECYCLE_MUTANT=url|stale|watermark|mainread: URL-only identity | older revision wins | unchanged reads
# do not advance ordering | verification reads on the main thread.
set -euo pipefail

SRC="$(cd "$(dirname "$0")/../PhotoBoothAttract" && pwd)"
WORK="$(mktemp -d /tmp/folder-lifecycle-checks.XXXXXX)"
EXE="folder-lifecycle-checks"
trap 'rm -rf "$WORK"; defaults delete "$EXE" >/dev/null 2>&1 || true' EXIT

sed -E 's/private (func|var|let)/\1/' "$SRC/PhotoManager.swift" > "$WORK/PhotoManager.swift"
case "${LIFECYCLE_MUTANT:-}" in
    release) sed -i '' 's/guard claims\[url\] == generation else { return false }/guard true else { return false }/' "$WORK/PhotoManager.swift" ;;
    url) sed -i '' 's/photo.digest == current.digest/true/' "$WORK/PhotoManager.swift" ;;
    stale) sed -i '' 's/guard photo.sequence > current.sequence else { return }//' "$WORK/PhotoManager.swift" ;;
    watermark) sed -i '' 's/photos\[index\].sequence = photo.sequence/_ = 0/' "$WORK/PhotoManager.swift" ;;
    current) sed -i '' 's/generation == self.generation/true/' "$WORK/PhotoManager.swift" ;;
    clear) sed -i '' 's/let generation = processingQueue.sync { lifecycle.begin() }/let generation = self.generation/' "$WORK/PhotoManager.swift" ;;
esac
cp "$SRC/PhotoModel.swift" "$SRC/PrintManager.swift" "$SRC/MessageManager.swift" "$WORK/"
case "${LIFECYCLE_MUTANT:-}" in
    url) sed -i '' 's/SHA256.hash(data: data) == digest ? /true ? /' "$WORK/PhotoModel.swift" ;;
    mainread) sed -i '' 's/DispatchQueue.global(qos: .userInitiated).async {/DispatchQueue.main.async {/' "$WORK/PhotoModel.swift" ;;
esac
echo 'final class ErrorLog { static let shared = ErrorLog(); func log(_ m: String) {} }' > "$WORK/ErrorLog.swift"

cat > "$WORK/main.swift" <<'EOF'
import AppKit
import Foundation

var failures = 0
func check(_ name: String, _ ok: Bool) {
    print(ok ? "PASS" : "FAIL", name)
    if !ok { failures += 1 }
}
func spin(_ s: Double) { RunLoop.main.run(until: Date().addingTimeInterval(s)) }
func waitUntil(_ s: Double, _ cond: () -> Bool) {
    let end = Date().addingTimeInterval(s)
    while !cond() && Date() < end { spin(0.05) }
}
func folder(_ n: String) -> URL {
    let u = URL(fileURLWithPath: "/private" + NSTemporaryDirectory() + "c1-\(n)-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
    return u
}
func png(_ url: URL, created: Date? = nil, color: NSColor = .red) {
    let img = NSImage(size: NSSize(width: 8, height: 8))
    img.lockFocus(); color.setFill(); NSRect(x: 0, y: 0, width: 8, height: 8).fill(); img.unlockFocus()
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
    if let created { try! FileManager.default.setAttributes([.creationDate: created], ofItemAtPath: url.path) }
}
func names(_ m: PhotoManager) -> [String] { m.photos.map { $0.url.lastPathComponent } }

// Pure lifecycle rules
var lc = FolderLifecycle()
let u = URL(fileURLWithPath: "/x/a.png")
let g1 = lc.begin(), g2 = lc.begin(), g3 = lc.begin()
check("A-B-A: first generation is stale after returning to the same folder", !lc.isCurrent(g1) && !lc.isCurrent(g2) && lc.isCurrent(g3))
check("claim is exclusive within a generation", lc.claim(u, generation: g3) && !lc.claim(u, generation: g3))
check("stale generation cannot claim", !lc.claim(URL(fileURLWithPath: "/x/b.png"), generation: g1))
let g4 = lc.begin()
check("begin drops older claims", !lc.owns(u, generation: g3) && lc.claim(u, generation: g4))
lc.release(u, generation: g3)
check("stale release cannot free a newer claim for the same URL", lc.owns(u, generation: g4))
lc.release(u, generation: g4)
check("current release frees the claim", lc.claim(u, generation: g4))

let m = PhotoManager()

// A -> B
let A = folder("A"), B = folder("B"), E = folder("empty")
png(A.appendingPathComponent("a.png")); png(B.appendingPathComponent("b.png"))
m.setWatchedFolder(A); spin(0.5)
check("select A shows A", names(m) == ["a.png"])
m.setWatchedFolder(B); spin(0.5)
check("A->B shows only B", names(m) == ["b.png"])
m.setWatchedFolder(A); spin(0.5)
check("A->B->A shows only A", names(m) == ["a.png"])
m.setWatchedFolder(E); spin(0.5)
check("empty destination shows nothing", m.photos.isEmpty)

// Pending incomplete write: retries continue in the same lifecycle, never cross a switch
let P = folder("P"), Q = folder("Q")
let late = P.appendingPathComponent("late.png")
try! Data([1, 2, 3, 4, 5, 6, 7, 8, 9]).write(to: late)
m.setWatchedFolder(P); spin(0.1)
png(late); waitUntil(3) { !m.photos.isEmpty }
check("incomplete write completed in same folder is published", names(m) == ["late.png"])
let late2 = P.appendingPathComponent("late2.png")
try! Data([1, 2, 3, 4, 5, 6, 7, 8, 9]).write(to: late2)
m.setWatchedFolder(P); spin(0.1)
m.setWatchedFolder(Q); png(late2); spin(1.5)
check("pending retry from P cannot publish into Q", m.photos.isEmpty)

// Queued publication from an older generation
let R = folder("R"); png(R.appendingPathComponent("r.png"))
m.setWatchedFolder(R); spin(0.5)
let stale = m.generation
let S = folder("S"); let s = S.appendingPathComponent("s.png"); png(s)
m.processNewFile(at: s, generation: stale)
m.setWatchedFolder(E); spin(0.5)
check("publication queued before a switch is dropped", m.photos.isEmpty)
m.processNewFile(at: s, generation: stale); spin(0.5)
check("stale watcher event is rejected", m.photos.isEmpty)

// Same-folder refresh
let F = folder("F"); png(F.appendingPathComponent("f.png"))
let g = F.appendingPathComponent("g.png"); try! Data([1, 2, 3, 4, 5, 6, 7, 8, 9]).write(to: g)
m.setWatchedFolder(F); spin(0.2)
let before = m.generation
m.refreshWatcher()
check("refresh starts a new generation and is busy", m.generation != before && m.isRefreshing)
waitUntil(2) { !m.isRefreshing }
check("refresh finishes and lists the folder once", !m.isRefreshing && names(m) == ["f.png"])
check("stale cleanup cannot release a refreshed claim", {
    m.removeFromProcessing(g, generation: before); spin(0.2)
    let current = m.generation
    return m.processingQueue.sync { m.lifecycle.owns(g, generation: current) }
}())
m.refreshWatcher(); m.setWatchedFolder(E)
check("switch during refresh clears busy state", !m.isRefreshing)
spin(1.0)
check("old refresh scan and completion do not alter new folder", m.photos.isEmpty && !m.isRefreshing)

// Clear/switch race
let C = folder("C"), D = folder("D")
for i in 0..<400 { png(C.appendingPathComponent("c\(i).png")) }
png(D.appendingPathComponent("d.png"))
m.setWatchedFolder(C); spin(1.0)
var cleared = -1
m.clearWatchedFolder { if case .success(let n) = $0 { cleared = n } }
m.setWatchedFolder(D)
check("switch during clear resets busy state", !m.isClearing)
waitUntil(10) { cleared >= 0 }
spin(0.5)
check("clear completion after a switch keeps the new folder's photos", cleared == 400 && names(m) == ["d.png"] && !m.isClearing)
var clearedD = -1
m.clearWatchedFolder { if case .success(let n) = $0 { clearedD = n } }
waitUntil(5) { clearedD >= 0 }
check("clear of the current folder still empties it", clearedD == 1 && m.photos.isEmpty && !m.isClearing)

// Reads started before a same-folder clear (kept outside the folder so they survive the delete)
let K = folder("K"), X = folder("X")
png(K.appendingPathComponent("k.png"))
m.setWatchedFolder(K); spin(0.5)
let preClear = m.generation
let kept = X.appendingPathComponent("kept.png"); png(kept)
let paused = X.appendingPathComponent("paused.png"); try! Data([1, 2, 3, 4, 5, 6, 7, 8, 9]).write(to: paused)
m.processNewFile(at: paused, generation: preClear)
var clearedK = -1
m.clearWatchedFolder { if case .success(let n) = $0 { clearedK = n } }
waitUntil(5) { clearedK >= 0 }
check("same-folder clear empties the folder", clearedK == 1 && m.photos.isEmpty)
m.processNewFile(at: kept, generation: preClear); spin(0.5)
check("read paused before clear cannot republish after it", m.photos.isEmpty)
png(paused); spin(1.5)
check("retry pending before clear cannot publish after it", m.photos.isEmpty)
let postClear = K.appendingPathComponent("post.png"); png(postClear)
m.processNewFile(at: postClear, generation: m.generation); spin(0.5)
check("arrival after clear is published", names(m) == ["post.png"])
var clearedEmpty = -1
let K2 = folder("K2")
m.setWatchedFolder(K2); spin(0.3)
let preEmpty = m.generation
m.clearWatchedFolder { if case .success(let n) = $0 { clearedEmpty = n } }
waitUntil(5) { clearedEmpty >= 0 }
m.processNewFile(at: kept, generation: preEmpty); spin(0.5)
check("read before clear of an empty folder is rejected", clearedEmpty == 0 && m.photos.isEmpty)

// Ordering, dedup, captured selection
let O = folder("O"), N = folder("N")
let now = Date()
png(O.appendingPathComponent("old.png"), created: now.addingTimeInterval(-300))
png(O.appendingPathComponent("mid.png"), created: now.addingTimeInterval(-200))
png(O.appendingPathComponent("new.png"), created: now.addingTimeInterval(-100))
png(N.appendingPathComponent("n.png"))
m.setWatchedFolder(O); spin(0.8)
check("newest first", names(m) == ["new.png", "mid.png", "old.png"])
let captured = m.photos[0]
m.processNewFile(at: O.appendingPathComponent("new.png"), generation: m.generation); spin(0.3)
check("duplicate notification keeps one row", m.photos.count == 3)
let arrival = O.appendingPathComponent("arrival.png"); png(arrival, created: Date())
m.processNewFile(at: arrival, generation: m.generation); spin(0.3)
check("new arrival is first and captured selection is unchanged", names(m).first == "arrival.png" && captured.url.lastPathComponent == "new.png" && m.photos.contains(captured))
m.setWatchedFolder(N); spin(0.5)
check("captured selection still points at its own photo after a switch", captured.url.lastPathComponent == "new.png" && names(m) == ["n.png"])

// CORE-002: preview and action identity
func rep(_ r: NSBitmapImageRep) -> String {
    let c = r.colorAt(x: r.pixelsWide / 2, y: r.pixelsHigh / 2)!.usingColorSpace(.deviceRGB)!
    return c.redComponent > c.blueComponent ? "red" : "blue"
}
func tint(_ d: Data) -> String { rep(NSBitmapImageRep(data: d)!) }
func tint(_ p: PhotoModel) -> String {
    rep(NSBitmapImageRep(cgImage: p.thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil)!))
}
func bytes(_ color: NSColor) -> Data {
    let t = URL(fileURLWithPath: NSTemporaryDirectory() + "c2-\(UUID().uuidString).png")
    png(t, color: color); defer { try? FileManager.default.removeItem(at: t) }
    return try! Data(contentsOf: t)
}
final class Rec { var prints: [Data] = []; var shares: [(Data, String?)] = []; var onPrint: (() -> Void)?; var allOnMain = true }
func sinks(_ r: Rec) -> ActionSinks {
    ActionSinks(print: { d, _ in r.allOnMain = r.allOnMain && Thread.isMainThread; r.prints.append(d); r.onPrint?() },
                share: { d, _, who in r.allOnMain = r.allOnMain && Thread.isMainThread; r.shares.append((d, who)) })
}
func act(_ p: PhotoModel, print: Bool, share: Bool, recipient: String? = nil, _ r: Rec) -> PhotoSourceError? {
    var done = false, err: PhotoSourceError?
    p.perform(print: print, share: share, recipient: recipient, sinks: sinks(r)) { err = $0; done = true }
    waitUntil(5) { done }
    return done ? err : .unavailable
}
func row(_ m: PhotoManager, _ name: String) -> PhotoModel? { m.photos.first { $0.url.lastPathComponent == name } }

var lc2 = FolderLifecycle()
let lg = lc2.begin(), lu = URL(fileURLWithPath: "/x/e.png")
_ = lc2.claim(lu, generation: lg)
check("event during a claim is not lost: release asks for a re-read", !lc2.claim(lu, generation: lg) && lc2.release(lu, generation: lg))
check("no event during a claim: release asks for nothing", lc2.claim(lu, generation: lg) && !lc2.release(lu, generation: lg))

let I = folder("I")
let ix = I.appendingPathComponent("x.png"), iy = I.appendingPathComponent("y.png"), iz = I.appendingPathComponent("z.png")
let t0 = Date().addingTimeInterval(-60)
png(ix, created: t0, color: .red); png(iy, created: t0.addingTimeInterval(1), color: .red); png(iz, created: t0.addingTimeInterval(2), color: .red)
m.setWatchedFolder(I); spin(0.8)
let gI = m.generation
let x1 = row(m, "x.png")!
m.processNewFile(at: ix, generation: gI); spin(0.3)
check("unchanged duplicate keeps the same row and revision", m.photos.count == 3 && row(m, "x.png")?.id == x1.id)

// In-place replacement
try! bytes(.blue).write(to: ix)
let rec1 = Rec()
check("replaced before the click: action is rejected, nothing printed or shared",
      act(x1, print: true, share: true, rec1) == .changed && rec1.prints.isEmpty && rec1.shares.isEmpty)
m.processNewFile(at: ix, generation: gI); spin(0.5)
let x2 = row(m, "x.png")!
check("in-place replacement updates the preview and keeps one row", m.photos.filter { $0.url == ix }.count == 1 && tint(x1) == "red" && tint(x2) == "blue" && x2.id != x1.id)
let rec2 = Rec()
check("sheet opened before the replacement is rejected", act(x1, print: false, share: true, recipient: "+15550100", rec2) == .changed && rec2.shares.isEmpty)
let rec3 = Rec()
check("the new row's action consumes the replacement bytes", act(x2, print: true, share: true, rec3) == nil && rec3.prints.map(tint) == ["blue"] && rec3.shares.map { tint($0.0) } == ["blue"])

// Atomic replacement
let swap = URL(fileURLWithPath: NSTemporaryDirectory() + "c2-swap-\(UUID().uuidString).png"); png(swap, color: .blue)
let y1 = row(m, "y.png")!
_ = try! FileManager.default.replaceItemAt(iy, withItemAt: swap)
m.processNewFile(at: iy, generation: gI); spin(0.5)
check("atomic replacement updates the preview and rejects the old selection", tint(row(m, "y.png")!) == "blue" && m.photos.count == 3 && act(y1, print: true, share: false, Rec()) == .changed)

// Between validation and consumption, then a new arrival and a folder switch during the sheet
let z1 = row(m, "z.png")!
let rec4 = Rec()
rec4.onPrint = { try! bytes(.blue).write(to: iz) }
check("file replaced while printing: print and share still use the verified bytes",
      act(z1, print: true, share: true, recipient: "+15550100", rec4) == nil && rec4.prints.map(tint) == ["red"] && rec4.shares.map { tint($0.0) } == ["red"] && rec4.shares.first?.1 == "+15550100")
try! bytes(.red).write(to: iz)
let arrive = I.appendingPathComponent("arrive.png"); png(arrive, created: Date(), color: .blue)
m.processNewFile(at: arrive, generation: gI); spin(0.4)
let rec5 = Rec()
check("new arrival during the sheet does not change what the selection prints", row(m, "arrive.png") != nil && act(z1, print: true, share: false, rec5) == nil && rec5.prints.map(tint) == ["red"])
m.setWatchedFolder(N); spin(0.5)
let rec6 = Rec()
check("folder switch during the sheet keeps the selection's own content", act(z1, print: false, share: true, rec6) == nil && rec6.shares.map { tint($0.0) } == ["red"])

// Incomplete replacement, then a completed one
let J = folder("J"); let jx = J.appendingPathComponent("j.png"); png(jx, color: .red)
m.setWatchedFolder(J); spin(0.6)
let gJ = m.generation
let j1 = row(m, "j.png")!
try! Data([1, 2, 3, 4, 5, 6, 7, 8, 9]).write(to: jx)
m.processNewFile(at: jx, generation: gJ); spin(0.6)
check("incomplete replacement: old preview cannot be used for an action", act(j1, print: true, share: true, Rec()) == .changed)
try! bytes(.blue).write(to: jx); waitUntil(3) { row(m, "j.png").map(tint) == "blue" }
check("retry completes the replacement", m.photos.count == 1 && tint(row(m, "j.png")!) == "blue")
let j2 = row(m, "j.png")!
try! Data([1, 2, 3, 4, 5, 6, 7, 8, 9]).write(to: jx)
m.processNewFile(at: jx, generation: gJ); waitUntil(5) { m.photos.isEmpty }
check("replacement that never completes drops the untrustworthy preview", m.photos.isEmpty)
check("and the old selection is rejected", act(j2, print: true, share: false, Rec()) == .changed)

// Disappearing file
let Kd = folder("Kd"); let kd = Kd.appendingPathComponent("gone.png"); png(kd)
m.setWatchedFolder(Kd); spin(0.6)
let kdp = row(m, "gone.png")!
try! FileManager.default.removeItem(at: kd)
let recG = Rec()
check("disappeared file: action reports unavailable", act(kdp, print: true, share: true, recG) == .unavailable && recG.prints.isEmpty)
m.processNewFile(at: kd, generation: m.generation); waitUntil(5) { m.photos.isEmpty }
check("disappeared file: the preview is removed", m.photos.isEmpty)

// Out-of-order completion
let Oo = folder("Oo"); let oo = Oo.appendingPathComponent("o.png")
m.setWatchedFolder(Oo); spin(0.3)
let gO = m.generation
png(oo, color: .red); let older = PhotoModel(url: oo, sequence: 5)!
png(oo, color: .blue); let newer = PhotoModel(url: oo, sequence: 9)!
m.publish(newer, generation: gO); m.publish(older, generation: gO)
check("an older in-flight revision cannot overwrite a newer one", m.photos.count == 1 && tint(m.photos[0]) == "blue")
m.publish(older, generation: gO - 1)
check("a stale-generation publication is ignored", m.photos.count == 1 && m.photos[0].id == newer.id)

// Unchanged newer content still advances the ordering watermark
let Wm = folder("Wm"); let wm = Wm.appendingPathComponent("w.png")
m.setWatchedFolder(Wm); spin(0.3)
let gW = m.generation
let redBytes = bytes(.red)
try! redBytes.write(to: wm); let red10 = PhotoModel(url: wm, sequence: 10)!, red30 = PhotoModel(url: wm, sequence: 30)!
png(wm, color: .blue); let blue20 = PhotoModel(url: wm, sequence: 20)!
m.publish(red10, generation: gW); m.publish(red30, generation: gW); m.publish(blue20, generation: gW)
try! redBytes.write(to: wm)
check("delayed older revision cannot replace the latest unchanged content", m.photos.count == 1 && tint(m.photos[0]) == "red" && m.photos[0].id == red10.id && m.photos[0].sequence == 30)
check("and the listed row still acts on its own content", act(m.photos[0], print: true, share: false, Rec()) == nil)

// Verification must not block the main run loop: the read is slow
let Fo = folder("Fo"); let fo = Fo.appendingPathComponent("f.png"); png(fo, color: .red)
m.setWatchedFolder(Fo); spin(0.6)
let f1 = row(m, "f.png")!
let fifoBytes = try! Data(contentsOf: fo)
var ticks = 0
let timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in ticks += 1 }
let recF = Rec()
var resultF: PhotoSourceError? = .unavailable
let beforeSinks = recF.prints.count
var doneF = false
f1.perform(print: true, share: false, sinks: sinks(recF), read: { _ in Thread.sleep(forTimeInterval: 0.8); return fifoBytes }) { resultF = $0; doneF = true }
spin(0.4)
check("main run loop stays responsive and nothing is output while the read is pending", ticks >= 5 && !doneF && recF.prints.count == beforeSinks)
waitUntil(5) { doneF }; timer.invalidate()
check("delayed read outputs the selected snapshot on the main thread", resultF == nil && recF.prints.map(tint) == ["red"] && recF.allOnMain)

for d in [I, J, Kd, Oo, Wm, Fo] { try? FileManager.default.removeItem(at: d) }

for d in [A, B, E, P, Q, R, S, F, C, D, O, N, K, K2, X] { try? FileManager.default.removeItem(at: d) }
print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
EOF

swiftc -swift-version 5 -o "$WORK/$EXE" "$WORK"/*.swift 2>&1 | grep -E "error" || true
"$WORK/$EXE"
