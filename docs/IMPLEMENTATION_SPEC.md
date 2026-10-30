# PhotoBooth Attract — Implementation Spec

> This document preserves the original requirements and implementation history.
> Historical "implemented" labels are not current verification. See [BUGS.md](BUGS.md)
> and [ENGINEERING_NOTES.md](ENGINEERING_NOTES.md) for the 2026-10-27 core review,
> and [ROADMAP.md](ROADMAP.md) for current sequencing. Requirements below are unchanged.

## Scenario

A photographer often does event coverage. After the event, she runs a **Photo Booth attraction**. The guest takes position and has their picture taken. An assistant works from an older 2012 MacBook Pro running macOS 15 Sequoia (e.g. with OpenCore Legacy Patcher). Performance is acceptable, but the GPU is on the weaker side.

The camera is connected to the Mac via **Sony Image Desktop**. When a picture is taken, image files are written directly to a folder, so no SD cards are needed.

A small **TV faces the guest**. On it, the app displays a **2×2 grid** of pictures labeled **1, 2, 3, and 4** (left to right, top to bottom). **1** is the newest image and **4** is the oldest. The guest says e.g. “I like number 2!” The assistant acknowledges and selects that image.

The guest can either:

- **Purchase a physical print** (e.g. 4×6 on a photo printer) **plus** a digital copy, or  
- **Get digital only**.

If the guest wants a print, the assistant selects the image. It is sent to a designated printer with a predefined print profile (4×6 photo; e.g. Canon Selphy CP1500). Once the print is queued, the image is composed in a new **iMessage draft**. The guest gives a phone number; the assistant enters it and sends. This relies on the Mac being tied to the photographer’s iPhone and using iCloud Messages and SMS/RCS forwarding for non‑iMessage recipients.

If the guest only wants a digital copy, the assistant uses a different action and skips printing, going straight to the iMessage draft flow.

---

## Technical Details and Function

### Two “realities”

- **Guest** sees only the TV with the grid. They call out a number and receive the picture shortly after.
- **Assistant** sees a **stream of photos** with a clear indication of which photo is 1–4 (like a camera roll with badges). When the guest says a number, the assistant knows exactly which image it is.

### UI and behavior

- **Toolbar** with clear actions: e.g. **Print + Send** and **Digital only** (and optionally **Print only**). Emoji or icons can illustrate these.
- **Photos** in reverse chronological order (newest first), with infinite scroll downward for the assistant.
- **Optional:** sort-order toggle (newest first vs oldest first) if feasible.
- **Guest grid** runs **full screen on the secondary display**.
- **Assistant view** runs **full screen on the primary display**.
- **Messages:** If possible, launch Messages full screen and use a side‑by‑side layout with the app for easier troubleshooting of mis-sends or failures.

---

## Implementation Phases

### Phase 1: Project Skeleton & Multi-Display Setup

- **Goal:** Establish app architecture (SwiftUI + AppKit where needed) and place windows on the correct screens.
- **Directive:** Act as a senior macOS developer. Build a non-sandboxed utility app in SwiftUI. Create a project skeleton that detects a secondary display on launch: open a **full-screen window on the secondary display** (Guest TV View) and a **standard window on the primary display** (Assistant View). Do not add photo logic yet; use colored rectangles or placeholders to verify window management.

**Status:** ✅ Implemented. `AppDelegate` creates Assistant window on primary screen and borderless full-screen Guest window on secondary (with fallback when no secondary display exists).

---

### Phase 2: The Hot Folder & Data Model

- **Goal:** Reliably detect new images and build the photo array.
- **Directive:** Implement a robust file watcher using **FSEvents** that monitors a specific local directory for new image files. Handle race conditions and only add a file path to an `@Published` array once the file is fully written. Provide a data model that stores file path, timestamp, and generates a low-memory downsampled thumbnail for the UI.

**Status:** ✅ Implemented. `PhotoManager` uses FSEvents, retries for incomplete writes, and maintains a processing set to avoid duplicates. `PhotoModel` holds URL, timestamp, and an 800px-max thumbnail via ImageIO.

---

