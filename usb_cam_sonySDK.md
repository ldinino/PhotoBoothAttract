---
name: Sony USB Camera SDK integration
overview: Integrate Sony Camera Remote SDK (USB-only) so PhotoBoothAttract can receive captured images directly from an attached Alpha camera, without relying on Imaging Edge Desktop. Keep the existing hot-folder watcher as a fallback and reuse the existing “Select Folder” as the SDK’s download destination.
todos:
  - id: milestone-a
    content: Add ObjC++ wrapper scaffolding; link/embed required Sony USB dylibs; ensure SDK Init/Release works at app startup/shutdown.
    status: completed
  - id: milestone-b
    content: Implement USB enumeration + connect/disconnect + connection state surfaced to SwiftUI.
    status: completed
  - id: milestone-c
    content: Implement SetSaveInfo to selected folder and OnCompleteDownload → ingest into PhotoManager/PhotoModel pipeline.
    status: completed
  - id: milestone-d
    content: Add View > Show Camera Preview command and a simple camera preview/status window (status + last received photo).
    status: cancelled
  - id: milestone-e
    content: "Harden behavior: reconnect, unplug, multi-camera selection (minimal), and user-facing error messages + setup doc."
    status: pending
isProject: false
---

## Goals

- Replace the external tether-app dependency (Imaging Edge Desktop Remote) with **direct USB ingest** via Sony Camera Remote SDK.
- **No camera setting changes** (trust camera); we only connect and receive image data/files.
- Reuse the existing **hot-folder ingestion UI + pipeline** by saving SDK downloads into the folder chosen by **Select Folder**.
- Add a lightweight, optional **Camera Preview** window reachable via **View > Show Camera Preview** (not required for core ingest).

## Current architecture to preserve

- **Photo ingestion today** is filesystem-based: `PhotoManager` watches a user-selected folder and calls `processNewFile(at:)` for `jpg/jpeg/png` once the file is fully written.

```214:254:/Volumes/Mass Sync/Dev/repos/Mac_Repos/PhotoBoothAttract/PhotoBoothAttract/PhotoManager.swift
    func processNewFile(at url: URL, retries: Int = 0) {
        // ...
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetStatus(source) == .statusComplete else {
            // retry
        }
        if let photo = PhotoModel(url: url) {
            DispatchQueue.main.async {
                if !self.photos.contains(where: { $0.url == url }) {
                    self.photos.append(photo)
                    self.photos.sort { $0.timestamp > $1.timestamp }
                }
            }
        }
        removeFromProcessing(url)
    }
```

## SDK facts from the repo (what we’ll integrate)

- The repo contains a working reference layout in `Camera_SDK/SimpleCli/` including:
  - C++ headers in `Camera_SDK/SimpleCli/app/CRSDK/` (e.g. `CameraRemote_SDK.h`, `IDeviceCallback.h`).
  - macOS universal dylibs under `Camera_SDK/SimpleCli/external/crsdk/`:
    - `libCr_Core.dylib`
    - `libmonitor_protocol.dylib`
    - `libmonitor_protocol_pf.dylib`
    - `CrAdapter/libCr_PTP_USB.dylib`
    - `CrAdapter/libusb-1.0.0.dylib`
- The SDK’s transfer path is callback-based: after capture and transfer, it calls `OnCompleteDownload(CrChar* filename, ...)`.

## Proposed design

### Data flow

- **Select Folder** remains the destination for camera downloads.
- When Sony USB mode is enabled:
  - App initializes SDK, enumerates USB cameras, connects, and sets SDK save location via `SetSaveInfo()`.
  - Camera captures (via physical shutter) are transferred by the SDK into the selected folder.
  - We ingest in one of two ways:
    - **Primary**: on `OnCompleteDownload`, call into Swift to ingest the file immediately (no race conditions).
    - **Secondary**: keep FSEvents watcher running for backfill/manual drops.

```mermaid
flowchart LR
  CameraUSB[Camera_USB] -->|SDK_transfer| SaveFolder[Selected_Folder]
  SDK[CameraRemoteSDK] -->|OnCompleteDownload(path)| AppIngest[Ingest_API]
  SaveFolder -->|FSEvents_backfill| PhotoManager[PhotoManager]
  AppIngest --> PhotoManager
  PhotoManager --> UI[GuestView_and_AssistantView]
```



### Bridging strategy (Swift ↔ C++ SDK)

