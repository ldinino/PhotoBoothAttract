# Engineering Notes

Technical evidence and acceptance checks for [BUGS.md](BUGS.md).
Priorities and sequencing live in [ROADMAP.md](ROADMAP.md), not in release history.

## Review Baseline

- Date: 2026-10-27. Source: `main` at `1a7089b511994816e5d7011851ef8796887e05d8`.
- Scope: folder ingestion, photo identity, assistant actions, guest grid, printing and Messages handoffs. SDK internals and updater behavior were excluded.
- No application code was changed. A temporary harness compiled the real core Swift sources with a logging stub and synthetic images. Private access was enabled only for the harness.
- Basic newest-first ordering and duplicate-event suppression passed. Seven defect reproductions cover six punchlist entries; CORE-001 has two reproductions.
- The normal Debug build passed. Xcode emitted local CoreDevice/CoreSimulator version warnings, not application-source errors.
- Live FSEvents checks were blocked because the standalone harness did not receive events. This is not evidence that the app's watcher cannot receive events.
- The one-photo guest grid was rendered offscreen. The complete app was not launched for this review.
- Physical printing, Messages attachment consumption or delivery, dual-display placement, SDK transfer and older Intel hardware were not verified.
- Temporary harness source, executable, images and share copies were removed. There is no committed test target or harness from this review.

Source links below refer to the reviewed baseline. Recheck the owning code before implementing a fix.

## CORE-001: Folder Lifecycle

