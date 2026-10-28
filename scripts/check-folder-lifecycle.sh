#!/bin/bash
# CORE-001/CORE-002 regression checks. Compiles the real PhotoManager/PhotoModel/PrintManager/
# MessageManager with a logging stub, so no app log, printer or Messages is touched. Actions run
# against stub sinks. Synthetic images only, in disposable temp folders.
# LIFECYCLE_MUTANT=release|current|clear breaks FolderLifecycle on purpose; the checks must then fail.
# LIFECYCLE_MUTANT=events|tombstone|wrongremove|lateabsence: ignore rename/remove flags | no stale-read tombstone | removal
# also drops a newer replacement.
# LIFECYCLE_MUTANT=url|stale|watermark|mainread: URL-only identity | older revision wins | unchanged reads
# do not advance ordering | verification reads on the main thread.
# LIFECYCLE_MUTANT=mainscan|nostop|stalebusy: initial scan on main | stale scan keeps preparing files | stale
# scan completion ends the new busy state.
set -euo pipefail

SRC="$(cd "$(dirname "$0")/../PhotoBoothAttract" && pwd)"
WORK="$(mktemp -d /tmp/folder-lifecycle-checks.XXXXXX)"
EXE="folder-lifecycle-checks"
trap 'rm -rf "$WORK"; defaults delete "$EXE" >/dev/null 2>&1 || true' EXIT

sed -E 's/private (func|var|let)/\1/' "$SRC/PhotoManager.swift" > "$WORK/PhotoManager.swift"
case "${LIFECYCLE_MUTANT:-}" in
    events) sed -i '' 's/flags \& UInt32(wanted) != 0/flags \& UInt32(kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemModified) != 0/' "$WORK/PhotoManager.swift" ;;
    tombstone) sed -i '' 's/sequence > (removedAt\[url\] ?? 0)/true/' "$WORK/PhotoManager.swift" ;;
    wrongremove) sed -i '' 's/\$0.url == url \&\& \$0.sequence < sequence/$0.url == url/' "$WORK/PhotoManager.swift" ;;
    lateabsence) sed -i '' 's/func removePhoto(at url: URL, generation: Int, observedAt sequence: Int) {/&\n        let sequence = nextSequence()/' "$WORK/PhotoManager.swift" ;;
    release) sed -i '' 's/guard claims\[url\] == generation else { return false }/guard true else { return false }/' "$WORK/PhotoManager.swift" ;;
    url) sed -i '' 's/photo.digest == current.digest/true/' "$WORK/PhotoManager.swift" ;;
    stale) sed -i '' 's/guard photo.sequence > current.sequence else { return }//' "$WORK/PhotoManager.swift" ;;
    watermark) sed -i '' 's/photos\[index\].sequence = photo.sequence/_ = 0/' "$WORK/PhotoManager.swift" ;;
    current) sed -i '' 's/generation == self.generation/true/' "$WORK/PhotoManager.swift" ;;
    mainscan) sed -i '' '/func scanExistingFiles/,/^    }$/ s/DispatchQueue.global(qos: .userInitiated).async/DispatchQueue.main.async/' "$WORK/PhotoManager.swift" ;;
    nostop) sed -i '' '/guard self.isCurrent(generation) else { break }/d' "$WORK/PhotoManager.swift" ;;
    stalebusy) sed -i '' 's/if self.isCurrent(generation) { self.isRefreshing = false }/self.isRefreshing = false/' "$WORK/PhotoManager.swift" ;;
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
import Combine
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
waitUntil(2) { !m.isRefreshing }
check("switch during refresh: busy ends with the new folder's scan", !m.isRefreshing)
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

// CORE-004: filesystem events. Flags are only a hint; the file's current state decides.
let fl = { (f: Int) in UInt32(f) }
check("flags: create/modify/rename/remove and combinations are relevant",
      [kFSEventStreamEventFlagItemCreated, kFSEventStreamEventFlagItemModified, kFSEventStreamEventFlagItemRenamed, kFSEventStreamEventFlagItemRemoved].allSatisfy { PhotoManager.isRelevant(flags: fl(Int($0))) }
      && PhotoManager.isRelevant(flags: fl(kFSEventStreamEventFlagItemRenamed | kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemRemoved)))
check("flags: directories and unrelated flags are ignored",
      !PhotoManager.isRelevant(flags: fl(kFSEventStreamEventFlagItemCreated | kFSEventStreamEventFlagItemIsDir)) && !PhotoManager.isRelevant(flags: fl(kFSEventStreamEventFlagItemXattrMod)))

