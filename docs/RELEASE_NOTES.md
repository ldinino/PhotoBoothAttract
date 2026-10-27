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
