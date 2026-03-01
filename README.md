# PhotoBooth Attract

A macOS app for event photo-booth workflows: show the latest photos on a guest-facing TV, and let an assistant print and send images via iMessage from a second screen.

## Features

- **Dual-display setup** — Guest TV view (2×2 grid) on the secondary display; Assistant view (scrollable photo stream) on the primary display
- **Hot-folder watching** — Monitors a folder (e.g. Sony Image Desktop output) for new images with FSEvents; no SD cards needed
- **Numbered grid** — Guest sees the 4 most recent photos labeled 1–4 (1 = newest). Assistant sees the same numbers on the first four rows
- **Print** — Silent 4×6 photo printing to a configurable printer (default: Canon Selphy CP1500)
- **Send via iMessage** — Compose a message with the image and optional phone number; works with iCloud Messages and SMS/RCS forwarding
- **Print + Digital or Digital only** — Per-photo actions: Print & Send, Print only, or Digital only (iMessage draft)

## Requirements

- **macOS** (e.g. 15 Sequoia or later; tested on older hardware with OpenCore Legacy Patcher)
- **Two displays** — One for the assistant, one for the guest TV (app runs with one display but Guest TV view won’t open)
- **Camera workflow** — Camera tethered so new photos land in a single folder (e.g. Sony Image Desktop)
- **Printer** — 4×6-capable printer (e.g. Canon Selphy CP1500), configured in System Settings and in the app’s Settings
- **Messages** — Mac signed into iMessage (and optionally linked to iPhone for SMS/RCS) for sending digital copies

## Build and run

1. Open `PhotoBoothAttract.xcodeproj` in Xcode.
2. Select the **PhotoBoothAttract** scheme and a run destination (e.g. My Mac).
3. Build and run (⌘R).

The app is a **non-sandboxed** utility so it can access arbitrary folders and printers. No code signing is required for local use.

## Usage

1. **Select folder** — In the Assistant window, click **Select Folder** and choose the directory where your camera/tethering app writes photos (e.g. Sony Image Desktop). The choice is saved for next launch.
2. **Guest TV** — If a second display is connected, the Guest TV window opens there full screen with a 2×2 grid. New photos appear automatically; positions 1–4 are labeled.
3. **Assistant view** — On the primary display, photos appear in reverse chronological order. The first four rows show badges **1–4** matching the guest grid.
4. **Actions per photo:**
   - **🖨️+✉️ Print & Digital** — Queue print, then open iMessage draft with the image (enter phone number and send).
   - **🖨️ Print only** — Send to the configured printer only.
   - **✉️ Digital only** — Open iMessage draft with the image (no print).
5. **Phone number sheet** — For “Print & Digital” or “Digital only,” you can enter a phone number and send, or choose **Send without number** to open a draft and type the number in Messages.
6. **Error Log** — **Help → Error Log** (or ⌘⌥L) to view, clear, or export the app’s log to the Desktop for troubleshooting.

## Settings

**PhotoBooth Attract → Settings…**

- **Printer** — Pick the 4×6 photo printer from the list (or type the exact name). Default is Canon Selphy CP1500. Save to apply.

## Project layout

| File | Role |
|------|------|
| `PhotoBoothAttractApp.swift` | App entry, Settings and Error Log windows |
| `AppDelegate.swift` | Window lifecycle; Assistant + Guest windows on correct screens |
| `PhotoManager.swift` | FSEvents watcher, folder selection, photo array |
| `PhotoModel.swift` | Single photo (URL, timestamp, thumbnail) |
| `GuestView.swift` | 2×2 guest grid (secondary display) |
| `AssistantView.swift` | Assistant list, row actions, phone-number sheet |
| `PrintManager.swift` | Silent 4×6 print to configured printer |
| `MessageManager.swift` | iMessage draft via NSSharingService |
| `SettingsView.swift` | Printer configuration |
| `ErrorLog.swift` | Persistent circular log and Error Log window |

For phased implementation details and prompt directives, see **[IMPLEMENTATION_SPEC.md](IMPLEMENTATION_SPEC.md)**.

## License

See repository license file if present.