let Ev = folder("Ev"); let ea = Ev.appendingPathComponent("ea.png"), eb = Ev.appendingPathComponent("eb.png")
png(ea, created: Date().addingTimeInterval(-50)); png(eb, created: Date().addingTimeInterval(-40))
m.setWatchedFolder(Ev); spin(0.8)
let gE = m.generation
let ea1 = row(m, "ea.png")!

try! FileManager.default.removeItem(at: ea)
m.reconcile(ea, generation: gE); m.reconcile(ea, generation: gE); waitUntil(3) { row(m, "ea.png") == nil }
check("removal drops only that row, repeated removal is harmless", names(m) == ["eb.png"])
let recEa = Rec()
check("removed row cannot be acted on", act(ea1, print: true, share: true, recEa) == .unavailable && recEa.prints.isEmpty && recEa.shares.isEmpty)

let moved = Ev.appendingPathComponent("moved.png")
try! FileManager.default.moveItem(at: eb, to: moved)
m.reconcile(eb, generation: gE); m.reconcile(moved, generation: gE); waitUntil(3) { names(m) == ["moved.png"] }
check("rename within the folder: old row leaves, new row arrives", names(m) == ["moved.png"])

let outside = X.appendingPathComponent("in.png"); png(outside)
try! FileManager.default.moveItem(at: outside, to: Ev.appendingPathComponent("in.png"))
m.reconcile(Ev.appendingPathComponent("in.png"), generation: gE); waitUntil(3) { row(m, "in.png") != nil }
check("rename into the folder appears", row(m, "in.png") != nil)
let inRow = row(m, "in.png")!
try! FileManager.default.moveItem(at: Ev.appendingPathComponent("in.png"), to: X.appendingPathComponent("out.png"))
m.reconcile(Ev.appendingPathComponent("in.png"), generation: gE); waitUntil(3) { row(m, "in.png") == nil }
check("rename out of the folder leaves, and its row is rejected", row(m, "in.png") == nil && act(inRow, print: true, share: false, Rec()) == .unavailable)

let inc = Ev.appendingPathComponent("inc.png"); try! Data([1, 2, 3, 4, 5, 6, 7, 8, 9]).write(to: inc)
m.reconcile(inc, generation: gE); spin(0.3)
check("incomplete arrival is not listed yet", row(m, "inc.png") == nil)
png(inc); waitUntil(3) { row(m, "inc.png") != nil }
check("incomplete arrival is listed once completed", row(m, "inc.png") != nil)

// Removal during a pending read: the read must not resurrect the row
let pend = X.appendingPathComponent("pend.png"); png(pend)
let staleRead = PhotoModel(url: pend, sequence: m.nextSequence())!
try! FileManager.default.removeItem(at: pend)
m.removePhoto(at: pend, generation: gE, observedAt: m.nextSequence()); spin(0.3)
m.publish(staleRead, generation: gE)
check("read started before a removal cannot publish after it", row(m, "pend.png") == nil)

// Deletion before queued publication, then recreation of the same path
let rc = Ev.appendingPathComponent("rc.png"); png(rc, color: .red)
m.processNewFile(at: rc, generation: gE); waitUntil(3) { row(m, "rc.png") != nil }
let rcOld = row(m, "rc.png")!
let queued = PhotoModel(url: rc, sequence: m.nextSequence())!
try! FileManager.default.removeItem(at: rc)
m.removePhoto(at: rc, generation: gE, observedAt: m.nextSequence()); waitUntil(3) { row(m, "rc.png") == nil }
m.publish(queued, generation: gE)
check("publication queued before deletion does not resurrect the row", row(m, "rc.png") == nil)
png(rc, color: .blue)
m.reconcile(rc, generation: gE); waitUntil(3) { row(m, "rc.png") != nil }
check("same-path recreation is listed as a new row", row(m, "rc.png").map(tint) == "blue" && row(m, "rc.png")!.id != rcOld.id)
let recRc = Rec()
check("old selection of the recreated path is rejected", act(rcOld, print: true, share: false, recRc) == .changed && recRc.prints.isEmpty)
m.removePhoto(at: rc, generation: gE, observedAt: m.nextSequence())
let replacement = PhotoModel(url: rc, sequence: m.nextSequence())!
m.publish(replacement, generation: gE); spin(0.3)
check("delayed stale removal cannot remove a newer replacement", row(m, "rc.png").map { $0.sequence >= replacement.sequence } == true)

