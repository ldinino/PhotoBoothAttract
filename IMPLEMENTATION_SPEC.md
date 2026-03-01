# PhotoBooth Attract — Implementation Spec

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

**Status:** ✅ Implemented. `MessageManager` uses **NSSharingService** (`composeMessage`) with optional recipient and image attachment. Images are optionally compressed (max 3000px, JPEG) before sharing. “Send without number” opens a draft with the image only; the assistant can then enter the number manually.

---

## Current Implementation Notes

| Area | Notes |
|------|--------|
| **Printer** | Configurable in **Settings** (PhotoBooth Attract → Settings…). Default display name is Canon Selphy CP1500; internal name may use underscores. |
| **Watched folder** | User chooses the Sony Image Desktop (or any) output folder via **Select Folder** in the Assistant view; path is persisted with a security-scoped bookmark. |
| **Error Log** | Help → **Error Log** (or ⌘⌥L) opens a window with timestamps and messages; clear and “Save to File” are available. |
| **Sort order** | Photos are always newest-first. A sort-order toggle is not yet implemented. |
| **Messages** | Uses `NSSharingService` rather than AppleScript; behavior matches “open draft with image (and optional number).” |

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
