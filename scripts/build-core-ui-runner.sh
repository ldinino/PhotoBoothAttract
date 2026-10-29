#!/bin/bash
# Builds the offline CORE UI runner (arm64 + x86_64) into dist/CoreUIRunner/. Development Mac only;
# the target needs nothing but that folder and a PhotoBooth Attract.app.
# RUNNER_MUTANT=layout|dismiss|cancel builds a deliberately wrong guest layout / sheet-completion guard /
# pending-Cancel guard; the runner must then FAIL.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/PhotoBoothAttract"
OUT="${RUNNER_OUT:-$ROOT/dist/CoreUIRunner}"
WORK="$(mktemp -d /tmp/core-ui-runner.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

for f in PhotoModel PhotoManager GuestView AssistantView PrintManager MessageManager AppDelegate; do cp "$SRC/$f.swift" "$WORK/"; done
cp "$ROOT"/scripts/core-ui-runner/*.swift "$WORK/"

# Test-only wiring, applied to the build copy: reach the attachment helper and swap the live sinks.
sed -i '' -E 's/private func attachmentURL/func attachmentURL/' "$WORK/MessageManager.swift"
sed -i '' 's/    static let live = ActionSinks(/    nonisolated(unsafe) static var live = ActionSinks(/' "$WORK/PhotoModel.swift"
grep -q 'static var live' "$WORK/PhotoModel.swift" || { echo "ERROR: sink wiring did not apply"; exit 1; }
grep -q '^    func attachmentURL' "$WORK/MessageManager.swift" || { echo "ERROR: attachment wiring did not apply"; exit 1; }

case "${RUNNER_MUTANT:-}" in
    layout) sed -i '' 's/\.position(x: cellWidth \* (CGFloat(index % 2) + 0.5),/.position(x: cellWidth * 0.5,/' "$WORK/GuestView.swift" ;;
    dismiss) sed -i '' 's/if sheetRequest?.id == requestID { sheetRequest = nil }/sheetRequest = nil/' "$WORK/AssistantView.swift" ;;
    cancel) sed -i '' '/keyboardShortcut(.cancelAction)/{n;s/\.disabled(isPending)//;}' "$WORK/AssistantView.swift" ;;
esac
if [ -n "${RUNNER_MUTANT:-}" ]; then
    cmp -s "$SRC/GuestView.swift" "$WORK/GuestView.swift" && cmp -s "$SRC/AssistantView.swift" "$WORK/AssistantView.swift" && { echo "ERROR: mutant did not apply"; exit 1; }
fi

REV="$(git -C "$ROOT" rev-parse --short HEAD)$(git -C "$ROOT" diff --quiet HEAD -- PhotoBoothAttract scripts || echo '+local-changes')"
printf 'let buildRevision = "%s%s"\nlet buildDate = "%s"\n' "$REV" "${RUNNER_MUTANT:+ MUTANT-$RUNNER_MUTANT}" "$(date -u +%Y-%m-%d)" > "$WORK/BuildInfo.swift"

for arch in arm64 x86_64; do
    swiftc -swift-version 5 -O -target "$arch-apple-macos15.7" -o "$WORK/runner-$arch" "$WORK"/*.swift
done

rm -rf "$OUT"; mkdir -p "$OUT/App"
lipo -create "$WORK/runner-arm64" "$WORK/runner-x86_64" -output "$OUT/CoreUIRunner"
codesign --force --sign - "$OUT/CoreUIRunner"

cat > "$OUT/run-core-ui.command" <<'LAUNCH'
#!/bin/bash
cd "$(dirname "$0")"
APP="./App/PhotoBooth Attract.app"
[ -d "$APP" ] || APP="./App/PhotoBoothAttract.app"
[ -d "$APP" ] || { echo "Put PhotoBooth Attract.app in the App folder next to this script, then run again."; read -r -p "Press Return to close."; exit 3; }
mkdir -p reports
./CoreUIRunner --app "$APP" --report "reports/core-ui-$(date +%Y%m%d-%H%M%S).txt" "$@"
code=$?
echo; echo "Runner exit code: $code (0 = all passed, 1 = failures, 2 = incomplete/skipped, 3 = could not start)"
read -r -p "Press Return to close."
exit $code
LAUNCH
chmod +x "$OUT/run-core-ui.command"

cat > "$OUT/INSTRUCTIONS.txt" <<'TXT'
PhotoBooth Attract CORE UI runner (offline; no install, no Xcode, no network)

1. Copy this whole folder to the target Mac (USB drive or AirDrop).
2. Put a Release (universal) PhotoBooth Attract.app inside the App folder (the older PhotoBoothAttract.app name also works).
   The runner never modifies it. For app cases it launches a throwaway copy (own bundle identifier, ad-hoc
   re-signed with the system codesign) so preferences, window state and the log stay separate from yours.
3. Leave any running event session alone; the runner never quits or touches it. It stops only the copy it started.
4. Attach the TV as the second display for the dual-display cases (leave one display for the single-display case).
5. Double-click run-core-ui.command (or run it in Terminal). If macOS blocks it, use
   System Settings > Privacy & Security > "Open Anyway" yourself; the runner does not bypass Gatekeeper.
6. App cases need Accessibility for Terminal: System Settings > Privacy & Security > Accessibility.
   Without it those cases report SKIP and the run ends INCOMPLETE. Add --prompt-accessibility to show the system prompt.
7. The runner will stub printing and Messages. It never prints, opens Messages or touches your event folder or settings.
8. Send back reports/core-ui-*.txt plus any failure you saw on screen. The report contains model, OS and results only.
TXT

echo "==> Built $OUT"
lipo -archs "$OUT/CoreUIRunner"
