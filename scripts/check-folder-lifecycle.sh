#!/bin/bash
# CORE-001 regression checks. Compiles the real PhotoManager/PhotoModel with a logging stub,
# so no app log or live folder is touched. Synthetic images only, in disposable temp folders.
# LIFECYCLE_MUTANT=release|current|clear breaks FolderLifecycle on purpose; the checks must then fail.
set -euo pipefail

SRC="$(cd "$(dirname "$0")/../PhotoBoothAttract" && pwd)"
WORK="$(mktemp -d /tmp/folder-lifecycle-checks.XXXXXX)"
EXE="folder-lifecycle-checks"
trap 'rm -rf "$WORK"; defaults delete "$EXE" >/dev/null 2>&1 || true' EXIT

sed -E 's/private (func|var|let)/\1/' "$SRC/PhotoManager.swift" > "$WORK/PhotoManager.swift"
case "${LIFECYCLE_MUTANT:-}" in
    release) sed -i '' 's/if claims\[url\] == generation { claims\[url\] = nil }/claims[url] = nil/' "$WORK/PhotoManager.swift" ;;
    current) sed -i '' 's/generation == self.generation/true/' "$WORK/PhotoManager.swift" ;;
    clear) sed -i '' 's/let generation = processingQueue.sync { lifecycle.begin() }/let generation = self.generation/' "$WORK/PhotoManager.swift" ;;
esac
cp "$SRC/PhotoModel.swift" "$WORK/"
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
func png(_ url: URL, created: Date? = nil) {
    let img = NSImage(size: NSSize(width: 8, height: 8))
    img.lockFocus(); NSColor.red.setFill(); NSRect(x: 0, y: 0, width: 8, height: 8).fill(); img.unlockFocus()
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

for d in [A, B, E, P, Q, R, S, F, C, D, O, N, K, K2, X] { try? FileManager.default.removeItem(at: d) }
print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
EOF

swiftc -swift-version 5 -o "$WORK/$EXE" "$WORK"/*.swift 2>&1 | grep -E "error" || true
"$WORK/$EXE"