### Phase 3: The User Interfaces

- **Goal:** Build Guest and Assistant views from the shared data model.
- **Guest directive:** Display exactly the **4 most recent** images in a **2×2 grid**. Label them **1** (newest) to **4** (oldest) with large, high-contrast overlays. When a 5th image arrives, the grid updates automatically.
- **Assistant directive:** Build a **reverse-chronological** scrolling list. The first four items must have **badge overlays (1, 2, 3, 4)** to match the Guest TV View. Include a toolbar on each row with: **🖨️+✉️** (Print & Digital) and **✉️** (Digital Only).

**Status:** ✅ Implemented. `GuestView` shows 2×2 grid with numbered cells; `AssistantView` shows scrollable list with 1–4 badges and row actions. Implementation also includes a **Print only** (🖨️) action for printing without opening the send sheet.

---

### Phase 4: Print Logic

- **Goal:** Silent print to the photo printer.
- **Directive:** Implement a printing utility that takes a local image file URL and sends it to a printer (default: **Canon Selphy CP1500**). Bypass the system print dialog. Configure `NSPrintInfo` for 4×6 photo paper with no margins.

**Status:** ✅ Implemented. `PrintManager` uses `NSPrintOperation` with no print panel, 4×6 paper, zero margins, and fit-to-page. Printer name is configurable (default `Canon_Selphy_CP1500`) via Settings.

---

### Phase 5: iMessage Automation

- **Goal:** Bridge the app to Messages for sending the image.
- **Directive:** Provide a function that takes a phone number and a local image file URL, then (e.g. via AppleScript or system APIs) opens the native macOS Messages app, creates a new chat with that number, and attaches the image to the draft so the user can hit send.

**Status:** ✅ Implemented. `MessageManager` uses **NSSharingService** (`composeMessage`) with optional recipient and image attachment. Images are compressed (max 3000px, no upscaling, JPEG, 1 MB target) before sharing. The copy keeps standard EXIF/TIFF, IPTC and XMP metadata (including Artist and Copyright) with orientation set to 1 and dimensions matching the output. A Settings toggle, saved with Save and on by default, removes GPS data; when stripping is on and a safe copy cannot be made, no photo is attached and an error is logged. Turning it off allows the original-byte fallback. “Send without number” opens a draft with the configured text (default thank-you message, or none if blank) and image; the assistant can then enter the number manually.

---

## Current Implementation Notes

| Area | Notes |
|------|--------|
| **Printer** | Configurable in **Settings** (PhotoBooth Attract → Settings…). Default display name is Canon Selphy CP1500; internal name may use underscores. |
| **Watched folder** | User chooses the Sony Image Desktop (or any) output folder via **Select Folder** in the Assistant view; path is persisted with a security-scoped bookmark. |
| **Error Log** | Help → **Error Log** (or ⌘⌥L) opens a window with timestamps and messages; clear and “Save to File” are available. |
| **Sort order** | Photos are always newest-first. A sort-order toggle is not yet implemented. |
| **Messages** | Uses `NSSharingService` rather than AppleScript; opens a draft with the configured text (default thank-you message, or none if blank) and image, optionally addressed to a phone number. |

---

## Acceptance Requirements

These requirements were moved from [ROADMAP.md](ROADMAP.md); moving them does not close
any acceptance checks. Verification and remaining equipment gaps belong in
[ENGINEERING_NOTES.md](ENGINEERING_NOTES.md) and [BUGS.md](BUGS.md).

### CORE Acceptance Gate

Before leaving CORE, all of the following must be met:

- Every core punchlist item meets its linked acceptance checks, with fixing commits or PRs
	and actual verification recorded in the engineering notes.
- Regression checks cover ordering, stable action selection, file replacement, incomplete
	writes, repeated events, folder changes and disappearing files. High-risk pure checks
	reject a deliberately wrong implementation.
- The actual Debug build passes. A real app launch confirms affected controls, empty/error
	states, partial/full grids and single-display fallback.
- Live hot-folder events, secondary-display lifecycle and older Intel Mac responsiveness
	have device evidence. Printer and Messages checks are recorded separately from build
	or simulated results; equipment blockers remain explicit.