**Owner:** [PhotoManager.swift](../PhotoBoothAttract/PhotoManager.swift#L89),
including the retry path in [processNewFile](../PhotoBoothAttract/PhotoManager.swift#L214).

**Evidence:** The real `setWatchedFolder` path was exercised with two disposable folders.
Photos from the first remained after selecting the second. Separately, a missing image
was scheduled for retry, the folder was switched, and the old image was then completed;
its retry published into the new folder's photo list.

**Acceptance:** Selecting a folder shows only that folder's photos. Pending reads,
retries and publications from an earlier folder lifecycle cannot repopulate the list.
Cover switch, refresh and clear interactions, including completion after a switch.
New arrivals must not retarget an action already in progress.

**Status: closed.** Fixed in PR #1 (`3b315b2`); automated, build and maintainer-reported
live-app checks pass. Older Intel verification remains outstanding at the overall core acceptance gate.

**Fix** (PR #1, merged as `3b315b2`): `FolderLifecycle` in
PhotoManager.swift holds a generation counter and per-URL claims tagged with their generation.
Selection and refresh call `beginLifecycle()`, which stops the watcher, clears photos, resets
busy flags and bumps the generation. Scans, retries, FSEvents callbacks (generation stored per
stream), publications, claim release and refresh/clear completions all check their generation,
so A-B-A and same-folder refresh are covered. A clear also starts a new generation (and restarts
the watcher under it), so reads and retries begun before the clear cannot republish deleted photos.

**Baseline reproduction** (real `PhotoManager` at 48128dd, scratch harness): A->B kept A's photo;
a retry from A published into B; the old cleanup released the claim a refresh had just taken;
clear completion after a switch emptied B (400-file fixture to widen the race).

**Automated:** `bash scripts/check-folder-lifecycle.sh` compiles the real `PhotoManager` and
`PhotoModel` with a logging stub and synthetic images (never the app log or a live folder);
all checks pass (31). Mutants: `release` (URL-only release) fails 2 checks; `current` (staleness
never detected) fails 11; `clear` (clear keeps the old generation) fails 4. The first review pass
missed the clear race; the added checks replay a pre-clear read and a pre-clear pending retry
after the clear completes, using files outside the cleared folder so they survive the delete.

**Build:** the Debug `xcodebuild` command from the brief succeeded. A standalone launch with the
saved folder suppressed stayed up for 6 seconds without stderr output.

**Maintainer manual verification (2026-10-27):** all five requested smoke checks reported passing;
the repository was on merged `main` at `3b315b2`. These are maintainer-reported results, not
automated UI inspection.

1. Folder A-B-A and empty-folder selection show only the selected folder's photos.
2. Live hot-folder arrivals appear without Refresh, newest first, with matching assistant/guest numbers.
3. Switching to B while a photo is being copied into A does not publish A's photo into B.
4. Refresh finishes without duplicates; confirmed clear removes disposable photos without reappearance;
  a subsequent arrival appears normally.
5. Guest-TV display and disconnect/reconnect pass; the assistant remains usable, with no recipient
  entry or settings on the guest display.

**Remaining verification:** Mac model and macOS version were not supplied, so older Intel
performance/compatibility is not established by this report. Printing and Messages were not part
of these checks. The overall core acceptance gate remains open.

**Remaining gap:** after a clear, arrivals that land while deletion is in progress are removed from the list at completion even if their files remain (CORE-005 territory).

## CORE-002: Preview and Action Identity

**Owner:** [PhotoManager.swift](../PhotoBoothAttract/PhotoManager.swift#L244).

**Evidence:** Ingesting a synthetic image, replacing its bytes with a different image,
and processing its URL again retained the original thumbnail. The actions still use
that URL, which now contains different image data. URL-only deduplication hides the change.

**Acceptance:** A replacement cannot leave a selectable stale preview pointing at
different content. Duplicate notifications for unchanged files still produce one row.
Cover same-path replacement and actions opened before replacement or a new arrival.
Do not modify original images to achieve this.

**Baseline reproduction** (real `PhotoManager`/`PhotoModel` at daf701f, scratch harness): a red
synthetic PNG was ingested, overwritten with a blue one and re-notified. Result: one row, thumbnail
still red, file now blue.

**Design:** `PhotoModel` reads the file once and derives both the thumbnail and a SHA-256 digest
from those bytes, plus a per-manager `sequence`. `PhotoManager.publish` keeps one row per URL:
an older sequence is ignored, a newer read of the same digest only advances the row's sequence (identity kept), and a newer different revision replaces the row. An event
that arrives while its URL is claimed is remembered and the URL is re-read on release (previously
dropped). A replacement that never becomes a complete image removes that URL's row. Actions carry
the selected `PhotoModel`; `perform` reads the source once, checks the digest and hands the same
`Data` to print and share (`PrintManager`/`MessageManager` no longer reopen the URL). The read and
hash run on a background queue; the sinks then run on the main thread with those bytes. A changed or
missing file is rejected with an alert and nothing is printed or sent; the assistant reselects.
The selection is rejected rather than preserved, so no copy of the original needs ownership.

**Automated:** `bash scripts/check-folder-lifecycle.sh` now compiles the real `PhotoManager`,
`PhotoModel`, `PrintManager` and `MessageManager`, with stub print/share sinks. 55 checks pass,
including unchanged duplicates, in-place and atomic replacement, incomplete and never-completing
replacement, a disappearing file, out-of-order publication, red 10 / red 30 / delayed blue 20
(unchanged newer content keeps the watermark), a slow read that leaves the main run loop ticking
and outputs the selected snapshot on the main thread, replacement before the click, after opening
the sheet and during printing, a new arrival and a folder switch during the sheet, with decoded
image colour asserted. Mutants: `url` (URL-only identity) fails 7 checks; `stale` 4; `watermark` 2;
`mainread` (verify on main) 1; `release` 2, `current` 11, `clear` 4.

**Build:** the Debug `xcodebuild` command from the brief succeeded.

**UI (reported accessibility evidence, not visual inspection):** the real Debug app was launched
with a temporary home and a one-photo synthetic folder. One row and three controls were present.
After opening Digital Only and replacing the source, Send without number closed the sheet and
showed the "Photo not sent" alert; no new Messages draft opened and one row remained. Only that
instance was closed and its fixtures removed. This was run before the off-main change and has not
been repeated since.

**Not verified:** thumbnail colour in the real window, Print only and numbered Send in the UI, the
unchanged-success draft, physical printing, older Intel Macs (including the cost of reading and
hashing originals there). The overall core acceptance gate stays open. Tunable: retries unchanged
(5 x 0.5 s) before a never-completing replacement drops the row.

PR: see the pull request for this branch.

## CORE-003: Attachment File Collisions

**Owner:** [MessageManager.swift](../PhotoBoothAttract/MessageManager.swift#L101).

**Evidence:** Compressing two different images from separate folders with the same
basename returned the same temporary URL. The second compression changed the bytes at
the first URL. Actual Messages attachment timing was not tested.

**Acceptance:** Each share request owns a distinct attachment file, including requests
for repeated source filenames. Preparing a later draft cannot change an earlier
attachment. Clean up copies only after consumers no longer need them; never delete originals.

## CORE-004: Filesystem Event Coverage

**Owner:** [PhotoManager.swift](../PhotoBoothAttract/PhotoManager.swift#L293).

**Evidence:** The callback filters for creation or modification flags only. There is
no deletion reconciliation, and a rename-only arrival does not trigger ingestion.
Live removal and rename tests were attempted but blocked by standalone event delivery.

**Acceptance:** A completed image moved into the watched folder becomes visible.
Deleted or moved-out files stop being actionable. Repeated events remain idempotent.
Verify actual FSEvents with synthetic files; preserve incomplete-write handling.

## CORE-005: Clear-Folder Failure Reporting

**Owner:** [PhotoManager.swift](../PhotoBoothAttract/PhotoManager.swift#L142).

**Evidence:** A disposable folder was made readable but not writable before clearing.
Deletion failed, yet completion returned success with zero deletions and emptied the
photo array while the image remained on disk.

**Acceptance:** Report failed or partial clears accurately and reconcile surviving
files instead of hiding them. Cover empty folders, denied deletions and folder changes
during a clear. Destructive checks must use disposable fixtures, never an event folder.

## CORE-006: Initial Scan Blocks the UI

**Owner:** [PhotoManager.swift](../PhotoBoothAttract/PhotoManager.swift#L262),
called during folder selection and saved-folder restoration.

**Evidence:** Source inspection shows synchronous enumeration followed by per-file
image-source validation and thumbnail generation on the caller's UI thread. Performance
on the older event Mac was not measured.

**Acceptance:** Folder enumeration and decoding do not block UI interaction. Observable
state updates remain on the main actor. Check a populated synthetic folder, cancellation
or folder switching during load, and responsiveness on the older event Mac.

## CORE-007: Print and Digital Failure Handling

**Owner:** [AssistantView.swift](../PhotoBoothAttract/AssistantView.swift#L419),
with the same pattern in the no-number action. [PrintManager.swift](../PhotoBoothAttract/PrintManager.swift#L29)
already offers a completion result.

**Evidence:** Source inspection shows callers discard that result, open a Messages
draft and close the sheet regardless of print failure. No printer operation was run.

**Acceptance:** Surface a failed print instead of implying the combined action succeeded.
Preserve Print & Digital, Print only and Digital only as distinct actions. Use simulated
failure for automated checks; a queued job does not establish a physical print.

## CORE-008: Share Image Orientation

**Owner:** [MessageManager.swift](../PhotoBoothAttract/MessageManager.swift#L93).

**Evidence:** A small synthetic JPEG with EXIF orientation 6 was compressed. The output
kept the unrotated pixel dimensions instead of the transformed dimensions. Orientation
is currently applied only when generating a downscaled thumbnail above 3000 pixels.

**Acceptance:** Shared copies preserve visible orientation below, at and above the
downscaling threshold. Cover rotated and mirrored EXIF orientations. Originals stay unchanged.

## CORE-009: Partially Filled Guest Grid

**Owner:** [GuestView.swift](../PhotoBoothAttract/GuestView.swift#L62).

**Evidence:** Rendering the real guest view with one synthetic photo into an 800x600
image showed the tile centered, leaving the intended top-left cell location empty.

**Acceptance:** Reserve a stable 2x2 layout for zero through four photos. Photo 1 occupies
the top-left cell, followed by 2 top-right, 3 bottom-left and 4 bottom-right. Verify partial
grids and arrival of a fifth photo; assistant badges must identify the same images.

## Verification Conventions

Use the actual Xcode project and [build workflow](../scripts/build-run.sh).
For a build without launching, run from the repository root:

```bash
xcodebuild \
  -project PhotoBoothAttract.xcodeproj \
  -scheme PhotoBoothAttract \
  -configuration Debug \
  -derivedDataPath /tmp/PhotoBoothAttract-build-debug \
  ONLY_ACTIVE_ARCH=YES build
```

Use existing test facilities or lightweight isolated checks; do not assume a test target
exists. For changed high-risk ordering, selection or readiness logic, demonstrate that
regression coverage rejects a deliberately wrong pure implementation, then restore and rerun.
Do not perform negative checks against live printing, Messages or guest files.

Use synthetic images and placeholder recipients. Never commit photos, phone numbers,
bookmarks, personal folder data, diagnostic exports or SDK binaries. Ask before real
printing or sending. Record hardware gaps as unverified, not passing results.