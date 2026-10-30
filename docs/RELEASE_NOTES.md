# PhotoBooth Assistant v1.1.1

Published 2026-10-30, build 18, from `2cf5382`.
[Release and download](https://github.com/ldinino/PhotoBoothAttract/releases/tag/v1.1.1).

## What's New

- PhotoBooth Attract is now PhotoBooth Assistant. Bundle identity, saved settings and the
	update feed are unchanged; in-place updates may retain the older installed filename.
- More reliable hot-folder ingestion, stable action selection, nonblocking initial scans,
	accurate clear-folder results and fixed numbered guest-grid quadrants.
- Separate attachment files per Messages request, normalized photo orientation and
	Print & Digital failure handling that retains the request instead of opening a draft.
- Customizable Messages draft text and standard EXIF/TIFF, IPTC and XMP attribution in
	compressed attachments. GPS removal defaults to on; originals remain untouched. The
	1 MiB sizing goal is a target, not a guaranteed maximum.
- Cooperative camera mode defaults to leaving camera control to Imaging Edge Desktop or
	another tethering app. Native capture and transfer remain experimental and unqualified.
- Assistant placement targets the primary display at launch and every display refresh.

## Distribution

The universal macOS 15.7+ app and all five required SDK libraries contain arm64 and x86_64
slices. The app is Developer ID signed, Apple-notarized and stapled. Signature, ticket and
Gatekeeper assessment checks pass after ZIP extraction; a fresh GitHub download matches
the verified package checksum.

## Verification Limits

The maintainer approved release with remaining device checks deferred, not passed:
single-display placement, the fixed-build Intel placement recheck, camera reconnect,
unavailable-printer behavior, the remaining Messages text/GPS route matrix and first launch
from a quarantined download on both architectures. Received-copy metadata retention across
Messages/carriers is not guaranteed. Cooperative hot-folder operation remains the production workflow.

---

# PhotoBoothAttract v1.0.14

## What's New

### Auto-Updater
- Added **Check for Updates** under the Help menu
- Checks GitHub Releases for the latest version and offers one-click download & install
- Logs update events to the Error Log for diagnostics

### Message Drafts
- iMessage drafts now include a pre-filled thank-you note with the SD Photography website link alongside the guest's photo

### Error Log (hotfix)
- **Persistent log** — Log is now written to `~/Library/Application Support/PhotoBoothAttract/PhotoBoothAttract.log` and survives app restarts
- **1 MB circular buffer** — Log file is automatically trimmed so it never exceeds 1 MB; oldest entries are dropped when full
- **Export** — Replaced "Save to File…" with **Export**: copies the current log to the Desktop with a timestamped filename (e.g. `PhotoBoothAttract_ErrorLog_2025-03-01_14-30-00.txt`)
- **Less noise** — Removed routine success logs (e.g. "Print job sent", "Message shared successfully"); shortened update-check and printer-not-found messages so the log stays useful without verbosity