- The SDK is C++ (namespaces, interfaces like `SCRSDK::IDeviceCallback`). Swift cannot call it directly.
- Implement a small **Objective-C++ wrapper** (`.mm`) that:
  - Includes SDK headers from `Camera_SDK/SimpleCli/app/CRSDK/`.
  - Owns the device handle and a C++ `IDeviceCallback` implementation.
  - Exposes an Objective-C class API callable from Swift (`start()`, `stop()`, `setSaveFolder(path)`, `connectFirstUSBCamera()`).
  - Emits events to Swift via a delegate/protocol or blocks: `onConnected`, `onDisconnected`, `onDownloadComplete(filePath)`, `onError(code)`.

### UI/UX

- Keep existing Assistant toolbar.
- Add a small “Camera” section (status + connect/disconnect) without touching camera settings.
- Add View-menu item **Show Camera Preview** that opens a separate window on the assistant side.
  - For v1, “Preview” can be mostly **status + last-downloaded thumbnail** (since live view is explicitly not important).
  - Later, we can optionally implement live view using `GetLiveViewImageInfo/GetLiveViewImage`.

## Build & packaging considerations

- Add the required dylibs to the app bundle under `Contents/Frameworks` and ensure `LD_RUNPATH_SEARCH_PATHS` already includes `@executable_path/../Frameworks` (it does in the project).
- Because we’re USB-only, we will **not** include the IP/SSH adapter dylibs.
- macOS quarantine: Sony docs mention removing quarantine attributes for SDK binaries; we’ll document that in the repo.
- Keep app non-sandboxed (already is) to allow writing to arbitrary selected folders.

## Safety constraints ("trust camera")

- We will **not** change exposure/drive/etc.
- We will not force `CrDeviceProperty_StillImageStoreDestination`.
- We will only:
  - Connect to the camera.
  - Set SDK save folder (`SetSaveInfo`) to the selected folder.
  - Receive downloads and ingest.
- If the camera is not configured to send images to PC, we surface a clear, minimal instruction (camera-side setting change is user responsibility).

## Implementation milestones

- **Milestone_A (plumbing + build)**: Add wrapper target/files, link dylibs, verify the app launches and can initialize/release SDK.
- **Milestone_B (USB connect)**: Enumerate cameras, connect first USB camera, show connection status.
- **Milestone_C (download → ingest)**: Set save folder to selected folder, handle `OnCompleteDownload`, ingest into `PhotoManager` (and optionally keep FSEvents as backstop).
- **Milestone_D (Preview window)**: Add View menu command and a new window showing live camera preview feed (full motion)
- **Milestone_E (resilience)**: Reconnect handling, unplug/replug behavior, multiple cameras (basic picker), error mapping to user-friendly messages.

## Key files likely to change/add

- Existing:
  - `/Volumes/Mass Sync/Dev/repos/Mac_Repos/PhotoBoothAttract/PhotoBoothAttract/PhotoManager.swift` (add a safe ingest entrypoint used by SDK callback, and/or reuse `processNewFile`)
  - `/Volumes/Mass Sync/Dev/repos/Mac_Repos/PhotoBoothAttract/PhotoBoothAttract/AssistantView.swift` (camera status + controls)
  - `/Volumes/Mass Sync/Dev/repos/Mac_Repos/PhotoBoothAttract/PhotoBoothAttract/AppDelegate.swift` or app bootstrap (lifecycle: init/release SDK)
  - `/Volumes/Mass Sync/Dev/repos/Mac_Repos/PhotoBoothAttract/PhotoBoothAttractApp.swift` (add View menu command)
  - `/Volumes/Mass Sync/Dev/repos/Mac_Repos/PhotoBoothAttract/PhotoBoothAttract.xcodeproj/project.pbxproj` (link/embed dylibs, bridging header if needed)
- New (proposed):
  - `PhotoBoothAttract/SonySDK/SonyCameraController.h` + `.mm` (ObjC++ wrapper)
  - `PhotoBoothAttract/SonySDK/SonyCameraManager.swift` (Swift-facing service + state)
  - `PhotoBoothAttract/CameraPreviewWindow.swift` (minimal preview/status window)
  - `PhotoBoothAttract/SonySDK/SonyCameraErrors.swift` (error mapping)
  - `docs/SONY_CAMERA_SDK.md` (setup + camera-side required settings)