// Absence observed (sequence taken) before the check result is acted on; the path is recreated and ingested meanwhile
let rr = Ev.appendingPathComponent("rr.png"); png(rr, color: .red)
m.processNewFile(at: rr, generation: gE); waitUntil(3) { row(m, "rr.png") != nil }
try! FileManager.default.removeItem(at: rr)
let lateObservation = m.nextSequence()
png(rr, color: .blue)
m.processNewFile(at: rr, generation: gE); waitUntil(3) { row(m, "rr.png").map(tint) == "blue" }
m.removePhoto(at: rr, generation: gE, observedAt: lateObservation); spin(0.3)
check("late absence observation cannot remove a recreated photo that exists", row(m, "rr.png").map(tint) == "blue")
let rrSeq = row(m, "rr.png")?.sequence ?? Int.max
m.publish(PhotoModel(url: rr, sequence: m.nextSequence())!, generation: gE)
check("and later arrivals of that path are still accepted", (row(m, "rr.png")?.sequence ?? 0) > rrSeq)

// Old-folder callbacks after a switch
try! FileManager.default.removeItem(at: rc)
m.setWatchedFolder(N); spin(0.5)
m.reconcile(rc, generation: gE); m.reconcile(Ev.appendingPathComponent("moved.png"), generation: gE); spin(0.5)
check("old-folder removal and arrival callbacks do not touch the new folder", names(m) == ["n.png"])

// Live FSEvents: no manual ingestion
let Lv = folder("Lv"); let lp = Lv.appendingPathComponent("live.png")
m.setWatchedFolder(Lv); spin(1.0)
png(lp); waitUntil(6) { row(m, "live.png") != nil }
check("live: created file appears automatically", row(m, "live.png") != nil)
let lrow = row(m, "live.png")
spin(1.0); try? FileManager.default.removeItem(at: lp); waitUntil(6) { row(m, "live.png") == nil }
check("live: deleted file leaves automatically", row(m, "live.png") == nil)
spin(1.0); png(lp, color: .blue); waitUntil(6) { row(m, "live.png") != nil }
check("live: recreated file appears with new content", row(m, "live.png").map(tint) == "blue" && row(m, "live.png")?.id != lrow?.id)
let LvX = folder("LvX"); let lq = LvX.appendingPathComponent("mv.png"); png(lq)
spin(1.0); try? FileManager.default.moveItem(at: lq, to: Lv.appendingPathComponent("mv.png")); waitUntil(6) { row(m, "mv.png") != nil }
check("live: rename into folder appears automatically", row(m, "mv.png") != nil)
spin(1.0); try? FileManager.default.moveItem(at: Lv.appendingPathComponent("mv.png"), to: lq); waitUntil(6) { row(m, "mv.png") == nil }
check("live: rename out of folder leaves automatically", row(m, "mv.png") == nil)
spin(1.0); try? FileManager.default.moveItem(at: lp, to: Lv.appendingPathComponent("renamed.png")); waitUntil(6) { row(m, "renamed.png") != nil && row(m, "live.png") == nil }
check("live: rename within folder swaps rows automatically", row(m, "renamed.png") != nil && row(m, "live.png") == nil)
for d in [Ev, Lv, LvX] { try? FileManager.default.removeItem(at: d) }

// CORE-006: initial scans run off main. The hook delays enumeration and every file, so a main-thread scan or an
// unstopped stale scan is visible.
final class Probe {
    private let lock = NSLock()
    private var seen: [String] = [], main = false
    func hook(_ delay: Double) -> (URL) -> Void {
        { [self] u in
            lock.lock(); seen.append(u.lastPathComponent); main = main || Thread.isMainThread; lock.unlock()
            Thread.sleep(forTimeInterval: delay)
        }
    }
    var onMain: Bool { lock.lock(); defer { lock.unlock() }; return main }
    func files(_ prefix: String) -> Int { lock.lock(); defer { lock.unlock() }; return seen.filter { $0.hasPrefix(prefix) }.count }
}
func filled(_ prefix: String, _ count: Int) -> URL {
    let d = folder(prefix)
    for i in 0..<count { png(d.appendingPathComponent("\(prefix)\(i).png"), created: Date().addingTimeInterval(Double(-i))) }
    return d
}
var ticks6 = 0
let timer6 = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in ticks6 += 1 }
var offMainPublication = false
var sinks6 = Set<AnyCancellable>()
func watch(_ r: PhotoManager) {
    r.$photos.dropFirst().sink { _ in if !Thread.isMainThread { offMainPublication = true } }.store(in: &sinks6)
    r.$isRefreshing.dropFirst().sink { _ in if !Thread.isMainThread { offMainPublication = true } }.store(in: &sinks6)
}