- The native UI runner drives the agreed CORE flows with synthetic fixtures and isolated
	preferences, including pending cancellation and request-scoped sheet completion. It emits
	per-case PASS/FAIL/SKIP, a summary and a failing exit code for failures; skipped/manual
	checks are not passes. Use state-based waits, preserve event settings, restore permissions,
	remove fixtures and close only app instances launched by the runner. Run the final pass
	on the older Intel Mac with the TV and on Apple Silicon.
- Developer ID signing, notarization, stapling and downloaded-build Gatekeeper checks in
	[Notarized Distribution](#notarized-distribution) are complete.
- Preserve original images except an explicitly confirmed clear, silent configured-printer
	4x6 output, assistant-controlled sending, the current deployment target and non-sandboxed
	architecture. Physical printing and Messages consumption/delivery need separately authorized
	manual checks; no automatic sending or real printing as routine automation. Record only
	sanitized evidence and model/OS information, not identifiers or raw diagnostic exports.

Keep cleanup limited to touched core code: remove dead paths and misleading helpers without
an architecture rewrite or visual redesign. SDK features, dependency changes and unrelated
updater work are outside CORE acceptance. Mocks alone cannot close this gate.

### Notarized Distribution

Use the existing [release workflow](../scripts/build-release.sh). Confirm local access to a
Developer ID Application certificate. Sign the app and nested code, including required Sony
SDK libraries, with secure timestamps and compatible hardened-runtime settings; notarize
and staple the result. Verify signatures, universal arm64/x86_64 app and SDK slices, and
Gatekeeper behavior from a quarantined download on Intel and Apple Silicon.

Preserve the deployment target, non-sandboxed architecture and SDK licensing/distribution
assumptions. Keep certificates, private keys and notary credentials out of Git and chat.
These checks do not authorize certificate export, OS security bypasses, release tags or publishing.

### Messages Draft Text

Allow the assistant to customize the text prefilled alongside a photo without changing code.
Both addressed and recipient-free drafts use the same configured text. Messages remains an
editable system draft; the assistant controls sending. Opening a draft is not proof of
sending or delivery.

A global multiline plain-text setting in
[SettingsView.swift](../PhotoBoothAttract/SettingsView.swift), stored in `UserDefaults`,
loads when Settings opens and persists only through Save.
[MessageManager.swift](../PhotoBoothAttract/MessageManager.swift) reads it for every draft;
both paths share one text/item builder and changes need no restart. A missing or non-string
value uses `Thank you for choosing SD Photography. https://www.sd-photo.com/`.
Blank or whitespace-only text means photo only; other text is kept exactly. Already-open
drafts are unchanged. Templates, placeholders, per-customer data and a preview sheet are out of scope.

**Acceptance:** Verify persistence, default/blank behavior and identical text selection in
both draft paths with focused automated checks. Separately verify real drafts on Intel and
Apple Silicon contain the configured text and photo, with and without a recipient, and remain
editable without automatic sending. Use synthetic photos and placeholder recipients; do not
send messages or record guest data as routine validation.

### Messages Attachment Metadata

Preserve standard EXIF/TIFF, IPTC and XMP metadata, especially camera-set Artist/creator and
Copyright/rights fields, in the compressed photo handed to Messages. Apply to both addressed
and recipient-free drafts; keep originals untouched. Use ImageIO properties and metadata APIs;
vendor MakerNotes are not guaranteed to round-trip.

For re-encoded copies, bake orientation into downsampled pixels and normalize stored
orientation to 1. Update EXIF `PixelXDimension`, `PixelYDimension` and other stored dimensions
to the actual output size. Remove or regenerate the embedded EXIF preview; do not retain
conflicting orientation or dimension values in other metadata namespaces. Preserve the
3000 px longest-edge cap, no upscaling and existing JPEG quality policy. Include metadata
bytes in every quality-search and fallback encode. The 1 MB goal is a target, not a guaranteed maximum.

**GPS policy (working decision, open for maintainer override):** an assistant-only Messages
setting in [SettingsView.swift](../PhotoBoothAttract/SettingsView.swift), persisted by Save
under `messagesStripGPS`, defaults to removal. Missing or non-Boolean saved values strip GPS;
only an explicitly saved Boolean false retains it. Each attachment request reads the setting
once. Remove the GPS property dictionary and every GPS metadata tag, then read the result
back before use. If stripping is on and re-encoding fails or GPS remains, produce no attachment
and log an error. Original-byte fallback is allowed only with stripping off; an encode failure
must not bypass stripping or modify the original.

**Acceptance:** Use synthetic fixtures with known EXIF/TIFF, IPTC and XMP fields, rotated
orientation, an embedded preview and dummy GPS. Read attachments back with
`CGImageSourceCopyPropertiesAtIndex` and `CGImageSourceCopyMetadataAtIndex`; compare preserved
fields, orientation 1, actual versus stored dimensions, preview handling and both GPS modes.
Cover missing metadata, metadata-heavy files near the size target, encode failures and fallbacks
in both draft paths. Verify originals remain byte-for-byte unchanged.

On Intel and Apple Silicon, inspect real addressed and recipient-free drafts under both GPS
settings and compare sanitized exported fields with the source. Recipient-copy retention
through Messages or carriers needs separate, authorized delivery evidence; exported attachments
do not establish it. No automatic sending or guest data. Print/save metadata behavior is out of scope.

### SDK Entry Gate

CORE acceptance, including device qualification and notarized distribution, and acceptance of
both high-priority Messages features are required before SDK implementation. Messages features
do not close pending CORE items.

After those gates, re-audit current code and the locally installed Sony SDK with relevant camera
evidence. Only then create a separate SDK punchlist, choose repair versus rewrite and define
scope and acceptance checks. [usb_cam_sonySDK.md](usb_cam_sonySDK.md) is historical investigation;
library loading and USB discovery do not prove capture or file transfer.

Keep the hot-folder product working. Direct capture, automatic sending, SDK distribution changes
and new OS requirements require an explicit decision; old milestone labels do not define new scope.

---

## Prompt Directives (Reference)

The following can be reused for incremental or AI-assisted development:

1. **Phase 1:** *"Act as a senior macOS developer. We are building a non-sandboxed utility app in SwiftUI. Create a project skeleton that detects a secondary display on launch. It should open a full-screen window on the secondary display (the 'Guest TV View') and a standard window on the primary display (the 'Assistant View'). Do not add photo logic yet, just use colored rectangles to prove the window management works."*

2. **Phase 2:** *"Implement a robust file watcher class using FSEvents that monitors a specific local directory for new image files. It must account for race conditions and only add the file path to an @Published array once the file is completely written. Provide the data model that stores the file path, timestamp, and generates a low-memory downsampled thumbnail for UI use."*

3. **Phase 3 (Guest):** *"Using the data model from the previous step, build the Guest TV View. It must display exactly the 4 most recent images in a 2x2 grid. Number them 1 (newest) to 4 (oldest) using large, high-contrast text overlays. When a 5th image arrives, the grid must update automatically."*

4. **Phase 3 (Assistant):** *"Build the Assistant View. It should be a reverse-chronological scrolling list. The first 4 items in this list must have badge overlays (1, 2, 3, 4) to match the Guest TV View. Include a toolbar on each row with two buttons: '🖨️+✉️' (Print & Digital) and '✉️' (Digital Only)."*

5. **Phase 4:** *"Write a printing utility class for macOS. It must take a local image file URL and send it directly to a printer named exactly 'Canon Selphy CP1500'. It must bypass the system print dialog completely. Configure the NSPrintInfo for 4x6 photo paper with no margins."*

6. **Phase 5:** *"Write a utility function that takes a phone number string and a local file URL for an image. Execute an AppleScript from within the Swift code that opens the native macOS Messages app, creates a new chat with the provided phone number, and attaches the image file to the draft so it is ready for the user to hit send."*

*(Note: The app implements Phase 5 via NSSharingService instead of AppleScript; the directive above remains valid as an alternative approach.)*
