#!/bin/bash
# CAM-001 regression checks. Compiles the real CameraMode/SonyCameraManager with fake SDK/browser
# counters, so no Sony SDK, USB discovery or camera is touched. Preferences use a throwaway suite.
# CAMERA_MUTANT=gate removes the Cooperative start gate; the checks must then fail.
set -euo pipefail

SRC="$(cd "$(dirname "$0")/../PhotoBoothAttract" && pwd)"
WORK="$(mktemp -d /tmp/camera-mode-checks.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

{ echo 'import Cocoa'; echo 'import ImageCaptureCore'; echo 'import Darwin'
  sed -n '/^enum CameraMode/,$p' "$SRC/AppDelegate.swift"; } > "$WORK/Camera.swift"
cat > "$WORK/ErrorLog.swift" <<'SWIFT'
final class ErrorLog { static let shared = ErrorLog(); func log(_ message: String) {} }
SWIFT

if [ "${CAMERA_MUTANT:-}" = "gate" ]; then
    sed -i '' 's/guard mode == .native, !started/guard !started/' "$WORK/Camera.swift"
    grep -q 'guard !started else { return }' "$WORK/Camera.swift" || { echo "ERROR: mutant did not apply"; exit 1; }
fi

cat > "$WORK/main.swift" <<'SWIFT'
import Foundation

var failures = 0
func check(_ ok: Bool, _ label: String) {
    print(ok ? "PASS \(label)" : "FAIL \(label)")
    if !ok { failures += 1 }
}

final class Counters {
    var made = 0, loads = 0, starts = 0, stops = 0
    var loadError: String?
    func factory() -> (SonyCameraManager) -> SonyCameraManager.Backend {
        return { _ in
            self.made += 1
            return SonyCameraManager.Backend(
                load: { self.loads += 1; return self.loadError },
                startDiscovery: { self.starts += 1 },
                stopDiscovery: { self.stops += 1 })
        }
    }
}

let suiteName = "camera-mode-checks"
let defaults = UserDefaults(suiteName: suiteName)!
defaults.removePersistentDomain(forName: suiteName)
defer { defaults.removePersistentDomain(forName: suiteName) }

// Mode resolution
check(CameraMode.resolve(defaults) == .cooperative, "missing preference defaults to Cooperative")
defaults.set("bogus", forKey: CameraMode.key)
check(CameraMode.resolve(defaults) == .cooperative, "invalid string defaults to Cooperative")
defaults.set(7, forKey: CameraMode.key)
check(CameraMode.resolve(defaults) == .cooperative, "non-string value defaults to Cooperative")
defaults.set("Native", forKey: CameraMode.key)
check(CameraMode.resolve(defaults) == .cooperative, "wrong-case value defaults to Cooperative")
defaults.set("native", forKey: CameraMode.key)
check(CameraMode.resolve(defaults) == .native, "saved native persists")
defaults.set("cooperative", forKey: CameraMode.key)
check(CameraMode.resolve(defaults) == .cooperative, "saved cooperative persists")

// Cooperative startup gating, repeated
let coop = Counters()
let coopManager = SonyCameraManager(mode: .cooperative, makeBackend: coop.factory())
for _ in 0..<3 { coopManager.start(); coopManager.stop() }
check(coop.made == 0 && coop.loads == 0 && coop.starts == 0 && coop.stops == 0,
      "Cooperative: zero backend allocations, SDK loads and discovery calls")
check(coopManager.connectionStatus == .notConnected, "Cooperative: inert manager stays notConnected")

// Active versus pending
defaults.set("cooperative", forKey: CameraMode.key)
let active = Counters()
let activeManager = SonyCameraManager(mode: CameraMode.resolve(defaults), makeBackend: active.factory())
defaults.set("native", forKey: CameraMode.key)
activeManager.start()
check(activeManager.mode == .cooperative && active.made == 0 && active.starts == 0,
      "saving Native does not change the running Cooperative manager")
let next = Counters()
let nextManager = SonyCameraManager(mode: CameraMode.resolve(defaults), makeBackend: next.factory())
nextManager.start()
check(nextManager.mode == .native && next.made == 1, "next launch resolves saved Native")

// Native startup
check(next.loads == 1 && next.starts == 1, "Native: one SDK load and one discovery start")
check(nextManager.connectionStatus == .notConnected, "Native: successful load is notConnected")
nextManager.start()
check(next.made == 1 && next.loads == 1 && next.starts == 1, "Native: repeated start is a no-op")
nextManager.stop(); nextManager.stop()
check(next.stops == 1, "Native: stop stops discovery once")
nextManager.start()
check(next.made == 1 && next.starts == 2 && next.stops == 1, "Native: restart reuses the backend")
nextManager.stop()

// Native load failure keeps discovery running (existing behavior)
let failing = Counters()
failing.loadError = "missing dylib"
let failingManager = SonyCameraManager(mode: .native, makeBackend: failing.factory())
failingManager.start()
check(failingManager.connectionStatus == .failed(reason: "missing dylib") && failing.starts == 1,
      "Native: load failure reports failed and still starts discovery")

print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
SWIFT

swiftc -swift-version 5 -O -o "$WORK/checks" "$WORK"/*.swift
"$WORK/checks"