// Startup restoration reads the bookmark saved by the previous selection
let G = filled("g", 5)
m.setWatchedFolder(G); spin(0.5)
let pStart = Probe()
let t6 = Date()
let r = PhotoManager(scanHook: pStart.hook(0.2))
check("startup: init returns before the delayed scan and shows busy", Date().timeIntervalSince(t6) < 0.15 && r.isRefreshing && r.photos.isEmpty)
let tk = ticks6; spin(0.5)
check("startup: main run loop keeps running while photos load", ticks6 - tk >= 8)
waitUntil(6) { !r.isRefreshing }
check("startup: restored folder is listed and nothing was prepared on main", r.photos.count == 5 && !pStart.onMain && r.watchedFolderURL?.lastPathComponent == G.lastPathComponent)

// Folder selection
watch(r)
let H = filled("h", 4)
let pSel = Probe(); r.scanHook = pSel.hook(0.2)
let t7 = Date(); r.setWatchedFolder(H)
check("select: call returns before the delayed scan and shows busy", Date().timeIntervalSince(t7) < 0.15 && r.isRefreshing && r.photos.isEmpty)
let tk2 = ticks6; spin(0.4)
check("select: main run loop keeps running while photos load", ticks6 - tk2 >= 5)
waitUntil(6) { !r.isRefreshing }
check("select: populated folder lists every photo newest first, off main, published on main",
      names(r) == (0..<4).map { "h\($0).png" } && !pSel.onMain && !offMainPublication)

// Empty and error states end busy
r.setWatchedFolder(folder("e6")); waitUntil(3) { !r.isRefreshing }
check("empty folder: busy ends and nothing is listed", !r.isRefreshing && r.photos.isEmpty)
r.setWatchedFolder(URL(fileURLWithPath: "/private/tmp/missing-\(UUID().uuidString)")); waitUntil(3) { !r.isRefreshing }
check("unreadable folder: busy ends and nothing is listed", !r.isRefreshing && r.photos.isEmpty)

// Switch during load: the old scan stops and cannot clear the new scan's busy state
let S1 = filled("s1x", 6), S2 = filled("s2x", 3)
let pSw = Probe(); r.scanHook = pSw.hook(0.3)
r.setWatchedFolder(S1); spin(0.5)
r.setWatchedFolder(S2); spin(0.9)
check("switch during load: old scan finished without ending the new busy state", r.isRefreshing)
waitUntil(6) { !r.isRefreshing }
check("switch during load: only the new folder is listed and the old scan stopped early", names(r).sorted() == ["s2x0.png", "s2x1.png", "s2x2.png"] && pSw.files("s1x") <= 2)

// Same-folder refresh during load
let T = filled("t", 5)
let pRf = Probe(); r.scanHook = pRf.hook(0.2)
r.setWatchedFolder(T); spin(0.5)
r.refreshWatcher()
waitUntil(6) { !r.isRefreshing }
check("refresh during load: each photo listed once and the old scan stopped early", r.photos.count == 5 && Set(names(r)).count == 5 && pRf.files("t") <= 7)

// Clear during load
let U = filled("u", 6)
let pCl = Probe(); r.scanHook = pCl.hook(0.2)
r.setWatchedFolder(U); spin(0.5)
var clearedU = -1
r.clearWatchedFolder { if case .success(let n) = $0 { clearedU = n } }
check("clear during load: busy is reset", !r.isRefreshing)
waitUntil(5) { clearedU >= 0 }; spin(1.0)
check("clear during load: nothing repopulates, busy stays off, old scan stopped early", clearedU == 6 && r.photos.isEmpty && !r.isRefreshing && pCl.files("u") <= 2)
timer6.invalidate()
for d in [G, H, S1, S2, T, U] { try? FileManager.default.removeItem(at: d) }

for d in [I, J, Kd, Oo, Wm, Fo] { try? FileManager.default.removeItem(at: d) }

for d in [A, B, E, P, Q, R, S, F, C, D, O, N, K, K2, X] { try? FileManager.default.removeItem(at: d) }
print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
EOF

swiftc -swift-version 5 -o "$WORK/$EXE" "$WORK"/*.swift 2>&1 | grep -E "error" || true
"$WORK/$EXE"
